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

#define _GNU_SOURCE
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdarg.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#undef Fflush
#undef Mkdir
#undef Stat
#include <rpm/rpmlib.h>
#include <rpm/misc.h>

#include <libintl.h>
#undef _
#define _(arg) dgettext("grpmi", arg)

#define streq !strcmp

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


char * init_rcstuff_(void)
{
	char * rpmrc;
	
	rpmrc = getenv("RPMRC_FILE");
	if (rpmrc && !*rpmrc)
		rpmrc = NULL;
	if (rpmReadConfigFiles(rpmrc, NULL))
		return _("Couldn't read RPM config files");

	return "";
}


/* these are in rpmlib but not in rpmlib.h */
int readLead(FD_t fd, struct rpmlead *lead);
int rpmReadSignature(FD_t fd, Header *header, short sig_type);

char * verify_sig_(char * file)
{
	struct rpmlead lead;
	Header sig;
	HeaderIterator sigIter;
	const void *ptr;
	int_32 tag, type, count;
	char result[8*BUFSIZ];
	FD_t fd, ofd;
	int i;
	const char *tmpfile = NULL;
	unsigned char buffer[8192];
	int gpg_sig = 0;

	fd = fdOpen(file, O_RDONLY, 0);
	if (fdFileno(fd) < 0) {
		return _("Couldn't open file\n");
	}
	memset(&lead, 0, sizeof(lead));
	if (readLead(fd, &lead)) {
		return _("Could not read lead bytes\n");
	}
	if (lead.major == 1) {
		return _("RPM version of package doesn't support signatures\n");
	}

	i = rpmReadSignature(fd, &sig, lead.signature_type);
	if (i != RPMRC_OK && i != RPMRC_BADSIZE) {
		return _("Could not read signature block (`rpmReadSignature' failed)\n");
	}
	if (!sig) {
		return _("No signatures\n");
	}

	if (makeTempFile(NULL, &tmpfile, &ofd))
		return _("`makeTempFile' failed!\n");

	while ((i = fdRead(fd, buffer, sizeof(buffer))) != 0) {
		if (i == -1) {
			fdClose(ofd);
			fdClose(fd);
			unlink(tmpfile);
			return _("Error reading file\n");
		}
		if (fdWrite(ofd, buffer, i) < 0) {
			fdClose(ofd);
			fdClose(fd);
			unlink(tmpfile);
			return _("Error writing temp file\n");
		}
	}
	fdClose(fd);
	fdClose(ofd);
		  
	for (sigIter = headerInitIterator(sig); headerNextIterator(sigIter, &tag, &type, &ptr, &count); ptr = headerFreeData(ptr, type)) {
		switch (tag) {
		case RPMSIGTAG_PGP5: case RPMSIGTAG_PGP: case RPMSIGTAG_GPG:
			gpg_sig = 1;
		case RPMSIGTAG_LEMD5_2:	case RPMSIGTAG_LEMD5_1: case RPMSIGTAG_MD5:
		case RPMSIGTAG_SIZE:
			break;
		default:
			continue;
		}

		i = rpmVerifySignature(tmpfile, tag, ptr, count, result);
		if (i != RPMSIG_OK)
			return strdup(result);
	}
	unlink(tmpfile);
	if (!gpg_sig)
		return _("No GPG signature in package\n");
	else
		return "";
}


void rpmError_callback_empty(void) {}

int rpmError_callback_data;
void rpmError_callback(void) {
	if (rpmErrorCode() != RPMERR_UNLINK && rpmErrorCode() != RPMERR_RMDIR) {
		write(rpmError_callback_data, rpmErrorString(), strlen(rpmErrorString()));
	}
}

SV * install_packages_callback_data = NULL;
int install_packages_callback(char * msg, ...) __attribute__ ((format (printf, 1, 2)));
int install_packages_callback(char * msg, ...)
{
        int i;
	char * out;
	dSP;

	va_list args;
	va_start(args, msg);
	if (vasprintf(&out, msg, args) == -1)
		out = "";
	va_end(args);

	if (!install_packages_callback_data)
		return 0;
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
  	XPUSHs(sv_2mortal(newSVpv(out, 0)));
  	PUTBACK;
	free(out);
  	i = perl_call_sv(install_packages_callback_data, G_SCALAR);
        SPAGAIN;
        if (i != 1)
		croak("Big trouble\n");
	else
		i = POPi;
  	PUTBACK;
	FREETMPS;
	LEAVE;
	return i;
}

