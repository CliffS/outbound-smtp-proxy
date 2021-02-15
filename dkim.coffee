#!/usr/bin/env coffee
#

fs = require 'fs'

{ dkimSign } = require 'mailauth/lib/dkim/sign'

message = fs.readFileSync '/home/cliff/tmp/Re: FW: Mail Delivery System.eml'

# console.log message.toString()

dkimSign message,
  signatureData: [
    signingDomain: 'might.be'
    selector: 'rsa'
    privateKey: fs.readFileSync '/home/cliff/tmp/privkey.pem'
  ]
.then (result) ->
  console.log result.errors if result.errors.length
  console.log result.signatures
.catch (err) ->
  console.log err
