#!/bin/sh
MAILDOMAIN=example.com
cat "/etc/letsencrypt/live/${MAILDOMAIN}/privkey.pem" "/etc/letsencrypt/live/${MAILDOMAIN}/fullchain.pem" > /etc/courier/imapd.pem
cp /etc/courier/imapd.pem /etc/courier/pop3d.pem
service courier-imap-ssl restart
service courier-pop-ssl restart
