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


### Gravelines NAT

#### On dis we need:

sysctl -w net.ipv4.ip_forward=1
ip route add 104.47.0.0/16 via 10.4.147.95 dev ens8

#### On outbound we need:

sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING ! -d 10.40.0.0/16 -o ens3 -j SNAT --to-source 188.165.11.148
ip route add 51.195.228.80/30 via 10.4.183.104


