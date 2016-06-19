VERSION = 6.01
NAME = rpmdrake

DIRS = po polkit data mime

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
BINDIR = $(PREFIX)/bin
SBINDIR = $(PREFIX)/sbin
LIBEXECDIR = $(PREFIX)/libexec
RPM=$(shell rpm --eval %_topdir)
PERL_VENDORLIB=$(DESTDIR)/$(shell perl -V:installvendorlib | perl -pi -e "s/.*=//; s/[;']//g")

all: dirs

dirs:
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || make -C $$n || exit 1 ;\
	done

install: $(ALL)
	find -name '*.pm' -o -name rpmdrake -o -name OnlineUpdate | xargs ./simplify-drakx-modules
	./simplify-drakx-modules {gurpmi.addmedia,edit-urpm-sources.pl}
	@for n in $(DIRS); do make -C $$n install; done
	install -d $(BINDIR) $(SBINDIR) $(LIBEXECDIR)
	install rpmdrake $(LIBEXECDIR)/drakrpm
	install OnlineUpdate $(LIBEXECDIR)/drakrpm-update
	install gurpmi.addmedia $(LIBEXECDIR)/drakrpm-addmedia
	install edit-urpm-sources.pl $(LIBEXECDIR)/drakrpm-editmedia
	ln -sf drakrpm-update $(BINDIR)/OnlineUpdate
	ln -sf drakrpm-update $(BINDIR)/drakrpm-update
	ln -sf drakrpm-editmedia $(BINDIR)/drakrpm-edit-media
	ln -sf drakrpm-addmedia $(BINDIR)/gurpmi.addmedia
	ln -sf drakrpm-editmedia $(BINDIR)/edit-urpm-sources.pl
	ln -sf drakrpm $(BINDIR)/rpmdrake
	install -d $(DATADIR)/rpmdrake/icons
	install -m644 icons/*.png $(DATADIR)/rpmdrake/icons
	install -m644 gui.lst $(DATADIR)/rpmdrake
	mkdir -p $(PERL_VENDORLIB)/Rpmdrake
	install -m 644 rpmdrake.pm $(PERL_VENDORLIB)
	install -m 644 Rpmdrake/*.pm $(PERL_VENDORLIB)/Rpmdrake
	perl -pi -e "s/version = 1/version = \'$(VERSION)'/" $(PERL_VENDORLIB)/Rpmdrake/init.pm

clean:
	@for n in $(DIRS); do make -C $$n clean; done

dis: dist
dist:
	rm -rf $(NAME)-$(VERSION).tar*
	@git archive --prefix=$(NAME)-$(VERSION)/ HEAD | xz  > $(NAME)-$(VERSION).tar.xz;
	$(info $(NAME)-$(VERSION).tar.xz is ready)

gui.lst:
	export LC_COLLATE=C; ( echo -e "calligra\nlibreoffice\nVMware-Player" ; \
	urpmf "/usr/share/((applnk|applications(|/kde)|apps/kicker/applets)/|kde4/services/plasma-applet|xsessions).*.desktop" |sed -e 's!:.*!!') \
	 | sort -u > gui.lst

check:
	rm -f po/*.pot
	@make -C po clean
	@make -C po rpmdrake.pot

.PHONY: gui.lst
