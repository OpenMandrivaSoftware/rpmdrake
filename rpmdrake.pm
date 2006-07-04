#*****************************************************************************
# 
#  Copyright (c) 2002 Guillaume Cottenceau
#  Copyright (c) 2002-2006 Thierry Vignaud <tvignaud@mandriva.com>
#  Copyright (c) 2003, 2004, 2005 MandrakeSoft SA
#  Copyright (c) 2005, 2006 Mandriva SA
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

package rpmdrake;

use lib qw(/usr/lib/libDrakX);
use urpm::download ();
use urpm::prompt;

use MDK::Common;
use MDK::Common::System;
use urpm;
use urpm::cfg;
use URPM;
use URPM::Resolve;
use strict;
use c;
use POSIX qw(_exit);
use common;

use curl_download;

our @ISA = qw(Exporter);
our $VERSION = '2.27';
our @EXPORT = qw(
    $changelog_first_config
    $mandrakeupdate_wanted_categories
    $already_splashed
    $max_info_in_descr
    $tree_mode
    $tree_flat
    $typical_width
    distro_type
    to_utf8
    myexit
    readconf
    writeconf
    interactive_msg
    interactive_packtable
    interactive_list
    fatal_msg
    getbanner
    wait_msg
    remove_wait_msg
    but
    but_
    slow_func
    slow_func_statusbar
    statusbar_msg
    statusbar_msg_remove
    choose_mirror
    make_url_mirror
    make_url_mirror_dist
    show_urpm_progress
    update_sources
    update_sources_check
    update_sources_interactive
    add_medium_and_check
    check_update_media_version
    strip_first_underscore
);
our $typical_width;
unshift @::textdomains, 'rpmdrake', 'urpmi';

eval { require ugtk2; ugtk2->import(qw(:all)) };
if ($@) {
    print "This program cannot be run in console mode.\n";
    _exit(0);  #- skip ugtk2::END
}
ugtk2::add_icon_path('/usr/share/rpmdrake/icons');

Locale::gettext::bind_textdomain_codeset('rpmdrake', 'UTF8');

our $mandrake_release = cat_(
    -e '/etc/mandrakelinux-release' ? '/etc/mandrakelinux-release' : '/etc/release'
) || '';
chomp $mandrake_release;
(our $mdk_version) = $mandrake_release =~ /(\d+\.\d+)/;
our $branded = -f '/etc/sysconfig/oem'
    and our %distrib = MDK::Common::System::distrib();
our $myname_update = $rpmdrake::branded ? N("Software Update") : N("Mandriva Linux Update");

@rpmdrake::prompt::ISA = 'urpm::prompt';

sub rpmdrake::prompt::prompt {
    my ($self) = @_;
    my @answers;
    my $d = ugtk2->new("", grab => 1, transient => 1);
    $d->{rwindow}->set_position('center_on_parent');
    gtkadd(
	$d->{window},
	gtkpack(
	    Gtk2::VBox->new(0, 5),
	    Gtk2::WrappedLabel->new($self->{title}),
	    (map { gtkpack(
		Gtk2::HBox->new(0, 5),
		Gtk2::Label->new($self->{prompts}[$_]),
		$answers[$_] = gtkset_visibility(gtkentry(), !$self->{hidden}[$_]),
	    ) } 0 .. $#{$self->{prompts}}),
	    gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { Gtk2->main_quit }),
	),
    );
    $d->main;
    map { $_->get_text } @answers;
}

$urpm::download::PROMPT_PROXY = new rpmdrake::prompt(
    N("Please enter your credentials for accessing proxy\n"),
    [ N("User name:"), N("Password:") ],
    undef,
    [ 0, 1 ],
);

sub to_utf8 {
    foreach (@_) {
        $_ = Locale::gettext::iconv($_, undef, "UTF-8");
        c::set_tagged_utf8($_);
    }
    wantarray() ? @_ : $_[0];
}

sub myexit { ugtk2::exit(undef, @_) }

$ENV{HOME} ||= '/root';

