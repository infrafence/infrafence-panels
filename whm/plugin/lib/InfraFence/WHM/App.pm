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
#
# The agent's replies are described in docs/panel-json.md.

use strict;
use warnings;

use Time::HiRes ();

use InfraFence::WHM::I18n  ();
use InfraFence::WHM::Map   ();
use InfraFence::WHM::Prefs ();
use InfraFence::WHM::Score ();
use InfraFence::WHM::Util qw(const_eq uri_escape);
use InfraFence::WHM::Validate qw(valid_ip valid_note valid_actor valid_docroot valid_choice valid_https_url);

our $VERSION = '0.1.0';

our $SITE_URL       = 'https://infrafence.com';
our $ADD_SERVER_URL = 'https://infrafence.com/add-server';

our @PAGES = qw(overview bans allowlist findings events coexistence sites);

# Seconds for all the agent calls of the Overview together (it makes six, seven
# with the 7-day map).
our $OVERVIEW_DEADLINE = 25;

# The Overview's "needs attention" list: events of these severities in the
# last 24 hours, the most severe first, then the newest.
use constant ATTENTION_MAX => 10;
my %SEV_RANK = ( critical => 4, high => 3, warning => 2, medium => 2, low => 1, info => 0 );

# The Events page's severity filter: the lowest severity rank shown.
my %SEV_FILTER = ( all => 0, warning => 2, critical => 3 );
my @SEV_FILTERS = qw(all warning critical);

# Where each action may be started from (the first one is the default) and
# what it acts on.
my %ACTIONS = (
    unban    => { pages => [qw(bans)],           target => 'ip' },
    allow    => { pages => [qw(allowlist bans)], target => 'ip' },
    disallow => { pages => [qw(allowlist)],      target => 'ip' },
    scan     => { pages => [qw(sites)],          target => 'path' },
);

# The agent accepts --limit 1-500.
my @BAN_LIMITS     = qw(500 100 250);
my @FINDING_LIMITS = qw(200 500);
my @EVENT_LIMITS   = qw(100 50 250 500);
my @FINDING_KINDS  = qw(all malware integrity);
my @BAN_SOURCES    = qw(local network automode manual);

# The agent lifts a ban on this server until the ban expires, at most 30 days.
use constant MAX_LIFT => 30 * 86400;

# Product names, not translated.
my %PANEL_NAMES = (
    cpanel      => 'cPanel & WHM',
    plesk       => 'Plesk',
    directadmin => 'DirectAdmin',
    cyberpanel  => 'CyberPanel',
    hestiacp    => 'HestiaCP',
    vestacp     => 'VestaCP',
    ispconfig   => 'ISPConfig',
    cloudpanel  => 'CloudPanel',
    cwp         => 'CWP',
    aapanel     => 'aaPanel',
    keyhelp     => 'KeyHelp',
    froxlor     => 'Froxlor',
    enhance     => 'Enhance',
    virtualmin  => 'Virtualmin',
    webmin      => 'Webmin',
    coolify     => 'Coolify',
    dokploy     => 'Dokploy',
    easypanel   => 'Easypanel',
    caprover    => 'CapRover',
    runcloud    => 'RunCloud',
    gridpane    => 'GridPane',
    forge       => 'Laravel Forge',
    ploi        => 'Ploi',
    bitnami     => 'Bitnami',
);

# Options besides agent, i18n and request:
#   prefs     an InfraFence::WHM::Prefs (the user's language choice)
#   whm_lang  the WHM user's own language (en, it...), for "Same as WHM"
#   map_dir   where world.json and countries.json are
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
    my $p    = $self->{request}{params};
    my $page = valid_choice( $p->{page}, \@PAGES, 'overview' );
    my $data = $self->_base($page);

    # The language can be changed on every page, with or without the agent.
    if ( defined $p->{action} && $p->{action} eq 'language' ) {
        return $self->_set_language( $page, $data );
    }

    return $self->_view( 'not_installed', $data ) unless $self->{agent}->installed;

    my $agent    = $self->{agent};
    my $overview = $page eq 'overview' && !( defined $p->{action} && length $p->{action} );
    $agent->deadline( Time::HiRes::time() + $OVERVIEW_DEADLINE ) if $overview && $agent->can('deadline');

    $data->{status} = $agent->call('status');

    if ( defined $p->{action} && length $p->{action} ) {
        return $self->_action( $p->{action}, $page, $data );
    }

    $self->_notice($data);
    my $res = $self->_page( $page, $data );
    $agent->deadline(undef) if $overview && $agent->can('deadline');
    return $res;
}

