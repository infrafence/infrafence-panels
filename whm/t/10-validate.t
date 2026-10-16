use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use IFTest ();
use InfraFence::WHM::Validate qw(valid_ip valid_note valid_actor valid_docroot valid_choice);

my %good = (
    '203.0.113.7'        => '203.0.113.7',
    ' 198.51.100.1 '     => '198.51.100.1',
    '255.255.255.255'    => '255.255.255.255',
    '10.0.0.0'           => '10.0.0.0',
    '2001:db8::1'        => '2001:db8::1',
    '2001:DB8:0:0:0:0:0:1' => '2001:db8::1',
    '::ffff:192.0.2.1'   => '::ffff:192.0.2.1',
);
is( valid_ip($_), $good{$_}, "valid ip '$_'" ) for sort keys %good;

for my $bad ( undef, '', '0.0.0.0', '::', '256.1.1.1', '1.2.3', '1.2.3.4.5', '01.2.3.4', '1.2.3.04',
    '1.2.3.4/24', '1.2.3.4 5.6.7.8', '-1.2.3.4', '--actor', '1.2.3.4;rm -rf /', '$(id)', "1.2.3.4\nx", "1.2.3.4\0",
    'fe80::1%eth0', '2001:db8::g', 'example.com', '1.2.3.4' x 20 )
{
    is( valid_ip($bad), undef, 'rejects ip ' . ( defined $bad ? "'$bad'" : 'undef' ) );
}

is( valid_note(undef),         '',               'empty note' );
is( valid_note('  Office  '),  'Office',         'note trimmed' );
is( valid_note("Caf\xc3\xa9"), "Caf\xc3\xa9",    'utf-8 note' );
is( valid_note( 'x' x 200 ),   'x' x 200,        '200 chars ok' );
is( valid_note( "\xc3\xa9" x 200 ), "\xc3\xa9" x 200, '200 non-ascii chars ok' );
is( valid_note( 'x' x 201 ),   undef,            '201 chars refused' );
is( valid_note("a\nb"),        undef,            'newline refused' );
is( valid_note("a\x00b"),      undef,            'NUL refused' );
is( valid_note('--actor=evil'), undef,           'leading dash refused' );
is( valid_note("\xff\xfe"),    undef,            'invalid utf-8 refused' );

is( valid_actor('root'),     'root',  'actor root' );
is( valid_actor('resell_1'), 'resell_1', 'actor reseller' );
is( valid_actor($_), undef, "actor '$_' refused" ) for ( '', '-x', 'a b', 'a;b', 'x' x 65 );

my @roots = ( '/home/a/public_html', '/home/b/site' );
is( valid_docroot( '/home/a/public_html', \@roots ), '/home/a/public_html', 'known docroot' );
is( valid_docroot( '/home/a/public_html/', \@roots ), undef, 'not exactly known' );
is( valid_docroot( '/home/a/public_html/../../root', \@roots ), undef, 'traversal' );
is( valid_docroot( '/etc', \@roots ), undef, 'unknown' );
is( valid_docroot( 'home/a/public_html', ['home/a/public_html'] ), undef, 'relative' );
is( valid_docroot( "/home/a\n", ["/home/a\n"] ), undef, 'control chars' );

is( valid_choice( '100', [qw(50 100)], 50 ), '100', 'choice' );
is( valid_choice( '7',   [qw(50 100)], 50 ), 50,    'choice default' );
is( valid_choice( undef, [qw(50 100)], 50 ), 50,    'choice undef' );

done_testing;
