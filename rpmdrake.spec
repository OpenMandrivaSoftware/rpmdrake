##################################################################
#
#
# !!!!!!!! WARNING => THIS HAS TO BE EDITED IN THE CVS !!!!!!!!!!!
#
#
##################################################################

%define name rpmdrake
%define version 3.1.1
%define release %mkrel 1

Name: %{name}
Version: %{version}
Release: %{release}
License: GPL
Source0: %name-%version.tar.bz2
Summary: Mandriva Linux graphical front end for sofware installation/removal
Requires: perl-MDK-Common >= 1.1.18-2mdk
Requires: urpmi >= 4.8.4
Requires: perl-URPM >= 1.40
Requires: drakxtools >= 10.4.54-1
Requires: rpmtools >= 5.0.5
Requires: packdrake >= 5.0.5
Requires: perl-Gtk2 >= 1.054-1mdk
Requires: perl-Locale-gettext >= 1.01-7mdk
# for now, packdrake (5.0.9) works better with this
Requires: perl-Compress-Zlib >= 1.33
BuildRequires: curl-devel >= 7.12.1-1mdk gettext openssl-devel perl-devel
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Group: System/Configuration/Packaging
URL: http://cvs.mandriva.com/cgi-bin/cvsweb.cgi/soft/rpmdrake/
Obsoletes: MandrakeUpdate
Provides: MandrakeUpdate
Conflicts: drakconf < 10.1-4mdk

%description
rpmdrake is a simple graphical frontend to manage software packages on a
Mandriva Linux system; it has 3 different modes:
- software packages installation;
- software packages removal;
- MandrivaUpdate (software packages updates).

A fourth program manages the media (add, remove, edit).

%package -n park-rpmdrake
Summary: Configure and update rpms on a park
Group: System/Configuration/Packaging
Requires: rsync scanssh perl-Expect rpmdrake

%description -n park-rpmdrake
Configure and update rpms on a park of hosts. The backend is parallel urpmi.

%prep
rm -rf $RPM_BUILD_ROOT

%setup -q

%build
make OPTIMIZE="$RPM_OPT_FLAGS -Wall" PREFIX=%{_prefix} INSTALLDIRS=vendor

%install
make install PREFIX=%buildroot/%{_prefix} BINDIR=%buildroot/%{_bindir} SBINDIR=%buildroot/%{_sbindir} DESTDIR=%buildroot
mkdir -p $RPM_BUILD_ROOT/%{perl_vendorlib}
install -m 644 rpmdrake.pm $RPM_BUILD_ROOT/%{perl_vendorlib}

%find_lang rpmdrake

mkdir -p $RPM_BUILD_ROOT%{_menudir}
cp %{name}.menu $RPM_BUILD_ROOT%{_menudir}/%{name}
mkdir -p $RPM_BUILD_ROOT%{_datadir}/applications/
cat > $RPM_BUILD_ROOT%{_datadir}/applications/mandriva-rpmdrake.desktop << EOF
[Desktop Entry]
Name=Install, Remove & Update Software
Comment=A graphical front end for installing, removing and updating packages
Exec=/usr/sbin/rpmdrake
Icon=/usr/share/icons/rpmdrake.png
Type=Application
Categories=GTK;X-MandrivaLinux-System-Configuration-Packaging;Settings;PackageManager;
EOF


mkdir -p $RPM_BUILD_ROOT{%{_miconsdir},%{_liconsdir}}
for i in rpmdrake rpmdrake-remove mandrivaupdate edit-urpm-sources; do
  cp pixmaps/${i}16.png $RPM_BUILD_ROOT%{_miconsdir}/${i}.png
  cp pixmaps/${i}32.png $RPM_BUILD_ROOT%{_iconsdir}/${i}.png
  cp pixmaps/${i}48.png $RPM_BUILD_ROOT%{_liconsdir}/${i}.png
done

# bloody RPM..
mkdir -p $RPM_BUILD_ROOT/var/lib/urpmi
touch $RPM_BUILD_ROOT/var/lib/urpmi/compssUsers.flat

%clean
rm -rf $RPM_BUILD_ROOT

%post 
%update_menus

%postun
%clean_menus

