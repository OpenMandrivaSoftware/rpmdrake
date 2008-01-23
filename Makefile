VERSION = 3.127
NAME = rpmdrake

DIRS = grpmi po data mime

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
BINDIR = $(PREFIX)/bin
SBINDIR = $(PREFIX)/sbin
RELATIVE_SBIN = ../sbin
RPM=$(shell rpm --eval %_topdir)
PERL_VENDORLIB=$(DESTDIR)/$(shell perl -V:installvendorlib   | perl -pi -e "s/.*=//; s/[;']//g")
PERL_VENDORARCH=$(DESTDIR)/$(shell perl -V:installvendorarch | perl -pi -e "s/.*=//; s/[;']//g")

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
	install rpmdrake MandrivaUpdate edit-urpm-sources.pl gurpmi.addmedia $(SBINDIR)
	ln -sf rpmdrake $(SBINDIR)/rpmdrake-remove
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
	mkdir -p $(PERL_VENDORLIB)/Rpmdrake
	install -m 644 rpmdrake.pm $(PERL_VENDORLIB)
	install -m 644 Rpmdrake/*.pm $(PERL_VENDORLIB)/Rpmdrake
	perl -pi -e "s/version = 1/version=$(VERSION)/" $(PERL_VENDORLIB)/Rpmdrake/init.pm

clean:
	@for n in $(DIRS); do \
		make -C $$n clean; \
	done

dis: clean
	rm -rf $(NAME)-$(VERSION) ../$(NAME)-$(VERSION).tar*
	svn export -q -rBASE . $(NAME)-$(VERSION)
	find $(NAME)-$(VERSION) -name .cvsignore |xargs rm -rf
	tar cf ../$(NAME)-$(VERSION).tar $(NAME)-$(VERSION)
	bzip2 -9f ../$(NAME)-$(VERSION).tar
	rm -rf $(NAME)-$(VERSION)

.PHONY: ChangeLog log changelog

log: ChangeLog

changelog: ChangeLog

ChangeLog:
	svn2cl --accum --authors ../../soft/common/username.xml
	rm -f *.bak
