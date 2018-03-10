#!/usr/bin/env coffee
#

net = require 'net'
# util = require 'util'
TLS = require 'tls'
Original = require './getOriginalDst'

LISTEN =
  port: 25125
  host: '127.0.0.1'

LOCAL = '10.20.30.38' # '54.38.39.66'
LOCAL = '54.38.39.66'
LOCAL = '192.168.0.65'

server = net.createServer (socket) ->
  console.log
    address: server.address()
    original: Original socket
  createOutboundConnection socket

server.listen LISTEN.port, LISTEN.host

createOutboundConnection = (inbound) ->
  message = ehlo = ''
  inbound.setEncoding 'utf8'
  inbound.on 'error', (err) =>
    console.error "Inbound:", err
  inbound.on 'close', =>
    console.log 'Inbound Connection Closed'
    outbound?.end()
  original = Original inbound
  options =
    port: 2525 # original.port
    host: original.address
    localAddress: LOCAL
  outbound = new net.Socket
  outbound.setEncoding 'utf8'
  outbound.on 'error', (err) =>
    console.error err
  .on 'connect', =>
    console.log 'connected'
  .on 'close', =>
    console.log 'Outbound Connection Closed'
    inbound.end()
  .on 'data', startData = (data) =>
    process.stdout.write "<< #{data}"
    if data.match /STARTTLS/
      [ data ] = data.split /\r?\n/
      message = data.replace /^250-(.*)/, "250 $1\r\n"
      data = ''
      outbound.write 'STARTTLS\r\n'
    else if data.match /^220 Ready to start TLS/
      data = ''
      outbound.setEncoding null
      outbound.removeAllListeners 'data'
      tls = TLS.connect
        socket: outbound
        rejectUnauthorized: false
        honorCipherOrder: true
      tls.on 'data', (data) =>
        process.stdout.write "TLS: #{data}"
        # inbound.write data
      tls.on 'error', (err) =>
        console.log 'TLS', err
      .setEncoding 'utf8'
      .on 'secureConnect', =>
        console.log "TLS Connected: ",
          if tls.authorized then 'authorized' else 'unauthorized'
        console.log tls.getCipher(), tls.getProtocol()
        tls.write ehlo
        inbound.pipe tls
        tls.pipe inbound
      .on 'close', =>
        console.log 'TLS Connection Closed'
    else if data.match /^250 /m
      console.log 'No STARTTLS Detected'
      outbound.removeAllListeners 'data'
      inbound.pipe outbound
      outbound.pipe inbound
    inbound.write data
  inbound.once 'data', (data) =>
    process.stdout.write ">> #{data}"
    ehlo = data
    outbound.write data

  outbound.connect options

