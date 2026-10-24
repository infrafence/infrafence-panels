use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/lib";
use IFTest qw(run_app render mock_agent TOKEN);
use InfraFence::WHM::Prefs ();

my $root  = tempdir( CLEANUP => 1 );
my $state = "$root/infrafence-whm";
my $prefs = InfraFence::WHM::Prefs->new( dir => "$state/prefs" );

sub post {
    my (%o) = @_;
    my $params = delete $o{params} || {};
    return run_app(
        prefs  => $prefs,
        method => 'POST',
        params => { action => 'language', page => 'bans', csrf => TOKEN, %$params },
        %o,
    );
}

# --- validation

is( InfraFence::WHM::Prefs::valid_lang($_), $_, "valid: $_" ) for qw(en it es fr de pt-BR);
ok( !defined InfraFence::WHM::Prefs::valid_lang($_), "invalid: $_" ) for ( 'pt', 'EN', 'ja', '', '../en', "it\n", 'it;' );

# --- nothing chosen: the WHM language

is( $prefs->lang('root'), undef, 'no choice yet' );
my $res = run_app( prefs => $prefs, lang => 'it' );
is( $res->{data}{lang_choice}, 'whm', 'follows WHM' );
is( $res->{data}{whm_lang_name}, 'Italiano', 'WHM language named' );

# --- a POST with the token stores the choice

$res = post( params => { lang => 'de' } );
is( $res->{code}, 303, 'language: 303' );
is( $res->{location}, 'index.cgi?page=bans', 'back to the page' );
is( $prefs->lang('root'), 'de', 'stored' );
my @st = stat "$state/prefs/root.json";
is( $st[2] & 07777, 0600, 'file 0600' );
is( ( stat "$state/prefs" )[2] & 07777, 0700, 'directory 0700' );
is( ( stat $state )[2] & 07777, 0700, 'state directory 0700' );
ok( -f "$state/.infrafence-whm", 'state directory marked for uninstall' );
is( run_app( prefs => $prefs )->{data}{lang_choice}, 'de', 'choice shown' );

$res = post( params => { lang => 'pt-BR', page => '../../x' } );
is( $res->{location}, 'index.cgi?page=overview', 'unknown page goes to the overview' );
is( $prefs->lang('root'), 'pt-BR', 'pt-BR' );

# Works without the agent too.
$res = post( params => { lang => 'fr' }, agent => mock_agent( bin => undef ) );
is( $res->{code}, 303, 'without the agent' );
is( $prefs->lang('root'), 'fr', 'stored without the agent' );

# --- refused: bad values, no token, wrong token, GET, other sites

for my $bad ( 'xx', 'pt', '', '../../etc/passwd', 'it"><script>' ) {
    $res = post( params => { lang => $bad } );
    is( $res->{code}, 400, "bad language '$bad' refused" );
    is( $res->{data}{errors}[0]{error}, 'invalid_language', 'invalid_language' );
}
is( $prefs->lang('root'), 'fr', 'unchanged after bad values' );

$res = post( params => { lang => 'es', csrf => '' } );
is( $res->{code}, 403, 'no token: 403' );
is( $res->{data}{errors}[0]{error}, 'csrf', 'csrf error' );
$res = post( params => { lang => 'es', csrf => '/cpsess0000000000' } );
is( $res->{code}, 403, 'wrong token: 403' );
$res = run_app( prefs => $prefs, params => { action => 'language', lang => 'es', csrf => TOKEN } );
is( $res->{code}, 403, 'GET: 403' );
$res = post( params => { lang => 'es' }, origin => 'https://evil.example' );
is( $res->{code}, 403, 'other origin: 403' );
$res = post( params => { lang => 'es' }, referer => 'https://evil.example/x' );
is( $res->{code}, 403, 'other referer: 403' );
# cpsrvd passes the host without its port (PR #4): still accepted from WHM's port.
$res = post( params => { lang => 'es' }, host => 'host07.hosting.example' );
is( $res->{code}, 303, 'host without port, form from :2087' );
is( $prefs->lang('root'), 'es', 'stored' );

# --- back to the WHM language

$res = post( params => { lang => 'whm' } );
is( $res->{code}, 303, 'reset' );
is( $prefs->lang('root'), undef, 'choice removed' );
ok( !-e "$state/prefs/root.json", 'file removed' );

