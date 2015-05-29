#
# DX cluster user routines
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#

package DXUser;

use DXLog;
use DB_File;
use Data::Dumper;
use Fcntl;
use IO::File;
use DXDebug;
use DXUtil;
use LRU;

use strict;

use vars qw(%u $dbm $filename %valid $lastoperinterval $lasttime $lru $lrusize $tooold $v3);

%u = ();
$dbm = undef;
$filename = undef;
$lastoperinterval = 60*24*60*60;
$lasttime = 0;
$lrusize = 2000;
$tooold = 86400 * 365;		# this marks an old user who hasn't given enough info to be useful
$v3 = 0;

# hash of valid elements and a simple prompt
%valid = (
		  call => '0,Callsign',
		  alias => '0,Real Callsign',
		  name => '0,Name',
		  qth => '0,Home QTH',
		  lat => '0,Latitude,slat',
		  long => '0,Longitude,slong',
		  qra => '0,Locator',
		  email => '0,E-mail Address,parray',
		  priv => '9,Privilege Level',
		  lastin => '0,Last Time in,cldatetime',
		  passwd => '9,Password,yesno',
		  passphrase => '9,Pass Phrase,yesno',
		  addr => '0,Full Address',
		  'sort' => '0,Type of User', # A - ak1a, U - User, S - spider cluster, B - BBS
		  xpert => '0,Expert Status,yesno',
		  bbs => '0,Home BBS',
		  node => '0,Last Node',
		  homenode => '0,Home Node',
		  lockout => '9,Locked out?,yesno',	# won't let them in at all
		  dxok => '9,Accept DX Spots?,yesno', # accept his dx spots?
		  annok => '9,Accept Announces?,yesno', # accept his announces?
		  lang => '0,Language',
		  hmsgno => '0,Highest Msgno',
		  group => '0,Group,parray',	# used to create a group of users/nodes for some purpose or other
		  buddies => '0,Buddies,parray',
		  isolate => '9,Isolate network,yesno',
		  wantbeep => '0,Req Beep,yesno',
		  wantann => '0,Req Announce,yesno',
		  wantwwv => '0,Req WWV,yesno',
		  wantwcy => '0,Req WCY,yesno',
		  wantecho => '0,Req Echo,yesno',
		  wanttalk => '0,Req Talk,yesno',
		  wantwx => '0,Req WX,yesno',
		  wantdx => '0,Req DX Spots,yesno',
		  wantemail => '0,Req Msgs as Email,yesno',
		  pagelth => '0,Current Pagelth',
		  pingint => '9,Node Ping interval',
		  nopings => '9,Ping Obs Count',
		  wantlogininfo => '0,Login Info Req,yesno',
          wantgrid => '0,Show DX Grid,yesno',
		  wantann_talk => '0,Talklike Anns,yesno',
		  wantpc16 => '9,Want Users from node,yesno',
		  wantsendpc16 => '9,Send PC16,yesno',
		  wantroutepc19 => '9,Route PC19,yesno',
		  wantusstate => '0,Show US State,yesno',
		  wantdxcq => '0,Show CQ Zone,yesno',
		  wantdxitu => '0,Show ITU Zone,yesno',
		  wantqtc => '0,Show if spot has new qtc telegrams,yesno',
		  wantqtc_as_comment => '0,Write qtc Information to Comments instead of Info,yesno',
		  wantgtk => '0,Want GTK interface,yesno',
		  wantpc9x => '0,Want PC9X interface,yesno',
		  lastoper => '9,Last for/oper,cldatetime',
		  nothere => '0,Not Here Text',
		  registered => '9,Registered?,yesno',
		  prompt => '0,Required Prompt',
		  version => '1,Version',
		  build => '1,Build',
		  believe => '1,Believable nodes,parray',
		  lastping => '1,Last Ping at,ptimelist',
		  maxconnect => '1,Max Connections',
		 );

#no strict;
sub AUTOLOAD
{
	no strict;
	my $name = $AUTOLOAD;
  
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
       goto &$AUTOLOAD;
}

