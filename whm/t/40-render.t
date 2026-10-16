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
    my @raw = $html =~ />\s*((?:nav|alert|notice|error|overview|missing|list|col|action|bans|allow|findings|events|coex|mode|handling|sites|confirm|time|plan|automode|source|kind|severity|finding_status|event|coverage|scan|domain_type|modsec_engine)\.[a-z_.]+)\s*</g;
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
    for my $act ( [ unban => { ip => '203.0.113.47' } ], [ allow => { ip => '192.0.2.5', note => 'x' } ],
        [ disallow => { ip => '198.51.100.4' } ], [ scan => { path => '/home/greenleaf/shop' } ] )
    {
        $html = render( run_app( lang => $lang, params => { action => $act->[0], %{ $act->[1] } } ) );
        no_raw_keys( $html, "$lang/confirm $act->[0]" );
    }
}

my $html = render( run_app( params => { page => 'overview' } ) );
like( $html, qr{href="https://app\.infrafence\.com/servers/agt_5f2c9e1a7b04" target="_blank" rel="noopener noreferrer"}, 'open in InfraFence link' );
like( $html, qr/Protected/, 'state' );

$html = render( run_app( agent => mock_agent( bin => undef ) ) );
like( $html, qr/not installed/, 'not installed text' );
like( $html, qr{<code>curl -fsSL https://get\.infrafence\.com \| sh</code>}, 'install command' );
like( $html, qr{href="https://infrafence\.com"}, 'site link' );
unlike( $html, qr/class="nav nav-tabs/, "no tabs when not installed" );

$html = render( run_app( scenario => 'stopped', params => { page => 'bans' } ) );
like( $html, qr/alert-warning.*not running/s, 'stopped banner' );

$html = render( run_app( params => { action => 'unban', ip => '203.0.113.47' } ) );
like( $html, qr{<form method="post" action="index\.cgi"}, 'confirm form posts' );
like( $html, qr{name="csrf" value="/cpsess4815162342"}, 'csrf token in form' );
like( $html, qr{name="confirm" value="1"}, 'confirm flag' );

$html = render( run_app( params => { page => 'bans', notice => 'unban_ok', ip => '203.0.113.47' } ) );
like( $html, qr/alert-success.*The ban on 203\.0\.113\.47 has been lifted/s, 'success notice' );

$html = render( run_app( params => { page => 'sites' } ) );
like( $html, qr{action=scan&amp;path=%2Fhome%2Fgreenleaf%2Fpublic_html}, 'scan link encoded' );

# Everything the agent sends is escaped.
for my $page ( @PAGES, 'confirm' ) {
    my %params = $page eq 'confirm'
      ? ( action => 'scan', path => qq{/home/x/"><script>alert(16)</script>} )
      : ( page => $page );
    $html = render( run_app( scenario => 'hostile', params => \%params ) );
    my $body = ( $html =~ m{<div id="ifn".*}s )[0];
    $body =~ s{<script>\n\(function \(\) \{.*?</script>}{}s;    # the plugin's own script
    unlike( $body, qr/<(?:script|img|svg|iframe|b|i|u)[\s>]/i, "hostile $page: no injected elements" );
    unlike( $body, qr/["']\s*(?:on[a-z]+|autofocus)\b/i, "hostile $page: no injected attributes" );
    unlike( $body, qr/href="javascript:/i, "hostile $page: no javascript: links" );
}

done_testing;
