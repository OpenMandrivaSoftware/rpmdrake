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
use my_gtk qw(:helpers :wrappers);
$::isStandalone = 1;

@ARGV or die "usage: ", basename($0), " <[-noupgrade] PACKAGE>...\n";

sub translate {
    my ($s) = @_;
    $s ? c::dgettext('grpmi', $s) : '';
}
sub _ {
    my $s = shift @_; my $t = translate($s);
    sprintf $t, @_;
}

sub interactive_msg {
    my ($title, $contents, $yesno) = @_;
    my $d = my_gtk->new($title);
    my $lines; $lines++ while $contents =~ /\n/g;
    my $l = new Gtk::Label($contents);
    gtkadd($d->{window},
	   gtkpack_(new Gtk::VBox(0,5),
		    1, $lines > 20 ? gtkset_usize(createScrolledWindow($l), 300, 300) : $l,
		    0, gtkpack(create_hbox(),
			       $yesno ? (gtksignal_connect(new Gtk::Button(_("Yes")), clicked => sub { $d->{retval} = 1; Gtk->main_quit }),
					 gtksignal_connect(new Gtk::Button(_("No")), clicked => sub { $d->{retval} = 0; Gtk->main_quit }))
			       : gtksignal_connect(new Gtk::Button(_("Ok")), clicked => sub { Gtk->main_quit })
			      )));
    $l->set_justify('left');
    $d->main;
    return $d->{retval};
}

Gtk->init;

$> and interactive_msg(_("Error..."),
		       _("You need to be root to install packages, sorry.")), exit -1;

grpmi_rpm::init_rcstuff() and interactive_msg(_("RPM initialization error"),
					      _("The initialization of config files of RPM was not possible, sorry.")), exit -1;

$ENV{HOME} ||= '/root';
my @grpmi_config = map { chomp_($_) } cat_("$ENV{HOME}/.grpmi");

my $mainw = my_gtk->new('grpmi');
my $label = new Gtk::Label(_("Initializing..."));
my $progressbar = gtkset_usize(new Gtk::ProgressBar, 400, 0);
gtkadd($mainw->{window}, gtkpack(gtkadd(create_vbox(), $label, $progressbar)));
$mainw->{rwindow}->set_position('center');
$mainw->sync;

my $exitstatus = -1;


# -=-=-=---=-=-=---=-=-=-- download potential URL's, and verify signatures -=-=-=---=-=-=--

my $proxy;
/http_proxy = (http:[^:]+:\d+)/ and $proxy = $1 foreach cat_("$ENV{HOME}/.wgetrc");
my $cache_location = '/var/cache/urpmi/rpms';
my $url_regexp = '^http://|^https://|^ftp://';
my $nb_downloads = int(grep { m,$url_regexp, } @ARGV);
my $download_progress;

for (my $i=0; $i<@ARGV; $i++) {
    if ($ARGV[$i] =~ m,$url_regexp,) {
	$download_progress++;
	$label->set(_("Downloading package `%s' (%s/%s)...", basename($ARGV[$i]), $download_progress, $nb_downloads));
	select(undef, undef, undef, 0.1); $mainw->flush;  #- hackish :-(
	my $res = curl_download::download($ARGV[$i], $cache_location, $proxy,
					  sub { $_[0] and $progressbar->update($_[1]/$_[0]); $mainw->flush });
	my $url = $ARGV[$i];
	$ARGV[$i] = "$cache_location/" . basename($ARGV[$i]);
	if ($res) {
	    interactive_msg(_("Error during download"),
_("There was an error downloading package:

%s

Error: %s
Do you want to continue (skipping this package)?", $url, $res), 1) or goto cleanup;
	    $ARGV[$i] = "-skipped&$ARGV[$i]&";
	}
    }

    if ($ARGV[$i] !~ /^-/) {
	if (-f $ARGV[$i]) {
	    $label->set(_("Verifying signature of `%s'...", basename($ARGV[$i]))); $mainw->flush;
	    my $res = grpmi_rpm::verify_sig("$ARGV[$i]");
	    $res and (interactive_msg(_("Signature verification error"),
_("The signature of the package `%s' is not correct:

%s
Do you want to install it anyway?",
					basename($ARGV[$i]), $res), 1) or $ARGV[$i] = "-skipped&$ARGV[$i]&");
	} else {
	    interactive_msg(_("File error"),
_("The following file is not valid:

%s

Do you want to continue anyway (skipping this package)?",
			      $ARGV[$i]), 1) or goto cleanup;
	    $ARGV[$i] = "-skipped&$ARGV[$i]&";
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

Do you want to force the install anyway?",
					      join("\n", split(/\|/, $1))), 1) ? 0 : 1
					},
			'inst-start' => sub { $install_progress++;
					      $label->set(_("Installing package `%s' (%s/%s)...", $1, $install_progress, $nb_installs));
					      $mainw->flush },
			'inst-progress' => sub {
			    $1 =~ /(\d+) (\d+)/;
			    $progressbar->update($1/$2); $mainw->flush
			},
		      );
	$msg =~ /^$_ (.*)/ and return &{$actions{$_}} foreach keys %actions;
	print STDERR "unknown msg:<$msg>\n";
	return 0;
    }
    
    my $res = chomp_(grpmi_rpm::install_packages(\&install_packages_callback, @ARGV));
    $res and interactive_msg(_("Problems occurred during installation"), _("There was an error during packages installation:\n\n%s", $res));
}


# -=-=-=---=-=-=---=-=-=-- cleanup -=-=-=---=-=-=--
$exitstatus = 0;
cleanup:
if (!member('noclearcache', @grpmi_config)) {
    foreach (@ARGV) {
	s/^-skipped&([^&]+)&$/$1/;
	/^\Q$cache_location/ and unlink;
    }
}
exit $exitstatus;
