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

DIRS = grpmi po

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
	perl -pi -e 's|use strict.*||' $(BINDIR)/*
	perl -pi -e 's|use vars.*||' $(BINDIR)/*
	perl -pi -e 's|use diagnostics.*||' $(BINDIR)/*
	ln -s rpmdrake $(BINDIR)/rpmdrake-remove
	ln -s rpmdrake $(BINDIR)/MandrakeUpdate
	install -d $(DATADIR)/rpmdrake/icons
	install -m644 icons/* $(DATADIR)/rpmdrake/icons

clean: 
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done

tar:
	mkdir -p t/rpmdrake; \
	cd t/rpmdrake; \
	cp -a ../../* .; \
	find -name "CVS" | xargs rm -rf; \
	cd ..; \
	tar jcvf ../rpmdrake.tar.bz2 rpmdrake; \
	cd ..; \
	rm -rf t
