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
#
# $Id$

$> and (exec {'consolehelper'} $0, @ARGV or die "consolehelper missing");

use lib qw(/usr/lib/libDrakX);
use strict;

use rpmdrake;

$::isStandalone = 1;
Gtk->init;


sub add_medium_and_check {
    my ($urpm, $msg, $options) = splice @_, 0, 3;
    standalone::explanations("Adding medium @_");
    my $wait = wait_msg($msg);
    $urpm->add_medium(@_);
    $urpm->update_media(%$options, noclean => 1);
    remove_wait_msg($wait);
    my ($medium) = grep { $_->{name} eq $_[0] } @{$urpm->{media}};
    $medium or interactive_msg('rpmdrake', _("Unable to create medium."));
    $medium->{modified} and interactive_msg('rpmdrake', _("Unable to update medium; it will be automatically disabled."));
    $urpm->write_config;
}

my $urpm = new urpm; 
$urpm->read_config; 

my ($remove, $edit, $clist);

sub add_callback {
    my ($mode, $rebuild_ui, $name_entry, $url_entry, $hdlist_entry, $count_nbs);
    my $w = my_gtk->new(_("Edit a source"));
    my %radios_infos = (local => { name => _("Local files"), url => _("Path:"), dirsel => 1 },
			ftp => { name => _("FTP server"), url => _("URL:"), loginpass => 1 },
			http => { name => _("HTTP server"), url => _("URL:") },
			removable => { name => _("Removable device"), url => _("Path or mount point:"), dirsel => 1 },
			security => { name => _("Security updates"), url => _("URL:"), securitysel => 1 },
		       );
    my @radios_names_ordered = qw(local ftp http removable security);
    my @modes_buttons = gtkradio($radios_infos{local}{name}, map { $radios_infos{$_}{name} } @radios_names_ordered);
    my $notebook = new Gtk::Notebook;
    $notebook->set_show_tabs(0); $notebook->set_show_border(0);
    mapn {
	my $info = $radios_infos{$_[0]};
	my $url_entry = sub {
	    gtkpack_(new Gtk::HBox(0, 0),
		     1, $info->{url_entry} = gtkentry,
		     if_($info->{dirsel}, 0, gtksignal_connect(new Gtk::Button(but(_("Browse..."))),
							       clicked => sub { $info->{url_entry}->set_text(ask_dir) })),
		     if_($info->{securitysel}, 0, gtksignal_connect(new Gtk::Button(but(_("Choose a mirror..."))),
								    clicked => sub { my $m = choose_mirror;
										     if ($m) {
											 my ($r) = cat_('/etc/mandrake-release') =~ /release\s(\S+)/;
											 $info->{url_entry}->set_text("$m/$r/RPMS/");
											 $info->{hdlist_entry}->set_text('../base/hdlist.cz');
										     }
										 })));
	};
	my $loginpass_entries = sub {
	    map { my $entry_name = $_->[0];
		  [ gtkpack_(new Gtk::HBox(0, 0),
			     1, new Gtk::Label,
			     0, gtksignal_connect($info->{$_->[0].'_check'} = new Gtk::CheckButton($_->[1]),
						  clicked => sub { $info->{$entry_name.'_entry'}->set_sensitive($_[0]->get_active);
								   $info->{pass_check}->set_active($_[0]->get_active);
								   $info->{login_check}->set_active($_[0]->get_active);
							       }),
			     1, new Gtk::Label),
		    gtkset_sensitive($info->{$_->[0].'_entry'} = gtkentry, 0) ] }
	      ([ 'login', _("Login:") ], [ 'pass', _("Password:") ])
	};
	my $nb = $count_nbs++;
	gtksignal_connect($_[1], 'clicked' => sub { $_[0]->get_active and $notebook->set_page($nb) });
	$notebook->append_page(my $book = create_packtable({},
		      [ _("Name:"), $info->{name_entry} = gtkentry($_[0] eq 'security' and 'update_source') ],
		      [ $info->{url}, $url_entry->() ],
		      [ _("Relative path to synthesis/hdlist:"), $info->{hdlist_entry} = gtkentry ],
		      if_($info->{loginpass}, $loginpass_entries->())));
	$book->show;
    } \@radios_names_ordered, \@modes_buttons;

    my $checkok = sub {
	my $info = $radios_infos{$radios_names_ordered[$notebook->get_current_page]};
	my ($name, $url, $hdlist) = map { $info->{$_.'_entry'}->get_text } qw(name url hdlist);
	$name eq '' || $url eq '' and interactive_msg('rpmdrake', _("You need to fill up at least the two first entries.")), return 0;
	if (member($name, map { $_->{name} } @{$urpm->{media}})) {
	    $info->{name_entry}->select_region(0, -1);
	    interactive_msg('rpmdrake', 
_("There is already a medium by that name, do you
really want to replace it?"), yesno => 1) or return 0;
	}
	1;
    };

    gtkadd($w->{window},
	   gtkpack(new Gtk::VBox(0,5),
		   new Gtk::Label(_("Adding a source:")),
		   gtkpack__(new Gtk::HBox(0, 0), new Gtk::Label(but(_("Type of source:"))), @modes_buttons),
		   $notebook,
		   new Gtk::HSeparator,
		   gtkpack(create_hbox(),
			   gtksignal_connect(new Gtk::Button(_("Ok")), clicked => sub {
						 $checkok->() and $w->{retval} = { nb => $notebook->get_current_page }, Gtk->main_quit;
					     }),
			   gtksignal_connect(new Gtk::Button(_("Cancel")), clicked => sub { $w->{retval} = 0; Gtk->main_quit }))));
    $w->{rwindow}->set_position('center');
    if ($w->main) {
	my $type = $radios_names_ordered[$w->{retval}{nb}];
	my $info = $radios_infos{$type};
	my %i = (name => $info->{name_entry}->get_text, url => $info->{url_entry}->get_text, hdlist => $info->{hdlist_entry}->get_text);
	my %make_url = (local => "file:/$i{url}", http => $i{url}, security => $i{url}, removable => "removable:/$i{url}");
	$i{url} =~ s|^ftp://||;
	$make_url{ftp} = sprintf "ftp://%s%s", $info->{login_check}->get_active
	                                           ? ($info->{login_entry}->get_text.':'.$info->{pass_entry}->get_text.'@')
						   : '',
					       $i{url};
	if (member($i{name}, map { $_->{name} } @{$urpm->{media}})) {
	    standalone::explanations("Removing medium $i{name}");
	    $urpm->select_media($i{name});
	    $urpm->remove_selected_media;
	}
	add_medium_and_check($urpm, _("Please wait, adding medium..."),
			     { probe_with_hdlist => member($type, qw(removable local)) && $i{hdlist} eq '' },
			     $i{name}, $make_url{$type}, $i{hdlist}, update => $type eq 'security');
	return 1;
    }
    return 0;
}

sub remove_callback {
    my $wait = wait_msg(_("Please wait, removing medium..."));
    my $name = $urpm->{media}[$clist->selection]{name};
    standalone::explanations("Removing medium $name");
    $urpm->select_media($name);
    $urpm->remove_selected_media;
    $urpm->update_media(noclean => 1);
    remove_wait_msg($wait);
}

sub edit_callback {
    my $medium = $urpm->{media}[$clist->selection];
    my $w = my_gtk->new(_("Edit a source"));
    my ($url_entry, $hdlist_entry);
    gtkadd($w->{window},
	   gtkpack_(new Gtk::VBox(0,5),
		    0, new Gtk::Label(_("Editing source \"%s\":", $medium->{name})),
		    0, create_packtable({},
					[ _("URL:"), $url_entry = gtkentry($medium->{url}) ],
					[ _("Relative path to synthesis/hdlist:"), $hdlist_entry = gtkentry($medium->{with_hdlist}) ]),
		    0, new Gtk::HSeparator,
		    0, gtkpack(create_hbox(),
			       gtksignal_connect(new Gtk::Button(_("Save changes")), clicked => sub { $w->{retval} = 1; Gtk->main_quit }),
			       gtksignal_connect(new Gtk::Button(_("Cancel")), clicked => sub { $w->{retval} = 0; Gtk->main_quit }))));
    $w->{rwindow}->set_position('center');
    $w->{rwindow}->set_usize(600, 0);
    if ($w->main) {
	my ($name, $update, $ignore) = map { $medium->{$_} } qw(name update ignore);
	my ($url, $with_hdlist) = ($url_entry->get_text, $hdlist_entry->get_text);
	$url =~ m|^removable://| and (interactive_msg(_("You need to insert the medium to continue"),
						      _("In order to save the changes, you need to insert the medium in the drive."),
						      yesno => 1, text => { yes => _("Ok"), no => _("Cancel") }) or return 0);
	standalone::explanations("Removing medium $name");
	$urpm->select_media($name);
	$urpm->remove_selected_media;
	add_medium_and_check($urpm, _("Please wait, updating medium..."), {}, $name, $url, $with_hdlist, update => $update);
	return 1;
    }
    return 0;
}

