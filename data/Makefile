PREFIX = /usr/local
DATADIR = $(PREFIX)/share
BINDIR = $(PREFIX)/bin

rpmdrake_dir = $(DATADIR)/rpmdrake

DESKTOP_IN := $(wildcard *.desktop.in)
DESKTOP = $(DESKTOP_IN:.desktop.in=.desktop)

all: $(DESKTOP)

clean:
	rm -f $(DESKTOP)

install: all
	install -d $(rpmdrake_dir)/desktop
	install -m644 $(DESKTOP) $(rpmdrake_dir)/desktop


%.desktop:   %.desktop.in
	../po/intltool-merge --utf8 ../po $< $@ -d -u -c ../po/.intltool-merge-cache

