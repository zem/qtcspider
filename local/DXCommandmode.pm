#!/usr/bin/perl
#
# This module impliments the user facing command mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
#
# 

package DXCommandmode;

#use POSIX;

@ISA = qw(DXChannel);

use POSIX qw(:math_h);
use DXUtil;
use DXChannel;
use DXUser;
use DXVars;
use DXDebug;
use DXM;
use DXLog;
use DXLogPrint;
use DXBearing;
use CmdAlias;
use Filter;
use Minimuf;
use DXDb;
use AnnTalk;
use WCY;
use Sun;
use Internet;
use Script;
use QSL;
use DB_File;
use VE7CC;
use DXXml;
use AsyncMsg;

use qtc::query;
use qtc::publish;
use qtc::interface::http;
use POSIX qw(strftime); 

use strict;
use vars qw(%Cache %cmd_cache $errstr %aliases $scriptbase %nothereslug
	$maxbadcount $msgpolltime $default_pagelth $cmdimportdir);

%Cache = ();					# cache of dynamically loaded routine's mod times
%cmd_cache = ();				# cache of short names
$errstr = ();					# error string from eval
%aliases = ();					# aliases for (parts of) commands
$scriptbase = "$main::root/scripts"; # the place where all users start scripts go
$maxbadcount = 3;				# no of bad words allowed before disconnection
$msgpolltime = 3600;			# the time between polls for new messages 
$cmdimportdir = "$main::root/cmd_import"; # the base directory for importing command scripts 
                                          # this does not exist as default, you need to create it manually
#

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
	my $self = DXChannel::alloc(@_);

	# routing, this must go out here to prevent race condx
	my $pkg = shift;
	my $call = shift;
#	my @rout = $main::routeroot->add_user($call, Route::here(1));
	DXProt::_add_thingy($main::routeroot, [$call, 0, 0, 1, undef, undef, $self->{conn}->peerhost], );

	# ALWAYS output the user
	my $ref = Route::User::get($call);
	if ($ref) {
		$main::me->route_pc16($main::mycall, undef, $main::routeroot, $ref);
		$main::me->route_pc92a($main::mycall, undef, $main::routeroot, $ref) unless $DXProt::pc92_slug_changes;
	}

	# we need a qtc query and a publisher
	if ( $main::qtc_root ) {
		$self->{qtc_query}=qtc::query->new(
			path=>$main::qtc_root
		); 
		if ( $main::qtc_privpath ) 
			my $qtc_interface; 
			if ( $main::qtc_interface_http_url ) {
				$qtc_interface=qtc::interface::http->new(
					path=>$main::qtc_root,
					url=>$main::qtc_interface_http_url,
				);
			}
			$self->{qtc_publish}=qtc::publish->new(
				path=>$main::qtc_root,
				privpath=>$main::qtc_privpath,
				interface=>$qtc_interface,
			); 
		}
	}
	return $self;
}

# this is how a a connection starts, you get a hello message and the motd with
# possibly some other messages asking you to set various things up if you are
# new (or nearly new and slacking) user.

