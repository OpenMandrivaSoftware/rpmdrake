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

use strict;
use rpmdrake;

$::isStandalone = 1;


sub add_medium_and_check {
    my ($urpm, $msg, $options) = splice @_, 0, 3;
    standalone::explanations("Adding medium @_");
    my $wait = wait_msg($msg);
    $urpm->add_medium(@_);
    $urpm->update_media(%$options, noclean => 1);
    remove_wait_msg($wait);
    my ($medium) = grep { $_->{name} eq $_[0] } @{$urpm->{media}};
    $medium or interactive_msg('rpmdrake', N("Unable to create medium."));
    $medium->{modified} and interactive_msg('rpmdrake', N("Unable to update medium; it will be automatically disabled."));
    $urpm->write_config;
}

my $urpm = urpm->new;
$urpm->read_config; 

my ($mainw, $remove, $edit, $list_tv);

sub add_callback {
    my ($mode, $rebuild_ui, $name_entry, $url_entry, $hdlist_entry, $count_nbs);
    my $w = ugtk2->new(N("Add a source"), grab => 1, center => 1, transient => $mainw->{rwindow});
    my %radios_infos = (local => { name => N("Local files"), url => N("Path:"), dirsel => 1 },
			ftp => { name => N("FTP server"), url => N("URL:"), loginpass => 1 },
			http => { name => N("HTTP server"), url => N("URL:") },
			removable => { name => N("Removable device"), url => N("Path or mount point:"), dirsel => 1 },
			security => { name => N("Security updates"), url => N("URL:"), securitysel => 1 },
		       );
    my @radios_names_ordered = qw(local ftp http removable security);
    my @modes_buttons = gtkradio($radios_infos{local}{name}, map { $radios_infos{$_}{name} } @radios_names_ordered);
    my $notebook = Gtk2::Notebook->new;
    $notebook->set_show_tabs(0); $notebook->set_show_border(0);
    mapn {
	my $info = $radios_infos{$_[0]};
	my $url_entry = sub {
	    gtkpack_(Gtk2::HBox->new(0, 0),
		     1, $info->{url_entry} = gtkentry,
		     if_($info->{dirsel}, 0, gtksignal_connect(Gtk2::Button->new(but(N("Browse..."))),
							       clicked => sub { $info->{url_entry}->set_text(ask_dir()) })),
		     if_($info->{securitysel}, 0, gtksignal_connect(Gtk2::Button->new(but(N("Choose a mirror..."))),
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
		  [ gtkpack_(Gtk2::HBox->new(0, 0),
			     1, Gtk2::Label->new(''),
			     0, gtksignal_connect($info->{$_->[0].'_check'} = Gtk2::CheckButton->new($_->[1]),
						  clicked => sub { $info->{$entry_name.'_entry'}->set_sensitive($_[0]->get_active);
								   $info->{pass_check}->set_active($_[0]->get_active);
								   $info->{login_check}->set_active($_[0]->get_active);
							       }),
			     1, Gtk2::Label->new('')),
		    gtkset_visibility(gtkset_sensitive($info->{$_->[0].'_entry'} = gtkentry(), 0), $_->[2]) ] }
	      ([ 'login', N("Login:"), 1 ], [ 'pass', N("Password:"), 0 ])
	};
	my $nb = $count_nbs++;
	gtksignal_connect($_[1], 'clicked' => sub { $_[0]->get_active and $notebook->set_current_page($nb) });
	$notebook->append_page(my $book = create_packtable({},
		      [ N("Name:"), $info->{name_entry} = gtkentry($_[0] eq 'security' and 'update_source') ],
		      [ $info->{url}, $url_entry->() ],
		      [ N("Relative path to synthesis/hdlist:"), $info->{hdlist_entry} = gtkentry ],
		      if_($info->{loginpass}, $loginpass_entries->())));
	$book->show;
    } \@radios_names_ordered, \@modes_buttons;

    my $checkok = sub {
	my $info = $radios_infos{$radios_names_ordered[$notebook->get_current_page]};
	my ($name, $url, $hdlist) = map { $info->{$_.'_entry'}->get_text } qw(name url hdlist);
	$name eq '' || $url eq '' and interactive_msg('rpmdrake', N("You need to fill up at least the two first entries.")), return 0;
	if (member($name, map { $_->{name} } @{$urpm->{media}})) {
	    $info->{name_entry}->select_region(0, -1);
	    interactive_msg('rpmdrake', 
N("There is already a medium by that name, do you
really want to replace it?"), yesno => 1) or return 0;
	}
	1;
    };

    gtkadd($w->{window},
	   gtkpack(Gtk2::VBox->new(0,5),
		   Gtk2::Label->new(N("Adding a source:")),
		   gtkpack__(Gtk2::HBox->new(0, 0), Gtk2::Label->new(but(N("Type of source:"))), @modes_buttons),
		   $notebook,
		   Gtk2::HSeparator->new,
		   gtkpack(create_hbox(),
			   gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub {
						 $checkok->() and $w->{retval} = { nb => $notebook->get_current_page }, Gtk2->main_quit;
					     }),
			   gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))));
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
	add_medium_and_check($urpm, N("Please wait, adding medium..."),
			     { probe_with_hdlist => member($type, qw(removable local)) && $i{hdlist} eq '' },
			     $i{name}, $make_url{$type}, $i{hdlist}, update => $type eq 'security');
	return 1;
    }
    return 0;
}

sub selrow {
    my ($model, $iter) = $list_tv->get_selection->get_selected;
    my $path = $model->get_path($iter);
    my $row = $path->to_string;
    $path->free;
    $iter->free;
    return $row;
}

sub remove_callback {
    my $wait = wait_msg(N("Please wait, removing medium..."));
    my $name = $urpm->{media}[selrow()]{name};
    standalone::explanations("Removing medium $name");
    $urpm->select_media($name);
    $urpm->remove_selected_media;
    $urpm->update_media(noclean => 1);
    remove_wait_msg($wait);
}

sub edit_callback {
    my $medium = $urpm->{media}[selrow()];
    my $w = ugtk2->new(N("Edit a source"), grab => 1, center => 1, transient => $mainw->{rwindow});
    my ($url_entry, $hdlist_entry);
    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0,5),
		    0, Gtk2::Label->new(N("Editing source \"%s\":", $medium->{name})),
		    0, create_packtable({},
					[ N("URL:"), $url_entry = gtkentry($medium->{url}) ],
					[ N("Relative path to synthesis/hdlist:"), $hdlist_entry = gtkentry($medium->{with_hdlist}) ]),
		    0, Gtk2::HSeparator->new,
		    0, gtkpack(create_hbox(),
			       gtksignal_connect(Gtk2::Button->new(N("Save changes")), clicked => sub { $w->{retval} = 1; Gtk2->main_quit }),
			       gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))));
    $w->{rwindow}->set_size_request(600, -1);
    if ($w->main) {
	my ($name, $update, $ignore) = map { $medium->{$_} } qw(name update ignore);
	my ($url, $with_hdlist) = ($url_entry->get_text, $hdlist_entry->get_text);
	$url =~ m|^removable://| and (interactive_msg(N("You need to insert the medium to continue"),
						      N("In order to save the changes, you need to insert the medium in the drive."),
						      yesno => 1, text => { yes => N("Ok"), no => N("Cancel") }) or return 0);
	standalone::explanations("Removing medium $name");
	$urpm->select_media($name);
	$urpm->remove_selected_media;
	add_medium_and_check($urpm, N("Please wait, updating medium..."), {}, $name, $url, $with_hdlist, update => $update);
	return 1;
    }
    return 0;
}