#use strict;

#
# initialise the system
#
sub init
{
	my ($pkg, $fn, $mode) = @_;
  
	confess "need a filename in User" if !$fn;

	my $ufn;
	my $convert;
	
	eval {
		require Storable;
	};

#	eval "use Storable qw(nfreeze thaw)";
	
	if ($@) {
		$ufn = "$fn.v2";
		$v3 = $convert = 0;
		dbg("the module Storable appears to be missing!!");
		dbg("trying to continue in compatibility mode (this may fail)");
		dbg("please install Storable from CPAN as soon as possible");
	} else {
		import Storable qw(nfreeze thaw);

		$ufn = "$fn.v3";
		$v3 = 1;
		$convert++ if -e "$fn.v2" && !-e $ufn;
	}
	
	if ($mode) {
		$dbm = tie (%u, 'DB_File', $ufn, O_CREAT|O_RDWR, 0666, $DB_BTREE) or confess "can't open user file: $fn ($!) [rebuild it from user_asc?]";
	} else {
		$dbm = tie (%u, 'DB_File', $ufn, O_RDONLY, 0666, $DB_BTREE) or confess "can't open user file: $fn ($!) [rebuild it from user_asc?]";
	}

	die "Cannot open $ufn ($!)\n" unless $dbm;

	$lru = LRU->newbase("DXUser", $lrusize);
	
	# do a conversion if required
	if ($dbm && $convert) {
		my ($key, $val, $action, $count, $err) = ('','',0,0,0);
		
		my %oldu;
		dbg("Converting the User File to V3 ");
		dbg("This will take a while, I suggest you go and have cup of strong tea");
		my $odbm = tie (%oldu, 'DB_File', "$fn.v2", O_RDONLY, 0666, $DB_BTREE) or confess "can't open user file: $fn.v2 ($!) [rebuild it from user_asc?]";
        for ($action = R_FIRST; !$odbm->seq($key, $val, $action); $action = R_NEXT) {
			my $ref = asc_decode($val);
			if ($ref) {
				$ref->put;
				$count++;
			} else {
				$err++
			}
		} 
		undef $odbm;
		untie %oldu;
		dbg("Conversion completed $count records $err errors");
	}
	$filename = $ufn;
}

sub del_file
{
	my ($pkg, $fn) = @_;
  
	confess "need a filename in User" if !$fn;
	$fn .= $v3 ? ".v3" : ".v2";
	unlink $fn;
}

#
# periodic processing
#
sub process
{
	if ($main::systime > $lasttime + 15) {
		$dbm->sync;
		$lasttime = $main::systime;
	}
}

#
# close the system
#

sub finish
{
	undef $dbm;
	untie %u;
}

#
# new - create a new user
#

sub alloc
{
	my $pkg = shift;
	my $call = uc shift;
	my $self = bless {call => $call, 'sort'=>'U'}, $pkg;
	return $self;
}

sub new
{
	my $pkg = shift;
	my $call = shift;
	#  $call =~ s/-\d+$//o;
  
#	confess "can't create existing call $call in User\n!" if $u{$call};

	my $self = $pkg->alloc($call);
	$self->put;
	return $self;
}

#
# get - get an existing user - this seems to return a different reference everytime it is
#       called - see below
#

sub get
{
	my $call = uc shift;
	my $data;
	
	# is it in the LRU cache?
	my $ref = $lru->get($call);
	return $ref if $ref && ref $ref eq 'DXUser';
	
	# search for it
	unless ($dbm->get($call, $data)) {
		$ref = decode($data);
		if ($ref) {
			if (!UNIVERSAL::isa($ref, 'DXUser')) {
				dbg("DXUser::get: got strange answer from decode of $call". ref $ref. " ignoring");
				return undef;
			}
			# we have a reference and it *is* a DXUser
		} else {
			dbg("DXUser::get: no reference returned from decode of $call $!");
			return undef;
		}
		$lru->put($call, $ref);
		return $ref;
	}
	return undef;
}

