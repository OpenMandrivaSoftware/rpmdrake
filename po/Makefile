# the domain name for gettext
PGOAL = rpmdrake

# perl files to search translatable strings in
PL_FILES = ../rpmdrake ../edit-urpm-sources.pl ../rpmdrake.pm
CFILES = ../grpmi/curl_download/curl_download.xs

POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

# because of different charsets or encodings.. :-(
IGNOREPOMS = zh_CN.po

PREFIX = $(RPM_BUILD_ROOT)/usr
DATADIR = $(PREFIX)/share
LOCALEDIR=$(DATADIR)/locale

all: $(MOFILES)

%.mo: %.po
	if [ -z "`echo $(IGNOREPOMS) | grep $<`" ]; then cat $< "$<"m >> "$<"f; else cp $< "$<"f; fi
	./clean_po.pl "$<"f > "$<"g
	msgfmt -o $@ "$<"g

merge: $(PGOAL).pot
	@for n in $(POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
		./get_from_compssusers.pl "$$n" > "$$n"m; \
	done

$(PGOAL).pot: $(PL_FILES) $(CFILES)
	INTLTOOL_EXTRACT=./intltool-extract ./intltool-update --gettext-package desktopstuff --pot
	perl_checker -q --generate-pot rpmdrake_tmp.pot $(PL_FILES)
	xgettext -F -n --add-comments='-PO' \
		--keyword=_ --keyword=__ --keyword=N_ --keyword=N \
		--language=C -o rpmdrake_tmp_c.pot $(CFILES)
	msgcat --use-first rpmdrake_tmp.pot rpmdrake_tmp_c.pot desktopstuff.pot > $@
	rm -f desktopstuff.pot rpmdrake_tmp.pot rpmdrake_tmp_c.pot

install:
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/$(PGOAL).mo; \
	done

clean:
	@rm -rf *.mo *.pof *.pog $(POFILES:%=%t) $(PL_CFILES) $(PGOAL).pot desktopstuff.pot rpmdrake_tmp.pot

