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

all: dirs

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n || exit 1 ;\
	done

install: $(ALL)
	@for n in $(DIRS); do \
		(cd $$n; $(MAKE) install) \
	done
	install -d $(BINDIR)
	install rpmdrake edit-urpm-sources.pl $(BINDIR)
	perl -pi -e 's|use strict.*||;s|use vars.*||;s|use diagnostics.*||;s|#-.*||' $(BINDIR)/*
	ln -s -f rpmdrake $(BINDIR)/rpmdrake-remove
	ln -s -f rpmdrake $(BINDIR)/MandrakeUpdate
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
