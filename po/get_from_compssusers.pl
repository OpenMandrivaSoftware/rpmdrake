#!/usr/bin/perl

use MDK::Common;

our @miss = (qw(Server Workstation), 'Graphical Environment');
our @exceptions = qw(Development Configuration Mail);

my $po = $ARGV[0];
my $drakxfile = "../../../gi/perl-install/install/share/po/$po";

-e $drakxfile or exit 0;

my ($enc_rpmdrake) = cat_($po) =~ /Content-Type: .*; charset=(.*)\\n/i;
my ($enc_drakx)    = cat_($drakxfile) =~ /Content-Type: .*; charset=(.*)\\n/;
uc($enc_rpmdrake) ne uc($enc_drakx) and die "Encodings differ for $po! rpmdrake's encoding: $enc_rpmdrake; drakx's encoding: $enc_drakx";

our $current;
our $entry;
foreach my $line (cat_($drakxfile)) {
    $line =~ m|^\Q#: share/compssUsers.pl:| || ($line =~ m|^msgid "([^"]+)"| && member($1, @miss)) and do {
	$current = 'inside';
        $entry = "# DO NOT BOTHER TO MODIFY HERE, BUT IN DRAKX PO\n";
        $line =~ m|^#:| or $entry .= "#: share/compssUsers.pl:999\n";
    };
    $current eq 'inside' and $entry .= $line;
    $line =~ m|^msgid "([^"]+)"| && member($1, @exceptions) and $current = 'outside';
    $line =~ m|^$| && $current eq 'inside' and do {
	$current = 'outside';
        print $entry;
    };
}
