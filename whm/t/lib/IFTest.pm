package IFTest;

# Shared setup for the tests and for dev/render: builds the controller with
# the mock agent and renders its response with the stub WHM master template.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Time::Local qw(timegm);

our $ROOT;
BEGIN { $ROOT = abs_path( dirname(__FILE__) . '/../..' ) }
use lib "$ROOT/plugin/lib";

use InfraFence::WHM::Agent ();
use InfraFence::WHM::App   ();
use InfraFence::WHM::I18n  ();

use Exporter 'import';
our @EXPORT_OK = qw(make_app run_app render mock_agent i18n $ROOT NOW TOKEN);

use constant NOW   => timegm( 0, 1, 12, 16, 9, 2026 );    # 2026-10-16 12:01:00 UTC, as dev/mock-agent
use constant TOKEN => '/cpsess4815162342';

sub mock_agent {
    my (%o) = @_;
    my %env = ( MOCK_AGENT_SCENARIO => $o{scenario} || 'default' );
    $env{MOCK_AGENT_LOG}   = $o{log}   if $o{log};
    $env{MOCK_AGENT_FAULT} = $o{fault} if $o{fault};
    $env{MOCK_AGENT_MAP}   = $o{map}   if $o{map};
    $env{MOCK_AGENT_SCORE} = $o{score} if $o{score};
    return InfraFence::WHM::Agent->new(
        bin          => exists $o{bin} ? $o{bin} : "$ROOT/dev/mock-agent",
        strict_owner => $o{strict_owner} || 0,
        timeout      => $o{timeout} || 10,
        env          => \%env,
    );
}

sub i18n {
    my ($lang) = @_;
    return InfraFence::WHM::I18n->new( dir => "$ROOT/plugin/locale", lang => $lang || 'en', now => sub { NOW } );
}

# make_app(params => {...}, method => 'POST', scenario => 'empty', lang => 'it',
#          map => 'stale', score => 'old', prefs => InfraFence::WHM::Prefs->new(...), ...)
sub make_app {
    my (%o) = @_;
    return InfraFence::WHM::App->new(
        agent    => $o{agent} || mock_agent(%o),
        i18n     => i18n( $o{lang} ),
        map_dir  => "$ROOT/plugin/map",
        whm_lang => exists $o{whm_lang} ? $o{whm_lang} : ( $o{lang} || 'en' ),
        ( $o{prefs} ? ( prefs => $o{prefs} ) : () ),
        request => {
            method  => $o{method} || 'GET',
            params  => $o{params} || {},
            token   => exists $o{token} ? $o{token} : TOKEN,
            actor   => exists $o{actor} ? $o{actor} : 'root',
            host    => exists $o{host} ? $o{host} : 'host07.hosting.example:2087',
            origin  => $o{origin},
            referer => exists $o{referer} ? $o{referer} : 'https://host07.hosting.example:2087' . TOKEN . '/cgi/infrafence/index.cgi',
        },
    );
}

sub run_app { make_app(@_)->run }

my $TT;

sub render {
    my ($res) = @_;
    require Template;
    $TT ||= Template->new(
        INCLUDE_PATH => [ "$ROOT/dev/stub", "$ROOT/plugin/templates" ],
        STRICT       => 0,
    ) or die Template->error;
    my $out = '';
    $TT->process( $res->{template}, { data => $res->{data} }, \$out ) or die $TT->error . "\n";
    return $out;
}

1;
