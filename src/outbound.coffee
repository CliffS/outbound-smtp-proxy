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
    local: '54.38.39.66'
  else
    throw new Error "No config found for #{os.hostname}"

log = Bunyan.createLogger
  name: 'outbound-smtp'
  streams:
    [
      level: 'debug'
      path: '/var/log/outbound-smtp.log'
      type: 'rotating-file'
      period: '1d'
      count: 14
    ,
      level: 'trace'
      path: '/var/log/outbound-smtp-trace.log'
      type: 'rotating-file'
      period: '1d'
      count: 2
      serializers:
        err: Bunyan.stdSerializers.err
    ]

log.info 'Server started'

server = net.createServer (socket) ->
  original = Original socket
  log.info address: original.address, "inbound connection"
  createOutboundConnection socket

server.listen CONFIG.port, CONFIG.host

createOutboundConnection = (inbound) ->
  ehlo = ''
  TLSStarted = false
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
    log.trace address: address, "<< #{data}"
    if data.match /STARTTLS/
      outbound.write 'STARTTLS\r\n'
      TLSStarted = true
    else if data.match(/^220 /i) and TLSStarted is true
      outbound.setEncoding null
      outbound.removeAllListeners 'data'
      tls = TLS.connect
        socket: outbound
        rejectUnauthorized: false
        honorCipherOrder: true
      tls.once 'error', (err) =>
        if err and Object.keys(err).length
          log.error
            address: address
            err: err,
            "TLS stream"
        inbound.end()
      .setEncoding 'utf8'
      .on 'data', (data) =>
        log.trace "<~ #{data}"
        inbound.write data
      .once 'secureConnect', =>
        log.info address: address, "TLS connected (%s) with %s",
          if tls.authorized then 'authorized' else 'unauthorized',
          tls.getProtocol()
        tls.write ehlo
        inbound.pipe tls
        # tls.pipe inbound
      .once 'close', =>
        log.debug address: address, 'TLS connection closed'
        inbound.end()
        outbound.end()
    else if data.match /^250 /m
      inbound.write data
      log.warn address: address, 'no STARTTLS detected'
      outbound.removeAllListeners 'data'
      inbound.pipe outbound
      outbound.pipe inbound
    else
      inbound.write data
  inbound.once 'data', (data) =>
    log.trace address:address, ">> #{data}"
    ehlo = data
    outbound.write data

  outbound.connect options

