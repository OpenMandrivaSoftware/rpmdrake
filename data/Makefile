PREFIX = /usr/local
DATADIR = $(PREFIX)/share
BINDIR = $(PREFIX)/bin

rpmdrake_dir = $(DATADIR)/rpmdrake

DIRECTORY_IN := $(wildcard *.directory.in)
DIRECTORY = $(DIRECTORY_IN:.directory.in=.directory)

DESKTOP_IN := $(wildcard *.desktop.in)
DESKTOP = $(DESKTOP_IN:.desktop.in=.desktop)

all: $(DIRECTORY) $(DESKTOP)

clean:
	rm -f $(DIRECTORY) $(DESKTOP)

install: all
	install -d $(rpmdrake_dir)/desktop
	install -m644 $(DESKTOP) $(DIRECTORY) $(rpmdrake_dir)/desktop


%.desktop:   %.desktop.in
	../po/intltool-merge --utf8 ../po $< $@ -d -u -c ../po/.intltool-merge-cache
%.directory: %.directory.in
	../po/intltool-merge --utf8 ../po $< $@ -d -u -c ../po/.intltool-merge-cache

