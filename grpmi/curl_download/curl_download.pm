package curl_download;

use strict;
use vars qw($VERSION @ISA);

require DynaLoader;

@ISA = qw(DynaLoader);
$VERSION = '1.0';

bootstrap curl_download $VERSION;

1;

