#!/usr/bin/perl

use MDK::Common;

@miss = (qw(Development Server Workstation), 'Graphical Environment');

my $po = $ARGV[0];
my $drakxfile = "../../../gi/perl-install/share/po/$po";

-e $drakxfile or exit 0;

my ($enc_rpmdrake) = cat_($po) =~ /Content-Type: .*; charset=(.*)\\n/i;
my ($enc_drakx)    = cat_($drakxfile) =~ /Content-Type: .*; charset=(.*)\\n/;
uc($enc_rpmdrake) ne uc($enc_drakx) and die "Encodings differ for $po! rpmdrake's encoding: $enc_rpmdrake; drakx's encoding: $enc_drakx";

foreach my $line (cat_($drakxfile)) {
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
