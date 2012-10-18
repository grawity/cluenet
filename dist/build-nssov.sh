#!/usr/bin/env bash

set -e

version=${1:-'2.4.30'}

buildroot="$PWD/openldap-nssov-build"

download() {
	cd "$buildroot"
	url="ftp://ftp.openldap.org/pub/OpenLDAP/openldap-release/openldap-$version.tgz"
	wget -c "$url"
	tar xzf "${url##*/}"
}

build() {
	cd "$buildroot/openldap-$version"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
	make depend
	cd contrib/slapd-modules/nssov
	make
}

package() {
	cd "$buildroot/openldap-$version"
	cd contrib/slapd-modules/nssov
	make DESTDIR="${destdir%/}/" moduledir="." schemadir="." install
	echo "Installed to $destdir"
}

getbuild() {
	mkdir -p "$buildroot"
	download
	build
	destdir="$buildroot/nssov"
	package
}

if (( UID )); then
	getbuild
	echo "Run $0 as root to install system-wide."
else
	test -d "$buildroot/nssov" || getbuild
	#destdir="/cluenet/lib/$(uname -m)/nssov"
	destdir="/cluenet/lib/nssov"
	package
fi
