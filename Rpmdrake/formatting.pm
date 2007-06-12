package Rpmdrake::formatting;
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

use strict;
use utf8;
use POSIX qw(strftime);
use rpmdrake;
use lib qw(/usr/lib/libDrakX);
use common;
use ugtk2 qw(escape_text_for_TextView_markup_format);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(format_field format_header localtime2changelog my_fullname pkg2medium rpm_description rpm_summary split_fullname urpm_name);


sub rpm_summary {
    my ($summary) = @_;
    utf8::decode($summary);
    $summary;
}

sub rpm_description {
    my ($description) = @_;
    utf8::decode($description);
    my ($t, $tmp);
    foreach (split "\n", $description) {
	s/^\s*//;
        if (/^$/ || /^\s*(-|\*|\+|o)\s/) {
            $t || $tmp and $t .= "$tmp\n";
            $tmp = $_;
        } else {
            $tmp = ($tmp ? "$tmp " : ($t && "\n") . $tmp) . $_;
        }
    }
    "$t$tmp\n";
}


sub split_fullname { $_[0] =~ /^(.*)-([^-]+-[^-]+)$/ }
sub my_fullname {
    return '?-?-?' unless ref $_[0];
    my ($name, $version, $release) = $_[0]->fullname;
    "$name-$version-$release";
}


sub urpm_name {
    return '?-?-?.?' unless ref $_[0];
    my ($name, $version, $release, $arch) = $_[0]->fullname;
    "$name-$version-$release.$arch";
}


sub pkg2medium {
    my ($p, $urpm) = @_;
    my $id = $p->id;
    return { name => N("None") } if !$id;
    foreach (@{$urpm->{media}}) {
        !$_->{ignore} && $id >= $_->{start} && $id <= $_->{end} and return $_;
    }
    undef;
}

#- strftime returns a string in the locale charset encoding;
#- but gtk2 requires UTF-8, so we use to_utf8() to ensure the
#- output of localtime2changelog() is always in UTF-8
#- as to_utf8() uses LC_CTYPE for locale encoding and strftime() uses LC_TIME,
#- it doesn't work if those two variables have values with different
#- encodings; but if a user has a so broken setup we can't do much anyway
sub localtime2changelog { to_utf8(POSIX::strftime("%c", localtime($_[0]))) }

sub format_header {
    my ($str) = @_;
    '<big>' . escape_text_for_TextView_markup_format($str) . '</big>';
}

sub format_field {
    my ($str) = @_;
    '<b>' . escape_text_for_TextView_markup_format($str) . '</b>';
}

1;
