package InfraFence::WHM::Agent;

# Runs `infrafence-agent panel <command> ... --json` and returns the decoded
# reply. The command is always started from an argv list (never a shell), with
# a clean environment, no stdin, a time limit and a cap on output size.
#
# Every failure is returned as a contract-style reply:
#   { ok => 0, error => '<code>', message => '...' }

use strict;
use warnings;

use Cwd ();
use IO::Select ();
use JSON::PP ();
use POSIX ();
use Time::HiRes ();

use InfraFence::WHM::Util qw(to_bytes);

our @SEARCH_PATH = qw(
  /usr/local/bin/infrafence-agent
  /usr/bin/infrafence-agent
  /usr/sbin/infrafence-agent
  /opt/infrafence/bin/infrafence-agent
);

use constant MAX_OUTPUT  => 8 * 1024 * 1024;
use constant SAFE_PATH   => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';

# Options:
#   bin           path to the agent; found in @SEARCH_PATH when not given
#   timeout       seconds per command (default 20)
#   strict_owner  refuse a binary unless it, and every directory from / down to
#                 it, is owned by root and not writable by group or others
#                 (default on; the tests turn it off)
#   env           extra environment for the child (tests only)
sub new {
    my ( $class, %args ) = @_;
    my $self = bless {
        timeout      => $args{timeout} || 20,
        strict_owner => exists $args{strict_owner} ? $args{strict_owner} : 1,
        env          => $args{env} || {},
        search       => $args{search} || \@SEARCH_PATH,
    }, $class;
    $self->{bin} = exists $args{bin} ? $args{bin} : $self->_find;
    return $self;
}

sub bin { $_[0]{bin} }

sub installed {
    my ($self) = @_;
    return defined $self->{bin} && -f $self->{bin} && -x _;
}

sub _find {
    my ($self) = @_;
    for my $p ( @{ $self->{search} } ) {
        return $p if -f $p && -x _;
    }
    return undef;
}

# The binary with every symlink resolved; that is the file checked and run.
sub _resolve {
    my ($self) = @_;
    return undef unless defined $self->{bin};
    my $real = Cwd::realpath( $self->{bin} );
    return undef unless defined $real && substr( $real, 0, 1 ) eq '/' && -f $real && -x _;
    return $real;
}

# Only root can change what is run: the file and each directory above it are
# owned by root and not writable by group or others (so a world-writable
# directory such as /tmp, even with the sticky bit, is refused).
sub _trusted {
    my ( $self, $real ) = @_;
    return 1 unless $self->{strict_owner};
    my @parts = grep { length } split m{/}, $real;
    my @paths = ('/');
    push @paths, '/' . join '/', @parts[ 0 .. $_ ] for 0 .. $#parts;
    for my $p (@paths) {
        my @st = lstat $p or return 0;
        return 0 if -l _;            # realpath() left no symlinks; one now is a race
        return 0 if $st[4] != 0;     # owned by root
        return 0 if $st[2] & 022;    # not writable by group or others
    }
    return 1;
}

# All the calls made until deadline(undef) share one time limit (an epoch,
# fractional seconds allowed), on top of each call's own timeout.
sub deadline {
    my ( $self, $at ) = @_;
    $self->{deadline} = $at;
    return;
}

sub _err {
    my ( $code, $message ) = @_;
    return { ok => 0, error => $code, message => defined $message ? $message : '' };
}

sub call {
    my ( $self, $command, @args ) = @_;
    return _err('not_installed') unless $self->installed;
    my $real = $self->_resolve;
    return _err('not_installed') unless defined $real;
    return _err('agent_untrusted') unless $self->_trusted($real);

    # Run the checked file itself, not the name that led to it.
    my @argv = ( $real, 'panel', $command, @args, '--json' );
    my ( $out, $exit, $failure ) = $self->_run(@argv);
    return _err($failure) if $failure;

    my $reply = eval { JSON::PP->new->utf8->decode($out) };
    return _err('bad_reply') unless ref $reply eq 'HASH' && exists $reply->{ok};
    $reply = to_bytes($reply);

    if ( $reply->{ok} ) {
        return _err('bad_reply') if $exit != 0;
        return $reply;
    }
    $reply->{error}   = 'unknown' unless defined $reply->{error} && length $reply->{error};
    $reply->{message} = ''        unless defined $reply->{message};
    return $reply;
}

# Returns (stdout, exit code, failure code or undef).
sub _run {
    my ( $self, @argv ) = @_;

    local $SIG{CHLD} = 'DEFAULT';
    local $SIG{PIPE} = 'IGNORE';

    my $deadline = Time::HiRes::time() + $self->{timeout};
    $deadline = $self->{deadline} if defined $self->{deadline} && $self->{deadline} < $deadline;
    return ( '', -1, 'timeout' ) if $deadline <= Time::HiRes::time();

    pipe( my $r, my $w ) or return ( '', -1, 'exec_failed' );
    my $pid = fork;
    return ( '', -1, 'exec_failed' ) unless defined $pid;

    if ( $pid == 0 ) {
        close $r;
        open STDIN,  '<',  '/dev/null' or POSIX::_exit(127);
        open STDOUT, '>&', $w          or POSIX::_exit(127);
        open STDERR, '>',  '/dev/null' or POSIX::_exit(127);
        %ENV = ( PATH => SAFE_PATH, LANG => 'C', %{ $self->{env} } );
        { exec {$argv[0]} @argv; }
        POSIX::_exit(127);
    }

    close $w;
    my $buf = '';
    my $sel = IO::Select->new($r);
    my $failure;

    while (1) {
        my $left = $deadline - Time::HiRes::time();
        if ( $left <= 0 ) { $failure = 'timeout'; last }
        next unless $sel->can_read($left);
        my $n = sysread $r, $buf, 65536, length $buf;
        if ( !defined $n ) {
            next if $!{EINTR} || $!{EAGAIN};
            $failure = 'exec_failed';
            last;
        }
        last if $n == 0;
        if ( length $buf > MAX_OUTPUT ) { $failure = 'bad_reply'; last }
    }
    close $r;

    if ($failure) {
        kill 'TERM', $pid;
        for ( 1 .. 20 ) {
            last if waitpid( $pid, POSIX::WNOHANG() ) == $pid;
            select undef, undef, undef, 0.1;
        }
        kill 'KILL', $pid;
        waitpid $pid, 0;
        return ( '', -1, $failure );
    }

    waitpid $pid, 0;
    my $exit = ( $? & 127 ) ? -1 : $? >> 8;
    return ( '', $exit, 'exec_failed' ) if $exit == 127 && $buf eq '';
    return ( $buf, $exit, undef );
}

1;
