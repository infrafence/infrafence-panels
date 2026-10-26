package InfraFence::WHM::I18n;

# Text for the plugin, from one JSON file per language (locale/<lang>.json).
# Missing keys fall back to English, then to the key itself. All strings are
# UTF-8 bytes. Placeholders are written {name} and filled from named arguments.
#
# The object is passed to the templates as `L`:
#   [% L.t('bans.title') | html %]
#   [% L.t('confirm.unban.title', ip => ip) | html %]
#   [% L.label('severity', row.severity) | html %]
#   [% L.time(row.created) | html %]   [% L.ago(status.last_heartbeat) | html %]

use strict;
use warnings;

use JSON::PP ();
use Time::Local ();

use InfraFence::WHM::Util qw(to_bytes);

our @LANGUAGES = qw(en it es fr de pt);

my %CACHE;

sub new {
    my ( $class, %args ) = @_;
    my $dir  = $args{dir} or die "locale dir required\n";
    my $lang = normalize( $args{lang} );
    my $self = bless {
        lang => $lang,
        dir  => $dir,
        now  => $args{now},
    }, $class;
    $self->{en}   = _load( $dir, 'en' );
    $self->{text} = $lang eq 'en' ? $self->{en} : _load( $dir, $lang );
    return $self;
}

# Maps a cPanel locale tag (en, it, pt_br, es_419, de_de...) to one of ours.
sub normalize {
    my ($tag) = @_;
    return 'en' unless defined $tag;
    my ($base) = lc($tag) =~ /\A([a-z]{2})(?:[_-]|\z)/;
    return 'en' unless defined $base;
    return ( grep { $_ eq $base } @LANGUAGES ) ? $base : 'en';
}

sub _load {
    my ( $dir, $lang ) = @_;
    my $file = "$dir/$lang.json";
    return $CACHE{$file} if $CACHE{$file};
    open my $fh, '<:raw', $file or return {};
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $data = eval { JSON::PP->new->utf8->decode($raw) };
    return {} unless ref $data eq 'HASH';
    return $CACHE{$file} = to_bytes($data);
}

sub lang { $_[0]{lang} }

sub has {
    my ( $self, $key ) = @_;
    return defined $self->{text}{$key} || defined $self->{en}{$key};
}

sub t {
    my ( $self, $key, @rest ) = @_;
    my $args = ( @rest == 1 && ref $rest[0] eq 'HASH' ) ? $rest[0] : {@rest};
    my $s = $self->{text}{$key};
    $s = $self->{en}{$key} unless defined $s;
    $s = $key unless defined $s;
    $s =~ s/\{([a-z_]+)\}/defined $args->{$1} ? $args->{$1} : "{$1}"/ge;
    return $s;
}

# A sentence with a count: "<key>.one" when n is 1, else "<key>.other";
# {n} is filled with the formatted number.
#   [% L.tn('verdict.critical', 3) | html %]
sub tn {
    my ( $self, $key, $n, @rest ) = @_;
    my $k = defined $n && $n == 1 && $self->has("$key.one") ? "$key.one" : "$key.other";
    return $self->t( $k, { @rest, n => $self->number($n) } );
}

# Text for a value from the agent (severity, source, status...). Values the
# plugin does not know yet are shown as they are.
sub label {
    my ( $self, $group, $value ) = @_;
    return '' unless defined $value && !ref $value && length $value;
    my $key = "$group.$value";
    return $self->has($key) ? $self->t($key) : $value;
}

sub _now { $_[0]{now} ? $_[0]{now}->() : CORE::time() }

# ISO 8601 (as sent by the agent) to epoch seconds.
sub epoch {
    my ( $self, $iso ) = @_;
    return undef unless defined $iso;
    my ( $y, $mo, $d, $h, $mi, $s, $tz ) =
      $iso =~ /\A(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d)(?::(\d\d))?(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?\z/
      or return undef;
    my $t = eval { Time::Local::timegm( $s || 0, $mi, $h, $d, $mo - 1, $y ) };
    return undef unless defined $t;
    if ( defined $tz && $tz ne 'Z' ) {
        my ( $sign, $oh, $om ) = $tz =~ /\A([+-])(\d\d):?(\d\d)\z/;
        my $off = ( $oh * 60 + $om ) * 60;
        $t += $sign eq '+' ? -$off : $off;
    }
    return $t;
}

# "2026-10-16 09:41 UTC"
sub time {
    my ( $self, $iso ) = @_;
    return '' unless defined $iso && length $iso;
    my $t = $self->epoch($iso);
    return $iso unless defined $t;
    my @g = gmtime $t;
    return sprintf '%04d-%02d-%02d %02d:%02d UTC', $g[5] + 1900, $g[4] + 1, $g[3], $g[2], $g[1];
}

# "20:56 UTC": the time of day, for times of the last 24 hours.
sub clock {
    my ( $self, $iso ) = @_;
    return '' unless defined $iso && length $iso;
    my $t = $self->epoch($iso);
    return $iso unless defined $t;
    my @g = gmtime $t;
    return sprintf '%02d:%02d UTC', $g[2], $g[1];
}

# "4 min ago", in the user's language.
sub ago {
    my ( $self, $iso ) = @_;
    my $t = $self->epoch($iso);
    return '' unless defined $t;
    my $age = $self->_now - $t;
    return $self->t('time.just_now') if $age < 60;
    return $self->t( 'time.minutes_ago', n => int( $age / 60 ) ) if $age < 3600;
    return $self->t( 'time.hours_ago',   n => int( $age / 3600 ) ) if $age < 86400;
    return $self->t( 'time.days_ago', n => int( $age / 86400 ) );
}

# Seconds since a timestamp (for "stale heartbeat" checks in templates).
sub age {
    my ( $self, $iso ) = @_;
    my $t = $self->epoch($iso);
    return undef unless defined $t;
    return $self->_now - $t;
}

sub number {
    my ( $self, $n ) = @_;
    return '' unless defined $n;
    return $n unless $n =~ /\A\d+\z/;
    my $sep = $self->t('format.thousands');
    $sep = ' ' if $sep eq 'format.thousands' || $sep eq '';
    1 while $n =~ s/\A(\d+)(\d{3})/$1$sep$2/;
    return $n;
}

1;
