package Rpmdrake::rpmnew;
#*****************************************************************************
#
#  Copyright (c) 2002 Guillaume Cottenceau
#  Copyright (c) 2002-2007 Thierry Vignaud <tvignaud@mandriva.com>
#  Copyright (c) 2003, 2004, 2005 MandrakeSoft SA
#  Copyright (c) 2005-2007 Mandriva SA
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
use mygtk2 qw(gtknew);  #- do not import anything else, especially gtkadd() which conflicts with ugtk2 one
use ugtk2 qw(:all);
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(dialog_rpmnew);

# /var/lib/nfs/etab /var/lib/nfs/rmtab /var/lib/nfs/xtab /var/cache/man/whatis
my %ignores_rpmnew = map { $_ => 1 } qw(
    /etc/adjtime
    /etc/group
    /etc/ld.so.conf
    /etc/localtime
    /etc/modules
    /etc/passwd
    /etc/security/fileshare.conf
    /etc/shells
    /etc/sudoers
    /etc/sysconfig/alsa
    /etc/sysconfig/autofsck
    /etc/sysconfig/harddisks
    /etc/sysconfig/harddrake2/previous_hw
    /etc/sysconfig/init
    /etc/sysconfig/installkernel
    /etc/sysconfig/msec
    /etc/sysconfig/nfs
    /etc/sysconfig/pcmcia
    /etc/sysconfig/rawdevices
    /etc/sysconfig/saslauthd
    /etc/sysconfig/syslog
    /etc/sysconfig/usb
    /etc/sysconfig/xinetd
);

sub dialog_rpmnew {
    my ($msg, %p2r) = @_;
    @{$p2r{$_}} = grep { !$ignores_rpmnew{$_} } @{$p2r{$_}} foreach keys %p2r;
    my $sum_rpmnew = sum(map { int @{$p2r{$_}} } keys %p2r);
    $sum_rpmnew == 0 and return 1;
    my @inspect_wsize = ($typical_width*2.5, 500);
    my $inspect = sub {
	my ($file) = @_;
	my ($rpmnew, $rpmsave) = ("$file.rpmnew", "$file.rpmsave");
	my $rpmfile = 'rpmnew';
	-r $rpmnew or $rpmfile = 'rpmsave';
	-r $rpmnew && -r $rpmsave && (stat $rpmsave)[9] > (stat $rpmnew)[9] and $rpmfile = 'rpmsave';
	$rpmfile eq 'rpmsave' and $rpmnew = $rpmsave;
	my @diff = `/usr/bin/diff -u '$file' '$rpmnew'`;
	@diff = N("(none)") if !@diff;
	my $d = ugtk2->new(N("Inspecting %s", $file), grab => 1, transient => $::main_window);
	my $save_wsize = sub { @inspect_wsize = $d->{rwindow}->get_size };
	my %texts;
	gtkadd(
	    $d->{window},
	    gtkpack_(
		gtknew('VBox', spacing => 5),
		1, create_vpaned(
		    create_vpaned(
			gtkpack_(
			    gtknew('VBox'),
			    0, gtknew('Label', text_markup => qq(<span font_desc="monospace">$file:</span>)),
			    1, gtknew('ScrolledWindow', child => $texts{file} = gtknew('TextView')),
			),
			gtkpack_(
			    gtknew('VBox'),
			    0, gtknew('Label', text_markup => qq(<span font_desc="monospace">$rpmnew:</span>)),
			    1, gtknew('ScrolledWindow', child => $texts{rpmnew} = gtknew('TextView')),
			),
			resize1 => 1,
		    ),
		    gtkpack_(
			gtknew('VBox'),
			0, gtknew('Label', text => N("changes:")),
			1, gtknew('ScrolledWindow', child => $texts{diff} = gtknew('TextView')),
		    ),
		    resize1 => 1,
		),
		0, gtkpack__(
		    gtknew('HButtonBox'),
		    gtksignal_connect(
			gtknew('Button', text => N("Remove .%s", $rpmfile)),
			clicked => sub { $save_wsize->(); unlink $rpmnew; Gtk2->main_quit },
		    ),
		    gtksignal_connect(
			gtknew('Button', text => N("Use .%s as main file", $rpmfile)),
			clicked => sub { $save_wsize->(); renamef($rpmnew, $file); Gtk2->main_quit },
		    ),
		    gtksignal_connect(
			gtknew('Button', text => N("Do nothing")),
			clicked => sub { $save_wsize->(); Gtk2->main_quit },
		    ),
		)
	    )
	);
	my %contents = (file => scalar(cat_($file)), rpmnew => scalar(cat_($rpmnew)));
	gtktext_insert($texts{$_}, [ [ $contents{$_}, { 'font' => 'monospace' } ] ]) foreach keys %contents;
	my @regexps = ([ '^(--- )|(\+\+\+ )', 'blue' ], [ '^@@ ', 'darkcyan' ], [ '^-', 'red3' ], [ '^\+', 'green3' ]);
	my $line2col = sub { $_[0] =~ /$_->[0]/ and return $_->[1] foreach @regexps; 'black' };
	gtktext_insert($texts{diff}, [ map { [ $_, { 'font' => 'monospace', 'foreground' => $line2col->($_) } ] } @diff ]);
	$d->{rwindow}->set_default_size(@inspect_wsize);
	$d->main;
    };

    interactive_packtable(
	N("Installation finished"),
	$::main_window,
	$msg,
	[ map { my $pkg = $_;
	    map {
		my $f = $_;
		my $b;
		[ gtkpack__(
		    gtknew('HBox'),
		    gtkset_markup(
			gtkset_selectable(gtknew('Label'), 1),
			qq($pkg:<span font_desc="monospace">$f</span>),
		    )
		),
		gtksignal_connect(
		    $b = gtknew('Button', text => N("Inspect...")),
		    clicked => sub {
			$inspect->($f);
			-r "$f.rpmnew" || -r "$f.rpmsave" or $b->set_sensitive(0);
		    },
		) ];
	    } @{$p2r{$pkg}};
	} keys %p2r ],
	[ gtknew('Button', text => N("Ok"), 
	    clicked => sub { Gtk2->main_quit }) ]
    );
    return 0;
}

1;
