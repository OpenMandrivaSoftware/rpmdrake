use ExtUtils::MakeMaker;
use Config;


system("curl-config --libs 2>/dev/null 1>/dev/null") == 0
  or
  die_('CURL development environment seems to be missing (curl-config command reports an error)');


WriteMakefile(
    'NAME'         => 'curl_download',
    'LIBS'         => [ chomp_(`curl-config --libs`) ],
    'VERSION_FROM' => 'curl_download.pm', # finds VERSION
    'OBJECT'       => 'curl_download.o',
    'INC'          => '-I.',
    'OPTIMIZE'     => '-O2 -Wall -Werror',
    'MAKEFILE'     => 'Makefile_c',
);



sub chomp_ { my @l = map { my $l = $_; chomp $l; $l } @_; wantarray ? @l : $l[0] }
sub die_ { die "\n   **ERROR**: @_\n\n" }
