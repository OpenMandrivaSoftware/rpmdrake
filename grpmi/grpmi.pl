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
use grpmi_rpm;

use lib qw(/usr/lib/libDrakX);
use ugtk2 qw(:all);
$::isStandalone = 1;

@ARGV or die "usage: ", basename($0), " [--no-verify-rpm] <[-noupgrade] PACKAGE>...\n";

sub translate {
    my ($s) = @_;
    $s ? c::dgettext('grpmi', $s) : '';
}
sub _ {
    my $s = shift @_; my $t = translate($s);
    sprintf $t, @_;
}
sub mexit { ugtk2::exit(undef, @_) }

sub interactive_msg {
    my ($title, $contents, $yesno) = @_;
    my $d = ugtk2->new($title);
    my $lines; $lines++ while $contents =~ /\n/g;
    my $l = Gtk2::Label->new($contents);
    gtkadd($d->{window},
	   gtkpack_(Gtk2::VBox->new(0,5),
		    1, $lines > 20 ? gtkset_size_request(create_scrolled_window($l), 300, 300) : $l,
		    0, gtkpack(create_hbox(),
			       $yesno ? (gtksignal_connect(Gtk2::Button->new(_("Yes")), clicked => sub { $d->{retval} = 1; Gtk2->main_quit }),
					 gtksignal_connect(Gtk2::Button->new(_("No")), clicked => sub { $d->{retval} = 0; Gtk2->main_quit }))
			       : gtksignal_connect(Gtk2::Button->new(_("Ok")), clicked => sub { Gtk2->main_quit })
			      )));
    $l->set_justify('left');
    $d->main;
    return $d->{retval};
}

$> and interactive_msg(_("Error..."),
		       _("You need to be root to install packages, sorry.")), mexit -1;

grpmi_rpm::init_rcstuff() and interactive_msg(_("RPM initialization error"),
					      _("The initialization of config files of RPM was not possible, sorry.")), mexit -1;

$ENV{HOME} ||= '/root';
my @grpmi_config = map { chomp_($_) } cat_("$ENV{HOME}/.grpmi");

my $mainw = ugtk2->new('grpmi');
my $label = Gtk2::Label->new(_("Initializing..."));
my $progressbar = gtkset_size_request(Gtk2::ProgressBar->new, 400, 0);
gtkadd($mainw->{window}, gtkpack(gtkadd(create_vbox(), $label, $progressbar)));
$mainw->{rwindow}->set_position('center');
$mainw->sync;

my $exitstatus = -1;
my $forced_exitstatus;


# -=-=-=---=-=-=---=-=-=-- download potential URL's, and verify signatures -=-=-=---=-=-=--

my $cache_location = '/var/cache/urpmi/rpms';
my $url_regexp = '^http://|^https://|^ftp://';
my $nb_downloads = int(grep { m,$url_regexp, } @ARGV);
my $download_progress;

for my $arg (@ARGV) {
    if ($arg =~ m,$url_regexp,) {
	$download_progress++;
	$label->set(_("Downloading package `%s' (%s/%s)...", basename($arg), $download_progress, $nb_downloads));
	select(undef, undef, undef, 0.1); $mainw->flush;  #- hackish :-(
	my $res = curl_download::download($arg, $cache_location,
					  sub { $_[0] and $progressbar->set_fraction($_[1]/$_[0]); $mainw->flush });
	my $url = $arg;
	$arg = "$cache_location/" . basename($arg);
	if ($res) {
	    interactive_msg(_("Error during download"),
_("There was an error downloading package:

%s

Error: %s
Do you want to continue (skipping this package)?", $url, $res), 1) or goto cleanup;
	    $arg = "-skipped&$arg&";
	}
    }

    if ($arg !~ /^-/ && !member('--no-verify-rpm', @ARGV)) {
	if (-f $arg) {
	    $label->set(_("Verifying signature of `%s'...", basename($arg))); $mainw->flush;
	    my $res = grpmi_rpm::verify_sig("$arg");
	    $res and (interactive_msg(_("Signature verification error"),
_("The signature of the package `%s' is not correct:

%s
Do you want to install it anyway?",
					basename($arg), $res), 1) or $arg = "-skipped&$arg&");
	} else {
	    interactive_msg(_("File error"),
_("The following file is not valid:

%s

Do you want to continue anyway (skipping this package)?",
			      $arg), 1) or goto cleanup;
	    $arg = "-skipped&$arg&";
	}
    }
}


# -=-=-=---=-=-=---=-=-=-- install packages -=-=-=---=-=-=---=-=-=-

if (grep { /^[^-]/ } @ARGV) {
    $label->set(_("Preparing packages for installation...")); $mainw->flush;
    my $nb_installs = int(grep { /^[^-]/ } @ARGV);
    my $install_progress;

    sub install_packages_callback {
	my ($msg) = @_;
	my $retval;
	my %actions = ( 'conflicts' => sub {
			    interactive_msg(_("Conflicts detected"),
_("Conflicts were detected:
%s

Install aborted.",
					      join("\n", split(/\|/, $1))));
			    $forced_exitstatus = -1;
			    return 1;
					},
			'inst-start' => sub { $install_progress++;
					      $label->set(_("Installing package `%s' (%s/%s)...", $1, $install_progress, $nb_installs));
					      $mainw->flush },
			'inst-progress' => sub {
			    $1 =~ /(\d+) (\d+)/;
			    $progressbar->set_fraction($1/$2); $mainw->flush
			},
		      );
	$msg =~ /^$_ (.*)/ and return &{$actions{$_}} foreach keys %actions;
	print STDERR "unknown msg:<$msg>\n";
	return 0;
    }
    
    my $res = chomp_(grpmi_rpm::install_packages(\&install_packages_callback, @ARGV));
    if ($res) {
	interactive_msg(_("Problems occurred during installation"), _("There was an error during packages installation:\n\n%s", $res));
	goto cleanup;
    }
}

# -=-=-=---=-=-=---=-=-=-- cleanup -=-=-=---=-=-=--
$exitstatus = 0;
$mainw->{rwindow}->hide;
cleanup:
if (!member('noclearcache', @grpmi_config)) {
    foreach (@ARGV) {
	s/^-skipped&([^&]+)&$/$1/;
	/^\Q$cache_location/ and unlink;
    }
}
mexit($forced_exitstatus || $exitstatus);
