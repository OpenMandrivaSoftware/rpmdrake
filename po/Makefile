# the domain name for gettext
PGOAL = rpmdrake

# perl files to search translatable strings in
PL_FILES = ../rpmdrake ../edit-urpm-sources.pl ../rpmdrake.pm
# C-like files to search translatable strings in
#CFILES = 

PL_CFILES = $(PL_FILES:%=%_.c)
POFILES = $(shell ls *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

PREFIX = $(RPM_BUILD_ROOT)/usr
DATADIR = $(PREFIX)/share
LOCALEDIR=$(DATADIR)/locale

all: $(PGOAL).pot $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

$(PL_CFILES): %_.c: %
	../grpmi/po/fake_c.pl $< > $@

%.mo: %.po
	msgfmt -o $@ $<

merge: $(PGOAL).pot
	@for n in $(POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

$(PGOAL).pot: $(PL_CFILES) $(CFILES)
	xgettext -F -n --add-comments='-PO' \
	--keyword=_ --keyword=__ --keyword=N_ \
	--language=C -o $@ $(PL_CFILES) $(CFILES)
	@rm -rf $(PL_CFILES)

install:
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(PGOAL).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t) $(PL_CFILES) $(PGOAL).pot