sub update_callback {
    my $w = my_gtk->new(_("Update source(s)"));
    gtkadd($w->{window},
	   gtkpack__(new Gtk::VBox(0,5),
		     new Gtk::Label(_("Select the source(s) you wish to update:")),
		     (my @buttons = map { new Gtk::CheckButton($_->{name}) } @{$urpm->{media}}),
		     new Gtk::HSeparator,
		     gtkpack(create_hbox(),
			     gtksignal_connect(new Gtk::Button(_("Update")), clicked => sub { $w->{retval} = 1; Gtk->main_quit }),
			     gtksignal_connect(new Gtk::Button(_("Cancel")), clicked => sub { $w->{retval} = 0; Gtk->main_quit }))));
    $w->{rwindow}->set_position('center');
    if ($w->main) {
	each_index { $_->get_active and $urpm->select_media($urpm->{media}[$::i]{name}) } @buttons;
	foreach (@{$urpm->{media}}) {  #- force ignored media to be returned alive (forked from urpmi.updatemedia...)
	    $_->{modified} and delete $_->{ignore};
	}
	slow_func(_("Please wait, updating media..."),
		  sub { $urpm->update_media(noclean => 1) });
    }
}

sub mainwindow {
    my %pixmaps = (selected => [ gtkcreate_png('selected') ], unselected => [ gtkcreate_png('unselected') ]);
    my $mainw = my_gtk->new(_("Configure sources"));
    $clist = new_with_titles Gtk::CList(_("Enabled?"), _("Source"));
    $clist->set_column_auto_resize($_, 1) foreach qw(0 1);
    $clist->set_column_justification(0, 'center');
    $clist->signal_connect(button_press_event => sub { my ($row, $col) = $clist->get_selection_info($_[1]->{x}, $_[1]->{'y'});
						       if ($col == 0 && $row =~ /^\d+$/) {
							   invbool(\$urpm->{media}[$row]{ignore});
							   my $pix = $pixmaps{$urpm->{media}[$row]{ignore} ? 'unselected' : 'selected'};
							   $clist->set_pixmap($row, 0, $pix->[0], $pix->[1]);
						       }
						   });
    $clist->signal_connect(select_row => sub { $$_->set_sensitive(1) foreach (\$remove, \$edit) });
    $clist->signal_connect(unselect_row => sub { $$_->set_sensitive(0) foreach (\$remove, \$edit) });

    my $reread_media = sub {
	$clist->clear;
	foreach (@{$urpm->{media}}) {
	    $clist->append('', $_->{name});
	    my $pix = $pixmaps{$_->{ignore} ? 'unselected' : 'selected'};
	    $clist->set_pixmap($clist->rows-1, 0, $pix->[0], $pix->[1]);
	}
    };
    $reread_media->();

    gtkadd($mainw->{window},
	   gtkpack_(new Gtk::VBox(0,5),
		    1, gtkpack_(new Gtk::HBox(0, 10),
				1, $clist,
				0, gtkpack__(new Gtk::VBox(0, 5),
					     gtkset_sensitive(gtksignal_connect($remove = new Gtk::Button(but(_("Remove"))),
										clicked => sub { remove_callback; $reread_media->(); }), 0),
					     gtkset_sensitive(gtksignal_connect($edit = new Gtk::Button(but(_("Edit"))),
										clicked => sub { edit_callback and $reread_media->() }), 0),
					     gtksignal_connect(new Gtk::Button(but(_("Add..."))), 
							       clicked => sub { add_callback and $reread_media->(); }),
					     gtksignal_connect(new Gtk::Button(but(_("Update..."))), clicked => \&update_callback))),
		    0, new Gtk::HSeparator,
		    0, gtkpack(create_hbox(),
			       gtksignal_connect(new Gtk::Button(_("Save and quit")), clicked => sub { $mainw->{retval} = 1; Gtk->main_quit }),
			       gtksignal_connect(new Gtk::Button(_("Quit")), clicked => sub { $mainw->{retval} = 0; Gtk->main_quit }))));
    $mainw->{rwindow}->set_position('center');
    $mainw->main;
}


readconf;

if (!member(basename($0), @$already_splashed)) {
    interactive_msg('rpmdrake',
_("%s

Is it ok to continue?",
_("Welcome to the packages source editor!

This tool will help you configure the packages sources you wish to use on
your computer. They will then be available to install new software package
or to perform updates.")), yesno => 1) or myexit -1;
    push @$already_splashed, basename($0);
}

if (mainwindow()) {
    $urpm->write_config;
}

writeconf;

myexit 0;
