package InfraFence::WHM::CGI;

# The glue between cpsrvd and the controller: reads the CGI request, checks
# that the WHM user has root privileges, runs InfraFence::WHM::App and prints
# the result through WHM's own Template Toolkit setup (Cpanel::Template), so
# the page is wrapped in WHM's master template.

use strict;
use warnings;

use InfraFence::WHM::Agent ();
use InfraFence::WHM::App   ();
use InfraFence::WHM::I18n  ();

our $SHARE_DIR = '/usr/local/share/infrafence-whm';

use constant MAX_BODY => 64 * 1024;

sub main {
    unless ( _has_root() ) {
        _print_headers( 403, 'text/plain' );
        print "Access denied. InfraFence requires root privileges in WHM.\n";
        return 0;
    }

    my $request = read_request( \%ENV, \*STDIN );
    my $i18n    = InfraFence::WHM::I18n->new(
        dir  => "$SHARE_DIR/locale",
        lang => _cpanel_locale(),
    );
    my $app = InfraFence::WHM::App->new(
        agent   => InfraFence::WHM::Agent->new,
        i18n    => $i18n,
        request => $request,
    );
    my $res = $app->run;

    if ( $res->{location} ) {
        _print_headers( $res->{code}, undef, $res->{location} );
        return 0;
    }

    _print_headers( $res->{code}, 'text/html; charset=utf-8' );
    require Cpanel::Template;
    Cpanel::Template::process_template(
        'whostmgr',
        {
            template_file => $res->{template},
            print         => 1,
            data          => $res->{data},
        },
    );
    return 0;
}

sub _has_root {
    my $ok = eval {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        Whostmgr::ACLS::hasroot();
    };
    return $ok ? 1 : 0;
}

sub _cpanel_locale {
    my $tag = eval {
        require Cpanel::Locale;
        Cpanel::Locale->get_handle->get_language_tag;
    };
    return $tag;
}

my %REASON = ( 200 => 'OK', 303 => 'See Other', 400 => 'Bad Request', 403 => 'Forbidden' );

sub _print_headers {
    my ( $code, $type, $location ) = @_;
    $code ||= 200;
    print "Status: $code " . ( $REASON{$code} || 'OK' ) . "\r\n";
    print "Location: $location\r\n" if $location;
    print "Content-Type: $type\r\n" if $type;
    print "Cache-Control: no-store\r\n";
    print "X-Content-Type-Options: nosniff\r\n";
    # The WHM URL carries the session token: never send it to other sites.
    print "Referrer-Policy: same-origin\r\n";
    print "\r\n";
}

# Builds the request hash the controller expects from a CGI environment.
sub read_request {
    my ( $env, $in ) = @_;
    my $method = uc( $env->{REQUEST_METHOD} || 'GET' );

    my %params;
    _parse_into( \%params, $env->{QUERY_STRING} );

    if ( $method eq 'POST' ) {
        my $len  = $env->{CONTENT_LENGTH} || 0;
        my $type = lc( $env->{CONTENT_TYPE} || '' );
        if ( $len =~ /\A\d+\z/ && $len > 0 && $len <= MAX_BODY && index( $type, 'application/x-www-form-urlencoded' ) == 0 ) {
            my $body = '';
            while ( length $body < $len ) {
                my $n = read $in, $body, $len - length $body, length $body;
                last unless $n;
            }
            # Fields in the body take precedence over the query string.
            my %post;
            _parse_into( \%post, $body );
            @params{ keys %post } = values %post;
        }
    }

    return {
        method  => $method,
        params  => \%params,
        token   => $env->{cp_security_token},
        actor   => $env->{REMOTE_USER},
        host    => $env->{HTTP_HOST},
        origin  => $env->{HTTP_ORIGIN},
        referer => $env->{HTTP_REFERER},
    };
}

# application/x-www-form-urlencoded; the first value of a repeated field wins.
sub _parse_into {
    my ( $into, $qs ) = @_;
    return unless defined $qs && length $qs;
    for my $pair ( split /[&;]/, $qs ) {
        next unless length $pair;
        my ( $k, $v ) = split /=/, $pair, 2;
        $v = '' unless defined $v;
        for ( $k, $v ) {
            tr/+/ /;
            s/%([0-9A-Fa-f]{2})/chr hex $1/ge;
        }
        next if length $k > 32 || exists $into->{$k};
        $into->{$k} = $v;
    }
}

1;
