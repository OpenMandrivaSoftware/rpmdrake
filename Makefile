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

DIRS = grpmi po data

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
BINDIR = $(PREFIX)/bin
SBINDIR = $(PREFIX)/sbin
RELATIVE_SBIN = ../sbin

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
	install rpmdrake edit-urpm-sources.pl $(SBINDIR)
	perl -pi -e 's|use strict.*||;s|use vars.*||;s|use diagnostics.*||;s|#-.*||' $(SBINDIR)/*
	ln -s -f rpmdrake $(SBINDIR)/rpmdrake-remove
	ln -s -f rpmdrake $(SBINDIR)/MandrakeUpdate
	install -d $(BINDIR)
	ln -sf $(RELATIVE_SBIN)/rpmdrake $(BINDIR)/rpmdrake
	ln -sf $(RELATIVE_SBIN)/rpmdrake-remove $(BINDIR)/rpmdrake-remove
	ln -sf $(RELATIVE_SBIN)/MandrakeUpdate $(BINDIR)/MandrakeUpdate
	ln -sf $(RELATIVE_SBIN)/edit-urpm-sources.pl $(BINDIR)/edit-urpm-sources.pl
	install -d $(DATADIR)/rpmdrake/icons
	install -m644 icons/*.png $(DATADIR)/rpmdrake/icons
	@for i in icons/title/*; do \
		install -d $(DATADIR)/rpmdrake/$$i; \
		install -m644 $$i/*.png $(DATADIR)/rpmdrake/$$i; \
	done
	install -m644 compssUsers.flat.default $(DATADIR)/rpmdrake

clean: 
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done

tar:
	mkdir ../t; \
	cd ../t; \
	cp -a ../rpmdrake .; \
	find -name "CVS" | xargs rm -rf; \
	tar jcvf ../rpmdrake.tar.bz2 rpmdrake; \
	cd ..; \
	rm -rf t

clust:
	scp ../rpmdrake.tar.bz2 bi:rpm/SOURCES
	scp rpmdrake.spec bi:rpm/SPECS

SOFTHOME = /home/gc/cvs/soft
GIHOME = /home/gc/cvs/gi

hack:
	cp -f $(SOFTHOME)/rpmdrake/rpmdrake $(SOFTHOME)/rpmdrake/edit-urpm-sources.pl /usr/sbin
	cp -f $(SOFTHOME)/rpmdrake/rpmdrake.pm $(shell rpm --eval %perl_vendorlib)
	cp -f $(GIHOME)/perl-install/my_gtk.pm $(GIHOME)/perl-install/ugtk.pm /usr/lib/libDrakX
#	perl -pi -e 's|use strict.*||;s|use vars.*||;s|use diagnostics.*||' /usr/lib/libDrakX/*.pm /usr/sbin/{rpmdrake,edit-urpm-sources.pl}
