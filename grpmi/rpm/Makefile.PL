use ExtUtils::MakeMaker;
use Config;

my $rpm_cflags = '-I/usr/include/rpm';
my $rpm_libs   = '-lrpm -lrpmdb -lrpmio -lpopt';

ccompile('#include <rpm/rpmlib.h>
          #include <rpm/misc.h>
         ',
	 'rpmdb db;',
	 $rpm_cflags,
	 $rpm_libs)
  or
  die_('rpm devel environment is needed');


WriteMakefile(
    'NAME'         => 'grpmi_rpm',
    'LIBS'         => [ $rpm_libs ],
    'VERSION_FROM' => 'grpmi_rpm.pm', # finds VERSION
    'OBJECT'       => 'grpmi_rpm.o',
    'INC'          => $rpm_cflags,
    'OPTIMIZE'     => '-O2 -Wall -Werror -g',
    'MAKEFILE'     => 'Makefile_c',
);




# Taken from Makefile.PL from Gtk-Perl
sub ccompile {
	my ($headers, $main, $cflags, $libs) = @_;
	my $fname = "temctest";
	my $r;
	chomp($cflags, $libs);
	open(CTEST, ">$fname.c") || return 0;
	print CTEST <<"EOTEST";
$headers

int main (int argc, char* argv[]) {
$main;
}
EOTEST
	close(CTEST);
	$r = system("$Config{cc} -o $fname $fname.c $cflags $libs 2>/dev/null 1>/dev/null");
	warn("RUNNING: $Config{cc} -o $fname $fname.c $cflags $libs\n") if $ENV{VERBOSE};
	unlink($fname, "$fname.c");
	return $r == 0;
}

sub chomp_ { my @l = map { my $l = $_; chomp $l; $l } @_; wantarray ? @l : $l[0] }
sub die_ { die "\n   **ERROR**: @_\n\n" }
