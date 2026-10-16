use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP ();
use lib "$FindBin::Bin/lib";
use IFTest qw(run_app mock_agent TOKEN);

my $dir = tempdir( CLEANUP => 1 );
my $log = "$dir/argv.log";

sub calls {
    open my $fh, '<', $log or return [];
    my @c = map { JSON::PP->new->decode($_) } <$fh>;
    close $fh;
    unlink $log;
    return \@c;
}
sub mutating { [ grep { $_->[1] =~ /\A(?:unban|allow|disallow|scan)\z/ } @{ calls() } ] }

# --- pages

for my $page (qw(overview bans allowlist findings events coexistence sites)) {
    my $res = run_app( params => { page => $page } );
    is( $res->{code}, 200, "$page: 200" );
    is( $res->{template}, 'infrafence/main.tmpl', "$page: main template" );
    is( $res->{data}{view}, $page, "$page: view" );
    is_deeply( $res->{data}{errors}, [], "$page: no errors" );
}

my $res = run_app( params => { page => '../../etc/passwd' } );
is( $res->{data}{view}, 'overview', 'unknown page falls back to overview' );

$res = run_app();
is( $res->{data}{protection}, 'protected', 'protected' );
is( $res->{data}{counts}{bans}, 9, 'ban count' );
is( $res->{data}{counts}{findings}, 3, 'open findings' );
is( $res->{data}{counts}{events}, 11, 'events in the last 24 h' );

$res = run_app( scenario => 'stopped' );
is( $res->{data}{protection}, 'stopped', 'stopped' );
ok( !$res->{data}{counts}, 'no counts while stopped' );

$res = run_app( params => { page => 'bans' }, scenario => 'stopped' );
is( $res->{data}{list_error}{error}, 'agent_not_running', 'list error while stopped' );

$res = run_app( agent => mock_agent( bin => undef ) );
is( $res->{data}{view}, 'not_installed', 'not installed' );
$res = run_app( agent => mock_agent( bin => undef ), method => 'POST',
    params => { action => 'unban', ip => '203.0.113.47', confirm => 1, csrf => TOKEN } );
is( $res->{data}{view}, 'not_installed', 'no actions without agent' );

$res = run_app( params => { page => 'bans', limit => '1000' }, log => $log );
is( $res->{data}{limit}, 1000, 'limit accepted' );
is_deeply( calls()->[-1], [qw(panel bans --limit 1000 --json)], 'limit passed' );
$res = run_app( params => { page => 'bans', limit => '5;id' }, log => $log );
is_deeply( calls()->[-1], [qw(panel bans --limit 500 --json)], 'bad limit ignored' );

$res = run_app( params => { page => 'findings', kind => 'malware' } );
is( scalar @{ $res->{data}{findings} }, 3, 'malware filter' );
is( $res->{data}{kind_count}{integrity}, 3, 'kind counts' );

$res = run_app( params => { page => 'coexistence' } );
is( scalar @{ $res->{data}{detected} }, 3, 'detected tools' );
is( $res->{data}{mode}, 'coexist', 'mode' );

$res = run_app( params => { page => 'sites' } );
is_deeply( [ map { $_->{account} } @{ $res->{data}{accounts} } ], [qw(brightdental greenleaf northwind)], 'accounts grouped' );
is( $res->{data}{site_count}, 5, 'site count' );

# --- confirmation step

$res = run_app( params => { page => 'bans', action => 'unban', ip => '203.0.113.47' }, log => $log );
is( $res->{data}{view}, 'confirm', 'GET shows confirmation' );
is( $res->{data}{act}{ip}, '203.0.113.47', 'confirm ip' );
is_deeply( mutating(), [], 'GET changes nothing' );

$res = run_app( method => 'POST', params => { action => 'unban', ip => '203.0.113.47', csrf => TOKEN }, log => $log );
is( $res->{data}{view}, 'confirm', 'POST without confirm=1 shows confirmation' );
is_deeply( mutating(), [], 'nothing changed' );

