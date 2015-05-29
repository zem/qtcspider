#
# The system variables - those indicated will need to be changed to suit your
# circumstances (and callsign)
#
# Copyright (c) 1998-2007 - Dirk Koopman G1TLH
#
#

package main;

# this really does need to change for your system!!!!			   
# use CAPITAL LETTERS
$mycall = "OE1XGB";

# your name
$myname = "Hans";

# Your 'normal' callsign (in CAPTTAL LETTERS) 
$myalias = "OE1SRC";

# Your latitude (+)ve = North (-)ve = South in degrees and decimal degrees
$mylatitude = +48.209;

# Your Longtitude (+)ve = East, (-)ve = West in degrees and decimal degrees
$mylongitude = +16.37;

# Your locator (USE CAPITAL LETTERS)
$mylocator = "JN88GF";

# Your QTH (roughly)
$myqth = "Vienna";

# Your e-mail address
$myemail = "oe1src\@oevsv.at";

# Your BBS addr
$mybbsaddr = "OE1SRC\#QTC-NET";

# the default language (the key used must match the one in the Messages file)
$lang = 'en';

# the country codes that my node is located in
# 
# for example 'qw(EA EA8 EA9 EA0)' for Spain and all its islands.
# if you leave this blank then it will use the country code for
# your $mycall. This will suit 98% of sysops (including GB7 BTW).
#

@my_cc = qw();

# the tcp address of the cluster this can be an address of an ethernet port
# but this is more secure. For normal use this will be fine. 
$clusteraddr = "localhost";

# the port number of the cluster (just leave this, unless it REALLY matters to you)
$clusterport = 27754;

# your favorite way to say 'Yes'
$yes = 'Yes';

# your favorite way to say 'No'
$no = 'No';

# the interval between unsolicited prompts if not traffic
$user_interval = 11*60;

# data files live in 
$data = "$root/data";

# system files live in
$system = "$root/sys";

# command files live in
$cmd = "$root/cmd";

# local command files live in (and overide $cmd)
$localcmd = "$root/local_cmd";

# where the user data lives
$userfn = "$data/users";

# the "message of the day" file
$motd = "$data/motd";

# are we debugging ?
@debug = qw(chan state msg cron connect);

# are we doing xml?
$do_xml = 0;

# the SQL database DBI dsn
#$dsn = "dbi:SQLite:dbname=$root/data/dxspider.db";
#$dbuser = "";
#$dbpass = "";

# configure root directory for qtc net 
$qtc_root="/var/spool/qtc/messages"; 

1;