sub update_callback {
    update_sources($urpm, transient => $mainw->{rwindow});
}

sub proxy_callback {
    my $w = ugtk2->new(N("Configure proxies"), grab => 1, center => 1, transient => $mainw->{rwindow});
    my ($proxy, $proxy_user) = curl_download::readproxy();
    my ($user, $pass) = $proxy_user =~ /^(.+):(.+)$/;
    gtkadd($w->{window},
	   gtkpack__(Gtk2::VBox->new(0, 5),
		     Gtk2::Label->new(N("If you need a proxy, enter the hostname and an optional port (syntax: <proxyhost[:port]>):")),
		     gtkpack_(Gtk2::HBox->new(0, 10),
			      0, gtkset_active(my $proxybutton = Gtk2::CheckButton->new(N("Proxy hostname:")), to_bool($proxy)),
			      1, gtkset_sensitive(my $proxyentry = gtkentry($proxy), to_bool($proxy))),
		     Gtk2::Label->new(N("You may specify a user/password for the proxy authentication:")),
		     gtkpack_(Gtk2::HBox->new(0, 10),
			      0, gtkset_active(my $proxyuserbutton = Gtk2::CheckButton->new(N("User:")), to_bool($proxy_user)),
			      1, gtkset_sensitive(my $proxyuserentry = gtkentry($user), to_bool($proxy_user)),
			      0, Gtk2::Label->new(N("Password:")),
			      1, gtkset_visibility(gtkset_sensitive(my $proxypasswordentry = gtkentry($pass), to_bool($proxy_user)), 0)),
		     Gtk2::HSeparator->new,
		     gtkpack(create_hbox(),
			     gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { $w->{retval} = 1; Gtk2->main_quit }),
			     gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))));
    $proxybutton->signal_connect(clicked => sub { $proxyentry->set_sensitive($_[0]->get_active);
						  $_[0]->get_active and return;
						  $proxyuserbutton->set_active(0);
						  $proxyuserentry->set_sensitive(0);
						  $proxypasswordentry->set_sensitive(0); });
    $proxyuserbutton->signal_connect(clicked => sub { $proxyuserentry->set_sensitive($_[0]->get_active);
						      $proxypasswordentry->set_sensitive($_[0]->get_active) });
    if ($w->main) {
	curl_download::writeproxy($proxybutton->get_active ? $proxyentry->get_text : '',
				  $proxyuserbutton->get_active ? ($proxyuserentry->get_text.':'.$proxypasswordentry->get_text) : '');
    }
}

