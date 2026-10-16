use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use IFTest ();
use InfraFence::WHM::CGI ();

sub req {
    my ( $env, $body ) = @_;
    $body = '' unless defined $body;
    open my $in, '<', \$body or die;
    return InfraFence::WHM::CGI::read_request( { %$env, CONTENT_LENGTH => length $body }, $in );
}

my $r = req( { REQUEST_METHOD => 'GET', QUERY_STRING => 'page=bans&ip=2001%3Adb8%3A%3A1&note=a+b&page=x', cp_security_token => '/cpsess1', REMOTE_USER => 'root', HTTP_HOST => 'h:2087' } );
is( $r->{method}, 'GET' );
is( $r->{params}{page}, 'bans', 'first value wins' );
is( $r->{params}{ip}, '2001:db8::1', 'percent decoding' );
is( $r->{params}{note}, 'a b', 'plus is space' );
is( $r->{token}, '/cpsess1', 'token' );
is( $r->{actor}, 'root', 'actor' );

$r = req( { REQUEST_METHOD => 'POST', QUERY_STRING => 'page=bans&action=x', CONTENT_TYPE => 'application/x-www-form-urlencoded' },
    'action=unban&ip=192.0.2.1&confirm=1&csrf=%2Fcpsess1' );
is( $r->{params}{action}, 'unban', 'body wins over query' );
is( $r->{params}{csrf}, '/cpsess1', 'csrf' );
is( $r->{params}{page}, 'bans', 'query kept' );

$r = req( { REQUEST_METHOD => 'POST', CONTENT_TYPE => 'multipart/form-data' }, 'action=unban' );
ok( !exists $r->{params}{action}, 'other content types ignored' );

$r = req( { REQUEST_METHOD => 'POST', CONTENT_TYPE => 'application/x-www-form-urlencoded' }, 'a=' . ( 'x' x 70000 ) );
ok( !exists $r->{params}{a}, 'oversized body ignored' );

done_testing;