our $configfile = "$ENV{HOME}/.rpmdrake";
our %config = (
    mandrakeupdate_wanted_categories => { var => \our $mandrakeupdate_wanted_categories, default => [ qw(security) ] },
    already_splashed => { var => \our $already_splashed, default => [] },
    max_info_in_descr => { var => \our $max_info_in_descr, default => [] },
    tree_mode => { var => \our $tree_mode, default => [ qw(mandrake_choices) ] },
    tree_flat => { var => \our $tree_flat, default => [ 0 ] },
    changelog_first_config => { var => \our $changelog_first_config, default => [ 0 ] },
);

sub readconf() {
    ${$config{$_}{var}} = $config{$_}{default} foreach keys %config;
    foreach my $l (cat_($configfile)) {
	$l =~ /^\Q$_\E (.*)/ and ${$config{$_}{var}} = [ split ' ', $1 ] foreach keys %config;
    }
}

sub writeconf() {
    unlink $configfile;
    output $configfile, map { "$_ " . join(' ', @${$config{$_}{var}}) . "\n" } keys %config;
}

sub getbanner() {
    $::MODE or return undef;
    Gtk2::Banner->new("title-$::MODE", {
	remove  => N("Software Packages Removal"),
	update  => N("Software Packages Update"),
	install => N("Software Packages Installation"),
    }->{$::MODE});
}

sub interactive_msg {
    my ($title, $contents, %options) = @_;
    my $d = ugtk2->new($title, grab => 1, if_(exists $options{transient}, transient => $options{transient}));
    $d->{rwindow}->set_position($options{transient} ? 'center_on_parent' : 'center_always');
    $contents = formatAlaTeX($contents) unless $options{scroll}; #- because we'll use a WrappedLabel
    my $banner = $options{banner} ? getbanner() : undef;
    gtkadd(
	$d->{window},
	gtkpack_(
	    Gtk2::VBox->new(0, 5),
	    if_($banner, 0, $banner),
	    1,
	    (
		$options{scroll} ? gtkadd(
		    gtkset_shadow_type(Gtk2::Frame->new, 'in'),
		    gtkset_size_request(
			create_scrolled_window(gtktext_insert(Gtk2::TextView->new, $contents)),
			$typical_width*2, 300
		    )
		) : gtkpack(create_hbox(), Gtk2::WrappedLabel->new($contents))
	    ),
	    0,
	    gtkpack(
		create_hbox(),
		(
		    ref($options{yesno}) eq 'ARRAY' ? map {
			my $label = $_;
			gtksignal_connect(
			    Gtk2::Button->new($label),
			    clicked => sub { $d->{retval} = $label; Gtk2->main_quit }
			);
		    } @{$options{yesno}}
		    : (
			$options{yesno} ? (
			    gtksignal_connect(
				Gtk2::Button->new($options{text}{no} || N("No")),
				clicked => sub { $d->{retval} = 0; Gtk2->main_quit }
			    ),
			    gtksignal_connect(
				Gtk2::Button->new($options{text}{yes} || N("Yes")),
				clicked => sub { $d->{retval} = 1; Gtk2->main_quit }
			    ),
			)
			: gtksignal_connect(
			    Gtk2::Button->new(N("Ok")),
			    clicked => sub { Gtk2->main_quit }
			)
		    )
		)
	    )
	)
    );
    $d->main;
}

sub interactive_packtable {
    my ($title, $parent_window, $top_label, $lines, $action_buttons) = @_;
    
    my $w = ugtk2->new($title, grab => 1, transient => $parent_window);
    $w->{rwindow}->set_position('center_on_parent');
    my $packtable = create_packtable({}, @$lines);

    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0, 5),
		    if_($top_label, 0, Gtk2::Label->new($top_label)),
		    1, create_scrolled_window($packtable),
		    0, gtkpack__(create_hbox(), @$action_buttons)));
    my $preq = $packtable->size_request;
    my ($xpreq, $ypreq) = ($preq->width, $preq->height);
    my $wreq = $w->{rwindow}->size_request;
    my ($xwreq, $ywreq) = ($wreq->width, $wreq->height);
    $w->{rwindow}->set_default_size(max($typical_width, min($typical_width*2.5, $xpreq+$xwreq)),
 				    max(200, min(450, $ypreq+$ywreq)));
    $w->main;
}

