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


use strict;
use lib qw(/usr/lib/libDrakX);
use common;
use rpmdrake;
use URPM::Signature;

BEGIN {
    eval { require ugtk2; ugtk2->import(qw(:all)) };
    if ($@) {
	print "This program cannot be run in console mode.\n";
	c::_exit(0);  #- skip ugtk2::END
    }
}

$::isStandalone = 1;

require_root_capability();

my $urpm;
my ($mainw, $remove, $edit, $list_tv);

sub selrow {
    my ($o_list_tv) = @_;
    defined $o_list_tv or $o_list_tv = $list_tv;
    my ($model, $iter) = $o_list_tv->get_selection->get_selected;
    $model && $iter or return -1;
    my $path = $model->get_path($iter);
    my $row = $path->to_string;
    return $row;
}

sub remove_row {
    my ($model, $path_str) = @_;
    my $iter = $model->get_iter_from_string($path_str);
    $iter or return;
    $model->remove($iter);
}

sub add_callback {
    my $w = ugtk2->new(N("Add a medium"), grab => 1, center => 1, transient => $mainw->{rwindow});
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
    my $count_nbs;
    mapn {
	my $info = $radios_infos{$_[0]};
	my $url_entry = sub {
	    gtkpack_(Gtk2::HBox->new(0, 0),
		     1, $info->{url_entry} = gtkentry(),
		     if_($info->{dirsel}, 0, gtksignal_connect(Gtk2::Button->new(but(N("Browse..."))),
							       clicked => sub { $info->{url_entry}->set_text(ask_dir()) })),
		     if_($info->{securitysel}, 0, gtksignal_connect(Gtk2::Button->new(but(N("Choose a mirror..."))),
								    clicked => sub { my $m = choose_mirror(transient => $w->{rwindow});
										     if ($m) {
											 $info->{url_entry}->set_text(make_url_mirror($m));
											 $info->{hdlist_entry}->set_text('media_info/synthesis.hdlist.cz');
                                                                                         $info->{hdlist_entry}->set_sensitive(1);
                                                                                         $info->{hdlist_check}->set_active(1);
										     }
										 })));
	};
        my $tips = Gtk2::Tooltips->new;
        my $checkbut_entry = sub {
            my ($name, $label, $visibility, $callback, $tip) = @_;
            [ gtkpack_(Gtk2::HBox->new(0, 0),
                       1, Gtk2::Label->new,
                       0, gtksignal_connect($info->{$name . '_check'} = gtkset_tip($tips, Gtk2::CheckButton->new($label), $tip),
                                            clicked => sub { $info->{$name . '_entry'}->set_sensitive($_[0]->get_active);
                                                             $callback and $callback->(@_);
                                                         })),
              gtkset_visibility(gtkset_sensitive($info->{$name . '_entry'} = gtkentry(), 0), $visibility) ];
        };
	my $loginpass_entries = sub {
	    map { 
                  $checkbut_entry->(@$_, sub {
                                        $info->{pass_check}->set_active($_[0]->get_active);
                                        $info->{login_check}->set_active($_[0]->get_active);
                                    })
              } ([ 'login', N("Login:"), 1 ], [ 'pass', N("Password:"), 0 ])
	};
	my $nb = $count_nbs++;
	gtksignal_connect($_[1], 'clicked' => sub { $_[0]->get_active and $notebook->set_current_page($nb) });
	$notebook->append_page(my $book = create_packtable({},
		      [ gtkset_alignment(Gtk2::Label->new(N("Name:")), 1, 0.5),
                        $info->{name_entry} = gtkentry($_[0] eq 'security' ? 'update_source' : '') ],
		      [ gtkset_alignment(Gtk2::Label->new($info->{url}), 1, 0.5),
                        $url_entry->() ],
		      $checkbut_entry->('hdlist', N("Relative path to synthesis/hdlist:"), 1, undef,
                                        N("If left blank, synthesis/hdlist will be automatically probed")),
		      if_($info->{loginpass}, $loginpass_entries->())));
	$book->show;
    } \@radios_names_ordered, \@modes_buttons;

    my $checkok = sub {
	my $info = $radios_infos{$radios_names_ordered[$notebook->get_current_page]};
	my ($name, $url) = map { $info->{$_ . '_entry'}->get_text } qw(name url);
	$name eq '' || $url eq '' and interactive_msg('rpmdrake', N("You need to fill up at least the two first entries.")), return 0;
	if (member($name, map { $_->{name} } @{$urpm->{media}})) {
	    $info->{name_entry}->select_region(0, -1);
	    interactive_msg('rpmdrake', 
N("There is already a medium by that name, do you
really want to replace it?"), yesno => 1) or return 0;
	}
	1;
    };

    my ($type, $probe, %i, %make_url);
    gtkadd(
	$w->{window},
	gtkpack(
	    Gtk2::VBox->new(0,5),
	    Gtk2::Label->new(N("Adding a medium:")),
	    gtkpack__(Gtk2::HBox->new(0, 0), Gtk2::Label->new(but(N("Type of medium:"))), @modes_buttons),
	    $notebook,
	    Gtk2::HSeparator->new,
	    gtkpack(
		create_hbox(),
		gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }),
		gtksignal_connect(
		    Gtk2::Button->new(N("Ok")), clicked => sub {
			if ($checkok->()) {
			    $w->{retval} = { nb => $notebook->get_current_page };
			    $type = $radios_names_ordered[$w->{retval}{nb}];
			    my $info = $radios_infos{$type};
			    %i = (name => $info->{name_entry}->get_text, url => $info->{url_entry}->get_text, hdlist => $info->{hdlist_entry}->get_text);
			    %make_url = (local => "file:/$i{url}", http => $i{url}, security => $i{url}, removable => "removable:/$i{url}");
			    $i{url} =~ s|^ftp://||;
			    $make_url{ftp} = sprintf "ftp://%s%s",
				$info->{login_check}->get_active
				    ? ($info->{login_entry}->get_text . ':' . $info->{pass_entry}->get_text . '@')
				    : '',
				$i{url};
			    $probe = $info->{hdlist_check}->get_active == 0 || $i{hdlist} eq '';
			    Gtk2->main_quit;
			}
		    },
		),
	    ),
	),
    );

    if ($w->main) {
	if (member($i{name}, map { $_->{name} } @{$urpm->{media}})) {
	    standalone::explanations("Removing medium $i{name}");
	    $urpm->select_media($i{name});
	    $urpm->remove_selected_media;
	}
	add_medium_and_check($urpm,
			     { probe_with => $probe, nolock => 1 },
			     $i{name}, $make_url{$type}, $i{hdlist}, update => $type eq 'security');
	return 1;
    }
    return 0;
}