#
# get an existing either from the channel (if there is one) or from the database
#
# It is important to note that if you have done a get (for the channel say) and you
# want access or modify that you must use this call (and you must NOT use get's all
# over the place willy nilly!)
#

sub get_current
{
	my $call = uc shift;
  
	my $dxchan = DXChannel::get($call);
	if ($dxchan) {
		my $ref = $dxchan->user;
		return $ref if $ref && UNIVERSAL::isa($ref, 'DXUser');

		dbg("DXUser::get_current: got invalid user ref for $call from dxchan $dxchan->{call} ". ref $ref. " ignoring");
	}
	return get($call);
}

#
# get all callsigns in the database 
#

sub get_all_calls
{
	return (sort keys %u);
}

#
# put - put a user
#

sub put
{
	my $self = shift;
	confess "Trying to put nothing!" unless $self && ref $self;
	my $call = $self->{call};

	$dbm->del($call);
	delete $self->{annok} if $self->{annok};
	delete $self->{dxok} if $self->{dxok};

	$lru->put($call, $self);
	my $ref = $self->encode;
	$dbm->put($call, $ref);
}

# freeze the user
sub encode
{
	goto &asc_encode unless $v3;
	my $self = shift;
	return nfreeze($self);
}

# thaw the user
sub decode
{
	goto &asc_decode unless $v3;
	return thaw(shift);
}

# 
# create a string from a user reference (in_ascii)
#
sub asc_encode
{
	my $self = shift;
	my $strip = shift;
	my $p;

	if ($strip) {
		my $ref = bless {}, ref $self;
		foreach my $k (qw(qth lat long qra sort call homenode node lastoper lastin)) {
			$ref->{$k} = $self->{$k} if exists $self->{$k};
		}
		$ref->{name} = $self->{name} if exists $self->{name} && $self->{name} !~ /selfspot/i;
		$p = dd($ref);
	} else {
		$p = dd($self);
	}
	return $p;
}

#
# create a hash from a string (in ascii)
#
sub asc_decode
{
	my $s = shift;
	my $ref;
	$s =~ s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
	eval '$ref = ' . $s;
	if ($@) {
		LogDbg('err', $@);
		$ref = undef;
	}
	return $ref;
}

#
# del - delete a user
#

sub del
{
	my $self = shift;
	my $call = $self->{call};
	$lru->remove($call);
	$dbm->del($call);
}

#
# close - close down a user
#

sub close
{
	my $self = shift;
	$self->{lastin} = time;
	$self->put();
}

#
# sync the database
#

sub sync
{
	$dbm->sync;
}

#
# return a list of valid elements 
# 

sub fields
{
	return keys(%valid);
}


#
# export the database to an ascii file
#

