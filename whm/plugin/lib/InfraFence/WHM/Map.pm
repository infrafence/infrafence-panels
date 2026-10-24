package InfraFence::WHM::Map;

# The Overview's attack map: turns the agent's `panel map` reply into what the
# template draws as inline SVG, with the world outlines shipped in map/world.json
# (Natural Earth, see map/NOTICE) and the country names in map/countries.json.
# Same look as the InfraFence dashboard's map: a country is filled from the land
# colour toward the critical colour, and a dot sized by attacks (square-root
# scale) sits on it.
#
# Nothing from the reply reaches the page unchecked: a country code must be two
# capital letters and one the map knows, counts must be whole numbers, a
# category a short lower-case word.

use strict;
use warnings;

use JSON::PP ();

use InfraFence::WHM::Util qw(to_bytes);

our $DIR = '/usr/local/share/infrafence-whm/map';

our @RANGES = ( [ '24h' => 24 ], [ '7d' => 168 ] );

use constant TOP           => 5;
use constant MAX_COUNTRIES => 250;
use constant DOT_MIN       => 2.5;
use constant DOT_MAX       => 22;

# The dashboard's tokens: --surface-3 (light) for land, --status-critical-solid.
my @LAND     = ( 0xe8, 0xea, 0xed );
my @CRITICAL = ( 0xd0, 0x3b, 0x3b );

my %CACHE;

sub _load {
    my ( $dir, $name ) = @_;
    my $file = "$dir/$name";
    return $CACHE{$file} if $CACHE{$file};
    open my $fh, '<:raw', $file or return undef;
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $data = eval { JSON::PP->new->utf8->decode($raw) };
    return undef unless ref $data eq 'HASH';
    return $CACHE{$file} = to_bytes($data);
}

sub world { _load( $_[0] || $DIR, 'world.json' ) }

# Country name in the plugin's language (en, it, es, fr, de, pt), or the code.
sub country_name {
    my ( $dir, $lang, $code ) = @_;
    my $names = _load( $dir || $DIR, 'countries.json' ) || {};
    my $n = ( $names->{$lang} || {} )->{$code};
    $n = ( $names->{en} || {} )->{$code} unless defined $n;
    return defined $n ? $n : $code;
}

sub range_hours {
    my ($range) = @_;
    for (@RANGES) { return $_->[1] if $_->[0] eq ( defined $range ? $range : '' ) }
    return $RANGES[0][1];
}

sub _count {
    my ($v) = @_;
    return undef unless defined $v && !ref $v && $v =~ /\A[0-9]{1,15}\z/;
    return $v + 0;
}