char * install_packages_(char ** packages)
{
	void * rpmRunTransactions_callback(const void * h, const rpmCallbackType what, const unsigned long amount, const unsigned long total, const void * pkgKey, void * data) {
		static FD_t fd;
		
		switch (what) {
		case RPMCALLBACK_INST_OPEN_FILE:
			return fd = fdOpen(pkgKey, O_RDONLY, 0);
		case RPMCALLBACK_INST_CLOSE_FILE:
			fdClose(fd);
			break;
		case RPMCALLBACK_INST_START:
			install_packages_callback("inst-start %s", basename(pkgKey));
			break;
		case RPMCALLBACK_INST_PROGRESS:
			install_packages_callback("inst-progress %ld %ld", amount, total);
			break;
		default:
			break;
		}
		return NULL;
	}
	char * returnmsg;
	rpmdb db;
	rpmTransactionSet rpmdep;
	rpmDependencyConflict conflicts;
	int num_conflicts;
	rpmProblemSet probs = NULL;
	char ** pkg;
	int noupgrade = 0;

	if (rpmdbOpen("", &db, O_RDWR, 0644)) {
		if (rpmErrorCode() == RPMERR_DBOPEN)
			return _("Couldn't open RPM DB for writing (not superuser?)");
		else
			return _("Couldn't open RPM DB for writing");
	}

	if (!(rpmdep = rpmtransCreateSet(db, NULL))) {
		returnmsg = _("Couldn't start transaction");
		goto install_packages_cleanup;
	}

	for (pkg = packages; pkg && *pkg; pkg++) {
		if (streq(*pkg, "-noupgrade")) 
			noupgrade = 1;
		else {
			Header h;
			int isSource, major;
			char *file = *pkg;
			char *LocalName = basename(file);
			FD_t fd;

			if (file[0] == '-')
				continue;

			fd = fdOpen(file, O_RDONLY, 0);
			if (fdFileno(fd) < 0) {
				returnmsg = my_asprintf(_("Can't open package `%s'\n"), LocalName);
				goto install_packages_cleanup;
			}
			switch (rpmReadPackageHeader(fd, &h, &isSource, &major, NULL)) {
			case 1:
				returnmsg = my_asprintf(_("Package `%s' is corrupted\n"), LocalName);
				goto install_packages_cleanup;
			default:
				returnmsg = my_asprintf(_("Package `%s' can't be installed\n"), LocalName);
				goto install_packages_cleanup;
			case 0:
				rpmtransAddPackage(rpmdep, h, NULL, file, !noupgrade, NULL);
			}
			fdClose(fd);
			noupgrade = 0;
		}
	}

	if (rpmdepCheck(rpmdep, &conflicts, &num_conflicts)) {
		returnmsg = _("Error while checking dependencies");
		goto install_packages_cleanup;
	}
	if (conflicts) {
		int i;
		char * conflict_msg = strdup("conflicts ");
		for (i=0; i<num_conflicts; i++) {
			char * msg1, * msg2;
			char sense = '\0';
			if (conflicts[i].needsFlags & RPMSENSE_SENSEMASK) {
				if (conflicts[i].needsFlags & RPMSENSE_LESS)    sense = '<';
				if (conflicts[i].needsFlags & RPMSENSE_GREATER) sense = '>';
				if (conflicts[i].needsFlags & RPMSENSE_EQUAL)   sense = '=';
				if (conflicts[i].needsFlags & RPMSENSE_SERIAL)  sense = 'S';
			}
			if (sense != '\0')
				msg1 = my_asprintf("%s %c %s", conflicts[i].needsName, sense, conflicts[i].needsVersion);
			else
				msg1 = strdup(conflicts[i].needsName);
			msg2 = my_asprintf("%s %s %s-%s-%s",
					  msg1,
					  (conflicts[i].sense == RPMDEP_SENSE_REQUIRES) ? _("is needed by") : _("conflicts with"),
					  conflicts[i].byName, conflicts[i].byVersion, conflicts[i].byRelease);
			free(msg1);
			msg1 = my_asprintf("%s|%s", conflict_msg, msg2);
			free(msg2);
			free(conflict_msg);
			conflict_msg = msg1;
		}
		if (install_packages_callback(conflict_msg)) {
			free(conflict_msg);
			returnmsg = "";
			goto install_packages_cleanup;
		}
		free(conflict_msg);
		rpmdepFreeConflicts(conflicts, num_conflicts);
	}

	if (rpmdepOrder(rpmdep)) {
		returnmsg = _("Error while checking dependencies 2");
		goto install_packages_cleanup;
	}
	if (rpmRunTransactions(rpmdep, rpmRunTransactions_callback, NULL, NULL, &probs, 0, 0)) {
		char * msg;
		int i;
		returnmsg = strdup(_("Problems occurred during installation:\n"));
		for (i = 0; i < probs->numProblems; i++) {
			const char * thispb = rpmProblemString(&(probs->probs[i]));
			msg = my_asprintf("%s%s\n", returnmsg, thispb);
			free(returnmsg);
			returnmsg = msg;
		}
		goto install_packages_cleanup;
	}
    
	rpmdbClose(db);
	return "";
      
 install_packages_cleanup: 
	rpmdbClose(db);
	return returnmsg;
}


/************************** Gateway to Perl ****************************/

MODULE = grpmi_rpm		PACKAGE = grpmi_rpm
PROTOTYPES : DISABLE

char *
init_rcstuff()
        CODE:
                RETVAL = init_rcstuff_();
        OUTPUT:
                RETVAL

char *
verify_sig(pkg)
char * pkg
	CODE:
                RETVAL = verify_sig_(pkg);
        OUTPUT:
                RETVAL

char *
install_packages(callback, ...)
SV * callback
	PREINIT:
		int i;
                char ** pkgs;
	CODE:
		install_packages_callback_data = callback;
		pkgs = malloc(sizeof(char *) * items);
                for (i=1; i<items; i++)
			pkgs[i-1] = SvPV(ST(i), PL_na);
		pkgs[items-1] = NULL;
                RETVAL = install_packages_(pkgs);
		free(pkgs);
		callback = NULL;
        OUTPUT:
                RETVAL

