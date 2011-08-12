#!python
import json
import socket
import sys

def encode(obj):
	return json.dumps(obj)

def decode(obj):
	return json.loads(obj or "{}")

def send_packed(fd, buf):
	fd.write("!rpc%04x" % len(buf))
	fd.write(buf)
	fd.flush()

def recv_packed(fd):
	buf = fd.read(8)
	if len(buf) != 8:
		raise IOError("Connection closed while reading")
	if buf[:4] != "!rpc":
		raise IOError("Invalid RPC magic")
	length = int(buf[4:8], 16)
	buf = fd.read(length)
	if len(buf) != length:
		raise IOError("Connection closed while reading")
	return buf

def send_fd(obj, fd=None):
	return send_packed(fd or sys.stdout, encode(obj))

def recv_fd(fd=None):
	return decode(recv_packed(fd or sys.stdin))
