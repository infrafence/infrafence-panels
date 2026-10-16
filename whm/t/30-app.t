use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP ();
use Time::HiRes ();
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

# An agent that answers `status` with the given fields (and the real status
# fixture for the rest), for states the fixtures do not cover.
{
    package StatusAgent;
    sub new { my ( $c, %s ) = @_; bless { s => \%s, real => IFTest::mock_agent() }, $c }
    sub installed { 1 }
    sub call {
        my ( $self, $cmd, @a ) = @_;
        my $r = $self->{real}->call( $cmd, @a );
        return $cmd eq 'status' ? { %$r, %{ $self->{s} } } : $r;
    }
}

# --- pages

for my $page (qw(overview bans allowlist findings events coexistence sites)) {
    my $res = run_app( params => { page => $page } );
    is( $res->{code}, 200, "$page: 200" );
    is( $res->{template}, 'infrafence/main.tmpl', "$page: main template" );
    is( $res->{data}{view}, $page, "$page: view" );
    is_deeply( $res->{data}{errors}, [], "$page: no errors" );
    ok( !$res->{data}{list_error}, "$page: no list error" );
}

my $res = run_app( params => { page => '../../etc/passwd' } );
is( $res->{data}{view}, 'overview', 'unknown page falls back to overview' );

$res = run_app( log => $log );
is( $res->{data}{protection}, 'protected', 'protected' );
is( $res->{data}{counts}{bans}, 4, 'ban count from total' );
is( $res->{data}{counts}{findings}, 2, 'findings still detected (not quarantined)' );
is( $res->{data}{counts}{events}, 5, 'events in the last 24 h' );
ok( !defined $res->{data}{automode}, 'automode null' );
is_deeply( [ grep { $_->[1] ne 'status' } @{ calls() } ],
    [ [qw(panel bans --limit 1 --json)], [qw(panel findings --limit 500 --json)], [qw(panel events --since 24h --limit 500 --json)] ],
    'overview argv within the agent limits' );

for my $case (
    [ { monitor_mode => JSON::PP::true() } => 'monitor' ],
    [ { suspended => 1, monitor_mode => 1 } => 'suspended' ],
    [ { connected => 0 } => 'offline' ],
    [ { agent_running => 0 } => 'stopped' ],
  )
{
    $res = run_app( agent => StatusAgent->new( %{ $case->[0] } ) );
    is( $res->{data}{protection}, $case->[1], "state $case->[1]" );
}
is( InfraFence::WHM::App::_automode(undef), undef, 'automode null' );
is( InfraFence::WHM::App::_automode( { enabled => 1 } ), 'on', 'automode enabled' );
is( InfraFence::WHM::App::_automode( { enabled => 0, state => 'x' } ), 'off', 'automode disabled' );
is( InfraFence::WHM::App::_automode( { state => 'learning' } ), 'learning', 'automode state' );
is( InfraFence::WHM::App::_automode( {} ), 'unknown', 'automode unknown shape' );

$res = run_app( scenario => 'stopped' );
is( $res->{data}{protection}, 'stopped', 'stopped' );
ok( !$res->{data}{counts}, 'no counts while stopped' );

$res = run_app( params => { page => 'bans' }, scenario => 'stopped' );
is( $res->{data}{list_error}{error}, 'agent_not_running', 'list error while stopped' );
$res = run_app( params => { page => 'sites' }, scenario => 'stopped' );
ok( !$res->{data}{list_error}, 'sites still listed while stopped' );
is( $res->{data}{site_count}, 4, 'sites while stopped' );
ok( !defined $res->{data}{malware_scan_enabled}, 'scan setting unknown while stopped' );

$res = run_app( agent => mock_agent( bin => undef ) );
is( $res->{data}{view}, 'not_installed', 'not installed' );
is( $res->{data}{add_server_url}, 'https://infrafence.com/add-server', 'add server link' );
$res = run_app( agent => mock_agent( bin => undef ), method => 'POST',
    params => { action => 'unban', ip => '203.0.113.7', confirm => 1, csrf => TOKEN } );
is( $res->{data}{view}, 'not_installed', 'no actions without agent' );

$res = run_app( params => { page => 'bans', limit => '250' }, log => $log );
is( $res->{data}{limit}, 250, 'limit accepted' );
is_deeply( calls()->[-1], [qw(panel bans --limit 250 --json)], 'limit passed' );
for my $bad ( '1000', '5;id', '' ) {
    run_app( params => { page => 'bans', limit => $bad }, log => $log );
    is_deeply( calls()->[-1], [qw(panel bans --limit 500 --json)], "limit '$bad' ignored" );
}
$res = run_app( params => { page => 'bans' } );
is( $res->{data}{total}, 4, 'total' );
is( $res->{data}{monitor_mode}, 0, 'bans enforced' );
$res = run_app( params => { page => 'bans' }, scenario => 'hostile' );
is( $res->{data}{monitor_mode}, 1, 'monitor mode on bans' );

