VERSION = $(shell awk '/define version/ { print $$3 }' $(NAME).spec)
NAME = rpmdrake

DIRS = grpmi po data

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
BINDIR = $(PREFIX)/bin
SBINDIR = $(PREFIX)/sbin
RELATIVE_SBIN = ../sbin
RPM=$(shell rpm --eval %_topdir)

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
	ln -sf $(RELATIVE_SBIN)/MandrivaUpdate $(SBINDIR)/drakrpm-update
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
	svn2cl --accum --authors ../../soft/common/username.xml
	rm -f *.bak
