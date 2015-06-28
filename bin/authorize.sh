#!/usr/bin/env bash

klist -s || kinit
klist -s || { echo "Kerberos login needed." >&2; exit 1; }

shell_services='atd cron login passwd sshd su sudo'

user=$1
host=${2:-$HOSTNAME}
host=${host%%.*}.cluenet.org

case $user in
    "")	echo "Usage: authorize <user> [<host>]" >&2;
    	exit 1;;
    -*)	user=${user#-};
    	change="delete";;
    *)	change="add";;
esac

user_dn="uid=${user},ou=people,dc=cluenet,dc=org"
host_dn="cn=${host},ou=servers,dc=cluenet,dc=org"

for service in $shell_services; do
	echo "dn: cn=${service},cn=svcAccess,${host_dn}"
	echo "${change}: member"
	echo "member: ${user_dn}"
	echo ""
done | ldapmodify -H "ldap://ldap.cluenet.org" -Y GSSAPI
