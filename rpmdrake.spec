%define name rpmdrake
%define version 2.0
%define release 2mdk

Name: %{name}
Version: %{version}
Release: %{release}
License: GPL
Source0: rpmdrake.tar.bz2
Summary: Mandrake Linux graphical front end for choosing packages for installion/removal
Requires: perl-MDK-Common urpmi >= 3.9 perl-URPM >= 0.50 drakxtools >= 1.1.9 grpmi >= 9.0
BuildRequires: curl-devel rpm-devel
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Group: System/Configuration/Packaging
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
?package(%{name}): command="/usr/sbin/rpmdrake" needs="x11" section="Configuration/Packaging" icon="rpmdrake.xpm"\
title="Install Software" longtitle="A graphical front end for installing packages"
?package(%{name}): command="/usr/sbin/rpmdrake-remove" needs="x11" section="Configuration/Packaging" icon="rpmdrake.xpm"\
title="Remove Software" longtitle="A graphical front end for removing packages"
?package(%{name}): command="/usr/sbin/MandrakeUpdate" needs="x11" section="Configuration/Packaging" icon="mandrakeupdate.xpm"\
title="Mandrake Update" longtitle="A graphical front end for software updates"
?package(%{name}): command="/usr/sbin/edit-urpm-sources.pl" needs="x11" section="Configuration/Packaging" icon="rpmdrake.xpm"\
title="Edit Software Sources" longtitle="A graphical front end to add/remove/edit sources for installing packages"
EOF

mkdir -p $RPM_BUILD_ROOT{%{_miconsdir},%{_liconsdir}}
cp pixmaps/mandrakeupdate16.xpm $RPM_BUILD_ROOT%{_miconsdir}/mandrakeupdate.xpm
cp pixmaps/mandrakeupdate32.xpm $RPM_BUILD_ROOT%{_iconsdir}/mandrakeupdate.xpm
cp pixmaps/mandrakeupdate48.xpm $RPM_BUILD_ROOT%{_liconsdir}/mandrakeupdate.xpm
cp pixmaps/rpmdrake16.xpm $RPM_BUILD_ROOT%{_miconsdir}/rpmdrake.xpm
cp pixmaps/rpmdrake32.xpm $RPM_BUILD_ROOT%{_iconsdir}/rpmdrake.xpm
cp pixmaps/rpmdrake48.xpm $RPM_BUILD_ROOT%{_liconsdir}/rpmdrake.xpm

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
%{_iconsdir}/*.xpm
%{_miconsdir}/*.xpm
%{_liconsdir}/*.xpm

%files -n grpmi -f grpmi.lang
%defattr(-, root, root)
%doc COPYING AUTHORS
%{_sbindir}/grpmi
%{perl_vendorarch}/auto/*
%{perl_vendorarch}/*.pm

%changelog
* Fri Aug  2 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-2mdk
- workaround packdrake segfault when hdlist is not available for
  a source (by file testing if the hdlist is readable)

* Thu Aug  1 2002 Guillaume Cottenceau <gc@mandrakesoft.com> 2.0-1mdk
- c'mon rpmdrake, strike back in Perl!
