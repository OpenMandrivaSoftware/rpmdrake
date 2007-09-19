# the domain name for gettext
PGOAL = rpmdrake

# perl files to search translatable strings in
PL_FILES = ../rpmdrake ../edit-urpm-sources.pl ../rpmdrake.pm ../gurpmi.addmedia ../Rpmdrake/*.pm ../MandrivaUpdate
CFILES = ../grpmi/curl_download/curl_download.xs

POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

top_srcdir=..
PREFIX = $(RPM_BUILD_ROOT)/usr
DATADIR = $(PREFIX)/share
LOCALEDIR=$(DATADIR)/locale

all: $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

merge: $(PGOAL).pot
	@for n in $(POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

$(PGOAL).pot: $(PL_FILES) $(CFILES)
	intltool-update --gettext-package desktopstuff --pot
	perl_checker -q --generate-pot $(PGOAL)_tmp.pot $(PL_FILES)
	xgettext -F -n --add-comments='-PO' \
		--keyword=_ --keyword=__ --keyword=N_ --keyword=N \
		--language=C -o $(PGOAL)_tmp_c.pot $(CFILES)
	msgcat --use-first $(PGOAL)_tmp.pot $(PGOAL)_tmp_c.pot desktopstuff.pot > $@
	rm -f desktopstuff.pot $(PGOAL)_tmp.pot $(PGOAL)_tmp_c.pot

install:
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(PGOAL).mo; \
	done

clean:
	@rm -rf *.mo *.pof *.pog $(POFILES:%=%t) $(PL_CFILES) desktopstuff.pot $(PGOAL)_tmp.pot

