package InfraFence::WHM::App;

# Controller for WHM » Plugins » InfraFence.
#
# It knows nothing about cPanel: it takes a request (method, params, security
# token, user), an Agent and an I18n object, and returns a response:
#   { code => 200, template => 'infrafence/main.tmpl', data => {...} }
#   { code => 303, location => 'index.cgi?...' }
#
# Changes follow two steps. A GET (or a POST without confirm=1) only shows a
# confirmation page. The change runs on a POST with confirm=1 and a csrf field
# that matches the WHM security token of the session.

use strict;
use warnings;

use InfraFence::WHM::Util qw(const_eq uri_escape);
use InfraFence::WHM::Validate qw(valid_ip valid_note valid_actor valid_docroot valid_choice);

our $VERSION = '0.1.0';

our $SITE_URL        = 'https://infrafence.com';
our $INSTALL_COMMAND = 'curl -fsSL https://get.infrafence.com | sh';

our @PAGES = qw(overview bans allowlist findings events coexistence sites);

# Where each action may be started from (the first one is the default) and
# what it acts on.
my %ACTIONS = (
    unban    => { pages => [qw(bans)],           target => 'ip' },
    allow    => { pages => [qw(allowlist bans)], target => 'ip' },
    disallow => { pages => [qw(allowlist)],      target => 'ip' },
    scan     => { pages => [qw(sites)],          target => 'path' },
);

my @BAN_LIMITS     = qw(500 100 1000);
my @FINDING_LIMITS = qw(200 500);
my @EVENT_LIMITS   = qw(100 50 250 500);
my @FINDING_KINDS  = qw(all malware integrity);

sub new {
    my ( $class, %args ) = @_;
    for (qw(agent i18n request)) {
        die "$_ required\n" unless $args{$_};
    }
    my $self = bless {%args}, $class;
    $self->{request}{params} ||= {};
    return $self;
}

sub run {
    my ($self) = @_;
    my $p    = $self->{request}{params} || {};
    my $page = valid_choice( $p->{page}, \@PAGES, 'overview' );
    my $data = $self->_base($page);

    return $self->_view( 'not_installed', $data ) unless $self->{agent}->installed;

    $data->{status} = $self->{agent}->call('status');

    if ( defined $p->{action} && length $p->{action} ) {
        return $self->_action( $p->{action}, $page, $data );
    }

    $self->_notice($data);
    return $self->_page( $page, $data );
}

sub _base {
    my ( $self, $page ) = @_;
    return {
        L               => $self->{i18n},
        page            => $page,
        pages           => [@PAGES],
        script          => 'index.cgi',
        csrf            => $self->{request}{token} || '',
        version         => $VERSION,
        site_url        => $SITE_URL,
        install_command => $INSTALL_COMMAND,
        errors          => [],
        sev_class       => {
            critical => 'danger',
            high     => 'danger',
            medium   => 'warning',
            low      => 'info',
            info     => 'default',
        },
    };
}

sub _view {
    my ( $self, $view, $data, $code ) = @_;
    $data->{view} = $view;
    return { code => $code || 200, template => 'infrafence/main.tmpl', data => $data };
}

sub _page {
    my ( $self, $page, $data, $code ) = @_;
    $data->{page} = $page;
    my $method = "_page_$page";
    $self->$method($data);
    return $self->_view( $page, $data, $code );
}

sub _error {
    my ( $data, $code, $message ) = @_;
    push @{ $data->{errors} }, { ok => 0, error => $code, message => defined $message ? $message : '' };
    return;
}

sub _running {
    my ($data) = @_;
    return $data->{status} && $data->{status}{ok} && $data->{status}{agent_running};
}

# ---------------------------------------------------------------- actions

