package InfraFence::WHM::Validate;

# Input validation. Every value that reaches the agent's argv goes through one
# of these functions first. They return the cleaned value, or undef.

use strict;
use warnings;

use Socket qw(inet_pton inet_ntop AF_INET6);

use Exporter 'import';
our @EXPORT_OK = qw(valid_ip valid_note valid_actor valid_docroot valid_choice valid_https_url);

use constant NOTE_MAX => 200;

# A single IPv4 or IPv6 address. IPv4 must be dotted quad without leading
# zeros (which some tools read as octal). IPv6 is returned in canonical form.
# The unspecified addresses (0.0.0.0, ::) are refused.
sub valid_ip {
    my ($s) = @_;
    return undef unless defined $s;
    $s =~ s/\A\s+//;
    $s =~ s/\s+\z//;
    return undef if $s eq '' || length $s > 45;

    if ( my @o = $s =~ /\A([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\z/ ) {
        for my $octet (@o) {
            return undef if $octet > 255 || ( length $octet > 1 && substr( $octet, 0, 1 ) eq '0' );
        }
        my $ip = join '.', @o;
        return undef if $ip eq '0.0.0.0';
        return $ip;
    }

    if ( index( $s, ':' ) >= 0 && $s =~ /\A[0-9A-Fa-f:.]+\z/ ) {
        my $packed = inet_pton( AF_INET6, $s );
        return undef unless defined $packed && length $packed == 16;
        return undef if $packed eq "\0" x 16;
        return lc inet_ntop( AF_INET6, $packed );
    }

    return undef;
}

# Free text note for an allow-list entry. Empty is fine. Valid UTF-8 without
# control characters, at most NOTE_MAX bytes (the agent's limit), and it may
# not start with "-" so it can never be taken for an option.
sub valid_note {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/\A\s+//;
    $s =~ s/\s+\z//;
    return '' if $s eq '';
    return undef if length $s > NOTE_MAX;
    my $chars = $s;
    return undef unless utf8::decode($chars);
    return undef if $chars =~ /[\x00-\x1f\x7f\x{80}-\x{9f}\x{2028}\x{2029}]/;
    return undef if substr( $s, 0, 1 ) eq '-';
    return $s;
}

# The WHM user name passed as --actor.
sub valid_actor {
    my ($s) = @_;
    return undef unless defined $s && $s =~ /\A[A-Za-z0-9_][A-Za-z0-9._-]{0,63}\z/;
    return $s;
}

# A document root is accepted only if the agent itself listed it in `sites`.
sub valid_docroot {
    my ( $path, $known ) = @_;
    return undef unless defined $path && length $path && length $path <= 4096;
    return undef unless substr( $path, 0, 1 ) eq '/';
    return undef if $path =~ /[\x00-\x1f\x7f]/;
    for my $k ( @{ $known || [] } ) {
        return $k if defined $k && $k eq $path;
    }
    return undef;
}

# A link the agent sends (dashboard_url), before it goes into an href.
# Strict: https, a host name made of DNS labels (no userinfo, no IP literal
# brackets), an optional port, then a path and query of plain URL characters
# only (no spaces, quotes, backslashes or "@"). No fragment.
my $LABEL = qr/[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?/;
my $HTTPS = qr{\Ahttps://$LABEL(?:\.$LABEL)*(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~%/+,;=:-]*)?(?:\?[A-Za-z0-9._~%/+,;=:&-]*)?\z};

sub valid_https_url {
    my ($s) = @_;
    return undef unless defined $s && length $s <= 2048 && $s =~ $HTTPS;
    if ( $s =~ m{\Ahttps://[^/?]*:([0-9]+)} ) {
        return undef if $1 < 1 || $1 > 65535;
    }
    return $s;
}

# One of a fixed list of values, or the default.
sub valid_choice {
    my ( $v, $allowed, $default ) = @_;
    return $default unless defined $v;
    for my $a (@$allowed) {
        return $a if $a eq $v;
    }
    return $default;
}

1;
