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

use standalone;     #- warning, standalone must be loaded very first, for 'explanations'

use MDK::Common;
use urpm;
use URPM;
use URPM::Resolve;
use packdrake;
use vars qw($configfile %config $mandrakeupdate_wanted_categories $already_splashed);
use my_gtk qw(:helpers :wrappers :ask);
my_gtk::add_icon_path('/usr/share/rpmdrake/icons');
use log;

use curl_download;

sub translate {
    my ($s) = @_;
    $s ? c::dgettext('rpmdrake', $s) : '';
}
sub _ {
    my $s = shift @_; my $t = translate($s);
    sprintf $t, @_;
}
sub myexit { my_gtk::exit @_ }
  
$ENV{HOME} ||= '/root';

sub readconf {
    $configfile = "$ENV{HOME}/.rpmdrake";
    %config = ( mandrakeupdate_wanted_categories => { var => \$mandrakeupdate_wanted_categories, default => [ qw(security) ] },
		already_splashed => { var => \$already_splashed, default => [] },
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
    my ($title, $contents, $options) = @_;
    my $d = my_gtk->new($title);
    gtkadd($d->{window},
	   gtkpack_(new Gtk::VBox(0,5),
		    1, new Gtk::Label($contents),
		    0, gtkpack(create_hbox(),
			       $options->{yesno} ? (gtksignal_connect(new Gtk::Button($options->{text}{yes} || _("Yes")),
								      clicked => sub { $d->{retval} = 1; Gtk->main_quit }),
						    gtksignal_connect(new Gtk::Button($options->{text}{no} || _("No")),
								      clicked => sub { $d->{retval} = 0; Gtk->main_quit }))
			       : gtksignal_connect(new Gtk::Button(_("Ok")), clicked => sub { Gtk->main_quit })
			      )));
    $d->main;
}

sub interactive_list {
    my ($title, $contents, @list) = @_;
    my $d = my_gtk->new($title);
    my $vbradios = gtkpack__(new Gtk::VBox(0, 0), my @radios = gtkradio('', @list));
    gtkadd($d->{window},
	   gtkpack__(new Gtk::VBox(0,5),
		     new Gtk::Label($contents),
		     int(@list) > 8 ? gtkset_usize(createScrolledWindow($vbradios), 250, 320) : $vbradios,
		     gtkpack__(create_hbox(), gtksignal_connect(new Gtk::Button(_("Ok")), clicked => sub { Gtk->main_quit }))));
    $d->main;
    my $tmp;
    each_index { $_->get_active and $tmp = $::i } @radios;
    $tmp;
}

sub fatal_msg {
    interactive_msg @_;
    myexit -1;
}

sub wait_msg {
    my $mainw = my_gtk->new('rpmdrake');
    my $label = new Gtk::Label($_[0]);
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
	my_gtk::flush;
	&$func;
	gtkset_mousecursor_normal($param);
    } else {
	my $w = wait_msg($param);
	&$func;
	remove_wait_msg($w);
    }
}


