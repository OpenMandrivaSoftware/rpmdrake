package curl_download;

use strict;
use MDK::Common;
use urpm::download;

require DynaLoader;

our @ISA = qw(DynaLoader);
our @EXPORT = qw(download readproxy writeproxy);
our $VERSION = '1.1';

bootstrap curl_download $VERSION;

sub readproxy (;$) {
    my $proxy = get_proxy(@_);
    ($proxy->{http_proxy} || $proxy->{ftp_proxy} || '',
	defined $proxy->{user} ? "$proxy->{user}:$proxy->{pwd}" : '');
}

sub writeproxy {
    my ($proxy, $proxy_user) = @_;
    my ($user, $pwd) = split /:/, $proxy_user;
    set_proxy_config(user => $user);
    set_proxy_config(pwd => $pwd);
    set_proxy_config(http_proxy => $proxy);
    dump_proxy_config();
}

sub download {
    my ($url, $location, $downloadprogress_callback) = @_;

    download_real($url, $location, $downloadprogress_callback, readproxy());
}

1;