sub _base {
    my ( $self, $page ) = @_;
    return {
        L              => $self->{i18n},
        page           => $page,
        pages          => [@PAGES],
        script         => 'index.cgi',
        csrf           => $self->{request}{token} || '',
        version        => $VERSION,
        site_url       => $SITE_URL,
        add_server_url => $ADD_SERVER_URL,
        panel_names    => \%PANEL_NAMES,
        languages      => [ map { { code => $_->[0], name => $_->[1] } } @InfraFence::WHM::Prefs::LANGUAGES ],
        lang_choice    => $self->_lang_choice,
        whm_lang_name  => _lang_name( InfraFence::WHM::I18n::normalize( $self->{whm_lang} ) ),
        errors         => [],
        sev_class      => {
            critical => 'danger',
            high     => 'danger',
            medium   => 'warning',
            warning  => 'warning',
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

# ---------------------------------------------------------------- language

# The language's own name, for one of the plugin's languages (en, it... pt).
sub _lang_name {
    my ($lang) = @_;
    for (@InfraFence::WHM::Prefs::LANGUAGES) {
        return $_->[1] if InfraFence::WHM::I18n::normalize( $_->[0] ) eq $lang;
    }
    return 'English';
}

# The stored choice ('it', 'pt-BR'...), or 'whm' when the plugin follows WHM.
sub _lang_choice {
    my ($self) = @_;
    my $prefs = $self->{prefs} or return 'whm';
    my $lang  = $prefs->lang( $self->{request}{actor} );
    return defined $lang ? $lang : 'whm';
}

# POST action=language lang=<code>|whm csrf=<token>: stores the WHM user's
# choice and goes back to the page. No confirmation step: it changes only how
# the plugin reads for this user.
sub _set_language {
    my ( $self, $page, $data ) = @_;
    my $p = $self->{request}{params};
    unless ( $self->_csrf_ok ) {
        _error( $data, 'csrf' );
        return $self->_view( 'language', $data, 403 );
    }
    my $actor = valid_actor( $self->{request}{actor} );
    unless ( defined $actor ) {
        _error( $data, 'invalid_actor' );
        return $self->_view( 'language', $data, 403 );
    }
    my $want = defined $p->{lang} && $p->{lang} eq 'whm' ? undef : InfraFence::WHM::Prefs::valid_lang( $p->{lang} );
    unless ( defined $want || ( defined $p->{lang} && $p->{lang} eq 'whm' ) ) {
        _error( $data, 'invalid_language' );
        return $self->_view( 'language', $data, 400 );
    }
    unless ( $self->{prefs} && $self->{prefs}->set_lang( $actor, $want ) ) {
        _error( $data, 'prefs_failed' );
        return $self->_view( 'language', $data, 500 );
    }
    return { code => 303, location => "index.cgi?page=$page" };
}

# ---------------------------------------------------------------- actions

sub _action {
    my ( $self, $name, $page, $data ) = @_;
    my $p = $self->{request}{params};

    my $spec = $ACTIONS{$name};
    unless ($spec) {
        _error( $data, 'unknown_action' );
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
        my @list = grep { ref $_ eq 'HASH' } @{ ref $sites->{sites} eq 'ARRAY' ? $sites->{sites} : [] };
        my $path = valid_docroot( $p->{path}, [ map { $_->{document_root} } @list ] );
        unless ( defined $path ) {
            _error( $data, 'not_a_document_root' );
            return $self->_page( $page, $data, 400 );
        }
        my @here = grep { defined $_->{document_root} && $_->{document_root} eq $path } @list;
        # The agent says in advance which document roots it will accept.
        unless ( grep { $_->{scannable} } @here ) {
            _error( $data, 'not_scannable' );
            return $self->_page( $page, $data, 400 );
        }
        $act{path}        = $path;
        $act{domains}     = [ map { $_->{domain} } @here ];
        ( $act{account} ) = map { $_->{account} } @here;
    }
    $data->{act} = \%act;

    my $confirmed = defined $p->{confirm} && $p->{confirm} eq '1';
    unless ( $confirmed && $self->_is_post ) {
        $self->_describe_ban( \%act ) if $name eq 'unban';
        return $self->_view( 'confirm', $data );
    }

    unless ( $self->_csrf_ok ) {
        _error( $data, 'csrf' );
        return $self->_view( 'confirm', $data, 403 );
    }
    my $actor = valid_actor( $self->{request}{actor} );
    unless ( defined $actor ) {
        _error( $data, 'invalid_actor' );
        return $self->_view( 'confirm', $data, 403 );
    }

    my @args = $name eq 'scan' ? ( $act{path} ) : ( $act{ip} );
    push @args, '--note', $act{note} if $name eq 'allow' && length $act{note};
    push @args, '--actor', $actor;

    my $reply = $self->{agent}->call( $name, @args );
    if ( $reply->{ok} ) {
        return { code => 303, location => "index.cgi?page=$page&" . _notice_query( $name, \%act, $reply ) };
    }

    $reply->{action} = $name;
    push @{ $data->{errors} }, $reply;
    return $self->_page( $page, $data );
}

# What the success message needs from the agent's reply, as query parameters.
sub _notice_query {
    my ( $name, $act, $r ) = @_;
    my $code = $name eq 'allow' && $r->{already} ? 'allow_already' : "${name}_ok";
    my @q = ("notice=$code");
    if ( $name ne 'scan' ) {
        my $ip = valid_ip( $r->{ip} );
        push @q, 'ip=' . uri_escape( defined $ip ? $ip : $act->{ip} );
    }
    push @q, 'until=' . uri_escape( $r->{lifted_until} ) if _iso( $r->{lifted_until} );
    push @q, 'own=1'        if $r->{own_address};
    push @q, "source=$r->{source}" if defined valid_choice( $r->{source}, [@BAN_SOURCES], undef );
    push @q, 'unreported=1' if exists $r->{reported} && !$r->{reported};
    push @q, 'threat_feed=1' if $r->{threat_feed};
    push @q, 'pending=1'     if $r->{firewall_pending};
    push @q, 'banned=1'      if $r->{banned};
    return join '&', @q;
}

# For the confirmation page: the ban's source and when the lift will end, by
# the agent's rule (the ban's expiry, or 30 days from now, whichever is first).
sub _describe_ban {
    my ( $self, $act ) = @_;
    my $reply = $self->{agent}->call( 'bans', '--limit', '500' );
    return unless $reply->{ok};
    my ($ban) = grep { ref $_ eq 'HASH' && defined $_->{ip} && ( valid_ip( $_->{ip} ) || '' ) eq $act->{ip} } @{ $reply->{bans} || [] };
    return unless $ban;
    $act->{source} = valid_choice( $ban->{source}, [@BAN_SOURCES], undef );
    my $L       = $self->{i18n};
    my $cap     = $L->_now + MAX_LIFT;
    my $expires = $L->epoch( $ban->{expires} );
    my $until   = defined $expires && $expires < $cap ? $expires : $cap;
    my @g       = gmtime $until;
    $act->{until} = sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ', $g[5] + 1900, $g[4] + 1, @g[ 3, 2, 1, 0 ];
}

sub _iso {
    my ($s) = @_;
    return defined $s && $s =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d{1,9})?)?(?:Z|[+-]\d\d:?\d\d)\z/;
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

    # When the browser says where the form came from, it must be this server. cpsrvd passes
    # HTTP_HOST without the port (emma.example.com, while the browser says :2087), so the names
    # must match and the ports only when cpsrvd gives one; without one, the form must come from
    # WHM's own ports (2087, 2086) or the default port of a whm.* proxy subdomain.
    my ( $host, $port ) = _host_port( $req->{host} );
    for my $from ( $req->{origin}, $req->{referer} ) {
        next unless defined $from && length $from && $from ne 'null';
        my ($h) = $from =~ m{\Ahttps?://([^/?#]+)}i;
        my ( $from_host, $from_port ) = _host_port($h);
        return 0 unless length $host && length $from_host && $from_host eq $host;
        if ( length $port ) {
            return 0 unless ( length $from_port ? $from_port : '' ) eq $port;
        }
        else {
            return 0 unless !length $from_port || $from_port eq '2087' || $from_port eq '2086';
        }
    }
    return 1;
}

# 'Host.Example:2087' -> ('host.example', '2087'); '[2001:db8::1]:2087' keeps the brackets.
sub _host_port {
    my ($hp) = @_;
    return ( '', '' ) unless defined $hp && length $hp;
    my ( $h, $p ) = lc($hp) =~ m{\A(\[[0-9a-f:.]+\]|[^:\[\]]+)(?::(\d{1,5}))?\z};
    return ( '', '' ) unless defined $h;
    return ( $h, defined $p ? $p : '' );
}

sub _notice {
    my ( $self, $data ) = @_;
    my $p    = $self->{request}{params};
    my $code = valid_choice( $p->{notice}, [qw(unban_ok allow_ok allow_already disallow_ok scan_ok)], undef );
    return unless $code;
    # A notice is one of the fixed messages above. The values filled into it
    # are re-derived, never echoed: the address is re-parsed and printed in
    # canonical form, the date is re-formatted, the source is one of a list,
    # flags are on/off. No free text from the query string is shown.
    my %n = ( code => $code );
    if ( $code ne 'scan_ok' ) {
        $n{ip} = valid_ip( $p->{ip} );
        return unless defined $n{ip};
    }
    $n{source} = valid_choice( $p->{source}, [@BAN_SOURCES], undef );
    delete $n{source} unless defined $n{source};
    for (qw(unreported threat_feed pending banned own)) {
        $n{$_} = 1 if defined $p->{$_} && $p->{$_} eq '1';
    }
    $n{until} = $p->{until} if _iso( $p->{until} );
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

# AutoMode is passed through from the dashboard as an object whose fields are
# not fixed yet. Show on/off when it says so, otherwise its state as sent.
sub _automode {
    my ($am) = @_;
    return undef unless ref $am eq 'HASH';
    return $am->{enabled} ? 'on' : 'off' if exists $am->{enabled} && !ref $am->{enabled};
    for my $k (qw(state mode status)) {
        return $am->{$k} if defined $am->{$k} && !ref $am->{$k} && length $am->{$k};
    }
    return 'unknown';
}

sub _page_overview {
    my ( $self, $data ) = @_;
    my $s = $data->{status};
    return unless $s->{ok};

    $data->{protection} =
        !$s->{agent_running}  ? 'stopped'
      : $s->{suspended}       ? 'suspended'
      : !$s->{connected}      ? 'offline'
      : $s->{monitor_mode}    ? 'monitor'
      :                         'protected';
    $data->{automode}      = _automode( $s->{automode} );
    $data->{dashboard_url} = valid_https_url( $s->{dashboard_url} );

    my $range = valid_choice( $self->{request}{params}{range}, [ map { $_->[0] } @InfraFence::WHM::Map::RANGES ], '24h' );
    $data->{range} = $range;

    return unless _running($data);
    my $agent = $self->{agent};
    my $L     = $self->{i18n};
    my %c;

    my $bans = $agent->call( 'bans', '--limit', '1' );
    $c{bans} = $bans->{total} if $bans->{ok};

    my $findings = $agent->call( 'findings', '--limit', '500' );
    if ( $findings->{ok} ) {
        $c{findings} = scalar grep { ref $_ eq 'HASH' && ( $_->{status} || '' ) eq 'detected' } @{ $findings->{findings} || [] };
    }

    my $events = $agent->call( 'events', '--since', '24h', '--limit', '500' );
    if ( $events->{ok} ) {
        my @ev = grep { ref $_ eq 'HASH' } @{ ref $events->{events} eq 'ARRAY' ? $events->{events} : [] };
        $c{events}      = scalar @ev;
        $c{events_more} = @ev >= 500 ? 1 : 0;
        $data->{attention} = _attention( \@ev, $L );
        $c{critical} = $data->{attention}{critical};
        $c{warning}  = $data->{attention}{warning};
    }
    $data->{counts} = \%c;

    my $map = $agent->call( 'map', '--hours', InfraFence::WHM::Map::range_hours($range) );
    $data->{map} = InfraFence::WHM::Map::view( reply => $map, lang => $L->lang, dir => $self->{map_dir}, range => $range );
    # The key figure is always the last 24 hours, whatever window the map shows.
    if ( $range eq '24h' ) {
        $c{attacks} = $data->{map}{total} if defined $data->{map}{total};
    }
    else {
        my $day = InfraFence::WHM::Map::view( reply => $agent->call( 'map', '--hours', 24 ), lang => $L->lang, dir => $self->{map_dir}, range => '24h' );
        $c{attacks} = $day->{total} if defined $day->{total};
    }

    my $score = $agent->call('score');
    $data->{score} = InfraFence::WHM::Score::view( reply => $score, number => sub { $L->number( $_[0] ) } );

    $data->{verdict} =
        $c{critical}                    ? { tone => 'critical', key => 'critical', n => $c{critical} }
      : $c{findings}                    ? { tone => 'critical', key => 'findings', n => $c{findings} }
      : $c{warning}                     ? { tone => 'warning',  key => 'warning',  n => $c{warning} }
      : $data->{protection} ne 'protected' ? { tone => 'warning', key => 'state' }
      :                                   { tone => 'ok', key => 'ok' };
}

# Critical and warning events of the last 24 hours, the most severe first,
# then the newest; at most ATTENTION_MAX, with the count of each level.
sub _attention {
    my ( $events, $L ) = @_;
    my ( %n, @list );
    for my $e (@$events) {
        my $sev  = defined $e->{severity} && !ref $e->{severity} ? $e->{severity} : '';
        my $rank = $SEV_RANK{$sev} || 0;
        next unless $rank >= $SEV_FILTER{warning};
        my $level = $rank >= $SEV_FILTER{critical} ? 'critical' : 'warning';
        $n{$level}++;
        push @list, { %$e, level => $level, rank => $level eq q{critical} ? 1 : 0, ip => valid_ip( $e->{source_ip} ) };
    }
    @list = map { $_->[1] }
      sort { $b->[1]{rank} <=> $a->[1]{rank} || $b->[0] <=> $a->[0] }
      map { [ $L->epoch( $_->{time} ) || 0, $_ ] } @list;
    splice @list, ATTENTION_MAX if @list > ATTENTION_MAX;
    return { events => \@list, critical => $n{critical} || 0, warning => $n{warning} || 0,
             filter => $n{critical} ? 'critical' : 'warning' };
}

sub _page_bans {
    my ( $self, $data ) = @_;
    my $limit = valid_choice( $self->{request}{params}{limit}, \@BAN_LIMITS, $BAN_LIMITS[0] );
    $data->{limit}  = $limit;
    $data->{limits} = [ sort { $a <=> $b } @BAN_LIMITS ];
    my $reply = $self->{agent}->call( 'bans', '--limit', $limit );
    $data->{bans}         = $self->_list( $data, $reply, 'bans' );
    $data->{total}        = $reply->{ok} && defined $reply->{total} ? $reply->{total} : scalar @{ $data->{bans} };
    $data->{monitor_mode} = $reply->{ok} && $reply->{monitor_mode} ? 1 : 0;
}

sub _page_allowlist {
    my ( $self, $data ) = @_;
    my $reply = $self->{agent}->call('allowlist');
    $data->{entries} = $self->_list( $data, $reply, 'allowlist' );
    $data->{form} ||= {};
    # Pre-fill the form from ?ip=, but not with the address a notice or a
    # failed action is about.
    return if $data->{notice} || $self->{request}{params}{action};
    my $ip = valid_ip( $self->{request}{params}{ip} );
    $data->{form}{ip} = $ip if defined $ip && !defined $data->{form}{ip};
}

sub _page_findings {
    my ( $self, $data ) = @_;
    my $p     = $self->{request}{params};
    my $limit = valid_choice( $p->{limit}, \@FINDING_LIMITS, $FINDING_LIMITS[0] );
    my $kind  = valid_choice( $p->{kind}, \@FINDING_KINDS, 'all' );
    $data->{limit}  = $limit;
    $data->{limits} = [ sort { $a <=> $b } @FINDING_LIMITS ];
    $data->{kind}   = $kind;
    $data->{kinds}  = [@FINDING_KINDS];

    my $reply = $self->{agent}->call( 'findings', '--limit', $limit );
    my $all   = $self->_list( $data, $reply, 'findings' );
    my %count = ( all => scalar @$all );
    $count{ $_->{kind} || '' }++ for @$all;
    $data->{kind_count} = \%count;
    $data->{total}      = $reply->{ok} && defined $reply->{total} ? $reply->{total} : scalar @$all;
    $data->{findings}   = $kind eq 'all' ? $all : [ grep { ( $_->{kind} || '' ) eq $kind } @$all ];
}

sub _page_events {
    my ( $self, $data ) = @_;
    my $p     = $self->{request}{params};
    my $limit = valid_choice( $p->{limit}, \@EVENT_LIMITS, $EVENT_LIMITS[0] );
    my $sev   = valid_choice( $p->{severity}, \@SEV_FILTERS, 'all' );
    $data->{limit}      = $limit;
    $data->{limits}     = [ sort { $a <=> $b } @EVENT_LIMITS ];
    $data->{severity}   = $sev;
    $data->{severities} = [@SEV_FILTERS];
    my $all = $self->_list( $data, $self->{agent}->call( 'events', '--limit', $limit ), 'events' );
    my %count = ( all => scalar @$all );
    for my $e (@$all) {
        my $rank = $SEV_RANK{ defined $e->{severity} && !ref $e->{severity} ? $e->{severity} : '' } || 0;
        $count{warning}++  if $rank >= $SEV_FILTER{warning};
        $count{critical}++ if $rank >= $SEV_FILTER{critical};
    }
    $data->{sev_count} = \%count;
    $data->{events}    = [ grep { ( $SEV_RANK{ defined $_->{severity} && !ref $_->{severity} ? $_->{severity} : '' } || 0 ) >= $SEV_FILTER{$sev} } @$all ];
}

sub _page_coexistence {
    my ( $self, $data ) = @_;
    my $reply = $self->{agent}->call('coexistence');
    $data->{tools} = $self->_list( $data, $reply, 'tools' );
    $data->{mode}  = $reply->{mode} if $reply->{ok};
}

sub _page_sites {
    my ( $self, $data ) = @_;
    my $reply = $self->{agent}->call('sites');
    my $sites = $self->_list( $data, $reply, 'sites' );
    my ( %by, @order );
    for my $s (@$sites) {
        my $acct = defined $s->{account} ? $s->{account} : '';
        push @order, $acct unless $by{$acct};
        push @{ $by{$acct} }, $s;
    }
    $data->{accounts}             = [ map { { account => $_, sites => $by{$_} } } sort @order ];
    $data->{site_count}           = scalar @$sites;
    $data->{account_count}        = scalar grep { length } @order;
    $data->{covered_count}        = scalar grep { $_->{scan_covered} } @$sites;
    $data->{malware_scan_enabled} = $reply->{ok} ? $reply->{malware_scan_enabled} : undef;
    $data->{control_panel}        = $reply->{ok} ? $reply->{control_panel} : undef;
}

1;
