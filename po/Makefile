PL_FILES = ../rpmdrake ../edit-urpm-sources.pl ../rpmdrake.pm
PL_CFILES = $(PL_FILES:%=%_.c)

POFILES = $(shell ls *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
LOCALEDIR=$(DATADIR)/locale

all: $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

$(PL_CFILES): %_.c: %
	../grpmi/po/fake_c.pl $< > $@

%.mo: %.po
	msgfmt -o $@ $<

merge: rpmdrake.pot
	@for n in $(POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

rpmdrake.pot: $(PL_CFILES)
	xgettext -F -n --add-comments='-PO' --keyword=_ --language=C -o $@ $(PL_CFILES)

install:
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/rpmdrake.mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t) $(PL_CFILES) rpmdrake.pot