sub remove_callback {
    my $row = selrow();
    $row == -1 and return;
    interactive_msg(
	N("Source Removal"),
	N("Are you sure you want to remove source \"%s\"?", to_utf8($urpm->{media}[$row]{name})),
	yesno => 1,
    ) or return;

    my $wait = wait_msg(N("Please wait, removing medium..."));
    my $name = $urpm->{media}[$row]{name};
    standalone::explanations("Removing medium $name");
    $urpm->select_media($name);
    $urpm->remove_selected_media;
    $urpm->update_media(noclean => 1, nolock => 1);
    remove_wait_msg($wait);
}

#- returns the name of the media for which edition failed, or undef on success
sub edit_callback {
    my $row = selrow();
    $row == -1 and return;
    my $medium = $urpm->{media}[$row];
    my $w = ugtk2->new(N("Edit a medium"), grab => 1, center => 1, transient => $mainw->{rwindow});
    my ($url_entry, $hdlist_entry, $url, $with_hdlist);
    gtkadd(
	$w->{window},
	gtkpack_(
	    Gtk2::VBox->new(0,5),
	    0, Gtk2::Label->new(N("Editing medium \"%s\":", $medium->{name})),
	    0, create_packtable(
		{},
		[ N("URL:"), $url_entry = gtkentry($medium->{url}) ],
		[ N("Relative path to synthesis/hdlist:"), $hdlist_entry = gtkentry($medium->{with_hdlist}) ],
	    ),
	    0, Gtk2::HSeparator->new,
	    0, gtkpack(
		create_hbox(),
		gtksignal_connect(
		    Gtk2::Button->new(N("Cancel")),
		    clicked => sub { $w->{retval} = 0; Gtk2->main_quit },
		),
		gtksignal_connect(
		    Gtk2::Button->new(N("Save changes")),
		    clicked => sub {
			$w->{retval} = 1;
			($url, $with_hdlist) = ($url_entry->get_text, $hdlist_entry->get_text);
			Gtk2->main_quit;
		    },
		),
		gtksignal_connect(
		    Gtk2::Button->new(N("Proxy...")),
		    clicked => sub { proxy_callback($medium) },
		),
	    )
	)
    );
    $w->{rwindow}->set_size_request(600, -1);
    if ($w->main) {
	my ($name, $update) = map { $medium->{$_} } qw(name update);
	$url =~ m|^removable://| and (
	    interactive_msg(
		N("You need to insert the medium to continue"),
		N("In order to save the changes, you need to insert the medium in the drive."),
		yesno => 1, text => { yes => N("Ok"), no => N("Cancel") }
	    ) or return 0
	);
	standalone::explanations("Removing medium $name");
	$urpm->select_media($name);
	$urpm->remove_selected_media;
	add_medium_and_check($urpm, { nolock => 1 }, $name, $url, $with_hdlist, update => $update);
	return $name;
    }
    return undef;
}

