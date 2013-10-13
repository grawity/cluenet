package Cluenet;
use warnings;
use strict;

=head1 Cluenet

Constants and variables intentionally aren't exported.

=cut

our $LDAP_HOST = $ENV{CN_LDAP_SERVER} // "ldap://ldap.cluenet.org";
our $LDAP_BASE = $ENV{CN_LDAP_BASE} // "dc=cluenet,dc=org";
our $KADM_HOST = $ENV{CN_KADM_HOST} // "krb5-admin.cluenet.org";
our $API_PRINC = undef;
our $API_KEYTAB = undef;
our $UID_MIN = 25000;
our $UID_MAX = 29999;

our %UI_CB;

1;
