 #******************************************************************************
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 #
 # Copyright 2002 MandrakeSoft
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 #
 #*****************************************************************************

VERSION = $(shell awk '/define version/ { print $$3 }' $(NAME).spec)
NAME = rpmdrake

DIRS = grpmi po data

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
BINDIR = $(PREFIX)/bin
SBINDIR = $(PREFIX)/sbin
RELATIVE_SBIN = ../sbin
RPM=$(HOME)/rpm

all: dirs

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n || exit 1 ;\
	done

install: $(ALL)
	@for n in $(DIRS); do \
		(cd $$n; $(MAKE) install) \
	done
	install -d $(SBINDIR)
	install rpmdrake park-rpmdrake edit-urpm-sources.pl gurpmi.addmedia $(SBINDIR)
	perl -pi -e 's|use strict.*||;s|use vars.*||;s|use diagnostics.*||;s|#-.*||' $(SBINDIR)/*
	ln -sf rpmdrake $(SBINDIR)/rpmdrake-remove
	ln -sf rpmdrake $(SBINDIR)/MandrivaUpdate
	install -d $(BINDIR)
	ln -sf $(RELATIVE_SBIN)/rpmdrake $(BINDIR)/rpmdrake
	ln -sf $(RELATIVE_SBIN)/rpmdrake-remove $(BINDIR)/rpmdrake-remove
	ln -sf $(RELATIVE_SBIN)/MandrivaUpdate $(BINDIR)/MandrivaUpdate
	ln -sf $(RELATIVE_SBIN)/edit-urpm-sources.pl $(BINDIR)/edit-urpm-sources.pl
	ln -sf edit-urpm-sources.pl $(SBINDIR)/drakrpm-edit-media
	ln -sf $(RELATIVE_SBIN)/drakrpm-edit-media $(BINDIR)/drakrpm-edit-media
	ln -sf $(RELATIVE_SBIN)/gurpmi.addmedia $(BINDIR)/gurpmi.addmedia
	ln -sf $(RELATIVE_SBIN)/rpmdrake $(BINDIR)/drakrpm
	ln -sf $(RELATIVE_SBIN)/rpmdrake-remove $(BINDIR)/drakrpm-remove
	ln -sf $(RELATIVE_SBIN)/MandrivaUpdate $(BINDIR)/drakrpm-update
	ln -sf $(RELATIVE_SBIN)/drakrpm-update $(BINDIR)/drakrpm-update
	install -d $(DATADIR)/rpmdrake/icons
	install -m644 icons/*.png $(DATADIR)/rpmdrake/icons
	install -m644 compssUsers.flat.default $(DATADIR)/rpmdrake

clean: 
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done

tar:
	mkdir ../t; \
	cd ../t; \
	cp -a ../rpmdrake .; \
	mv rpmdrake rpmdrake-$(VERSION); \
	find -name "CVS" | xargs rm -rf; \
	tar jcvf ../rpmdrake-$(VERSION).tar.bz2 rpmdrake-$(VERSION); \
	cd ..; \
	rm -rf t

clust:
	scp ../rpmdrake-$(VERSION).tar.bz2 bi:rpm/SOURCES/rpmdrake-$(VERSION).tar.bz2
	rm -f scp ../rpmdrake-$(VERSION).tar.bz2
	scp rpmdrake.spec bi:rpm/SPECS

SOFTHOME = /home/gc/cvs/soft
GIHOME = /home/gc/cvs/gi

hack:
	cp -f $(SOFTHOME)/rpmdrake/rpmdrake $(SOFTHOME)/rpmdrake/edit-urpm-sources.pl $(SOFTHOME)/rpmdrake/gurpmi.addmedia /usr/sbin
	ln -sf edit-urpm-sources.pl /usr/sbin/edit-urpm-media
	cp -f $(SOFTHOME)/rpmdrake/rpmdrake.pm $(shell rpm --eval %perl_vendorlib)
	cp -f $(GIHOME)/perl-install/ugtk2.pm /usr/lib/libDrakX
	perl -pi -e 's|use strict.*||;s|use vars.*||;s|use diagnostics.*||' /usr/lib/libDrakX/*.pm /usr/sbin/{rpmdrake,edit-urpm-sources.pl}




dis: clean
	rm -rf $(NAME)-$(VERSION) ../$(NAME)-$(VERSION).tar*
	mkdir -p $(NAME)-$(VERSION)
	find . -not -name "$(NAME)-$(VERSION)"|cpio -pd $(NAME)-$(VERSION)/
	find $(NAME)-$(VERSION) -type d -name CVS -o -name .cvsignore |xargs rm -rf
	tar cf ../$(NAME)-$(VERSION).tar $(NAME)-$(VERSION)
	bzip2 -9f ../$(NAME)-$(VERSION).tar
	rm -rf $(NAME)-$(VERSION)

srpm: dis ../$(NAME)-$(VERSION).tar.bz2 $(RPM)
	cp -f ../$(NAME)-$(VERSION).tar.bz2 $(RPM)/SOURCES
	cp -f $(NAME).spec $(RPM)/SPECS/
	rm -f ../$(NAME)-$(VERSION).tar.bz2
	rpm -bs $(NAME).spec

rpm: srpm
	rpm -bb --clean --rmsource $(NAME).spec

.PHONY: ChangeLog
ChangeLog:
	cvs2cl -W 400 -I Changelog --accum -U ../../soft/common/username
	rm -f *.bak