sub update_callback {
    update_sources_interactive($urpm, transient => $mainw->{rwindow}, nolock => 1);
}

sub proxy_callback {
    my ($medium) = @_;
    my $medium_name = $medium ? $medium->{name} : '';
    my $w = ugtk2->new(N("Configure proxies"), grab => 1, center => 1, transient => $mainw->{rwindow});
    my ($proxy, $proxy_user) = curl_download::readproxy($medium_name);
    my ($user, $pass) = $proxy_user =~ /^([^:]*):(.*)$/;
    my ($proxybutton, $proxyentry, $proxyuserbutton, $proxyuserentry, $proxypasswordentry);
    gtkadd(
	$w->{window},
	gtkpack__(
	    Gtk2::VBox->new(0, 5),
	    gtkset_justify(Gtk2::Label->new(
		$medium_name
		    ? N("Proxy settings for media \"%s\"", $medium_name)
		    : N("Global proxy settings")
	    ), 'center'),
	    gtkset_justify(Gtk2::Label->new(N("If you need a proxy, enter the hostname and an optional port (syntax: <proxyhost[:port]>):")), 'center'),
	    gtkpack_(
		Gtk2::HBox->new(0, 10),
		0, gtkset_active($proxybutton = Gtk2::CheckButton->new(N("Proxy hostname:")), to_bool($proxy)),
		1, gtkset_sensitive($proxyentry = gtkentry($proxy), to_bool($proxy)),
	    ),
	    gtkset_justify(Gtk2::Label->new(N("You may specify a user/password for the proxy authentication:")), 'center'),
	    gtkpack_(
		Gtk2::HBox->new(0, 10),
		0, gtkset_active($proxyuserbutton = Gtk2::CheckButton->new(N("User:")), to_bool($proxy_user)),
		1, gtkset_sensitive($proxyuserentry = gtkentry($user), to_bool($proxy_user)),
		0, Gtk2::Label->new(N("Password:")),
		1, gtkset_visibility(gtkset_sensitive($proxypasswordentry = gtkentry($pass), to_bool($proxy_user)), 0),
	    ),
	    Gtk2::HSeparator->new,
	    gtkpack(
		create_hbox(),
		gtksignal_connect(
		    Gtk2::Button->new(N("Ok")),
		    clicked => sub {
			$w->{retval} = 1;
			$proxy = $proxybutton->get_active ? $proxyentry->get_text : '';
			$proxy_user = $proxyuserbutton->get_active
			    ? ($proxyuserentry->get_text . ':' . $proxypasswordentry->get_text) : '';
			Gtk2->main_quit;
		    },
		),
		gtksignal_connect(
		    Gtk2::Button->new(N("Cancel")),
		    clicked => sub { $w->{retval} = 0; Gtk2->main_quit },
		)
	    )
	)
    );
    $proxybutton->signal_connect(
	clicked => sub {
	    $proxyentry->set_sensitive($_[0]->get_active);
	    $_[0]->get_active and return;
	    $proxyuserbutton->set_active(0);
	    $proxyuserentry->set_sensitive(0);
	    $proxypasswordentry->set_sensitive(0);
	}
    );
    $proxyuserbutton->signal_connect(clicked => sub { $proxyuserentry->set_sensitive($_[0]->get_active);
    $proxypasswordentry->set_sensitive($_[0]->get_active) });

    $w->main and curl_download::writeproxy($proxy, $proxy_user, $medium_name);
}

