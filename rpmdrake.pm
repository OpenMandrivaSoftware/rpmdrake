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

use lib qw(/usr/lib/libDrakX);
use standalone;     #- warning, standalone must be loaded very first, for 'explanations'

use MDK::Common;
use urpm;
use URPM;
use URPM::Resolve;
use packdrake;
use strict;
use vars qw($configfile %config $mandrakeupdate_wanted_categories $already_splashed $max_info_in_descr $typical_width);
use log;
use c;

use curl_download;

eval { require ugtk2; ugtk2->import(qw(:all)) };
if ($@) {
    print "This program cannot be run in console mode.\n";
    c::_exit(0);  #- skip ugtk2::END
}
ugtk2::add_icon_path('/usr/share/rpmdrake/icons');

sub translate {
    my ($s) = @_;
    $s ? c::dgettext('rpmdrake', $s) : '';
}
sub sprintf_fixutf8 {
    my $need_upgrade;
    $need_upgrade |= to_bool(c::is_tagged_utf8($_)) + 1 foreach @_;
    if ($need_upgrade == 3) { c::upgrade_utf8($_) foreach @_ };
    sprintf shift, @_;
}
sub N {
    my $s = shift @_; my $t = translate($s);
    sprintf_fixutf8 $t, @_;
}
sub myexit { ugtk2::exit(undef, @_) }

$ENV{HOME} ||= '/root';

sub readconf {
    $configfile = "$ENV{HOME}/.rpmdrake";
    %config = (mandrakeupdate_wanted_categories => { var => \$mandrakeupdate_wanted_categories, default => [ qw(security) ] },
	       already_splashed => { var => \$already_splashed, default => [] },
	       max_info_in_descr => { var => \$max_info_in_descr, default => [] },
	      );
    ${$config{$_}{var}} = $config{$_}{default} foreach keys %config;
    
    foreach my $l (cat_($configfile)) {
	$l =~ /^\Q$_\E (.*)/ and ${$config{$_}{var}} = [ split ' ', $1 ] foreach keys %config;
    }
}

sub writeconf {
    output $configfile, map { "$_ " . join(' ', @${$config{$_}{var}}) . "\n" } keys %config;
}

sub interactive_msg {
    my ($title, $contents, %options) = @_;
    my $d = ugtk2->new($title, grab => 1, if_(exists $options{transient}, transient => $options{transient}));
    gtkadd($d->{window},
	   gtkpack_(Gtk2::VBox->new(0,5),
		    1, $options{scroll} ? gtkadd(gtkset_shadow_type(Gtk2::Frame->new, 'in'),
						 gtkset_size_request(create_scrolled_window(gtktext_insert(Gtk2::TextView->new, $contents)),
								     $typical_width*2, 300))
					: Gtk2::Label->new($contents),
		    0, gtkpack(create_hbox(),
			       ref($options{yesno}) eq 'ARRAY' ? map {
				   my $label = $_;
				   gtksignal_connect(Gtk2::Button->new($label), clicked => sub { $d->{retval} = $label; Gtk2->main_quit })
			       } @{$options{yesno}}
			       : $options{yesno} ? (gtksignal_connect(Gtk2::Button->new($options{text}{yes} || N("Yes")),
								      clicked => sub { $d->{retval} = 1; Gtk2->main_quit }),
						    gtksignal_connect(Gtk2::Button->new($options{text}{no} || N("No")),
								      clicked => sub { $d->{retval} = 0; Gtk2->main_quit }))
			       : gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub { Gtk2->main_quit })
			      )));
    $d->main;
}

sub interactive_packtable {
    my ($title, $parent_window, $top_label, $lines, $action_buttons) = @_;
    
    my $w = ugtk2->new($title, grab => 1, transient => $parent_window);
    my $packtable = create_packtable({}, @$lines);

    gtkadd($w->{window},
	   gtkpack_(Gtk2::VBox->new(0, 5),
		    if_($top_label, 0, Gtk2::Label->new($top_label)),
		    1, create_scrolled_window($packtable),
		    0, gtkpack__(create_hbox(), @$action_buttons)));
    my ($xpreq, $ypreq) = $packtable->size_request->values;
    my ($xwreq, $ywreq) = $w->{rwindow}->size_request->values;
    $w->{rwindow}->set_default_size(max($typical_width, min($typical_width*2.5, $xpreq+$xwreq)),
 				    max(200, min(450, $ypreq+$ywreq)));
    $w->main;
}

