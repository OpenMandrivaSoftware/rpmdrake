/* -*- c -*-
 *
 * Copyright (c) 2002 Guillaume Cottenceau (gc at mandrakesoft dot com)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2, as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 ******************************************************************************/

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <curl/curl.h>
#include <curl/easy.h>

#include <libintl.h>
#undef _
#define _(arg) dgettext("grpmi", arg)

char * my_asprintf(char *msg, ...)
{
	char * out;
	va_list args;
	va_start(args, msg);
	if (vasprintf(&out, msg, args) == -1)
		out = "";
	va_end(args);
	return out;
}


SV * downloadprogress_callback_sv = NULL;

int my_progress_func(void *ptr, double td, double dd, double tu, double du)
{
	dSP;
	if (!downloadprogress_callback_sv)
		return 0;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
  	XPUSHs(sv_2mortal(newSVnv(td)));
  	XPUSHs(sv_2mortal(newSVnv(dd)));
  	PUTBACK;
  	perl_call_sv(downloadprogress_callback_sv, G_DISCARD);
	FREETMPS;
	LEAVE;
	return 0;
}

char * download_url_real(char * url, char * location, char * proxy, char * proxy_user)
{
	CURL *curl;
	CURLcode rescurl = CURL_LAST;

	if ((curl = curl_easy_init())) {
		char * outfilename;
		struct stat statbuf;
		char * filename = basename(url);
		FILE * outfile;

		if (stat(location, &statbuf) || !S_ISDIR(statbuf.st_mode))
			return _("Directory where to put download must be existing");

		if (asprintf(&outfilename, "%s/%s", location, filename) == -1)
			return _("Out of memory\n");

		if (!stat(outfilename, &statbuf) && S_ISREG(statbuf.st_mode)) {
			curl_easy_setopt(curl, CURLOPT_RESUME_FROM, statbuf.st_size);
		} else {
			unlink(outfilename);
			curl_easy_setopt(curl, CURLOPT_RESUME_FROM, 0);
		}
	
		outfile = fopen(outfilename, "a");
		free(outfilename);

		if (!outfile)
			return _("Could not open output file in append mode");

		curl_easy_setopt(curl, CURLOPT_URL, url);
		curl_easy_setopt(curl, CURLOPT_FILE, outfile);
		curl_easy_setopt(curl, CURLOPT_NOPROGRESS, FALSE);
		curl_easy_setopt(curl, CURLOPT_PROGRESSFUNCTION, my_progress_func);

		if (proxy && strcmp(proxy, ""))
			curl_easy_setopt(curl, CURLOPT_PROXY, proxy);
		if (proxy_user && strcmp(proxy_user, ""))
			curl_easy_setopt(curl, CURLOPT_PROXYUSERPWD, proxy_user);

		rescurl = curl_easy_perform(curl);

		if (rescurl == CURLE_ALREADY_COMPLETE)
			rescurl = CURLE_OK;
	
		fclose(outfile);
		curl_easy_cleanup(curl);
	}
	
	if (rescurl != CURLE_OK) {
		switch (rescurl) {
		case CURLE_UNSUPPORTED_PROTOCOL:
			return _("Unsupported protocol\n");
			break;
		case CURLE_FAILED_INIT:
			return _("Failed init\n");
			break;
		case CURLE_URL_MALFORMAT:
			return _("Bad URL format\n");
			break;
		case CURLE_URL_MALFORMAT_USER:
			return _("Bad user format in URL\n");
			break;
		case CURLE_COULDNT_RESOLVE_PROXY:
			return _("Couldn't resolve proxy\n");
			break;
		case CURLE_COULDNT_RESOLVE_HOST:
			return _("Couldn't resolve host\n");
			break;
		case CURLE_COULDNT_CONNECT:
			return _("Couldn't connect\n");
			break;
		case CURLE_FTP_WEIRD_SERVER_REPLY:
			return _("Ftp weird server reply\n");
			break;
		case CURLE_FTP_ACCESS_DENIED:
			return _("Ftp access denied\n");
			break;
		case CURLE_FTP_USER_PASSWORD_INCORRECT:
			return _("Ftp user password incorrect\n");
			break;
		case CURLE_FTP_WEIRD_PASS_REPLY:
			return _("Ftp weird PASS reply\n");
			break;
		case CURLE_FTP_WEIRD_USER_REPLY:
			return _("Ftp weird USER reply\n");
			break;
		case CURLE_FTP_WEIRD_PASV_REPLY:
			return _("ftp weird PASV reply\n");
			break;
		case CURLE_FTP_WEIRD_227_FORMAT:
			return _("Ftp weird 227 format\n");
			break;
		case CURLE_FTP_CANT_GET_HOST:
			return _("Ftp can't get host\n");
			break;
		case CURLE_FTP_CANT_RECONNECT:
			return _("Ftp can't reconnect\n");
			break;
		case CURLE_FTP_COULDNT_SET_BINARY:
			return _("Ftp couldn't set binary\n");
			break;
		case CURLE_PARTIAL_FILE:
			return _("Partial file\n");
			break;
		case CURLE_FTP_COULDNT_RETR_FILE:
			return _("Ftp couldn't RETR file\n");
			break;
		case CURLE_FTP_WRITE_ERROR:
			return _("Ftp write error\n");
			break;
		case CURLE_FTP_QUOTE_ERROR:
			/* "quote" is an ftp command, not the typographic things, so
			 * don't translate that word */
			return _("Ftp quote error\n");
			break;
		case CURLE_HTTP_NOT_FOUND:
			return _("http not found\n");
			break;
		case CURLE_WRITE_ERROR:
			return _("Write error\n");
			break;
		case CURLE_MALFORMAT_USER: /* the user name is illegally specified */
			return _("User name illegally specified\n");
			break;
		case CURLE_FTP_COULDNT_STOR_FILE: /* failed FTP upload */
			return _("ftp couldn't STOR file\n");
			break;
		case CURLE_READ_ERROR: /* could open/read from file */
			return _("Read error\n");
			break;
		case CURLE_OUT_OF_MEMORY:
			return _("Out of memory\n");
			break;
		case CURLE_OPERATION_TIMEOUTED: /* the timeout time was reached */
			return _("Time out\n");
			break;
		case CURLE_FTP_COULDNT_SET_ASCII: /* TYPE A failed */
			return _("Ftp couldn't set ASCII\n");
			break;
		case CURLE_FTP_PORT_FAILED: /* FTP PORT operation failed */
			return _("Ftp PORT failed\n");
			break;
		case CURLE_FTP_COULDNT_USE_REST: /* the REST command failed */
			return _("Ftp couldn't use REST\n");
			break;
		case CURLE_FTP_COULDNT_GET_SIZE: /* the SIZE command failed */
			return _("Ftp couldn't get size\n");
			break;
		case CURLE_HTTP_RANGE_ERROR: /* The RANGE "command" didn't seem to work */
			return _("Http range error\n");
			break;
		case CURLE_HTTP_POST_ERROR:
			return _("Http POST error\n");
			break;
		case CURLE_SSL_CONNECT_ERROR: /* something was wrong when connecting with SSL */
			return _("Ssl connect error\n");
			break;
		case CURLE_FTP_BAD_DOWNLOAD_RESUME: /* couldn't resume download */
			return _("Ftp bad download resume\n");
			break;
		case CURLE_FILE_COULDNT_READ_FILE:
			return _("File couldn't read file\n");
			break;
		case CURLE_LDAP_CANNOT_BIND:
			return _("LDAP cannot bind\n");
			break;
		case CURLE_LDAP_SEARCH_FAILED:
			return _("LDAP search failed\n");
			break;
		case CURLE_LIBRARY_NOT_FOUND:
			return _("Library not found\n");
			break;
		case CURLE_FUNCTION_NOT_FOUND:
			return _("Function not found\n");
			break;
		case CURLE_ABORTED_BY_CALLBACK:
			return _("Aborted by callback\n");
			break;
		case CURLE_BAD_FUNCTION_ARGUMENT:
			return _("Bad function argument\n");
			break;
		case CURLE_BAD_CALLING_ORDER:
			return _("Bad calling order\n");
			break;
		default:
			return my_asprintf(_("Unknown error code %d\n"), rescurl);
			break;
		}
	}
	return "";
}


/************************** Gateway to Perl ****************************/

MODULE = curl_download		PACKAGE = curl_download
PROTOTYPES : DISABLE

char *
download_real(url, location, downloadprogress_callback, proxy, proxy_user)
     char * url
     char * location
     SV * downloadprogress_callback
     char * proxy
     char * proxy_user
	CODE:
                downloadprogress_callback_sv = downloadprogress_callback;
                RETVAL = download_url_real(url, location, proxy, proxy_user);
        OUTPUT:
                RETVAL

