package Rpmdrake::edit_urpm_sources;
#*****************************************************************************
# 
#  Copyright (c) 2002 Guillaume Cottenceau
#  Copyright (c) 2002-2007 Thierry Vignaud <tvignaud@mandriva.com>
#  Copyright (c) 2002-2007 Mandriva Linux
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
use Rpmdrake::open_db;
use Rpmdrake::formatting;
use URPM::Signature;
use MDK::Common::Math qw(max);
use urpm::media;
use urpm::download;
use urpm::lock;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(run);

use mygtk3 qw(gtknew gtkset);
use ugtk3 qw(:all);

my $urpm;
my ($mainw, $list_tv, $something_changed);

my %col = (
    mainw => {
        is_enabled => 0,
        is_update  => 1,
        type       => 2,
        name       => 3,
        activatable => 4
    },
);


sub get_medium_type {
    my ($medium) = @_;
    my %medium_type = (
        cdrom     => N("CD-ROM"),
        ftp       => N("FTP"),
        file      => N("Local"),
        http      => N("HTTP"),
        https     => N("HTTPS"),
        nfs       => N("NFS"),
        removable => N("Removable"),
        rsync     => N("rsync"),
        ssh       => N("SSH"),
    );
    return N("Mirror list") if $medium->{mirrorlist};
    return $medium_type{$1} if $medium->{url} =~ m!^([^:]*)://!;
    return N("Local");
}

sub selrow {
    my ($o_list_tv) = @_;
    defined $o_list_tv or $o_list_tv = $list_tv;
    my ($model, $iter) = $o_list_tv->get_selection->get_selected;
    $model && $iter or return -1;
    my $path = $model->get_path($iter);
    my $row = $path->to_string;
    return $row;
}

sub selected_rows {
    my ($o_list_tv) = @_;
    defined $o_list_tv or $o_list_tv = $list_tv;
    my ($rows) = $o_list_tv->get_selection->get_selected_rows;
    return -1 if @$rows == 0;
    map { $_->to_string } @$rows;
}

sub remove_row {
    my ($model, $path_str) = @_;
    my $iter = $model->get_iter_from_string($path_str);
    $iter or return;
    $model->remove($iter);
}

sub remove_from_list {
    my ($list, $list_ref, $model) = @_;
    my $row = selrow($list);
    if ($row != -1) {
        splice @$list_ref, $row, 1;
        remove_row($model, $row);
    }

}