my %u2l = (
	   at => _("Austria"),
	   be => _("Belgium"),
	   br => _("Brazil"),
	   ca => _("Canada"),
	   cr => _("Costa Rica"),
	   cz => _("Czech Republic"),
	   de => _("Germany"),
	   dk => _("Danmark"),
	   el => _("Greece"),
	   es => _("Spain"),
	   fi => _("Finland"),
	   fr => _("France"),
	   gr => _("Greece"),
	   il => _("Israel"),
	   it => _("Italy"),
	   jp => _("Japan"),
	   ko => _("Korea"),
	   nl => _("Netherlands"),
	   no => _("Norway"),
	   pl => _("Poland"),
	   pt => _("Portugal"),
	   ru => _("Russia"),
	   se => _("Sweden"),
	   tw => _("Taiwan"),
	   uk => _("United Kingdom"),
	   zh => _("China"),
	   com => _("United States"),
	   org => _("United States"),
	   net => _("United States"),
	   edu => _("United States"),
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
	   'Brazil/East' =>       [ 'br', @$us ],
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
my %sites2countries = ('proxad.net' => 'fr');

sub mirrors {
    my ($cachedir, $class) = @_;
    my $mirrorslist = "$cachedir/mirrorsfull.list";
    unlink $mirrorslist;
    my $proxy;
    /http_proxy = (http:[^:]+:\d+)/ and $proxy = $1 foreach cat_("$ENV{HOME}/.wgetrc");
    my $res = curl_download::download('http://www.linux-mandrake.com/mirrorsfull.list', $cachedir, $proxy, sub {});
    $res and die $res;
    require timezone;
    my $tz = ${timezone::read()}{timezone};
    my @mirrors = map { my ($land, $goodness);
			my ($arch, $url) = m|\Q$class\E([^:]*):(.+)|;
			$url =~ m|\.\Q$_\E/| and $land = $_ foreach keys %u2l;
			$url =~ m|\W\Q$_\E/| and $land = $sites2countries{$_} foreach keys %sites2countries;
			each_index { $_ eq $land and $goodness ||= 100-$::i } (map { if_($tz =~ /^$_$/, @{$t2l{$_}}) } keys %t2l), @$us;
			if_($arch && MDK::Common::System::compat_arch($arch),
			    { url => $url, land => $u2l{$land} || _("United States"), goodness => $goodness + rand })
		    } cat_($mirrorslist);
    unlink $mirrorslist;
    return sort { $::b->{goodness} <=> $::a->{goodness} } @mirrors;
}

sub choose_mirror {
    interactive_msg('', 
_("I need to contact MandrakeSoft website to get the mirrors list.
Please check that your network is currently running.

Is it ok to continue?"), { yesno => 1 }) or return '';
    my $wait = wait_msg(_("Please wait, downloading mirrors addresses from MandrakeSoft website."));
    my @mirrors;
    eval { @mirrors = mirrors('/var/cache/urpmi', 'updates') };
    remove_wait_msg($wait);
    if ($@) {
	my $msg = $@;  #- seems that value is bitten before being printed by next func..
	interactive_msg(_("Error during download"),
_("There was an error downloading the mirrors list:

%s
The network, or MandrakeSoft website, are maybe unavailable.
Please try again later.", $msg));
	return '';
    }

    !@mirrors and interactive_msg(_("No mirror"),
_("I can't find any suitable mirror.

There can be many reasons for this problem; the most frequent is
the case when the architecture of your processor is not supported
by Mandrake Linux Official Updates.")), return '';

    my $w = my_gtk->new('rpmdrake');
    my $tree = Gtk::CTree->new(1, 0);
    $tree->set_selection_mode('browse');
    $tree->set_column_auto_resize(0, 1);
    $tree->set_row_height($tree->style->font->ascent + $tree->style->font->descent + 1);

    gtkadd($w->{window}, 
	   gtkpack_(new Gtk::VBox(0,5),
		    0, _("Please choose the desired mirror."),
		    1, createScrolledWindow($tree),
		    0, gtkpack(new Gtk::HBox(1, 20),
			       map {
				   my $retv = $_->[1];
				   gtksignal_connect(new Gtk::Button(but($_->[0])), "clicked" => sub {
						 $retv and $w->{retval} = { sel => ($tree->node_get_pixtext($tree->selection, 0))[0] };
						 Gtk->main_quit })
			       } ([ _("Ok"), 1], [ _("Cancel"), 0 ])),
		   ));
    $tree->freeze;
    my %roots;
    $tree->insert_node($roots{$_->{land}} ||= $tree->insert_node(undef, undef, [ $_->{land}, '', '' ], 5, (undef) x 4, 0, 0),
		       undef, [ $_->{url}, '', '' ], 5, (undef) x 4, 1, 0) foreach @mirrors;
    $tree->expand($tree->node_nth(0));
    $tree->select($tree->node_nth(1));
    $tree->thaw;
    $w->{window}->set_usize(400, 300);
    $w->{rwindow}->show_all;
    $w->main && member($w->{retval}{sel}, map { $_->{url} } @mirrors) and $w->{retval}{sel};
}