sub interactive_list {
    my ($title, $contents, $list, $callback, %options) = @_;
    my $d = ugtk2->new($title, grab => 1, if_(exists $options{transient}, transient => $options{transient}));
    $d->{rwindow}->set_position($options{transient} ? 'center_on_parent' : 'center_always');
    my @radios = gtkradio('', @$list);
    my $vbradios = $callback ? create_packtable(
	{},
	mapn {
	    my $n = $_[1];
	    [ $_[0],
	    gtksignal_connect(
		Gtk2::Button->new(but(N("Info..."))),
		clicked => sub { $callback->($n) },
	    ) ];
	} \@radios, $list,
    ) : gtkpack__(Gtk2::VBox->new(0, 0), @radios);
    my $choice;
    gtkadd(
	$d->{window},
	gtkpack__(
	    Gtk2::VBox->new(0,5),
	    Gtk2::Label->new($contents),
	    int(@$list) > 8 ? gtkset_size_request(create_scrolled_window($vbradios), 250, 320) : $vbradios,
	    gtkpack__(
		create_hbox(),
          gtksignal_connect(
		    Gtk2::Button->new(N("Cancel")), clicked => sub { Gtk2->main_quit }),
          gtksignal_connect(
		    Gtk2::Button->new(N("Ok")), clicked => sub {
			each_index { $_->get_active and $choice = $::i } @radios;
			Gtk2->main_quit;
		    }
		)
	    )
	)
    );
    $d->main;
    $choice;
}

sub fatal_msg {
    interactive_msg @_;
    myexit -1;
}

sub wait_msg {
    my ($msg, %options) = @_;
    gtkflush();
    my $mainw = ugtk2->new('Rpmdrake', grab => 1, if_(exists $options{transient}, transient => $options{transient}));
    $mainw->{real_window}->set_position($options{transient} ? 'center_on_parent' : 'center_always');
    my $label = ref($msg) =~ /^Gtk/ ? $msg : Gtk2::WrappedLabel->new($msg);
    my $banner = $options{banner} ? getbanner() : undef;
    gtkadd(
	$mainw->{window},
	gtkpack__(
	    gtkset_border_width(Gtk2::VBox->new(0, 5), 6),
	    if_($banner, $banner),
	    $label,
	    if_(exists $options{widgets}, @{$options{widgets}}),
	)
    );
    $mainw->sync;
    gtkset_mousecursor_wait($mainw->{rwindow}->window) unless $options{no_wait_cursor};
    $mainw->flush;
    $mainw;
}

sub remove_wait_msg {
    my $w = shift;
    gtkset_mousecursor_normal($w->{rwindow}->window);
    $w->destroy;
}

sub but { "    $_[0]    " }
sub but_ { "        $_[0]        " }

sub slow_func ($&) {
    my ($param, $func) = @_;
    if (ref($param) =~ /^Gtk/) {
	gtkset_mousecursor_wait($param);
	ugtk2::flush();
	$func->();
	gtkset_mousecursor_normal($param);
    } else {
	my $w = wait_msg($param);
	$func->();
	remove_wait_msg($w);
    }
}

sub statusbar_msg {
    unless ($::statusbar) { #- fallback if no status bar
	if (defined &::wait_msg_) { goto &::wait_msg_ } else { goto &wait_msg }
    }
    my ($msg) = @_;
    #- always use the same context description for now
    my $cx = $::statusbar->get_context_id("foo");
    $::w and $::w->{rwindow} and gtkset_mousecursor_wait($::w->{rwindow}->window);
    #- returns a msg_id to be passed optionnally to statusbar_msg_remove
    $::statusbar->push($cx, $msg);
}

