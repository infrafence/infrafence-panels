use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use IFTest qw(run_app render);
use InfraFence::WHM::App ();

# The plugin is updated from the dashboard (Panel plugins), not with the
# agent. Agent 1.0.35 and later say which release is the latest
# (`plugin_latest` of `panel status`): when it is newer than this plugin,
# every page of an entitled organization says so. Older agents: nothing.

my $have_tt = eval { require Template; 1 };
my $V = $InfraFence::WHM::App::VERSION;

# --- the rule

my %s = ( ok => 1, agent_running => 1 );
is( InfraFence::WHM::App::plugin_update( { %s, plugin_latest => '99.0.0' } ), '99.0.0', 'newer: shown' );
is( InfraFence::WHM::App::plugin_update( { %s, plugin_latest => $V } ), undef, 'the same version: nothing' );
is( InfraFence::WHM::App::plugin_update( { %s, plugin_latest => '0.9.9' } ), undef, 'older: nothing' );
is( InfraFence::WHM::App::plugin_update( { %s } ), undef, 'an older agent without the field: nothing' );
is( InfraFence::WHM::App::plugin_update( { %s, plugin_latest => undef } ), undef, 'null: nothing' );
is( InfraFence::WHM::App::plugin_update( { %s, plugin_latest => $_ } ), undef, "not a version: '$_'" )
  for ( '', 'latest', '1.0.4<script>', '1.0.4 ', 'v1.0.4', '1.0.4-rc1', '1' );
is( InfraFence::WHM::App::plugin_update( { %s, plugin_latest => { v => 1 } } ), undef, 'not text: nothing' );
is( InfraFence::WHM::App::plugin_update( { ok => 1, agent_running => 0, plugin_latest => '99.0.0' } ), undef, 'agent not running: nothing' );
is( InfraFence::WHM::App::plugin_update(undef), undef, 'no status: nothing' );

is( InfraFence::WHM::App::version_cmp( @$_[ 0, 1 ] ), $_->[2], "compare $_->[0] $_->[1]" ) for (
    [ '1.0.10', '1.0.9', 1 ], [ '1.0.9', '1.0.10', -1 ], [ '1.0.3', '1.0.3', 0 ],
    [ '1.1', '1.0.9', 1 ], [ '1.0', '1.0.0', 0 ], [ '2.0.0', '10.0.0', -1 ],
);

# --- every page, entitled organizations only

my $newer = '99.0.0';
for my $page (qw(overview bans allowlist findings events coexistence sites)) {
    my $res = run_app( plugin_latest => $newer, params => { page => $page } );
    is( $res->{data}{plugin_update}, $newer, "$page: the newer release" );
}
is( run_app( plugin_latest => $newer, params => { page => 'bans', action => 'unban', ip => '203.0.113.7' } )->{data}{plugin_update},
    $newer, 'a confirmation page too' );
is( run_app( plugin_latest => $V )->{data}{plugin_update}, undef, 'up to date: nothing' );
is( run_app()->{data}{plugin_update}, undef, 'an older agent: nothing' );
for my $gate (qw(starter unpaid unknown)) {
    for my $g (qw(old new)) {
        is( run_app( plugin_latest => $newer, scenario => $gate, gate => $g )->{data}{plugin_update}, undef, "$gate ($g agent): nothing" );
    }
}
is( run_app( plugin_latest => $newer, scenario => 'stopped' )->{data}{plugin_update}, undef, 'agent stopped: nothing' );
# The plan changed after `status`: nothing of the earlier answer is shown.
is( run_app( plugin_latest => $newer, gate => 'new', refuse => 'plan_required', params => { page => 'bans' } )->{data}{plugin_update},
    undef, 'refused after status: nothing' );

SKIP: {
    skip 'Template Toolkit not installed', 1 unless $have_tt;

    my $html = render( run_app( plugin_latest => $newer ) );
    like( $html, qr/class="alert alert-info ifn-update" role="status">\s*A new version of the plugin is available \(99\.0\.0\)\./, 'the notice' );
    like( $html, qr{<a href="https://infrafence\.com/panels" target="_blank" rel="noopener noreferrer">Update it from the InfraFence dashboard › Panel plugins <span aria-hidden="true">&#8599;</span></a>}, 'the link to Panel plugins' );
    like( $html, qr{<dt>Agent version</dt><dd>1\.0\.23</dd>}, 'agent version row' );
    like( $html, qr{<dt>Plugin version</dt><dd>\Q$V\E\s*<span class="label label-info">99\.0\.0 available</span></dd>}, 'plugin version row with the newer release' );

    $html = render( run_app( plugin_latest => $V ) );
    unlike( $html, qr/ifn-update/, 'up to date: no notice' );
    like( $html, qr{<dt>Plugin version</dt><dd>\Q$V\E</dd>}, 'plugin version row' );

    $html = render( run_app() );
    unlike( $html, qr/ifn-update/, 'older agent: no notice' );
    like( $html, qr{<dt>Agent version</dt><dd>1\.0\.23</dd>.*<dt>Plugin version</dt><dd>\Q$V\E</dd>}s, 'older agent: both versions anyway' );

    $html = render( run_app( plugin_latest => $newer, scenario => 'starter' ) );
    unlike( $html, qr/ifn-update/, 'Starter: no notice' );
    unlike( $html, qr/99\.0\.0/, 'Starter: the release is not shown' );

    $html = render( run_app( plugin_latest => $newer, lang => 'it', params => { page => 'bans' } ) );
    like( $html, qr/È disponibile una nuova versione del plugin \(99\.0\.0\)\./, 'italian notice' );
    like( $html, qr/Aggiornalo dalla dashboard di InfraFence › Plugin dei pannelli/, 'italian link' );

    # A hostile value never reaches the page.
    $html = render( run_app( plugin_latest => '1.0.4"><script>alert(1)</script>' ) );
    unlike( $html, qr/<script>alert/, 'hostile plugin_latest not printed' );
}

done_testing;
