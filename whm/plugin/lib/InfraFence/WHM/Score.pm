package InfraFence::WHM::Score;

# The Overview's security score: turns the agent's `panel score` reply into
# the score, its grade, a sparkline of the trend and the items that take
# points off, each with the values its sentence needs. The score itself is
# computed by the InfraFence dashboard; the plugin only shows it.

use strict;
use warnings;

use constant MAX_ITEMS => 20;
use constant MAX_TREND => 31;
use constant SPARK_W   => 220;
use constant SPARK_H   => 44;

# The dashboard's scale: A >= 90, B >= 75, C >= 60, D >= 40, F below.
sub grade {
    my ($s) = @_;
    return $s >= 90 ? 'A' : $s >= 75 ? 'B' : $s >= 60 ? 'C' : $s >= 40 ? 'D' : 'F';
}

# The dashboard's colours for a grade: ok, warning or critical.
my %TONE = ( A => 'ok', B => 'ok', C => 'warning', D => 'warning', F => 'critical' );

sub _int {
    my ( $v, $max ) = @_;
    return undef unless defined $v && !ref $v && $v =~ /\A[0-9]{1,9}\z/;
    return undef if defined $max && $v > $max;
    return $v + 0;
}

sub _iso {
    my ($v) = @_;
    return defined $v && !ref $v && $v =~ /\A[0-9T:.+Z-]{10,40}\z/ ? $v : undef;
}

# { state => ok|old_agent|not_connected|unavailable, score, grade, tone,
#   items => [{ key, points, args }], trend, spark, delta, stale, generated_at }
sub view {
    my (%a) = @_;
    my ( $reply, $number ) = @a{qw(reply number)};
    $number ||= sub { $_[0] };
    my %v;

    unless ( ref $reply eq 'HASH' && $reply->{ok} ) {
        my $e = ref $reply eq 'HASH' ? ( $reply->{error} || '' ) : '';
        $v{state} =
            $e eq 'unknown_command' ? 'old_agent'
          : $e eq 'not_connected'   ? 'not_connected'
          :                           'unavailable';
        return \%v;
    }
    my $score = _int( $reply->{score}, 100 );
    unless ( defined $score ) {
        $v{state} = 'unavailable';
        return \%v;
    }

    my @items;
    for my $i ( ref $reply->{items} eq 'ARRAY' ? @{ $reply->{items} } : () ) {
        next unless ref $i eq 'HASH' && defined $i->{key} && !ref $i->{key} && $i->{key} =~ /\A[a-z][a-z0-9_]{0,47}\z/;
        my $points = _int( $i->{points}, 100 );
        next unless $points;
        push @items, { key => $i->{key}, points => $points, args => _args( $i->{detail}, $i->{key}, $number ) };
        last if @items >= MAX_ITEMS;
    }
    @items = sort { $b->{points} <=> $a->{points} } @items;

    my @trend;
    for my $t ( ref $reply->{trend} eq 'ARRAY' ? @{ $reply->{trend} } : () ) {
        next unless ref $t eq 'HASH' && defined $t->{day} && !ref $t->{day} && $t->{day} =~ /\A\d{4}-\d\d-\d\d\z/;
        my $s = _int( $t->{score}, 100 );
        push @trend, { day => $t->{day}, score => $s } if defined $s;
    }
    @trend = sort { $a->{day} cmp $b->{day} } @trend;
    splice @trend, 0, @trend - MAX_TREND if @trend > MAX_TREND;

    my $g = grade($score);
    %v = (
        state        => 'ok',
        score        => $score,
        grade        => $g,
        tone         => $TONE{$g},
        items        => \@items,
        trend        => \@trend,
        stale        => $reply->{stale} ? 1 : 0,
        generated_at => _iso( $reply->{generated_at} ),
    );
    if ( @trend > 1 ) {
        $v{delta} = $score - $trend[0]{score};
        $v{spark} = _spark( \@trend );
    }
    return \%v;
}

# Values for the item's sentence: counts formatted, ports and versions checked.
sub _args {
    my ( $d, $key, $number ) = @_;
    # A value the reply lacks shows as a dash, never as a placeholder.
    my %out = map { $_ => "\xe2\x80\x93" } qw(failed total packages critical other members n ports version latest);
    return \%out unless ref $d eq 'HASH';
    for my $k (qw(failed total packages critical other members)) {
        my $n = _int( $d->{$k} );
        $out{$k} = $number->($n) if defined $n;
    }
    my $n = $key eq 'malware' ? $d->{critical} : $d->{packages};
    $n = _int($n);
    $out{n} = $number->($n) if defined $n;
    if ( ref $d->{ports} eq 'ARRAY' ) {
        my @p = grep { defined $_ } map { _int( $_, 65535 ) } @{ $d->{ports} };
        splice @p, 10 if @p > 10;
        $out{ports} = join ', ', @p if @p;
    }
    for my $k (qw(version latest)) {
        $out{$k} = $d->{$k} if defined $d->{$k} && !ref $d->{$k} && $d->{$k} =~ /\A[0-9A-Za-z][0-9A-Za-z.+~-]{0,31}\z/;
    }
    return \%out;
}

# A polyline of the trend, oldest on the left. The vertical scale fits the
# values (at least 10 points tall), so a small change is still visible.
sub _spark {
    my ($trend) = @_;
    my $n = @$trend;
    my ( $lo, $hi ) = ( 100, 0 );
    for (@$trend) {
        $lo = $_->{score} if $_->{score} < $lo;
        $hi = $_->{score} if $_->{score} > $hi;
    }
    if ( $hi - $lo < 10 ) {
        my $mid = ( $hi + $lo ) / 2;
        ( $lo, $hi ) = ( $mid - 5, $mid + 5 );
    }
    my $dx  = ( SPARK_W - 4 ) / ( $n - 1 );
    my @pts = map { sprintf '%.1f,%.1f', 2 + $_ * $dx, 2 + ( SPARK_H - 4 ) * ( $hi - $trend->[$_]{score} ) / ( $hi - $lo ) } 0 .. $n - 1;
    return { width => SPARK_W, height => SPARK_H, points => join( ' ', @pts ), first => $trend->[0], last => $trend->[-1] };
}

1;