sub _action {
    my ( $self, $name, $page, $data ) = @_;
    my $p = $self->{request}{params};

    my $spec = $ACTIONS{$name};
    unless ($spec) {
        _error( $data, 'bad_request' );
        return $self->_page( $page, $data, 400 );
    }
    $page = valid_choice( $page, $spec->{pages}, $spec->{pages}[0] );
    my %act = ( name => $name, page => $page );

    if ( $spec->{target} eq 'ip' ) {
        my $ip = valid_ip( $p->{ip} );
        unless ( defined $ip ) {
            _error( $data, 'invalid_ip' );
            return $self->_page( $page, $data, 400 );
        }
        $act{ip} = $ip;
        if ( $name eq 'allow' ) {
            my $note = valid_note( $p->{note} );
            unless ( defined $note ) {
                _error( $data, 'invalid_note' );
                $data->{form} = { ip => $ip };
                return $self->_page( $page, $data, 400 );
            }
            $act{note} = $note;
        }
    }
    else {
        my $sites = $self->{agent}->call('sites');
        unless ( $sites->{ok} ) {
            push @{ $data->{errors} }, $sites;
            return $self->_page( $page, $data );
        }
        my @list = grep { ref $_ eq 'HASH' } @{ $sites->{sites} || [] };
        my $path = valid_docroot( $p->{path}, [ map { $_->{docroot} } @list ] );
        unless ( defined $path ) {
            _error( $data, 'unknown_path' );
            return $self->_page( $page, $data, 400 );
        }
        $act{path} = $path;
        ( $act{site} ) = grep { defined $_->{docroot} && $_->{docroot} eq $path } @list;
    }
    $data->{act} = \%act;

    my $confirmed = defined $p->{confirm} && $p->{confirm} eq '1';
    return $self->_view( 'confirm', $data ) unless $confirmed && $self->_is_post;

    unless ( $self->_csrf_ok ) {
        _error( $data, 'csrf' );
        return $self->_view( 'confirm', $data, 403 );
    }
    my $actor = valid_actor( $self->{request}{actor} );
    unless ( defined $actor ) {
        _error( $data, 'bad_actor' );
        return $self->_view( 'confirm', $data, 403 );
    }

    my @args = $name eq 'scan' ? ( $act{path} ) : ( $act{ip} );
    push @args, '--note', $act{note} if $name eq 'allow' && length $act{note};
    push @args, '--actor', $actor;

    my $reply = $self->{agent}->call( $name, @args );
    if ( $reply->{ok} ) {
        my $target = $name eq 'scan' ? 'path=' . uri_escape( $act{path} ) : 'ip=' . uri_escape( $act{ip} );
        return { code => 303, location => "index.cgi?page=$page&notice=${name}_ok&$target" };
    }

    $reply->{action} = $name;
    push @{ $data->{errors} }, $reply;
    return $self->_page( $page, $data );
}

sub _is_post {
    my ($self) = @_;
    return uc( $self->{request}{method} || '' ) eq 'POST';
}

