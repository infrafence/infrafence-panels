package InfraFence::WHM::Util;

# Small helpers shared by the WHM plugin modules.

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(to_bytes const_eq uri_escape);

# Turns a decoded JSON structure into plain UTF-8 byte strings and 1/0 booleans,
# so that everything handed to the templates is in the same form as the
# template files themselves.
sub to_bytes {
    my ($v) = @_;
    my $ref = ref $v;
    if ( $ref eq 'HASH' ) {
        my %out;
        for my $k ( keys %$v ) {
            my $bk = $k;
            utf8::encode($bk) if utf8::is_utf8($bk);
            $out{$bk} = to_bytes( $v->{$k} );
        }
        return \%out;
    }
    return [ map { to_bytes($_) } @$v ] if $ref eq 'ARRAY';
    return ( $v ? 1 : 0 ) if $ref && $ref =~ /Boolean\z/;
    return undef if $ref;    # nothing else is expected from the agent
    return $v unless defined $v;
    my $s = "$v";
    utf8::encode($s) if utf8::is_utf8($s);
    return $s;
}

# Compares two strings in time that depends only on their length.
sub const_eq {
    my ( $a, $b ) = @_;
    return 0 unless defined $a && defined $b && length $a == length $b;
    my $diff = 0;
    $diff |= ord( substr $a, $_, 1 ) ^ ord( substr $b, $_, 1 ) for 0 .. length($a) - 1;
    return $diff == 0;
}

sub uri_escape {
    my ($s) = @_;
    $s = '' unless defined $s;
    utf8::encode($s) if utf8::is_utf8($s);
    $s =~ s/([^A-Za-z0-9\-._~])/sprintf '%%%02X', ord $1/ge;
    return $s;
}

1;
