use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use IFTest qw(run_app render mock_agent TOKEN);

eval { require Template; 1 } or plan skip_all => 'Template Toolkit not installed';

my @PAGES = qw(overview bans allowlist findings events coexistence sites);

sub no_raw_keys {
    my ( $html, $name ) = @_;
    # A missing translation shows up as its key, e.g. "bans.title".
    my @raw = $html =~ />\s*((?:nav|alert|notice|error|overview|missing|list|col|action|bans|allow|findings|events|coex|coex_action|mode|sites|confirm|time|plan|automode|source|allow_source|kind|severity|finding_status|state|resolved_how|event|event_source|tool_kind|coverage|domain_type|unban|lang|verdict|attention|score|map|attack_cat|gate)\.[a-z_.]+)\s*</g;
    is_deeply( \@raw, [], "$name: no untranslated keys" ) or diag join ', ', @raw;
}

for my $lang (qw(en it es fr de pt)) {
    for my $page (@PAGES) {
        my $html = render( run_app( lang => $lang, params => { page => $page } ) );
        like( $html, qr/<div class="whm-title">.*InfraFence/s, "$lang/$page: wrapped in master" );
        like( $html, qr/class="active"><a href="index\.cgi\?page=$page"/, "$lang/$page: active tab" );
        like( $html, qr/<div id="ifn" class="ifn" lang="$lang">/, "$lang/$page: lang" );
        no_raw_keys( $html, "$lang/$page" );
    }
    my $html = render( run_app( lang => $lang, agent => mock_agent( bin => undef ) ) );
    no_raw_keys( $html, "$lang/not_installed" );
    for my $act ( [ unban => { ip => '203.0.113.7' } ], [ allow => { ip => '192.0.2.5', note => 'x' } ],
        [ disallow => { ip => '198.51.100.4' } ], [ scan => { path => '/home/alice/public_html' } ] )
    {
        $html = render( run_app( lang => $lang, params => { action => $act->[0], %{ $act->[1] } } ) );
        no_raw_keys( $html, "$lang/confirm $act->[0]" );
    }
    for my $v (qw(stale not_connected old)) {
        no_raw_keys( render( run_app( lang => $lang, map => $v, score => $v ) ), "$lang/overview map+score $v" );
    }
    no_raw_keys( render( run_app( lang => $lang, params => { range => '7d' } ) ), "$lang/overview 7d" );
    no_raw_keys( render( run_app( lang => $lang, scenario => 'hostile' ) ), "$lang/overview hostile" );
    for my $sev (qw(all warning critical)) {
        no_raw_keys( render( run_app( lang => $lang, params => { page => 'events', severity => $sev } ) ), "$lang/events $sev" );
    }
    for my $scenario (qw(stopped empty restricted monitor)) {
        for my $page (@PAGES) {
            no_raw_keys( render( run_app( lang => $lang, scenario => $scenario, params => { page => $page } ) ), "$lang/$scenario/$page" );
        }
    }
    my $notice = render( run_app( lang => $lang, params => { page => 'bans', notice => 'allow_ok', ip => '192.0.2.1',
        banned => 1, unreported => 1, threat_feed => 1, pending => 1, own => 1 } ) );
    no_raw_keys( $notice, "$lang/notices" );
    $notice = render( run_app( lang => $lang, params => { page => 'bans', notice => 'unban_ok', ip => '192.0.2.1', until => '2026-10-17T12:00:00Z', source => 'network' } ) );
    for my $ip (qw(192.0.2.50 198.51.100.23 198.51.100.9 192.0.2.99)) {
        no_raw_keys( render( run_app( lang => $lang, params => { page => 'bans', action => 'unban', ip => $ip } ) ), "$lang/confirm unban $ip" );
    }
    no_raw_keys( $notice, "$lang/unban notice" );
    like( $notice, qr/2026-10-17 12:00 UTC/, "$lang: end of the lift shown" );
    # Every coexistence action the agent can send is translated.
    my $L = IFTest::i18n($lang);
    for my $id (qw(csf lfd imunify imunifyav cphulk fail2ban crowdsec plesk_firewall bitninja monarx firewalld ufw modsecurity)) {
        ok( $L->has("coex_action.coexist_$id"), "$lang: coex_action.coexist_$id" );
    }
}

my $html = render( run_app( params => { page => 'overview' } ) );
like( $html, qr{href="https://app\.infrafence\.com/servers/42" target="_blank" rel="noopener noreferrer"}, 'open in InfraFence link' );
like( $html, qr/Protected/, 'state' );