$res = run_app( params => { page => 'allowlist' } );
is_deeply( [ map { $_->{source} } @{ $res->{data}{entries} } ], [qw(panel dashboard dashboard)], 'allow list sources' );

$res = run_app( params => { page => 'findings', kind => 'malware' } );
is( scalar @{ $res->{data}{findings} }, 2, 'malware filter' );
is( $res->{data}{kind_count}{integrity}, 1, 'kind counts' );
is( $res->{data}{total}, 3, 'findings total' );

$res = run_app( params => { page => 'coexistence' } );
is( scalar @{ $res->{data}{tools} }, 5, 'tools' );
is( $res->{data}{mode}, 'coexist', 'mode' );
$res = run_app( params => { page => 'coexistence' }, scenario => 'empty' );
is_deeply( $res->{data}{tools}, [], 'no tools' );
is( $res->{data}{mode}, 'primary', 'primary mode' );

$res = run_app( params => { page => 'sites' } );
is_deeply( [ map { $_->{account} } @{ $res->{data}{accounts} } ], [qw(alice bob)], 'accounts grouped' );
is( $res->{data}{site_count}, 4, 'site count' );
is( $res->{data}{account_count}, 2, 'account count' );
is( run_app( params => { page => 'sites' }, scenario => 'restricted' )->{data}{account_count}, 2, 'sites without account not counted' );
is( $res->{data}{covered_count}, 3, 'covered count' );
is( $res->{data}{malware_scan_enabled}, 1, 'scheduled scans on' );

# The Overview's four agent calls share one deadline.
{
    local $InfraFence::WHM::App::OVERVIEW_DEADLINE = 2;
    my $t0 = Time::HiRes::time();
    $res = run_app( agent => mock_agent( fault => 'timeout', timeout => 10 ) );
    cmp_ok( Time::HiRes::time() - $t0, '<', 4, 'overview bounded by the shared deadline' );
    is( $res->{data}{status}{error}, 'timeout', 'status timed out' );
}

# --- confirmation step

$res = run_app( params => { page => 'bans', action => 'unban', ip => '203.0.113.7' }, log => $log );
is( $res->{data}{view}, 'confirm', 'GET shows confirmation' );
is( $res->{data}{act}{ip}, '203.0.113.7', 'confirm ip' );
is_deeply( mutating(), [], 'GET changes nothing' );

for my $case (
    [ '203.0.113.7',   'local',    '2026-10-17T12:00:00Z', 'expiry within 30 days' ],
    [ '198.51.100.23', 'automode', '2026-10-16T16:00:00Z', 'automode ban' ],
    [ '192.0.2.50',    'network',  '2026-10-18T00:00:00Z', 'network ban' ],
    [ '198.51.100.9',  'manual',   '2026-11-15T12:01:00Z', 'permanent ban: 30 days from now' ],
  )
{
    my ( $ip, $source, $until, $name ) = @$case;
    $res = run_app( params => { page => 'bans', action => 'unban', ip => $ip } );
    is( $res->{data}{act}{source}, $source, "confirm: source, $name" );
    is( $res->{data}{act}{until},  $until,  "confirm: lifted until, $name" );
}
$res = run_app( params => { page => 'bans', action => 'unban', ip => '192.0.2.99' } );
is( $res->{data}{view}, 'confirm', 'unknown ban still confirms (the agent decides)' );
ok( !$res->{data}{act}{until}, 'no date for an unknown ban' );

$res = run_app( method => 'POST', params => { action => 'unban', ip => '203.0.113.7', csrf => TOKEN }, log => $log );
is( $res->{data}{view}, 'confirm', 'POST without confirm=1 shows confirmation' );
is_deeply( mutating(), [], 'nothing changed' );

