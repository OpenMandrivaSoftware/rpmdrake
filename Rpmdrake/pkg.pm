package Rpmdrake::pkg;
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
use MDK::Common::Func 'any';
use lib qw(/usr/lib/libDrakX);
use common;
use POSIX qw(_exit);
use URPM;
use utf8;
use Rpmdrake::gurpm;
use Rpmdrake::formatting;
use Rpmdrake::rpmnew;

use rpmdrake;
use urpm;
use urpm::lock;
use urpm::install;
use urpm::signature;
use urpm::get_pkgs;
use urpm::select;
use urpm::main_loop;
use urpm::args qw();


use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(extract_header find_installed_version formatlistpkg get_pkgs open_rpm_db parse_compssUsers_flat perform_installation perform_removal run_rpm);

use mygtk2 qw(gtknew);
use ugtk2 qw(:all);
use Gtk2::Pango;
use Gtk2::Gdk::Keysyms;


sub parse_compssUsers_flat() {
    my (%compssUsers, $category);
    my $compss = '/var/lib/urpmi/compssUsers.flat';
    -r $compss or $compss = '/usr/share/rpmdrake/compssUsers.flat.default';
    -r $compss or do {
	print STDERR "No compssUsers.flat file found\n";
	return undef;
    };
    foreach (cat_($compss)) {
	s/#.*//;
	/^\s*$/ and next;
	if (/^\S/) {
	    if (/^(.+?) \[icon=.+?\] \[path=(.+?)\]/) {
		$category = translate($2) . '|' . translate($1);
	    } else {
		print STDERR "Malformed category in compssUsers.flat: <$_>\n";
	    }
	} elsif (/^\t(\d) (\S+)\s*$/) {
	    $category or print STDERR "Entry without category <$_>\n";
	    push @{$compssUsers{$2}}, $category . ($1 <= 3 ? '|' . N("Other") : '');
	}
    }
    \%compssUsers;
}

sub run_rpm {
    foreach (qw(LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION LC_ALL)) {
        local $ENV{$_} = $ENV{$_} . '.UTF-8' if !/UTF-8/;
    }
    my @l = `@_`;
    wantarray() ? @l : join('', @l);
}


sub extract_header {
    my ($pkg, $urpm) = @_;
    my $chg_prepro = sub {
	#- preprocess changelog for faster TextView insert reaction
	[ map { [ "$_\n", if_(/^\*/, { 'weight' => Gtk2::Pango->PANGO_WEIGHT_BOLD }) ] } split("\n", $_[0]) ];
    };
    my $name = urpm_name($pkg->{pkg});
    if ($pkg->{pkg}->flag_installed && !$pkg->{pkg}->flag_upgrade) {
	add2hash($pkg, { files => [ split /\n/, chomp_(scalar(run_rpm("rpm -ql $name"))) || N("(none)") ],
                         changelog => $chg_prepro->(to_utf8(scalar(run_rpm("rpm -q --changelog $name")))) });
    } else {
	my ($p, $medium) = ($pkg->{pkg}, pkg2medium($pkg->{pkg}, $urpm));
	my $hdlist = urpm::media::any_hdlist($urpm, $medium);
	if (-r $hdlist) {
	    my $packer;
         require MDV::Packdrakeng; 
         eval { $packer = MDV::Packdrakeng->open(archive => $hdlist, quiet => 1) } or do {
		    warn "Warning, hdlist $hdlist seems corrupted ($@)\n";
		    goto header_non_available;
		};
            my ($headersdir, $retries);
         while (!-d $headersdir && $retries < 5) {
             $headersdir = chomp_(`mktemp -d /tmp/rpmdrake.XXXXXXXX`);
             $retries++;
             -d $headersdir or warn qq(Could not create temporary directory "$headersdir");
         }
         -d $headersdir or  do {
             warn "Warning, could not extract header for $name from $hdlist!";
             goto header_non_available;
	    };
	    $packer->extract($headersdir, $p->header_filename);
	    $p->update_header("$headersdir/" . $p->header_filename) or do {
		warn "Warning, could not extract header for $name from $hdlist!";
		goto header_non_available;
	    };
	    rm_rf($headersdir);
	    add2hash($pkg, { description => rpm_description($p->description) });
	    add2hash($pkg, {
	        files => scalar($p->files) ? [ $p->files ] : [ N("(none)") ],
		changelog => $chg_prepro->(join("\n", mapn { "* " . localtime2changelog($_[2]) . " $_[0]\n\n$_[1]\n" }
						[ $p->changelog_name ], [ $p->changelog_text ], [ $p->changelog_time ])) });
	    $p->pack_header; # needed in order to call methods on objects outside ->traverse
	} else {
           header_non_available:
             add2hash($pkg, { summary => $p->summary || N("(Not available)"), description => undef });
	}
    }
}