sub interactive_list {
    my ($title, $contents, $list, $callback, %options) = @_;
    my $d = ugtk2->new($title, grab => 1, if_(exists $options{transient}, transient => $options{transient}));
    my @radios = gtkradio('', @$list);
    my $vbradios = $callback ? create_packtable({},
						mapn { my $n = $_[1];
						       [ $_[0],
							 gtksignal_connect(Gtk2::Button->new(but(N("Info..."))),
									   clicked => sub { $callback->($n) }) ]
						   } \@radios, $list)
                             : gtkpack__(Gtk2::VBox->new(0, 0), @radios);
    my $choice;
    gtkadd($d->{window},
	   gtkpack__(Gtk2::VBox->new(0,5),
		     Gtk2::Label->new($contents),
		     int(@$list) > 8 ? gtkset_size_request(create_scrolled_window($vbradios), 250, 320) : $vbradios,
		     gtkpack__(create_hbox(), gtksignal_connect(Gtk2::Button->new(N("Ok")), clicked => sub {
								    each_index { $_->get_active and $choice = $::i } @radios;
								    Gtk2->main_quit
								}))));
    $d->main;
    $choice;
}

sub fatal_msg {
    interactive_msg @_;
    myexit -1;
}

sub wait_msg {
    my ($msg, %options) = @_;
    my $mainw = ugtk2->new('rpmdrake', grab => 1, if_(exists $options{transient}, transient => $options{transient}));
    my $label = Gtk2::Label->new($msg);
    gtkadd($mainw->{window}, gtkpack(gtkadd(create_vbox(), $label)));
    $label->signal_connect(expose_event => sub { $mainw->{displayed} = 1 });
    $mainw->sync until $mainw->{displayed};
    gtkset_mousecursor_wait($mainw->{rwindow}->window);
    $mainw->flush;
    $mainw;
}
sub remove_wait_msg { $_[0]->destroy }

sub but { "    $_[0]    " }