sub parallel_read_sysconf {
    my @conf;
    foreach (cat_('/etc/urpmi/parallel.cfg')) {
        my ($name, $protocol, $command) = /([^:]+):([^:]+):(.*)/ or print STDERR "Warning, unrecognized line in /etc/urpmi/parallel.cfg:\n$_";
        my $medias = $protocol =~ s/\(([^\)]+)\)$// ? [ split /,/, $1 ] : [];
        push @conf, { name => $name, protocol => $protocol, medias => $medias, command => $command };
    }
    \@conf;
}

sub parallel_write_sysconf {
    my ($conf) = @_;
    output '/etc/urpmi/parallel.cfg',
           map { my $m = @{$_->{medias}} ? '(' . join(',', @{$_->{medias}}) . ')' : '';
                 "$_->{name}:$_->{protocol}$m:$_->{command}\n" } @$conf;
}

sub remove_parallel {
    my ($num, $conf) = @_;
    if ($num != -1) {
        splice @$conf, $num, 1;
        parallel_write_sysconf($conf);
    }
}

sub edit_parallel {
    my ($num, $conf) = @_;
    my $edited = $num == -1 ? {} : $conf->[$num];

    my $w = ugtk2->new($num == -1 ? N("Add a parallel group") : N("Edit a parallel group"), grab => 1);
    my $name_entry;

    my $medias_ls = Gtk2::ListStore->new("Glib::String");
    my $medias = Gtk2::TreeView->new_with_model($medias_ls);
    $medias->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
    $medias->set_headers_visible(0);
    $medias->get_selection->set_mode('browse');
    $medias_ls->append_set([ 0 => $_ ]) foreach @{$edited->{medias}};

    my $add_media = sub {
        my $w = ugtk2->new(N("Add a medium limit"), grab => 1);
        my $medias_list_ls = Gtk2::ListStore->new("Glib::String");
        my $medias_list = Gtk2::TreeView->new_with_model($medias_list_ls);
        $medias_list->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
        $medias_list->set_headers_visible(0);
        $medias_list->get_selection->set_mode('browse');
        $medias_list_ls->append_set([ 0 => $_->{name} ]) foreach @{$urpm->{media}};
        my $sel;
        gtkadd($w->{window},
               gtkpack__(Gtk2::VBox->new(0, 5),
                         Gtk2::Label->new(N("Choose a medium for adding in the media limit:")),
                         $medias_list,
                         Gtk2::HSeparator->new,
                         gtkpack(create_hbox(),
           gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub {
                                 $w->{retval} = 1;
                                 $sel = selrow($medias_list);
                                 Gtk2->main_quit
                             }),
           gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))));
        if ($w->main && $sel != -1) {
            my $media = ${$urpm->{media}}[$sel]{name};
            $medias_ls->append_set([ 0 => $media ]);
            push @{$edited->{medias}}, $media;
        }
    };
    my $remove_media = sub {
        my $row = selrow($medias);
        if ($row != -1) {
            splice @{$edited->{medias}}, $row, 1;
            remove_row($medias_ls, $row);
        }
    };

    my $hosts_ls = Gtk2::ListStore->new("Glib::String");
    my $hosts = Gtk2::TreeView->new_with_model($hosts_ls);
    $hosts->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
    $hosts->set_headers_visible(0);
    $hosts->get_selection->set_mode('browse');
    my $hosts_list;
    if ($edited->{protocol} eq 'ssh')    { $hosts_list = [ split /:/, $edited->{command} ] };
    if ($edited->{protocol} eq 'ka-run') { push @$hosts_list, $1 while $edited->{command} =~ /-m (\S+)/g };
    $hosts_ls->append_set([ 0 => $_ ]) foreach @$hosts_list;
    my $add_host = sub {
        my $w = ugtk2->new(N("Add a host"), grab => 1);
        my ($entry, $value);
        gtkadd($w->{window},
               gtkpack__(Gtk2::VBox->new(0, 5),
                         Gtk2::Label->new(N("Type in the hostname or IP address of the host to add:")),
                         $entry = gtkentry(),
                         Gtk2::HSeparator->new,
                         gtkpack(create_hbox(),
           gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { $w->{retval} = 1; $value = $entry->get_text; Gtk2->main_quit }),
           gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))));
        if ($w->main) {
            $hosts_ls->append_set([ 0 => $value ]);
            push @$hosts_list, $value;
        }
    };
    my $remove_host = sub {
        my $row = selrow($hosts);
        if ($row != -1) {
            splice @$hosts_list, $row, 1;
            remove_row($hosts_ls, $row);
        }
    };

    my @protocols_names = qw(ka-run ssh);
    my @protocols;
    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0, 5),
                    if_($num != -1,
                        0, Gtk2::Label->new(N("Editing parallel group \"%s\":", $edited->{name}))),
		    1, create_packtable({},
					[ N("Group name:"), $name_entry = gtkentry($edited->{name}) ],
                                        [ N("Protocol:"), gtkpack__(Gtk2::HBox->new(0, 0),
                                                                    @protocols = gtkradio($edited->{protocol}, @protocols_names)) ],
                                        [ N("Media limit:"),
                                          gtkpack_(Gtk2::HBox->new(0, 5),
                                                   1, gtkadd(gtkset_shadow_type(Gtk2::Frame->new, 'in'),
                                                             create_scrolled_window($medias, [ 'never', 'automatic' ])),
                                                   0, gtkpack__(Gtk2::VBox->new(0, 0),
                                             gtksignal_connect(Gtk2::Button->new(but(N("Add"))),    clicked => sub { $add_media->() }),
                                             gtksignal_connect(Gtk2::Button->new(but(N("Remove"))), clicked => sub { $remove_media->() }))) ],
                                        [ N("Hosts:"),
                                          gtkpack_(Gtk2::HBox->new(0, 5),
                                                   1, gtkadd(gtkset_shadow_type(Gtk2::Frame->new, 'in'),
                                                             create_scrolled_window($hosts, [ 'never', 'automatic' ])),
                                                   0, gtkpack__(Gtk2::VBox->new(0, 0),
                                             gtksignal_connect(Gtk2::Button->new(but(N("Add"))),    clicked => sub { $add_host->() }),
                                             gtksignal_connect(Gtk2::Button->new(but(N("Remove"))), clicked => sub { $remove_host->() }))) ]),
		    0, Gtk2::HSeparator->new,
		    0, gtkpack(create_hbox(),
			       gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub {
                                                     $w->{retval} = 1;
                                                     $edited->{name} = $name_entry->get_text;
                                                     mapn {
                                                         $_[0]->get_active and $edited->{protocol} = $_[1];
                                                     } \@protocols, \@protocols_names;
                                                     Gtk2->main_quit }),
			       gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))));
    $w->{rwindow}->set_position('center');
    $w->{rwindow}->set_size_request(600, -1);
    if ($w->main) {
        $num == -1 and push @$conf, $edited;
        if ($edited->{protocol} eq 'ssh')    { $edited->{command} = join(':', @$hosts_list) }
        if ($edited->{protocol} eq 'ka-run') { $edited->{command} = "-c ssh " . join(' ', map { "-m $_" } @$hosts_list) }
        parallel_write_sysconf($conf);
	return 1;
    }        
    return 0;
}

