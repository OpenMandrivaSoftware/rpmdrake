package Rpmdrake::init;
#*****************************************************************************
#
#  Copyright (c) 2002 Guillaume Cottenceau
#  Copyright (c) 2002-2007 Thierry Vignaud <tvignaud@mandriva.com>
#  Copyright (c) 2003, 2004, 2005 MandrakeSoft SA
#  Copyright (c) 2005-2007 Mandriva SA
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
#
# $Id$

use strict;
use MDK::Common::Func 'any';
use lib qw(/usr/lib/libDrakX);
use common;
BEGIN { $::no_global_argv_parsing = 1 }

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(init warn_about_user_mode $changelog_first $default_list_mode %rpmdrake_options $MODE);

BEGIN {  #- we want to run this code before the Gtk->init of the use-my_gtk
    my $basename = sub { local $_ = shift; s|/*\s*$||; s|.*/||; $_ };
    any { /^--?h/ } @ARGV and do {
	printf join("\n", N("Usage: %s [OPTION]...", $basename->($0)),
N("  --auto                 assume default answers to questions"),
N("  --changelog-first      display changelog before filelist in the description window"),
N("  --media=medium1,..     limit to given media"),
N("  --merge-all-rpmnew     propose to merge all .rpmnew/.rpmsave files found"),
N("  --mode=MODE            set mode (install (default), remove, update)"),
N("  --justdb               update the database, but do not modify the filesystem"),
N("  --no-confirmation      don't ask first confirmation question in update mode"),
N("  --no-media-update      don't update media at startup"),
N("  --no-verify-rpm        don't verify packages signatures"),
N("  --parallel=alias,host  be in parallel mode, use \"alias\" group, use \"host\" machine to show needed deps"),
N("  --pkg-nosel=pkg1,..    show only these packages"),
N("  --pkg-sel=pkg1,..      preselect these packages"),
N("  --rpm-root             use another root for rpm installation"),
N("  --urpmi-root           use another root for urpmi db & rpm installation"),
N("  --root                 force to run as root"),
N("  --search=pkg           run search for \"pkg\""),
chomp_(N("  --version      - print this tool's version number.
")),
""
);
	exit 0;
    };
}

BEGIN { #- for mcc
    if ("@ARGV" =~ /--embedded (\w+)/) {
	$::XID = $1;
	$::isEmbedded = 1;
    }
}

use rpmdrake;

#- This is needed because text printed by Gtk2 will always be encoded
#- in UTF-8; we first check if LC_ALL is defined, because if it is,
#- changing only LC_COLLATE will have no effect.
use POSIX qw(setlocale LC_ALL LC_COLLATE strftime);
use locale;
my $collation_locale = $ENV{LC_ALL};
if ($collation_locale) {
  $collation_locale =~ /UTF-8/ or setlocale(LC_ALL, "$collation_locale.UTF-8");
} else {
  $collation_locale = setlocale(LC_COLLATE);
  $collation_locale =~ /UTF-8/ or setlocale(LC_COLLATE, "$collation_locale.UTF-8");
}

my $version = 1;
our %rpmdrake_options;
foreach (@ARGV) {
    /^-?-(\S+)$/ or next;
    my $val = $1;
    if ($val =~ /=/) {
        my ($name, $values) = split /=/, $val;
        my @values = split /,/, $values;
        $rpmdrake_options{$name} = \@values if @values;
    } else {
        if ($val eq 'version') {
            print "$0 $version\n";
            exit(0);
       }
        $rpmdrake_options{$val} = 1;
    }
}

foreach my $option (qw(media mode parallel pkg-nosel pkg-sel rpm-root search)) {
    if (defined $rpmdrake_options{$option} && !ref($rpmdrake_options{$option})) {
        warn "wrong usage of \"$option\" option!\n";
        exit(-1); # too early for my_exit()
    }
}

our $MODE = ref $rpmdrake_options{mode} ? $rpmdrake_options{mode}[0] : undef;
unless ($MODE) {
    $MODE = 'install';
    $0 =~ m|remove$|  and $MODE = 'remove';
    $0 =~ m|update$|i and $MODE = 'update';
}

our $default_list_mode;
$default_list_mode = 'all' if $MODE eq 'install';
if ($MODE eq 'remove') {
    $default_list_mode = 'installed';
} elsif ($MODE eq 'update') {
    $default_list_mode = 'all_updates';
}

$MODE eq 'update' || $rpmdrake_options{root} and require_root_capability();
$::noborderWhenEmbedded = 1;

our $changelog_first = $changelog_first_config->[0];
$changelog_first = 1 if $rpmdrake_options{'changelog-first'};

sub warn_about_user_mode() {
    $> and (interactive_msg(N("Running in user mode"),
                            N("You are launching this program as a normal user.
You will not be able to perform modifications on the system,
but you may still browse the existing database."), yesno => 1, text => { no => N("Cancel"), yes => N("Ok") }) or myexit(0));
}

sub init() {
    if (!$> && !member($MODE, @$already_splashed)) {
        interactive_msg(N("Welcome"),
                        N("%s

Is it ok to continue?",
                          $MODE eq 'remove' ?
                            N("Welcome to the software removal tool!

This tool will help you choose which software you want to remove from
your computer.")
                              : $MODE eq 'update' ?
                                N("Welcome to %s!

This tool will help you choose the updates you want to install on your
computer.", $rpmdrake::myname_update)
                                  :
                                    ($rpmdrake::branded ? N("Welcome to the software installation tool!")
                                       : N("Welcome to the software installation tool!

Your Mandriva Linux system comes with several thousands of software
packages on CDROM or DVD. This tool will help you choose which software
you want to install on your computer.")))
                          , yesno => 1) or myexit(-1);
        push @$already_splashed, $MODE;
    }
    if (!$> && !$offered_to_add_sources->[0]) {
        if (interactive_msg(N("Welcome"),
                            join("\n\n",
                                 N("The software installation tool can set up media sources."),
                                 N("Do you want to add media sources now?"),
                                 ),
                            yesno => 1,
                        )
        ) {
            require Rpmdrake::edit_urpm_sources;
            Rpmdrake::edit_urpm_sources::easy_add_callback();
        }
        $offered_to_add_sources->[0] = 1;
    }
}

1;