sub slow_func($&) {
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


my %u2l = (
	   at => N("Austria"),
	   au => N("Australia"),
	   be => N("Belgium"),
	   br => N("Brazil"),
	   ca => N("Canada"),
	   cr => N("Costa Rica"),
	   cz => N("Czech Republic"),
	   de => N("Germany"),
	   dk => N("Danmark"),
	   el => N("Greece"),
	   es => N("Spain"),
	   fi => N("Finland"),
	   fr => N("France"),
	   gr => N("Greece"),
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
	   tw => N("Taiwan"),
	   uk => N("United Kingdom"),
	   zh => N("China"),
	   com => N("United States"),
	   org => N("United States"),
	   net => N("United States"),
	   edu => N("United States"),
	  );
my $us = [ qw(com org net edu) ];
my %t2l = (
	   'America/\w+' =>       $us,
	   'Asia/Tel_Aviv' =>     [ qw(il ru cz at) ],
	   'Asia/Tokyo' =>        [ qw(jp ko tw), @$us ],
	   'Asia/Seoul' =>        [ qw(ko jp tw), @$us ],
	   'Asia/(Taipei|Beijing)' => [ qw(zn jp), @$us ],
	   'Atlantic/Reykjavik' => [ qw(uk no se dk) ],
	   'Australia/\w+' =>     [ qw(au jp ko tw), @$us ],
	   'Brazil/\w+' =>       [ 'br', @$us ],
	   'Canada/\w+' =>        [ 'ca', @$us ],
	   'Europe/Amsterdam' =>  [ qw(nl be de at) ],
	   'Europe/Athens' =>     [ qw(gr pl de nl at) ],
	   'Europe/Berlin' =>     [ qw(de be at nl fr) ],
	   'Europe/Brussels' =>   [ qw(be de nl fr at) ],
	   'Europe/Budapest' =>   [ qw(it cz at de at) ],
	   'Europe/Copenhagen' => [ qw(dk nl de be at) ],
	   'Europe/Dublin' =>     [ qw(uk fr be nl) ],
	   'Europe/Helsinki' =>   [ qw(fi se no nl at) ],
	   'Europe/Istanbul' =>   [ qw(il ru cz at) ],
	   'Europe/Lisbon' =>     [ qw(pt es fr it) ],
	   'Europe/London' =>     [ qw(uk fr be nl at) ],
	   'Europe/Madrid' =>     [ qw(es fr pt it) ],
	   'Europe/Moscow' =>     [ qw(ru de pl at) ],
	   'Europe/Oslo' =>       [ qw(no se fi dk at) ],
	   'Europe/Paris' =>      [ qw(fr be de at) ],
	   'Europe/Prague' =>     [ qw(cz be de at) ],
	   'Europe/Rome' =>       [ qw(it fr de at) ],
	   'Europe/Stockholm' =>  [ qw(se no dk fi at) ],
	   'Europe/Vienna' =>     [ qw(at de cz it) ],
	  );
my %sites2countries = ('proxad.net' => 'fr',
		       'planetmirror.com' => 'au');

sub mirrors {
    my ($cachedir, $class) = @_;
    $cachedir = '/tmp';
    my $mirrorslist = "$cachedir/mirrorsfull.list";
    unlink $mirrorslist;
    my $res = curl_download::download('http://www.linux-mandrake.com/mirrorsfull.list', $cachedir, sub {});
    $res and die $res;
    require timezone;
    my $tz = ${timezone::read()}{timezone};
    my @mirrors = map { my ($arch, $url) = m|\Q$class\E([^:]*):(.+)|;
			if ($arch && MDK::Common::System::compat_arch($arch)) {
	                    my ($land, $goodness);
			    $url =~ m|\.\Q$_\E/| and $land = $_ foreach keys %u2l;
			    $url =~ m|\W\Q$_\E/| and $land = $sites2countries{$_} foreach keys %sites2countries;
			    each_index { $_ eq $land and $goodness ||= 100-$::i } (map { if_($tz =~ /^$_$/, @{$t2l{$_}}) } keys %t2l), @$us;
			    { url => $url, land => $u2l{$land} || N("United States"), goodness => $goodness + rand };
			} else { () }
		    } cat_($mirrorslist);
    unlink $mirrorslist;
    return sort { $::b->{goodness} <=> $::a->{goodness} } @mirrors;
}

sub choose_mirror {
    interactive_msg('', 
N("I need to contact MandrakeSoft website to get the mirrors list.
Please check that your network is currently running.

Is it ok to continue?"), yesno => 1) or return '';
    my $wait = wait_msg(N("Please wait, downloading mirrors addresses from MandrakeSoft website."));
    my @mirrors;
    eval { @mirrors = mirrors('/var/cache/urpmi', 'updates') };
    remove_wait_msg($wait);
    if ($@) {
	my $msg = $@;  #- seems that value is bitten before being printed by next func..
	interactive_msg(N("Error during download"),
N("There was an error downloading the mirrors list:

%s
The network, or MandrakeSoft website, are maybe unavailable.
Please try again later.", $msg));
	return '';
    }

    !@mirrors and interactive_msg(N("No mirror"),
N("I can't find any suitable mirror.

There can be many reasons for this problem; the most frequent is
the case when the architecture of your processor is not supported
by Mandrake Linux Official Updates.")), return '';

    my $w = ugtk2->new('rpmdrake', grab => 1);
    my $tree_model = Gtk2::TreeStore->new(Gtk2::GType->STRING);
    my $tree = Gtk2::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
#    $tree->set_row_height($tree->style->font->ascent + $tree->style->font->descent + 1); FIXME is that still needed?
    my $column = Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0);
    $tree->append_column($column);
    $tree->set_headers_visible(0);

    gtkadd($w->{window}, 
	   gtkpack_(Gtk2::VBox->new(0,5),
		    0, N("Please choose the desired mirror."),
		    1, create_scrolled_window($tree),
		    0, gtkpack(Gtk2::HBox->new(1, 20),
			       map {
				   my $retv = $_->[1];
				   gtksignal_connect(Gtk2::Button->new(but($_->[0])), clicked => sub {
						 if ($retv) {
						     my ($model, $iter) = $tree->get_selection->get_selected;
						     $model and $w->{retval} = { sel => $model->get($iter, 0) };
						     $iter and $iter->free;
						 }
						 Gtk2->main_quit })
			       } ([ N("Ok"), 1], [ N("Cancel"), 0 ])),
		   ));
    my %roots;
    $tree_model->append_set($roots{$_->{land}} ||= $tree_model->append_set(undef, [ 0 => $_->{land} ]),
			    [ 0 => $_->{url} ])->free foreach @mirrors;

    $w->{window}->set_size_request(400, 300);
    $w->{rwindow}->show_all;

    my $path = Gtk2::TreePath->new_first;
    $tree->expand_row($path, 0);
    $path->down;
    $tree->get_selection->select_path($path);
    $path->free;

    $w->main && member($w->{retval}{sel}, map { $_->{url} } @mirrors) and $w->{retval}{sel};
}

sub update_sources {
    my ($urpm, %opts) = @_;
    my $w = ugtk2->new(N("Update source(s)"), grab => 1, center => 1, %opts);
    my (@buttons, @sources_to_update);
    gtkadd($w->{window},
	   gtkpack__(Gtk2::VBox->new(0,5),
		     Gtk2::Label->new(N("Select the source(s) you wish to update:")),
		     (@buttons = map { Gtk2::CheckButton->new($_->{name}) } @{$urpm->{media}}),
		     Gtk2::HSeparator->new,
		     gtkpack(create_hbox(),
			     gtksignal_connect(Gtk2::Button->new(N("Update")), clicked => sub {
						   $w->{retval} = 1;
						   @sources_to_update = grep { $_->get_active } @buttons;
						   Gtk2->main_quit;
					       }),
			     gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { $w->{retval} = 0; Gtk2->main_quit }))));
    if ($w->main && @sources_to_update) {
	each_index { $urpm->select_media($urpm->{media}[$::i]{name}) } @sources_to_update;
	foreach (@{$urpm->{media}}) {  #- force ignored media to be returned alive (forked from urpmi.updatemedia...)
	    $_->{modified} and delete $_->{ignore};
	}
	slow_func(N("Please wait, updating media..."),
		  sub { $urpm->update_media(noclean => 1) });
	return 1;
    }
    return 0;
}
