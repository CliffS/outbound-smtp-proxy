# smtp-proxy-outbound
This will listen on a port for a redirected SMTP connection
and upgrade it to TLS if possible.

To redirect the port you need:

```
iptables -t nat -A OUTPUT -p tcp --dport 25 --source 178.32.61.145 -j DNAT --to-destination 127.0.0.1:25
```