$html = render( run_app( agent => mock_agent( bin => undef ) ) );
like( $html, qr/not installed/, 'not installed text' );
like( $html, qr{Add this server in the InfraFence dashboard \(Servers &gt; Add server\) and run the command shown there\.}, 'add server text' );
like( $html, qr{href="https://infrafence\.com/add-server" target="_blank" rel="noopener noreferrer"}, 'add server link' );
unlike( $html, qr/class="nav nav-tabs/, "no tabs when not installed" );

$html = render( run_app( scenario => 'stopped', params => { page => 'bans' } ) );
like( $html, qr/alert-warning.*not running/s, 'stopped banner' );

$html = render( run_app( params => { action => 'unban', ip => '203.0.113.7' } ) );
like( $html, qr{<form method="post" action="index\.cgi"}, 'confirm form posts' );
like( $html, qr{name="csrf" value="/cpsess4815162342"}, 'csrf token in form' );
like( $html, qr{name="confirm" value="1"}, 'confirm flag' );

$html = render( run_app( params => { page => 'bans', action => 'unban', ip => '192.0.2.50' } ) );
like( $html, qr/on this server only, until 2026-10-18 00:00 UTC at the latest/, 'confirm: this server only, until the date' );
like( $html, qr/network ban: your organization keeps it in force on its other servers/, 'confirm: network ban kept elsewhere' );
$html = render( run_app( params => { page => 'bans', action => 'unban', ip => '203.0.113.7' } ) );
unlike( $html, qr/keeps it in force on its other servers/, 'confirm: local ban has no such line' );
$html = render( run_app( params => { page => 'bans', notice => 'unban_ok', ip => '198.51.100.23', source => 'automode', until => '2026-10-16T16:00:00Z' } ) );
like( $html, qr/lifted on this server only.*until 2026-10-16 16:00 UTC at the latest.*AutoMode ban: your organization keeps it/s, 'result: scope, date, kept elsewhere' );

$html = render( run_app( params => { page => 'sites', notice => 'scan_ok', path => '/home/<i>x</i>' } ) );
like( $html, qr/A malware scan of the site has started/, 'scan notice' );
unlike( $html, qr{/home/(?:<|&lt;)i}, 'no path from the query string in the page' );
$html = render( run_app( agent => IFTest::mock_agent( scenario => 'hostile' ) ) );
unlike( $html, qr/ifn-open/, 'javascript: dashboard_url not linked' );

$html = render( run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.7' } ) );
like( $html, qr/alert-success.*The ban on 203\.0\.113\.7 has been lifted/s, 'success notice' );
$html = render( run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.7', threat_feed => 1 } ) );
like( $html, qr/alert-warning.*threat list/s, 'threat feed warning' );

$html = render( run_app( params => { page => 'allowlist' } ) );
like( $html, qr{action=disallow&amp;ip=198\.51\.100\.4}, 'panel entry can be removed' );
unlike( $html, qr{action=disallow&amp;ip=203\.0\.113\.20}, 'dashboard entry cannot' );
like( $html, qr/Managed in the dashboard/, 'dashboard entry marked' );

$html = render( run_app( params => { page => 'coexistence' } ) );
like( $html, qr/Rule sets: Imunify360 WAF, OWASP CRS/, 'ModSecurity rule sets' );
like( $html, qr/CSF \(ConfigServer Firewall\)<\/strong> <span class="text-muted">14\.20/, 'CSF version' );

$html = render( run_app( params => { page => 'events' } ) );
like( $html, qr/SQL injection.*ModSecurity/s, 'event type and source' );

$html = render( run_app( params => { page => 'overview' }, scenario => 'stopped' ) );
like( $html, qr/Not protected/, 'stopped state' );
unlike( $html, qr/class="row ifn-counts"/, 'no counts while stopped' );

$html = render( run_app( params => { page => 'sites' }, scenario => 'restricted' ) );
unlike( $html, qr{action=scan&amp;path=%2Fvar%2Fwww%2Fshared}, 'no scan action when not scannable' );
like( $html, qr/Not owned by the account/, 'reason: not owned' );
like( $html, qr/No document root/, 'reason: no document root' );
like( $html, qr/Scheduled malware scanning is off/, 'scheduled scans off' );

$html = render( run_app( params => { page => 'sites' } ) );
like( $html, qr{action=scan&amp;path=%2Fhome%2Falice%2Fpublic_html%2Fblog}, 'scan link encoded' );

# Everything the agent sends is escaped.
for my $page ( @PAGES, 'confirm' ) {
    my %params = $page eq 'confirm'
      ? ( action => 'scan', path => qq{/home/x/"><script>alert(22)</script>} )
      : ( page => $page );
    $html = render( run_app( scenario => 'hostile', params => \%params ) );
    my $body = ( $html =~ m{<div id="ifn".*}s )[0];
    $body =~ s{<script>\n\(function \(\) \{.*?</script>}{}s;    # the plugin's own script
    # The plugin's own drawings (map, sparkline): only its shapes inside, then left out.
    while ( $body =~ s{(<svg class="ifn-(?:map-svg|spark)[^"]*"[^>]*>)(.*?)</svg>}{}s ) {
        my ( $open, $inner ) = ( $1, $2 );
        unlike( $open, qr/\son[a-z]+=/i, "hostile $page: no handler on the plugin's svg" );
        my @tags = $inner =~ /<([a-zA-Z]+)/g;
        is_deeply( [ grep { !/\A(?:g|path|circle|polyline|title)\z/ } @tags ], [], "hostile $page: only shapes in the plugin's svg" );
        unlike( $inner, qr/\son[a-z]+=|javascript:/i, "hostile $page: no handlers in the plugin's svg" );
    }
    unlike( $body, qr/<(?:script|img|svg|iframe|b|i|u)[\s>]/i, "hostile $page: no injected elements" );
    unlike( $body, qr/["']\s*(?:on[a-z]+|autofocus)\b/i, "hostile $page: no injected attributes" );
    unlike( $body, qr/href="javascript:/i, "hostile $page: no javascript: links" );
}

done_testing;
