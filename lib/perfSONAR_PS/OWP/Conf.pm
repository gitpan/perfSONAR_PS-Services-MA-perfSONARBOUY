package perfSONAR_PS::OWP::Conf;

require 5.005;
use strict;
use warnings;

our $VERSION = 0.08;

=head1 NAME

perfSONAR_PS::OWP::Conf

=head1 DESCRIPTION

This module is used to set configuration parameters for the OWP one-way-ping
mesh configuration.

To add additional "scalar" parameters, just start using them. If the new
parameter is a BOOL then also add it to the BOOL hash here. If the new
parameter is an array then add it to the ARRS hash.

=cut

# use POSIX;
use FindBin;

#$Conf::REVISION = '$Id: Conf.pm 1814 2008-03-10 19:10:27Z zurawski $';
#$Conf::VERSION='1.0';

# Eventually set using $sysconfig autoconf variable.
$Conf::CONFPATH = '~';    # default dir for config files.

$Conf::GLOBALCONFENV  = 'OWPGLOBALCONF';
$Conf::DEVCONFENV     = 'OWPCONF';
$Conf::GLOBALCONFNAME = 'owmesh.conf';

#
# This hash is used to privide default values for "some" parameters.
#
my %DEFS = (
    OWAMPDPIDFILE  => 'owampd.pid',
    OWAMPDINFOFILE => 'owampd.info',
    OWPBINDIR      => "$FindBin::Bin",
    CONFDIR        => "$Conf::CONFPATH/",
);

# Opts that are arrays.
# (These options are automatically split with whitespace - and the return
# is set as an array reference. These options can also show up on more
# than one line, and the values will append onto the array.)
# (Syntax is [val val val] )
my %ARRS;

# Keep hash of all 'types' of sub-hashes in the config hash.
my %HASHOPTS;

=head2 new()

TDB

=cut

sub new {
    my ( $class, @initialize ) = @_;
    my $self = {};

    bless $self, $class;

    $self->init(@initialize);

    return $self;
}

=head2 resolve_path()

TDB

=cut

