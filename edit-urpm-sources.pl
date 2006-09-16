#!/usr/bin/perl
#*****************************************************************************
# 
#  Copyright (c) 2002 Guillaume Cottenceau
#  Copyright (c) 2002-2006 Thierry Vignaud <tvignaud@mandriva.com>
#  Copyright (c) 2002-2006 Mandriva Linux
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
use POSIX qw(_exit);
use MDK::Common qw(max);

BEGIN { #- for mcc
    if ("@ARGV" =~ /--embedded (\w+)/) {
	$::XID = $1;
	$::isEmbedded = 1;
    }
}

BEGIN {
    eval {
        require ugtk2; ugtk2->import(qw(:all));
        require mygtk2; mygtk2->import(qw(gtknew))
    };
    if ($@) {
	print "This program cannot be run in console mode ($@_).\n";
	_exit(0);  #- skip ugtk2::END
    }
}

$ugtk2::wm_icon = "title-install";
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

sub easy_add_callback {
    #- cooker and community don't have update sources
    my $want_base_distro = distro_type(0) eq 'updates' ? interactive_msg_(
	N("Choose media type"),
N("This step enables you to add sources from a Mandriva Linux web or FTP mirror.

There are two kinds of official mirrors. You can choose to add sources that
contain the complete set of packages of your distribution (usually a superset
of what comes on the standard installation CDs), or sources that provide the
official updates for your distribution. (You can add both, but you'll have
to do this in two steps.)"),
	 transient => $mainw->{real_window},
	yesno => 1, text => { yes => N("Distribution sources"), no => N("Official updates") },
    ) : 1;
    my ($mirror) = choose_mirror(message =>
N("This will attempt to install all official sources corresponding to your
distribution (%s).

I need to contact the Mandriva website to get the mirror list.
Please check that your network is currently running.

Is it ok to continue?", $rpmdrake::mandrake_release),
	want_base_distro => $want_base_distro,
     transient => $mainw->{real_window},
    ) or return 0;
    my $m = $mirror->{url};
    my $is_update = $mirror->{type} eq 'updates';
    $m .= '/media/main/updates' if $is_update;
    my $wait = wait_msg_(N("Please wait, adding media..."));
    my $url = $want_base_distro ? make_url_mirror_dist($m) : make_url_mirror($m);
    my $medium_name;
    if ($want_base_distro && !$is_update) {
	if ($rpmdrake::mandrake_release =~ /(\d+\.\d+) \((\w+)\)/) {
	    $medium_name = $2 . $1 . '-';
	} else {
	    $medium_name = 'distrib';
	}
	#- ensure a unique medium name
	my $initial_number = 1 + max map { $_->{name} =~ /\(\Q$medium_name\E(\d+)\b/ ? $1 : 0 } @{$urpm->{media}};
	add_medium_and_check(
	    $urpm,
	    { nolock => 1, distrib => 1 },
	    $medium_name, $url, probe_with => 'synthesis', initial_number => $initial_number,
	);
    } else {
	$medium_name = 'update_source';
	#- ensure a unique medium name
	my $nb_sources = max map { $_->{name} =~ /^\Q$medium_name\E(\d*)$/ ? $1 || 1 : 0 } @{$urpm->{media}};
	if ($nb_sources) { $medium_name .= $nb_sources + 1 }
	add_medium_and_check(
	    $urpm,
	    { nolock => 1, probe_with => 1 },
	    $medium_name, $url, '', update => 1,
	);
    }
    remove_wait_msg($wait);
    return 1;
}

sub add_callback {
    my $w = ugtk2->new(N("Add a medium"), grab => 1, center => 1,  transient => $mainw->{real_window});
    my %radios_infos = (
	local => { name => N("Local files"), url => N("Path:"), dirsel => 1 },
	ftp => { name => N("FTP server"), url => N("URL:"), loginpass => 1 },
	rsync => { name => N("RSYNC server"), url => N("URL:") },
	http => { name => N("HTTP server"), url => N("URL:") },
	removable => { name => N("Removable device"), url => N("Path or mount point:"), dirsel => 1 },
    );
    my @radios_names_ordered = qw(local ftp rsync http removable);
    my @modes = map { $radios_infos{$_}{name} } @radios_names_ordered;
    # TODO: replace NoteBook by sensitive widgets and Label->set()
    my $notebook = Gtk2::Notebook->new;
    $notebook->set_show_tabs(0); $notebook->set_show_border(0);
    my ($count_nbs, %pages);
    my $size_group = Gtk2::SizeGroup->new('horizontal');
    my ($cb1, $cb2);
    map {
	my $info = $radios_infos{$_};
	my $url_entry = sub {
	    gtkpack_(
		Gtk2::HBox->new(0, 0),
		1, $info->{url_entry} = gtkentry(),
		if_(
		    $info->{dirsel},
		    0, gtksignal_connect(
			Gtk2::Button->new(but(N("Browse..."))),
			clicked => sub { $info->{url_entry}->set_text(ask_dir()) },
		    )
		),
	    );
	};
        my $tips = Gtk2::Tooltips->new;
        my $checkbut_entry = sub {
            my ($name, $label, $visibility, $callback, $tip) = @_;
            my $w = [ gtksignal_connect(
		    $info->{$name . '_check'} = gtkset_tip($tips, Gtk2::CheckButton->new($label), $tip),
		    clicked => sub {
			$info->{$name . '_entry'}->set_sensitive($_[0]->get_active);
			$callback and $callback->(@_);
		    },
	    ),
	    gtkset_visibility(gtkset_sensitive($info->{$name . '_entry'} = gtkentry(), 0), $visibility) ];
	    $size_group->add_widget($info->{$name . '_check'});
	    $w;
        };
	my $loginpass_entries = sub {
	    map {
		$checkbut_entry->(
		    @$_, sub {
			$info->{pass_check}->set_active($_[0]->get_active);
			$info->{login_check}->set_active($_[0]->get_active);
		    }
		);
	    } ([ 'login', N("Login:"), 1 ], [ 'pass', N("Password:"), 0 ]);
	};
	$pages{$info->{name}} = $count_nbs++;
	my $with_hdlist_checkbut_entry;
	$with_hdlist_checkbut_entry = $checkbut_entry->(
	    'hdlist', N("Relative path to synthesis/hdlist:"), 1,
	    sub { $info->{distrib_check} and $_[0]->get_active and $info->{distrib_check}->set_active(0) },
	    N("If left blank, synthesis/hdlist will be automatically probed"),
	);
	$notebook->append_page(
	    gtkshow(create_packtable(
		{ xpadding => , ypadding => 0 },
		[ gtkset_alignment(Gtk2::Label->new(N("Name:")), 0, 0.5),
		    $info->{name_entry} = gtkentry('') ],
		[ gtkset_alignment(Gtk2::Label->new($info->{url}), 0, 0.5),
		    $url_entry->() ],
		$with_hdlist_checkbut_entry,
		if_($info->{loginpass}, $loginpass_entries->()),
		sub {
		    [ gtksignal_connect(
			    $info->{distrib_check} = $cb1 = Gtk2::CheckButton->new(N("Create media for a whole distribution")),
			    clicked => sub {
				if ($_[0]->get_active) {
				    $info->{hdlist_entry}->set_sensitive(0);
				    $info->{hdlist_check}->set_active(0);
				}
			    },
			)
		    ];
		}->(),
		sub {
		    [ $info->{update_check} = $cb2 = Gtk2::CheckButton->new(N("Search this media for updates")) ];
		}->(),
	    ))
	);
    } @radios_names_ordered;
    $size_group->add_widget($_) foreach $cb1, $cb2;

    my $checkok = sub {
	my $info = $radios_infos{$radios_names_ordered[$notebook->get_current_page]};
	my ($name, $url) = map { $info->{$_ . '_entry'}->get_text } qw(name url);
	$name eq '' || $url eq '' and interactive_msg_('rpmdrake', N("You need to fill up at least the two first entries.")), return 0;
	if (member($name, map { $_->{name} } @{$urpm->{media}})) {
	    $info->{name_entry}->select_region(0, -1);
	    interactive_msg_('rpmdrake',
N("There is already a medium by that name, do you
really want to replace it?"), yesno => 1) or return 0;
	}
	1;
    };

    my ($type, $probe, %i, %make_url, $type_box);
    gtkadd(
	$w->{window},
	gtkpack(
	    Gtk2::VBox->new(0,5),
	    gtknew('Title2', label => N("Adding a medium:")),
	    gtkpack__(Gtk2::HBox->new(0, 0),
                      Gtk2::Label->new(but(N("Type of medium:"))),
                      $type_box = gtksignal_connect(Gtk2::ComboBox->new_with_strings(\@modes, $radios_infos{local}{name}),
                      changed => sub { $notebook->set_current_page($pages{$_[0]->get_text}) })
                     ),
	    $notebook,
	    Gtk2::HSeparator->new,
	    gtkpack(
		create_hbox(),
		gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }),
		gtksignal_connect(
		    Gtk2::Button->new(N("Ok")), clicked => sub {
			if ($checkok->()) {
			    $w->{retval} = { nb => $notebook->get_current_page };
			    ($type) = grep { $radios_infos{$_}{name} eq $type_box->get_text } keys %radios_infos;
			    my $info = $radios_infos{$type};
			    %i = (
				name => $info->{name_entry}->get_text,
				url => $info->{url_entry}->get_text,
				hdlist => $info->{hdlist_entry}->get_text,
				distrib => $info->{distrib_check} ? $info->{distrib_check}->get_active : 0,
				update => $info->{update_check}->get_active ? 1 : undef,
			    );
			    %make_url = (
				local => "file:/$i{url}",
				http => $i{url},
				rsync => $i{url},
				removable => "removable:/$i{url}",
			    );
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
	if ($i{distrib}) {
	    add_medium_and_check(
		$urpm,
		{ nolock => 1, distrib => 1 },
		$i{name}, $make_url{$type}, probe_with => 'synthesis', update => $i{update},
	    );
	} else {
	    if (member($i{name}, map { $_->{name} } @{$urpm->{media}})) {
		$urpm->select_media($i{name});
		$urpm->remove_selected_media;
	    }
	    add_medium_and_check(
		$urpm,
		{ probe_with => $probe, nolock => 1 },
		$i{name}, $make_url{$type}, $i{hdlist}, update => $i{update},
	    );
	}
	return 1;
    }
    return 0;
}

sub options_callback {
    my $w = ugtk2->new(N("Global options for package installation"), grab => 1, center => 1,  transient => $mainw->{real_window});
    my @verif_radio_infos = (
	{ name => N("always"), value => 1 },
	{ name => N("never"),  value => 0 },
    );
    my @verif_radio = gtkradio($verif_radio_infos[$urpm->{options}{'verify-rpm'} ? 0 : 1]{name}, map { $_->{name} } @verif_radio_infos);
    my @avail_downloaders = grep { -f "/usr/bin/$_" } qw(curl wget);
    my @downl_radio = gtkradio($urpm->{options}{downloader} || $avail_downloaders[0], @avail_downloaders);
    gtkadd(
	$w->{window},
	gtkpack(
	    Gtk2::VBox->new(0,5),
	    gtkpack(Gtk2::HBox->new(0,0), Gtk2::Label->new(N("Verify RPMs to be installed:")), @verif_radio),
	    gtkpack(Gtk2::HBox->new(0,0), Gtk2::Label->new(N("Download program to use:")), @downl_radio),
	    gtkpack(
		create_hbox(),
		gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { Gtk2->main_quit }),
		gtksignal_connect(
		    Gtk2::Button->new(N("Ok")), clicked => sub {
			foreach my $i (0 .. $#verif_radio) {
			    $verif_radio[$i]->get_active
				and $urpm->{global_config}{'verify-rpm'} = $verif_radio_infos[$i]{value};
			}
			foreach my $i (0 .. $#downl_radio) {
			    $downl_radio[$i]->get_active
				and $urpm->{global_config}{downloader} = $avail_downloaders[$i];
			}
			$urpm->write_config;
			$urpm = urpm->new;
			$urpm->read_config;
			Gtk2->main_quit;
		    },
		),
	    ),
	),
    );
    $w->main;
}

sub remove_callback {
    my $row = selrow();
    $row == -1 and return;
    interactive_msg_(
	N("Source Removal"),
	N("Are you sure you want to remove source \"%s\"?", to_utf8($urpm->{media}[$row]{name})),
	yesno => 1,
	 transient => $mainw->{real_window},
    ) or return;

    my $wait = wait_msg_(N("Please wait, removing medium..."));
    my $name = $urpm->{media}[$row]{name};
    $urpm->select_media($name);
    $urpm->remove_selected_media;
    $urpm->update_media(noclean => 1, nolock => 1);
    remove_wait_msg($wait);
}

sub renum_media ($$$) {
    my ($model, @iters) = @_;
    my @rows = map { $model->get_path($_)->to_string } @iters;
    my @media = map { $urpm->{media}[$_] } @rows;
    $urpm->{media}[$rows[$_]] = $media[1 - $_] foreach 0, 1;
    my $i = 1;
    $_->{priority} = $i++ foreach @{$urpm->{media}};
    $model->swap(@iters);
    $urpm->write_config; $urpm = urpm->new; $urpm->read_config;
}

sub upwards_callback {
    my ($model, $iter) = $list_tv->get_selection->get_selected; $model && $iter or return;
    my $prev = $model->get_iter_from_string($model->get_path($iter)->to_string - 1);
    defined $prev and renum_media($model, $iter, $prev);
}

sub downwards_callback {
    my ($model, $iter) = $list_tv->get_selection->get_selected; $model && $iter or return;
    my $next = $model->iter_next($iter);
    defined $next and renum_media($model, $iter, $next);
}

#- returns the name of the media for which edition failed, or undef on success
sub edit_callback {
    my $row = selrow();
    $row == -1 and return;
    my $medium = $urpm->{media}[$row];
    my $config = urpm::cfg::load_config($urpm->{config}, 1);
    my $w = ugtk2->new(N("Edit a medium"), grab => 1, center => 1,  transient => $mainw->{real_window});
    my ($url_entry, $hdlist_entry, $url, $with_hdlist);
    gtkadd(
	$w->{window},
	gtkpack_(
	    Gtk2::VBox->new(0,5),
	    0, gtknew('Title2', label => N("Editing medium \"%s\":", $medium->{name})),
	    0, create_packtable(
		{},
		[ gtknew('Label_Left', text => N("URL:")), $url_entry = gtkentry($config->{$medium->{name}}{url}) ],
		[ gtknew('Label_Left', text => N("Relative path to synthesis/hdlist:")), $hdlist_entry = gtkentry($config->{$medium->{name}}{with_hdlist}) ],
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
	    interactive_msg_(
		N("You need to insert the medium to continue"),
		N("In order to save the changes, you need to insert the medium in the drive."),
		yesno => 1, text => { yes => N("Ok"), no => N("Cancel") }
	    ) or return 0
	);
	my $saved_proxy = urpm::download::get_proxy($name);
	undef $saved_proxy if !defined $saved_proxy->{http_proxy} && !defined $saved_proxy->{ftp_proxy};
	$urpm->select_media($name);
	$urpm->remove_selected_media;
	add_medium_and_check($urpm, { nolock => 1, proxy => $saved_proxy }, $name, $url, $with_hdlist, update => $update);
	return $name;
    }
    return undef;
}

sub update_callback {
    update_sources_interactive($urpm,  transient => $mainw->{real_window}, nolock => 1);
}

sub proxy_callback {
    my ($medium) = @_;
    my $medium_name = $medium ? $medium->{name} : '';
    my $w = ugtk2->new(N("Configure proxies"), grab => 1, center => 1,  transient => $mainw->{real_window});
    my ($proxy, $proxy_user) = curl_download::readproxy($medium_name);
    my ($user, $pass) = $proxy_user =~ /^([^:]*):(.*)$/;
    my ($proxybutton, $proxyentry, $proxyuserbutton, $proxyuserentry, $proxypasswordentry);
    my $sg = Gtk2::SizeGroup->new('horizontal');
    gtkadd(
	$w->{window},
	gtkpack__(
	    Gtk2::VBox->new(0, 5),
	    gtknew('Title2', label =>
		$medium_name
		    ? N("Proxy settings for media \"%s\"", $medium_name)
		    : N("Global proxy settings")
	    ),
	    gtknew('Label_Left', text => N("If you need a proxy, enter the hostname and an optional port (syntax: <proxyhost[:port]>):")),
	    gtkpack_(
		Gtk2::HBox->new(0, 10),
		1, gtkset_active($proxybutton = Gtk2::CheckButton->new(N("Proxy hostname:")), to_bool($proxy)),
		0, gtkadd_widget($sg, gtkset_sensitive($proxyentry = gtkentry($proxy), to_bool($proxy))),
	    ),
         gtkset_active($proxyuserbutton = Gtk2::CheckButton->new(N("You may specify a user/password for the proxy authentication:")), to_bool($proxy_user)),
	    gtkpack_(
		my $hb_user = gtkset_sensitive(Gtk2::HBox->new(0, 10), to_bool($proxy_user)),
		1, gtknew('Label_Left', text => N("User:")),
		0, gtkadd_widget($sg, $proxyuserentry = gtkentry($user)),
      ),
	    gtkpack_(
		my $hb_pswd = gtkset_sensitive(Gtk2::HBox->new(0, 10), to_bool($proxy_user)),
		1, gtknew('Label_Left', text => N("Password:")),
		0, gtkadd_widget($sg, gtkset_visibility($proxypasswordentry = gtkentry($pass), 0)),
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
    $sg->add_widget($_) foreach ($proxyentry, $proxyuserentry, $proxypasswordentry);
    $proxybutton->signal_connect(
	clicked => sub {
	    $proxyentry->set_sensitive($_[0]->get_active);
	    $_[0]->get_active and return;
	    $proxyuserbutton->set_active(0);
	    $hb_user->set_sensitive(0);
	    $hb_pswd->set_sensitive(0);
	}
    );
    $proxyuserbutton->signal_connect(clicked => sub { $_->set_sensitive($_[0]->get_active) foreach $hb_user, $hb_pswd;
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
    my $w = ugtk2->new($num == -1 ? N("Add a parallel group") : N("Edit a parallel group"), grab => 1, center => 1,  transient => $mainw->{real_window});
    my $name_entry;

    my $medias_ls = Gtk2::ListStore->new("Glib::String");
    my $medias = Gtk2::TreeView->new_with_model($medias_ls);
    $medias->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
    $medias->set_headers_visible(0);
    $medias->get_selection->set_mode('browse');
    $medias_ls->append_set([ 0 => $_ ]) foreach @{$edited->{medias}};

    my $add_media = sub {
        my $w = ugtk2->new(N("Add a medium limit"), grab => 1,  transient => $mainw->{real_window});
        my $medias_list_ls = Gtk2::ListStore->new("Glib::String");
        my $medias_list = Gtk2::TreeView->new_with_model($medias_list_ls);
        $medias_list->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
        $medias_list->set_headers_visible(0);
        $medias_list->get_selection->set_mode('browse');
        $medias_list_ls->append_set([ 0 => $_->{name} ]) foreach @{$urpm->{media}};
        my $sel;
        gtkadd(
	    $w->{window},
	    gtkpack__(
		Gtk2::VBox->new(0, 5),
		Gtk2::Label->new(N("Choose a medium for adding in the media limit:")),
		$medias_list,
		Gtk2::HSeparator->new,
		gtkpack(
		    create_hbox(),
		    gtksignal_connect(
			Gtk2::Button->new(N("Ok")),
			clicked => sub { $w->{retval} = 1; $sel = selrow($medias_list); Gtk2->main_quit },
		    ),
		    gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit })
		)
	    )
	);
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
    if    ($edited->{protocol} eq 'ssh')    { $hosts_list = [ split /:/, $edited->{command} ] }
    elsif ($edited->{protocol} eq 'ka-run') { push @$hosts_list, $1 while $edited->{command} =~ /-m (\S+)/g }
    $hosts_ls->append_set([ 0 => $_ ]) foreach @$hosts_list;
    my $add_host = sub {
        my $w = ugtk2->new(N("Add a host"), grab => 1,  transient => $mainw->{real_window});
        my ($entry, $value);
	gtkadd(
	    $w->{window},
	    gtkpack__(
		Gtk2::VBox->new(0, 5),
		Gtk2::Label->new(N("Type in the hostname or IP address of the host to add:")),
		$entry = gtkentry(),
		Gtk2::HSeparator->new,
		gtkpack(
		    create_hbox(),
		    gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { $w->{retval} = 1; $value = $entry->get_text; Gtk2->main_quit }),
		    gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit })
		)
	    )
	);
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
    gtkadd(
	$w->{window},
	gtkpack_(
	    Gtk2::VBox->new(0, 5),
	    if_(
		$num != -1,
		0, Gtk2::Label->new(N("Editing parallel group \"%s\":", $edited->{name}))
	    ),
	    1, create_packtable(
		{},
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
			gtksignal_connect(Gtk2::Button->new(but(N("Remove"))), clicked => sub { $remove_host->() }))) ]
	    ),
	    0, Gtk2::HSeparator->new,
	    0, gtkpack(
		create_hbox(),
		gtksignal_connect(
		    Gtk2::Button->new(N("Ok")), clicked => sub {
			$w->{retval} = 1;
			$edited->{name} = $name_entry->get_text;
			mapn { $_[0]->get_active and $edited->{protocol} = $_[1] } \@protocols, \@protocols_names;
			Gtk2->main_quit;
		    }
		),
		gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))
	)
    );
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
    my $w = ugtk2->new(N("Configure parallel urpmi (distributed execution of urpmi)"), grab => 1, center => 1,  transient => $mainw->{real_window});
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

    gtkadd(
	$w->{window},
	gtkpack_(
	    Gtk2::VBox->new(0,5),
	    1, gtkpack_(
		Gtk2::HBox->new(0, 10),
		1, $list,
		0, gtkpack__(
		    Gtk2::VBox->new(0, 5),
		    gtksignal_connect(
			$remove = Gtk2::Button->new(but(N("Remove"))),
			clicked => sub { remove_parallel(selrow($list), $conf); $reread->() },
		    ),
		    gtksignal_connect(
			$edit = Gtk2::Button->new(but(N("Edit..."))),
			clicked => sub {
			    my $row = selrow($list);
			    $row != -1 and edit_parallel($row, $conf);
			    $reread->();
			},
		    ),
		    gtksignal_connect(
			Gtk2::Button->new(but(N("Add..."))),
			clicked => sub { edit_parallel(-1, $conf) and $reread->() },
		    )
		)
	    ),
	    0, Gtk2::HSeparator->new,
	    0, gtkpack(
		create_hbox(),
		gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { Gtk2->main_quit })
	    )
	)
    );
    $w->main;
}

sub keys_callback {
    my $w = ugtk2->new(N("Manage keys for digital signatures of packages"), grab => 1, center => 1,  transient => $mainw->{real_window});

    my $media_list_ls = Gtk2::ListStore->new("Glib::String");
    my $media_list = Gtk2::TreeView->new_with_model($media_list_ls);
    $media_list->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Medium"), Gtk2::CellRendererText->new, 'text' => 0));
    $media_list->get_selection->set_mode('browse');

    my $keys_list_ls = Gtk2::ListStore->new("Glib::String", "Glib::String");
    my $keys_list = Gtk2::TreeView->new_with_model($keys_list_ls);
    $keys_list->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("_:cryptographic keys\nKeys"), Gtk2::CellRendererText->new, 'text' => 0));
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
        my $w_add = ugtk2->new(N("Add a key"), grab => 1,  transient => $w->{real_window});
        my $available_keyz_ls = Gtk2::ListStore->new("Glib::String", "Glib::String");
        my $available_keyz = Gtk2::TreeView->new_with_model($available_keyz_ls);
        $available_keyz->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
        $available_keyz->set_headers_visible(0);
        $available_keyz->get_selection->set_mode('browse');
        $available_keyz_ls->append_set([ 0 => sprintf("%s (%s)", $_, $key_name->($_)), 1 => $_ ]) foreach keys %{$urpm->{keys}};
        my $key;
	gtkadd(
	    $w_add->{window},
	    gtkpack__(
		Gtk2::VBox->new(0, 5),
		Gtk2::Label->new(N("Choose a key for adding to the medium %s", $current_medium)),
		$available_keyz,
		Gtk2::HSeparator->new,
		gtkpack(
		    create_hbox(),
		    gtksignal_connect(
			Gtk2::Button->new(N("Ok")),
			clicked => sub {
			    my ($model, $iter) = $available_keyz->get_selection->get_selected;
			    $model && $iter and $key = $model->get($iter, 1);
			    Gtk2->main_quit;
			},
		    ),
		    gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { Gtk2->main_quit })
		)
	    )
	);
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
	interactive_msg_(N("Remove a key"),
                        N("Are you sure you want to remove the key %s from medium %s?\n(name of the key: %s)",
                          $key, $current_medium, $key_name->($key)),
                        yesno => 1,  transient => $w->{real_window}) or return;
        $urpm->{media}[$current_medium_nb]{'key-ids'} = join(',', difference2(\@{$keys[$current_medium_nb]}, [ $key ]));
        $write->();
    };

    gtkadd(
	$w->{window},
	gtkpack_(
	    Gtk2::VBox->new(0,5),
	    1, gtkpack_(
		Gtk2::HBox->new(0, 10),
		1, $media_list,
		1, $keys_list,
		0, gtkpack__(
		    Gtk2::VBox->new(0, 5),
		    gtksignal_connect(
			$remove = Gtk2::Button->new(but(N("Add a key..."))),
			clicked => \&$add_key,
		    ),
		    gtksignal_connect(
			$remove = Gtk2::Button->new(but(N("Remove key"))),
			clicked => \&$remove_key,
		    )
		)
	    ),
	    0, Gtk2::HSeparator->new,
	    0, gtkpack(
		create_hbox(),
		gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { Gtk2->main_quit })
	    ),
	),
    );
    $w->main;
}

