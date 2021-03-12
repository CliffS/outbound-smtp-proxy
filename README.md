# smtp-proxy-outbound
This will listen on a port for a redirected SMTP connection
and upgrade it to TLS if possible.

### building

```
$ npm install
$ npm run build
```

### iptables

To redirect the port you need:
```
 iptables -t nat -A OUTPUT -p tcp --dport 25 --source 51.89.226.10 -j DNAT --to-destination 127.0.0.1:25
```
### systemd

The file in the systemd directory needs to be copied into
`/etc/systemd/system`.