sub start
{ 
	my ($self, $line, $sort) = @_;
	my $user = $self->{user};
	my $call = $self->{call};
	my $name = $user->{name};
	
	# log it
	my $host = $self->{conn}->peerhost;
	$host ||= "AGW Port #$self->{conn}->{agwport}" if exists $self->{conn}->{agwport};
	$host ||= "unknown";
	LogDbg('DXCommand', "$call connected from $host");

	$self->{name} = $name ? $name : $call;
	$self->send($self->msg('l2',$self->{name}));
	$self->state('prompt');		# a bit of room for further expansion, passwords etc
	$self->{priv} = $user->priv || 0;
	$self->{lang} = $user->lang || $main::lang || 'en';
	my $pagelth = $user->pagelth;
	$pagelth = $default_pagelth unless defined $pagelth;
	$self->{pagelth} = $pagelth;
	($self->{width}) = $line =~ /width=(\d+)/; $line =~ s/\s*width=\d+\s*//;
	$self->{width} = 80 unless $self->{width} && $self->{width} > 80;
	$self->{consort} = $line;	# save the connection type
	
	# set some necessary flags on the user if they are connecting
	$self->{beep} = $user->wantbeep;
	$self->{ann} = $user->wantann;
	$self->{wwv} = $user->wantwwv;
	$self->{wcy} = $user->wantwcy;
	$self->{talk} = $user->wanttalk;
	$self->{wx} = $user->wantwx;
	$self->{dx} = $user->wantdx;
	$self->{logininfo} = $user->wantlogininfo;
	$self->{ann_talk} = $user->wantann_talk;
	$self->{here} = 1;
	$self->{prompt} = $user->prompt if $user->prompt;

	# sort out new dx spot stuff
	$user->wantdxcq(0) unless defined $user->{wantdxcq};
	$user->wantdxitu(0) unless defined $user->{wantdxitu};	
	$user->wantusstate(0) unless defined $user->{wantusstate};

	# sort out registration
	if ($main::reqreg == 1) {
		$self->{registered} = $user->registered;
	} elsif ($main::reqreg == 2) {
		$self->{registered} = !$user->registered;
	} else {
		$self->{registered} = 1;
	}

	# send the relevant MOTD
	$self->send_motd;

	# sort out privilege reduction
	$self->{priv} = 0 if $line =~ /^(ax|te)/ && !$self->conn->{usedpasswd};

	# get the filters
	my $nossid = $call;
	$nossid =~ s/-\d+$//;
	
	$self->{spotsfilter} = Filter::read_in('spots', $call, 0) 
		|| Filter::read_in('spots', $nossid, 0)
			|| Filter::read_in('spots', 'user_default', 0);
	$self->{wwvfilter} = Filter::read_in('wwv', $call, 0) 
		|| Filter::read_in('wwv', $nossid, 0) 
			|| Filter::read_in('wwv', 'user_default', 0);
	$self->{wcyfilter} = Filter::read_in('wcy', $call, 0) 
		|| Filter::read_in('wcy', $nossid, 0) 
			|| Filter::read_in('wcy', 'user_default', 0);
	$self->{annfilter} = Filter::read_in('ann', $call, 0) 
		|| Filter::read_in('ann', $nossid, 0) 
			|| Filter::read_in('ann', 'user_default', 0) ;

	# clean up qra locators
	my $qra = $user->qra;
	$qra = undef if ($qra && !DXBearing::is_qra($qra));
	unless ($qra) {
		my $lat = $user->lat;
		my $long = $user->long;
		$user->qra(DXBearing::lltoqra($lat, $long)) if (defined $lat && defined $long);  
	}

	# decide on echo
	my $echo = $user->wantecho;
	unless ($echo) {
		$self->send_now('E', "0");
		$self->send($self->msg('echow'));
		$self->conn->echo($echo) if $self->conn->can('echo');
	}
	
	$self->tell_login('loginu');
	$self->tell_buddies('loginb');
	
	# do we need to send a forward/opernam?
	my $lastoper = $user->lastoper || 0;
	my $homenode = $user->homenode || ""; 
	if ($homenode eq $main::mycall && $main::systime >= $lastoper + $DXUser::lastoperinterval) {
		run_cmd($main::me, "forward/opernam $call");
		$user->lastoper($main::systime + ((int rand(10)) * 86400));
	}

	# run a script send the output to the punter
	my $script = new Script(lc $call) || new Script('user_default');
	$script->run($self) if $script;

	# send cluster info
	my $info = Route::cluster();
	$self->send("Cluster:$info");

	# send prompts for qth, name and things
	$self->send($self->msg('namee1')) if !$user->name;
	$self->send($self->msg('qthe1')) if !$user->qth;
	$self->send($self->msg('qll')) if !$user->qra || (!$user->lat && !$user->long);
	$self->send($self->msg('hnodee1')) if !$user->qth;
	$self->send($self->msg('m9')) if DXMsg::for_me($call);

	# send out any buddy messages for other people that are online
	foreach my $call (@{$user->buddies}) {
		my $ref = Route::User::get($call);
		if ($ref) {
			foreach my $node ($ref->parents) {
				$self->send($self->msg($node eq $main::mycall ? 'loginb' : 'loginbn', $call, $node));
			} 
		}
	}

	$self->lastmsgpoll($main::systime);
	$self->prompt;
}

#
# This is the normal command prompt driver
#

