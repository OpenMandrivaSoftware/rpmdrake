PL_FILES = ../grpmi.pl
PL_CFILES = $(PL_FILES:%=%_.c)

CFILES = ../curl_download/curl_download.xs ../rpm/grpmi_rpm.xs

POFILES = $(shell ls *.po)
MOFILES = $(POFILES:%.po=%.mo)
LANGS = $(POFILES:%.po=%)

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
LOCALEDIR=$(DATADIR)/locale

CFILES =  ../curl_download/curl_download.xs ../rpm/grpmi_rpm.xs

all: $(MOFILES)

%.mo: %.po
	msgfmt -o $@ $<

$(PL_CFILES): %_.c: %
	./fake_c.pl $< > $@

%.mo: %.po
	msgfmt -o $@ $<

merge: grpmi.pot
	@for n in $(POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

grpmi.pot: $(PL_CFILES) $(CFILES)
	xgettext -F -n --add-comments='-PO' --keyword=_ --language=C -o $@ $(PL_CFILES) $(CFILES)

install:
	for l in $(LANGS); do \
		install -d $(LOCALEDIR)/$$l/LC_MESSAGES; \
		install -m 644 $$l.mo $(LOCALEDIR)/$$l/LC_MESSAGES/grpmi.mo; \
	done

clean:
	@rm -rf *.mo $(POFILES:%=%t) $(PL_CFILES) grpmi.pot
