use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP ();
use lib "$FindBin::Bin/lib";
use IFTest qw(run_app render TOKEN);

# Plugin 1.1.0 with agent 1.0.41: the known SSH logins, the regular clients
# of the database ports, and the event details (docs/panel-json.md).

my $dir = tempdir( CLEANUP => 1 );
my $log = "$dir/argv.log";

sub calls {
    open my $fh, '<', $log or return [];
    my @c = map { JSON::PP->new->decode($_) } <$fh>;
    close $fh;
    unlink $log;
    return \@c;
}

my $has_tt = eval { require Template; 1 };

# --- SSH logins

my $res = run_app( params => { page => 'logins' }, log => $log );
is( $res->{code}, 200, 'logins: 200' );
is_deeply( [ map { [ @$_[ 1 .. $#$_ ] ] } grep { $_->[1] ne 'status' } @{ calls() } ],
    [ [qw(ssh-logins --limit 500 --json)] ], 'logins: one call, within the agent limits' );
my @l = @{ $res->{data}{logins} };
is( scalar @l, 2, 'logins: two addresses' );
is_deeply( [ map { $_->{ip} } @l ], [ '198.51.100.61', '2001:db8:44::7' ], 'logins: in the agent order' );
is_deeply( $l[0]{users}, ['root'], 'logins: users' );
is( $l[0]{country_name}, 'Italy', 'logins: country name' );
is( $l[1]{country}, undef, 'logins: no country' );
is( $l[0]{seen}, 'both', 'logins: imported and live' );
is( $l[1]{seen}, 'logs', 'logins: imported only' );
is( $l[0]{logins}, 14, 'logins: count' );
is( $res->{data}{scanned_at}, '2026-10-16T06:00:00Z', 'logins: logs last read' );
ok( !$res->{data}{needs_agent}, 'logins: no update needed' );
is( run_app( lang => 'it', params => { page => 'logins' } )->{data}{logins}[0]{country_name}, 'Italia', 'logins: country in the language' );

if ($has_tt) {
    my $html = render($res);
    like( $html, qr/Known SSH logins \(last 30 days\)/, 'logins: title' );
    like( $html, qr{href="index\.cgi\?page=logins&amp;action=allow&amp;ip=198\.51\.100\.61">Add to whitelist</a>}, 'logins: add to whitelist' );
    like( $html, qr/Logs last read 2026-10-16 06:00 UTC/, 'logins: when the logs were read' );
}

# Older agent: the page says which agent it needs, without an error.
$res = run_app( params => { page => 'logins' }, access => 'old' );
is( $res->{data}{needs_agent}, '1.0.41', 'old agent: needs 1.0.41' );
ok( !$res->{data}{list_error}, 'old agent: no list error' );
is_deeply( $res->{data}{logins}, [], 'old agent: no rows' );
if ($has_tt) {
    my $html = render($res);
    like( $html, qr/needs InfraFence agent 1\.0\.41 or later/, 'old agent: message' );
    unlike( $html, qr/alert-danger/, 'old agent: no red error' );
}

$res = run_app( params => { page => 'logins' }, scenario => 'empty' );
is_deeply( $res->{data}{logins}, [], 'empty: no logins' );
like( render($res), qr/No SSH login in the last 30 days/, 'empty: message' ) if $has_tt;

# Hostile values: dropped or escaped.
$res = run_app( params => { page => 'logins' }, scenario => 'hostile' );
@l = @{ $res->{data}{logins} };
is_deeply( [ map { $_->{ip} } @l ], [ '198.51.100.61', '2001:db8::7' ], 'hostile: a bad address is dropped, IPv6 normalized' );
is_deeply( $l[0]{users}, ['<script>alert(21)</script>'], 'hostile: control characters and objects dropped' );
is( $l[0]{country}, undef, 'hostile: bad country dropped' );
is( $l[0]{last_at}, undef, 'hostile: bad time dropped' );
is( $l[0]{logins}, undef, 'hostile: bad count dropped' );
is( $res->{data}{scanned_at}, undef, 'hostile: bad scan time dropped' );
is( $l[1]{allowed}, 1, "hostile: allowed" );
if ($has_tt) {
    my $html = render($res);
    unlike( $html, qr/<script>alert|<img src=x/, 'hostile: nothing unescaped' );
    like( $html, qr/&lt;script&gt;alert\(21\)/, 'hostile: user escaped' );
}

# --- whitelisting from the SSH logins

$res = run_app( params => { page => 'logins', action => 'allow', ip => '198.51.100.61' }, log => $log );
is( $res->{data}{view}, 'confirm', 'allow from logins: confirmation first' );
is( $res->{data}{act}{page}, 'logins', 'allow from logins: back to logins' );
is( $res->{data}{act}{note}, 'Known SSH login', 'allow from logins: a note saying where it came from' );
ok( !grep( { $_->[1] eq 'allow' } @{ calls() } ), 'allow from logins: nothing run on a GET' );
$res = run_app( lang => 'de', params => { page => 'logins', action => 'allow', ip => '198.51.100.61' } );
is( $res->{data}{act}{note}, 'Bekannte SSH-Anmeldung', 'allow from logins: note in the language' );

$res = run_app(
    method => 'POST', log => $log,
    params => { page => 'logins', action => 'allow', ip => '198.51.100.61', note => 'Known SSH login', confirm => 1, csrf => TOKEN },
);
is( $res->{code}, 303, 'allow from logins: done' );
like( $res->{location}, qr/\Aindex\.cgi\?page=logins&notice=allow_ok&ip=198\.51\.100\.61/, 'allow from logins: back with the notice' );
is_deeply( [ grep { $_->[1] eq 'allow' } @{ calls() } ],
    [ [qw(panel allow 198.51.100.61 --note), 'Known SSH login', qw(--actor root --json)] ], 'allow from logins: the agent command' );

# A note given (even empty) is kept as given.
$res = run_app( params => { page => 'logins', action => 'allow', ip => '198.51.100.61', note => '' } );
is( $res->{data}{act}{note}, '', 'allow from logins: an empty note stays empty' );
# The bans page keeps no default note.
$res = run_app( params => { page => 'bans', action => 'allow', ip => '203.0.113.7' } );
is( $res->{data}{act}{note}, '', 'allow from bans: no default note' );

# --- database clients

$res = run_app( params => { page => 'clients' }, log => $log );
is( $res->{code}, 200, 'clients: 200' );
is_deeply( [ map { [ @$_[ 1 .. $#$_ ] ] } grep { $_->[1] ne 'status' } @{ calls() } ],
    [ [qw(db-clients --json)] ], 'clients: one call' );
my @c = @{ $res->{data}{clients} };
is( scalar @c, 3, 'clients: three' );
is_deeply( [ map { "$_->{port} $_->{ip}" } @c ], [ '3306 203.0.113.80', '3306 198.51.100.0/24', '6379 192.0.2.81' ], 'clients: by port' );
is( $c[0]{port_name}, 'MySQL/MariaDB', 'clients: port name' );
is( $c[0]{days}, 4, 'clients: days seen' );
ok( $c[1]{range} && !$c[0]{range}, 'clients: a declared range' );
is( $c[1]{host}, '198.51.100.%', 'clients: the panel entry of a declared client' );
is( $c[2]{allowed}, 1, 'clients: allowed' );
is( $res->{data}{unlisted}, 2, 'clients: two not whitelisted' );
if ($has_tt) {
    my $html = render($res);
    like( $html, qr/Regular clients of database ports/, 'clients: title' );
    like( $html, qr/seen connected on 3 or more of the last 7 days/, 'clients: the rule' );
    like( $html, qr{page=clients&amp;action=allow&amp;ip=203\.0\.113\.80">Add to whitelist}, 'clients: add a single address' );
    unlike( $html, qr{action=allow&amp;ip=198\.51\.100\.0}, 'clients: no panel action for a range' );
    like( $html, qr/Whitelist the range in the InfraFence dashboard/, 'clients: a range is whitelisted in the dashboard' );
    like( $html, qr/2 clients are not on the whitelist/, 'clients: the warning' );
}
$res = run_app( params => { page => 'clients', action => 'allow', ip => '203.0.113.80' } );
is( $res->{data}{act}{note}, 'Regular database client', 'allow from clients: note' );
$res = run_app( params => { page => 'clients', action => 'allow', ip => '198.51.100.0/24' } );
is( $res->{code}, 400, 'allow from clients: a range is refused' );

$res = run_app( params => { page => 'clients' }, access => 'old' );
is( $res->{data}{needs_agent}, '1.0.41', 'clients, old agent: needs 1.0.41' );

$res = run_app( params => { page => 'clients' }, scenario => 'hostile' );
@c = @{ $res->{data}{clients} };
is_deeply( [ map { $_->{ip} } @c ], [ '198.51.100.0/24', '192.0.2.81' ], 'clients hostile: bad port and source dropped' );
is( $c[1]{host}, undef, 'clients hostile: an observed client has no host' );
is( $c[1]{days}, undef, 'clients hostile: bad days dropped' );
is( $c[1]{first_seen}, undef, 'clients hostile: bad time dropped' );
is( $res->{data}{min_days}, 3, 'clients hostile: bad min_days replaced' );
unlike( render($res), qr/<script>alert|javascript:alert/, 'clients hostile: nothing unescaped' ) if $has_tt;

is( InfraFence::WHM::App::_cidr($_->[0]), $_->[1], "cidr " . ( ref $_->[0] ? "ref" : $_->[0] // "undef" ) ) for (
    [ '198.51.100.0/24', '198.51.100.0/24' ], [ '2001:DB8::/48', '2001:db8::/48' ], [ '198.51.100.0/33', undef ],
    [ '198.51.100.0', undef ], [ '198.51.100.0/024', undef ], [ 'x/24', undef ], [ undef, undef ], [ {}, undef ],
);

# --- event details

$res = run_app( params => { page => 'events' }, scenario => 'access' );
my %by = map { $_->{type} => $_ } @{ $res->{data}{events} };
my $mail = $by{mail_brute_force};
is_deeply( $mail->{facts}, [
    { key => 'target_user', value => 'info@alice.example' }, { key => 'protocol', value => 'IMAP' },
    { key => 'auth_method', value => 'PLAIN' }, { key => 'attempts', value => '6' }, { key => 'mta', value => 'dovecot' },
], 'details: mail attack' );
is( $mail->{summary}, 'info@alice.example · IMAP · PLAIN', 'details: mail summary' );
is_deeply( $by{sql_injection}{cves}, ['CVE-2024-27956'], 'details: CVE' );
is( $by{sql_injection}{summary}, 'CVE-2024-27956', 'details: CVE summary' );
is_deeply( [ map { $_->{key} } @{ $by{sql_injection}{facts} } ], [qw(attack_type domain)], 'details: WAF facts' );
is( $by{db_exposed}{summary}, '0.0.0.0:3306', 'details: where the database listens' );
is_deeply( $by{ssh_brute_force}{facts}, [], 'details: none' );
is( $by{ssh_brute_force}{summary}, '', 'details: no summary' );
ok( !exists $mail->{details}, 'details: the raw object is not passed on' );
if ($has_tt) {
    my $html = render($res);
    like( $html, qr{<summary><span class="ifn-mono">info\@alice\.example · IMAP · PLAIN</span></summary>}, 'details: summary shown' );
    like( $html, qr{<th scope="row">Mailbox</th><td class="ifn-mono">info\@alice\.example</td>}, 'details: mailbox' );
    like( $html, qr{<th scope="row">Attack type</th><td class="ifn-mono">SQL injection</td>}, 'details: attack type named' );
    like( $html, qr{href="https://infrafence\.com/exploitation\?cve=CVE-2024-27956" target="_blank" rel="noopener noreferrer"}, 'details: CVE link' );
    like( $html, qr{<th scope="row">Listening on</th><td class="ifn-mono">0\.0\.0\.0:3306</td>}, 'details: bind address' );
    my $it = render( run_app( lang => 'it', params => { page => 'events' }, scenario => 'access' ) );
    like( $it, qr{<th scope="row">Casella</th>}, 'details: Italian' );
    # Overview: the summary next to the event.
    like( render( run_app( scenario => 'access' ) ), qr{ifn-event-summary">CVE-2024-27956</span>}, 'details: on the Overview' );
}

# An agent before 1.0.41 sends no details: nothing changes.
$res = run_app( params => { page => 'events' } );
ok( !grep( { @{ $_->{facts} } || @{ $_->{cves} } } @{ $res->{data}{events} } ), 'old agent: no details' );
unlike( render($res), qr/<details/, 'old agent: no details element' ) if $has_tt;

# Hostile details.
$res = run_app( params => { page => 'events' }, scenario => 'hostile' );
my ($h) = grep { $_->{type} =~ /script/ } @{ $res->{data}{events} };
is_deeply( $h->{cves}, ['CVE-2024-27956'], 'hostile details: only well-formed CVEs' );
ok( !grep( { $_->{key} eq 'attempts' || $_->{key} eq 'bind_address' } @{ $h->{facts} } ), 'hostile details: bad attempts, bind address of another type dropped' );
my ($db) = grep { $_->{type} eq 'db_exposed' } @{ $res->{data}{events} };
is( $db->{summary}, '0.0.0.0:3306<img src=x onerror=alert(29)>', 'hostile details: kept as text' );
if ($has_tt) {
    my $html = render($res);
    unlike( $html, qr/<script>alert\(2[67]\)|<img src=x onerror=alert\(29\)>|<b>imap/, 'hostile details: escaped' );
    unlike( $html, qr/href="javascript:/, 'hostile details: no script link' );
}

is( InfraFence::WHM::App::event_details( { type => 'mail_relay_scan', details => { recipient => 'victim@relay.example', recipient_domain => 'RELAY.example', protocol => 'smtp' } } )->{summary},
    "\xe2\x86\x92 victim\@relay.example · SMTP", 'details: relay probe summary' );
is( InfraFence::WHM::App::event_details( { type => 'x', details => 'not an object' } )->{summary}, '', 'details: not an object' );
my $many = join ',', map { sprintf 'CVE-2024-%04d', $_ } 1000 .. 1015;
is( scalar @{ InfraFence::WHM::App::event_details( { type => 'x', details => { cves => $many } } )->{cves} }, 10, 'details: at most 10 CVEs' );
is( scalar @{ InfraFence::WHM::App::event_details( { type => 'x', details => { target_user => 'a' x 255 } } )->{facts} }, 0, 'details: too long dropped' );
for my $bad ( "evil\xe2\x80\xaegro\@x", "a\xe2\x80\x8bb\@x", "\xff\xfe", "a\xc2\x85b" ) {
    is( scalar @{ InfraFence::WHM::App::event_details( { type => 'x', details => { target_user => $bad } } )->{facts} }, 0, 'details: spoofing characters dropped' );
}
is( InfraFence::WHM::App::event_details( { type => 'x', details => { target_user => "jos\xc3\xa9\@x" } } )->{facts}[0]{value}, "jos\xc3\xa9\@x", 'details: accents kept' );

# --- not entitled: nothing asked, empty lists

for my $page (qw(logins clients)) {
    $res = run_app( scenario => 'starter', gate => 'new', params => { page => $page }, log => $log );
    is( $res->{data}{gate}, 'plan_required', "$page gated" );
    is_deeply( [ map { $_->[1] } @{ calls() } ], ['status'], "$page gated: only status" );
    is_deeply( $res->{data}{ $page eq 'logins' ? 'logins' : 'clients' }, [], "$page gated: empty" );
}
$res = run_app( scenario => 'starter', gate => 'new', method => 'POST', log => $log,
    params => { page => 'logins', action => 'allow', ip => '198.51.100.61', confirm => 1, csrf => TOKEN } );
is( $res->{code}, 403, 'allow from logins gated: refused' );
ok( !grep( { $_->[1] eq 'allow' } @{ calls() } ), 'allow from logins gated: not run' );

done_testing;
