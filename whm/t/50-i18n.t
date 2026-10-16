use strict;
use warnings;
use Test::More;
use FindBin;
use JSON::PP ();
use lib "$FindBin::Bin/lib";
use IFTest qw(i18n $ROOT);
use InfraFence::WHM::I18n ();

sub load {
    open my $fh, '<:raw', "$ROOT/plugin/locale/$_[0].json" or die $!;
    local $/;
    return JSON::PP->new->utf8->decode(<$fh>);
}

my $en = load('en');
for my $lang (qw(it es fr de pt)) {
    my $t = load($lang);
    is_deeply( [ sort keys %$t ], [ sort keys %$en ], "$lang: same keys as en" );
    for my $k ( sort keys %$en ) {
        next unless defined $t->{$k};
        my @a = sort $en->{$k} =~ /(\{[a-z_]+\})/g;
        my @b = sort $t->{$k} =~ /(\{[a-z_]+\})/g;
        is_deeply( \@b, \@a, "$lang: placeholders in $k" ) or last;
    }
    unlike( join( ' ', values %$t ), qr/</, "$lang: no markup" );
}

# Every key used by the templates exists.
my %used;
for my $f ( glob "$ROOT/plugin/templates/infrafence/*.tmpl" ) {
    open my $fh, '<', $f or die $!;
    local $/;
    my $src = <$fh>;
    $used{$1} = 1 while $src =~ /L\.t\('([a-z_.]+)'/g;
}
ok( exists $en->{$_}, "en has $_" ) for grep { !/\.\z/ } sort keys %used;

is( InfraFence::WHM::I18n::normalize($_->[0]), $_->[1], 'normalize ' . ( $_->[0] // 'undef' ) ) for (
    [ 'en', 'en' ], [ 'it', 'it' ], [ 'pt_br', 'pt' ], [ 'es_419', 'es' ], [ 'de-DE', 'de' ],
    [ 'fr', 'fr' ], [ 'ja', 'en' ], [ 'i_cpanel_snowmen', 'en' ], [ undef, 'en' ], [ '../../x', 'en' ],
);

my $L = i18n('it');
is( $L->t( 'notice.unban_ok', ip => '192.0.2.1' ) =~ /192\.0\.2\.1/ ? 1 : 0, 1, 'placeholder filled' );
is( $L->t('no.such.key'), 'no.such.key', 'unknown key shows key' );
is( $L->label( 'severity', 'weird' ), 'weird', 'unknown value shown as is' );
is( $L->time('2026-10-16T09:41:07Z'), '2026-10-16 09:41 UTC', 'time' );
is( $L->time('2026-10-16T11:41:07+02:00'), '2026-10-16 09:41 UTC', 'time with offset' );
is( $L->time('garbage'), 'garbage', 'unparsable time shown as is' );
is( i18n('en')->ago('2026-10-16T11:56:00Z'), '5 min ago', 'ago minutes' );
is( i18n('en')->ago('2026-10-16T09:01:00Z'), '3 h ago', 'ago hours' );
is( i18n('en')->ago('2026-10-13T12:01:00Z'), '3 d ago', 'ago days' );
is( i18n('en')->number(1234567), '1,234,567', 'number en' );
is( i18n('de')->number(1234567), '1.234.567', 'number de' );

done_testing;
