# https://stackoverflow.com/a/29635482/1150513
ffi         =  require  'ffi-napi'
Struct      =  require  'struct'

current = ffi.Library null,
  'getsockopt': ['int', ['int', 'int', 'int', 'pointer', 'pointer']]

SOL_IP = 0
SO_ORIGINAL_DST = 80
AF_INET = 2

get_original_dst = (client) ->
  ip_addr = Struct()
    .word8    'b1'
    .word8    'b2'
    .word8    'b3'
    .word8    'b4'

  sockaddr_in = Struct()
    .word16Sle  'sin_family'
    .word16Ube  'sin_port'
    .struct     'sin_addr', ip_addr
    .word32Sle  'junk1'
    .word32Sle  'junk2'

  socklen_t = Struct()
  .word32Ule 'length'
  socklen_t.allocate()
  optlen = socklen_t.buffer()
  socklen_t.fields.length = sockaddr_in.length()
  sockaddr_in.allocate()
  optval = sockaddr_in.buffer()
  # optlen[0] = 16
  r = current.getsockopt(client._handle.fd, SOL_IP, SO_ORIGINAL_DST, optval, optlen)
  if r is -1
    throw new Error('getsockopt(SO_ORIGINAL_DST) error')
  if sockaddr_in.fields.sin_family isnt AF_INET
    throw new Error('getsockopt(SO_ORIGINAL_DST) returns unknown family: ' + sockaddr_in.fields.sin_family)
  ip = sockaddr_in.get('sin_addr').fields
  ipaddr = [ ip.b1, ip.b2, ip.b3, ip.b4 ].join '.'
  {
    address: ipaddr
    family: 'IPv4'
    port: sockaddr_in.fields.sin_port
  }

module.exports = get_original_dst
