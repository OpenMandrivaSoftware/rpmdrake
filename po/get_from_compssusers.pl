#!/usr/bin/perl

use MDK::Common;

@miss = (qw(Development Server Workstation), 'Graphical Environment');

foreach my $line (cat_("../../../gi/perl-install/share/po/$ARGV[0]")) {
    $line =~ m|^\Q#: ../../share/compssUsers:999| || ($line =~ m|^msgid "([^"]+)"| && grep { $_ eq $1 } @miss) and do {
	$current = 'inside';
	print "# DO NOT BOTHER TO MODIFY HERE, BUT IN DRAKX PO\n";
        $line =~ m|^#:| or print "#: ../../share/compssUsers:999\n";
    };
    $current eq 'inside' and print $line;
    $line =~ m|^$| and do {
	$current = 'outside';
    };
}