sub mainwindow {
    $mainw = ugtk2->new(N("Configure sources"), center => 1);

    my $list = Gtk2::ListStore->new(Gtk2::GType->BOOLEAN, Gtk2::GType->STRING);
    $list_tv = Gtk2::TreeView->new_with_model($list);
    $list_tv->get_selection->set_mode('browse');
    $list_tv->set_rules_hint(1);

    $list_tv->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Enabled?"), my $tr = Gtk2::CellRendererToggle->new, 'active' => 0));
    $list_tv->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Source"), Gtk2::CellRendererText->new, 'text' => 1));

    $tr->signal_connect('toggled', sub {
			    my ($cell, $path) = @_;
			    my $iter = $list->get_iter_from_string($path);
			    invbool(\$urpm->{media}[$path]{ignore});
			    $list->set($iter, [ 0, !$urpm->{media}[$path]{ignore} ]);
			    $iter->free;
			});

    my $reread_media = sub {
	$list->clear;
	$list->append_set([ 0 => !$_->{ignore}, 1 => $_->{name} ])->free foreach @{$urpm->{media}};
    };
    $reread_media->();

    gtkadd($mainw->{window},
	   gtkpack_(Gtk2::VBox->new(0,5),
		    1, gtkpack_(Gtk2::HBox->new(0, 10),
				1, $list_tv,
				0, gtkpack__(Gtk2::VBox->new(0, 5),
					     gtksignal_connect($remove = Gtk2::Button->new(but(N("Remove"))),
										clicked => sub { remove_callback(); $reread_media->(); }),
					     gtksignal_connect($edit = Gtk2::Button->new(but(N("Edit"))),
										clicked => sub { edit_callback() and $reread_media->() }),
					     gtksignal_connect(Gtk2::Button->new(but(N("Add..."))), 
							       clicked => sub { add_callback() and $reread_media->(); }),
					     gtksignal_connect(Gtk2::Button->new(but(N("Update..."))), clicked => \&update_callback),
					     gtksignal_connect(Gtk2::Button->new(but(N("Proxy..."))), clicked => \&proxy_callback))),
		    0, Gtk2::HSeparator->new,
		    0, gtkpack(create_hbox(),
			       gtksignal_connect(Gtk2::Button->new(N("Save and quit")), clicked => sub { $mainw->{retval} = 1; Gtk2->main_quit }),
			       gtksignal_connect(Gtk2::Button->new(N("Quit")), clicked => sub { $mainw->{retval} = 0; Gtk2->main_quit }))));
    $mainw->main;
}


readconf;

if (!member(basename($0), @$already_splashed)) {
    interactive_msg('rpmdrake',
N("%s

Is it ok to continue?",
N("Welcome to the packages source editor!

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