# --- per user

post( params => { lang => 'it' }, actor => 'alice' );
post( params => { lang => 'de' }, actor => 'bob' );
is( $prefs->lang('alice'), 'it', 'alice' );
is( $prefs->lang('bob'), 'de', 'bob' );
is( $prefs->lang('root'), undef, 'root unaffected' );
is( run_app( prefs => $prefs, actor => 'bob' )->{data}{lang_choice}, 'de', 'bob sees his own' );
is( run_app( prefs => $prefs, actor => 'alice' )->{data}{lang_choice}, 'it', 'alice sees hers' );

for my $bad ( '../alice', 'a/b', '.', '..', '', undef, "x\n" ) {
    my $name = defined $bad ? $bad : 'undef';
    $res = post( params => { lang => 'es' }, actor => $bad );
    is( $res->{code}, 403, "user '$name' refused" );
    is( $prefs->lang($bad), undef, "no preference read for '$name'" );
}
is( $prefs->lang('alice'), 'it', 'alice unchanged' );
ok( !-e "$root/alice.json" && !-e "$state/alice.json", 'nothing written outside prefs/' );

# --- files that are not safe are ignored

SKIP: {
    skip 'symlink tests need a writable temporary directory', 4 unless -d $root;
    open my $fh, '>', "$root/elsewhere.json" or die $!;
    print {$fh} qq({"lang":"fr"}\n);
    close $fh;
    symlink "$root/elsewhere.json", "$state/prefs/mallory.json" or die $!;
    is( $prefs->lang('mallory'), undef, 'symlinked file ignored' );
    ok( !$prefs->set_lang( 'mallory', 'it' ) || !-l "$state/prefs/mallory.json", 'symlink replaced, never written through' );
    open $fh, '<', "$root/elsewhere.json" or die $!;
    is( scalar <$fh>, qq({"lang":"fr"}\n), 'link target untouched' );
    close $fh;

    open $fh, '>', "$state/prefs/carol.json" or die $!;
    print {$fh} qq({"lang":"it"}\n);
    close $fh;
    chmod 0666, "$state/prefs/carol.json";
    is( $prefs->lang('carol'), undef, 'world-writable file ignored' );
}

open my $fh, '>', "$state/prefs/dave.json" or die $!;
print {$fh} qq({"lang":"<script>"}\n);
close $fh;
chmod 0600, "$state/prefs/dave.json";
is( $prefs->lang('dave'), undef, 'stored value checked again on read' );
open $fh, '>', "$state/prefs/erin.json" or die $!;
print {$fh} '{"lang":"it","x":"' . ( 'y' x 5000 ) . '"}';
close $fh;
chmod 0600, "$state/prefs/erin.json";
is( $prefs->lang('erin'), undef, 'oversized file ignored' );

my $loose = InfraFence::WHM::Prefs->new( dir => "$root/loose/prefs" );
mkdir "$root/loose";
mkdir "$root/loose/prefs";
chmod 0777, "$root/loose/prefs";
ok( !$loose->set_lang( 'root', 'it' ), 'world-writable prefs directory not used' );

# --- rendering

SKIP: {
    skip 'Template Toolkit not installed', 1 unless eval { require Template; 1 };
    my $html = render( run_app( prefs => $prefs, actor => 'alice', lang => 'it', whm_lang => 'en' ) );
    like( $html, qr{<form class="form-inline ifn-lang" method="post" action="index\.cgi">}, 'language form posts' );
    like( $html, qr{name="action" value="language"}, 'language action' );
    like( $html, qr{name="csrf" value="/cpsess4815162342"}, 'with the security token' );
    like( $html, qr{<option value="whm">Come WHM \(English\)</option>}, 'same as WHM, named' );
    like( $html, qr{<option value="it" lang="it" selected>Italiano</option>}, 'current choice selected' );
    like( $html, qr{<option value="pt-BR" lang="pt-BR">Português \(Brasil\)</option>}, 'pt-BR offered' );
    $html = render( post( params => { lang => 'es', csrf => 'x' } ) );
    like( $html, qr/security check failed/, 'csrf error shown' );
    $html = render( run_app( agent => mock_agent( bin => undef ), prefs => $prefs ) );
    like( $html, qr/name="action" value="language"/, 'selector also when the agent is missing' );
}

done_testing;