sub normal
{
	my $self = shift;
	my $cmdline = shift;
	my @ans;

	# save this for them's that need it
	my $rawline = $cmdline;
	
	# remove leading and trailing spaces
	$cmdline =~ s/^\s*(.*)\s*$/$1/;
	
	if ($self->{state} eq 'page') {
		my $i = $self->{pagelth};
		my $ref = $self->{pagedata};
		my $tot = @$ref;
		
		# abort if we get a line starting in with a
		if ($cmdline =~ /^a/io) {
			undef $ref;
			$i = 0;
		}
        
		# send a tranche of data
		while ($i-- > 0 && @$ref) {
			my $line = shift @$ref;
			$line =~ s/\s+$//o;	# why am having to do this? 
			$self->send($line);
		}
		
		# reset state if none or else chuck out an intermediate prompt
		if ($ref && @$ref) {
			$tot -= $self->{pagelth};
			$self->send($self->msg('page', $tot));
		} else {
			$self->state('prompt');
		}
	} elsif ($self->{state} eq 'sysop') {
		my $passwd = $self->{user}->passwd;
		if ($passwd) {
			my @pw = grep {$_ !~ /\s/} split //, $passwd;
			my @l = @{$self->{passwd}};
			my $str = "$pw[$l[0]].*$pw[$l[1]].*$pw[$l[2]].*$pw[$l[3]].*$pw[$l[4]]";
			if ($cmdline =~ /$str/) {
				$self->{priv} = $self->{user}->priv;
			} else {
				$self->send($self->msg('sorry'));
			}
		} else {
			$self->send($self->msg('sorry'));
		}
		$self->state('prompt');
	} elsif ($self->{state} eq 'passwd') {
		my $passwd = $self->{user}->passwd;
		if ($passwd && $cmdline eq $passwd) {
			$self->send($self->msg('pw1'));
			$self->state('passwd1');
		} else {
			$self->conn->{echo} = $self->conn->{decho};
			delete $self->conn->{decho};
			$self->send($self->msg('sorry'));
			$self->state('prompt');
		}
	} elsif ($self->{state} eq 'passwd1') {
		$self->{passwd} = $cmdline;
		$self->send($self->msg('pw2'));
		$self->state('passwd2');
	} elsif ($self->{state} eq 'passwd2') {
		if ($cmdline eq $self->{passwd}) {
			$self->{user}->passwd($cmdline);
			$self->send($self->msg('pw3'));
		} else {
			$self->send($self->msg('pw4'));
		}
		$self->conn->{echo} = $self->conn->{decho};
		delete $self->conn->{decho};
		$self->state('prompt');
	} elsif ($self->{state} eq 'talk' || $self->{state} eq 'chat') {
		if ($cmdline =~ m{^(?:/EX|/ABORT)}i) {
			for (@{$self->{talklist}}) {
				if ($self->{state} eq 'talk') {
					$self->send_talks($_,  $self->msg('talkend'));
				} else {
					$self->local_send('C', $self->msg('chatend', $_));
				}
			}
			$self->state('prompt');
			delete $self->{talklist};
		} elsif ($cmdline =~ m|^/+\w+|) {
			$cmdline =~ s|^/||;
			my $sendit = $cmdline =~ s|^/+||;
			my @in = $self->run_cmd($cmdline);
			$self->send_ans(@in);
			if ($sendit && $self->{talklist} && @{$self->{talklist}}) {
				foreach my $l (@in) {
					my @bad;
					if (@bad = BadWords::check($l)) {
						$self->badcount(($self->badcount||0) + @bad);
						LogDbg('DXCommand', "$self->{call} swore: $l with words:" . join(',', @bad) . ")");
					} else {
						for (@{$self->{talklist}}) {
							if ($self->{state} eq 'talk') {
								$self->send_talks($_, $l);
							} else {
								send_chats($self, $_, $l)
							}
						}
					}
				}
			}
			$self->send($self->{state} eq 'talk' ? $self->talk_prompt : $self->chat_prompt);
		} elsif ($self->{talklist} && @{$self->{talklist}}) {
			# send what has been said to whoever is in this person's talk list
			my @bad;
			if (@bad = BadWords::check($cmdline)) {
				$self->badcount(($self->badcount||0) + @bad);
				LogDbg('DXCommand', "$self->{call} swore: $cmdline with words:" . join(',', @bad) . ")");
			} else {
				for (@{$self->{talklist}}) {
					if ($self->{state} eq 'talk') {
						$self->send_talks($_, $rawline);
					} else {
						send_chats($self, $_, $rawline);
					}
				}
			}
			$self->send($self->talk_prompt) if $self->{state} eq 'talk';
			$self->send($self->chat_prompt) if $self->{state} eq 'chat';
		} else {
			# for safety
			$self->state('prompt');
		}
	} elsif (my $func = $self->{func}) {
		no strict 'refs';
		my @ans;
		if (ref $self->{edit}) {
			eval { @ans = $self->{edit}->$func($self, $rawline)};
		} else {
			eval {	@ans = &{$self->{func}}($self, $rawline) };
		}
		if ($@) {
			$self->send_ans("Syserr: on stored func $self->{func}", $@);
			delete $self->{func};
			$self->state('prompt');
			undef $@;
		}
		$self->send_ans(@ans);
	} else {
		$self->send_ans(run_cmd($self, $cmdline));
	} 

	# check for excessive swearing
	if ($self->{badcount} && $self->{badcount} >= $maxbadcount) {
		LogDbg('DXCommand', "$self->{call} logged out for excessive swearing");
		$self->disconnect;
		return;
	}

	# send a prompt only if we are in a prompt state
	$self->prompt() if $self->{state} =~ /^prompt/o;
}

# send out the talk messages taking into account vias and connectivity
sub send_talks
{
	my ($self, $ent, $line) = @_;
	
	my ($to, $via) = $ent =~ /(\S+)>(\S+)/;
	$to = $ent unless $to;
	my $call = $via && $via ne '*' ? $via : $to;
	my $clref = Route::get($call);
	my $dxchan = $clref->dxchan if $clref;
	if ($dxchan) {
		$dxchan->talk($self->{call}, $to, undef, $line);
	} else {
		$self->send($self->msg('disc2', $via ? $via : $to));
		my @l = grep { $_ ne $ent } @{$self->{talklist}};
		if (@l) {
			$self->{talklist} = \@l;
		} else {
			delete $self->{talklist};
			$self->state('prompt');
		}
	}
}

sub send_chats
{
	my $self = shift;
	my $target = shift;
	my $text = shift;

	my $msgid = DXProt::nextchatmsgid();
	$text = "#$msgid $text";
	$main::me->normal(DXProt::pc93($target, $self->{call}, undef, $text));
}

