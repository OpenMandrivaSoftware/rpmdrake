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

DIRS = curl_download rpm po

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
SBINDIR = $(PREFIX)/sbin

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
	install grpmi.pl $(SBINDIR)/grpmi
	perl -pi -e 's|use strict.*||' $(SBINDIR)/grpmi
	perl -pi -e 's|use vars.*||' $(SBINDIR)/grpmi
	perl -pi -e 's|use diagnostics.*||' $(SBINDIR)/grpmi

clean: 
	@for n in $(DIRS); do \
		(cd $$n; make clean) \
	done