sub _want_base_distro() {
    $::expert && distro_type(0) eq 'updates' ? interactive_msg(
	N("Choose media type"),
N("In order to keep your system secure and stable, you must at a minimum set up
sources for official security and stability updates. You can also choose to set
up a fuller set of sources which includes the complete official OpenMandriva Lx
repositories, giving you access to a greater variety of software. Please choose
whether to configure update sources only, or the full set
of sources."),
	 transient => $::main_window,
	yesno => 1, text => { yes => N("Full set of sources"), no => N("Update sources only") },
    ) : 1;
}

sub easy_add_callback_with_mirror() {
    # when called on early init by rpmdrake
    $urpm ||= fast_open_urpmi_db();

    #- cooker and community don't have update sources
    my $want_base_distro = _want_base_distro();
    defined $want_base_distro or return;
    my $distro = $rpmdrake::mandrake_release;
    my ($mirror) = choose_mirror($urpm, message =>
N("This will attempt to install all official sources corresponding to your
distribution (%s).

I need to contact the OpenMandriva website to get the mirror list.
Please check that your network is currently running.

Is it ok to continue?", $distro),
     transient => $::main_window,
    ) or return 0;
    ref $mirror or return;
    my $wait = wait_msg(N("Please wait, adding media..."));
    add_distrib_update_media($urpm, $mirror, if_(!$want_base_distro, only_updates => 1));
    $offered_to_add_sources->[0] = 1;
    remove_wait_msg($wait);
    return 1;
}

sub easy_add_callback() {
    # when called on early init by rpmdrake
    $urpm ||= fast_open_urpmi_db();

    #- cooker and community don't have update sources
    my $want_base_distro = _want_base_distro();
    defined $want_base_distro or return;
    warn_for_network_need(undef, transient => $::main_window) or return;
    my $wait = wait_msg(N("Please wait, adding media..."));
    add_distrib_update_media($urpm, undef, if_(!$want_base_distro, only_updates => 1));
    $offered_to_add_sources->[0] = 1;
    remove_wait_msg($wait);
    return 1;
}

sub add_callback() {
    my $w = ugtk3->new(N("Add a medium"), grab => 1, center => 1,  transient => $::main_window);
    my $prev_main_window = $::main_window;
    local $::main_window = $w->{real_window};
    my %radios_infos = (
	local => { name => N("Local files"), url => N("Medium path:"), dirsel => 1 },
	ftp => { name => N("FTP server"), url => N("URL:"), loginpass => 1 },
	rsync => { name => N("RSYNC server"), url => N("URL:") },
	http => { name => N("HTTP server"), url => N("URL:") },
	removable => { name => N("Removable device (CD-ROM, DVD, ...)"), url => N("Path or mount point:"), dirsel => 1 },
    );
    my @radios_names_ordered = qw(local ftp rsync http removable);
    # TODO: replace NoteBook by sensitive widgets and Label->set()
    my $notebook = gtknew('Notebook');
    $notebook->set_show_tabs(0); $notebook->set_show_border(0);
    my ($count_nbs, %pages);
    my $size_group = Gtk3::SizeGroup->new('horizontal');
    my ($cb1, $cb2);
    foreach (@radios_names_ordered) {
	my $info = $radios_infos{$_};
	my $url_entry = sub {
	    gtkpack_(
		gtknew('HBox'),
		1, $info->{url_entry} = gtkentry(),
		if_(
		    $info->{dirsel},
		    0, gtksignal_connect(
			gtknew('Button', text => but(N("Browse..."))),
			clicked => sub {
                            my $dir = ask_dir() or return;
                            $info->{url_entry}->set_text(ask_dir());
                        },
		    )
		),
	    );
	};
        my $checkbut_entry = sub {
            my ($name, $label, $visibility, $callback, $tip) = @_;
            my $w = [ gtksignal_connect(
		    $info->{$name . '_check'} = gtkset(gtknew('CheckButton', text => $label), tip => $tip),
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
	$notebook->append_page(
	    gtkshow(create_packtable(
		{ xpadding => 0, ypadding => 0 },
		[ gtkset_alignment(gtknew('Label', text => N("Medium name:")), 0, 0.5),
		    $info->{name_entry} = gtkentry('') ],
		[ gtkset_alignment(gtknew('Label', text => $info->{url}), 0, 0.5),
		    $url_entry->() ],
		if_($info->{loginpass}, $loginpass_entries->()),
		sub {
		    [ $info->{distrib_check} = $cb1 = gtknew('CheckButton', text => N("Create media for a whole distribution"),
                                                         toggled => sub {
                                                             return if !$cb2;
                                                             my ($w) = @_;
                                                             $info->{update_check}->set_sensitive(!$w->get_active);
                                                         })
		    ];
		}->(),
		sub {
		    [ $info->{update_check} = $cb2 = gtknew('CheckButton', text => N("Tag this medium as an update medium")) ];
		}->(),
	    ))
	);
    }
    $size_group->add_widget($_) foreach $cb1, $cb2;

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

    my $type = 'local';
    my (%i, %make_url);
    gtkadd(
	$w->{window},
	gtkpack(
	    gtknew('VBox', spacing => 5),
	    gtknew('Title2', label => N("Adding a medium:")),
	    gtknew('HBox', children_tight => [
                      Gtk3::Label->new(but(N("Type of medium:"))),
                      gtknew('ComboBox', text_ref => \$type, 
                             list => \@radios_names_ordered,
                             format => sub { $radios_infos{$_[0]}{name} },
                             changed => sub { $notebook->set_current_page($pages{$_[0]->get_text}) })
                     ]),
	    $notebook,
	    gtknew('HSeparator'),
	    gtkpack(
		gtknew('HButtonBox'),
		gtknew('Button', text => N("Cancel"), clicked => sub { $w->{retval} = 0; Gtk3->main_quit }),
		gtksignal_connect(
		    gtknew('Button', text => N("Ok")), clicked => sub {
			if ($checkok->()) {
			    $w->{retval} = { nb => $notebook->get_current_page };
			    my $info = $radios_infos{$type};
			    %i = (
				name => $info->{name_entry}->get_text,
				url => $info->{url_entry}->get_text,
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
			    Gtk3->main_quit;
			}
		    },
		),
	    ),
	),
    );

    if ($w->main) {
	$::main_window = $prev_main_window;
	if ($i{distrib}) {
	    add_medium_and_check(
		$urpm,
		{ nolock => 1, distrib => 1 },
		$i{name}, $make_url{$type}, probe_with => 'synthesis', update => $i{update},
	    );
	} else {
	    if (member($i{name}, map { $_->{name} } @{$urpm->{media}})) {
		urpm::media::select_media($urpm, $i{name});
		urpm::media::remove_selected_media($urpm);
	    }
	    add_medium_and_check(
		$urpm,
		{ nolock => 1 },
		$i{name}, $make_url{$type}, $i{hdlist}, update => $i{update},
	    );
	}
	return 1;
    }
    return 0;
}

sub options_callback() {
    my $w = ugtk3->new(N("Global options for package installation"), grab => 1, center => 1,  transient => $::main_window);
    local $::main_window = $w->{real_window};
    my %verif = (0 => N("never"), 1 => N("always"));
    my $verify_rpm = $urpm->{global_config}{'verify-rpm'};
    my @avail_downloaders = urpm::download::available_ftp_http_downloaders();
    my $downloader = $urpm->{global_config}{downloader} || $avail_downloaders[0];
    my %xml_info_policies = (
        'never'       => N("Never"), 
        'on-demand'   => N("On-demand"), 
        'update-only' => N("Update-only"), 
        'always'      => N("Always"), 
    );
    my $xml_info_policy = $urpm->{global_config}{'xml-info'};

    gtkadd(
	$w->{window},
	gtkpack(
	    gtknew('VBox', spacing => 5),
	    gtknew('HBox', children_loose => [ gtknew('Label', text => N("Verify RPMs to be installed:")),
                                               gtknew('ComboBox', list => [ keys %verif ], text_ref => \$verify_rpm,
                                                      format => sub { $verif{$_[0]} || $_[0] },
                                                  )
                                           ]),
	    gtknew('HBox', children_loose => [ gtknew('Label', text => N("Download program to use:")),
                                               gtknew('ComboBox', list => \@avail_downloaders, text_ref => \$downloader,
                                                      format => sub { $verif{$_[0]} || $_[0] },
                                                  )
                                           ]),
	    gtknew('HBox',
                   children_loose =>
                     [ gtknew('Label', text => N("XML meta-data download policy:")),
                       gtknew('ComboBox',
                              list => [ keys %xml_info_policies ], text_ref => \$xml_info_policy,

                              format => sub { $xml_info_policies{$_[0]} || $_[0] },
                              tip => 
                                join("\n",
                                     N("For remote media, specify when XML meta-data (file lists, changelogs & information) are downloaded."),
                                     '',
                                     N("Never"),
                                     N("For remote media, XML meta-data are never downloaded."),
                                     '',
                                     N("On-demand"),
                                     N("(This is the default)"),
                                     N("The specific XML info file is downloaded when clicking on package."),
                                     '',
                                     N("Update-only"), 
                                     N("Updating media implies updating XML info files already required at least once."),
                                     '',
                                     N("Always"),
                                     N("All XML info files are downloaded when adding or updating media."),
                                 ),
                          ),
                   ]),

	    gtkpack(
		gtknew('HButtonBox'),
		gtknew('Button', text => N("Cancel"), clicked => sub { Gtk3->main_quit }),
		gtksignal_connect(
		    gtknew('Button', text => N("Ok")), clicked => sub {
                        $urpm->{global_config}{'verify-rpm'} = $verify_rpm;
                        $urpm->{global_config}{downloader} = $downloader;
                        $urpm->{global_config}{'xml-info'} = $xml_info_policy;
                        $something_changed = 1;
			urpm::media::write_config($urpm);
			$urpm = fast_open_urpmi_db();
			Gtk3->main_quit;
		    },
		),
	    ),
	),
    );
    $w->main;
}

sub remove_callback() {
    my @rows = selected_rows();
    @rows == 0 and return;
    interactive_msg(
	N("Source Removal"),
	@rows == 1 ?
	  N("Are you sure you want to remove source \"%s\"?", $urpm->{media}[$rows[0]]{name}) :
	    N("Are you sure you want to remove the following sources?") . "\n\n" .
	      format_list(map { $urpm->{media}[$_]{name} } @rows),
	yesno => 1, scroll => 1,
	 transient => $::main_window,
    ) or return;

    my $wait = wait_msg(N("Please wait, removing medium..."));
    foreach my $row (reverse(@rows)) {
     $something_changed = 1;
	urpm::media::remove_media($urpm, [ $urpm->{media}[$row] ]);
	urpm::media::write_urpmi_cfg($urpm);
	remove_wait_msg($wait);
    }
    return 1;
}

sub renum_media ($$$) {
    my ($model, @iters) = @_;
    my @rows = map { $model->get_path($_)->to_string } @iters;
    my @media = map { $urpm->{media}[$_] } @rows;
    $urpm->{media}[$rows[$_]] = $media[1 - $_] foreach 0, 1;
    $model->swap(@iters);
    $something_changed = 1;
    urpm::media::write_config($urpm);
    $urpm = fast_open_urpmi_db();
}

sub upwards_callback() {
    my @rows = selected_rows();
    @rows == 0 and return;
    my $model = $list_tv->get_model;
    my $prev = $model->get_iter_from_string($rows[0] - 1);
    defined $prev and renum_media($model, $model->get_iter_from_string($rows[0]), $prev);
    $list_tv->get_selection->signal_emit('changed');
}

sub downwards_callback() {
    my @rows = selected_rows();
    @rows == 0 and return;
    my $model = $list_tv->get_model;
    my $iter = $model->get_iter_from_string($rows[0]);
    my $next = $model->get_iter_from_string($rows[0] + 1);
    defined $next and renum_media($model, $iter, $next);
    $list_tv->get_selection->signal_emit('changed');
}

#- returns the name of the media for which edition failed, or undef on success
sub edit_callback() {
    my ($row) = selected_rows();
    $row == -1 and return;
    my $medium = $urpm->{media}[$row];
    my $config = urpm::cfg::load_config_raw($urpm->{config}, 1);
    my ($verbatim_medium) = grep { $medium->{name} eq $_->{name} } @$config;
    my $old_main_window = $::main_window;
    my $w = ugtk3->new(N("Edit a medium"), grab => 1, center => 1,  transient => $::main_window);
    local $::main_window = $w->{real_window};
    my ($url_entry, $downloader_entry, $url, $downloader);
    gtkadd(
	$w->{window},
	gtkpack_(
	    gtknew('VBox', spacing => 5),
	    0, gtknew('Title2', label => N("Editing medium \"%s\":", $medium->{name})),
	    0, create_packtable(
		{},
		[ gtknew('Label_Left', text => N("URL:")), $url_entry = gtkentry($verbatim_medium->{url} || $verbatim_medium->{mirrorlist}) ],
		[ gtknew('Label_Left', text => N("Downloader:")),
            my $download_combo = Gtk3::ComboBox->new_with_strings([ urpm::download::available_ftp_http_downloaders() ],
                                                                  $verbatim_medium->{downloader} || '') ],
	    ),
	    0, gtknew('HSeparator'),
	    0, gtkpack(
		gtknew('HButtonBox'),
		gtksignal_connect(
		    gtknew('Button', text => N("Cancel")),
		    clicked => sub { $w->{retval} = 0; Gtk3->main_quit },
		),
		gtksignal_connect(
		    gtknew('Button', text => N("Save changes")),
		    clicked => sub {
			$w->{retval} = 1;
			$url = $url_entry->get_text;
			$downloader = $downloader_entry->get_text;
			Gtk3->main_quit;
		    },
		),
		gtksignal_connect(
		    gtknew('Button', text => N("Proxy...")),
		    clicked => sub { proxy_callback($medium) },
		),
	    )
	)
    );
    $downloader_entry = $download_combo->entry;
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
	my $saved_proxy = urpm::download::get_proxy($name);
	undef $saved_proxy if !defined $saved_proxy->{http_proxy} && !defined $saved_proxy->{ftp_proxy};
	urpm::media::select_media($urpm, $name);
     if (my ($media) = grep { $_->{name} eq $name } @{$urpm->{media}}) {
         put_in_hash($media, {
             ($verbatim_medium->{mirrorlist} ? 'mirrorlist' : 'url') => $url,
             name => $name,
             if_($update ne $media->{update} || $update, update => $update),
             if_($saved_proxy ne $media->{proxy} || $saved_proxy, proxy => $saved_proxy),
             if_($downloader ne $media->{downloader} || $downloader, downloader => $downloader),
             modified => 1,
         });
         urpm::media::write_config($urpm);
         local $::main_window = $old_main_window;
         update_sources_noninteractive($urpm, [ $name ], transient => $::main_window, nolock => 1);
     } else {
         urpm::media::remove_selected_media($urpm);
         add_medium_and_check($urpm, { nolock => 1, proxy => $saved_proxy }, $name, $url, undef, update => $update, if_($downloader, downloader => $downloader));
     }
	return $name;
    }
    return undef;
}

sub update_callback() {
    update_sources_interactive($urpm,  transient => $::main_window, nolock => 1);
}

sub proxy_callback {
    my ($medium) = @_;
    my $medium_name = $medium ? $medium->{name} : '';
    my $w = ugtk3->new(N("Configure proxies"), grab => 1, center => 1,  transient => $::main_window);
    local $::main_window = $w->{real_window};
    my ($proxy, $proxy_user) = readproxy($medium_name);
    my ($user, $pass) = $proxy_user =~ /^([^:]*):(.*)$/;
    my ($proxybutton, $proxyentry, $proxyuserbutton, $proxyuserentry, $proxypasswordentry);
    my $sg = Gtk3::SizeGroup->new('horizontal');
    gtkadd(
	$w->{window},
	gtkpack__(
	    gtknew('VBox', spacing => 5),
	    gtknew('Title2', label =>
		$medium_name
		    ? N("Proxy settings for media \"%s\"", $medium_name)
		    : N("Global proxy settings")
	    ),
	    gtknew('Label_Left', text => N("If you need a proxy, enter the hostname and an optional port (syntax: <proxyhost[:port]>):")),
	    gtkpack_(
		gtknew('HBox', spacing => 10),
		1, gtkset_active($proxybutton = gtknew('CheckButton', text => N("Proxy hostname:")), to_bool($proxy)),
		0, gtkadd_widget($sg, gtkset_sensitive($proxyentry = gtkentry($proxy), to_bool($proxy))),
	    ),
         gtkset_active($proxyuserbutton = gtknew('CheckButton', text => N("You may specify a username/password for the proxy authentication:")), to_bool($proxy_user)),
	    gtkpack_(
		my $hb_user = gtknew('HBox', spacing => 10, sensitive => to_bool($proxy_user)),
		1, gtknew('Label_Left', text => N("User:")),
		0, gtkadd_widget($sg, $proxyuserentry = gtkentry($user)),
      ),
	    gtkpack_(
		my $hb_pswd = gtknew('HBox', spacing => 10, sensitive => to_bool($proxy_user)),
		1, gtknew('Label_Left', text => N("Password:")),
		0, gtkadd_widget($sg, gtkset_visibility($proxypasswordentry = gtkentry($pass), 0)),
	    ),
	    gtknew('HSeparator'),
	    gtkpack(
		gtknew('HButtonBox'),
		gtksignal_connect(
		    gtknew('Button', text => N("Ok")),
		    clicked => sub {
			$w->{retval} = 1;
			$proxy = $proxybutton->get_active ? $proxyentry->get_text : '';
			$proxy_user = $proxyuserbutton->get_active
			    ? ($proxyuserentry->get_text . ':' . $proxypasswordentry->get_text) : '';
			Gtk3->main_quit;
		    },
		),
		gtksignal_connect(
		    gtknew('Button', text => N("Cancel")),
		    clicked => sub { $w->{retval} = 0; Gtk3->main_quit },
		)
	    )
	)
    );
    $sg->add_widget($_) foreach $proxyentry, $proxyuserentry, $proxypasswordentry;
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

    $w->main and do {
        $something_changed = 1;
        writeproxy($proxy, $proxy_user, $medium_name);
    };
}

sub parallel_read_sysconf() {
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

sub add_callback_ {
    my ($title, $label, $mainw, $widget, $get_value, $check) = @_;
    my $w = ugtk3->new($title, grab => 1,  transient => $mainw->{real_window});
    local $::main_window = $w->{real_window};
    gtkadd(
        $w->{window},
        gtkpack__(
            gtknew('VBox', spacing => 5),
            gtknew('Label', text => $label),
            $widget,
            gtknew('HSeparator'),
            gtkpack(
                gtknew('HButtonBox'),
                gtknew('Button', text => N("Ok"), clicked => sub { $w->{retval} = 1; $get_value->(); Gtk3->main_quit }),
                gtknew('Button', text => N("Cancel"), clicked => sub { $w->{retval} = 0; Gtk3->main_quit })
            )
        )
    );
    $check->() if $w->main;
}

sub edit_parallel {
    my ($num, $conf) = @_;
    my $edited = $num == -1 ? {} : $conf->[$num];
    my $w = ugtk3->new($num == -1 ? N("Add a parallel group") : N("Edit a parallel group"), grab => 1, center => 1,  transient => $::main_window);
    local $::main_window = $w->{real_window};
    my $name_entry;

    my ($medias_ls, $hosts_ls) = (Gtk3::ListStore->new("Glib::String"), Gtk3::ListStore->new("Glib::String"));

    my ($medias, $hosts) = map {
        my $list = Gtk3::TreeView->new_with_model($_);
        $list->append_column(Gtk3::TreeViewColumn->new_with_attributes('', Gtk3::CellRendererText->new, 'text' => 0));
        $list->set_headers_visible(0);
        $list->get_selection->set_mode('browse');
        $list;
    } $medias_ls, $hosts_ls;

    $medias_ls->append_set([ 0 => $_ ]) foreach @{$edited->{medias}};

    my $add_media = sub {
        my $medias_list_ls = Gtk3::ListStore->new("Glib::String");
        my $medias_list = Gtk3::TreeView->new_with_model($medias_list_ls);
        $medias_list->append_column(Gtk3::TreeViewColumn->new_with_attributes('', Gtk3::CellRendererText->new, 'text' => 0));
        $medias_list->set_headers_visible(0);
        $medias_list->get_selection->set_mode('browse');
        $medias_list_ls->append_set([ 0 => $_->{name} ]) foreach @{$urpm->{media}};
        my $sel;
        add_callback_(N("Add a medium limit"), N("Choose a medium to add to the media limit:"),
                      $w, $medias_list, sub { $sel = selrow($medias_list) },
                      sub {
                          return if $sel == -1;
                          my $media = ${$urpm->{media}}[$sel]{name};
                          $medias_ls->append_set([ 0 => $media ]);
                          push @{$edited->{medias}}, $media;
                      }
                  );
    };

    my $hosts_list;
    if    ($edited->{protocol} eq 'ssh')    { $hosts_list = [ split /:/, $edited->{command} ] }
    elsif ($edited->{protocol} eq 'ka-run') { push @$hosts_list, $1 while $edited->{command} =~ /-m (\S+)/g }
    $hosts_ls->append_set([ 0 => $_ ]) foreach @$hosts_list;
    my $add_host = sub {
        my ($entry, $value);
        add_callback_(N("Add a host"), N("Type in the hostname or IP address of the host to add:"),
                      $mainw, $entry = gtkentry(), sub { $value = $entry->get_text },
                      sub { $hosts_ls->append_set([ 0 => $value ]); push @$hosts_list, $value }
                  );
    };

    my @protocols_names = qw(ka-run ssh);
    my @protocols;
    gtkadd(
	$w->{window},
	gtkpack_(
	    gtknew('VBox', spacing => 5),
	    if_(
		$num != -1,
		0, gtknew('Label', text => N("Editing parallel group \"%s\":", $edited->{name}))
	    ),
	    1, create_packtable(
		{},
		[ N("Group name:"), $name_entry = gtkentry($edited->{name}) ],
		[ N("Protocol:"), gtknew('HBox', children_tight => [
		    @protocols = gtkradio($edited->{protocol}, @protocols_names) ]) ],
		[ N("Media limit:"),
		gtknew('HBox', spacing => 5, children => [
		    1, gtknew('Frame', shadow_type => 'in', child => 
			gtknew('ScrolledWindow', h_policy => 'never', child => $medias)),
		    0, gtknew('VBox', children_tight => [
			gtksignal_connect(Gtk3::Button->new(but(N("Add"))),    clicked => sub { $add_media->() }),
			gtksignal_connect(Gtk3::Button->new(but(N("Remove"))), clicked => sub {
                                              remove_from_list($medias, $edited->{medias}, $medias_ls);
                                          }) ]) ]) ],
		[ N("Hosts:"),
		gtknew('HBox', spacing => 5, children => [
		    1, gtknew('Frame', shadow_type => 'in', child => 
			gtknew('ScrolledWindow', h_policy => 'never', child => $hosts)),
		    0, gtknew('VBox', children_tight => [
			gtksignal_connect(Gtk3::Button->new(but(N("Add"))),    clicked => sub { $add_host->() }),
			gtksignal_connect(Gtk3::Button->new(but(N("Remove"))), clicked => sub {
                                              remove_from_list($hosts, $hosts_list, $hosts_ls);
                                          }) ]) ]) ]
	    ),
	    0, gtknew('HSeparator'),
	    0, gtkpack(
		gtknew('HButtonBox'),
		gtksignal_connect(
		    gtknew('Button', text => N("Ok")), clicked => sub {
			$w->{retval} = 1;
			$edited->{name} = $name_entry->get_text;
			mapn { $_[0]->get_active and $edited->{protocol} = $_[1] } \@protocols, \@protocols_names;
			Gtk3->main_quit;
		    }
		),
		gtknew('Button', text => N("Cancel"), clicked => sub { $w->{retval} = 0; Gtk3->main_quit }))
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

sub parallel_callback() {
    my $w = ugtk3->new(N("Configure parallel urpmi (distributed execution of urpmi)"), grab => 1, center => 1,  transient => $mainw->{real_window});
    local $::main_window = $w->{real_window};
    my $list_ls = Gtk3::ListStore->new("Glib::String", "Glib::String", "Glib::String", "Glib::String");
    my $list = Gtk3::TreeView->new_with_model($list_ls);
    each_index { $list->append_column(Gtk3::TreeViewColumn->new_with_attributes($_, Gtk3::CellRendererText->new, 'text' => $::i)) } N("Group"), N("Protocol"), N("Media limit");
    $list->append_column(my $commandcol = Gtk3::TreeViewColumn->new_with_attributes(N("Command"), Gtk3::CellRendererText->new, 'text' => 3));
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
	    gtknew('VBox', spacing => 5),
	    1, gtkpack_(
		gtknew('HBox', spacing => 10),
		1, $list,
		0, gtkpack__(
		    gtknew('VBox', spacing => 5),
		    gtksignal_connect(
			Gtk3::Button->new(but(N("Remove"))),
			clicked => sub { remove_parallel(selrow($list), $conf); $reread->() },
		    ),
		    gtksignal_connect(
			Gtk3::Button->new(but(N("Edit..."))),
			clicked => sub {
			    my $row = selrow($list);
			    $row != -1 and edit_parallel($row, $conf);
			    $reread->();
			},
		    ),
		    gtksignal_connect(
			Gtk3::Button->new(but(N("Add..."))),
			clicked => sub { edit_parallel(-1, $conf) and $reread->() },
		    )
		)
	    ),
	    0, gtknew('HSeparator'),
	    0, gtkpack(
		gtknew('HButtonBox'),
		gtknew('Button', text => N("Ok"), clicked => sub { Gtk3->main_quit })
	    )
	)
    );
    $w->main;
}

sub keys_callback() {
    my $w = ugtk3->new(N("Manage keys for digital signatures of packages"), grab => 1, center => 1,  transient => $mainw->{real_window});
    local $::main_window = $w->{real_window};
    $w->{real_window}->set_size_request(600, 300);

    my $media_list_ls = Gtk3::ListStore->new("Glib::String");
    my $media_list = Gtk3::TreeView->new_with_model($media_list_ls);
    $media_list->append_column(Gtk3::TreeViewColumn->new_with_attributes(N("Medium"), Gtk3::CellRendererText->new, 'text' => 0));
    $media_list->get_selection->set_mode('browse');

    my $key_col_size = 200;
    my $keys_list_ls = Gtk3::ListStore->new("Glib::String", "Glib::String");
    my $keys_list = Gtk3::TreeView->new_with_model($keys_list_ls);
    $keys_list->set_rules_hint(1);
    $keys_list->append_column(my $col = Gtk3::TreeViewColumn->new_with_attributes(N("_:cryptographic keys\nKeys"), my $renderer = Gtk3::CellRendererText->new, 'text' => 0));
    $col->set_sizing('fixed');
    $col->set_fixed_width($key_col_size);
    $renderer->set_property('width' => 1);
    $renderer->set_property('wrap-width', $key_col_size);
    $keys_list->get_selection->set_mode('browse');

    my ($current_medium, $current_medium_nb, @keys);

    my $read_conf = sub {
        $urpm->parse_pubkeys(root => $urpm->{root});
        @keys = map { [ split /[,\s]+/, $_->{'key-ids'} ] } @{$urpm->{media}};
    };
    my $write = sub {
        $something_changed = 1;
        urpm::media::write_config($urpm);
        $urpm = fast_open_urpmi_db();
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
        my $available_keyz_ls = Gtk3::ListStore->new("Glib::String", "Glib::String");
        my $available_keyz = Gtk3::TreeView->new_with_model($available_keyz_ls);
        $available_keyz->append_column(Gtk3::TreeViewColumn->new_with_attributes('', Gtk3::CellRendererText->new, 'text' => 0));
        $available_keyz->set_headers_visible(0);
        $available_keyz->get_selection->set_mode('browse');
        $available_keyz_ls->append_set([ 0 => sprintf("%s (%s)", $_, $key_name->($_)), 1 => $_ ]) foreach keys %{$urpm->{keys}};
        my $key;
        add_callback_(N("Add a key"), N("Choose a key to add to the medium %s", $current_medium), $w, $available_keyz,
                      sub {
                          my ($model, $iter) = $available_keyz->get_selection->get_selected;
                          $model && $iter and $key = $model->get($iter, 1);
                      },
                      sub {
                          return if !defined $key;
                          $urpm->{media}[$current_medium_nb]{'key-ids'} = join(',', sort(uniq(@{$keys[$current_medium_nb]}, $key)));
                          $write->();
                      }
                  );


    };

    my $remove_key = sub {
        my ($model, $iter) = $keys_list->get_selection->get_selected;
        $model && $iter or return;
        my $key = $model->get($iter, 1);
	interactive_msg(N("Remove a key"),
                        N("Are you sure you want to remove the key %s from medium %s?\n(name of the key: %s)",
                          $key, $current_medium, $key_name->($key)),
                        yesno => 1,  transient => $w->{real_window}) or return;
        $urpm->{media}[$current_medium_nb]{'key-ids'} = join(',', difference2(\@{$keys[$current_medium_nb]}, [ $key ]));
        $write->();
    };

    gtkadd(
	$w->{window},
	gtkpack_(
	    gtknew('VBox', spacing => 5),
	    1, gtkpack_(
		gtknew('HBox', spacing => 10),
		1, create_scrolled_window($media_list),
		1, create_scrolled_window($keys_list),
		0, gtkpack__(
		    gtknew('VBox', spacing => 5),
		    gtksignal_connect(
			Gtk3::Button->new(but(N("Add"))),
			clicked => \&$add_key,
		    ),
		    gtksignal_connect(
			Gtk3::Button->new(but(N("Remove"))),
			clicked => \&$remove_key,
		    )
		)
	    ),
	    0, gtknew('HSeparator'),
	    0, gtkpack(
		gtknew('HButtonBox'),
		gtknew('Button', text => N("Ok"), clicked => sub { Gtk3->main_quit })
	    ),
	),
    );
    $w->main;
}

sub show_about() {
    my $license = formatAlaTeX(translate($::license));
    $license =~ s/\n/\n\n/sg; # nicer formatting
    my $w = gtknew('AboutDialog', name => N("Rpmdrake"),
		   version => $rpmdrake::distro_version,
		   copyright => N("Copyright (C) %s by Mandriva\nCopyright (C) %s OpenMandriva", '2002-2008', '2013'),
		   license => $license, wrap_license => 1,
		   comments => N("Rpmdrake is the OpenMandriva package management tool."),
		   website => 'http://openmandriva.org/',
		   website_label => N("OpenMandriva"),
		   authors => [ 'Thierry Vignaud <vignaud@mandriva.com>' ],
		   artists => [ 'Rugyada' ],
		   translator_credits =>
		   #-PO: put here name(s) and email(s) of translator(s) (eg: "John Smith <jsmith@nowhere.com>")
		   N("_: Translator(s) name(s) & email(s)\n"),
		   transient_for => $::main_window, modal => 1, position_policy => 'center-on-parent',
	);
    $w->show_all;
    $w->run;
}

sub mainwindow() {
    undef $something_changed;
    $mainw = ugtk3->new(N("Configure media"), center => 1, transient => $::main_window, modal => 1);
    local $::main_window = $mainw->{real_window};

    my $reread_media;

    my $ui = gtknew(
	'UIManager',
	actions => [
	    [ 'FileMenu', undef, N("_File") ],
	    [ 'Update', undef, N("_Update"), N("<control>U"), undef, sub { update_callback() and $reread_media->() }, ],
	    [ 'Add_a_specific_mirror', undef, N("Add a specific _media mirror"), N("<control>M"), undef, sub { easy_add_callback_with_mirror() and $reread_media->() } ],
	    [ 'Add_a_custom_medium', undef, N("_Add a custom medium"), N("<control>A"), undef, sub { add_callback() and $reread_media->() } ],
	    [ 'Close', undef, N("Close"), N("<control>W"), undef, sub { Gtk3->main_quit }, ],
	    [ 'OptionsMenu', undef, N("_Options") ],
	    [ 'Global_options', undef, N("_Global options"), N("<control>G"), undef, \&options_callback ],
	    [ 'Manage_keys', undef, N("Manage _keys"), N("<control>K"), undef, \&keys_callback ],
	    [ 'Parallel', undef, N("_Parallel"), N("<control>P"), undef, \&parallel_callback ],
	    [ 'Proxy', undef, N("P_roxy"), N("<control>R"), undef, \&proxy_callback ],
	    if_($0 =~ /edit-urpm-sources/,
		[ 'HelpMenu', undef, N("_Help") ],
		[ 'Report_Bug', undef, N("_Report Bug"), undef, undef, sub { run_drakbug('edit-urpm-sources.pl') } ],
		[ 'Help', undef, N("_Help"), undef, undef, sub { rpmdrake::open_help('sources') } ],
		[ 'About', undef, N("_About..."), undef, undef, \&show_about ],
	    ),
	],
	string =>
	join("\n",
	     qq(<ui>
  <menubar name='MenuBar'>
    <menu action='FileMenu'>
      <menuitem action='Update'/>
      <menuitem action='Add_a_specific_mirror'/>
      <menuitem action='Add_a_custom_medium'/>
      <menuitem action='Close'/>
    </menu>
    <menu action='OptionsMenu'>
      <menuitem action='Global_options'/>
      <menuitem action='Manage_keys'/>
      <menuitem action='Parallel'/>
      <menuitem action='Proxy'/>
    </menu>
),
	     if_($0 =~ /edit-urpm-sources/, qq(
    <menu action='HelpMenu'>
      <menuitem action='Report_Bug'/>
      <menuitem action='Help'/>
      <menuitem action='About'/>
    </menu>)),
	     qq(
  </menubar>
</ui>)));

    my $menu = $ui->get_widget('/MenuBar');

    my $list = Gtk3::ListStore->new("Glib::Boolean", "Glib::Boolean", "Glib::String", "Glib::String", "Glib::Boolean");
    $list_tv = Gtk3::TreeView->new_with_model($list);
    $list_tv->get_selection->set_mode('multiple');
    my ($dw_button, $edit_button, $remove_button, $up_button);
    $list_tv->get_selection->signal_connect(changed => sub {
        my ($selection) = @_;
        my ($rows) = $selection->get_selected_rows;
        my $model = $list;
        my $size = $#{$rows};
        # we can delete several medium at a time:
        $remove_button and $remove_button->set_sensitive($size != -1);
        # we can only edit/move one item at a time:
        $_ and $_->set_sensitive($size == 0) foreach $up_button, $dw_button, $edit_button;

        # we can only up/down one item if not at begin/end:
        return if $size != 0;
	
        my $curr_path = $rows->[0];
        my $first_path = $model->get_path($model->get_iter_first);
        $up_button->set_sensitive($first_path && $first_path->compare($curr_path));

        $curr_path->next;
        my $next_item = $model->get_iter($curr_path);
        $dw_button->set_sensitive($next_item || 0); # && !$model->get($next_item, 0)
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
		    my $name = $model->get($iter, $col{mainw}{name});
		    push @media, urpm::media::name2medium($urpm, $name);
		    0;
		}, undef);
	    @{$urpm->{media}} = @media;
	},
    );

    $list_tv->append_column(Gtk3::TreeViewColumn->new_with_attributes(N("Enabled"),
                                                                      my $tr = Gtk3::CellRendererToggle->new,
                                                                      'active' => $col{mainw}{is_enabled}));
    $list_tv->append_column(Gtk3::TreeViewColumn->new_with_attributes(N("Updates"),
                                                                      my $cu = Gtk3::CellRendererToggle->new,
                                                                      'active' => $col{mainw}{is_update},
                                                                      activatable => $col{mainw}{activatable}));
    $list_tv->append_column(Gtk3::TreeViewColumn->new_with_attributes(N("Type"),
                                                                      Gtk3::CellRendererText->new,
                                                                      'text' => $col{mainw}{type}));
    $list_tv->append_column(Gtk3::TreeViewColumn->new_with_attributes(N("Medium"),
                                                                      Gtk3::CellRendererText->new,
                                                                      'text' => $col{mainw}{name}));
    my $id;
    $id = $tr->signal_connect(
	toggled => sub {
	    my (undef, $path) = @_;
	    $tr->signal_handler_block($id);
	    my $_guard = before_leaving { $tr->signal_handler_unblock($id) };
	    my $iter = $list->get_iter_from_string($path);
	    $urpm->{media}[$path]{ignore} = !$urpm->{media}[$path]{ignore} || undef;
	    $list->set($iter, $col{mainw}{is_enabled}, !$urpm->{media}[$path]{ignore});
	    urpm::media::write_config($urpm);
	    my $ignored = $urpm->{media}[$path]{ignore};
	    $reread_media->();
	    if (!$ignored && $urpm->{media}[$path]{ignore}) {
		# reread media failed to un-ignore an ignored medium
		# probably because urpm::media::check_existing_medium() complains
		# about missing synthesis when the medium never was enabled before;
		# thus it restored the ignore bit
		$urpm->{media}[$path]{ignore} = !$urpm->{media}[$path]{ignore} || undef;
		urpm::media::write_config($urpm);
		#- Enabling this media failed, force update
		interactive_msg('rpmdrake',
		    N("This medium needs to be updated to be usable. Update it now?"),
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
	    $list->set($iter, $col{mainw}{is_update}, ! !$urpm->{media}[$path]{update});
         $something_changed = 1;
	},
    );

    $reread_media = sub {
	my ($name) = @_;
        $reorder_ok = 0;
     $something_changed = 1;
        # save position:
        my $rect = $list_tv->get_visible_rect;
        my ($x, $y) = @$rect{'x', 'y'};
	if (defined $name) {
	    urpm::media::select_media($urpm, $name);
	    update_sources_check(
		$urpm,
		{ nolock => 1 },
		N_("Unable to update medium, errors reported:\n\n%s"),
		$name,
	    );
	}
	# reread configuration after updating media else ignore bit will be restored
	# by urpm::media::check_existing_medium():
	$urpm = fast_open_urpmi_db();
	$list->clear;
     foreach (grep { ! $_->{external} } @{$urpm->{media}}) {
         my $name = $_->{name};
         $list->append_set($col{mainw}{is_enabled} => !$_->{ignore},
                           $col{mainw}{is_update} => ! !$_->{update},
                           $col{mainw}{type} => get_medium_type($_),
                           $col{mainw}{name} => $name,
                           $col{mainw}{activatable} => to_bool($::expert),
                       );
     }
        $reorder_ok = 1;
        # restore position:
        Glib::Timeout->add(10, sub { $list_tv->scroll_to_point($x, $y); 0 });
    };
    $reread_media->();
    $something_changed = 0;

    gtkadd(
	$mainw->{window},
	gtkpack_(
	    gtknew('VBox', spacing => 5),
	    0, $menu,
	    ($0 =~ /rpm-edit-media|edit-urpm-sources/ ? (0, Gtk3::Banner->new($ugtk3::wm_icon, N("Configure media"))) : ()),
	    1, gtkpack_(
		gtknew('HBox', spacing => 10),
		1, gtknew('ScrolledWindow', child => $list_tv),
		0, gtkpack__(
		    gtknew('VBox', spacing => 5),
		    gtksignal_connect(
			$remove_button = Gtk3::Button->new(but(N("Remove"))),
			clicked => sub { remove_callback() and $reread_media->() },
		    ),
		    gtksignal_connect(
			$edit_button = Gtk3::Button->new(but(N("Edit"))),
			clicked => sub {
			    my $name = edit_callback(); defined $name and $reread_media->($name);
			}
		    ),
		    gtksignal_connect(
			Gtk3::Button->new(but(N("Add"))),
			clicked => sub { easy_add_callback() and $reread_media->() },
		    ),
		    gtkpack(
			gtknew('HBox'),
			gtksignal_connect(
                            $up_button = gtknew('Button',
                                                image => gtknew('Image', stock => 'gtk-go-up')),
                            clicked => \&upwards_callback),

			gtksignal_connect(
                            $dw_button = gtknew('Button',
                                                image => gtknew('Image', stock => 'gtk-go-down')),
                            clicked => \&downwards_callback),
		    ),
		)
	    ),
	    0, gtknew('HSeparator'),
	    0, gtknew('HButtonBox', layout => 'edge', children_loose => [
		gtksignal_connect(Gtk3::Button->new(but(N("Help"))), clicked => sub { rpmdrake::open_help('sources') }),
		gtksignal_connect(Gtk3::Button->new(but(N("Ok"))), clicked => sub { Gtk3->main_quit })
	    ])
	)
    );
    $_->set_sensitive(0) foreach $dw_button, $edit_button, $remove_button, $up_button;

    $mainw->{rwindow}->set_size_request(600, 400);
    $mainw->main;
    return $something_changed;
}


sub run() {
    # ignore rpmdrake's option regarding ignoring debug media:
    local $ignore_debug_media = [ 0 ];
    local $ugtk3::wm_icon = get_icon('rpmdrake-omv', 'title-media');
    my $lock;
    {
        $urpm = fast_open_urpmi_db();
        my $err_msg = "urpmdb locked\n";
        local $urpm->{fatal} = sub {
            interactive_msg('rpmdrake',
                            N("The Package Database is locked. Please close other applications
working with the Package Database (do you have another media

manager on another desktop, or are you currently installing
packages as well?"));
            die $err_msg;
        };
        # lock urpmi DB
        eval { $lock = urpm::lock::urpmi_db($urpm, 'exclusive', wait => $urpm->{options}{wait_lock}) };
        if (my $err = $@) {
            return if $err eq $err_msg;
            die $err;
        }
    }

    my $res = mainwindow();
    urpm::media::write_config($urpm);

    writeconf();

    undef $lock;
    $res;
}

sub readproxy (;$) {
    my $proxy = get_proxy($_[0]);
    ($proxy->{http_proxy} || $proxy->{ftp_proxy} || '',
	defined $proxy->{user} ? "$proxy->{user}:$proxy->{pwd}" : '');
}

sub writeproxy {
    my ($proxy, $proxy_user, $o_media_name) = @_;
    my ($user, $pwd) = split /:/, $proxy_user;
    set_proxy_config(user => $user, $o_media_name);
    set_proxy_config(pwd => $pwd, $o_media_name);
    set_proxy_config(http_proxy => $proxy, $o_media_name);
    set_proxy_config(ftp_proxy => $proxy, $o_media_name);
    dump_proxy_config();
}

1;
