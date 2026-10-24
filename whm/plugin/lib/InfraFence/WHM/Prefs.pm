package InfraFence::WHM::Prefs;

# Per WHM user preferences of the plugin (today only the language), one small
# JSON file per user:
#   /var/cpanel/infrafence-whm/prefs/<user>.json   {"lang":"it"}
#
# The directories are created 0700 and the files 0600, owned by the user the
# CGI runs as (root under cpsrvd). A file or directory that is a symlink, is
# owned by someone else or is writable by group or others is ignored, never
# followed or trusted. The user name is checked before it becomes a file name.

use strict;
use warnings;

use Fcntl qw(O_WRONLY O_CREAT O_EXCL O_RDONLY O_NOFOLLOW);
use File::Basename qw(dirname);
use JSON::PP ();

use InfraFence::WHM::Validate qw(valid_actor);

our $DIR = '/var/cpanel/infrafence-whm/prefs';

# The languages a user can choose: the code stored and sent by the form, and
# the language's own name (not translated).
our @LANGUAGES = (
    [ en      => 'English' ],
    [ it      => 'Italiano' ],
    [ es      => 'Español' ],
    [ fr      => 'Français' ],
    [ de      => 'Deutsch' ],
    [ 'pt-BR' => 'Português (Brasil)' ],
);

use constant MAX_SIZE => 4096;
use constant MARKER   => '.infrafence-whm';

sub new {
    my ( $class, %args ) = @_;
    return bless { dir => $args{dir} || $DIR }, $class;
}

sub valid_lang {
    my ($v) = @_;
    return undef unless defined $v;
    for (@LANGUAGES) {
        return $_->[0] if $_->[0] eq $v;
    }
    return undef;
}

sub _file {
    my ( $self, $user ) = @_;
    my $u = valid_actor($user);
    return undef unless defined $u && $u !~ /\A\.\.?\z/;
    return "$self->{dir}/$u.json";
}

# Owned by us, not a symlink, not writable by group or others.
sub _safe {
    my ( $path, $want_dir ) = @_;
    my @st = lstat $path or return 0;
    return 0 if -l _;
    return 0 if $want_dir ? !-d _ : !-f _;
    return 0 if $st[4] != $>;
    return 0 if $st[2] & 022;
    return 1;
}

# The user's language code, or undef when none was chosen (or it cannot be read safely).
sub lang {
    my ( $self, $user ) = @_;
    my $p = $self->get($user);
    return valid_lang( $p->{lang} );
}

sub get {
    my ( $self, $user ) = @_;
    my $file = $self->_file($user) or return {};
    return {} unless _safe( $self->{dir}, 1 ) && _safe( $file, 0 );
    sysopen my $fh, $file, O_RDONLY | O_NOFOLLOW or return {};
    my $raw = '';
    my $n = sysread $fh, $raw, MAX_SIZE + 1;
    close $fh;
    return {} unless defined $n && $n <= MAX_SIZE;
    my $data = eval { JSON::PP->new->utf8->decode($raw) };
    return {} unless ref $data eq 'HASH';
    my $lang = valid_lang( $data->{lang} );
    return defined $lang ? { lang => $lang } : {};
}

# Stores the user's language; undef removes the choice (back to the WHM
# language). Returns 1 on success.
sub set_lang {
    my ( $self, $user, $lang ) = @_;
    my $file = $self->_file($user) or return 0;
    if ( defined $lang ) {
        $lang = valid_lang($lang);
        return 0 unless defined $lang;
    }
    $self->_mkdirs or return 0;

    unless ( defined $lang ) {
        return 1 unless -e $file || -l $file;
        return unlink($file) ? 1 : 0;
    }

    my $tmp = "$file.$$.tmp";
    unlink $tmp if -l $tmp || -e $tmp;
    sysopen my $fh, $tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600 or return 0;
    my $ok = print {$fh} JSON::PP->new->canonical->encode( { lang => $lang } ), "\n";
    $ok = close($fh) && $ok;
    $ok &&= chmod 0600, $tmp;
    unless ( $ok && rename $tmp, $file ) {
        unlink $tmp;
        return 0;
    }
    return 1;
}

# The state directory and prefs/ under it, 0700. A directory that exists but
# is not safe is not used. The state directory carries the plugin's marker, so
# uninstall.sh knows it may remove it.
sub _mkdirs {
    my ($self) = @_;
    my $dir   = $self->{dir};
    my $state = dirname($dir);
    for my $d ( $state, $dir ) {
        unless ( -e $d || -l $d ) {
            mkdir $d, 0700 or return 0;
            chmod 0700, $d;
            if ( $d eq $state ) {
                sysopen my $m, "$d/" . MARKER, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600 or return 0;
                close $m;
            }
        }
        return 0 unless _safe( $d, 1 );
    }
    return 1;
}

1;