sub special_prompt
{
	my $self = shift;
	my $prompt = shift;
	my @call;
	for (@{$self->{talklist}}) {
		my ($to, $via) = /(\S+)>(\S+)/;
		$to = $_ unless $to;
		push @call, $to;
	}
	return $self->msg($prompt, join(',', @call));
}

sub talk_prompt
{
	my $self = shift;
	return $self->special_prompt('talkprompt');
}

sub chat_prompt
{
	my $self = shift;
	return $self->special_prompt('chatprompt');
}

#
# send a load of stuff to a command user with page prompting
# and stuff
#

sub send_ans
{
	my $self = shift;
	
	if ($self->{pagelth} && @_ > $self->{pagelth}) {
		my $i;
		for ($i = $self->{pagelth}; $i-- > 0; ) {
			my $line = shift @_;
			$line =~ s/\s+$//o;	# why am having to do this? 
			$self->send($line);
		}
		$self->{pagedata} =  [ @_ ];
		$self->state('page');
		$self->send($self->msg('page', scalar @_));
	} else {
		for (@_) {
			if (defined $_) {
				$self->send($_);
			} else {
				$self->send('');
			}
		}
	} 
}

# 
# this is the thing that runs the command, it is done like this for the 
# benefit of remote command execution
#

sub run_cmd
{
	my $self = shift;
	my $user = $self->{user};
	my $call = $self->{call};
	my $cmdline = shift;
	my @ans;
	
	return () if length $cmdline == 0;
	
	# split the command line up into parts, the first part is the command
	my ($cmd, $args) = split /\s+/, $cmdline, 2;
	$args = "" unless defined $args;
		
	if ($cmd) {

		# check cmd
		if ($cmd =~ m|^/| || $cmd =~ m|[^-?\w/]|) {
			LogDbg('DXCommand', "cmd: invalid characters in '$cmd'");
			return $self->_error_out('e1');
		}

		# strip out // on command only
		$cmd =~ s|//|/|g;
					
		my ($path, $fcmd);
			
		dbg("cmd: $cmd") if isdbg('command');
			
		# alias it if possible
		my $acmd = CmdAlias::get_cmd($cmd);
		if ($acmd) {
			($cmd, $args) = split /\s+/, "$acmd $args", 2;
			$args = "" unless defined $args;
			dbg("cmd: aliased $cmd $args") if isdbg('command');
		}
			
		# first expand out the entry to a command
		($path, $fcmd) = search($main::localcmd, $cmd, "pl");
		($path, $fcmd) = search($main::cmd, $cmd, "pl") unless $path && $fcmd;

		if ($path && $cmd) {
			dbg("cmd: path $cmd cmd: $fcmd") if isdbg('command');
			
			my $package = find_cmd_name($path, $fcmd);
			return ($@) if $@;
				
			if ($package && $self->can("${package}::handle")) {
				no strict 'refs';
				dbg("cmd: package $package") if isdbg('command');
				eval { @ans = &{"${package}::handle"}($self, $args) };
				return (DXDebug::shortmess($@)) if $@;
			} else {
				dbg("cmd: $package not present") if isdbg('command');
				return $self->_error_out('e1');
			}
		} else {
			dbg("cmd: $cmd not found") if isdbg('command');
			return $self->_error_out('e1');
		}
	}
	
	my $ok = shift @ans;
	if ($ok) {
		delete $self->{errors};
	} else {
		if (++$self->{errors} > $DXChannel::maxerrors) {
			$self->send($self->msg('e26'));
			$self->disconnect;
			return ();
		}
	}
	return map {s/([^\s])\s+$/$1/; $_} @ans;
}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub process
{
	my $t = time;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	
	foreach $dxchan (@dxchan) {
		next if $dxchan->sort ne 'U';  
	
		# send a outstanding message prompt if required
		if ($t >= $dxchan->lastmsgpoll + $msgpolltime) {
			$dxchan->send($dxchan->msg('m9')) if DXMsg::for_me($dxchan->call);
			$dxchan->lastmsgpoll($t);
		}
		
		# send a prompt if no activity out on this channel
		if ($t >= $dxchan->t + $main::user_interval) {
			$dxchan->prompt() if $dxchan->{state} =~ /^prompt/o;
			$dxchan->t($t);
		}
	}

	while (my ($k, $v) = each %nothereslug) {
		if ($main::systime >= $v + 300) {
			delete $nothereslug{$k};
		}
	}

	import_cmd();
}