sub parallel_callback {
    my $w = ugtk2->new(N("Configure parallel urpmi (distributed execution of urpmi)"), grab => 1, transient => $mainw->{rwindow});
    my $list_ls = Gtk2::ListStore->new("Glib::String", "Glib::String", "Glib::String", "Glib::String");
    my $list = Gtk2::TreeView->new_with_model($list_ls);
    each_index { $list->append_column(Gtk2::TreeViewColumn->new_with_attributes($_, Gtk2::CellRendererText->new, 'text' => $::i)) } N("Group"), N("Protocol"), N("Media limit");
    $list->append_column(my $commandcol = Gtk2::TreeViewColumn->new_with_attributes(N("Command"), Gtk2::CellRendererText->new, 'text' => 3));
    $commandcol->set_max_width(200);

    my $conf;
    my $reread = sub {
	$list_ls->clear;
        $conf = parallel_read_sysconf();
	foreach (@$conf) {
            $list_ls->append_set([ 0 => $_->{name},
                                   1 => $_->{protocol},
                                   2 => @{$_->{medias}} ? join(', ', @{$_->{medias}}) : N("(none)"),
                                   3 => $_->{command} ]);
	}
    };
    $reread->();

    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0,5),
		    1, gtkpack_(Gtk2::HBox->new(0, 10),
				1, $list,
				0, gtkpack__(Gtk2::VBox->new(0, 5),
					     gtksignal_connect($remove = Gtk2::Button->new(but(N("Remove"))),
                                                               clicked => sub { remove_parallel(selrow($list), $conf); $reread->() }),
					     gtksignal_connect($edit = Gtk2::Button->new(but(N("Edit"))),
                                                               clicked => sub {
                                                                   my $row = selrow($list);
                                                                   $row != -1 and edit_parallel($row, $conf);
                                                                   $reread->() }),
					     gtksignal_connect(Gtk2::Button->new(but(N("Add..."))), 
							       clicked => sub { edit_parallel(-1, $conf) and $reread->() }))),
		    0, Gtk2::HSeparator->new,
		    0, gtkpack(create_hbox(),
			       gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { Gtk2->main_quit }))));
    $w->{rwindow}->set_position('center');

    $w->main;
}