sub _csrf_ok {
    my ($self) = @_;
    my $req = $self->{request};
    return 0 unless $self->_is_post;

    my $token = $req->{token};
    return 0 unless defined $token && length $token >= 8;
    return 0 unless const_eq( $token, defined $req->{params}{csrf} ? $req->{params}{csrf} : '' );

    # When the browser says where the form came from, it must be this server.
    my $host = lc( $req->{host} || '' );
    for my $from ( $req->{origin}, $req->{referer} ) {
        next unless defined $from && length $from && $from ne 'null';
        my ($h) = $from =~ m{\Ahttps?://([^/?#]+)}i;
        return 0 unless defined $h && length $host && lc $h eq $host;
    }
    return 1;
}

sub _notice {
    my ( $self, $data ) = @_;
    my $p    = $self->{request}{params};
    my $code = valid_choice( $p->{notice}, [qw(unban_ok allow_ok disallow_ok scan_ok)], undef );
    return unless $code;
    my %n = ( code => $code );
    if ( $code eq 'scan_ok' ) {
        my $path = $p->{path};
        return unless defined $path && $path =~ m{\A/[^\x00-\x1f\x7f]{0,4095}\z};
        $n{path} = $path;
    }
    else {
        $n{ip} = valid_ip( $p->{ip} );
        return unless defined $n{ip};
    }
    $data->{notice} = \%n;
}

# ---------------------------------------------------------------- pages

sub _list {
    my ( $self, $data, $reply, $field ) = @_;
    if ( $reply->{ok} ) {
        my $list = $reply->{$field};
        return [ grep { ref $_ eq 'HASH' } ( ref $list eq 'ARRAY' ? @$list : () ) ];
    }
    $data->{list_error} = $reply;
    return [];
}

sub _page_overview {
    my ( $self, $data ) = @_;
    my $s = $data->{status};
    return unless $s->{ok};

    $data->{protection} =
        !$s->{agent_running} ? 'stopped'
      : !$s->{connected}     ? 'offline'
      :                        'protected';

    return unless _running($data);
    my $agent = $self->{agent};
    my %c;

    my $bans = $agent->call( 'bans', '--limit', '1000' );
    if ( $bans->{ok} ) {
        $c{bans} = defined $bans->{total} ? $bans->{total} : scalar @{ $bans->{bans} || [] };
    }

    my $findings = $agent->call( 'findings', '--limit', '500' );
    if ( $findings->{ok} ) {
        $c{findings} = scalar grep { ref $_ eq 'HASH' && ( $_->{status} || '' ) eq 'open' } @{ $findings->{findings} || [] };
    }

    my $events = $agent->call( 'events', '--limit', '500' );
    if ( $events->{ok} ) {
        my $L   = $self->{i18n};
        my @all = grep { ref $_ eq 'HASH' } @{ $events->{events} || [] };
        $c{events}      = scalar grep { my $a = $L->age( $_->{time} ); defined $a && $a <= 86400 } @all;
        $c{events_more} = @all >= 500 ? 1 : 0;
    }
    $data->{counts} = \%c;
}

sub _page_bans {
    my ( $self, $data ) = @_;
    my $limit = valid_choice( $self->{request}{params}{limit}, \@BAN_LIMITS, $BAN_LIMITS[0] );
    $data->{limit}  = $limit;
    $data->{limits} = [ sort { $a <=> $b } @BAN_LIMITS ];
    my $reply = $self->{agent}->call( 'bans', '--limit', $limit );
    $data->{bans}  = $self->_list( $data, $reply, 'bans' );
    $data->{total} = $reply->{ok} && defined $reply->{total} ? $reply->{total} : scalar @{ $data->{bans} };
}

sub _page_allowlist {
    my ( $self, $data ) = @_;
    my $reply = $self->{agent}->call('allowlist');
    $data->{entries} = $self->_list( $data, $reply, 'entries' );
    $data->{form} ||= {};
    my $ip = valid_ip( $self->{request}{params}{ip} );
    $data->{form}{ip} = $ip if defined $ip && !defined $data->{form}{ip};
}

sub _page_findings {
    my ( $self, $data ) = @_;
    my $p     = $self->{request}{params};
    my $limit = valid_choice( $p->{limit}, \@FINDING_LIMITS, $FINDING_LIMITS[0] );
    my $kind  = valid_choice( $p->{kind}, \@FINDING_KINDS, 'all' );
    $data->{limit} = $limit;
    $data->{kind}  = $kind;
    $data->{kinds} = [@FINDING_KINDS];

    my $all = $self->_list( $data, $self->{agent}->call( 'findings', '--limit', $limit ), 'findings' );
    my %count = ( all => scalar @$all );
    $count{ $_->{kind} || '' }++ for @$all;
    $data->{kind_count} = \%count;
    $data->{findings}   = $kind eq 'all' ? $all : [ grep { ( $_->{kind} || '' ) eq $kind } @$all ];
}

sub _page_events {
    my ( $self, $data ) = @_;
    my $limit = valid_choice( $self->{request}{params}{limit}, \@EVENT_LIMITS, $EVENT_LIMITS[0] );
    $data->{limit}  = $limit;
    $data->{limits} = [ sort { $a <=> $b } @EVENT_LIMITS ];
    $data->{events} = $self->_list( $data, $self->{agent}->call( 'events', '--limit', $limit ), 'events' );
}

sub _page_coexistence {
    my ( $self, $data ) = @_;
    my $reply = $self->{agent}->call('coexistence');
    my $tools = $self->_list( $data, $reply, 'tools' );
    return unless $reply->{ok};
    $data->{mode}        = $reply->{mode};
    $data->{detected}    = [ grep { $_->{detected} } @$tools ];
    $data->{not_found}   = [ grep { !$_->{detected} } @$tools ];
    $data->{modsecurity} = ref $reply->{modsecurity} eq 'HASH' ? $reply->{modsecurity} : undef;
}

sub _page_sites {
    my ( $self, $data ) = @_;
    my $sites = $self->_list( $data, $self->{agent}->call('sites'), 'sites' );
    my ( %by, @order );
    for my $s (@$sites) {
        my $acct = defined $s->{account} ? $s->{account} : '';
        push @order, $acct unless $by{$acct};
        push @{ $by{$acct} }, $s;
    }
    my %cov;
    $cov{ $_->{coverage} || 'none' }++ for @$sites;
    $data->{accounts} = [ map { { account => $_, owner => $by{$_}[0]{owner}, sites => $by{$_} } } sort @order ];
    $data->{coverage_count} = \%cov;
    $data->{site_count}     = scalar @$sites;
}

1;