#
# finish up a user context
#
sub disconnect
{
	my $self = shift;
	my $call = $self->call;

	return if $self->{disconnecting}++;

	delete $self->{senddbg};

	my $uref = Route::User::get($call);
	my @rout;
	if ($uref) {
#		@rout = $main::routeroot->del_user($uref);
		@rout = DXProt::_del_thingy($main::routeroot, [$call, 0]);

		dbg("B/C PC17 on $main::mycall for: $call") if isdbg('route');

		# issue a pc17 to everybody interested
		$main::me->route_pc17($main::mycall, undef, $main::routeroot, $uref);
		$main::me->route_pc92d($main::mycall, undef, $main::routeroot, $uref) unless $DXProt::pc92_slug_changes;
	} else {
		confess "trying to disconnect a non existant user $call";
	}

	# I was the last node visited
    $self->user->node($main::mycall);
		
	# send info to all logged in thingies
	$self->tell_login('logoutu');
	$self->tell_buddies('logoutb');

	LogDbg('DXCommand', "$call disconnected");

	$self->SUPER::disconnect;
}

#
# short cut to output a prompt
#

sub prompt
{
	my $self = shift;

	return if $self->{gtk};		# 'cos prompts are not a concept that applies here
	
	my $call = $self->call;
	my $date = cldate($main::systime);
	my $time = ztime($main::systime);
	my $prompt = $self->{prompt} || $self->msg('pr');

	$call = "($call)" unless $self->here;
	$prompt =~ s/\%C/$call/g;
	$prompt =~ s/\%D/$date/g;
	$prompt =~ s/\%T/$time/g;
	$prompt =~ s/\%M/$main::mycall/g;
	
	$self->send($prompt);
}

# broadcast a message to all users [except those mentioned after buffer]
sub broadcast
{
	my $pkg = shift;			# ignored
	my $s = shift;				# the line to be rebroadcast
	
    foreach my $dxchan (DXChannel::get_all()) {
		next unless $dxchan->{sort} eq 'U'; # only interested in user channels  
		next if grep $dxchan == $_, @_;
		$dxchan->send($s);			# send it
	}
}

# gimme all the users
sub get_all
{
	return grep {$_->{sort} eq 'U'} DXChannel::get_all();
}

# run a script for this user
sub run_script
{
	my $self = shift;
	my $silent = shift || 0;
	
}

#
# search for the command in the cache of short->long form commands
#

sub search
{
	my ($path, $short_cmd, $suffix) = @_;
	my ($apath, $acmd);
	
	# commands are lower case
	$short_cmd = lc $short_cmd;
	dbg("command: $path $short_cmd\n") if isdbg('command');

	# do some checking for funny characters
	return () if $short_cmd =~ /\/$/;

	# return immediately if we have it
	($apath, $acmd) = split ',', $cmd_cache{$short_cmd} if $cmd_cache{$short_cmd};
	if ($apath && $acmd) {
		dbg("cached $short_cmd = ($apath, $acmd)\n") if isdbg('command');
		return ($apath, $acmd);
	}
	
	# if not guess
	my @parts = split '/', $short_cmd;
	my $dirfn;
	my $curdir = $path;
	
        while (my $p = shift @parts) {
                opendir(D, $curdir) or confess "can't open $curdir $!";
                my @ls = readdir D;
                closedir D;

                # if this isn't the last part
                if (@parts) {
                        my $found;
                        foreach my $l (sort @ls) {
                                next if $l =~ /^\./;
                                if ((-d "$curdir/$l") && $p eq substr($l, 0, length $p)) {
                                        dbg("got dir: $curdir/$l\n") if isdbg('command');
                                        $dirfn .= "$l/";
                                        $curdir .= "/$l";
                                        $found++;
                                        last;
                                }
                        }
                        # only proceed if we find the directory asked for
                        return () unless $found;
                } else {
                        foreach my $l (sort @ls) {
                                next if $l =~ /^\./;
                                next unless $l =~ /\.$suffix$/;
                                if ($p eq substr($l, 0, length $p)) {
                                        $l =~ s/\.$suffix$//;
                                        $dirfn = "" unless $dirfn;
                                        $cmd_cache{$short_cmd} = join(',', ($path, "$dirfn$l")); # cache it
                                        dbg("got path: $path cmd: $dirfn$l\n") if isdbg('command');
                                        return ($path, "$dirfn$l");
                                }
                        }
                }
        }

	return ();  
}  

# clear the command name cache
sub clear_cmd_cache
{
	no strict 'refs';
	
	for my $k (keys %Cache) {
		unless ($k =~ /cmd_cache/) {
			dbg("Undefining cmd $k") if isdbg('command');
			undef $DXCommandmode::{"${k}::"};
		}
	}
	%cmd_cache = ();
	%Cache = ( cmd_clear_cmd_cache  => $Cache{cmd_clear_cmd_cache} );
}

#
# the persistant execution of things from the command directories
#
#
# This allows perl programs to call functions dynamically
# 
# This has been nicked directly from the perlembed pages
#
#require Devel::Symdump;  

sub valid_package_name {
	my $string = shift;
	$string =~ s|([^A-Za-z0-9_/])|sprintf("_%2x",unpack("C",$1))|eg;
	
	$string =~ s|/|_|g;
	return "cmd_$string";
}