sub statusbar_msg_remove {
    my ($msg_id) = @_;
    if (!$::statusbar || ref $msg_id) { #- fallback if no status bar
	goto &remove_wait_msg;
    }
    my $cx = $::statusbar->get_context_id("foo");
    if (defined $msg_id) {
	$::statusbar->remove($cx, $msg_id);
    } else {
	$::statusbar->pop($cx);
    }
    $::w and $::w->{rwindow} and gtkset_mousecursor_normal($::w->{rwindow}->window);
}

sub slow_func_statusbar ($$&) {
    my ($msg, $w, $func) = @_;
    gtkset_mousecursor_wait($w->window);
    my $msg_id = statusbar_msg($msg);
    gtkflush();
    $func->();
    statusbar_msg_remove($msg_id);
    gtkset_mousecursor_normal($w->window);
}

my %u2l = (
	   at => N("Austria"),
	   au => N("Australia"),
	   be => N("Belgium"),
	   br => N("Brazil"),
	   ca => N("Canada"),
	   ch => N("Switzerland"),
	   cr => N("Costa Rica"),
	   cz => N("Czech Republic"),
	   de => N("Germany"),
	   dk => N("Danmark"),
	   el => N("Greece"),
	   es => N("Spain"),
	   fi => N("Finland"),
	   fr => N("France"),
	   gr => N("Greece"),
	   hu => N("Hungary"),
	   il => N("Israel"),
	   it => N("Italy"),
	   jp => N("Japan"),
	   ko => N("Korea"),
	   nl => N("Netherlands"),
	   no => N("Norway"),
	   pl => N("Poland"),
	   pt => N("Portugal"),
	   ru => N("Russia"),
	   se => N("Sweden"),
	   sg => N("Singapore"),
	   sk => N("Slovakia"),
	   tw => N("Taiwan"),
	   uk => N("United Kingdom"),
	   cn => N("China"),
	   com => N("United States"),
	   org => N("United States"),
	   net => N("United States"),
	   edu => N("United States"),
	  );
my $us = [ qw(com org net edu) ];
my %t2l = (
	   'America/\w+' =>       $us,
	   'Asia/Tel_Aviv' =>     [ qw(il ru it cz at de fr se) ],
	   'Asia/Tokyo' =>        [ qw(jp ko tw), @$us ],
	   'Asia/Seoul' =>        [ qw(ko jp tw), @$us ],
	   'Asia/Taipei' =>       [ qw(tw jp), @$us ],
	   'Asia/(Shanghai|Beijing)' => [ qw(cn tw sg), @$us ],
	   'Asia/Singapore' =>    [ qw(cn sg), @$us ],
	   'Atlantic/Reykjavik' => [ qw(uk no se fi dk), @$us, qw(nl de fr at cz it) ],
	   'Australia/\w+' =>     [ qw(au jp ko tw), @$us ],
	   'Brazil/\w+' =>        [ 'br', @$us ],
	   'Canada/\w+' =>        [ 'ca', @$us ],
	   'Europe/Amsterdam' =>  [ qw(nl be de at cz fr se dk it) ],
	   'Europe/Athens' =>     [ qw(gr pl cz de it nl at fr) ],
	   'Europe/Berlin' =>     [ qw(de be at nl cz it fr se) ],
	   'Europe/Brussels' =>   [ qw(be de nl fr cz at it se) ],
	   'Europe/Budapest' =>   [ qw(cz it at de fr nl se) ],
	   'Europe/Copenhagen' => [ qw(dk nl de be se at cz it) ],
	   'Europe/Dublin' =>     [ qw(uk fr be nl dk se cz it) ],
	   'Europe/Helsinki' =>   [ qw(fi se no nl be de fr at it) ],
	   'Europe/Istanbul' =>   [ qw(il ru it cz it at de fr nl se) ],
	   'Europe/Lisbon' =>     [ qw(pt es fr it cz at de se) ],
	   'Europe/London' =>     [ qw(uk fr be nl de at cz se it) ],
	   'Europe/Madrid' =>     [ qw(es fr pt it cz at de se) ],
	   'Europe/Moscow' =>     [ qw(ru de pl cz at se be fr it) ],
	   'Europe/Oslo' =>       [ qw(no se fi dk de be at cz it) ],
	   'Europe/Paris' =>      [ qw(fr be de at cz nl it se) ],
	   'Europe/Prague' =>     [ qw(cz it at de fr nl se) ],
	   'Europe/Rome' =>       [ qw(it fr cz de at nl se) ],
	   'Europe/Stockholm' =>  [ qw(se no dk fi nl de at cz fr it) ],
	   'Europe/Vienna' =>     [ qw(at de cz it fr nl se) ],
	  );
