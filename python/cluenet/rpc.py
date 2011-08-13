#!python
import json
import socket
import sys

def encode(obj):
	return json.dumps(obj)

def decode(buf):
	return json.loads(buf or "{}")

class Rpc():
	def __init__(self, rfd=None, wfd=None):
		self.rfd = rfd or sys.stdin
		self.wfd = wfd or rfd or sys.stdout

	def rpc_send_packed(self, buf):
		self.wfd.write("!rpc%04x" % len(buf))
		self.wfd.write(buf)
		self.wfd.flush()

	def rpc_recv_packed(self):
		buf = self.rfd.read(8)
		if len(buf) != 8:
			raise IOError("Connection closed while reading")
		try:
			if buf[:4] != "!rpc": raise ValueError
			length = int(buf[4:8], 16)
		except:
			buf += self.rfd.read(502)
			self.wfd.write("Protocol mismatch\n")
			self.close()
			raise IOError("Protocol mismatch: received %r" % buf)
		buf = self.rfd.read(length)
		if len(buf) != length:
			raise IOError("Connection closed while reading")
		return buf

	def rpc_send(self, obj):
		buf = encode(obj)
		self.rpc_send_packed(buf)

	def rpc_recv(self):
		buf = self.rpc_recv_packed()
		return decode(buf)

	def close(self):
		self.wfd.flush()
		self.wfd.close()
		self.rfd.close()