# 
# this bit of magic finds a command in the offered directory
sub find_cmd_name {
	my $path = shift;
	my $cmdname = shift;
	my $package = valid_package_name($cmdname);
	my $filename = "$path/$cmdname.pl";
	my $mtime = -M $filename;
	
	# return if we can't find it
	$errstr = undef;
	unless (defined $mtime) {
		$errstr = DXM::msg('e1');
		return undef;
	}
	
	if(exists $Cache{$package} && exists $Cache{$package}->{mtime} && $Cache{$package}->{mtime} <= $mtime) {
		#we have compiled this subroutine already,
		#it has not been updated on disk, nothing left to do
		#print STDERR "already compiled $package->handler\n";
		;
	} else {

		my $sub = readfilestr($filename);
		unless ($sub) {
			$errstr = "Syserr: can't open '$filename' $!";
			return undef;
		};
		
		#wrap the code into a subroutine inside our unique package
		my $eval = qq(package DXCommandmode::$package; use POSIX qw{:math_h}; use DXLog; use DXDebug; use DXUser; use DXUtil; our \@ISA = qw{DXCommandmode}; );


		if ($sub =~ m|\s*sub\s+handle\n|) {
			$eval .= $sub;
		} else {
			$eval .= qq(sub handle { $sub });
		}
		
		if (isdbg('eval')) {
			my @list = split /\n/, $eval;
			my $line;
			for (@list) {
				dbg($_ . "\n") if isdbg('eval');
			}
		}
		
		# get rid of any existing sub and try to compile the new one
		no strict 'refs';

		if (exists $Cache{$package}) {
			dbg("find_cmd_name: Redefining $package") if isdbg('command');
			undef $DXCommandmode::{"${package}::"};
			delete $Cache{$package};
		} else {
			dbg("find_cmd_name: Defining $package") if isdbg('command');
		}

		eval $eval;

		$Cache{$package} = {mtime => $mtime } unless $@;
	}

	return "DXCommandmode::$package";
}

sub send
{
	my $self = shift;
	if ($self->{gtk}) {
		for (@_) {
			$self->SUPER::send(dd(['cmd',$_]));
		}
	} else {
		$self->SUPER::send(@_);
	}
}

sub local_send
{
	my ($self, $let, $buf) = @_;
	if ($self->{state} eq 'prompt' || $self->{state} eq 'talk' || $self->{state} eq 'chat') {
		if ($self->{enhanced}) {
			$self->send_later($let, $buf);
		} else {
			$self->send($buf);
		}
	} else {
		$self->delay($buf);
	}
}

# send a talk message here
sub talk
{
	my ($self, $from, $to, $via, $line, $onode) = @_;
	$line =~ s/\\5E/\^/g;
	if ($self->{talk}) {
		if ($self->{gtk}) {
			$self->local_send('T', dd(['talk',$to,$from,$via,$line]));
		} else {
			$self->local_send('T', "$to de $from: $line");
		}
	}
	Log('talk', $to, $from, '<' . ($onode || '*'), $line);
	# send a 'not here' message if required
	unless ($self->{here} && $from ne $to) {
		my $key = "$to$from";
		unless (exists $nothereslug{$key}) {
			my ($ref, $dxchan);
			if (($ref = Route::get($from)) && ($dxchan = $ref->dxchan)) {
				my $name = $self->user->name || $to;
				my $s = $self->user->nothere || $dxchan->msg('nothere', $name);
				$nothereslug{$key} = $main::systime;
				$dxchan->talk($to, $from, undef, $s);
			}
		}
	}
}

# send an announce
sub announce
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my $to = shift;
	my $target = shift;
	my $text = shift;
	my ($filter, $hops);

	if (!$self->{ann_talk} && $to ne $self->{call}) {
		my $call = AnnTalk::is_talk_candidate($_[0], $text);
		return if $call;
	}

	if ($self->{annfilter}) {
		($filter, $hops) = $self->{annfilter}->it(@_ );
		return unless $filter;
	}

	unless ($self->{ann}) {
		return if $_[0] ne $main::myalias && $_[0] ne $main::mycall;
	}
	return if $target eq 'SYSOP' && $self->{priv} < 5;
	my $buf;
	if ($self->{gtk}) {
		$buf = dd(['ann', $to, $target, $text, @_])
	} else {
		$buf = "$to$target de $_[0]: $text";
		$buf =~ s/\%5E/^/g;
		$buf .= "\a\a" if $self->{beep};
	}
	$self->local_send($target eq 'WX' ? 'W' : 'N', $buf);
}

# send a chat
sub chat
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my $target = shift;
	my $to = shift;
	my $text = shift;
	my ($filter, $hops);

	return unless grep uc $_ eq $target, @{$self->{user}->{group}};
	
	$text =~ s/^\#\d+ //;
	my $buf;
	if ($self->{gtk}) {
		$buf = dd(['chat', $to, $target, $text, @_])
	} else {
		$buf = "$target de $_[0]: $text";
		$buf =~ s/\%5E/^/g;
		$buf .= "\a\a" if $self->{beep};
	}
	$self->local_send('C', $buf);
}