%files -f rpmdrake.lang
%defattr(-, root, root)
%doc COPYING AUTHORS README ChangeLog
%{_sbindir}/rpmdrake*
%{_sbindir}/MandrivaUpdate
%{_sbindir}/edit-urpm-*
%{_sbindir}/drakrpm-edit-media
%{_sbindir}/drakrpm-update
%{_sbindir}/gurpmi.addmedia
%{_bindir}/*
%{_datadir}/%{name}
%{perl_vendorlib}/*.pm
%{_menudir}/%{name}
%{_datadir}/applications/mandriva-rpmdrake.desktop
%{_iconsdir}/*.png
%{_miconsdir}/*.png
%{_liconsdir}/*.png
%ghost %{_var}/lib/urpmi/compssUsers.flat
%{perl_vendorarch}/auto/*
%{perl_vendorarch}/*.pm

%files -n park-rpmdrake
%defattr(-,root,root)
%{_sbindir}/park-rpmdrake

%changelog
* Mon Aug 28 2006 Thierry Vignaud <tvignaud@mandriva.com> 3.1.1-1mdv2007.0
- add a "Media Manager" entry
- display a busy cursor when:
  o selecting "Reload the packages list"
  o switching mode
- do not embed wait message on startup
- fix some crashes
- group tree:
  o no more pijama style
  o use smaller icons for subgroups

* Wed Aug 23 2006 Thierry Vignaud <tvignaud@mandriva.com> 3.1-1mdv2007.0
- make GUI working
- many GUI improvements
- somewhat faster startup (more to come...)

* Mon Jul 10 2006 Olivier Blin <oblin@mandriva.com> 3.0-2mdv2007.0
- add 2.27-2mdk changes that weren't in CVS

* Mon Jul  3 2006 Thierry Vignaud <tvignaud@mandriva.com> 3.0-1mdv2007.0
- make some windows transcient
- fix garbaged error messages while accessing mirrors
- edit-urpm-sources:
  o improve layout by using nicer alignment (#17716)
  o improve layout by using a combo box (#17733)
  o let's be more user-friendly by showing one cannot move an item
    when it's the first or the last one
  o prevent some Gtk+ critic warnings
- rpmdrake (WIP):
  o unify all interfaces (#21877)
  o add a "report bug" menu entry (since mcc's menu is hidden)
  o enable one to cancel selecting packages
  o fix encoding of urpmi error

* Fri Mar 17 2006 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.27-2mdk
- Rebuild, require new perl-URPM

* Wed Mar 01 2006 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.27-1mdk
- Add Development/PHP to the rpm group list
- A couple of gurpmi.addmedia bug fixes by Thierry Vignaud
- Fix for mirror and version-guessing heuristic
- Clean cache after downloads
- Update config file when not run as root

* Mon Jan 02 2006 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.26-1mdk
- Add a button to clear the search text field and to redraw the package tree
- Bump requires on drakxtools (for Locale::gettext)

* Fri Dec 16 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.25-1mdk
- Fix another bug with rpm names containing regex metacharacters
- Use Locale::gettext (Pixel)

* Thu Dec 08 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.24-1mdk
- Support rsync sources (Javier Martínez)
- Require urpmi 4.8.4 for fixes

* Mon Nov 28 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.23-2mdk
- Message updates
- Restore embedding of Software Media Manager in MCC

* Fri Nov 18 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.23-1mdk
- Display locks before basesystem packages in rpmdrake-remove
- Honor the "prohibit-remove" option

* Wed Nov 16 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.22-1mdk
- Restore embedding in MCC
- Display README.urpmi only once

* Mon Oct 31 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.21-1mdk
- Fix sort under some locales (bugs #18617 and #19356)
- Ask the user if one should update unignored invalid media
- Remove context menu in the software media manager
- Make some popups prettier in the software media manager
- Fix busy loop in gtk display (bug #15985)
- Misc. cleanups
- Message updates

* Mon Sep 12 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.20-3mdk
- Avoid double encoding for bad signature message
- Message updates

* Tue Aug 30 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.20-2mdk
- Message updates
- Install drakrpm-update in /usr/bin also

* Thu Aug 25 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.20-1mdk
- Message updates
- Avoid some forms of utf8 double-encoding

* Thu Aug 18 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.19-2mdk
- Message updates
- Rename files named mandrake*
- Display sensible wait cursor

* Fri Jul 29 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.19-1mdk
- Add a status bar, remove lots of popup messages
- Fix --pkg-sel= option
- Message updates

* Mon Jul 25 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.18-1mdk
- Make long error windows scrollable
- Translations / strings nits
- Use i18n functions from drakxtools

* Wed Jul 20 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.17-1mdk
- Fix more display bugs

* Tue Jul 19 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.16-2mdk
- Message updates
- Fix display bug 16676

* Mon Jun 13 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.16-1mdk
- Keep descriptions even when alternate synthesis media
- Always display banners in MCC

* Wed May 18 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.15-1mdk
- Software media manager: add a column to mark media as update sources,
  and add an "update" checkbox to mark added media as "updates".
- MandrivaUpdate: Always show reason for upgrades even if no media was updated

* Fri May 13 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.14-1mdk
- Fix rpmdrake in non-update modes

* Thu May 12 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.13-1mdk
- Rework the algorithm to compute upgrades to be more similar to urpmi
- Display architecture in information panel

* Thu Apr 28 2005 Rafael Garcia-Suarez <rgarciasuarez@mandriva.com> 2.12-1mdk
- Prompt for proxy credentials if configured so
- Require newest urpmi
- Don't display rsync mirrors if rsync isn't installed
- Recognize the "Limited" distro brand
- Handle virtual media correctly

* Fri Apr 15 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.11-1mdk
- Rename MandrakeUpdate to MandrivaUpdate

* Wed Mar 30 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.10-4mdk
- po updates
- make gurpmi.addmedia more robust (bug #15028)

* Mon Mar 21 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.10-3mdk
- Change window title, doesn't include internal version name
- po updates

* Wed Mar 16 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.10-2mdk
- Install drakrpm-edit-media as a symlink to edit-urpm-sources.pl

* Wed Mar 16 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.10-1mdk
- Don't install drakrpm-edit-media
- rpmdrake --help works again
- Notes for installed packages are not displayed several times across different
  installs

* Mon Mar 07 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.9-1mdk
- Don't install edit-urpm-media as a copy of edit-urpm-sources.pl anymore
- rpmdrake: restore Quit button, add ctrl-Q as shortcut (Titi)
- add a vertical scrollbar in the software media manager

* Wed Feb 23 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.8-1mdk
- Don't hardcode mirror list url, use /etc/urpmi/mirror.config like
  urpmi.addmedia does

* Mon Feb 14 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.7-1mdk
- Don't show diffs for rpmnew files that haven't changed
- Make the software media manager cope with variables in media (M. Scherer)

* Fri Feb 11 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.6-1mdk
- Fix utf-8 changelog display in rpmdrake-remove
- Fix view by group

* Thu Feb 10 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.5-5mdk
- Fix crash when displaying changelog

* Wed Feb 09 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.5-4mdk
- Add a new command-line option, --search=pkg, to launch search for "pkg" at
  startup
- Now requires Compress::Zlib, to fix obscure packdrake forking issues
- Language updates, and fix some encoding issues

* Thu Jan 20 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.5-3mdk
- When displaying rpms by medium, display media in the order they appear in
  urpmi.cfg
- Restore view of selected size in rpmdrake
- Remove the view menu (for later)

* Tue Jan 18 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.5-2mdk
- Quick fix for a crash on some popup windows
- Regenerate po files

* Mon Jan 17 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.5-1mdk
- Software media manager: the "Add..." dialog allows to add updates as well
  as official sources (for Official distros), whereas the "security updates"
  option from the "Add custom..." dialog has been made redundant.
- Language updates
- Fix requires of park-rpmdrake (Pixel)

* Wed Jan 12 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.4-5mdk
- rpmdrake now has a menu bar (supported in mcc thanks to Titi)
- Fix crash with new mygtk2 (Titi)
- Move the 'Quit', 'Update media' and 'Help' buttons to it, as well as the
  right-click popup menu.
- Software media manager: requalify the "Add..." button to add the sources for
  the current distribution, and rename the old "Add..." button to "Add
  custom...". (The implementation is not complete yet)

* Fri Jan 07 2005 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.4-4mdk
- New command-line option --no-media-update to Mandrakeupdate, to avoid
  updating media at startup
- A few optimisations
- Fix the display of the number of RPMs to be retrieved in rpmdrake

* Fri Dec 17 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.4-3mdk
- Add the ability to reorder the media in the software media manager

* Wed Dec 15 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.4-2mdk
- Remove dependency on gurpmi
- Only load packdrake when needed
- Translation updates

* Thu Dec 02 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.4-1mdk
- Software media manager:
  - New option setting window, for the downloader and verify-rpm options.
  - Possibility to add all media for a distribution at once (like
    urpmi.addmedia --distrib)
- Add a cancel button in the download progress window
- Don't show the help button in rpmdrake when embedded in the mcc

* Thu Nov 25 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.3-1mdk
- edit-urpm-sources: setting per-media proxies should now work.
- Fix save and restore of package tree display mode in rpmdrake.
- Take into account limit-rate, compress and resume options from urpmi.cfg.

* Thu Nov 18 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.2-4mdk
- edit-urpm-sources: When modifying a media has failed, restore it (don't die,
  and don't keep it in the intermediate state of being ignored)

* Tue Nov 16 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.2-3mdk
- Fix adding an update media in the software media manager.
- Fix sort by country in the mirror list.

* Mon Nov 15 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.2-2mdk
- Rebuild for new perl

* Tue Nov 09 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.2-1mdk
- Make the changelog-first option configurable in ~/.rpmdrake (cf bug 11888)
- Less unnecessary package tree rebuilding
- Can search packages whose names contain a '+'
- Allow branding via an OEM file

* Tue Oct 05 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-13mdk
- Language updates
- Adaptation to the new update mirror architecture

* Thu Sep 30 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-12mdk
- Presentation and translation nits
- Upgrade dependencies

* Thu Sep 23 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-11mdk
- The "Update media" button wasn't active when it should

* Wed Sep 22 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-10mdk
- fix parsing of scanssh output in park-rpmdrake (Pixel)

* Tue Sep 21 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-9mdk
- Display the path of the README.urpmi file
- Language updates
- Change menu entry to 'Mandrakelinux Update'

* Tue Sep 14 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-8mdk
- Language updates
- Disable the "update media" button in removal mode

* Thu Sep 09 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-7mdk
- Language updates
- Change menu entry to 'Mandrakeupdate'

* Wed Sep 01 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-6mdk
- Fix position of "quit" button (Titi)
- Fix display of localized dates in the changelog (Pablo)

* Mon Aug 30 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-5mdk
- Small cleanups in GUI

* Tue Aug 24 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-4mdk
- Add an "update media" button

* Mon Aug 23 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-3mdk
- fix some error popups too large
- fix a crash when trying to remove base packages
- fix download bars for packages (displayed wrong info) and for hdlists (wasn't
  properly updated)
- button reordering
- message updates

* Thu Aug 19 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-2mdk
- Message updates
- Don't ask for selections in browse mode (read-only)
- Reenable selection of all packages

* Wed Aug 18 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.5-1mdk
- Add a checkbox "Show automatically selected packages" 

* Tue Aug 17 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.4-2mdk
- Message updates
- Fix a bug on display of fatal errors

* Wed Aug 11 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.4-1mdk
- rpmdrake uses localized dates in changelog
- edit-urpm-sources.pl requires confirmation when removing media
  (Fabrice Facorat)
- Update messages

* Wed Aug 04 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-14mdk
- Update messages
- Fix some utf-8 handling in error messages
- Fix display of rpmdrake's help
- Refuse to select more than 2000 packages at once

* Wed Jul 28 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-13mdk
- Recognize README.update.urpmi, in addition to README.upgrade.urpmi
- Update requires.
- Allow selection of subtrees, except when the whole tree would be selected.

* Tue Jul 20 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-12mdk
- Display fixes
- Message updates
- Prevent to select an entire subtree by mistake. (work around for bug #9941)

* Thu Jul 08 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-11mdk
- After installation or upgrade of an rpm, display the contents of a file
  README{,.install,.upgrade}.urpmi
- Presentation nits

* Wed Jul 07 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-10mdk
- Rebuild and fix for new perl

* Mon Jul 05 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-9mdk
- MandrakeUpdate: list packages even when not found in the description file
- Software media manager: allow to set a proxy for only one media

* Wed Jun 30 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-8mdk
- Don't display the "update media" button when not used as root
- use urpm::download
- rebuild for new curl

* Wed Jun 23 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-7mdk
- Message changes and interface cosmetics
- Software media manager: only update explicitly selected sources
- rpmdrake: checks whether the update media added by the installer corresponds
  to the current MDK release

* Mon May 24 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-6mdk
- Message changes
- Replace deprecated OptionMenu widget by ComboBox

* Tue May 11 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-5mdk
- Avoid selecting all packages when choosing a view sorted by update
  availability
- Remove spurious error messages in the Software Media Manager

* Tue May 04 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-4mdk
- Make the package list pane resizable (Robert Vojta) (#8925)

* Mon May 03 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-3mdk
- Fix reset of the wait cursor when run embedded in drakconf

* Tue Apr 27 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-2mdk
- Language updates

* Mon Apr 26 2004 Rafael Garcia-Suarez <rgarciasuarez@mandrakesoft.com> 2.1.3-1mdk
- MandrakeUpdate: didn't notify the user when it failed to retrieve
  the hdlist or synthesis file from a mirror. As a consequence no
  update was ever appearing.

* Mon Mar 22 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1.2-12mdk
- fix unsane big progressbar for embedded wait messages
- rpmdrake:
  o set xwindow icon
  o fix icon in banner (use same icon as in mcc)
- park-rpmdrake: if mcc icon is there, use it for the wm icon (pixel)
- edit-urpm-sources.pl: just like MandrakeUpdate, edit-urpm-sources
  can also configure a "update" media, so just like MandrakeUpdate
  defaulting it to synthesis instead of hdlist (pixel)

* Wed Mar 10 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1.2-11mdk
- follow std button order
- MandrakeUpdate:
  o fix description and summary field
  o download small synthesis rather than big fat hdlist by default

* Wed Mar  3 2004 Pixel <pixel@mandrakesoft.com> 2.1.2-10mdk
- fix support for "community" and "cooker" classes of mirrors for updates

* Fri Feb 27 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.2-9mdk
- support "community" and "cooker" classes of mirrors for updates

* Thu Feb 26 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.2-8mdk
- MandrakeUpdate: add --media, --pkg-sel and --pkg-nosel commandline
  switches, to be invoked by MandrakeOnline

* Mon Feb 23 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.2-7mdk
- rpmdrake: don't hide progress window during install (#8146)

* Fri Feb 20 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.2-6mdk
- edit-urpm-media: fix broken media reordering (program crashed)
- rpmdrake: hide password in logs (#6260)
- edit-urpm-media: lock urpmi database while running (#6828)

* Fri Feb 13 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1.2-5mdk
- make it embeddable

* Fri Feb 13 2004 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1.2-4mdk
- use new banner style

* Thu Feb 12 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.2-3mdk
- some #7472-alike progressbar sizing fixes
- menu: specify that gurpmi.addmedia handles application/x-urpmi-media
- fix #7425: center-always or center-on-parent popup windows
- fix #7675: rpmdrake-remove wrongly thought an unrelated package was
  needed to remove another one

* Wed Jan 21 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.2-2mdk
- remove unneeded stuff from grpmi/po/*.po
- fix garbled characters for fatal and error msgs reported by urpm
- report more errors when adding a medium
- add gurpmi.addmedia

* Thu Jan 15 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.2-1mdk
- add ability to use rpmdrake/rpmdrake-remove with a "parallel"
  urpmi configuration (drawbacks: deps are shown only valid for a
  given node; multiple choices will work in --auto mode only)
- reword "void" for "empty" (#6873)

* Wed Jan 14 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.1-2mdk
- fix wrongly using unavailable sorting method in remove mode after
  save in install mode
- fix big performance penalty on long filelists since 2.1-36mdk
  allowing correct display of filenames in RTL languages (#6865)
 
* Mon Jan 12 2004 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1.1-1mdk
- add ability to cancel packages downloads (#6317)
- save sorting method at exit of rpmdrake for Lord Titi (#6051)
- together with changes in 2.1-36mdk deserve a subsubversion change
- remove unecessary provides perl(rpmdrake)

* Fri Jan 09 2004 Warly <warly@mandrakesoft.com> 2.1-37mdk
- add provides perl(rpmdrake)

* Tue Dec 23 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-36mdk
- provide drak* names as well
- fix filelist wrongly displayed in RTL language, thx titi (#6581)
- remove info on last selected package after install (#4648)
- MandrakeUpdate: add ability to select all (#6576 and others)

* Fri Sep  5 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-35mdk
- fix invalid-build-requires libcurl2-devel
- fix garbled UTF8 in "summary" and "description" of pkgs when i18n'ed
- use new urpmi API to verify signatures, so that we don't miss
  signatures problems when key of package is not in urpmi allowed pool
- fix "Reset the selection" that didn't really reset it for urpmi :/

* Tue Sep  2 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-34mdk
- s/9.1/9.2/ (#5201)
- help:
  - use --id
  - launch the good sub-chapter
  - add an help button to the Media Editor
- edit-urpm-media: fix not reporting any error when updating of
  media fail (#5212)

* Tue Sep 02 2003 David Baudens <baudens@mandrakesoft.com> 2.1-33mdk
- Update banners

* Mon Aug 18 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-32mdk
- edit-urpm-media:
  - handle modality in parallel and key editors
  - fix #4914 (program crashes when trying to add a medium)
- MandrakeUpdate: handle subdirectory in "updates" for special
  Mandrake issues such as corporate/clustering/etc
- rpmdrake: focus in the find entry on startup (#5021)

* Wed Aug 13 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-31mdk
- require root capability when run "Install Sofware" and add a new
  menu entry reading "Browse Available Software"
- s/Medias/Media/ in the program name of the menu entry
- fixes interactive_packtables dialogs initially much too small
  because titi replaced ->size_request by ->get_size_request
  (such dialog is for example "more information on packages")
- don't display a too high message when there are many packages
  with signatures problems (#4335)
- when updating media, if url is too long, don't display it because
  it enlarges much the dialog; better display only the basename
  and the medium name (#4338)
- edit-urpm-media/add:
  - right-align left labels
  - use a checkbutton for "hdlist" so that user better understands
    it's optional (and say in a tooltip that it is)
  - fix browsing for adding a security update (port gtk2-perl-xs
    not complete)
- edit-urpm-media: add ability to manage media keys

* Mon Aug  4 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-30mdk
- revert "use checkboxes instead of icons"

* Fri Jul 25 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1-29mdk
- use checkboxes instead of icons
- fix mouse selection

* Wed Jul 23 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1-28mdk
- fix #4248 (crash when asking for more infos in rpmdrake-remove)

* Tue Jul 22 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1-27mdk
- let selected packages be visible

* Tue Jul 22 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1-26mdk
- keep rpmdrake wait messages centered
- fix search

* Wed Jul 16 2003 Thierry Vignaud <tvignaud@mandrakesoft.com> 2.1-25mdk
- switch to gtk2-perl-xs

* Wed Jun 18 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-24mdk
- new ugtk2.pm API
- use urpmi reporting reasons for impossibility to select some
  packages, and for needing to remove some
- fix sorting of translated stuff in the treeview (will need
  drakxtools > 9.2-0.7mdk to work properly though)
- split translation of groups to ease i18n job
- fix some missing translations for compssUsers ("Mandrake Choices")
- scroll to the search results

* Fri Jun  6 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-23mdk
- rpmdrake: at install time, when some local files are impossible
  to find, list which one (asked by Gerard Delafond <gerard at
  delafond.org>)
- rpmdrake: new perl-URPM api

* Fri May 30 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-22mdk
- fix media/medias by medium/media
- edit-medias:
  - add ability to edit parallel urpmi
  - add ability to update a medium or regenerate its hdlist through
    right-click on the medium name

* Wed May 28 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-21mdk
- let medias be reorderable in the medias editor (drag and drop the list)
- add ability to list leaves (sorted by installation date) in remove mode
- add ability to run the rpmdrake suite as a user (you can browse
  packages but can't modify the system)
- edit-medias: remove weird looking Save&Quit / Quit buttons, use Ok only
- adding an update source: fix sorting according to tz
- let rpm groups be translatable (exhausts many invalid groups...)
- fix some distlint DIRM

* Fri May 16 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-20mdk
- perl-URPM API change: gives architecture in ask_remove
- fix "packages have bad signature dialog": really display a yes/no
  question! :)
- fix not removing gurpm dialog when exiting package installation with
  an error
- fix #3908 (garbage chars displayed as date in changelog entries in
  removal mode)
- substitute references to "sources" by now talking about "medias",
  should be more understandable and more consistent with urpmi

* Mon May 12 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-19mdk
- obsolete grpmi by gurpm.pm (from urpmi) sharing code between gurpmi
  and rpmdrake
- fix percent completed shown as "speed" in some situations, thx
  David Walser

* Thu Apr 17 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-18mdk
- fix problem shown by #3768: correctly handle case when there
  are already update source(s), but they are all disabled
- report more urpmi errors in the GUI

* Wed Apr 16 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-17mdk
- fix drakhelp zombie process (thx titi)
- More infos -> More info thx David Walser
- fix /me sux breaking the "sorry this package can't be selected"
  in -16mdk, when trying to select a package that conflicts with
  a previously selected
- add urpmi reasons when "sorry this package can't be selected"
- show download progress of update medias when starting
  MandrakeUpdate

* Tue Apr 15 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-16mdk
- update for urpmi-4.3 (skipped packages should be better handled
  now: they will appear in package selection and searches, but
  not in "Upgradable" under "sort by update availability", as one
  would expect)
- MandrakeUpdate: UI change to follow David Walser's suggestions and
  patches from #3610, e.g. don't use two paned windows anymore

* Tue Apr  8 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-15mdk
- rpmdrake: small UI change to follow #3610, e.g. in
  "maximum information" mode, have the source and currently installed
  version closer to the top
- grpmi: fix yet again an UTF8 problem (#3676)

* Wed Mar 26 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-14mdk
- grpmi/curl_download: fixes for MandrakeClub:
  - don't verify peer's certificate (-k option of commandline curl)
  - allow following locations (allow HTTP redirections)
  - don't check for hostname before sending authentication (allow HTTP
    redirection needing authentication to another host)
- grpmi/curl_download: add missing recent curl error codes

* Wed Mar 12 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-13mdk
- update share/icons from mcc new icons

* Tue Mar 11 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-12mdk
- new icons
- latest po's

* Wed Mar  5 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-11mdk
- rpmdrake: when installation fails because some files are missing,
  display any encountered urpmi error
- choose a mirror dialog: larger default size so that the
  scrollbars don't appear
- latest po's

* Mon Mar  3 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-10mdk
- grpmi: fix error reporting (of gpg, rpm, curl) broken in non english

* Fri Feb 28 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-9mdk
- add help support thx to drakhelp

* Fri Feb 28 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-8mdk
- finish using urpmi callbacks when updating sources

* Fri Feb 21 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-7mdk
- fix bug that prevented from having all the translations in
  the PO (#1233)
- rpmdrake:
  - fix locking of CD after installation (#1311)
- add download progress when updating distant sources (still needs
  improvement in messages, work in progress with urpmi)
- some code cleanup thx to titi & perl checker

* Thu Feb 13 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-6mdk
- grpmi: if there was an error during installation, propose to
  remove the cached/downloaded packages or not (partially follows
  a nice suggestion by Jeff Martin <jeffm at tampabay.rr.com>)

* Tue Feb 11 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-5mdk
- rpmdrake:
  - mark version as 9.1
  - fixes error "source not selected" (#966 and its army of duplicates)

* Thu Jan 23 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-4mdk
- edit-urpm-sources:
  - fix wrong display of medium as "enabled", after adding a medium
    that has problems and is hence automatically disabled (#995)
  - fix crashing when managing to call Remove or Edit with nothing
    selected (#970)
- add a dependency to a recent drakxtools to fix #1030
- fix problems of characters display in non-latin1 locales
- fix wait messages breakage when using perl-GTK2 >= 0.0.cvs.2003.01.27.1
- a sources editor fix thx to titi
- select the right program among console-helper and kdesu to become root,
  thx to titi

* Tue Jan 21 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-3mdk
- rpmdrake:
  - fix "update sources" dialog which didn't update the asked mediums
- edit-urpm-sources:
  - fix many errors originating from not being able to access toggle
    buttons and entries after the dialog is finished (empty source
    name, impossible to add mediums without hdlists, etc)

* Fri Jan 10 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-2mdk
- grpmi:
  - verify all signatures at the end of all downloads
  - allow to say "yes to all" to the signatures questions
  - allow to retry downloads
- rpmdrake:
  - don't reset selection list when no package was installed/removed
  - try to have a more sensible default size for the rpmnew dialog
  - fix "Can't call method set_sensitive on an undefined value"
    stopping the program after resolving a rpmnew
  - add the possibility to view more infos on each package, when
    presenting a list of deps
- br*tn*y release :)

* Wed Jan  8 2003 Guillaume Cottenceau <gc@mandrakesoft.com> 2.1-1mdk
- gtk2 (possibly contains important breakages, use with care)
- other fixes:
  - report errors when removing packages errored out!
  - rpmdrake-remove: fix absence of packages that are alternatives to basesystem

* Mon Sep 16 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-27mdk
- fix not finding grpmi in sudo mode
- fix unclickable "not finding grpmi" dialog

* Thu Sep 12 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-26mdk
- fixes not parsing descriptions file when MU adds itself the
  security source
- fixes all packages are displayed when "normal" updates are
  selected, even "security" and "bugfix" packages

* Wed Sep 11 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-25mdk
- when installing packages, set urpm->{fatal} so that I can intercept
  when "cancel" is clicked for the change of CD's -> we no more exit
  the program anymore

* Tue Sep 10 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-24mdk
- when starting rpmdrake as user, usermode restes some env vars, thus
  the locale seen might be fr_FR when it was fr; thus, for the title
  images, we need to load also ^(..)_.+ when the first try fails

* Mon Sep  9 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-23mdk
- in removal mode, fix misleading presence of "update sources"; fix
  behaviour of "reset selection"

* Fri Sep  6 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-22mdk
- don't display passwords in clear text for Lord Beranger
- set /etc/urpmi/proxy.cfg as 0600 when saving it
- add --changelog-first commandline option to display changelog before
  filelist in the description window
- add --merge-all-rpmnew commandline option to ask for merging all
  .rpmnew/.rpmsave files of the system
- fix impossibility of install packages after user refuses one
  time to remove some packages to allow others to be upgraded

* Thu Sep  5 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-21mdk
- add "search in files" in rpmdrake-remove
- when grpmi detects conflicts, don't aask for force, but abort
- when groups are partially selected, clicking on the group means
  unselection, not selection (because some members of groups are
  not selectable)
- have an expert right-click menu on the left treeview, for:
  - reset selection
  - reload lists
  - update sources

* Wed Sep  4 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-20mdk
- maximum information also provides info about currently installed
  package(s)
- add option "--no-verify-rpm" to not verify packages signatures
- have an icon in the top banner, and also have nice looking pre
  rendered (png) i18n's titles for iso8859-15? compatible po's

* Tue Sep  3 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-19mdk
- fix should not report "everything installed successfully" when not
- colorize the .rpmnew/.rpmsave diff
- colorize a bit the package description textfield
- use a fake modality to prevent user from clicking on "install"
  button while current installation is not yet finished
- fix error message when in console mode or XFree not available
- consolehelper should startup faster (when rpmdrake isexecuted
  as user)

* Mon Sep  2 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-18mdk
- rpmdrake:
  - fix displaying of dependencies: sometimes, when some packages
    can't be selected, it didn't correctly display the
    dependencies
  - add symlinks in /usr/bin so that user has the binaries in his path
  - add a warning message when it seems the user will install too much

* Fri Aug 30 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-17mdk
- rpmdrake:
  - support proxies using /etc/urpmi/proxy.cfg
- edit-urpm-sources:
  - add a proxy configuration editor

* Fri Aug 30 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-16mdk
- when a small amount of .rpmnew, don't have a scrolledwindow; when a
  very large amount, don't create a window higher than the screen
- have the changelogs extracted from the hdlist header: quicker, and
  good for distant sources (thx houpla)

* Thu Aug 29 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-15mdk
- fix program exiting when in "maximum informations" in rpmdrake-remove
- fix english typo, "informations" with an "s" doesn't english
- when searching in "by selection" or "by update availability" modes,
  instead of limiting search results, categorize search results

* Thu Aug 29 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-14mdk
- meuh, forgot to upload the change in drakxtools necessary for -13mdk

* Wed Aug 28 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-13mdk
- rpmdrake: right-click on the descriptions of a package to get more
  informations (source name, filelist, changelog when available)

* Tue Aug 27 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-12mdk
- rpmdrake
  - fix displaying of .rpmnew dialog when no .rpmnew files
  - have a static list of files for which we ignore the .rpmnew's
  - support .rpmsave files as well

* Tue Aug 27 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-11mdk
- edit-urpm-sources
  - when editing a removable medium, warn we need the medium in
    drive
  - some questions were only presentend with an "Ok" button
- rpmdrake
  - after installing packages, the "size selected" was not reset to 0
  - import compssUsers translations from drakx, take them for mandrake
    choices tree form
  - provide a nice interface to choose to keep or remove .rpmnew files

* Tue Aug 27 2002 David BAUDENS <baudens@mandrakesoft.com> 2.0-10mdk
- Update icons

* Mon Aug 26 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-9mdk
- grpmi: don't display successful end message when installing packages
  so that we have back the old behaviour and it's better for programs
  requesting several packages installation in a row (standalone apps);
  the successful message is still here in rpmdrake, it's displayed
  by rpmdrake itself
- rpmdrake: when choosing between packages, add the ability to have
  information about each package choice (one button per package)

* Mon Aug 26 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-8mdk
- rpmdrake-remove: don't show basesystem packages so that it
  becomes possible to select whole categories in "Mandrake
  Choices" mode (Development/Development for example)
- rpmdrake-remove: API of urpm.pm has changed (fixes "/" not an ARRAY
  reference)

* Fri Aug 23 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-7mdk
- rpmdrake: when a choice has to be made involving locales,
  autochoose the package requiring the locales already installed
  on the machine, or the package requiring an already selected
  locale
- rpmdrake: when user does a multiple selection of packages to
  install, if some packages require a new locale to install and
  they look like i18n packages (eg they contain the same locale
  name in their name), don't select them; it should fix the
  selection of all the locales when user selects "KDE
  Workstation" or "Gnome Workstation"; of course, still possible
  to select these packages one by one
- in by_presence and by_selection modes, limit search results to
  upgradable packages and to selected packages

* Thu Aug 22 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-6mdk
- edit-urpm-sources: toggle the ignore flag only when the button
  press was really done in an existing col/row
- rpmdrake: definitively fix the compssUsers.flat missing problem
  by having a "default" file for fallbacking on it when the DrakX
  generated one is missing
- grpmi: add an rcfile and the "noclearcache" option so that
  /var/lib/urpmi/cache/rpms/ is not cleared after trying to install
  the packages
- rpmdrake: use the width of current font to set the maximum size
  of the packages column, rather than pure hardcoding
- rpmdrake.pm: since timezone::read doesn't give a hash anymore but
  a hashref I need to reflect that in my code (pixel sux)
- grpmi: don't forget to unlink the tmpfile even when the
  signature is not correct
- grpmi: use my_gtk::exit so that mouse cursor gets fixed when
  exiting
- rpmdrake: keep up the main window when installing/removing
  packages, "it looks more professional"
- rpmdrake: fix exiting program when an hdlist seems corrupted to
  packdrake
- rpmdrake: add "search in descriptions", have an optionmenu to
  select the search type, have a progressbar and a stop button
  because it can be take a long time
- rpmdrake: have it possible to cancel a selection when user is not
  happy of the dependencies of the selection
- rpmdrake: use some hackery in my_gtk and in rpmdrake to really
  have a [+] in front of parent categories even if they are not
  really populated
- MandrakeUpdate: when user cancels the initial choose of mirror,
  explain that she can selects a manual mirror from the sources
  manager
- (fcrozat) provide .desktop files to have rpmdrake stuff in
  Nautilus when rpmdrake package is installed
- MandrakeUpdate: don't only use "update_source" as an update
  source, but all the sources marked as update by urpmi (fixes
  not taking into account the update source defined during
  install, if any)

* Mon Aug  5 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-5mdk
- when searching in files, limit search results to listed
  packages or the program might crash
- when searching in files, do it case sensitive
- in MandrakeUpdate mode, display a nice explanation message when
  the list of updates is void, and also put "(none)" in the list
  instead of seeing nothing and wondering if something is broken
  or not
- don't quit when validation was not ok (e.g. when user doesn't
  like the "these packages need to be removed for others to be
  upgraded", don't quit)
- handle case when use entered ftp location with a leading ftp://
- edit-urpm-sources: don't strictly require that all the fields be
  filled since urpmi can make guesses or build the hdlist itself;
  in removable and local modes, give the probe_with_hdlist option
  when the hdlist field is void

* Mon Aug  5 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-4mdk
- grpmi: provide information about the number of current download and
  number of overall downloads, same with installation of packages
- have compssUsers.flat a ghost file, so that rpm doesn't remove it
  when upgrading from rpmdrake-1.5 series
- substitute popuping Menu to get more sort methods by OptionMenu in
  one of the Radio, it should be easier for users to find them here
- don't exit at the end of the action, but restart
- add "update..." button in edit-urpm-sources to update the desired
  media
- when a search didn't get any results, tell it
- add searching in files facility (decision is made upon the presence
  of a / in the search field)
- try harder to really honour ignored media when trying to guess
  in which medium is a package
- don't die when a header could not be extracted

* Fri Aug  2 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-3mdk
- fix mouse cursor problem by calling my_gtk::exit instead of perl's
- fix grpmi exiting on illegal division by zero when curl reports a
  download of zero size
- allow user to cancel on medium changes

* Fri Aug  2 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-2mdk
- workaround packdrake segfault when hdlist is not available for
  a source (by file testing if the hdlist is readable)

* Thu Aug  1 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-1mdk
- c'mon rpmdrake, strike back in Perl!