$res = run_app( params => { action => 'unban', ip => '203.0.113.47', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{data}{view}, 'confirm', 'GET with confirm=1 does not act' );
is_deeply( mutating(), [], 'nothing changed' );

# --- CSRF

my %unban = ( action => 'unban', ip => '203.0.113.47', confirm => 1 );
for my $case (
    [ 'missing csrf',   { params => {%unban} } ],
    [ 'wrong csrf',     { params => { %unban, csrf => '/cpsess0000000000' } } ],
    [ 'no session token', { params => { %unban, csrf => '' }, token => '' } ],
    [ 'foreign referer', { params => { %unban, csrf => TOKEN }, referer => 'https://evil.example/x' } ],
    [ 'foreign origin',  { params => { %unban, csrf => TOKEN }, origin => 'https://evil.example' } ],
  )
{
    my ( $name, $o ) = @$case;
    $res = run_app( method => 'POST', log => $log, %$o );
    is( $res->{code}, 403, "$name: 403" );
    is( $res->{data}{errors}[0]{error}, 'csrf', "$name: csrf error" );
    is_deeply( mutating(), [], "$name: nothing changed" );
}

$res = run_app( method => 'POST', params => { %unban, csrf => TOKEN }, actor => 'bad user', log => $log );
is( $res->{data}{errors}[0]{error}, 'bad_actor', 'bad actor refused' );
is_deeply( mutating(), [], 'nothing changed' );

# --- actions

$res = run_app( method => 'POST', params => { %unban, csrf => TOKEN }, log => $log );
is( $res->{code}, 303, 'unban redirects' );
is( $res->{location}, 'index.cgi?page=bans&notice=unban_ok&ip=203.0.113.47', 'redirect target' );
is_deeply( mutating(), [ [qw(panel unban 203.0.113.47 --actor root --json)] ], 'unban argv' );

$res = run_app( method => 'POST', referer => undef,
    params => { action => 'allow', page => 'bans', ip => '203.0.113.47', note => 'Office', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{location}, 'index.cgi?page=bans&notice=allow_ok&ip=203.0.113.47', 'allow from bans returns to bans' );
is_deeply( mutating(), [ [ qw(panel allow 203.0.113.47 --note Office --actor root --json) ] ], 'allow argv with note' );

$res = run_app( method => 'POST', params => { action => 'allow', ip => '2001:DB8::7', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{location}, 'index.cgi?page=allowlist&notice=allow_ok&ip=2001%3Adb8%3A%3A7', 'ipv6 normalised' );
is_deeply( mutating(), [ [qw(panel allow 2001:db8::7 --actor root --json)] ], 'no --note when empty' );

$res = run_app( method => 'POST', params => { action => 'disallow', ip => '198.51.100.4', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{code}, 303, 'disallow' );
is_deeply( mutating(), [ [qw(panel disallow 198.51.100.4 --actor root --json)] ], 'disallow argv' );

$res = run_app( method => 'POST', params => { action => 'scan', path => '/home/greenleaf/shop', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{location}, 'index.cgi?page=sites&notice=scan_ok&path=%2Fhome%2Fgreenleaf%2Fshop', 'scan redirect' );
is_deeply( mutating(), [ [qw(panel scan /home/greenleaf/shop --actor root --json)] ], 'scan argv' );

# --- validation happens before the agent is asked to change anything

for my $case (
    [ unban => { ip => '1.2.3.4; reboot' },           'invalid_ip' ],
    [ unban => { ip => '--actor' },                   'invalid_ip' ],
    [ allow => { ip => '192.0.2.5', note => "a\nb" }, 'invalid_note' ],
    [ allow => { ip => '192.0.2.5', note => '-x' },   'invalid_note' ],
    [ scan  => { path => '/etc' },                    'unknown_path' ],
    [ scan  => { path => '/home/greenleaf/shop/../../../root' }, 'unknown_path' ],
    [ reboot => { ip => '192.0.2.5' },                'bad_request' ],
  )
{
    my ( $action, $p, $err ) = @$case;
    $res = run_app( method => 'POST', params => { action => $action, %$p, confirm => 1, csrf => TOKEN }, log => $log );
    is( $res->{code}, 400, "$action $err: 400" );
    is( $res->{data}{errors}[0]{error}, $err, "$action: $err" );
    is_deeply( mutating(), [], "$action $err: agent not called" );
}

# --- errors from the agent are shown on the page

$res = run_app( method => 'POST', params => { action => 'unban', ip => '192.0.2.99', confirm => 1, csrf => TOKEN } );
is( $res->{code}, 200, 'agent error renders the page' );
is( $res->{data}{view}, 'bans', 'back on bans' );
is( $res->{data}{errors}[0]{error}, 'not_found', 'error code' );
is( $res->{data}{errors}[0]{action}, 'unban', 'action recorded' );

$res = run_app( method => 'POST', params => { action => 'allow', ip => '198.51.100.4', confirm => 1, csrf => TOKEN } );
is( $res->{data}{errors}[0]{error}, 'already_allowed', 'already allowed' );

# --- notices

$res = run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.47' } );
is_deeply( $res->{data}{notice}, { code => 'unban_ok', ip => '203.0.113.47' }, 'notice' );
$res = run_app( params => { page => 'bans', notice => 'unban_ok', ip => '<script>' } );
ok( !$res->{data}{notice}, 'notice with bad ip dropped' );
$res = run_app( params => { page => 'bans', notice => 'pwned', ip => '203.0.113.47' } );
ok( !$res->{data}{notice}, 'unknown notice dropped' );

done_testing;
