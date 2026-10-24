use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use IFTest qw($ROOT);

for my $m (qw(Util Validate Agent I18n Map Prefs Score App CGI)) {
    require_ok("InfraFence::WHM::$m");
}

for my $script ( "$ROOT/plugin/cgi/index.cgi", "$ROOT/dev/mock-agent", "$ROOT/dev/render" ) {
    my $out = `$^X -I$ROOT/plugin/lib -c $script 2>&1`;
    is( $?, 0, "perl -c $script" ) or diag $out;
}

open my $fh, '<', "$ROOT/VERSION" or die $!;
chomp( my $v = <$fh> );
is( $InfraFence::WHM::App::VERSION, $v, 'App::VERSION matches VERSION' );

done_testing;
