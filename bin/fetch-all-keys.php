#!/usr/bin/php
<?php # r11
/*
 * Usage: fetch-all-keys [-f file] [--no-tls]
 *
 * Options: 
 *
 *   -f FILE     Write keys to FILE instead of ~/.ssh/authorized_keys
 *               Specify - for stdout.
 *
 *   -T          Do not use ldap_start_tls()
 *
 * This script automatically downloads the SSH public keys of all users into
 * a single authorized_keys file.
 *
 * (c) 2010 Mantas Mikulėnas <grawity@gmail.com>
 * Released under the MIT Expat License (dist/LICENSE.expat)
 */

define("SYSLOG_PREFIX", "fetchkeys");

$keysPath = null;

$filter = "(&(objectClass=posixAccount)(!(objectClass=suspendedUser))(clueSshPubKey=*))";

$starttls = true;

$argv0 = array_shift($argv);
while ($arg = array_shift($argv)) switch($arg):
case "-f":
	$keysPath = array_shift($argv);
	if ($keysPath === null)
		diehorribly("Usage: -f file");
	break;
	exit(0);
case "-T":
	$starttls = false;
	break;
case "-h": case "--help":
	system("grep '^[ /]\*' ".escapeshellarg(__FILE__));
default:
	diehorribly("Try {$argv0} --help");
endswitch;

function diehorribly($text = false) {
	if ($text) L(LOG_ERR, $text);
	exit(1);
}

function L($level, $text) {
	syslog($level, SYSLOG_PREFIX . ": " . $text);
	fwrite(STDERR, $text . "\n");
}

if ($keysPath === null) {
	$home = getenv("HOME");
	if ($home === false)
		diehorribly("Could not determine home directory for current user");
	else
		$keysPath = "{$home}/.ssh/authorized_keys";
}


# connect to LDAP and do search
$ldapH = ldap_connect("ldap://ldap.cluenet.org");

if (!is_resource($ldapH))
	diehorribly("LDAP connection failed");

ldap_set_option($ldapH, LDAP_OPT_PROTOCOL_VERSION, 3)
	or diehorribly("Could not upgrade to LDAP v3");

if ($starttls) ldap_start_tls($ldapH)
	or diehorribly("Cannot start TLS");

ldap_bind($ldapH, null, null)
	or diehorribly("Anonymous bind failed");

$resultH = ldap_search($ldapH, "ou=people,dc=cluenet,dc=org", $filter,
	array("uid", "uidNumber", "clueSshPubKey"));

if (!is_resource($resultH))
	diehorribly("Search failed");

$count = ldap_count_entries($ldapH, $resultH);

# open the key file
if ($keysPath == "-")
	$outH = STDOUT;
else
	$outH = @fopen($keysPath, "w");

if (!is_resource($outH))
	diehorribly("Cannot open {$path} for writing");

fwrite($outH, "# auto-generated key list\n\n");

# write keys	
for (
$entryID = ldap_first_entry($ldapH, $resultH);
$entryID != false;
$entryID = ldap_next_entry($ldapH, $entryID)) {

	$values = ldap_get_attributes($ldapH, $entryID);
	
	$user = $values['uid'][0];
	$uid = (int) $values['uidNumber'][0];
	
	# IT'S CALLED SSH KEY, NOT GPG -_-
	if ($uid == 25047) continue;
	
	$keys = $values['clueSshPubKey'];
	
	fwrite($outH, "# {$user} ({$uid})\n");

	for ($i = 0; $i < $keys["count"]; $i++)
		fwrite($outH, rtrim($keys[$i]) . "\n");

	fwrite($outH, "\n");
}

# disconnect
ldap_unbind($ldapH);

fclose($outH);

exit(0);

