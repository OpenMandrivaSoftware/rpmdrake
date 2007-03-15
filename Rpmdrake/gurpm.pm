package Rpmdrake::gurpm;
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
use mygtk2 qw(gtknew);  #- do not import anything else, especially gtkadd() which conflicts with ugtk2 one
use ugtk2 qw(:all);


our ($mainw, $label, $progressbar, $vbox, $cancel, $hbox_cancel);

my $previous_main_window;

sub init {
    my ($title, $initializing, %options) = @_;
    $mainw = ugtk2->new($title, %options, default_width => 600);
    $previous_main_window = $::main_window;
    $::main_window = $mainw->{real_window};
    $label = gtknew('Label', text => $initializing);
    $progressbar = gtknew('ProgressBar');
    gtkadd($mainw->{window}, $vbox = gtknew('VBox', spacing => 5, border_width => 6, children_tight => [ $label, $progressbar ]));
    $mainw->{rwindow}->set_position('center-on-parent');
    $mainw->sync;
}

sub label {
    $label->set($_[0]);
    select(undef, undef, undef, 0.1);  #- hackish :-(
    $mainw->flush;
}

sub progress {
    $progressbar->set_fraction($_[0]);
    $mainw->flush;
}

sub end() {
    $mainw and $mainw->destroy;
    $mainw = undef;
    $cancel = undef;  #- in case we'll do another one later
    $::main_window = $previous_main_window;
}

sub validate_cancel {
    my ($cancel_msg, $cancel_cb) = @_;
    if (!$cancel) {
        gtkpack__(
	    $vbox,
	    $hbox_cancel = gtkpack__(
		gtknew('HButtonBox'),
		$cancel = gtknew('Button', text => $cancel_msg, clicked => \&$cancel_cb),
	    ),
	);
    }
    $cancel->set_sensitive(1);
    $cancel->show;
}

sub invalidate_cancel() {
    $cancel and $cancel->set_sensitive(0);
}

sub invalidate_cancel_forever() {
    $hbox_cancel or return;
    $hbox_cancel->destroy;
    $mainw->shrink_topwindow;
}

1;