my %sites2countries = (
  'proxad.net' => 'fr',
  'planetmirror.com' => 'au',
  'averse.net' => 'sg',
);

#- get distrib release number (2006.0, etc)
sub etc_version() {
    (my $v) = split / /, cat_('/etc/version');
    return $v;
}

#- returns the keyword describing the type of the distribution.
#- the parameter indicates whether we want base or update sources
sub distro_type {
    my ($want_base_distro) = @_;
    return 'cooker' if $mandrake_release =~ /cooker/i;
    #- we can't use updates for community while official is not out (release ends in ".0")
    if ($want_base_distro || $mandrake_release =~ /community/i && etc_version() =~ /\.0$/) {
	return 'official' if $mandrake_release =~ /official|limited/i;
	return 'community' if $mandrake_release =~ /community/i;
	#- unknown: fallback to updates
    }
    return 'updates';
}

sub compat_arch_for_updates($) {
    # FIXME: We prefer 64-bit packages to update on biarch platforms,
    # since the system is populated with 64-bit packages anyway.
    my ($arch) = @_;
    return $arch =~ /x86_64|amd64/ if arch() eq 'x86_64';
    MDK::Common::System::compat_arch($arch);
}

sub mirrors {
    my ($cachedir, $want_base_distro) = @_;
    $cachedir ||= '/root';
    my $mirrorslist = "$cachedir/mirrorsfull.list";
    unlink $mirrorslist;
    urpm::cfg::mirrors_cfg();
    my $res = curl_download::download($urpm::cfg::mirrors, $cachedir, sub {});
    $res and do { c::set_tagged_utf8($res); die $res };
    require timezone;
    my $tz = ${timezone::read()}{timezone};
    my $distro_type = distro_type($want_base_distro);
    my @mirrors = map {
	my ($arch, $url) = m|\Q$distro_type\E([^:]*):(.+)|;
	if ($arch && compat_arch_for_updates($arch)) {
	    my ($land, $goodness);
	    foreach (keys %u2l) {
		if ($url =~ m|//[^/]+\.\Q$_\E/|) { $land = $_; last }
	    }
	    $url =~ m|\W\Q$_\E/| and $land = $sites2countries{$_} foreach keys %sites2countries;
	    each_index { $_ eq $land and $goodness ||= 100-$::i } (map { if_($tz =~ /^$_$/, @{$t2l{$_}}) } keys %t2l), @$us;
	    { url => $url, land => $u2l{$land} || N("United States"), goodness => $goodness + rand() };
	} else { () }
    } cat_($mirrorslist);
    unless (-x '/usr/bin/rsync') {
	@mirrors = grep { $_->{url} !~ /^rsync:/ } @mirrors;
    }
    unlink $mirrorslist;
    return sort { $b->{goodness} <=> $a->{goodness} } @mirrors;
}

sub choose_mirror {
    my (%options) = @_;
    my $message = $options{message} ? $options{message} :
$branded
? N("I need to access internet to get the mirror list.
Please check that your network is currently running.

Is it ok to continue?")
: N("I need to contact the Mandriva website to get the mirror list.
Please check that your network is currently running.

Is it ok to continue?");
    delete $options{message};
    interactive_msg(N("Mirror choice"), $message, yesno => 1, %options) or return '';
    my $wait = wait_msg(
	$branded
	? N("Please wait, downloading mirror addresses.")
	: N("Please wait, downloading mirror addresses from the Mandriva website.")
    );
    my @mirrors = eval { mirrors('/var/cache/urpmi', $options{want_base_distro}) };
    remove_wait_msg($wait);
    if ($@) {
	my $msg = $@;  #- seems that value is bitten before being printed by next func..
	interactive_msg(N("Error during download"),
($branded
? N("There was an error downloading the mirror list:

%s
The network, or the website, may be unavailable.
Please try again later.", $msg)
: N("There was an error downloading the mirror list:

%s
The network, or the Mandriva website, may be unavailable.
Please try again later.", $msg)), %options

	);
	return '';
    }

    !@mirrors and interactive_msg(N("No mirror"),
($branded
? N("I can't find any suitable mirror.")
: N("I can't find any suitable mirror.

There can be many reasons for this problem; the most frequent is
the case when the architecture of your processor is not supported
by Mandriva Linux Official Updates.")), %options
    ), return '';

    my $w = ugtk2->new('rpmdrake', grab => 1);
    $w->{rwindow}->set_position($options{transient} ? 'center_on_parent' : 'center_always');
    my $tree_model = Gtk2::TreeStore->new("Glib::String");
    my $tree = Gtk2::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
    $tree->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, text => 0));
    $tree->set_headers_visible(0);

    gtkadd(
	$w->{window}, 
	gtkpack_(
	    Gtk2::VBox->new(0,5),
	    0, N("Please choose the desired mirror."),
	    1, create_scrolled_window($tree),
	    0, gtkpack(
		create_hbox('edge'),
		map {
		    my $retv = $_->[1];
		    gtksignal_connect(
			Gtk2::Button->new(but($_->[0])),
			clicked => sub {
			    if ($retv) {
				my ($model, $iter) = $tree->get_selection->get_selected;
				$model and $w->{retval} = { sel => $model->get($iter, 0) };
			    }
			    Gtk2->main_quit;
			},
		    );
		} [ N("Cancel"), 0 ], [ N("Ok"), 1 ]
	    ),
	)
    );
    my %roots;
    $tree_model->append_set($roots{$_->{land}} ||= $tree_model->append_set(undef, [ 0 => $_->{land} ]),
			    [ 0 => $_->{url} ]) foreach @mirrors;

    $w->{window}->set_size_request(500, 400);
    $w->{rwindow}->show_all;

    my $path = Gtk2::TreePath->new_first;
    $tree->expand_row($path, 0);
    $path->down;
    $tree->get_selection->select_path($path);

    $w->main && member($w->{retval}{sel}, map { $_->{url} } @mirrors) ? $w->{retval}{sel} : '';
}

sub make_url_mirror {
    my ($mirror) = @_;
    if ($mirror =~ m!/(?:RPMS|media/main)/?\Z!) {
	"$mirror/";
    } else {
	my ($class, $release) = $mandrake_release =~ /(\S+)\s+release\s+(\S+)/;
	$class !~ /linux/i and $release = lc($class) . "/$release";  #- handle subdirectory for corporate/clustering/etc
	"$mirror/$release/main_updates/";
    }
}

sub make_url_mirror_dist {
    my ($mirror) = @_;
    $mirror =~ s!/(?:RPMS|media/main)/?\Z!/!;
    $mirror;
}

sub show_urpm_progress {
    my ($label, $pb, $mode, $file, $percent, $total, $eta, $speed) = @_;
    $file =~ s|([^:]*://[^/:\@]*:)[^/:\@]*(\@.*)|$1xxxx$2|; #- if needed...
    my $medium if 0;
    if ($mode eq 'copy') {
	$pb->set_fraction(0);
	$label->set_label(N("Copying file for medium `%s'...", $file));
    } elsif ($mode eq 'parse') {
	$pb->set_fraction(0);
	$label->set_label(N("Examining file of medium `%s'...", $file));
    } elsif ($mode eq 'retrieve') {
	$pb->set_fraction(0);
	$label->set_label(N("Examining remote file of medium `%s'...", $file));
        $medium = $file;
    } elsif ($mode eq 'done') {
	$pb->set_fraction(1.0);
	$label->set_label($label->get_label . N(" done."));
        $medium = undef;
    } elsif ($mode eq 'failed') {
	$pb->set_fraction(1.0);
	$label->set_label($label->get_label . N(" failed!"));
        $medium = undef;
    } else {
        length($file) > 60 and $file = $medium ? #-PO: We're downloading the said file from the said medium
                                                 N("%s from medium %s", basename($file), $medium)
                                               : basename($file);
        if ($mode eq 'start') {
            $pb->set_fraction(0);
            $label->set_label(N("Starting download of `%s'...", $file));
        } elsif ($mode eq 'progress') {
            if (defined $total && defined $eta) {
                $pb->set_fraction($percent/100);
                $label->set_label(N("Download of `%s', time to go:%s, speed:%s", $file, $eta, $speed));
            } else {
                $pb->set_fraction($percent/100);
                $label->set_label(N("Download of `%s', speed:%s", $file, $speed));
            }
        }
    }
    Gtk2->main_iteration while Gtk2->events_pending;
}

sub update_sources {
    my ($urpm, %options) = @_;
    my $cancel = 0;
    my $w; my $label; $w = wait_msg(
	$label = Gtk2::Label->new(N("Please wait, updating media...")),
	no_wait_cursor => 1,
	banner => $options{banner},
	widgets => [
	    my $pb = gtkset_size_request(Gtk2::ProgressBar->new, 300, -1),
	    gtkpack(
		create_hbox(),
		gtksignal_connect(
		    Gtk2::Button->new(N("Cancel")),
		    clicked => sub {
			$cancel = 1;
			$w->destroy;
		    },
		),
	    ),
	],
    );
    my @media; @media = @{$options{medialist}} if ref $options{medialist};
    my $outerfatal = $urpm->{fatal};
    local $urpm->{fatal} = sub { $w->destroy; $outerfatal->(@_) };
    $urpm->update_media(
	%options,
	callback => sub {
	    $cancel and goto cancel_update;
	    my ($type, $media) = @_;
	    return if $type !~ /^(?:start|progress|end)$/ && @media && !member($media, @media);
	    if ($type eq 'failed') {
		$urpm->{fatal}->(N("Error retrieving packages"),
N("It's impossible to retrieve the list of new packages from the media
`%s'. Either this update media is misconfigured, and in this case
you should use the Software Media Manager to remove it and re-add it in order
to reconfigure it, either it is currently unreachable and you should retry
later.",
    $media));
	    } else {
		show_urpm_progress($label, $pb, @_);
	    }
	},
    );
    $w->destroy;
  cancel_update:
}

sub update_sources_check {
    my ($urpm, $options, $error_msg, @media) = @_;
    my @error_msgs;
    local $urpm->{fatal} = sub { push @error_msgs, $_[1]; goto fatal_error };
    local $urpm->{error} = sub { push @error_msgs, $_[0] };
    update_sources($urpm, %$options, noclean => 1, medialist => \@media);
  fatal_error:
    if (@error_msgs) {
        interactive_msg('rpmdrake', sprintf(translate($error_msg), join("\n", @error_msgs)), scroll => 1);
        return 0;
    }
    return 1;
}

sub update_sources_interactive {
    my ($urpm, %options) = @_;
    my $w = ugtk2->new(N("Update media"), grab => 1, center => 1, %options);
    $w->{rwindow}->set_position($options{transient} ? 'center_on_parent' : 'center_always');
    my @buttons;
    my @media = grep { ! $_->{ignore} } @{$urpm->{media}};
    unless (@media) {
        interactive_msg('rpmdrake', N("No active medium found. You must enable some media to be able to update them."));
	return 0;
    }
    gtkadd(
	$w->{window},
	gtkpack__(
	    Gtk2::VBox->new(0,5),
	    Gtk2::Label->new(N("Select the media you wish to update:")),
	    (
		@buttons = map {
		    Gtk2::CheckButton->new_with_label($_->{name});
		} @media
	    ),
	    Gtk2::HSeparator->new,
	    gtkpack(
		create_hbox(),
		gtksignal_connect(
		    Gtk2::Button->new(N("Cancel")),
		    clicked => sub { $w->{retval} = 0; Gtk2->main_quit },
		),
		gtksignal_connect(
		    Gtk2::Button->new(N("Select all")),
		    clicked => sub { $_->set_active(1) foreach @buttons },
		),
		gtksignal_connect(
		    Gtk2::Button->new(N("Update")),
		    clicked => sub {
			$w->{retval} = any { $_->get_active } @buttons;
			# list of media listed in the checkbox panel
			my @buttonmedia = grep { !$_->{ignore} } @{$urpm->{media}};
			@media = map_index { if_($_->get_active, $buttonmedia[$::i]{name}) } @buttons;
			Gtk2->main_quit;
		    },
		),
	    )
	)
    );
    if ($w->main) {
	#- force ignored media to be returned alive (forked from urpmi.update...)
	foreach (@{$urpm->{media}}) {
	    $_->{modified} and delete $_->{ignore};
	}
        $urpm->select_media(@media);
        update_sources_check(
	    $urpm,
	    {},
	    N_("Unable to update medium; it will be automatically disabled.\n\nErrors:\n%s"),
	    @media,
	);
	return 1;
    }
    return 0;
}

sub add_medium_and_check {
    my ($urpm, $options) = splice @_, 0, 2;
    my @newnames = ($_[0]); #- names of added media
    my $fatal_msg;
    my @error_msgs;
    local $urpm->{fatal} = sub { printf STDERR "Fatal: %s\n", $_[1]; $fatal_msg = to_utf8($_[1]); goto fatal_error };
    local $urpm->{error} = sub { printf STDERR "Error: %s\n", $_[0]; push @error_msgs, to_utf8($_[0]) };
    if ($options->{distrib}) {
	@newnames = $urpm->add_distrib_media(@_);
    } else {
	$urpm->add_medium(@_);
    }
    if (@error_msgs) {
        interactive_msg(
	    'rpmdrake',
	    N("Unable to add medium, errors reported:\n\n%s",
	    join("\n", @error_msgs)),
	    scroll => 1,
	);
        return 0;
    }

    foreach my $name (@newnames) {
	urpm::download::set_proxy_config($_, $options->{proxy}{$_}, $name) foreach keys %{$options->{proxy} || {}};
    }

    if (update_sources_check($urpm, $options, N_("Unable to add medium, errors reported:\n\n%s"), @newnames)) {
        $urpm->write_config;
	$options->{proxy} and urpm::download::dump_proxy_config();
    } else {
	$urpm->read_config;
        return 0;
    }

    my %newnames; @newnames{@newnames} = ();
    if (any { exists $newnames{$_->{name}} } @{$urpm->{media}}) {
        return 1;
    } else {
        interactive_msg('rpmdrake', N("Unable to create medium."));
        return 0;
    }

  fatal_error:
    interactive_msg(N("Failure when adding medium"),
                    N("There was a problem adding medium:\n\n%s", $fatal_msg));
    return 0;
}

#- Check whether the default update media (added by installation)
#- matches the current mdk version
sub check_update_media_version {
    my $urpm = shift;
    foreach (@_) {
	if ($_->{name} =~ /(\d+\.\d+).*\bftp\du\b/ && $1 ne $mdk_version) {
	    interactive_msg(
		'rpmdrake',
		$branded
		? N("Your medium `%s', used for updates, does not match the version of %s you're running (%s).
It will be disabled.",
		    $_->{name}, $distrib{system}, $distrib{product})
		: N("Your medium `%s', used for updates, does not match the version of Mandriva Linux you're running (%s).
It will be disabled.",
		    $_->{name}, $mdk_version)
	    );
	    $_->{ignore} = 1;
	    $urpm->write_config() if -w $urpm->{config};
	    return 0;
	}
    }
    1;
}

sub open_help {
    my ($mode) = @_;
    use run_program;
    run_program::raw({ detach => 1 }, 'drakhelp', '--id', "software-management-$mode");
    interactive_msg(
	N("Help launched in background"),
	N("The help window has been started, it should appear shortly on your desktop."),
    );
}

sub strip_first_underscore { join '', map { s/_//; $_ } @_ }

1;
