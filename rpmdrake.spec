##################################################################
#
#
# !!!!!!!! WARNING => THIS HAS TO BE EDITED IN THE CVS !!!!!!!!!!!
#
#
##################################################################

%define name rpmdrake
%define version 2.0
%define release 17mdk

Name: %{name}
Version: %{version}
Release: %{release}
License: GPL
Source0: rpmdrake.tar.bz2
Summary: Mandrake Linux graphical front end for choosing packages for installion/removal
Requires: perl-MDK-Common urpmi >= 4.0 perl-URPM >= 0.60 drakxtools >= 1.1.9-24mdk grpmi >= 9.0 rpmtools >= 4.5
BuildRequires: curl-devel rpm-devel
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Group: System/Configuration/Packaging
URL: http://cvs.mandrakesoft.com/cgi-bin/cvsweb.cgi/soft/rpmdrake/
Obsoletes: MandrakeUpdate

%description
rpmdrake is a simple graphical frontend to manage software packages on a
Mandrake Linux system; it has 3 different modes:
- software packages installation;
- software packages removal;
- Mandrake Update (software packages updates).

A fourth program manages the sources (add, remove, edit).

%package -n grpmi
Version: 9.0
Summary: Mandrake Linux graphical frontend for packages installation
Group: System/Configuration/Packaging

%description -n grpmi
grpmi is a graphical frontend to show progression of download and
installation of software packages.

%prep
rm -rf $RPM_BUILD_ROOT

%setup -q -n rpmdrake

%build
make OPTIMIZE="$RPM_OPT_FLAGS -Wall" PREFIX=%{_prefix} INSTALLDIRS=vendor

%install
make install PREFIX=$RPM_BUILD_ROOT/%{_prefix} BINDIR=$RPM_BUILD_ROOT/%{_sbindir}
mkdir -p $RPM_BUILD_ROOT/%{perl_vendorlib}
install -m 644 rpmdrake.pm $RPM_BUILD_ROOT/%{perl_vendorlib}

%find_lang rpmdrake
%find_lang grpmi
cat rpmdrake.lang grpmi.lang

mkdir -p $RPM_BUILD_ROOT%{_menudir}
cat > $RPM_BUILD_ROOT%{_menudir}/%{name} << EOF
?package(%{name}): command="/usr/sbin/rpmdrake" needs="x11" section="Configuration/Packaging" icon="rpmdrake.png"\
title="Install Software" longtitle="A graphical front end for installing packages"
?package(%{name}): command="/usr/sbin/rpmdrake-remove" needs="x11" section="Configuration/Packaging" icon="rpmdrake.png"\
title="Remove Software" longtitle="A graphical front end for removing packages"
?package(%{name}): command="/usr/sbin/MandrakeUpdate" needs="x11" section="Configuration/Packaging" icon="mandrakeupdate.png"\
title="Mandrake Update" longtitle="A graphical front end for software updates"
?package(%{name}): command="/usr/sbin/edit-urpm-sources.pl" needs="x11" section="Configuration/Packaging" icon="rpmdrake.png"\
title="Software Sources Manager" longtitle="A graphical front end to add/remove/edit sources for installing packages"
EOF

mkdir -p $RPM_BUILD_ROOT{%{_miconsdir},%{_liconsdir}}
cp pixmaps/mandrakeupdate16.png $RPM_BUILD_ROOT%{_miconsdir}/mandrakeupdate.png
cp pixmaps/mandrakeupdate32.png $RPM_BUILD_ROOT%{_iconsdir}/mandrakeupdate.png
cp pixmaps/mandrakeupdate48.png $RPM_BUILD_ROOT%{_liconsdir}/mandrakeupdate.png
cp pixmaps/rpmdrake16.png $RPM_BUILD_ROOT%{_miconsdir}/rpmdrake.png
cp pixmaps/rpmdrake32.png $RPM_BUILD_ROOT%{_iconsdir}/rpmdrake.png
cp pixmaps/rpmdrake48.png $RPM_BUILD_ROOT%{_liconsdir}/rpmdrake.png

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
%doc COPYING AUTHORS
%{_sbindir}/rpmdrake*
%{_sbindir}/MandrakeUpdate
%{_sbindir}/edit-urpm-sources.pl
%{_datadir}/rpmdrake
%{perl_vendorlib}/*.pm
%{_menudir}/%{name}
%{_iconsdir}/*.png
%{_miconsdir}/*.png
%{_liconsdir}/*.png
%ghost /var/lib/urpmi/compssUsers.flat

%files -n grpmi -f grpmi.lang
%defattr(-, root, root)
%doc COPYING AUTHORS
%{_sbindir}/grpmi
%{perl_vendorarch}/auto/*
%{perl_vendorarch}/*.pm

%changelog
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
