package curl_download;

use strict;
use vars qw($VERSION @ISA @EXPORT);
use MDK::Common;

require DynaLoader;

@ISA = qw(DynaLoader);
@EXPORT = qw(download readproxy writeproxy);
$VERSION = '1.0';

bootstrap curl_download $VERSION;

sub readproxy {
    my ($proxy, $proxy_user);
    foreach (cat_('/etc/urpmi/proxy.cfg')) {
	/^http_proxy\s*=\s*(.*)$/ and $proxy = $1;
	/^ftp_proxy\s*=\s*(.*)$/ and $proxy = $1;
	/^proxy_user\s*=\s*(.*)$/ and $proxy_user = $1;
    }
    ($proxy, $proxy_user);
}

sub writeproxy {
    my ($proxy, $proxy_user) = @_;
    my $f = '/etc/urpmi/proxy.cfg'; 
    output($f,
	   if_($proxy, "http_proxy=$proxy\n"),
	   if_($proxy_user, "proxy_user=$proxy_user\n"));
    chmod 0600, $f;
}

sub download {
    my ($url, $location, $downloadprogress_callback) = @_;

    download_real($url, $location, $downloadprogress_callback, readproxy());
}

1;

