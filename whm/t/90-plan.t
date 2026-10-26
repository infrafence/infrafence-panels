use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP ();
use lib "$FindBin::Bin/lib";
use IFTest qw(run_app render TOKEN);
use InfraFence::WHM::App ();

# The plugin is part of the Basic, Pro and AutoMode plans. Starter, an unpaid
# subscription (protection switched off) and an unknown plan get no data and
# no actions, from an agent that gates (1.0.34, MOCK_AGENT_GATE=new) or not.

my $have_tt = eval { require Template; 1 };

my $dir = tempdir( CLEANUP => 1 );
my $log = "$dir/argv.log";

sub calls {
    open my $fh, '<', $log or return [];
    my @c = map { JSON::PP->new->decode($_) } <$fh>;
    close $fh;
    unlink $log;
    return \@c;
}
sub commands { [ map { $_->[1] } @{ calls() } ] }

my @PAGES = qw(overview bans allowlist findings events coexistence sites);

# --- the rule

my %base = ( ok => 1, agent_running => 1 );
for my $case (
    [ { plan => 'basic' },                              'ok' ],
    [ { plan => 'pro', protection => 'active' },        'ok' ],
    [ { plan => 'automode', protection => 'refused' },  'ok' ],
    [ { plan => 'starter' },                            'plan_required' ],
    [ { plan => 'free' },                               'plan_required' ],
    [ { plan => 'enterprise' },                         'plan_required' ],
    [ { plan => 'starter', protection => 'disabled' },  'plan_required' ],
    [ { plan => 'basic', protection => 'disabled' },    'unpaid' ],
    [ { plan => undef, protection => 'disabled' },      'unpaid' ],
    [ { plan => undef },                                'unknown' ],
    [ { plan => '' },                                   'unknown' ],
    [ { plan => { x => 1 } },                           'unknown' ],
    [ { plan => 'basic', entitled => 0 },               'unknown' ],
    [ { plan => 'basic', entitlement => 'unpaid' },     'unpaid' ],
    [ { plan => 'starter', entitlement => 'ok' },       'ok' ],
    [ { plan => 'starter', entitlement => 'weird' },    'plan_required' ],
    [ { plan => 'basic', entitlement => 'weird' },      'ok' ],
  )
{
    my ( $s, $want ) = @$case;
    is( InfraFence::WHM::App::entitlement( { %base, %$s } ), $want, 'entitlement ' . JSON::PP->new->canonical->allow_nonref->encode($s) );
}
is( InfraFence::WHM::App::entitlement( { ok => 1, agent_running => 0, plan => 'pro' } ), 'unknown', 'agent not running: unknown' );
is( InfraFence::WHM::App::entitlement( { ok => 0, error => 'timeout' } ), 'unknown', 'no status: unknown' );
is( InfraFence::WHM::App::entitlement(undef), 'unknown', 'nothing: unknown' );

# --- paid plans: everything as before

for my $o ( {}, { scenario => 'paid' }, { scenario => 'paid', gate => 'new' } ) {
    my $name = join( ' ', %$o ) || 'default';
    my $res = run_app( %$o, log => $log );
    ok( !$res->{data}{gate}, "$name: entitled" );
    is( $res->{data}{counts}{bans}, 4, "$name: figures" );
    is_deeply( commands(), [qw(status bans findings events map score)], "$name: data asked" );
}

# --- not entitled: no data command, zeros, empty lists

for my $gate (qw(old new)) {
    for my $case ( [ starter => 'plan_required' ], [ unpaid => 'unpaid' ], [ unknown => 'unknown' ] ) {
        my ( $scenario, $code ) = @$case;
        my $name = "$scenario ($gate agent)";
        for my $page (@PAGES) {
            my $res = run_app( scenario => $scenario, gate => $gate, params => { page => $page }, log => $log );
            is( $res->{code}, 200, "$name $page: 200" );
            is( $res->{data}{view}, $page, "$name $page: view" );
            is( $res->{data}{gate}, $code, "$name $page: $code" );
            is_deeply( commands(), ['status'], "$name $page: only status asked" );
            ok( !$res->{data}{list_error} && !@{ $res->{data}{errors} }, "$name $page: no error shown" );
        }
        my $res = run_app( scenario => $scenario, gate => $gate );
        is_deeply( $res->{data}{counts}, { attacks => 0, critical => 0, bans => 0, findings => 0, events => 0, warning => 0 }, "$name: all figures 0" );
        is( $res->{data}{map}{state}, 'empty', "$name: empty map" );
        is( $res->{data}{map}{total}, 0, "$name: no attacks on the map" );
        is( $res->{data}{score}{state}, 'gated', "$name: no score" );
        ok( !$res->{data}{verdict}, "$name: no verdict" );
        is_deeply( $res->{data}{attention}{events}, [], "$name: nothing needs attention" );
        ok( !$res->{data}{attention}{resolved}, "$name: nothing resolved listed" );
        is( run_app( scenario => $scenario, gate => $gate, params => { range => '7d' } )->{data}{map}{range}, '7d', "$name: 7-day map" );
    }
}
is( run_app( scenario => 'unpaid' )->{data}{protection}, 'disabled', 'unpaid: protection off' );

