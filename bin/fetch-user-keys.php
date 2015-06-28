#!/usr/bin/env php
<?php
const LDAP_URI = "ldap://ldap.cluenet.org";

class config {
	static $optin = true;
	static $logmax = LOG_NOTICE;
	static $logopts = LOG_PID;
}

function putlog($level, $message) {
	if ($level <= config::$logmax)
		syslog($level, $message);
}

$argv0 = array_shift($argv);
foreach (getopt("av") as $opt => $optarg)
	switch ($opt) {
	case "a":
		config::$optin = false;
		break;
	case "v":
		config::$logmax++;
		config::$logopts |= LOG_PERROR;
		break;
	}

$filter = "(&
	(objectClass=posixAccount)
	(!(objectClass=suspendedUser))
	(clueSshPubKey=*)
)";

if (($my_uid = posix_getuid()) >= 1000) {
	$my_pwent = posix_getpwuid($my_uid);
	$username = $my_pwent["name"];
	$filter = "(&{$filter}(uid=$username))";
	config::$optin = false;
	config::$logopts |= LOG_PERROR;
}

$ldapconf = "/etc/ldap/cluenet.conf";
if (is_file($ldapconf))
	putenv("LDAPCONF=$ldapconf");

openlog("fetch-keys", config::$logopts, LOG_DAEMON);

$conn = ldap_connect(LDAP_URI);
if (!$conn) {
	putlog(LOG_ERR, "LDAP connection failed");
	exit(1);
}
if (!ldap_set_option($conn, LDAP_OPT_PROTOCOL_VERSION, 3)) {
	putlog(LOG_ERR, "upgrade to LDAPv3 failed");
	exit(1);
}
if (!ldap_start_tls($conn)) {
	putlog(LOG_ERR, "TLS negotiation failed: ".ldap_error($conn));
	exit(1);
}
if (!ldap_bind($conn, null, null)) {
	putlog(LOG_ERR, "anonymous bind failed: ".ldap_error($conn));
	exit(1);
}

$search = ldap_list($conn, "ou=people,dc=cluenet,dc=org", $filter,
	array("uid", "uidNumber", "homeDirectory", "clueSshPubKey"));
if (!$search) {
	putlog(LOG_ERR, "search failed: ".ldap_error($conn));
	exit(1);
}

$num_res = ldap_count_entries($conn, $search);
putlog(LOG_INFO, "found $num_res accounts");

for ($entry = ldap_first_entry($conn, $search);
		$entry != false;
		$entry = ldap_next_entry($conn, $entry)) {

	$values = ldap_get_attributes($conn, $entry);
	$user = $values["uid"][0];
	$uid = (int) $values["uidNumber"][0];
	$home = $values["homeDirectory"][0];
	$keys = $values["clueSshPubKey"];

	if (!is_dir($home))
		continue;

	if (config::$optin and !file_exists("$home/.ssh/authorized_keys.autoupdate")) {
		putlog(LOG_INFO, "skipping $user - not opted in");
		continue;
	}

	putlog(LOG_INFO, "updating keys for $user");
	$file = "$home/.ssh/authorized_keys";

	$owner = @fileowner($file);
	if ($owner === false) {
		putlog(LOG_NOTICE, "skipping $user - does not have authorized_keys");
		continue;
	}
	elseif ($owner and $owner !== $uid) {
		putlog(LOG_WARNING, "skipping $user - insecure ownership on $file");
		continue;
	}

	$fh = fopen($file, "w");
	if (!$fh) {
		putlog(LOG_NOTICE, "failed to open $file");
		continue;
	}

	fwrite($fh, "# updated ".date("r")." from LDAP (uid=$user)\n");
	for ($i = 0; $i < $keys["count"]; $i++)
		fwrite($fh, $keys[$i]."\n");
	putlog(LOG_INFO, "wrote ".$keys["count"]." keys to $file");

	$local = "$file.local";
	if (is_file($local)) {
		$local_fh = fopen($local, "r");
		if (!$local_fh) {
			putlog(LOG_NOTICE, "failed to open $local");
		} else {
			putlog(LOG_INFO, "copying keys from $local");
			fwrite($fh, "# local keys\n");
			while (($buf = fread($local_fh, 4096)) !== false) {
				fwrite($fh, $buf);
			}
			fclose($local_fh);
		}
	}

	fclose($fh);
}

ldap_unbind($conn);
closelog();
