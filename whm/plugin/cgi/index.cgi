#!/usr/local/cpanel/3rdparty/bin/perl

# WHM » Plugins » InfraFence
# Installed as /usr/local/cpanel/whostmgr/docroot/cgi/infrafence/index.cgi

use strict;
use warnings;

use lib '/usr/local/cpanel';
use lib '/usr/local/share/infrafence-whm/lib';

use InfraFence::WHM::CGI ();

exit InfraFence::WHM::CGI::main();