$res = run_app( params => { action => 'unban', ip => '203.0.113.7', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{data}{view}, 'confirm', 'GET with confirm=1 does not act' );
is_deeply( mutating(), [], 'nothing changed' );

$res = run_app( params => { action => 'scan', path => '/home/alice/public_html' } );
is_deeply( $res->{data}{act}{domains}, [qw(alice.example alice.example.net)], 'every domain on the document root' );
is( $res->{data}{act}{account}, 'alice', 'account' );

# --- CSRF

my %unban = ( action => 'unban', ip => '203.0.113.7', confirm => 1 );
for my $case (
    [ 'missing csrf',     { params => {%unban} } ],
    [ 'wrong csrf',       { params => { %unban, csrf => '/cpsess0000000000' } } ],
    [ 'no session token', { params => { %unban, csrf => '' }, token => '' } ],
    [ 'foreign referer',  { params => { %unban, csrf => TOKEN }, referer => 'https://evil.example/x' } ],
    [ 'foreign origin',   { params => { %unban, csrf => TOKEN }, origin => 'https://evil.example' } ],
  )
{
    my ( $name, $o ) = @$case;
    $res = run_app( method => 'POST', log => $log, %$o );
    is( $res->{code}, 403, "$name: 403" );
    is( $res->{data}{errors}[0]{error}, 'csrf', "$name: csrf error" );
    is_deeply( mutating(), [], "$name: nothing changed" );
}

$res = run_app( method => 'POST', params => { %unban, csrf => TOKEN }, actor => 'bad user', log => $log );
is( $res->{data}{errors}[0]{error}, 'invalid_actor', 'bad actor refused' );
is_deeply( mutating(), [], 'nothing changed' );

# --- actions

$res = run_app( method => 'POST', params => { %unban, csrf => TOKEN }, log => $log );
is( $res->{code}, 303, 'unban redirects' );
is( $res->{location}, 'index.cgi?page=bans&notice=unban_ok&ip=203.0.113.7&until=2026-10-17T12%3A00%3A00Z&source=local', 'redirect carries the end of the lift and the source' );
is_deeply( mutating(), [ [qw(panel unban 203.0.113.7 --actor root --json)] ], 'unban argv' );

$res = run_app( method => 'POST', referer => undef,
    params => { action => 'allow', page => 'bans', ip => '203.0.113.7', note => 'Office', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{location}, 'index.cgi?page=bans&notice=allow_ok&ip=203.0.113.7&banned=1', 'allow a banned address' );
is_deeply( mutating(), [ [qw(panel allow 203.0.113.7 --note Office --actor root --json)] ], 'allow argv with note' );

$res = run_app( method => 'POST', params => { action => 'allow', ip => '2001:DB8::7', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{location}, 'index.cgi?page=allowlist&notice=allow_ok&ip=2001%3Adb8%3A%3A7', 'ipv6 normalised' );
is_deeply( mutating(), [ [qw(panel allow 2001:db8::7 --actor root --json)] ], 'no --note when empty' );

$res = run_app( method => 'POST', params => { action => 'allow', ip => '198.51.100.4', confirm => 1, csrf => TOKEN } );
is( $res->{location}, 'index.cgi?page=allowlist&notice=allow_already&ip=198.51.100.4', 'already allowed' );
$res = run_app( method => 'POST', params => { action => 'allow', ip => '192.0.2.1', confirm => 1, csrf => TOKEN } );
is( $res->{location}, 'index.cgi?page=allowlist&notice=allow_already&ip=192.0.2.1&own=1', 'own address flagged' );
$res = run_app( method => 'POST', params => { action => 'allow', ip => '127.0.0.1', confirm => 1, csrf => TOKEN } );
is( $res->{data}{errors}[0]{error}, 'loopback_address', 'loopback refused by the agent' );

$res = run_app( method => 'POST', scenario => 'restricted', log => $log,
    params => { action => 'scan', path => '/var/www/shared', confirm => 1, csrf => TOKEN } );
is( $res->{code}, 400, 'not scannable: 400' );
is( $res->{data}{errors}[0]{error}, 'not_scannable', 'not scannable checked before asking the agent' );
is_deeply( mutating(), [], 'not scannable: agent not called' );

$res = run_app( method => 'POST', params => { action => 'disallow', ip => '198.51.100.4', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{location}, 'index.cgi?page=allowlist&notice=disallow_ok&ip=198.51.100.4', 'disallow' );
is_deeply( mutating(), [ [qw(panel disallow 198.51.100.4 --actor root --json)] ], 'disallow argv' );

$res = run_app( method => 'POST', params => { action => 'scan', path => '/home/alice/public_html/blog', confirm => 1, csrf => TOKEN }, log => $log );
is( $res->{location}, 'index.cgi?page=sites&notice=scan_ok&path=%2Fhome%2Falice%2Fpublic_html%2Fblog', 'scan redirect' );
is_deeply( mutating(), [ [qw(panel scan /home/alice/public_html/blog --actor root --json)] ], 'scan argv' );

is( InfraFence::WHM::App::_notice_query( 'unban', { ip => '192.0.2.1' },
        { ok => 1, ip => '192.0.2.1', reported => 0, threat_feed => 1, firewall_pending => 1, lifted_until => '2026-11-15T12:00:00.5+00:00' } ),
    'notice=unban_ok&ip=192.0.2.1&until=2026-11-15T12%3A00%3A00.5%2B00%3A00&unreported=1&threat_feed=1&pending=1', 'reply flags carried to the notice' );
is( InfraFence::WHM::App::_notice_query( 'unban', { ip => '192.0.2.1' }, { ok => 1, ip => '192.0.2.1', lifted_until => '<b>' } ),
    'notice=unban_ok&ip=192.0.2.1', 'invalid lifted_until dropped' );
is( InfraFence::WHM::App::_notice_query( 'scan', { path => '/home/a/www' }, { ok => 1, path => '/home/a/real' } ),
    'notice=scan_ok&path=%2Fhome%2Fa%2Freal', 'scan notice shows the resolved path' );

# --- validation happens before the agent is asked to change anything

for my $case (
    [ unban  => { ip => '1.2.3.4; reboot' },             'invalid_ip' ],
    [ unban  => { ip => '--actor' },                     'invalid_ip' ],
    [ allow  => { ip => '192.0.2.5', note => "a\nb" },   'invalid_note' ],
    [ allow  => { ip => '192.0.2.5', note => '-x' },     'invalid_note' ],
    [ allow  => { ip => '192.0.2.5', note => 'x' x 201 }, 'invalid_note' ],
    [ scan   => { path => '/etc' },                      'not_a_document_root' ],
    [ scan   => { path => '/home/alice/public_html/../../../root' }, 'not_a_document_root' ],
    [ reboot => { ip => '192.0.2.5' },                   'unknown_action' ],
  )
{
    my ( $action, $p, $err ) = @$case;
    $res = run_app( method => 'POST', params => { action => $action, %$p, confirm => 1, csrf => TOKEN }, log => $log );
    is( $res->{code}, 400, "$action $err: 400" );
    is( $res->{data}{errors}[0]{error}, $err, "$action: $err" );
    is_deeply( mutating(), [], "$action $err: agent not called" );
}

# --- errors from the agent are shown on the page

for my $case (
    [ unban    => '192.0.2.99',   'not_banned',           'bans' ],
    [ disallow => '203.0.113.20', 'managed_by_dashboard', 'allowlist' ],
    [ disallow => '192.0.2.5',    'not_in_allowlist',     'allowlist' ],
  )
{
    my ( $action, $ip, $err, $page ) = @$case;
    $res = run_app( method => 'POST', params => { action => $action, ip => $ip, confirm => 1, csrf => TOKEN } );
    is( $res->{code}, 200, "$err: page rendered" );
    is( $res->{data}{view}, $page, "$err: back on $page" );
    is( $res->{data}{errors}[0]{error}, $err, "$err: error code" );
    is( $res->{data}{errors}[0]{action}, $action, "$err: action recorded" );
}

$res = run_app( method => 'POST', params => { page => 'allowlist', action => 'disallow', ip => '203.0.113.20', confirm => 1, csrf => TOKEN } );
ok( !defined $res->{data}{form}{ip}, 'no pre-fill after a failed action' );

# --- notices

$res = run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.7', unreported => 1, threat_feed => 1, pending => 'x', until => '2026-10-17T12:00:00Z' } );
is_deeply( $res->{data}{notice}, { code => 'unban_ok', ip => '203.0.113.7', unreported => 1, threat_feed => 1, until => '2026-10-17T12:00:00Z' }, 'notice with flags' );
$res = run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.7', until => '"><script>' } );
ok( !exists $res->{data}{notice}{until}, 'bad until dropped' );
$res = run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.7', source => 'network' } );
is( $res->{data}{notice}{source}, 'network', 'source kept' );
$res = run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.7', source => '<b>' } );
ok( !exists $res->{data}{notice}{source}, 'unknown source dropped' );
$res = run_app( params => { page => 'allowlist', ip => '192.0.2.8' } );
is( $res->{data}{form}{ip}, '192.0.2.8', 'form pre-filled from ?ip=' );
$res = run_app( params => { page => 'allowlist', notice => 'allow_ok', ip => '192.0.2.8' } );
ok( !defined $res->{data}{form}{ip}, 'but not after a notice' );
$res = run_app( params => { page => 'bans', notice => 'unban_ok', ip => '<script>' } );
ok( !$res->{data}{notice}, 'notice with bad ip dropped' );
$res = run_app( params => { page => 'bans', notice => 'pwned', ip => '203.0.113.7' } );
ok( !$res->{data}{notice}, 'unknown notice dropped' );

done_testing;
