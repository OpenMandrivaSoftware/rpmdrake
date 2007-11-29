package Rpmdrake::open_db;
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
use common;
use rpmdrake;
use URPM;
use urpm;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(fast_open_urpmi_db open_rpm_db open_urpmi_db);


# because rpm blocks some signals when rpm DB is opened, we don't keep open around:
sub open_rpm_db {
    my ($o_force) = @_;
    my $host;
    log::explanations("opening the RPM database");
    if ($::rpmdrake_options{parallel} && ((undef, $host) = @{$::rpmdrake_options{parallel}})) {
        my $done if 0;
        my $dblocation = "/var/cache/urpmi/distantdb/$host";
        if (!$done || $o_force) {
            print "syncing db from $host to $dblocation...";
            mkdir_p "$dblocation/var/lib/rpm";
            system "rsync -Sauz -e ssh $host:/var/lib/rpm/ $dblocation/var/lib/rpm";
            $? == 0 or die "Couldn't sync db from $host to $dblocation";
            $done = 1;
            print "done.\n";
        }
        URPM::DB::open($dblocation) or die "Couldn't open RPM DB";
    } else {
        URPM::DB::open($::rpmdrake_options{'rpm-root'}[0]) or die "Couldn't open RPM DB ($::rpmdrake_options{'rpm-root'}[0])";
    }
}

# do not pay the urpm::media::configure() heavy cost:
sub fast_open_urpmi_db() {
    my $urpm = urpm->new;
    my $error_happened;
    $urpm->{options}{wait_lock} = $::rpmdrake_options{'wait-lock'};
    $urpm->{options}{'verify-rpm'} = !$::rpmdrake_options{'no-verify-rpm'} if defined $::rpmdrake_options{'no-verify-rpm'};
    $urpm->{options}{auto} = $::rpmdrake_options{auto} if defined $::rpmdrake_options{auto};
    urpm::set_files($urpm, $::rpmdrake_options{'urpmi-root'}[0]) if $::rpmdrake_options{'urpmi-root'}[0];
    urpm::args::set_root($urpm, $::rpmdrake_options{'rpm-root'}[0]) if $::rpmdrake_options{'rpm-root'}[0];

    $urpm::args::rpmdrake_options{justdb} = $::rpmdrake_options{justdb};

    $urpm->{fatal} = sub {
        $error_happened = 1;
        interactive_msg(N("Fatal error"),
                         N("A fatal error occurred: %s.", $_[1]));
    };

    urpm::media::read_config($urpm);
    # FIXME: seems uneeded with newer urpmi:
    if ($error_happened) {
        touch('/etc/urpmi/urpmi.cfg');
        exec('edit-urpm-sources.pl');
    }
    $urpm;
}

sub open_urpmi_db() {
    my $urpm = fast_open_urpmi_db();
    my $media = ref $::rpmdrake_options{media} ? join(',', @{$::rpmdrake_options{media}}) : '';

    my $searchmedia = join(',', map { $_->{name} } grep { $_->{ignore} && $_->{name} =~ /backport/i } @{$urpm->{media}});
    $urpm->{lock} = urpm::lock::urpmi_db($urpm, undef, wait => $urpm->{options}{wait_lock});
    urpm::media::configure($urpm, media => $media, if_($searchmedia, searchmedia => $searchmedia));
    $urpm;
}

1;
