# the domain name for gettext
PGOAL = grpmi

# C-like files to search translatable strings in
CFILES = ../curl_download/curl_download.xs

POFILES = $(shell ls *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

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

$(PGOAL).pot: $(CFILES)
	perl_checker -q --generate-pot grpmi_tmp.pot $(PL_FILES)
	xgettext -F -n --add-comments='-PO' \
	--keyword=_ --keyword=__ --keyword=N_ --keyword=N \
	--language=C -o grpmi_tmp_c.pot $(CFILES)
	msgcat --use-first grpmi_tmp_c.pot grpmi_tmp.pot > $@
	rm -f grpmi_tmp_c.pot grpmi_tmp.pot

install:
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(PGOAL).mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t) $(PL_CFILES) $(PGOAL).pot grpmi_tmp_c.pot grpmi_tmp.pot