sub export
{
	my $fn = shift;
	my $basic_info_only = shift;
	
	# save old ones
	rename "$fn.oooo", "$fn.ooooo" if -e "$fn.oooo";
	rename "$fn.ooo", "$fn.oooo" if -e "$fn.ooo";
	rename "$fn.oo", "$fn.ooo" if -e "$fn.oo";
	rename "$fn.o", "$fn.oo" if -e "$fn.o";
	rename "$fn", "$fn.o" if -e "$fn";

	my $count = 0;
	my $err = 0;
	my $del = 0;
	my $fh = new IO::File ">$fn" or return "cannot open $fn ($!)";
	if ($fh) {
		my $key = 0;
		my $val = undef;
		my $action;
		my $t = scalar localtime;
		print $fh q{#!/usr/bin/perl
#
# The exported userfile for a DXSpider System
#
# Input file: $filename
#       Time: $t
#
			
package main;
			
# search local then perl directories
BEGIN {
	umask 002;
				
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
	
	# try to detect a lockfile (this isn't atomic but 
	# should do for now
	$lockfn = "$root/local/cluster.lck";       # lock file name
	if (-e $lockfn) {
		open(CLLOCK, "$lockfn") or die "Can't open Lockfile ($lockfn) $!";
		my $pid = <CLLOCK>;
		chomp $pid;
		die "Lockfile ($lockfn) and process $pid exists - cluster must be stopped first\n" if kill 0, $pid;
		close CLLOCK;
	}
}

package DXUser;

use DXVars;
use DXUser;

if (@ARGV) {
	$main::userfn = shift @ARGV;
	print "user filename now $userfn\n";
}

DXUser->del_file($main::userfn);
DXUser->init($main::userfn, 1);
%u = ();
my $count = 0;
my $err = 0;
while (<DATA>) {
	chomp;
	my @f = split /\t/;
	my $ref = asc_decode($f[1]);
	if ($ref) {
		$ref->put();
		$count++;
	} else {
		print "# Error: $f[0]\t$f[1]\n";
		$err++
	}
}
DXUser->sync; DXUser->finish;
print "There are $count user records and $err errors\n";
};
		print $fh "__DATA__\n";

        for ($action = R_FIRST; !$dbm->seq($key, $val, $action); $action = R_NEXT) {
			if (!is_callsign($key) || $key =~ /^0/) {
				my $eval = $val;
				my $ekey = $key;
				$eval =~ s/([\%\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg; 
				$ekey =~ s/([\%\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg; 
				LogDbg('DXCommand', "Export Error1: $ekey\t$eval");
				eval {$dbm->del($key)};
				dbg(carp("Export Error1: $ekey\t$eval\n$@")) if $@;
				++$err;
				next;
			}
			my $ref = decode($val);
			if ($ref) {
				my $t = $ref->{lastin} || 0;
				if ($ref->{sort} eq 'U' && !$ref->{priv} && $main::systime > $t + $tooold) {
					unless ($ref->{lat} && $ref->{long} || $ref->{qth} || $ref->{qra}) {
						eval {$dbm->del($key)};
						dbg(carp("Export Error2: $key\t$val\n$@")) if $@;
						LogDbg('DXCommand', "$ref->{call} deleted, too old");
						$del++;
						next;
					}
				}
				# only store users that are reasonably active or have useful information
				print $fh "$key\t" . $ref->asc_encode($basic_info_only) . "\n";
				++$count;
			} else {
				LogDbg('DXCommand', "Export Error3: $key\t$val");
				eval {$dbm->del($key)};
				dbg(carp("Export Error3: $key\t$val\n$@")) if $@;
				++$err;
			}
		} 
        $fh->close;
    } 
	return "$count Users $del Deleted $err Errors ('sh/log Export' for details)";
}

#
# group handling
#

# add one or more groups
sub add_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	$self->{group} = $ref if !$self->{group};
	push @$ref, @_ if @_;
}

# remove one or more groups
sub del_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	my @in = @_;
	
	$self->{group} = $ref if !$self->{group};
	
	@$ref = map { my $a = $_; return (grep { $_ eq $a } @in) ? () : $a } @$ref;
}

# does this thing contain all the groups listed?
sub union
{
	my $self = shift;
	my $ref = $self->{group};
	my $n;
	
	return 0 if !$ref || @_ == 0;
	return 1 if @$ref == 0 && @_ == 0;
	for ($n = 0; $n < @_; ) {
		for (@$ref) {
			my $a = $_;
			$n++ if grep $_ eq $a, @_; 
		}
	}
	return $n >= @_;
}

# simplified group test just for one group
sub in_group
{
	my $self = shift;
	my $s = shift;
	my $ref = $self->{group};
	
	return 0 if !$ref;
	return grep $_ eq $s, $ref;
}

# set up a default group (only happens for them's that connect direct)
sub new_group
{
	my $self = shift;
	$self->{group} = [ 'local' ];
}

# set up empty buddies (only happens for them's that connect direct)
sub new_buddies
{
	my $self = shift;
	$self->{buddies} = [  ];
}

#
# return a prompt for a field
#

sub field_prompt
{ 
	my ($self, $ele) = @_;
	return $valid{$ele};
}

# some variable accessors
sub sort
{
	my $self = shift;
	@_ ? $self->{'sort'} = shift : $self->{'sort'} ;
}

# some accessors

# want is default = 1
sub _want
{
	my $n = shift;
	my $self = shift;
	my $val = shift;
	my $s = "want$n";
	$self->{$s} = $val if defined $val;
	return exists $self->{$s} ? $self->{$s} : 1;
}

# wantnot is default = 0
sub _wantnot
{
	my $n = shift;
	my $self = shift;
	my $val = shift;
	my $s = "want$n";
	$self->{$s} = $val if defined $val;
	return exists $self->{$s} ? $self->{$s} : 0;
}

sub wantbeep
{
	return _want('beep', @_);
}

sub wantann
{
	return _want('ann', @_);
}

sub wantwwv
{
	return _want('wwv', @_);
}

sub wantwcy
{
	return _want('wcy', @_);
}

sub wantecho
{
	return _want('echo', @_);
}

sub wantwx
{
	return _want('wx', @_);
}

sub wantdx
{
	return _want('dx', @_);
}

sub wanttalk
{
	return _want('talk', @_);
}

sub wantgrid
{
	return _want('grid', @_);
}

sub wantemail
{
	return _want('email', @_);
}

sub wantann_talk
{
	return _want('ann_talk', @_);
}

sub wantpc16
{
	return _want('pc16', @_);
}

sub wantsendpc16
{
	return _want('sendpc16', @_);
}

sub wantroutepc16
{
	return _want('routepc16', @_);
}

sub wantusstate
{
	return _want('usstate', @_);
}

sub wantdxcq
{
	return _want('dxcq', @_);
}

sub wantdxitu
{
	return _want('dxitu', @_);
}

sub wantqtc
{
	return _want('qtc', @_);
}

sub wantqtc_as_comment
{
	# default should be to show qtc info in INFO not in comment field
	return _wantnot('qtc_as_comment', @_);
}

sub wantgtk
{
	return _want('gtk', @_);
}

sub wantpc9x
{
	return _want('pc9x', @_);
}

sub wantlogininfo
{
	my $self = shift;
	my $val = shift;
	$self->{wantlogininfo} = $val if defined $val;
	return $self->{wantlogininfo};
}

sub is_node
{
	my $self = shift;
	return $self->{sort} =~ /[ACRSX]/;
}

sub is_local_node
{
	my $self = shift;
	return grep $_ eq 'local_node', @{$self->{group}};
}

sub is_user
{
	my $self = shift;
	return $self->{sort} eq 'U';
}

sub is_bbs
{
	my $self = shift;
	return $self->{sort} eq 'B';
}

sub is_spider
{
	my $self = shift;
	return $self->{sort} eq 'S';
}

sub is_clx
{
	my $self = shift;
	return $self->{sort} eq 'C';
}

sub is_dxnet
{
	my $self = shift;
	return $self->{sort} eq 'X';
}

sub is_arcluster
{
	my $self = shift;
	return $self->{sort} eq 'R';
}

sub is_ak1a
{
	my $self = shift;
	return $self->{sort} eq 'A';
}

sub unset_passwd
{
	my $self = shift;
	delete $self->{passwd};
}

sub unset_passphrase
{
	my $self = shift;
	delete $self->{passphrase};
}

sub set_believe
{
	my $self = shift;
	my $call = uc shift;
	$self->{believe} ||= [];
	push @{$self->{believe}}, $call unless grep $_ eq $call, @{$self->{believe}};
}

sub unset_believe
{
	my $self = shift;
	my $call = uc shift;
	if (exists $self->{believe}) {
		$self->{believe} = [grep {$_ ne $call} @{$self->{believe}}];
		delete $self->{believe} unless @{$self->{believe}};
	}
}

sub believe
{
	my $self = shift;
	return exists $self->{believe} ? @{$self->{believe}} : ();
}

sub lastping
{
	my $self = shift;
	my $call = shift;
	$self->{lastping} ||= {};
	$self->{lastping} = {} unless ref $self->{lastping};
	my $b = $self->{lastping};
	$b->{$call} = shift if @_;
	return $b->{$call};	
}
1;
__END__





