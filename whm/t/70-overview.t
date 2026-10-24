use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP ();
use lib "$FindBin::Bin/lib";
use IFTest qw(run_app render mock_agent i18n $ROOT);
use InfraFence::WHM::Map   ();
use InfraFence::WHM::Score ();

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

# --- the map

my $res = run_app();
my $m   = $res->{data}{map};
is( $m->{state}, 'ok', 'map: fresh reply' );
is( $m->{range}, '24h', 'map: 24 h by default' );
is( $m->{total}, 865, 'map: total' );
is( scalar @{ $m->{countries} }, 5, 'map: top 5 countries' );
is_deeply( [ map { $_->{code} } @{ $m->{countries} } ], [qw(CN US RU BR IN)], 'map: sorted by attacks' );
is( $m->{countries}[0]{name}, 'China', 'map: country name' );
is( $m->{country_count}, 16, 'map: countries in all' );
is_deeply( [ map { $_->{cat} } @{ $m->{categories} } ], [qw(ssh web scans bots other)], 'map: categories' );
is( $m->{categories}[0]{pct}, 59, 'map: share of the categories' );
ok( !$m->{stale}, 'map: not stale' );
my ($cn) = grep { ( $_->{code} || '' ) eq 'CN' } @{ $m->{svg}{shapes} };
is( $cn->{fill}, '#e0b2b4', 'map: busiest country at full shade' );
my ($no) = grep { ( $_->{code} || '' ) eq '' } @{ $m->{svg}{shapes} };
is( $no->{fill}, '#e8eaed', 'map: land colour without attacks' );
is( $m->{svg}{dots}[0]{r}, '22.0', 'map: biggest dot first' );
is( $res->{data}{counts}{attacks}, 865, 'figure: attacks in 24 h' );

is( run_app( lang => 'it' )->{data}{map}{countries}[1]{name}, 'Stati Uniti', 'map: country names follow the language' );

$res = run_app( params => { range => '7d' }, log => $log );
is( $res->{data}{map}{range}, '7d', 'map: 7 days' );
is( $res->{data}{map}{total}, 5815, 'map: 7-day total' );
is( $res->{data}{counts}{attacks}, 865, 'figure: still the last 24 h' );
my @maps = grep { $_->[1] eq 'map' } @{ calls() };
is_deeply( \@maps, [ [qw(panel map --hours 168 --json)], [qw(panel map --hours 24 --json)] ], 'map: 168 h, plus 24 h for the figure' );

for my $bad ( '30d', '7d;id', '', '168' ) {
    run_app( params => { range => $bad }, log => $log );
    my ($call) = grep { $_->[1] eq 'map' } @{ calls() };
    is_deeply( $call, [qw(panel map --hours 24 --json)], "map: range '$bad' falls back to 24 h" );
}

$res = run_app( map => 'stale' );
is( $res->{data}{map}{state}, 'ok', 'stale map still drawn' );
ok( $res->{data}{map}{stale}, 'stale flagged' );
is( $res->{data}{map}{generated_at}, '2026-10-16T09:40:00Z', 'stale: when' );

is( run_app( map => 'not_connected' )->{data}{map}{state}, 'not_connected', 'map: not connected' );
is( run_app( map => 'old' )->{data}{map}{state}, 'old_agent', 'map: agent without panel map' );
is( run_app( scenario => 'empty' )->{data}{map}{state}, 'empty', 'map: no attacks' );
is( run_app( scenario => 'empty' )->{data}{map}{total}, 0, 'map: zero' );
ok( !run_app( scenario => 'stopped' )->{data}{map}, 'map: not asked while stopped' );
is( run_app( map => 'old', fault => '' )->{data}{verdict}{key}, 'critical', 'old agent: the rest of the page still works' );