# Resolved problems with an entitled agent 1.0.34 (gate new) and when the
# plan changes after `status` (every other command refused).
my $resolved = run_app( scenario => 'resolved', gate => 'new' );
ok( !$resolved->{data}{gate}, 'resolved, entitled: not gated' );
is( $resolved->{data}{attention}{resolved}{n}, 4, 'resolved, entitled: resolved problems listed' );
is( $resolved->{data}{counts}{critical}, 1, 'resolved, entitled: open critical only' );
$resolved = run_app( scenario => 'resolved', gate => 'new', refuse => 'plan_required', params => { page => 'events', state => 'resolved' } );
is( $resolved->{data}{gate}, 'plan_required', 'resolved, refused later: gated' );
is_deeply( $resolved->{data}{events}, [], 'resolved, refused later: no events' );

# --- actions are refused before the agent is asked, a forged POST included

my %post = ( method => 'POST', log => $log );
for my $scenario (qw(starter unpaid unknown)) {
    for my $act (
        [ unban    => { ip => '203.0.113.7' },              'bans' ],
        [ allow    => { ip => '192.0.2.5', note => 'x' },   'allowlist' ],
        [ disallow => { ip => '198.51.100.4' },             'allowlist' ],
        [ scan     => { path => '/home/alice/public_html' }, 'sites' ],
        [ reboot   => { ip => '192.0.2.5' },                'overview' ],
      )
    {
        my ( $name, $args, $page ) = @$act;
        my $res = run_app( %post, scenario => $scenario, params => { action => $name, %$args, confirm => 1, csrf => TOKEN } );
        is( $res->{code}, 403, "$scenario: forged $name POST refused" );
        is( $res->{data}{view}, $page, "$scenario: $name back on $page" );
        is_deeply( commands(), ['status'], "$scenario: $name never reached the agent" );
        $res = run_app( scenario => $scenario, params => { action => $name, %$args }, log => $log );
        is( $res->{code}, 403, "$scenario: no confirmation page for $name" );
        is_deeply( commands(), ['status'], "$scenario: $name confirmation asked nothing" );
    }
}
# The language can still be changed.
{
    require InfraFence::WHM::Prefs;
    my $prefs = InfraFence::WHM::Prefs->new( dir => "$dir/prefs" );
    my $res = run_app( %post, scenario => 'starter', prefs => $prefs, params => { action => 'language', lang => 'it', csrf => TOKEN } );
    is( $res->{code}, 303, 'starter: language still changed' );
}

# --- an agent that refuses after `status` (agent 1.0.34, the plan just changed)

for my $code (qw(plan_required unpaid unknown)) {
    my $res = run_app( scenario => 'paid', refuse => $code, log => $log );
    is( $res->{data}{gate}, $code, "refused $code: overview gated" );
    is_deeply( commands(), [qw(status bans)], "refused $code: no command after the refusal" );
    is( $res->{data}{counts}{bans}, 0, "refused $code: figures 0" );
    for my $page (qw(bans allowlist findings events coexistence sites)) {
        $res = run_app( scenario => 'paid', refuse => $code, params => { page => $page } );
        is( $res->{data}{gate}, $code, "refused $code: $page gated" );
        ok( !$res->{data}{list_error} && !@{ $res->{data}{errors} }, "refused $code: $page shows no error" );
    }
    $res = run_app( %post, scenario => 'paid', refuse => $code, params => { action => 'unban', ip => '203.0.113.7', confirm => 1, csrf => TOKEN } );
    is( $res->{code}, 403, "refused $code: unban refused" );
    is( $res->{data}{gate}, $code, "refused $code: unban page gated" );
    is( $res->{data}{view}, 'bans', "refused $code: back on bans" );
    is_deeply( commands(), [qw(status unban)], "refused $code: the agent refused the unban" );
    $res = run_app( %post, scenario => 'paid', refuse => $code, params => { action => 'scan', path => '/home/alice/public_html', confirm => 1, csrf => TOKEN } );
    is_deeply( commands(), [qw(status sites)], "refused $code: scan stopped at the site list" );
    is( $res->{data}{gate}, $code, "refused $code: scan gated" );
}
# Only the agent's own codes gate the plugin: an error without a code (which
# the plugin reports as "unspecified") is shown as an error.
{
    package NoCodeAgent;
    sub new { bless { real => IFTest::mock_agent() }, shift }
    sub installed { 1 }
    sub call {
        my ( $self, $cmd, @a ) = @_;
        return $cmd eq 'status' ? $self->{real}->call($cmd) : { ok => 0, error => 'unspecified', message => '' };
    }
}
my $res = run_app( agent => NoCodeAgent->new, params => { page => 'bans' } );
ok( !$res->{data}{gate}, 'error without a code: not gated' );
is( $res->{data}{list_error}{error}, 'unspecified', 'error without a code: shown' );