sub keys_callback {
    my $w = ugtk2->new(N("Manage keys for digital signatures of packages"), grab => 1, transient => $mainw->{rwindow});

    my $media_list_ls = Gtk2::ListStore->new("Glib::String");
    my $media_list = Gtk2::TreeView->new_with_model($media_list_ls);
    $media_list->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Medium"), Gtk2::CellRendererText->new, 'text' => 0));
    $media_list->get_selection->set_mode('browse');

    my $keys_list_ls = Gtk2::ListStore->new("Glib::String", "Glib::String");
    my $keys_list = Gtk2::TreeView->new_with_model($keys_list_ls);
    $keys_list->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Keys"), Gtk2::CellRendererText->new, 'text' => 0));
    $keys_list->get_selection->set_mode('browse');

    my ($current_medium, $current_medium_nb, @keys);

    my $read_conf = sub {
        $urpm->parse_pubkeys(root => $urpm->{root});
        @keys = map { [ split /[,\s]+/, $_->{'key-ids'} ] } @{$urpm->{media}};
    };
    my $write = sub {
        $urpm->write_config;
        $urpm = urpm->new;
        $urpm->read_config; 
        $read_conf->();
        $media_list->get_selection->signal_emit('changed');
    };
    $read_conf->();
    my $key_name = sub {
        exists $urpm->{keys}{$_[0]} ? $urpm->{keys}{$_[0]}{name}
                                    : N("no name found, key doesn't exist in rpm keyring!");
    };
    
    $media_list_ls->append_set([ 0 => $_->{name} ]) foreach @{$urpm->{media}};
    $media_list->get_selection->signal_connect(changed => sub {
        my ($model, $iter) = $_[0]->get_selected;
        $model && $iter or return;
        $current_medium = $model->get($iter, 0);
        $current_medium_nb = $model->get_path($iter)->to_string;
        $keys_list_ls->clear;
        $keys_list_ls->append_set([ 0 => sprintf("%s (%s)", $_, $key_name->($_)), 1 => $_ ]) foreach @{$keys[$current_medium_nb]};
    });

    my $add_key = sub {
        my $w_add = ugtk2->new(N("Add a key"), grab => 1, transient => $w->{rwindow});
        my $available_keyz_ls = Gtk2::ListStore->new("Glib::String", "Glib::String");
        my $available_keyz = Gtk2::TreeView->new_with_model($available_keyz_ls);
        $available_keyz->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
        $available_keyz->set_headers_visible(0);
        $available_keyz->get_selection->set_mode('browse');
        $available_keyz_ls->append_set([ 0 => sprintf("%s (%s)", $_, $key_name->($_)), 1 => $_ ]) foreach keys %{$urpm->{keys}};
        my $key;
        gtkadd($w_add->{window},
               gtkpack__(Gtk2::VBox->new(0, 5),
                         Gtk2::Label->new(N("Choose a key for adding to the medium %s", $current_medium)),
                         $available_keyz,
                         Gtk2::HSeparator->new,
                         gtkpack(create_hbox(),
                                 gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub {
                                                       my ($model, $iter) = $available_keyz->get_selection->get_selected;
                                                       $model && $iter and $key = $model->get($iter, 1);
                                                       Gtk2->main_quit;
                                                   }),
                                 gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { Gtk2->main_quit }))));
        $w_add->main;
        if (defined $key) {
            $urpm->{media}[$current_medium_nb]{'key-ids'} = join(',', sort(uniq(@{$keys[$current_medium_nb]}, $key)));
            $write->();
        }
    };

    my $remove_key = sub {
        my ($model, $iter) = $keys_list->get_selection->get_selected;
        $model && $iter or return;
        my $key = $model->get($iter, 1);
	interactive_msg(N("Remove a key"),
                        N("Are you sure you want to remove the key %s from medium %s?\n(name of the key: %s)",
                          $key, $current_medium, $key_name->($key)),
                        yesno => 1, transient => $w->{rwindow}) or return;
        $urpm->{media}[$current_medium_nb]{'key-ids'} = join(',', difference2(\@{$keys[$current_medium_nb]}, [ $key ]));
        $write->();
    };

    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0,5),
		    1, gtkpack_(Gtk2::HBox->new(0, 10),
				1, $media_list,
				1, $keys_list,
				0, gtkpack__(Gtk2::VBox->new(0, 5),
					     gtksignal_connect($remove = Gtk2::Button->new(but(N("Add a key..."))),
                                                               clicked => \&$add_key),
					     gtksignal_connect($remove = Gtk2::Button->new(but(N("Remove key"))),
                                                               clicked => \&$remove_key))),
		    0, Gtk2::HSeparator->new,
		    0, gtkpack(create_hbox(),
			       gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { Gtk2->main_quit }))));
    $w->{rwindow}->set_position('center');

    $w->main;
}


