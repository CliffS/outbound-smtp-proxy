#!/usr/bin/env coffee
#

os  = require 'os'
net = require 'net'
TLS = require 'tls'
Bunyan = require 'bunyan'

Original = require './getOriginalDst'


CONFIG = switch os.hostname()
  when 'prog'
    port: 25125
    host: '127.0.0.1'
    local: '10.20.30.38'
    outboundPort: 25
  when 'pt'
    port: 25
    host: '127.0.0.1'
    local: '54.38.99.66'

log = Bunyan.createLogger
  name: 'outbound-smtp'
  # serializers:
    # err: Bunyan.stdSerializers.err
  streams: [
    level: 'debug'
    path: '/var/log/outbound-smtp.log'
    type: 'rotating-file'
    period: '1d'
    count: 14
  ]

log.info 'Server started'

server = net.createServer (socket) ->
  original = Original socket
  log.info address: original.address, "inbound connection"
  createOutboundConnection socket

server.listen CONFIG.port, CONFIG.host

createOutboundConnection = (inbound) ->
  ehlo = ''
  original = Original inbound
  address = original.address
  inbound.setEncoding 'utf8'
  inbound.once 'error', (err) =>
    log.error
      address: address
      err: err,
      "inbound stream"
    inbound.end()
  inbound.once 'close', =>
    log.debug address: address, 'inbound connection closed'
    outbound?.end()
  options =
    port: CONFIG.outboundPort ? original.port
    host: original.address
    localAddress: CONFIG.local
  outbound = new net.Socket
  outbound.setEncoding 'utf8'
  outbound.once 'error', (err) =>
    log.error
      address: address
      err: err,
      "outbound stream"
    inbound.end()
  .once 'connect', =>
    log.debug address: address, "outbound connected"
  .once 'close', =>
    log.debug address: address, "outbound closed"
    inbound.end()
  .on 'data', startData = (data) =>
    if data.match /STARTTLS/
      outbound.write 'STARTTLS\r\n'
    else if data.match /^220 Ready to start TLS/
      outbound.setEncoding null
      outbound.removeAllListeners 'data'
      tls = TLS.connect
        socket: outbound
        rejectUnauthorized: false
        honorCipherOrder: true
      tls.once 'error', (err) =>
        log.error
          address: address
          err: err,
          "TLS stream"
        inbound.end()
      .setEncoding 'utf8'
      .once 'secureConnect', =>
        log.info address: address, "TLS connected (%s) with %s",
          if tls.authorized then 'authorized' else 'unauthorized',
          tls.getProtocol()
        tls.write ehlo
        inbound.pipe tls
        tls.pipe inbound
      .once 'close', =>
        log.debug address: address, 'TLS connection closed'
        inbound.close()
        outbound.close()
    else if data.match /^250 /m
      inbound.write data
      log.info address: address, 'no STARTTLS detected'
      outbound.removeAllListeners 'data'
      inbound.pipe outbound
      outbound.pipe inbound
    else
      inbound.write data
  inbound.once 'data', (data) =>
    ehlo = data
    outbound.write data

  outbound.connect options

