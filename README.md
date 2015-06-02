# qtcspider
qtc net patch for dxspider


This one shows spots like this: 

> DX de OE1SRC:     3566.0  DD5TT        good dx                       1749Z QTC 1

or if the user wants a different setting: 
> DX de OE1SRC:     3566.0  OE5XML       QTC 3 - good dx               1749Z JN88

you may show telegrams for a call:
> sh/telegram [call] [new|timeline_new|timeline|all|sent]

and you can deliver telegrams with: 

> qsp call [refnum1] [refnum2] [.....]

or 
> qsp [refnum1] [refnum2] [.....]

if you received them in the first place.....

the command: 
> telegram [fromcall] [tocall] [text]

can be used to send a telegram text from one call to another one via qtc.... 

INSTALLATION: 

git clone spider  (from the DXSpider Repository)
git clone qtcspider 
link ./local_cmd and ./local from qtcspider to spider 
follow the instructions in the DXSpider documentation for installation.... 
add the following to DXVars.pm:

# configure root directory for qtc net 
# example:
#$qtc_root="/var/spool/qtc/messages"; 

# this is the path to the directory where your private key is located.
# example:
#$qtc_privpath="/var/spool/qtc/qtc-keys/oe1xgb_somechecksum"; 

# configure the url used to publish qtc-net messages if spider runs 
# with a differend user than the qtc processor 
# example:
#$qtc_interface_http_url="http://www.qtc-net.org/qtc-if.cgi"; 
