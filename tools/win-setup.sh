#!/bin/bash
#
# Copyright 2013 Gerald Combs <gerald@wireshark.org>
#
# Wireshark - Network traffic analyzer
# By Gerald Combs <gerald@wireshark.org>
# Copyright 1998 Gerald Combs
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# The cygwin version of bash has an option to ignore the extra CR at
# the end of a script line that would cause an error otherwise. Use this
# option if supported.
# Note: The following line must be the first non-comment line
(set -o igncr) 2>/dev/null && set -o igncr; # comment is needed as well

err_exit () {
	echo ""
	echo "ERROR: $1"
	shift
	for str in "$@" ; do
		echo "$str"
	done
	echo ""
	exit 1
}

usage () {
	echo "Usage:"
	echo "	$0 --appverify <appname> [<appname>] ..."
	echo "  $0 --libverify <destination> <subdirectory> <package>"
	echo "	$0 --download  <destination> <subdirectory> <package> <tag> <platform>"
	echo "	$0 --settag    <destination> <tag>"
	echo "	$0 --checktag  <destination> <tag>"
	echo ""
	exit 1
}

# Try to find our proxy settings, and set http_proxy/use_proxy accordingly.
find_proxy() {
	# Someone went to the trouble of configuring wget.
	if grep "^use_proxy *= *on" $HOME/.wgetrc > /dev/null 2>&1 ; then
		return
	fi

	# ...and wget can't fetch two registry keys because...?
	proxy_enabled=$(regtool get /HKCU/Software/Microsoft/Windows/CurrentVersion/Internet\ Settings/ProxyEnable 2>/dev/null | tr -d '\012')
	#
	# Bash's test command appears not to use short-circuit evaluation,
	# so
	#
	#	-n "$proxy_enabled" -a "$proxy_enabled" -ne 0
	#
	# causes a complaint if "$proxy_enabled" is an empty string -
	# the first test fails, but the second test is done anyway,
	# and generates a complaint about the LHS of -ne not being
	# numeric.  Therefore, we do the tests separately.
	#
	if [ -n "$proxy_enabled" ] ; then
		if [ "$proxy_enabled" -ne 0 ] ; then
			export http_proxy=$(regtool get /HKCU/Software/Microsoft/Windows/CurrentVersion/Internet\ Settings/ProxyServer 2>/dev/null)
			echo "Using Internet Explorer proxy settings."
		fi
	fi

	if [ -z "$http_proxy" -a -z "$HTTP_PROXY" ] ; then
		echo "No HTTP proxy specified (http_proxy and HTTP_PROXY are empty)."
		# a proxy might also be specified using .wgetrc, so don't switch off the proxy
		#use_proxy="-Y off"
		return
	fi

	# We found a proxy somewhere
	use_proxy="-Y on"
	if [ -z "$http_proxy" ] ; then
		echo "HTTP proxy ($HTTP_PROXY) has been specified and will be used."
		export http_proxy=$HTTP_PROXY
	else
		echo "HTTP proxy ($http_proxy) has been specified and will be used."
	fi
}

# Main
TAG_FILE="current_tag.txt"
if [ -z "$*" ] ; then
	usage
fi
case "$1" in
--appverify)
	shift
	if [ -z "$*" ] ; then
		usage
	fi

	echo "Checking for required applications:"
	which which > /dev/null 2>&1 || \
		err_exit "Can't find 'which'.  Unable to proceed."

	MISSING_APPS=
	PATH_RE=""
	for APP in $* ; do

		case "$APP" in
			--windowsonly)
				PATH_RE="^/cygdrive/.*/"
				continue
				;;
			--cygwinonly)
				PATH_RE="^/usr/.*/"
				continue
				;;
		esac

		APP_PATH=$(cygpath --unix "$APP")
		if [ -x "$APP_PATH" -a ! -d "$APP_PATH" ] ; then
			APP_LOC="$APP_PATH"
		else
			APP_LOC=$(which "$APP_PATH" 2> /dev/null)
		fi
		echo "$APP_LOC" | grep "$PATH_RE" > /dev/null 2>&1
		IN_PATH=$?
		if [ "$APP_LOC" = "" -o $IN_PATH -ne 0 ] ; then
			MISSING_APPS="$MISSING_APPS $APP"
		else
			echo "	$APP: $APP_LOC $res"
		fi

		PATH_RE=""
	done

	if [ -n "$MISSING_APPS" ]; then
		echo
		echo "Can't find: $MISSING_APPS"
 		err_exit "These application(s) are either not installed or simply can't be found in the current PATH: $PATH." \
 		"" "For additional help, please visit:" "    http://www.wireshark.org/docs/wsdg_html_chunked/ChSetupWin32.html"
	fi
	;;