# --- what the pages show

SKIP: {
    skip 'Template Toolkit not installed', 1 unless $have_tt;

    my %text = (
        plan_required => qr{The InfraFence plugin is included in the Basic, Pro and AutoMode plans\.</strong>\s*Your organization is on the Starter plan},
        unpaid        => qr{Your InfraFence subscription is not active: the plugin shows no data until it is\.</strong>},
        unknown       => qr{Waiting for the InfraFence dashboard</strong>},
    );
    for my $case ( [ starter => 'plan_required' ], [ unpaid => 'unpaid' ], [ unknown => 'unknown' ] ) {
        my ( $scenario, $code ) = @$case;
        for my $page (@PAGES) {
            my $html = render( run_app( scenario => $scenario, params => { page => $page } ) );
            like( $html, $text{$code}, "$scenario $page: banner" );
            like( $html, qr/class="ifn-empty"><p>No data is shown while the plugin is not active/, "$scenario $page: no data" ) unless $page eq 'overview';
            unlike( $html, qr/action=(?:unban|allow|disallow|scan)&amp;/, "$scenario $page: no action links" );
        }
        my $html = render( run_app( scenario => $scenario ) );
        my @figures = $html =~ m{<span class="ifn-figure-n">([^<]*)</span>}g;
        is_deeply( \@figures, [ (0) x 4 ], "$scenario: four figures at 0" );
        like( $html, qr/class="ifn-map-svg"/, "$scenario: map drawn" );
        like( $html, qr/ifn-map-overlay">No data is shown/, "$scenario: map without data" );
        unlike( $html, qr/<div class="ifn-status-score">/, "$scenario: no score" );
        unlike( $html, qr/<circle/, "$scenario: no dots" );
        if ( $code eq 'unknown' ) {
            unlike( $html, qr{infrafence\.com/billing}, "$scenario: no billing link" );
        }
        else {
            like( $html, qr{<a href="https://infrafence\.com/billing" target="_blank" rel="noopener noreferrer">}, "$scenario: billing link" );
        }
        $html = render( run_app( scenario => $scenario, params => { page => 'allowlist' } ) );
        like( $html, qr/id="ifn-allow-ip"[^>]* disabled>/, "$scenario: whitelist address disabled" );
        like( $html, qr/id="ifn-allow-note"[^>]* disabled>/, "$scenario: whitelist note disabled" );
        like( $html, qr/<button type="submit" class="btn btn-primary btn-sm" disabled>/, "$scenario: whitelist button disabled" );
        for my $lang (qw(en it es fr de pt)) {
            for my $page (@PAGES) {
                my $h = render( run_app( lang => $lang, scenario => $scenario, params => { page => $page } ) );
                my @raw = $h =~ />\s*((?:gate|overview|verdict|score|map|attention|alert|plan)\.[a-z_.]+)\s*</g;
                is_deeply( \@raw, [], "$lang/$scenario/$page: no untranslated keys" );
            }
        }
    }
    my $html = render( run_app( scenario => 'unpaid' ) );
    like( $html, qr/Protection is off/, 'unpaid: protection off in the status row' );
    like( $html, qr/alert-danger ifn-gate/, 'unpaid: red banner' );

    # The plan's name in the banner is escaped.
    {
        package PlanAgent;
        sub new { bless { real => IFTest::mock_agent() }, shift }
        sub installed { 1 }
        sub call {
            my ( $self, $cmd, @a ) = @_;
            my $r = $self->{real}->call( $cmd, @a );
            return $cmd eq 'status' ? { %$r, plan => '<img src=x onerror=alert(1)>' } : $r;
        }
    }
    $html = render( run_app( agent => PlanAgent->new ) );
    like( $html, qr/on the &lt;img src=x onerror=alert\(1\)&gt; plan/, 'plan name escaped' );
    unlike( $html, qr/<img src=x/, 'no injected element' );

    $html = render( run_app( scenario => 'stopped' ) );
    unlike( $html, qr/ifn-gate/, 'stopped: the stopped alert, not the plan banner' );
    like( $html, qr/not running/, 'stopped: alert' );
}

done_testing;