# format a qtc net telegram 
sub format_telegram {
	my $self=shift; 
	my $msg=shift; # this is a qtc net message object
	my @ret;

	#push @ret, Dumper($msg); 
	#return @ret; 
	
	push @ret, "------------------------------------------------------";
	push @ret, strftime("%Y-%m-%d %H:%M:%S UTC", gmtime($msg->telegram_date))." UTC  --  publisher: ".$msg->call; 
	push @ret, "nr.: ".$msg->hr_refnum."  --  from: ".$msg->from."  --  to: ".$msg->to; 
	push @ret, "text: ".$msg->telegram; 
	push @ret, " ";

	return @ret; 
}

sub format_dx_spot
{
	my $self = shift;

	my $t = ztime($_[2]);
	my $loc = '';
	my $clth = $self->{consort} eq 'local' ? 29 : 30;
	my $comment = substr (($_[3] || ''), 0, $clth);
	$comment .= ' ' x ($clth - length($comment));
	if ($self->{user}->wantgrid) {
		my $ref = DXUser::get_current($_[4]);
		if ($ref) {
			$loc = $ref->qra || '';
			$loc = ' ' . substr($loc, 0, 4) if $loc;
		}
	}

	if ($self->{user}->wantdxitu) {
		$loc = ' ' . sprintf("%2d", $_[10]) if defined $_[10];
		$comment = substr($comment, 0,  $self->{consort} eq 'local' ? 26 : 27) . ' ' . sprintf("%2d", $_[8]) if defined $_[8]; 
	} elsif ($self->{user}->wantdxcq) {
		$loc = ' ' . sprintf("%2d", $_[11]) if defined $_[11];
		$comment = substr($comment, 0,  $self->{consort} eq 'local' ? 26 : 27) . ' ' . sprintf("%2d", $_[9]) if defined $_[9]; 
	} elsif ($self->{user}->wantusstate) {
		$loc = ' ' . $_[13] if $_[13];
		$comment = substr($comment, 0,  $self->{consort} eq 'local' ? 26 : 27) . ' ' . $_[12] if $_[12]; 
	}

	# format qtc information into the cluster message 
	if ( $self->{user}->wantqtc ) {
		my $num_qtc=$self->{qtc_query}->num_telegrams(lc($_[1])); 
		if ( $num_qtc ) {
			if ( $self->{user}->wantqtc_as_comment ) {
				$comment=substr("QTC $num_qtc - ".$comment, 0, $clth);
			} else { 
				$loc = " QTC $num_qtc";
			}
		}
	}
	return sprintf "DX de %-7.7s%11.1f  %-12.12s %-s $t$loc", "$_[4]:", $_[0], $_[1], $comment;
}

# send a dx spot
sub dx_spot
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	return unless $self->{dx};

	my ($filter, $hops);

	if ($self->{spotsfilter}) {
		($filter, $hops) = $self->{spotsfilter}->it(@_ );
		return unless $filter;
	}

	dbg('spot: "' . join('","', @_) . '"') if isdbg('dxspot');

	my $buf;
	if ($self->{ve7cc}) {
		$buf = VE7CC::dx_spot($self, @_);
	} elsif ($self->{gtk}) {
		my ($dxloc, $byloc);

		my $ref = DXUser::get_current($_[4]);
		if ($ref) {
			$byloc = $ref->qra;
			$byloc = substr($byloc, 0, 4) if $byloc;
		}

		my $spot = $_[1];
		$spot =~ s|/\w{1,4}$||;
		$ref = DXUser::get_current($spot);
		if ($ref) {
			$dxloc = $ref->qra;
			$dxloc = substr($dxloc, 0, 4) if $dxloc;
		}
		$buf = dd(['dx', @_, ($dxloc||''), ($byloc||'')]);
		
	} else {
		$buf = $self->format_dx_spot(@_);
		$buf .= "\a\a" if $self->{beep};
		$buf =~ s/\%5E/^/g;
	}

	$self->local_send('X', $buf);
}

sub wwv
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	return unless $self->{wwv};
	
	if ($self->{wwvfilter}) {
		($filter, $hops) = $self->{wwvfilter}->it(@_[7..$#_] );
		return unless $filter;
	}

	my $buf;
	if ($self->{gtk}) {
		$buf = dd(['wwv', @_])
	} else {
		$buf = "WWV de $_[6] <$_[1]>:   SFI=$_[2], A=$_[3], K=$_[4], $_[5]";
		$buf .= "\a\a" if $self->{beep};
	}
	
	$self->local_send('V', $buf);
}

sub wcy
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	return unless $self->{wcy};
	
	if ($self->{wcyfilter}) {
		($filter, $hops) = $self->{wcyfilter}->it(@_ );
		return unless $filter;
	}

	my $buf;
	if ($self->{gtk}) {
		$buf = dd(['wcy', @_])
	} else {
		$buf = "WCY de $_[10] <$_[1]> : K=$_[4] expK=$_[5] A=$_[3] R=$_[6] SFI=$_[2] SA=$_[7] GMF=$_[8] Au=$_[9]";
		$buf .= "\a\a" if $self->{beep};
	}
	$self->local_send('Y', $buf);
}

