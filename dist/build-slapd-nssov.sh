#!/usr/bin/env bash

set -e
version='2.4.29'

download() {
	cd "$buildroot"
	url="ftp://ftp.openldap.org/pub/OpenLDAP/openldap-release/openldap-$version.tgz"
	wget -c "$url"
	tar xzf "${url##*/}"
}

build() {
	cd "$buildroot/openldap-$version"
	./configure --prefix='/cluenet/openldap'
	make depend
	make
	cd contrib/slapd-modules/nssov
	make
}

package() {
	cd "$buildroot/openldap-$version"
	make install
	cd contrib/slapd-modules/nssov
	make install
}

buildroot="$PWD/openldap-nssov-build"

if (( UID )); then
	mkdir -p "$buildroot"
	download
	build
	echo "Run $0 as root to install."
else
	package
fi