sub mainwindow {
    $mainw = ugtk2->new(N("Configure media"), center => 1);

    my $list = Gtk2::ListStore->new("Glib::Boolean", "Glib::String");
    $list_tv = Gtk2::TreeView->new_with_model($list);
    $list_tv->get_selection->set_mode('browse');
    $list_tv->set_rules_hint(1);
    $list_tv->set_reorderable(1);

    my $reorder_ok = 1;
    $list->signal_connect(row_deleted => sub {
                              my ($model) = @_;
                              $reorder_ok or return;
                              my @media;
                              $model->foreach(sub {
                                              my (undef, undef, $iter) = @_;
                                              my $name = $model->get($iter, 1);
                                              push @media, find { $_->{name} eq $name } @{$urpm->{media}};
                                              0;
                                          }, undef);
                              @{$urpm->{media}} = @media;
                          });

    $list_tv->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Enabled?"), my $tr = Gtk2::CellRendererToggle->new, 'active' => 0));
    $list_tv->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Medium"), Gtk2::CellRendererText->new, 'text' => 1));

    $tr->signal_connect(toggled => sub {
			    my (undef, $path) = @_;
			    my $iter = $list->get_iter_from_string($path);
			    $urpm->{media}[$path]{ignore} = !$urpm->{media}[$path]{ignore} || undef;
			    $list->set($iter, 0, !$urpm->{media}[$path]{ignore});
			});

    my $menu = Gtk2::Menu->new;
    my @menu_actions = ([ 'update_source', N("Update medium") ], [ 'generate_hdlist', N("Regenerate hdlist") ]);
    foreach (@menu_actions) {
	my ($action, $text) = @$_;
        my $row;
        my $select_media = sub {
            $urpm->select_media($urpm->{media}[$row]{name});
            foreach (@{$urpm->{media}}) {  #- force ignored media to be returned alive
                $_->{modified} and delete $_->{ignore};
            }
        };
	my %action2fun; %action2fun = (
			  update_source => sub {
                              slow_func(N("Please wait, updating media..."),
                                        sub { $urpm->update_media(noclean => 1, nolock => 1) });
                          },
			  generate_hdlist => sub {
                              slow_func(N("Please wait, generating hdlist..."),
                                        sub { $urpm->update_media(noclean => 1, force => 1, nolock => 1) });
                          });
	$menu->append(gtksignal_connect(gtkshow(Gtk2::MenuItem->new_with_label($text)),
                                        activate => sub {
                                            $row = selrow();
                                            $row == -1 and return;
                                            $select_media->();
                                            $action2fun{$action}->()
                                        }));
    }
    $list_tv->signal_connect(button_press_event => sub {
                                 $_[1]->button == 3 or return 0;
                                 $menu->popup(undef, undef, undef, undef, $_[1]->button, $_[1]->time);
                                 1;
                             });

    my $reread_media = sub {
	my ($name) = @_;
        $reorder_ok = 0;
	$urpm = urpm->new;
	$urpm->read_config; 
	if (defined $name) {
	    #- this media must be reconstructed since editing it failed
	    foreach (grep { $_->{name} eq $name } @{$urpm->{media}}) {
		delete $_->{ignore};
	    }
	    $urpm->select_media($name);
	    $urpm->update_media(noclean => 1, nolock => 1);
	}
	$list->clear;
	$list->append_set([ 0 => !$_->{ignore}, 1 => $_->{name} ]) foreach @{$urpm->{media}};
        $reorder_ok = 1;
    };
    $reread_media->();

    gtkadd(
	$mainw->{window},
	gtkpack_(
	    Gtk2::VBox->new(0,5),
	    1, gtkpack_(
		Gtk2::HBox->new(0, 10),
		1, $list_tv,
		0, gtkpack__(
		    Gtk2::VBox->new(0, 5),
		    gtksignal_connect(
			$remove = Gtk2::Button->new(but(N("Remove"))),
			clicked => sub { remove_callback(); $reread_media->() },
		    ),
		    gtksignal_connect(
			$edit = Gtk2::Button->new(but(N("Edit"))),
			clicked => sub {
			    my $name = edit_callback(); defined $name and $reread_media->($name);
			}
		    ),
		    gtksignal_connect(
			Gtk2::Button->new(but(N("Add..."))), 
			clicked => sub { add_callback() and $reread_media->() },
		    ),
		    gtksignal_connect(
			Gtk2::Button->new(but(N("Update..."))),
			clicked => sub { update_callback() and $reread_media->() },
		    ),
		    gtksignal_connect(Gtk2::Button->new(but(N("Manage keys..."))), clicked => \&keys_callback),
		    gtksignal_connect(Gtk2::Button->new(but(N("Proxy..."))), clicked => \&proxy_callback),
		    gtksignal_connect(Gtk2::Button->new(but(N("Parallel..."))), clicked => \&parallel_callback)
		)
	    ),
	    0, Gtk2::HSeparator->new,
	    0, gtkpack(create_hbox('edge'),
		gtksignal_connect(
		    Gtk2::Button->new(but(N("Help"))), clicked => sub {
			system("drakhelp --id software-management-sources &");
			interactive_msg(
			    N("Help launched in background"),
			    N("The help window has been started, it should appear shortly on your desktop."),
			);
		    }
		),
		gtksignal_connect(Gtk2::Button->new(but(N("Ok"))), clicked => sub { Gtk2->main_quit })
	    )
	)
    );
    $mainw->main;
}


readconf();

if (!member(basename($0), @$already_splashed)) {
    interactive_msg('rpmdrake',
N("%s

Is it ok to continue?",
N("Welcome to the Software Media Manager!

This tool will help you configure the packages media you wish to use on
your computer. They will then be available to install new software package
or to perform updates.")), yesno => 1) or myexit -1;
    push @$already_splashed, basename($0);
}

{
    $urpm = urpm->new;
    local $urpm->{fatal} = sub {
        interactive_msg('rpmdrake',
N("Packages database is locked. Please close other applications
working with packages database (do you have another media
manager on another desktop, or are you currently installing
packages as well?)."));
        myexit -1;
    };
    $urpm->exlock_urpmi_db;
}

mainwindow();
$urpm->write_config;

writeconf();

myexit 0;
