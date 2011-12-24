import base64
import os
import subprocess
import cluenet.rpc

"""
Python's SASL implementations are crap.
"""

def encode(buf):
	return base64.b64encode(buf)

def decode(string):
	return base64.b64decode(string)

class BozoSASL(object):
	def __init__(self, mech, service, host):
		self.mech = mech
		self.service = service
		self.host = host
		self.need_step = True
		
		self.proc = subprocess.Popen(["/cluenet/bin/saslhelper",
						"-m", mech,
						"-s", service,
						"-h", host],
					stdin=subprocess.PIPE,
					stdout=subprocess.PIPE)
	
	def _read(self):
		return self.proc.stdout.readline().strip('\n').split(' ')
	
	def _write(self, data):
		self.proc.stdin.write(data+b'\n')
	
	def client_start(self):
		ln = self._read()
		if ln[0] == b'write':
			resp = decode(ln[1])
			ln = self._read()
		if ln[0] == b'read':
			self.need_step = True
		if ln[0] == b'done':
			self.need_step = False
			self.proc.wait()
		return resp

	def client_step(self, resp):
		self._write(encode(resp))
		return self.client_init()
	
class BozoSASL2(object):
	def __init__(self, mech, service, host, authz=None):
		self.mech = mech
		self.service = service
		self.host = host
		self.need_step = True
		
		self.proc = subprocess.Popen(["/home/grawity/cluenet/bin/saslhelper2"],
						stdin=subprocess.PIPE,
						stdout=subprocess.PIPE)

		self.helper = cluenet.rpc.RpcClient(self.proc.stdout, self.proc.stdin)
		res = self.helper.new(mech=mech, service=service, host=host, user=authz)
	
	def client_start(self):
		res = self.helper.start()
		self.need_step = bool(res['step'])
		return decode(res['data'])
	
	def client_step(self, resp):
		res = self.helper.step(data=encode(resp))
		self.need_step = bool(res['step'])
		return decode(res['data'])
	
	def sasl_encode(self, data):
		res = self.helper.encode(data=encode(data))
		return decode(res['data'])
	
	def sasl_decode(self, data):
		res = self.helper.decode(data=encode(data))
		return decode(res['data'])
