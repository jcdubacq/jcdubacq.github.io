#!/bin/sh
MAINDOMAIN=example.com
OTHERDOMAINS="example.net example.org"
# This should be the name in the certficate
MAILSERVER=mail
MBOXUSER=mail
# Depends on your letsencrypt setup, maybe juste .../${REALDOMAIN}
CERTFICATEDIR=/etc/letsencrypt/live/${MAILSERVER}.${REALDOMAIN}
if [ -f "/root/lib/postfix/secrets/setup" ]; then
    . /root/lib/postfix/secrets/setup
fi

REALHOST=$(hostname)
REALDOMAIN=$(domainname)
if [ -z "$REALHOST" ]||[ -z "$REALDOMAIN" ]; then
    echo "${REALHOST}.${REALDOMAIN} is incomplete full name"
    exit 1
fi
if [ -z "$SAFETY" ]; then
    SAFETY=1
fi

cd /etc/postfix

# Common setup
postconf compatibility_level=3.5
postconf mydomain=${MAINDOMAIN}
postconf myhostname=${MAILSERVER}.${MAINDOMAIN}
postconf mydestination=
postconf biff=no
postconf message_size_limit=50480000

# Canonical
echo "/root@(.*)"'\.'"${REALDOMAIN}/     root.${1}@${MAINDOMAIN}" > canonical
if [ "$MAINDOMAIN" != "$REALDOMAIN" ]; then
    echo "/root@${REALHOST}.${MAINDOMAIN}/     root.${REALHOST}@${MAINDOMAIN}" >> canonical
fi
echo "/^(.*)@${REALHOST}.${REALDOMAIN}/        ${1}@${MAINDOMAIN}" >> canonical
echo "/^(.*)@.*"'\.'"${MAINDOMAIN}/        ${1}@${MAINDOMAIN}" >> canonical

postconf canonical_maps=pcre:/etc/postfix/canonical

# TLS for incoming mail
postconf smtpd_tls_cert_file=${CERTFICATEDIR}/fullchain.pem
postconf smtpd_tls_key_file=${CERTFICATEDIR}/privkey.pem
postconf smtpd_tls_session_cache_database='btree:${data_directory}/smtp_scache'
postconf smtpd_tls_security_level=may

# STMPD restrictions
postconf smtpd_delay_open_until_valid_rcpt=no


for x in client helo sender; do
    touch ${i}_whitelist.cdb
    postmap ${i}_whitelist.cdb
done

postconf "smtpd_helo_restrictions=check_helo_access=cdb:helo_whitelist reject_invalid_helo_hostname reject_non_fqdn_helo_hostname reject_unknown_helo_hostname"
postconf "smtpd_sender_restrictions=check_sender_access=cdb:sender_whitelist reject_non_fqdn_sender reject_unknown_sender_domain"
postconf "smtpd_recipient_restrictions=check_helo_access=cdb:helo_whitelist reject_non_fqdn_recipient reject_unknown_recipient_domain reject_unknown_sender_domain reject_unlisted_sender reject_unauth_destination"

CLIENTBASE="smtpd_client_restrictions=permit_mynetworks check_client_access=cdb:client_whitelist reject_unauth_pipelining"
if [ "$SAFETY" = 1 ]; then
    postconf "$CLIENTBASE"
elif [ "$SAFETY" = 2 ]; then
    postconf "$CLIENTBASE reject_unknown_reverse_client_hostname"
elif [ "$SAFETY" = 3 ]; then
    postconf "$CLIENTBASE reject_unknown_client_hostname"
fi

# Virtual delivery

UID=$(getent passwd $MBOXUSER|cut -f3 -d:)
GID=$(getent passwd $MBOXUSER|cut -f4 -d:)

postconf "virtual_mailbox_domains=${MAINDOMAIN} ${OTHERDOMAINS}"
postconf "virtual_mailbox_base=/home/vmail"
postconf "virtual_mailbox_maps=hash:/etc/postfix/vmail_mailbox"
postconf "virtual_minimum_uid=${UID}"
postconf "virtual_uid_maps=static:${UID}"
postconf "virtual_gid_maps=static:${GID}"
postconf "virtual_alias_maps=hash:/etc/postfix/vmail_aliases"