--libverify)
	if [ -z "$2" -o -z "$3" -o -z "$4" ] ; then
		usage
	fi
	DEST_PATH=$(cygpath "$2")
	PACKAGE_PATH=$4
	PACKAGE=$(basename "$PACKAGE_PATH")
	if [ ! -e "$DEST_PATH/$PACKAGE" ] ; then
		err_exit "Package $PACKAGE is needed but is apparently not downloaded; 'nmake -f ... setup' required ?"
	fi
	;;
--download)
	if [ -z "$2" -o -z "$3" -o -z "$4" -o -z "$5" -o -z "$6" ] ; then
		usage
	fi
	DEST_PATH=$(cygpath "$2")
	DEST_SUBDIR=$3
	PACKAGE_PATH=$4
	DOWNLOAD_TAG=$5
	WIRESHARK_TARGET_PLATFORM=$6

	if [ -z "$WIRESHARK_TARGET_PLATFORM" ]; then
		err_exit "WIRESHARK_TARGET_PLATFORM not defined"
	fi
	# DOWNLOAD_PREFIX MUST be in the form
	#   https://anonsvn.wireshark.org/wireshark-win32-libs/tags/<date>/packages
	# or
	#   https://anonsvn.wireshark.org/wireshark-win64-libs/tags/<date>/packages
	# or
	#   /packages to test uploads before creating the tag.
	#DOWNLOAD_PREFIX="https://anonsvn.wireshark.org/wireshark-$WIRESHARK_TARGET_PLATFORM-libs/trunk/packages"
	DOWNLOAD_PREFIX="https://anonsvn.wireshark.org/wireshark-$WIRESHARK_TARGET_PLATFORM-libs/tags/$DOWNLOAD_TAG/packages"

	PACKAGE=$(basename "$PACKAGE_PATH")
	echo ""
	echo "****** $PACKAGE ******"
	find_proxy
	echo "Downloading $4 into '$DEST_PATH', installing into $3"
	if [ ! -d "$DEST_PATH/$DEST_SUBDIR" ] ; then
		mkdir -p "$DEST_PATH/$DEST_SUBDIR" || \
			err_exit "Can't create '$DEST_PATH/$DEST_SUBDIR'"
	fi
	cd "$DEST_PATH" || err_exit "Can't find '$DEST_PATH'"
	PKG_PATH="$PWD"
	wget $use_proxy -nc "$DOWNLOAD_PREFIX/$PACKAGE_PATH" || \
		err_exit "Can't download $DOWNLOAD_PREFIX/$PACKAGE_PATH"
	cd "$DEST_SUBDIR" || err_exit "Can't find $DEST_SUBDIR"
	echo "Extracting '$PKG_PATH/$PACKAGE' into '$PKG_PATH/$DEST_SUBDIR'"
	if [[ "$PACKAGE" == *.zip ]] ; then
		unzip -oq "$PKG_PATH/$PACKAGE" ||
			err_exit "Couldn't unpack '$PKG_PATH/$PACKAGE'"
		echo "Verifying that the DLLs and EXEs in $DEST_SUBDIR are executable."
		# XX: Note that find will check *all* dlls/exes in DEST_SUBDIR and below
		#     which may be more than those just unzipped depending upon DEST_SUBDIR.
		#     This may cause extra repeated checks but will do no harm.
		for i in $(/usr/bin/find . \( -name '*\.dll' -o -name '*\.exe' \)) ; do
			if [ ! -x "$i" ] ; then
				echo "Changing file permissions (add executable bit) to:"
				echo "$i"
				chmod a+x "$i"
			fi
		done
	fi
	;;
--settag)
	if [ -z "$2"  -o -z "$3" ] ; then
		usage
	fi
	DEST_PATH=$(cygpath "$2")
	DOWNLOAD_TAG=$3
	echo "$DOWNLOAD_TAG" > "$DEST_PATH/$TAG_FILE"
	;;
--checktag)
	if [ -z "$2" -o -z "$3" ] ; then
		usage
	fi
	DEST_PATH=$(cygpath "$2")
	WIN_PATH=$(cygpath --windows "$2")
	DOWNLOAD_TAG=$3
	LAST_TAG=$(cat "$DEST_PATH/$TAG_FILE" 2> /dev/null)
	if [ "$DOWNLOAD_TAG" != "$LAST_TAG" ] ; then
		if [ -z "$LAST_TAG" ] ; then
			LAST_TAG="(unknown)"
		fi
		err_exit \
			"The contents of '$WIN_PATH\\$TAG_FILE' is $LAST_TAG." \
			"It should be $DOWNLOAD_TAG."
	fi
	;;
*)
	usage
	;;
esac

exit 0