# broadcast debug stuff to all interested parties
sub broadcast_debug
{
	my $s = shift;				# the line to be rebroadcast
	
	foreach my $dxchan (DXChannel::get_all) {
		next unless $dxchan->{enhanced} && $dxchan->{senddbg};
		if ($dxchan->{gtk}) {
			$dxchan->send_later('L', dd(['db', $s]));
		} else {
			$dxchan->send_later('L', $s);
		}
	}
}

sub do_entry_stuff
{
	my $self = shift;
	my $line = shift;
	my @out;
	
	if ($self->state eq 'enterbody') {
		my $loc = $self->{loc} || confess "local var gone missing" ;
		if ($line eq "\032" || $line eq '%1A' || uc $line eq "/EX") {
			no strict 'refs';
			push @out, &{$loc->{endaction}}($self);          # like this for < 5.8.0
			$self->func(undef);
			$self->state('prompt');
		} elsif ($line eq "\031" || uc $line eq "/ABORT" || uc $line eq "/QUIT") {
			push @out, $self->msg('m10');
			delete $loc->{lines};
			delete $self->{loc};
			$self->func(undef);
			$self->state('prompt');
		} else {
			push @{$loc->{lines}}, length($line) > 0 ? $line : " ";
			# i.e. it ain't and end or abort, therefore store the line
		}
	} else {
		confess "Invalid state $self->{state}";
	}
	return @out;
}

sub store_startup_script
{
	my $self = shift;
	my $loc = $self->{loc} || confess "local var gone missing" ;
	my @out;
	my $call = $loc->{call} || confess "callsign gone missing";
	confess "lines array gone missing" unless ref $loc->{lines};
	my $r = Script::store($call, $loc->{lines});
	if (defined $r) {
		if ($r) {
			push @out, $self->msg('m19', $call, $r);
		} else {
			push @out, $self->msg('m20', $call);
		}
	} else {
		push @out, "error opening startup script $call $!";
	} 
	return @out;
}

# Import any commands contained in any files in import_cmd directory
#
# If the filename has a recogisable callsign as some delimited part
# of it, then this is the user the command will be run as. 
#
sub import_cmd
{
	# are there any to do in this directory?
	return unless -d $cmdimportdir;
	unless (opendir(DIR, $cmdimportdir)) {
		LogDbg('err', "can\'t open $cmdimportdir $!");
		return;
	} 

	my @names = readdir(DIR);
	closedir(DIR);
	my $name;
	foreach $name (@names) {
		next if $name =~ /^\./;

		my $s = Script->new($name, $cmdimportdir);
		if ($s) {
			LogDbg('DXCommand', "Run import cmd file $name");
			my @cat = split /[^A-Za-z0-9]+/, $name;
			my ($call) = grep {is_callsign(uc $_)} @cat;
			$call ||= $main::mycall;
			$call = uc $call;
			my @out;
			
			
			$s->inscript(0);	# switch off script checks
			
			if ($call eq $main::mycall) {
				@out = $s->run($main::me, 1);
			} else {
				my $dxchan = DXChannel::get($call);
			    if ($dxchan) {
					@out = $s->run($dxchan, 1);
				} else {
					my $u = DXUser::get($call);
					if ($u) {
						$dxchan = $main::me;
						my $old = $dxchan->{call};
						my $priv = $dxchan->{priv};
						my $user = $dxchan->{user};
						$dxchan->{call} = $call;
						$dxchan->{priv} = $u->priv;
						$dxchan->{user} = $u;
						@out = $s->run($dxchan, 1);
						$dxchan->{call} = $old;
						$dxchan->{priv} = $priv;
						$dxchan->{user} = $user;
					} else {
						LogDbg('err', "Trying to run import cmd for non-existant user $call");
					}
				}
			}
			$s->erase;
			for (@out) {
				LogDbg('DXCommand', "Import cmd $name/$call: $_");
			}
		} else {
			LogDbg('err', "Failed to open $cmdimportdir/$name $!");
			unlink "$cmdimportdir/$name";
		}
	}
}

sub print_find_reply
{
	my ($self, $node, $target, $flag, $ms) = @_;
	my $sort = $flag == 2 ? "External" : "Local";
	$self->send("$sort $target found at $node in $ms ms" );
}

# send the most relevant motd
sub send_motd
{
	my $self = shift;
	my $motd;

	unless ($self->{registered}) {
		$motd = "${main::motd}_nor_$self->{lang}";
		$motd = "${main::motd}_nor" unless -e $motd;
	}
	$motd = "${main::motd}_$self->{lang}" unless $motd && -e $motd;
	$motd = $main::motd unless $motd && -e $motd;
	if ($self->conn->ax25) {
		if ($motd) {
			$motd = "${motd}_ax25" if -e "${motd}_ax25";
		} else {
			$motd = "${main::motd}_ax25" if -e "${main::motd}_ax25";
		}
	}
	$self->send_file($motd) if -e $motd;
}
1;
__END__
