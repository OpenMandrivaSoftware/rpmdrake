#!/usr/bin/perl
#*****************************************************************************
# 
#  Copyright (c) 2002 Guillaume Cottenceau (gc at mandrakesoft dot com)
# 
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2, as
#  published by the Free Software Foundation.
# 
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
# 
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
# 
#*****************************************************************************

use strict;
use MDK::Common;

use curl_download;

print "Downloading `$ARGV[0]' to /tmp.\n";

$| = 1;
my $res = curl_download::download($ARGV[0], '/tmp',
                                  sub { $_[0] and printf "Progressing download, %d%% done.\r", 100*$_[1]/$_[0] });

printf "Download finished. Results is (void resultas == success):\n%s\n", $res;
