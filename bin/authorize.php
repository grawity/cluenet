#!/usr/bin/env php
<?php

const LDAP_SERVER = "ldap://ldap.cluenet.org";
const LDAP_BASEDN = "dc=cluenet,dc=org";
const LDAP_STARTTLS = false;
const GSS_REALM = "CLUENET.ORG";

putenv("LDAPCONF=".getenv("HOME")."/cluenet/ldap.conf");

function fatal(/*$format, @args*/) {
	$args = func_get_args();
	$format = array_shift($args);
	vfprintf(STDERR, $format, $args);
	exit(1);
}

include_once "/home/grawity/lib/ldap.php";

function connect_and_bind() {
	$link = ldap_connect(LDAP_SERVER)
		or fatal("Could not connect to %s\n", LDAP_SERVER);

	@ldap_set_option($link, LDAP_OPT_PROTOCOL_VERSION, 3)
		or fatal("Error enabling LDAPv3: %s (%d)\n",
		ldap_error($link), ldap_errno($link));
	
	if (LDAP_STARTTLS)
		@ldap_start_tls($link)
			or fatal("Error: start_tls: %s (%d)\n",
			ldap_error($link), ldap_errno($link));
	
	@ldap_sasl_bind($link, null, null, "GSSAPI")
		or fatal("Error: sasl_bind: %s (%d)\n",
		ldap_error($link), ldap_errno($link));
	
	return $link;
}

function authorize($add, $user, $server, $service="sshd") {
	global $link;

	$fqdn = "$server.cluenet.org";
	$userdn = "uid=$user,ou=people,dc=cluenet,dc=org";
	$serverdn = "cn=$fqdn,ou=servers,dc=cluenet,dc=org";
	$groupdn = "cn=$service,cn=svcAccess,$serverdn";

	$entry = array(
		"member" => $userdn,
		);

	$func = $add ? "ldap_mod_add" : "ldap_mod_del";

	printf("%s %s access to %s/%s\n", ($add?"Adding":"Removing"),
		$user, $server, $service);
	
	if (@$func($link, $groupdn, $entry)) {
		return true;
	}
	else {
		fprintf(STDERR, "Error: ldap_mod_add [%s to %s/%s]: %s (%s)\n",
			$username, $server, $service,
			ldap_error($link), ldap_errno($link));
		return false;
	}
}

function arg() {
	global $argv;
	static $i=0;
	return isset($argv[++$i])? $argv[$i] : null;
}

function dn_to_service($dn) {
	$host = $service = null;
	$dn = ldap_explode_dn($dn, 0);
	for ($i = 0; $i < $dn["count"]; $i++) {
		list ($attr, $value) = explode("=", $dn[$i], 2);
		if ($attr == "cn") {
			if ($service === null)
				$service = $value;
			elseif ($value == "svcAccess")
				null;
			elseif ($host === null)
				$host = $value;
			else
				return null;
		}
	}
	return "$host/$service";
}

function dn_to_user($dn) {
	$dn = ldap_explode_dn($dn, 0);
	for ($i = 0; $i < $dn["count"]; $i++) {
		list ($attr, $value) = explode("=", $dn[$i], 2);
		if ($attr == "uid")
			return $value;
	}
	return null;
}

if ($argc < 2) {
	fprintf(STDERR, "Usage: %s <command> [args...]\n", $argv[0]);
	exit(2);
}

switch ($cmd = arg()) {
case "add":
	$user = arg();
	$server = arg();
	if (!strlen($user) or !strlen($server)) {
		fprintf(STDERR, "Usage: %s %s <user> <server>\n", $argv[0], $cmd);
		exit(2);
	}
	break;
case "del":
case "rm":
	$cmd = "del";
	$user = arg();
	$server = arg();
	break;
case "list":
	$query = arg();
	if (!strlen($query)) {
		fprintf(STDERR, "Usage: %s %s <user>\n", $argv[0], $cmd);
		fprintf(STDERR, "       %s %s <host>/(<service>|*)\n", $argv[0], $cmd);
		exit(2);
	}
	break;
case "listsvc":
	$host = arg();
	if (!strlen($host)) {
		fprintf(STDERR, "Usage: %s %s <host>\n", $argv[0], $cmd);
		exit(2);
	}
	break;
default:
	fwrite(STDERR, "Unknown command '$cmd'\n");
	exit(2);
}

$link = connect_and_bind();
$service = "login";

switch ($cmd) {
case "add":
	authorize(true, $user, $server, $service);
	break;
case "del":
	authorize(false, $user, $server, $service);
	break;
case "list":
	if (strpos($query, "/") === false) {
		$user = $query;
		$userdn = sprintf("uid=%s,ou=people,%s", $user, LDAP_BASEDN);
		$filter = sprintf("(&(objectClass=groupOfNames)(member=%s))", $userdn);
		$res = ldap_search($link, LDAP_BASEDN, $filter, array());
		ldap_each_res($link, $res, function ($link, $ent) use ($user) {
			$acldn = ldap_get_dn($link, $ent);
			$a[] = $acldn;
			echo $user, ": ", dn_to_service($acldn), "\n";
		});
	}
	else {
		list ($host, $service) = explode("/", $query, 2);
		if (!strlen($host) or !strlen($service)) {
			fwrite(STDERR, "Invalid host/service specification\n");
			exit(2);
		}

		if ($service == '*') {
			$aclbase = sprintf("cn=svcAccess,cn=%s,ou=servers,%s",
				$host, LDAP_BASEDN);
			$res = ldap_search($link, $aclbase, "objectClass=groupOfNames",
				array("member"));
		} else {
			$acldn = sprintf("cn=%s,cn=svcAccess,cn=%s,ou=servers,%s",
				$service, $host, LDAP_BASEDN);
			$res = ldap_read($link, $acldn, "objectClass=groupOfNames",
				array("member"));
		}

		ldap_each_res($link, $res, function ($link, $ent) {
			$dn = ldap_get_dn($link, $ent);
			$values = ldap_get_values($link, $ent, "member");
			for ($i = 0; $i < $values["count"]; $i++)
				echo dn_to_service($dn), ": ", dn_to_user($values[$i]), "\n";
		});
	}
	break;
case "listsvc":
	$hostdn = sprintf("cn=%s,ou=servers,%s", $host, LDAP_BASEDN);
	$res = ldap_read($link, $hostdn, "objectClass=server",
		array("authorizedService"));
	if ($ent = ldap_first_entry($link, $res)) {
		$values = ldap_get_values($link, $ent, "authorizedService");
		for ($i = 0; $i < $values["count"]; $i++)
			echo $host, "/", $values[$i], "\n";
	}
	break;
}
