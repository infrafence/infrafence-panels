use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP ();
use lib "$FindBin::Bin/lib";
use IFTest qw(mock_agent $ROOT);

my $dir = tempdir( CLEANUP => 1 );
my $log = "$dir/argv.log";

sub last_argv {
    open my $fh, '<', $log or return;
    my @l = <$fh>;
    return JSON::PP->new->decode( $l[-1] );
}

my $a = mock_agent( log => $log );
ok( $a->installed, 'mock is installed' );

my $r = $a->call('status');
ok( $r->{ok}, 'status ok' );
is( $r->{version}, '1.0.23', 'version' );
is( $r->{agent_id}, 42, 'agent id' );
ok( !defined $r->{automode}, 'null stays undef' );
is( $r->{agent_running}, 1, 'JSON true becomes 1' );
is_deeply( last_argv(), [qw(panel status --json)], 'argv for status' );

$r = $a->call( 'bans', '--limit', '3' );
is( scalar @{ $r->{bans} }, 3, 'limit applied' );
is( $r->{total}, 4, 'total kept' );

# Arguments reach the agent as separate argv entries, untouched by any shell.
my $weird = q{/home/a b/$(touch /tmp/pwned);`id`|x'"};
$a->call( 'scan', $weird, '--actor', 'root' );
is_deeply( last_argv(), [ 'panel', 'scan', $weird, '--actor', 'root', '--json' ], 'argv passed verbatim' );

$r = $a->call( 'unban', '192.0.2.99', '--actor', 'root' );
ok( !$r->{ok}, 'error reply' );
is( $r->{error}, 'not_banned', 'error code kept' );
is( $r->{agent_running}, 1, 'agent_running kept' );
like( $r->{message}, qr/192\.0\.2\.99/, 'message kept' );

$r = $a->call( 'unban', 'x', '--actor', 'root' );
is( $r->{error}, 'invalid_ip', 'refused before asking the agent' );
ok( !exists $r->{agent_running}, 'no agent_running in that case' );

$r = $a->call( 'unban', '203.0.113.7', '--actor', 'root' );
is( $r->{scope}, 'server', 'unban is local to this server' );
is( $r->{source}, 'local', 'source of the lifted ban' );

my $stopped = mock_agent( scenario => 'stopped' );
$r = $stopped->call('bans');
is( $r->{error}, 'agent_not_running', 'stopped agent' );
is( $r->{agent_running}, 0, 'agent_running false' );
$r = $stopped->call('status');
ok( $r->{ok} && !$r->{agent_running}, 'status still answers' );
ok( !defined $r->{plan}, 'unknown values are null' );
ok( $stopped->call('sites')->{ok}, 'sites still answers' );
ok( $stopped->call('coexistence')->{ok}, 'coexistence still answers' );

$r = mock_agent( fault => 'garbage' )->call('status');
is( $r->{error}, 'bad_reply', 'non-JSON output' );

$r = mock_agent( fault => 'mismatch' )->call('status');
is( $r->{error}, 'bad_reply', 'ok:true with non-zero exit' );

$r = mock_agent( fault => 'stderr' )->call('status');
ok( $r->{ok}, 'stderr is ignored' );

my $t0 = time;
$r = mock_agent( fault => 'timeout', timeout => 2 )->call('status');
is( $r->{error}, 'timeout', 'timeout' );
cmp_ok( time - $t0, '<=', 6, 'timeout honoured' );

my $none = mock_agent( bin => undef );
ok( !$none->installed, 'missing binary' );
is( $none->call('status')->{error}, 'not_installed', 'not_installed' );

ok( !mock_agent( bin => "$dir/nope" )->installed, 'nonexistent path' );

# Discovery only looks at the fixed list of paths.
my $found = InfraFence::WHM::Agent->new( search => [ "$dir/nope", "$ROOT/dev/mock-agent" ] );
is( $found->bin, "$ROOT/dev/mock-agent", 'search path' );

# Strict ownership: the mock belongs to the test user, so it is refused unless
# the test runs as root on a root-owned copy.
if ( $> != 0 ) {
    is( mock_agent( strict_owner => 1 )->call('status')->{error}, 'agent_untrusted', 'non-root owner refused' );
}
else {
    my $copy = "$dir/agent";
    system( 'cp', "$ROOT/dev/mock-agent", $copy ) == 0 or die;
    chown 0, 0, $copy;
    chmod 0755, $copy;
    my $env = { MOCK_AGENT_FIXTURES => "$ROOT/dev/fixtures" };
    my $ok  = InfraFence::WHM::Agent->new( bin => $copy, env => $env );
    ok( $ok->call('status')->{ok}, 'root-owned binary accepted' );
    chmod 0777, $copy;
    is( $ok->call('status')->{error}, 'agent_untrusted', 'world-writable binary refused' );
    chown 1, 1, $copy;
    chmod 0755, $copy;
    is( $ok->call('status')->{error}, 'agent_untrusted', 'non-root owner refused' );
}

# The child gets a clean environment.
{
    local $ENV{IFN_SECRET} = 'leak';
    my $probe = "$dir/probe";
    open my $fh, '>', $probe or die;
    print {$fh} qq{#!/bin/sh\nprintf '{"ok":true,"env":"%s","path":"%s"}' "\$IFN_SECRET" "\$PATH"\n};
    close $fh;
    chmod 0755, $probe;
    my $r = InfraFence::WHM::Agent->new( bin => $probe, strict_owner => 0 )->call('status');
    is( $r->{env}, '', 'environment not inherited' );
    like( $r->{path}, qr{\A/usr/local/sbin:}, 'fixed PATH' );
}

done_testing;
