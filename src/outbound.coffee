#!/usr/bin/env coffee
#

os  = require 'os'
net = require 'net'
TLS = require 'tls'
DNS = require('dns').promises
Bunyan = require 'bunyan'

Original = require './get-original-dst'
Package  = require '../package.json'


CONFIG = switch os.hostname()
  when 'prog', 'spectre'
    port: 25125
    host: '127.0.0.1'
    lookup: os.hostname()
    local: '10.20.30.20'
    outboundPort: 25
  when 'pt'
    port: 25
    host: '127.0.0.1'
    lookup: [
      'pt.may.be'
      'cgp.might.be'
      'outbound.might.be'
      'spare.might.be'
    ]
    local: []
    helo: 'mail.inspired-networks.co.uk'
  when 'dis'
    port: 25
    host: '127.0.0.1'
    lookup: [
      'secure-1.might.be'
      'secure-2.might.be'
      'secure-3.might.be'
    ]
    local: []
    helo: 'mail.inspired-networks.co.uk'
  else
    throw new Error "No config found for #{os.hostname()}"

log = Bunyan.createLogger
  name: 'outbound-smtp'
  serializers:
    err: Bunyan.stdSerializers.err
  streams:
    [
      level: 'debug'
      path: '/var/log/outbound-smtp/debug.log'
      type: 'rotating-file'
      period: '1d'
      count: 14
    ,
      level: 'trace'
      path: '/var/log/outbound-smtp/trace.log'
      type: 'rotating-file'
      period: '1d'
      count: 2
    ]

do ->
  if Array.isArray CONFIG.lookup
    Resolver = DNS.Resolver
    resolver = new Resolver
    # Son't use local servers as they'll screw up the local host
    resolver.setServers [
      '8.8.8.8'
      '8.8.4.4'
    ]
    local = await Promise.all ( resolver.resolve4 host for host in CONFIG.lookup )
    CONFIG.local = local.flat 3
    log.debug "local = #{CONFIG.local.join ", "}"

log.info "Server started: version #{Package.version}"

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
  [ local, reverse ] = if Array.isArray CONFIG.local
    ptr = Math.floor Math.random() * CONFIG.local.length
    [
      CONFIG.local[ptr]
      CONFIG.lookup[ptr]
    ]
  else [ CONFIG.local, CONFIG.lookup ]
  log.debug "local = #{local}, reverse = \"#{reverse}\""
  options =
    port: CONFIG.outboundPort ? original.port
    host: original.address
    localAddress: local
  outbound = new net.Socket
  outbound.setEncoding 'utf8'
  outbound.once 'error', (err) =>
    log.error
      address: address
      err: err,
      "outbound stream"
    inbound.end()
  .once 'connect', =>
    log.debug
      address: address
      local: outbound.localAddress
    , "outbound connected"
  .once 'close', =>
    log.debug address: address, "outbound closed"
    inbound.end()
  .on 'data', startData = (data) =>
    if data.match /^[45]\d\d/
      log.warn
        address: address
        local: outbound.localAddress
      , "<< #{data}"
    else
      log.trace
        address: address
        local: outbound.localAddress
      , "<< #{data}"
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
        if data.match /^[45]\d\d/
          log.warn
            address: address
            local: outbound.localAddress
          , "<~ #{data}"
        else
          log.trace
            address: address
            local: outbound.localAddress
          , "<~ #{data}"
        inbound.write data
      .once 'secureConnect', =>
        log.info address: address, "TLS connected (%s) with %s",
          if tls.authorized then 'authorized' else 'unauthorized',
          tls.getProtocol()
        tls.write ehlo
        inbound.on 'data', (data) =>
          if data.match /^(MAIL|REPT|DATA|QUIT)/
            log.trace address: address, "~> #{data}"
          tls.write data
        # inbound.pipe tls
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
    ehlo = data.replace CONFIG.helo, reverse
    outbound.write ehlo

  outbound.connect options

