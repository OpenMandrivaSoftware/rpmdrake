package grpmi_rpm;

use strict;
use vars qw($VERSION @ISA);

require DynaLoader;

@ISA = qw(DynaLoader);
$VERSION = '1.0';

bootstrap grpmi_rpm $VERSION;

1;