# Builds the view: { state => ok|empty|old_agent|not_connected|unavailable,
# range, total, countries (top), categories, svg, stale, generated_at }.
sub view {
    my (%a) = @_;
    my ( $reply, $lang, $dir, $range ) = @a{qw(reply lang dir range)};
    my %v = ( range => $range, ranges => [ map { $_->[0] } @RANGES ] );

    unless ( ref $reply eq 'HASH' && $reply->{ok} ) {
        my $e = ref $reply eq 'HASH' ? ( $reply->{error} || '' ) : '';
        $v{state} =
            $e eq 'unknown_command' ? 'old_agent'
          : $e eq 'not_connected'   ? 'not_connected'
          :                           'unavailable';
        return \%v;
    }

    my $world = world($dir);
    unless ($world) {
        $v{state} = 'unavailable';
        return \%v;
    }
    my $dots  = $world->{dots} || {};
    my %known = %$dots;
    $known{ $_->[0] } = 1 for grep { ref $_ eq 'ARRAY' && length $_->[0] } @{ $world->{shapes} || [] };

    my $total = _count( ref $reply->{total} eq 'HASH' ? $reply->{total}{attacks} : undef ) || 0;

    my ( @countries, %seen );
    for my $c ( ref $reply->{countries} eq 'ARRAY' ? @{ $reply->{countries} } : () ) {
        next unless ref $c eq 'HASH' && defined $c->{code} && !ref $c->{code};
        my $code = $c->{code};
        next unless $code =~ /\A[A-Z]{2}\z/ && $known{$code} && !$seen{$code}++;
        my $n = _count( $c->{attacks} );
        next unless $n;
        push @countries, { code => $code, attacks => $n };
        last if @countries >= MAX_COUNTRIES;
    }
    @countries = sort { $b->{attacks} <=> $a->{attacks} || $a->{code} cmp $b->{code} } @countries;
    $total = 0 + $total;
    my $sum = 0;
    $sum += $_->{attacks} for @countries;
    $total = $sum if $sum > $total;

    my ( @cats, %cseen );
    for my $c ( ref $reply->{categories} eq 'ARRAY' ? @{ $reply->{categories} } : () ) {
        next unless ref $c eq 'HASH' && defined $c->{cat} && !ref $c->{cat};
        next unless $c->{cat} =~ /\A[a-z][a-z0-9_]{0,31}\z/ && !$cseen{ $c->{cat} }++;
        my $n = _count( $c->{attacks} );
        next unless $n;
        push @cats, { cat => $c->{cat}, attacks => $n };
        last if @cats >= 20;
    }
    @cats = sort { $b->{attacks} <=> $a->{attacks} } @cats;
    my $ctotal = 0;
    $ctotal += $_->{attacks} for @cats;
    # Shares of the categories shown, as on the dashboard's map (at least 1%).
    for (@cats) {
        my $p = int( 100 * $_->{attacks} / $ctotal + 0.5 );
        $_->{pct} = $p < 1 ? 1 : $p;
    }

    my $max = @countries ? $countries[0]{attacks} : 0;
    my %by  = map { $_->{code} => $_ } @countries;
    for my $c (@countries) {
        $c->{name}  = country_name( $dir, $lang, $c->{code} );
        $c->{share} = $total ? int( 1000 * $c->{attacks} / $total + 0.5 ) / 10 : 0;
    }

    my @shapes = map {
        my ( $code, $d ) = @$_;
        my $c = length $code ? $by{$code} : undef;
        {
            d    => $d,
            fill => $c ? _fill( $c->{attacks}, $max ) : _hex(@LAND),
            ( $c ? ( code => $code, name => $c->{name}, attacks => $c->{attacks} ) : () ),
        }
    } grep { ref $_ eq 'ARRAY' } @{ $world->{shapes} || [] };

    my @dots;
    for my $c (@countries) {
        my $xy = $dots->{ $c->{code} } or next;
        push @dots, {
            x       => $xy->[0],
            y       => $xy->[1],
            r       => sprintf( '%.1f', DOT_MIN + ( DOT_MAX - DOT_MIN ) * sqrt( $c->{attacks} / $max ) ),
            name    => $c->{name},
            attacks => $c->{attacks},
        };
    }
    @dots = sort { $b->{r} <=> $a->{r} } @dots;    # small dots on top of big ones

    $v{state}        = $total > 0 ? 'ok' : 'empty';
    $v{total}        = $total;
    $v{countries}    = [ @countries[ 0 .. ( @countries > TOP ? TOP - 1 : $#countries ) ] ];
    $v{country_count} = scalar @countries;
    $v{categories}   = \@cats;
    $v{stale}        = $reply->{stale} ? 1 : 0;
    $v{generated_at} = $reply->{generated_at}
      if defined $reply->{generated_at} && !ref $reply->{generated_at} && $reply->{generated_at} =~ /\A[0-9T:.+Z-]{10,40}\z/;
    $v{svg} = { width => $world->{width} + 0, height => $world->{height} + 0, shapes => \@shapes, dots => \@dots };
    return \%v;
}

sub _hex { sprintf '#%02x%02x%02x', @_ }

# From land toward critical by 10-32%, by the square root of the share of the maximum.
sub _fill {
    my ( $n, $max ) = @_;
    my $pct = $max > 0 ? int( 10 + 22 * sqrt( $n / $max ) + 0.5 ) / 100 : 0;
    return _hex( map { int( $LAND[$_] + ( $CRITICAL[$_] - $LAND[$_] ) * $pct + 0.5 ) } 0 .. 2 );
}

1;
