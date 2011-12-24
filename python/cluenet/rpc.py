#!python
import base64
import json
import ldap.sasl
import socket
import sys

def serialize(obj):
	return json.dumps(obj)

def unserialize(buf):
	return json.loads(buf or "{}")

class RpcPeer(object):
	sasl_service = "host"
	remote_host = "localhost"

	"""Stream wrapper class for exchanging RPC packets over arbitrary streams."""

	def __init__(self, rfd=None, wfd=None):
		self.rfd = rfd or sys.stdin
		self.wfd = wfd or rfd or sys.stdout

	def close(self):
		self.wfd.flush()
		self.wfd.close()
		self.rfd.close()

	def rpc_send_packed(self, buf):
		"""Send binary buffer as RPC packet"""
		self.wfd.write("!rpc%04x" % len(buf))
		self.wfd.write(buf)
		self.wfd.flush()

	def rpc_recv_packed(self):
		"""Receive RPC packet with binary buffer"""
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
		"""Send simple object as RPC packet; must be JSON-serializable"""
		buf = serialize(obj)
		self.rpc_send_packed(buf)

	def rpc_recv(self):
		"""Receive RPC packet as simple JSON object"""
		buf = self.rpc_recv_packed()
		return unserialize(buf)

class RpcClient(RpcPeer):
	def __init__(self, *a, **kw):
		self.sasl = None
		self.auth_info = None
		super(RpcClient, self).__init__(*a, **kw)

	def rpc_call(self, func, args):
		"""Send a RPC function call and return result"""
		self.rpc_send([func, args])
		return self.rpc_recv()
	
	def call(self, func, **args):
		"""Make a ClueRPC-style function call (only named arguments)"""
		result = self.rpc_call(func, args)
		status = result["success"]
		if status:
			return result
		else:
			raise RpcError.new(result)

	def methods(self):
		res = self.call('list')
		return res['functions']

	def __getattr__(self, name):
		"""Proxy methods for RPC functions"""
		def rpc_func_wrapper(**args):
			return self.call(name, **args)
		return rpc_func_wrapper
		return lambda **args: self.call(name, **args)
	
	def authenticate(self, mech="GSSAPI", authz=None):
		if self.auth_info:
			return self.auth_info

		import cluenet.sasl
		self.sasl = cluenet.sasl.BozoSASL2(mech, self.sasl_service, self.remote_host, authz)

		saslout = self.sasl.client_start()
		res = self.auth(mech=mech, data=base64.b64encode(saslout), seal=0)
		while u"data" in res:
			saslin = base64.b64decode(res['data'])
			saslout = self.sasl.client_step(saslin)
			res = self.auth(data=base64.b64encode(saslout))
		self.auth_info = res
		return res

class RpcSocketClient(RpcClient):
	def __init__(self, af, addr):
		self.af = af
		self.addr = addr

		self.sock = socket.socket(af, socket.SOCK_STREAM)
		self.sock.connect(addr)

		fd = self.sock.makefile()
		super(RpcSocketClient, self).__init__(fd)
	
	def close(self):
		super(RpcSocketClient, self).close()
		self.sock.close()

class RpcInetClient(RpcSocketClient):
	def __init__(self, host, port=10875, af=socket.AF_INET6):
		self.remote_host = host
		super(RpcInetClient, self).__init__(af, (host, port))

class RpcError(Exception):
	def __init__(self, data):
		self.data = data
		self.msg = data["msg"]

	def __str__(self):
		return self.msg
	
	@staticmethod
	def new(data):
		msg = data["msg"].split(": ")[0]
		if msg == "access denied":
			return RpcAccessDeniedError(data)
		elif msg == "invalid function":
			return RpcUnknownFunctionError(data)
		else:
			return RpcError(data)

class RpcAccessDeniedError(RpcError):
	pass

class RpcMissingArgumentError(RpcError):
	pass

class RpcUnknownFunctionError(RpcError):
	pass
