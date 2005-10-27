use ExtUtils::MakeMaker;

my $libs = `curl-config --libs`;
$? == 0 or die "CURL development environment seems to be missing (curl-config command reports an error)\n";
chomp $libs;

WriteMakefile(
    'NAME'         => 'curl_download',
    'LIBS'         => [ $libs ],
    'VERSION_FROM' => 'curl_download.pm', # finds VERSION
    'OBJECT'       => 'curl_download.o',
    'INC'          => '-I.',
    'OPTIMIZE'     => '-O2 -Wall -Werror',
    'MAKEFILE'     => 'Makefile_c',
);