sub resolve_path {
    my ( $self, $path ) = @_;
    my ( $home, $user, $key );

    if ( ( $path =~ m#^~/#o ) || ( $path =~ m#^~$#o ) ) {
        $home 
            = $ENV{"HOME"}
            || $ENV{"LOGDIR"}
            || ( getpwuid($<) )[7]
            || "BOGUSHOMEDIR";
        $path =~ s#^\~#$home#o;
    }
    elsif ( ($user) = ( $path =~ m#^~([^/]+)/.*#o ) ) {
        $home = ( getpwnam($user) )[7] || "BOGUSHOMEDIR";
        $path = $home . substr( $path, length($user) + 1 );
    }

    while ( ($key) = ( $path =~ m#\$([^\/]+)#o ) ) {
        $path =~ s/\$$key/$ENV{$key}/g;
    }
    while ( ($key) = ( $path =~ m#\$\{([^\}]+)\}#o ) ) {
        $path =~ s/\$\{$key\}/$ENV{$key}/g;
    }

    return $path;
}

=head2 load_line()

grok a single line from the config file, and adding that parameter
into the hash ref passed in, unless skip is set.

=cut

sub load_line {
    my ( $self, $line, $href, $skip ) = @_;
    my ( $pname, $val );

    $_ = $line;

    return 1 if (/^\s*#/);    # comments
    return 1 if (/^\s*$/);    # blank lines

    # reset any var
    if ( ($pname) = /^\!(\w+)\s+/o ) {
        $pname =~ tr/a-z/A-Z/;
        delete ${$href}{$pname} if ( !defined($skip) );
        return 1;
    }

    # bool
    if ( ($pname) = /^(\w+)\s*$/o ) {
        $pname =~ tr/a-z/A-Z/;
        ${$href}{$pname} = 1 if ( !defined($skip) );
        return 1;
    }

    # array assignment
    if ( ( ( $pname, $val ) = /^(\w+)\s+\[(.*?)\]\s*$/o ) ) {
        $_ = $val;
        $pname =~ tr/a-z/A-Z/;
        $ARRS{$pname} = 1;
        return 1 if ( defined($skip) );
        push @{ ${$href}{$pname} }, split;
        return 1;
    }

    # assignment
    if ( ( ( $pname, $_ ) = /^(\w+)\s+(.*?)\s*$/o ) ) {
        return 1 if ( defined($skip) );
        $pname =~ tr/a-z/A-Z/;

        # reset boolean
        if ( /^undef$/oi || /^off$/oi || /^false$/oi || /^no$/oi ) {
            delete ${$href}{$pname} if ( defined( ${$href}{$pname} ) );
            return 1;
        }
        elsif ( defined( $ARRS{$pname} ) ) {
            push @{ ${$href}{$pname} }, split;
        }
        else {
            ${$href}{$pname} = $_;
            if ( /\~/ || /\$/ ) {
                ${ ${$href}{'PATHOPTS'} }{$pname} = 1;
            }
        }
        return 1;
    }

    return 0;
}

=head2 load_regex_section()

TDB

=cut

sub load_regex_section {
    my ( $self, $line, $file, $fh, $type, $match, $count ) = @_;
    my ( $start, $end, $exp, $skip );

    # set start to expression matching <$type=($exp)>
    $start = sprintf "^<%s\\s\*=\\s\*\(\\S\+\)\\s\*>\\s\*", $type;

    # return 0 if this is not a BEGIN section <$type=$exp>
    return $count if ( !( ($exp) = ( $line =~ /$start/i ) ) );

    # set end to expression matching </$type>
    $end = sprintf "^<\\\/%s\\s\*>\\s\*", $type;

    # check if regex matches for this expression
    # (If it doesn't match, set skip so syntax matching will grok
    # lines without setting hash values.)
    $exp =~ s/([^\w\s-])/\\$1/g;
    $exp =~ s/\\\*/.\*/g;
    $exp =~ s/\\\?/./g;
    if ( !( $match =~ /$exp/ ) ) {
        $skip = 1;
    }

    #
    # Grok all lines in this sub-section
    #
    while (<$fh>) {
        $count++;
        last if (/$end/i);
        my $line = $_;
        chomp $line;
        die "Syntax error $file:$.:\"$line\"" if (/^</);
        next if $self->load_line( $line, $self, $skip );

        # Unknown format
        die "Syntax error $file:$.:\"$line\"";
    }
    return $count;
}

=head2 load_subhash()

TDB

=cut

sub load_subhash {
    my ( $self, $line, $file, $fh, $count ) = @_;
    my ( $type, $end, $name, %subhash );

    if ( !( ( $type, $name ) = /^<\s*(\S+)\s*=\s*(\S+)\s*>\s*$/i ) ) {
        return $count;
    }
    $name =~ tr/a-z/A-Z/;
    $type =~ tr/a-z/A-Z/;

    # Keep track of non scalar types to aid in retrieval
    $ARRS{ $type . "LIST" } = 1;
    $HASHOPTS{$type} = 1;

    # set end to expression matching </$type>
    $end = sprintf "^<\\\/%s\\s\*>\\s\*", $type;

    #
    # Grok all lines in this sub-section
    #
    while (<$fh>) {
        $count++;
        last if (/$end/i);
        die "Syntax error $file:$.:\"$_\"" if (/^</);
        next if $self->load_line( $_, \%subhash );

        # Unknown format
        die "Syntax error $file:$.:\"$_\"";
    }
    if ( exists( $self->{ $type . "-" . $name } ) ) {
        foreach ( keys %subhash ) {
            ${ $self->{ $type . "-" . $name } }{$_} = $subhash{$_};
        }
    }
    else {

        # Set info needed for value retrieval
        # Make a 'list' to enumerate all sub-hashes of this type
        push @{ $self->{ $type . 'LIST' } }, $name;
        %{ $self->{ $type . "-" . $name } } = %subhash;
    }
    return $count;
}

=head2 load_subfile()

TDB

=cut

sub load_subfile {
    my ( $self, $line, $count ) = @_;
    my ($newfile);

    if ( !( ($newfile) = ( $line =~ /^<\s*include\s*=\s*(\S+)\s*>\s*/i ) ) ) {
        return $count;
    }

    return $self->load_file( $self->resolve_path($newfile), $count );
}

=head2 load_file()

TDB

=cut

sub load_file {
    my ( $self, $file, $count ) = @_;
    my ( $sysname, $hostname ) = POSIX::uname();

    my ( $pname, $pval, $key, $outcount );
    local (*PFILE);
    open( PFILE, "<" . $file ) || die "Unable to open $file";
    while (<PFILE>) {
        my $line = $_;
        $count++;

        #
        # include files
        #
        $outcount = $self->load_subfile( $_, $count );
        if ( $outcount > $count ) {
            $count = $outcount;
            next;
        }

        #
        # regex matches
        #

        # HOSTNAME
        $outcount = $self->load_regex_section( $_, $file, \*PFILE, "HOST", $hostname, $count );
        if ( $outcount > $count ) {
            $count = $outcount;
            next;
        }

        # OS
        $outcount = $self->load_regex_section( $_, $file, \*PFILE, "OS", $sysname, $count );
        if ( $outcount > $count ) {
            $count = $outcount;
            next;
        }

        # sub-hash's
        $outcount = $self->load_subhash( $_, $file, \*PFILE, $count );
        if ( $outcount > $count ) {
            $count = $outcount;
            next;
        }

        # global options
        next if $self->load_line( $_, $self );

        die "Syntax error $file:$count:\"$line\"";
    }

    $count;
}

=head2 init()

TDB

=cut

sub init {
    my ( $self, %args ) = @_;
    my ( $confdir, $nodename );
    my ( $name,    $file, $key );
    my ( $sysname, $hostname ) = POSIX::uname();

ARG:
    foreach ( keys %args ) {
        $name = $_;
        $name =~ tr/a-z/A-Z/;
        if ( $name ne $_ ) {
            $args{$name} = $args{$_};
            delete $args{$_};
        }
        /^confdir$/oi and $confdir  = $args{$name}, next ARG;
        /^node$/oi    and $nodename = $args{$name}, next ARG;
    }

    if ( !defined($nodename) ) {
        ($nodename) = ( $hostname =~ /^[^-]*-(\w*)/o )
            and $nodename =~ tr/a-z/A-Z/;
        $self->{'NODE'} = $nodename if ( defined($nodename) );
    }

    #
    # Global conf file
    #
    if ( defined( $ENV{$Conf::GLOBALCONFENV} ) ) {
        $file = $self->resolve_path( $ENV{$Conf::GLOBALCONFENV} );
    }
    elsif ( defined($confdir) ) {
        $file = $self->resolve_path( $confdir . '/' . $Conf::GLOBALCONFNAME );
    }
    else {
        $file = $self->resolve_path( $DEFS{CONFDIR} . '/' . $Conf::GLOBALCONFNAME );
    }
    if ( -e $file ) {
        $self->{'GLOBALCONF'} = $file;
    }
    else {
        die "Unable to open Global conf:$file";
    }
    $self->load_file( $self->{'GLOBALCONF'}, 0 );

    undef $file;

    if ( defined( $ENV{$Conf::DEVCONFENV} ) ) {
        $file = $self->resolve_path( $ENV{$Conf::DEVCONFENV} );
    }

    if ( defined($file) and -e $file ) {
        $self->{'DEVNODECONF'} = $file;
    }
    else {
    }
    $self->load_file( $self->{'DEVNODECONF'}, 0 )
        if defined( $self->{'DEVNODECONF'} );

    #
    # args passed in as initializers over-ride everything else.
    #
    foreach $key ( keys %args ) {
        $self->{$key} = $args{$key};
    }

    #
    # hard coded	(this modules fallbacks)
    #
    foreach $key ( keys(%DEFS) ) {
        $self->{$key} = $DEFS{$key} if ( !defined( $self->{$key} ) );
    }

    1;
}

=head2 get_ref()

TDB

=cut

sub get_ref {
    my ( $self, %args ) = @_;
    my ( $type, $attr, $fullattr, $hopt, $name, @subhash, $ref ) = ( undef, undef, undef, undef, undef, undef, undef );

ARG:
    foreach ( keys %args ) {
        /^attr$/oi and $attr = $args{$_}, next ARG;
        /^type$/oi and $type = $args{$_}, next ARG;
        foreach $hopt ( keys %HASHOPTS ) {
            if (/^$hopt$/i) {
                $name = $args{$_};
                $name =~ tr/a-z/A-Z/;
                if ( defined( $self->{ $hopt . "-" . $name } ) ) {
                    push @subhash, $self->{ $hopt . "-" . $name };
                }
                next ARG;
            }
        }
        die "Unknown named parameter $_ passed into get_ref";
    }

    return undef if ( !defined $attr );
    $attr =~ tr/a-z/A-Z/;

    if ( defined $type ) {
        $fullattr = $type . $attr;
        $fullattr =~ tr/a-z/A-Z/;
    }

    # Try sub-hashes
    my $dopath = 0;
    foreach (@subhash) {
        if ( ( defined $fullattr ) && ( defined ${$_}{$fullattr} ) ) {
            $ref = ${$_}{$fullattr};
            $dopath = 1 if ( defined ${$_}{'PATHOPTS'}
                && defined ${ ${$_}{'PATHOPTS'} }{$fullattr} );
        }
        elsif ( defined ${$_}{$attr} ) {
            $ref = ${$_}{$attr};
            $dopath = 1 if ( defined ${$_}{'PATHOPTS'}
                && defined ${ ${$_}{'PATHOPTS'} }{$attr} );
        }
    }

    # If no value found in sub-hash, try global level
    if ( !defined $ref ) {
        if ( ( defined $fullattr ) && ( defined $self->{$fullattr} ) ) {
            $ref = $self->{$fullattr};
            $dopath = 1 if ( defined( $self->{'PATHOPTS'} )
                && defined( ${ $self->{'PATHOPTS'} }{$fullattr} ) );
        }
        elsif ( defined $self->{$attr} ) {
            $ref = $self->{$attr};
            $dopath = 1 if ( defined $self->{'PATHOPTS'}
                && defined ${ $self->{'PATHOPTS'} }{$attr} );
        }
    }

    if ( $ref && $dopath ) {
        return $self->resolve_path($ref);
    }

    return $ref;
}

=head2 get_val()

This is a convienence routine that returns no value
if the value isn't retrievable.

=cut

sub get_val {
    my ( $self, %args ) = @_;
    my ($ref);

    for ( $ref = $self->get_ref(%args) ) {
        return if ( !defined($_) );
        /SCALAR/ and return $$ref;
        /HASH/   and return %$ref;
        /ARRAY/  and return @$ref;
        die "Invalid value in hash!?" if ( ref($ref) );

        # return actual value
        return $ref;
    }

    # not reached
    return undef;
}

=head2 must_get_val()

This is a convienence routine that dies with
an error message if the value isn't retrievable.

=cut

sub must_get_val {
    my ( $self, %args ) = @_;
    my ($ref);

    for ( $ref = $self->get_ref(%args) ) {

        # undef:break out and report error.
        last if ( !defined($_) );
        /SCALAR/ and return $$ref;
        /HASH/   and return %$ref;
        /ARRAY/  and return @$ref;
        die "Invalid value in hash!?" if ( ref($ref) );

        # return actual value.
        return $ref;
    }

    my ($emsg) = "";
    $emsg .= "$_=>$args{$_}, " for ( keys %args );
    my ( $dummy, $fname, $line ) = caller;
    die "Conf::must_get_val($emsg) undefined, called from $fname\:$line\n";
}

=head2 get_sublist()

This is a convienence routine that returns values from a LIST
if and only if the sub-hash has a particular value set.

=cut

sub get_sublist {
    my ( $self, %args ) = @_;
    my ($ref);
    my ( $list, $attr, $value );

ARG:
    foreach ( keys %args ) {
        /^list$/oi  and $list  = $args{$_}, next ARG;
        /^attr$/oi  and $attr  = $args{$_}, next ARG;
        /^value$/oi and $value = $args{$_}, next ARG;
        die "Unknown named parameter $_ passed into get_ref";
    }

    return undef if ( !defined($list) );

    $list =~ tr/a-z/A-Z/;
    my @list = $self->get_val( ATTR => $list . 'LIST' );

    # return full list if no qualifier attached
    return @list if ( !defined($attr) );

    # determine qualified sublist using attr/value
    my @sublist;
    $attr =~ tr/a-z/A-Z/;

    foreach (@list) {
        my $subval = $self->get_val( $list => $_, ATTR => $attr );
        if ( defined($subval) && ( !defined($value) || ( $subval eq $value ) ) ) {
            push @sublist, $_;
        }
    }

    return if ( !scalar(@sublist) );
    return @sublist;
}

=head2 must_get_sublist()

This is a convienence routine that dies with
an error message if the value isn't retrievable.

=cut

sub must_get_sublist {
    my ( $self, %args ) = @_;
    my ($ref);

    my @sublist = $self->get_sublist(%args);

    return @sublist if ( scalar @sublist );

    my ($emsg) = "";
    $emsg .= "$_=>$args{$_}, " for ( keys %args );
    my ( $dummy, $fname, $line ) = caller;
    die "Conf::must_get_sublist($emsg) undefined, called from $fname\:$line\n";
}

=head2 dump_hash()

TDB

=cut

sub dump_hash {
    my ( $self, $href, $pre ) = @_;
    my ($key);
    my ($rtnval) = "";

KEY:
    foreach $key ( sort keys %$href ) {
        my ($val);
        $val = "";
        for ( ref $href->{$key} ) {
            /^$/ and $rtnval .= $pre . $key . "=$href->{$key}\n", next KEY;
            /ARRAY/ and $rtnval 
                .= $pre 
                . $key . "=\["
                . join( ',', @{ $href->{$key} } ) . "\]\n",
                next KEY;
            /HASH/ and $rtnval .= $pre . $key . "[\n" . $self->dump_hash( $href->{$key}, "$pre\t" ) . $pre . "]\n", next KEY;
            die "Invalid hash value!";
        }
    }

    return $rtnval;
}

=head2 dump()

TDB

=cut

sub dump {
    my ($self) = @_;

    return $self->dump_hash( $self, "" );
}

=head2 get_mesh_description()

The Remaining functions should probably be moved into another module.
They assume a particular set of configuration options exist in the file.

=cut

sub get_mesh_description {
    my ( $self, %args ) = @_;
    my ($mesh);

ARG:
    foreach ( keys %args ) {
        /^mesh$/oi and $mesh = $args{$_}, next ARG;
        die "Unknown named parameter $_ passed into get_mesh_description";
    }

    return undef if ( !defined($mesh) );

    my ($addrtype);
    my ( @tarr, %thash );

    if ( !( $addrtype = $self->get_val( MESH => $mesh, ATTR => 'ADDRTYPE' ) ) ) {
        my ( $dummy, $fname, $line ) = caller;
        die "Conf::get_mesh_description(MESH=>$mesh) ATTR=>'ADDRTYPE' is undefined, called from $fname\:$line\n";
    }
    my %rhash;
    my $node;

    $rhash{'ADDRTYPE'} = $addrtype;
    $rhash{'EXCLUDE_SELF'} = $self->get_val( MESH => $mesh, ATTR => 'EXCLUDE_SELF' );

    # compile list of receivers
    @tarr = $self->get_val( MESH => $mesh, ATTR => 'NODES' );
    foreach $node (@tarr) {
        $thash{$node} = 1;
    }
    @tarr = $self->get_val( MESH => $mesh, ATTR => 'INCLUDE_RECEIVERS' );
    foreach $node (@tarr) {
        $thash{$node} = 1;
    }
    @tarr = $self->get_val( MESH => $mesh, ATTR => 'EXCLUDE_RECEIVERS' );
    foreach $node (@tarr) {
        $thash{$node} = 0;
    }

    # sort list into array for processing
    undef @tarr;
    foreach $node ( sort keys %thash ) {

        # skip if node excluded from this mesh
        next if ( !$thash{$node} );

        # skip if node does not have proper address for this mesh
        next if ( !( $self->get_val( NODE => $node, TYPE => $addrtype, ATTR => 'ADDR' ) ) );
        push @tarr, $node;
    }

    @{ $rhash{'RECEIVERS'} } = (@tarr);

    undef %thash;

    # compile list of senders
    @tarr = $self->get_val( MESH => $mesh, ATTR => 'NODES' );
    foreach $node (@tarr) {
        $thash{$node} = 1;
    }
    @tarr = $self->get_val( MESH => $mesh, ATTR => 'INCLUDE_SENDERS' );
    foreach $node (@tarr) {
        $thash{$node} = 1;
    }
    @tarr = $self->get_val( MESH => $mesh, ATTR => 'EXCLUDE_SENDERS' );
    foreach $node (@tarr) {
        $thash{$node} = 0;
    }

    # sort list into array for processing
    undef @tarr;
    foreach $node ( sort keys %thash ) {

        # skip if node excluded from this mesh
        next if ( !$thash{$node} );

        # skip if node does not have proper address for this mesh
        next if ( !( $self->get_val( NODE => $node, TYPE => $addrtype, ATTR => 'ADDR' ) ) );
        push @tarr, $node;
    }

    @{ $rhash{'SENDERS'} } = (@tarr);

    # bwctl can run the client from the central-db.
    $rhash{'CENTRALLY_INVOKED'} = $self->get_val(
        MESH => $mesh,
        ATTR => 'CENTRALLY_INVOKED'
    );

    return %rhash;
}

=head2 get_names_info()

Returns a list of crucial directories and filenames for the given resolution.
$datadirname is the link's data directory
$rel_dir is its (www) relative directory
$filename is only useful with mode 2, where it gives a relative
name for the summary line
$mode indicates whether the summary file is needed.

=cut

sub get_names_info {
    my ( $self, $mtype, $recv, $sender, $res ) = @_;
    my $rel_dir = $self->get_rel_path( $mtype, $recv, $sender );
    my $datadirname = join( '/', $self->must_get_val( ATTR => 'CENTRALDATADIR' ), $rel_dir, $res );

    my $full_www = join( '/', $self->must_get_val( ATTR => 'CENTRALWWWDIR' ), $rel_dir );

    my $summary_file = "$full_www/last_summary";

    my $www_reldir = "$rel_dir/$res";

    return ( $datadirname, $summary_file, $full_www );
}

=head2 get_rel_path()

Make a full www path out of the relative one.

=cut

sub get_rel_path {
    my ( $self, $mtype, $recv, $sender ) = @_;
    return "$mtype/$recv/$sender";
}

1;

__END__

=head1 USAGE

		my $conf = new perfSONAR_PS::OWP::Conf([
					NODE	=>	nodename,
					CONFDIR =>	path/to/confdir,
					])
		NODE will default to ($node) = ($hostname =~ /^.*-(/w)/) CONFDIR will
		default to $HOME

		The config files can have sections that are only relevant to a particular
		system/node/addr by using the pseudo httpd.conf file syntax:

		<OS=$regex>
		osspecificsettings	val
		</OS>

		The names for the headings are OS and Host. $regex is a text string used to
		match uname -s, and uname -n. It can contain the wildcard chars '*' and '?'
		with '*' matching 0 or more occurances of *anything* and '?' matching
		exactly 1 occurance of *anything*.

=head1 SEE ALSO

L<FindBin>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id: Conf.pm 1814 2008-03-10 19:10:27Z zurawski $

=head1 AUTHOR

Jeff Boote, boote@internet2.edu
Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2002-2008, Internet2

All rights reserved.

=cut