# Hostile replies: bad codes ignored, counts checked, duplicates dropped.
$res = run_app( scenario => 'hostile' );
$m   = $res->{data}{map};
is_deeply( [ map { $_->{code} } @{ $m->{countries} } ], ['DE'], 'hostile: only a valid, known code with a whole count' );
is( $m->{countries}[0]{attacks}, 2, 'hostile: first of a duplicate wins' );
is_deeply( [ map { $_->{cat} } @{ $m->{categories} } ], ['ssh'], 'hostile: only clean categories' );
is( $m->{total}, 2, 'hostile: total never below the countries' );
ok( !defined $m->{generated_at}, 'hostile: markup in generated_at dropped' );
my %fills = map { $_->{fill} => 1 } @{ $m->{svg}{shapes} };
ok( !grep( { !/\A#[0-9a-f]{6}\z/ } keys %fills ), 'hostile: fills are colours the plugin made' );

is( InfraFence::WHM::Map::view( reply => { ok => 0, error => 'timeout' } )->{state}, 'unavailable', 'map: other errors' );
is( InfraFence::WHM::Map::view( reply => { ok => 1, total => { attacks => 3 } }, dir => "$dir/none" )->{state}, 'unavailable', 'map: geometry missing' );

# The shipped geometry.
my $world = InfraFence::WHM::Map::world("$ROOT/plugin/map");
ok( $world && @{ $world->{shapes} } > 150, 'world.json: country shapes' );
ok( !grep( { $_->[1] !~ /\A[MLZ0-9.,\-]+\z/ } @{ $world->{shapes} } ), 'world.json: paths are plain path data' );
ok( -s "$ROOT/plugin/map/NOTICE", 'map attribution shipped' );

# --- the score

$res = run_app();
my $sc = $res->{data}{score};
is( $sc->{state}, 'ok', 'score: fresh' );
is( $sc->{score}, 64, 'score' );
is( $sc->{grade}, 'C', 'grade' );
is( $sc->{tone}, 'warning', 'grade tone' );
is( $sc->{delta}, 12, 'trend delta' );
is_deeply( [ map { $_->{key} } @{ $sc->{items} } ], [qw(exposed_ports hardening agent_outdated malware)], 'items by points' );
is( $sc->{items}[0]{args}{ports}, '3306, 6379', 'ports' );
is( $sc->{items}[1]{args}{failed}, 12, 'counts' );
like( $sc->{spark}{points}, qr/\A[0-9., ]+\z/, 'sparkline points' );
is( InfraFence::WHM::Score::grade($_->[0]), $_->[1], "grade of $_->[0]" ) for [ 90, 'A' ], [ 89, 'B' ], [ 75, 'B' ], [ 60, 'C' ], [ 40, 'D' ], [ 39, 'F' ], [ 0, 'F' ];

is( run_app( score => 'not_connected' )->{data}{score}{state}, 'not_connected', 'score: not connected' );
is( run_app( score => 'old' )->{data}{score}{state}, 'old_agent', 'score: old agent' );
ok( run_app( score => 'stale' )->{data}{score}{stale}, 'score: stale' );
$sc = run_app( scenario => 'empty' )->{data}{score};
is_deeply( [ $sc->{score}, scalar @{ $sc->{items} }, $sc->{spark} ], [ 100, 0, undef ], 'score: nothing to fix, no trend' );

$sc = run_app( scenario => 'hostile' )->{data}{score};
is( $sc->{grade}, 'C', 'hostile: grade computed, not taken' );
is_deeply( [ map { $_->{key} } @{ $sc->{items} } ], [qw(exposed_ports hardening agent_outdated brand_new_rule)], 'hostile: bad keys dropped' );
is( $sc->{items}[0]{args}{ports}, '3306', 'hostile: bad port dropped' );
is( $sc->{items}[1]{args}{failed}, "\xe2\x80\x93", 'hostile: bad count is a dash' );
is( $sc->{items}[2]{args}{version}, "\xe2\x80\x93", 'hostile: bad version is a dash' );
is( scalar @{ $sc->{trend} }, 2, 'hostile: bad trend points dropped' );
ok( !defined $sc->{generated_at}, 'hostile: bad time dropped' );

# --- critical events and the verdict

$res = run_app();
my $a = $res->{data}{attention};
is_deeply( [ $a->{critical}, $a->{warning} ], [ 2, 2 ], 'attention counts' );
is_deeply( [ map { $_->{type} } @{ $a->{events} } ], [qw(malware_realtime sql_injection integrity_change ssh_brute_force)], 'critical first, then newest' );
is( $a->{events}[1]{ip}, '198.51.100.23', 'source address' );
is( $a->{filter}, 'critical', 'link to the critical filter' );
is( $res->{data}{counts}{critical}, 2, 'figure: critical events' );
is_deeply( $res->{data}{verdict}, { tone => 'critical', key => 'critical', n => 2 }, 'verdict: critical events' );

$res = run_app( scenario => 'empty' );
is_deeply( $res->{data}{attention}{events}, [], 'no critical events' );
is_deeply( $res->{data}{verdict}, { tone => 'ok', key => 'ok' }, 'verdict: nothing to do' );

my $many = InfraFence::WHM::App::_attention( [ map { { severity => $_ % 2 ? 'critical' : 'warning', type => 'x', time => sprintf( '2026-10-16T%02d:00:00Z', $_ ) } } 0 .. 20 ], i18n() );
is( scalar @{ $many->{events} }, 10, 'at most 10' );
is_deeply( [ $many->{critical}, $many->{warning} ], [ 10, 11 ], 'counts cover all' );
is( $many->{events}[0]{time}, '2026-10-16T19:00:00Z', 'newest critical first' );

# --- events page severity filter

$res = run_app( params => { page => 'events', severity => 'critical' } );
is_deeply( [ map { $_->{severity} } @{ $res->{data}{events} } ], [qw(critical critical)], 'events: critical' );
is_deeply( $res->{data}{sev_count}, { all => 5, warning => 4, critical => 2 }, 'events: counts per filter' );
$res = run_app( params => { page => 'events', severity => 'warning' } );
is( scalar @{ $res->{data}{events} }, 4, 'events: warning and above' );
$res = run_app( params => { page => 'events', severity => '<x>' } );
is( $res->{data}{severity}, 'all', 'events: unknown filter is all' );
is( scalar @{ $res->{data}{events} }, 5, 'events: all' );

# --- rendering

SKIP: {
    skip 'Template Toolkit not installed', 1 unless $have_tt;
    my $html = render( run_app() );
    like( $html, qr{<svg class="ifn-map-svg" viewBox="0 0 960 \d+" role="img"}, 'map drawn inline' );
    like( $html, qr{<title>China: 301 attacks</title>}, 'country tooltip without JS' );
    like( $html, qr{href="index\.cgi\?page=overview&amp;range=7d#ifn-map"}, '7-day link' );
    like( $html, qr{aria-current="true">24 h</a>}, '24 h is current' );
    like( $html, qr{Top sources.*China</span> <span class="ifn-num">301}s, 'top countries' );
    like( $html, qr{SSH brute force</span> <span class="ifn-num">59%}, 'categories' );
    unlike( $html, qr/blocked/i, 'no blocked figure' );
    my ($body) = $html =~ m{(<div id="ifn".*)}s;
    unlike( $body, qr{(?:src|href|xlink:href)="(?:https?:)?//(?!app\.infrafence\.com|infrafence\.com)}, 'no external resources' );
    unlike( $body, qr{url\(}, 'no external resources in styles' );
    like( $html, qr{ifn-grade-warning">Grade C}, 'score and grade' );
    like( $html, qr{Risky service ports open to the network: 3306, 6379</span>\s*<span class="ifn-points">\xe2\x88\x9216 points}, 'item worded with points' );
    like( $html, qr{The agent is out of date: 1\.0\.23, latest 1\.0\.24}, 'agent_outdated worded' );
    like( $html, qr{href="https://app\.infrafence\.com/servers/42" target="_blank" rel="noopener noreferrer">Fix these in InfraFence}, 'fix link' );
    like( $html, qr{<svg class="ifn-spark ifn-spark-warning"}, 'sparkline' );
    like( $html, qr{\+12 in 30 days}, 'trend delta' );
    like( $html, qr{2 critical events in the last 24 hours\.}, 'verdict' );
    like( $html, qr{Critical: 2 · Warning: 2}, 'attention counts' );
    like( $html, qr{SQL injection attempt <span class="ifn-ip text-muted">from 198\.51\.100\.23}, 'event name and address' );
    like( $html, qr{href="index\.cgi\?page=events&amp;severity=critical">See them in Events}, 'link to filtered events' );

    $html = render( run_app( map => 'stale', score => 'stale' ) );
    like( $html, qr{Last updated 2 h ago}, 'stale note' );
    $html = render( run_app( map => 'old', score => 'old' ) );
    like( $html, qr{Update the InfraFence agent to see the attack map here}, 'old agent: map' );
    like( $html, qr{Update the InfraFence agent to see the security score here}, 'old agent: score' );
    unlike( $html, qr{alert-danger}, 'old agent: calm, no error box' );
    $html = render( run_app( map => 'not_connected', score => 'not_connected' ) );
    like( $html, qr{The map appears once this server has connected}, 'not connected: map' );
    like( $html, qr{The score appears once this server has connected}, 'not connected: score' );
    $html = render( run_app( scenario => 'empty' ) );
    like( $html, qr{No attacks recorded in this time window}, 'empty map' );
    like( $html, qr{No critical events in the last 24 hours}, 'no critical events' );
    like( $html, qr{Nothing needs your attention}, 'calm verdict' );
    $html = render( run_app( scenario => 'hostile' ) );
    like( $html, qr{Security event <code>&lt;script&gt;}, 'unknown event type shown as escaped code' );
    $html = render( run_app( params => { page => 'events', severity => 'critical' } ) );
    like( $html, qr{class="active"><a href="index\.cgi\?page=events&amp;severity=critical&amp;limit=100" aria-current="true">Critical <span class="badge">2}, 'events filter pills' );
    like( $html, qr{name="severity" value="critical"}, 'filter kept by the limit form' );
}

done_testing;
