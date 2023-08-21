# Courier setup

Goal: courier-imap-ssl available for IMAPS access. No other access is required. For webmail, simple IMAP access might be useful, but it's very easy to add after. However, pop3 will also be supported as an available service.

## SSL setup

A valid certificate will be required. As [ours](certbot.html) is provided by `certbot` from Let's Encrypt, the best place is `/etc/letsencrypt/renewal-hooks/post/COURIER.sh` where we install this [small script]().

```sh
#!/bin/sh
MAILDOMAIN=example.com
cat "/etc/letsencrypt/live/${MAILDOMAIN}/privkey.pem" "/etc/letsencrypt/live/${MAILDOMAIN}/fullchain.pem" > /etc/courier/imapd.pem
cp /etc/courier/imapd.pem /etc/courier/pop3d.pem
service courier-imap-ssl restart
service courier-pop-ssl restart
```

The script builds a combined PEM file, with the private key+authentication chain, as this is what is required by Courier.

## Account setup

Account setup is a mess. For e-mail, you need at least to sync passwords

```sh
# Answer yes to directory creation
apt install courier-imap
```