sub mainwindow {
    $mainw = ugtk2->new(N("Configure media"), center => 1);
    $::main_window = $mainw->{real_window};

    my $list = Gtk2::ListStore->new("Glib::Boolean", "Glib::Boolean", "Glib::String");
    $list_tv = Gtk2::TreeView->new_with_model($list);
    $list_tv->get_selection->set_mode('browse');
    my ($up_button, $dw_button);
    $list_tv->get_selection->signal_connect(changed => sub {
        my ($model, $iter) = $_[0]->get_selected;
        return if !$iter;
        my $curr_path = $model->get_path($iter);
        my $first_path = $model->get_path($model->get_iter_first);
        $up_button->set_sensitive($first_path && $first_path->compare($curr_path));

        $curr_path->next;
        my $next_item = $model->get_iter($curr_path);
        $dw_button->set_sensitive($next_item); # && !$model->get($next_item, 0)
    });

    $list_tv->set_rules_hint(1);
    $list_tv->set_reorderable(1);

    my $reorder_ok = 1;
    $list->signal_connect(
	row_deleted => sub {
	    $reorder_ok or return;
	    my ($model) = @_;
	    my @media;
	    $model->foreach(
		sub {
		    my (undef, undef, $iter) = @_;
		    my $name = $model->get($iter, 2);
		    push @media, find { $_->{name} eq $name } @{$urpm->{media}};
		    0;
		}, undef);
	    @{$urpm->{media}} = @media;
	},
    );

    $list_tv->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Enabled?"), my $tr = Gtk2::CellRendererToggle->new, 'active' => 0));
    $list_tv->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Updates?"), my $cu = Gtk2::CellRendererToggle->new, 'active' => 1));
    $list_tv->append_column(Gtk2::TreeViewColumn->new_with_attributes(N("Medium"), Gtk2::CellRendererText->new, 'text' => 2));

    my $reread_media; #- closure defined later
    $tr->signal_connect(
	toggled => sub {
	    my (undef, $path) = @_;
	    my $iter = $list->get_iter_from_string($path);
	    $urpm->{media}[$path]{ignore} = !$urpm->{media}[$path]{ignore} || undef;
	    $list->set($iter, 0, !$urpm->{media}[$path]{ignore});
	    $urpm->write_config;
	    my $ignored = $urpm->{media}[$path]{ignore};
	    $reread_media->();
	    if (!$ignored && $urpm->{media}[$path]{ignore}) {
		#- Enabling this media failed, force update
		interactive_msg_('rpmdrake',
		    N("This medium needs to be updated to be usable. Update it now ?"),
		    yesno => 1,
		) and $reread_media->($urpm->{media}[$path]{name});
	    }
	},
    );

    $cu->signal_connect(
	toggled => sub {
	    my (undef, $path) = @_;
	    my $iter = $list->get_iter_from_string($path);
	    $urpm->{media}[$path]{update} = !$urpm->{media}[$path]{update} || undef;
	    $list->set($iter, 1, ! !$urpm->{media}[$path]{update});
	},
    );

    $reread_media = sub {
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
	    update_sources_check(
		$urpm,
		{ nolock => 1 },
		N_("Unable to update medium, errors reported:\n\n%s"),
		$name,
	    );
	}
	$list->clear;
	$list->append_set(0 => !$_->{ignore}, 1 => ! !$_->{update}, 2 => $_->{name}) foreach grep { ! $_->{external} } @{$urpm->{media}};
        $reorder_ok = 1;
    };
    $reread_media->();

    gtkadd(
	$mainw->{window},
	gtkpack_(
	    Gtk2::VBox->new(0,5),
	    1, gtkpack_(
		Gtk2::HBox->new(0, 10),
		1, create_scrolled_window($list_tv),
		0, gtkpack__(
		    Gtk2::VBox->new(0, 5),
		    gtksignal_connect(
			$remove = Gtk2::Button->new(but(N("Remove"))),
			clicked => sub { remove_callback(); $reread_media->() },
		    ),
		    gtksignal_connect(
			$edit = Gtk2::Button->new(but(N("Edit..."))),
			clicked => sub {
			    my $name = edit_callback(); defined $name and $reread_media->($name);
			}
		    ),
		    gtksignal_connect(
			Gtk2::Button->new(but(N("Add..."))),
			clicked => sub { easy_add_callback() and $reread_media->() },
		    ),
		    gtksignal_connect(
			Gtk2::Button->new(but(N("Add custom..."))),
			clicked => sub { add_callback() and $reread_media->() },
		    ),
		    gtksignal_connect(
			Gtk2::Button->new(but(N("Update..."))),
			clicked => sub { update_callback() and $reread_media->() },
		    ),
		    gtksignal_connect(Gtk2::Button->new(but(N("Manage keys..."))), clicked => \&keys_callback),
		    gtksignal_connect(Gtk2::Button->new(but(N("Proxy..."))), clicked => \&proxy_callback),
		    gtksignal_connect(Gtk2::Button->new(but(N("Parallel..."))), clicked => \&parallel_callback),
		    gtksignal_connect(Gtk2::Button->new(but(N("Global options..."))), clicked => \&options_callback),
		    gtkpack(
			Gtk2::HBox->new(0, 0),
			gtksignal_connect(gtkadd($up_button = Gtk2::Button->new, Gtk2::Arrow->new("up", "none")), clicked => \&upwards_callback),
			gtksignal_connect(gtkadd($dw_button = Gtk2::Button->new, Gtk2::Arrow->new("down", "none")), clicked => \&downwards_callback),
		    ),
		)
	    ),
	    0, Gtk2::HSeparator->new,
	    0, gtkpack(create_hbox('edge'),
		gtksignal_connect(Gtk2::Button->new(but(N("Help"))), clicked => sub { rpmdrake::open_help('sources') }),
		gtksignal_connect(Gtk2::Button->new(but(N("Ok"))), clicked => sub { Gtk2->main_quit })
	    )
	)
    );
    $mainw->{rwindow}->set_size_request(600, -1);
    $mainw->main;
}

sub interactive_msg_  {  interactive_msg(@_, if_(defined $::main_window, transient => $::main_window)) }
sub wait_msg_         {         wait_msg(@_, if_(defined $::main_window, transient => $::main_window)) }

readconf();

if (!member(basename($0), @$already_splashed)) {
    interactive_msg_('rpmdrake',
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
        interactive_msg_('rpmdrake',
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