my %options;

# because rpm blocks some signals when rpm DB is opened, we don't keep open around:
sub open_rpm_db {
    my ($o_force) = @_;
    my $host;
    log::explanations("opening the RPM database");
    if ($options{parallel} && ((undef, $host) = @{$options{parallel}})) {
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
        URPM::DB::open($::rpmdrake_options{'rpm-root'}->[0]) or die "Couldn't open RPM DB ($::rpmdrake_options{'rpm-root'}->[0])";
    }
}


sub find_installed_version {
    my ($p) = @_;
    my @version;
    open_rpm_db()->traverse_tag('name', [ $p->name ], sub { push @version, $_[0]->version . '-' . $_[0]->release });
    @version ? join(',', sort @version) : N("(none)");
}

sub formatlistpkg { join("\n", map { s/^(\s)/  \1/mg; "- $_" } sort { uc($a) cmp uc($b) } @_) }


# -=-=-=---=-=-=---=-=-=-- install packages -=-=-=---=-=-=---=-=-=-

my (@update_medias, $is_update_media_already_asked);

sub warn_about_media {
    my ($w, $opts) = @_;
    my $urpm = open_urpmi_db();

    my $update_name = 'update_source';
    return if !member($::default_list_mode, qw(all_updates security bugfix normal));
    return if $::rpmdrake_options{'no-media-update'};

    # do not update again media after installing/removing some packages:
    $::rpmdrake_options{'no-media-update'} ||= 1;

	    if (@update_medias > 0) {
		if (!$opts->{skip_updating_mu} && !$is_update_media_already_asked) {
              $is_update_media_already_asked = 1;
		     $::rpmdrake_options{'no-confirmation'} or interactive_msg_with_banner(N("Confirmation"),
N("I need to contact the mirror to get latest update packages.
Please check that your network is currently running.

Is it ok to continue?"), yesno => 1,
                   widget =>  gtknew('CheckButton', text => N("Do not ask me next time"),
                                     active_ref => \$::rpmdrake_options{'no-confirmation'}
                                 )) or myexit(-1);
		    writeconf();
		    urpm::media::select_media($urpm, map { $_->{name} } @update_medias);
		    update_sources($urpm, noclean => 1, banner => $::isEmbedded);
		}
	    } else {
		if (any { $_->{update} } @{$urpm->{media}}) {
		    interactive_msg(N("Already existing update media"),
N("You already have at least one update medium configured, but
all of them are currently disabled. You should run the Software
Media Manager to enable at least one (check it in the \"%s\"
column).

Then, restart \"%s\".", N("Enabled"), $rpmdrake::myname_update));
		    myexit(-1);
		}
	      mu_retry_another_mirror:
		my ($mirror) = choose_mirror(if_(exists $w->{real_window}, transient => $w->{real_window}));
		my $m = ref($mirror) ? $mirror->{url} : '';
		$m or interactive_msg(N("How to choose manually your mirror"),
N("You may also choose your desired mirror manually: to do so,
launch the Software Media Manager, and then add a `Security
updates' medium.

Then, restart %s.", $rpmdrake::myname_update)), myexit(-1);
		add_medium_and_check(
		    $urpm, {},
		    $update_name, make_url_mirror($m), 'media_info/synthesis.hdlist.cz', update => 1,
		);
		@update_medias = { name => $update_name };  #- hack to simulate a medium for parsing of descriptions
	    }
}



sub open_urpmi_db() {
    my $error_happened;
    my $urpm = urpm->new;
    $urpm->{options}{'split-level'} ||= 20;
    $urpm->{options}{'split-length'} ||= 1;
    $urpm->{options}{'verify-rpm'} = !$::rpmdrake_options{'no-verify-rpm'} if defined $::rpmdrake_options{'no-verify-rpm'};
    $urpm->{options}{auto} = $::rpmdrake_options{'auto'} if defined $::rpmdrake_options{'auto'};
    urpm::set_files($urpm, $::rpmdrake_options{'urpmi-root'}->[0]) if $::rpmdrake_options{'urpmi-root'}->[0];
    urpm::args::set_root($urpm, $::rpmdrake_options{'rpm-root'}->[0]) if $::rpmdrake_options{'rpm-root'}->[0];

    $urpm::args::rpmdrake_options{justdb} = $::rpmdrake_options{justdb};

    $urpm->{fatal} = sub {
        $error_happened = 1;
        interactive_msg(N("Fatal error"),
                         N("A fatal error occurred: %s.", $_[1]));
    };
    my $media = ref $::rpmdrake_options{media} ? join(',', @{$::rpmdrake_options{media}}) : '';
    urpm::media::read_config($urpm);

    my $searchmedia = join(',', map { $_->{name} } grep { $_->{ignore} && $_->{name} =~ /backport/i } @{$urpm->{media}});
    urpm::media::configure($urpm, media => $media, if_($searchmedia, searchmedia => $searchmedia));
    if ($error_happened) {
        touch('/etc/urpmi/urpmi.cfg');
        exec('edit-urpm-sources.pl');
    }
    $urpm;
}

sub get_parallel_group() {
    $::rpmdrake_options{parallel} ? $::rpmdrake_options{parallel}[0] : undef;
}

our $probe_only_for_updates;
sub get_pkgs {
    my ($opts) = @_;
    my $w = $::main_window;

    Rpmdrake::gurpm::init(1 ? N("Please wait") : N("Package installation..."), N("Initializing..."), transient => $::main_window);
    my $_gurpm_clean_guard = before_leaving { Rpmdrake::gurpm::end() };
    my $_flush_guard = Gtk2::GUI_Update_Guard->new;

    my $urpm = open_urpmi_db();
    my $_lock = urpm::lock::urpmi_db($urpm);
    @update_medias = grep { !$_->{ignore} && $_->{update} } @{$urpm->{media}};

    warn_about_media($w, $opts);

    Rpmdrake::gurpm::label(N("Reading updates description"));
    Rpmdrake::gurpm::progress(0.05);

	#- parse the description file
    my %update_descr = urpm::get_updates_description($urpm, @update_medias);

    my $_unused = N("Please wait, finding available packages...");

    # find out installed packages:

    my $level = 0.05;
    my $total = @{$urpm->{depslist}};
    Rpmdrake::gurpm::label(N("Please wait, listing base packages..."));
    Rpmdrake::gurpm::progress($level);

    my ($count, $prev_stage, $new_stage, $limit);
    
    my $reset_update = sub { undef $prev_stage; $count = 0; $limit = $_[0] };
    my $update = sub {
        return if !$total; # don't die if there's no source
        $count++;
        $new_stage = $level+($limit-$level)*$count/$total;
        if ($prev_stage + 0.01 < $new_stage) {
            $prev_stage = $new_stage;
            Rpmdrake::gurpm::progress($new_stage);
        }
    };

    my @base = ("basesystem", split /,\s*/, $urpm->{global_config}{'prohibit-remove'});
    my (%base, %basepackages);
    my $db = open_rpm_db();
    my $sig_handler = sub { undef $db; exit 3 };
    local $SIG{INT} = $sig_handler;
    local $SIG{QUIT} = $sig_handler;
    $reset_update->(0.33);
    while (defined(local $_ = shift @base)) {
	exists $basepackages{$_} and next;
	$db->traverse_tag(m|^/| ? 'path' : 'whatprovides', [ $_ ], sub {
			      $update->();
			      push @{$basepackages{$_}}, urpm_name($_[0]);
			      push @base, $_[0]->requires_nosense;
			  });
    }
    foreach (values %basepackages) {
	my $n = @$_; #- count number of times it's provided
	foreach (@$_) {
	    $base{$_} = \$n;
	}
    }
    Rpmdrake::gurpm::label(N("Please wait, finding installed packages..."));
    Rpmdrake::gurpm::progress($level = 0.33);
    $reset_update->(0.66);
    my (@installed_pkgs, %all_pkgs);
    if (!$probe_only_for_updates) {
    $db->traverse(sub {
	    my ($pkg) = @_;
	    $update->();
	    my $fullname = urpm_name($pkg);
	    #- Extract summary and description since they'll be lost when the header is packed
	    $all_pkgs{$fullname} = {
		selected => 0, pkg => $pkg, urpm_name => urpm_name($pkg),
		summary => $pkg->summary,
		description => rpm_description($pkg->description),
	    } if !($all_pkgs{$fullname} && $all_pkgs{$fullname}{description});
	    if (my $name = $base{$fullname}) {
		$all_pkgs{$fullname}{base} = \$name;
		$pkg->set_flag_base(1) if $$name == 1;
	    }
         push @installed_pkgs, $fullname;
	    $pkg->pack_header; # needed in order to call methods on objects outside ->traverse
	});
    }

    if (my $group = get_parallel_group()) {
        urpm::media::configure($urpm, parallel => $group);
    }

    # find out availlable packages:

    $urpm->{state} = {};
    my (@installable_pkgs, @updates);

    Rpmdrake::gurpm::label(N("Please wait, finding available packages..."));
    Rpmdrake::gurpm::progress($level = 0.66);

    check_update_media_version($urpm, @update_medias);

    my $requested = {};
    my $state = {};
    $urpm->request_packages_to_upgrade(
	$db,
	$state,
	$requested,
    );

    # list of updates (including those matching /etc/urpmi/skip.list):
    my @requested = sort map { urpm_name($_) } @{$urpm->{depslist}}[keys %$requested];
    # list of pure updates (w/o those matching /etc/urpmi/skip.list but with their deps):
    my @requested_strict = $probe_only_for_updates ?
      sort map {
          urpm_name($_);
      } $urpm->resolve_requested($db, $state, $requested, callback_choices => \&Rpmdrake::gui::callback_choices)
        : ();
    # list updates including skiped ones + their deps in MandrivaUpdate:
    push @requested, difference2(\@requested_strict, \@requested) if $probe_only_for_updates;

    if (!$probe_only_for_updates) {
        $urpm->compute_installed_flags($db); # TODO/FIXME: not for updates
        $urpm->{depslist}[$_]->set_flag_installed foreach keys %$requested; #- pretend it's installed
    }
    $urpm->{rpmdrake_state} = $state; #- Don't forget it
    Rpmdrake::gurpm::progress($level = 0.7);

    my @search_medias = grep { $_->{searchmedia} } @{$urpm->{media}};

    my @backports;
    my %pkg_sel   = map { $_ => 1 } @{$::rpmdrake_options{'pkg-sel'}   || []};
    my %pkg_nosel = map { $_ => 1 } @{$::rpmdrake_options{'pkg-nosel'} || []};
    $reset_update->(1);
    foreach my $pkg (@{$urpm->{depslist}}) {
        $update->();
	$pkg->flag_upgrade or next;
        my $selected = 0;
        my $name = urpm_name($pkg);

	if (member($name, @requested) && any { $pkg->id >= $_->{start} && $pkg->id <= $_->{end} } @update_medias) {
            if ($::rpmdrake_options{'pkg-sel'} || $::rpmdrake_options{'pkg-nosel'}) {
		my $n = $name;
		$pkg_sel{$n} || $pkg_nosel{$n} or next;
		$pkg_sel{$n} and $selected = 1;
	    } else {
             # selecting updates by default but skipped ones (MandrivaUpdate only):
             $selected = member($name, @requested_strict);
	    }
            push @updates, $name;
	} else {
         push @installable_pkgs, $name;
         if (@search_medias) {
             my $raw_medium = pkg2medium($pkg, $urpm);
             my $medium = $raw_medium->{name};
             push @backports, $name if any { $_->{start} <= $pkg->id && $pkg->id <= $_->{end} } @search_medias;
         }
     }
        $all_pkgs{urpm_name($pkg)} = { selected => $selected, pkg => $pkg,
                                       summary => $pkg->summary,
                                   };
    }
    if ($::rpmdrake_options{'pkg-sel'} && $::rpmdrake_options{'pkg-nosel'}) {
        push @{$::rpmdrake_options{'pkg-nosel'}}, @{$::rpmdrake_options{'pkg-sel'}};
        delete $::rpmdrake_options{'pkg-sel'};
    }

    $all_pkgs{$_}{pkg}->set_flag_installed foreach @installed_pkgs;

    # urpmi only care about the first medium where it found the package,
    # so there's no need to list the same package several time:
    @installable_pkgs = uniq(@installable_pkgs);

    +{ urpm => $urpm,
       all_pkgs => \%all_pkgs,
       installed => \@installed_pkgs,
       installable => \@installable_pkgs,
       updates => \@updates,
       update_descr => \%update_descr,
       backports => \@backports,
   };
}

sub display_READMEs_if_needed {
    my ($urpm, $w) = @_;
    return if !$urpm->{readmes};
    my %Readmes = %{$urpm->{readmes}};
    if (keys %Readmes) {        #- display the README*.urpmi files
        interactive_packtable(
            N("Upgrade information"),
            $w,
            N("These packages come with upgrade information"),
            [ map {
                my $fullname = $_;
                [ gtkpack__(
                    gtknew('HBox'),
                    gtkset_selectable(gtknew('Label', text => $Readmes{$fullname}),1),
                ),
                  gtksignal_connect(
                      gtknew('Button', text => N("Upgrade information about this package")),
                      clicked => sub {
                          interactive_msg(
                              N("Upgrade information about package %s", $Readmes{$fullname}),
                              (join '' => formatAlaTeX(scalar cat_($fullname))),
                              scroll => 1,
                          );
                      },
                  ),
		    ] } keys %Readmes ],
            [ gtknew('Button', text => N("Ok"), clicked => sub { Gtk2->main_quit }) ]
        );
    }
}

sub perform_parallel_install {
    my ($urpm, $group, $w, $statusbar_msg_id) = @_;
    my @pkgs = map { if_($_->flag_requested, urpm_name($_)) } @{$urpm->{depslist}};
    my $temp = chomp_(`mktemp /tmp/rpmdrake.XXXXXXXX`);
    -e $temp or die N("Could not create temporary directory '%s'", $temp);

    my $res = !run_program::get_stderr('urpmi', '2>', $temp, '-v', '--X', '--parallel', $group, @pkgs);
    my @error_msgs = cat_($temp);

    if ($res) {
        $$statusbar_msg_id = statusbar_msg(
            #N("Everything installed successfully"),
            N("All requested packages were installed successfully."),
        );
    } else {
        interactive_msg(
            N("Problem during installation"),
            N("There was a problem during the installation:\n\n%s", join("\n", @error_msgs)),
            scroll => 1,
        );
    }
    open_rpm_db('force_sync');
    $w->set_sensitive(1);
    return 0;
}

sub perform_installation {  #- (partially) duplicated from /usr/sbin/urpmi :-(
    my ($urpm, $pkgs) = @_;

    my @error_msgs;
    my $statusbar_msg_id;
    local $urpm->{fatal} = sub {
        my $fatal_msg = $_[1];
        printf STDERR "Fatal: %s\n", $fatal_msg;
        Rpmdrake::gurpm::end();
        interactive_msg(N("Installation failed"),
                        N("There was a problem during the installation:\n\n%s", $fatal_msg));
        goto return_with_exit_code;
    };
    local $urpm->{error} = sub { printf STDERR "Error: %s\n", $_[0]; push @error_msgs, $_[0] };

    my $w = $::main_window;
    $w->set_sensitive(0);
    my $_restore_sensitive = before_leaving { $w->set_sensitive(1) };

    my $_flush_guard = Gtk2::GUI_Update_Guard->new;

    if (my $group = get_parallel_group()) {
        return perform_parallel_install($urpm, $group, \$statusbar_msg_id);
    }

    my $lock = urpm::lock::urpmi_db($urpm);
    my $rpm_lock = urpm::lock::rpm_db($urpm, 'exclusive');
    my $state = $probe_only_for_updates ? { } : $urpm->{rpmdrake_state};

    # select packages to install:
    $urpm->resolve_requested(open_rpm_db(), $state, { map { $_->id => undef } grep { $_->flag_selected } @{$urpm->{depslist}} },
                             callback_choices => \&Rpmdrake::gui::callback_choices);

    my ($local_sources, $list) = urpm::get_pkgs::selected2list($urpm, 
	$state->{selected},
    );
    if (!$local_sources && (!$list || !@$list)) {
        interactive_msg(
	    N("Unable to get source packages."),
	    N("Unable to get source packages, sorry. %s",
		@error_msgs ? N("\n\nError(s) reported:\n%s", join("\n", @error_msgs)) : ''),
	    scroll => 1,
	);
        goto return_with_exit_code;
    }

    my @pkgs = map { scalar($_->fullname) } sort(grep { $_->flag_selected } @{$urpm->{depslist}});#{ $a->name cmp $b->name } @{$urpm->{depslist}}[keys %{$state->{selected}}];
    @{$urpm->{ask_remove}} = sort urpm::select::removed_packages($urpm, $urpm->{state});
    my @to_remove = map { if_($pkgs->{$_}{selected} && !$pkgs->{$_}{pkg}->flag_upgrade, $pkgs->{$_}{urpm_name}) } keys %$pkgs;

    my $r = formatlistpkg(map { scalar(urpm::select::translate_why_removed_one($urpm, $urpm->{state}, $_)) } @to_remove);

    my $install_count = int(@pkgs);
    my $to_install = $install_count == 0 ? '' :
      ( P("The following package is going to be installed:", "The following %d packages are going to be installed:", $install_count, $install_count)
      . "\n" . formatlistpkg(map { s!.*/!!; $_ } @pkgs) . "\n");
    my $remove_count =  scalar(@to_remove);
    interactive_msg(($to_install ? N("Confirmation") : N("Some packages need to be removed")),
                     ($r ? 
                        (!$to_install ? join("\n\n", P("Remove one package?", "Remove %d packages?", $remove_count, $remove_count), $r) :
 ($remove_count == 1 ?
 N("The following package has to be removed for others to be upgraded:")
 : N("The following packages have to be removed for others to be upgraded:")) . join("\n\n", '', $r, if_($to_install, $to_install)) . N("Is it ok to continue?"))
                          : $to_install),
                     scroll => 1,
                     yesno => 1) or return 1;

    my $_umount_guard = before_leaving { urpm::removable::try_umounting_removables($urpm) };

    # select packages to uninstall for !update mode:
    perform_removal($urpm, { map { $_ => $pkgs->{$_} } @to_remove }) if !$probe_only_for_updates;

    Rpmdrake::gurpm::init(1 ? N("Please wait") : N("Package installation..."), N("Initializing..."), transient => $::main_window);
    my $_guard = before_leaving { Rpmdrake::gurpm::end() };
    my $canceled;
    my $something_installed;

    my ($progress, $total, @rpms_upgrade);
    my $transaction;
    my ($progress_nb, $transaction_progress_nb, $remaining, $done);
    my $callback_inst = sub {
        my ($urpm, $type, $id, $subtype, $amount, $total) = @_;
        my $pkg = defined $id ? $urpm->{depslist}[$id] : undef;
        if ($subtype eq 'start') {
            if ($type eq 'trans') {
                Rpmdrake::gurpm::label(1 ? N("Preparing packages installation...") : N("Preparing package installation transaction..."));
                } elsif (defined $pkg) {
                    $something_installed = 1;
                    Rpmdrake::gurpm::label(N("Installing package `%s' (%s/%s)...", $pkg->name, ++$transaction_progress_nb, scalar(@{$transaction->{upgrade}}))
                                             . "\n" .N("Total: %s/%s", ++$progress_nb, $install_count));
                }
        } elsif ($subtype eq 'progress') {
            Rpmdrake::gurpm::progress($total ? $amount/$total : 1);
        }
    };

    urpm::main_loop::run($urpm, $state, undef, undef, { },
                         {
                             completed => sub {
                                 # explicitly destroy the progress window when it's over; we may
                                 # have sg to display before returning (errors, rpmnew/rpmsave, ...):
                                 Rpmdrake::gurpm::end();
                                       
                                 undef $lock;
                                 undef $rpm_lock;
                             },
                             inst => $callback_inst,
                             trans => $callback_inst,
                             ask_yes_or_no => sub {
                                 # handle 'allow-force' and 'allow-nodeps' options:
                                 my ($title, $msg) = @_;
                                 local $::main_window = $Rpmdrake::gurpm::mainw->{real_window};
                                 interactive_msg($title, $msg, yesno => 1, scroll => 1,
                                 ) or goto return_with_exit_code;
                             },
                             message => sub {
                                 my ($message) = @_;
                                 interactive_msg(N("Error"), $message, yesno => 1);
                             },
                             trans_log => sub {
                                 my ($mode, $file, $percent, $total, $eta, $speed) = @_;
                                 if ($mode eq 'start') {
                                     Rpmdrake::gurpm::label(N("Downloading package `%s'...", basename($file)));
                                     Rpmdrake::gurpm::validate_cancel(but(N("Cancel")), sub { $canceled = 1 });
                                 } elsif ($mode eq 'progress') {
                                     Rpmdrake::gurpm::label(
                                         join("\n",
                                              N("Downloading package `%s'...", basename($file)),
                                              (defined $total && defined $eta ?
                                                 N("        %s%% of %s completed, ETA = %s, speed = %s", $percent, $total, $eta, $speed)
                                                   : N("        %s%% completed, speed = %s", $percent, $speed)
                                               ) =~ /^\s*(.*)/
                                           ),
                                     );
                                     Rpmdrake::gurpm::progress($percent/100);
                                 } elsif ($mode eq 'end') {
                                     Rpmdrake::gurpm::progress(1);
                                     Rpmdrake::gurpm::invalidate_cancel();
                                 }
                                 $canceled and goto return_with_exit_code;

                             },
                             post_extract => sub {
                                 my ($set, $transaction_sources, $transaction_sources_install) = @_;
                                 $transaction = $set;
                                 $transaction_progress_nb = 0;
                                 $done += grep { !/\.src\.rpm$/ } values %$transaction_sources;         #updates
                                 $total = keys(%$transaction_sources_install) + keys %$transaction_sources;
                                 push @rpms_upgrade, grep { !/\.src\.rpm$/ } values %$transaction_sources;
                                 $done += grep { !/\.src\.rpm$/ } values %$transaction_sources_install; # installs
                             },
                             pre_removable => sub {
                                 # Gtk2::GUI_Update_Guard->new use of alarm() kill us when
                                 # running system(), thus making DVD being ejected and printing
                                 # wrong error messages (#30463)
                                       
                                 local $SIG{ALRM} = sub { die "ALARM" };
                                 $remaining = alarm(0);
                             },

                             post_removable => sub { alarm $remaining },
                             copy_removable => sub {
                                 interactive_msg(
                                     N("Change medium"),
                                     N("Please insert the medium named \"%s\" on device [%s]", $_[0], $_[1]),
                                     yesno => 1, text => { no => N("Cancel"), yes => N("Ok") },
                                 );
                             },
                             pre_check_sig => sub { Rpmdrake::gurpm::label(N("Verifying package signatures...")) },
                             check_sig => sub { Rpmdrake::gurpm::progress(++$progress/$total) },
                             bad_signature => sub {
                                 my ($msg, $msg2) = @_;
                                 local $::main_window = $Rpmdrake::gurpm::mainw->{real_window};
                                 interactive_msg(
                                     N("Warning"), "$msg\n$msg2", yesno => 1, if_(10 < $msg =~ tr/\n/\n/, scroll => 1),
                                 ) or goto return_with_exit_code;
                             },
                             post_download => sub {
                                 $canceled and goto return_with_exit_code;
                                 Rpmdrake::gurpm::invalidate_cancel_forever();
                             },
                             missing_files_summary => sub {
                                 my ($error_sources) = @_;
                                 my @missing_errors = values %$error_sources or return;
                                 interactive_msg(
                                     N("Installation failed"),
                                     N("Installation failed, some files are missing:\n%s\n\nYou may want to update your media database.",
                                       join "\n", map { "- $_" } sort @missing_errors) .
                                         (@error_msgs ? N("\n\nError(s) reported:\n%s", join("\n", @error_msgs)) : ''),
                                     scroll => 1,
                                 );
                             },
                             trans_error_summary => sub {
                                 my ($nok, $errors) = @_;
                                 interactive_msg(
                                     N("Problem during installation"),
                                     if_($nok, N("%d installation transactions failed", $nok) . "\n\n") .
                                       N("There was a problem during the installation:\n\n%s",
                                         join("\n\n", @$errors, @error_msgs)),
                                     if_(@$errors + @error_msgs > 1, scroll => 1),
                                 );
                             },
                             success_summary => sub {
                                 if (!($done || @to_remove)) {
                                     interactive_msg(N("Error"),
                                                     N("Unrecoverable error: no package found for installation, sorry."));
                                     return;
                                 }
                                 my %pkg2rpmnew;
                                 foreach my $u (@rpms_upgrade) {
                                     $u =~ m|/([^/]+-[^-]+-[^-]+)\.[^\./]+\.rpm$|
                                       and $pkg2rpmnew{$1} = [ grep { m|^/etc| && (-r "$_.rpmnew" || -r "$_.rpmsave") }
                                                                 map { chomp_($_) } run_rpm("rpm -ql $1") ];
                                 }
                                 dialog_rpmnew(N("The installation is finished; everything was installed correctly.

Some configuration files were created as `.rpmnew' or `.rpmsave',
you may now inspect some in order to take actions:"),
                                               %pkg2rpmnew)
                                   and $statusbar_msg_id = statusbar_msg(N("All requested packages were installed successfully."));
                                 display_READMEs_if_needed($urpm, $w);
                             },
                             already_installed_or_not_installable => sub {
                                 my ($msg1, $msg2) = @_;
                                 interactive_msg(N("Error"), join("\n", @$msg1, @$msg2));                                
                             },
                         },
                     );

    statusbar_msg_remove($statusbar_msg_id); #- XXX maybe remove this

  return_with_exit_code:
    return !($something_installed || scalar(@to_remove));
}


# -=-=-=---=-=-=---=-=-=-- remove packages -=-=-=---=-=-=---=-=-=-

sub perform_removal {
    my ($urpm, $pkgs) = @_;
    my @toremove = map { if_($pkgs->{$_}{selected}, $pkgs->{$_}{urpm_name}) } keys %$pkgs;
    return if !@toremove;
    Rpmdrake::gurpm::init(1 ? N("Please wait") : N("Please wait, removing packages..."), N("Initializing..."), transient => $::main_window);
    my $_a = before_leaving { Rpmdrake::gurpm::end() };

    my $progress = -1;
    local $urpm->{log} = sub {
        my $str = $_[0];
        print $str;
        $progress++;
        return if $progress <= 0; # skip first "creating transaction..." message
        Rpmdrake::gurpm::label($str); # display "removing package %s"
        Rpmdrake::gurpm::progress(min(0.99, scalar($progress/@toremove)));
        gtkflush();
    };

    my @results;
    slow_func_statusbar(
	N("Please wait, removing packages..."),
	$::main_window,
	sub {
	    @results = $::rpmdrake_options{parallel}
		? urpm::parallel::remove($urpm, \@toremove)
		: urpm::install::install($urpm, \@toremove, {}, {},
                                   callback_report_uninst => sub { Rpmdrake::gurpm::label($_[0]) },
                               );
	    open_rpm_db('force_sync');
	},
    );
    if (@results) {
	interactive_msg(
	    N("Problem during removal"),
	    N("There was a problem during the removal of packages:\n\n%s", join("\n",  @results)),
	    if_(@results > 1, scroll => 1),
	);
	return 1;
    } else {
	return 0;
    }
}

1;
