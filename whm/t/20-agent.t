use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use Time::HiRes ();
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

# Strict ownership: the binary and every directory above it must be owned by
# root and not writable by group or others. Only testable as root.
if ( $> != 0 ) {
    is( mock_agent( strict_owner => 1 )->call('status')->{error}, 'agent_untrusted', 'non-root owner refused' );
}
else {
    require File::Path;
    my $base = '/opt/ifn-agent-test';
    File::Path::rmtree($base);
    File::Path::make_path( "$base/bin", { mode => 0755 } );
    chmod 0755, '/opt', $base, "$base/bin";
    my $bin = "$base/bin/infrafence-agent";
    open my $fh, '>', $bin or die $!;
    print {$fh} qq{#!/bin/sh\nprintf '{"ok":true,"self":"%s"}' "\$0"\n};
    close $fh;
    chmod 0755, $bin;
    my $agent = sub { InfraFence::WHM::Agent->new( bin => $_[0] || $bin ) };

    ok( $agent->()->call('status')->{ok}, 'root-owned binary in root-owned directories accepted' );

    chmod 0777, $bin;
    is( $agent->()->call('status')->{error}, 'agent_untrusted', 'world-writable binary refused' );
    chmod 0775, $bin;
    is( $agent->()->call('status')->{error}, 'agent_untrusted', 'group-writable binary refused' );
    chmod 0755, $bin;
    chown 1, 1, $bin;
    is( $agent->()->call('status')->{error}, 'agent_untrusted', 'binary not owned by root refused' );
    chown 0, 0, $bin;

    for my $dir ( $base, "$base/bin" ) {
        chmod 0777, $dir;
        is( $agent->()->call('status')->{error}, 'agent_untrusted', "world-writable $dir refused" );
        chmod 0755, $dir;
        chown 1, 1, $dir;
        is( $agent->()->call('status')->{error}, 'agent_untrusted', "$dir not owned by root refused" );
        chown 0, 0, $dir;
    }
    ok( $agent->()->call('status')->{ok}, 'accepted again once fixed' );

    # A symlink is resolved: what matters is the file it points to.
    my $loose = File::Temp::tempdir( CLEANUP => 1 );    # under /tmp (mode 1777)
    system( 'cp', $bin, "$loose/agent" ) == 0 or die;
    chmod 0755, "$loose/agent";
    symlink "$loose/agent", "$base/bin/link" or die $!;
    is( $agent->("$base/bin/link")->call('status')->{error}, 'agent_untrusted', 'symlink to a file under /tmp refused' );
    unlink "$base/bin/link";
    is( $agent->("$loose/agent")->call('status')->{error}, 'agent_untrusted', 'binary under sticky /tmp refused' );

    symlink $bin, "$base/link" or die $!;
    my $r = $agent->("$base/link")->call('status');
    ok( $r->{ok}, 'symlink to a trusted file accepted' );
    is( $r->{self}, $bin, 'the resolved file is the one executed' );

    symlink "$base/nowhere", "$base/dangling" or die $!;
    is( $agent->("$base/dangling")->call('status')->{error}, 'not_installed', 'dangling symlink' );
    File::Path::rmtree($base);
}

# One deadline shared by several calls.
{
    my $slow = mock_agent( fault => 'timeout', timeout => 10 );
    my $t0   = Time::HiRes::time();
    $slow->deadline( $t0 + 2 );
    is( $slow->call('status')->{error}, 'timeout', 'deadline ends the first call' );
    is( $slow->call('bans')->{error},   'timeout', 'later calls fail at once' );
    cmp_ok( Time::HiRes::time() - $t0, '<', 4, 'both within the shared deadline' );
    $slow->deadline(undef);
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
