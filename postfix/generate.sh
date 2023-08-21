#!/bin/sh
MAINDOMAIN=example.com
OTHERDOMAINS="example.net example.org"
# This should be the name in the certficate
MAILSERVER=mail
MBOXUSER=mail
# Depends on your letsencrypt setup, maybe juste .../${REALDOMAIN}
CERTFICATEDIR=/etc/letsencrypt/live/${MAILSERVER}.${REALDOMAIN}
REALHOST=$(hostname)
REALDOMAIN=$(domainname)
if [ -f "/root/lib/postfix/secrets/setup" ]; then
    . /root/lib/postfix/secrets/setup
fi

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
echo "/root@(.*)"'\.'"${REALDOMAIN}/     root."'${1}'"@${MAINDOMAIN}" > canonical
if [ "$MAINDOMAIN" != "$REALDOMAIN" ]; then
    echo "/root@${REALHOST}.${MAINDOMAIN}/     root.${REALHOST}@${MAINDOMAIN}" >> canonical
fi
echo "/^(.*)@${REALHOST}.${REALDOMAIN}/        "'${1}'"@${MAINDOMAIN}" >> canonical
echo "/^(.*)@.*"'\.'"${MAINDOMAIN}/        "'${1}'"@${MAINDOMAIN}" >> canonical

postconf canonical_maps=pcre:/etc/postfix/canonical

# TLS for incoming mail
postconf smtpd_tls_cert_file=${CERTFICATEDIR}/fullchain.pem
postconf smtpd_tls_key_file=${CERTFICATEDIR}/privkey.pem
postconf smtpd_tls_session_cache_database='btree:${data_directory}/smtp_scache'
postconf smtpd_tls_security_level=may

# STMPD restrictions
postconf smtpd_delay_open_until_valid_rcpt=no


for x in client helo sender recipient; do
    touch ${x}_whitelist
    postmap ${x}_whitelist
done

postconf "notify_classes=bounce,resource,software"

postconf "smtpd_helo_restrictions=check_helo_access=cdb:helo_whitelist reject_invalid_helo_hostname reject_non_fqdn_helo_hostname reject_unknown_helo_hostname"
postconf "smtpd_sender_restrictions=check_sender_access=cdb:sender_whitelist reject_non_fqdn_sender reject_unknown_sender_domain"
postconf "smtpd_recipient_restrictions=permit_mynetworks permit_sasl_authenticated check_helo_access=cdb:recipient_whitelist reject_non_fqdn_recipient reject_unknown_recipient_domain reject_unknown_sender_domain reject_unlisted_sender reject_unauth_destination"

postconf "smtpd_data_restrictions=reject_unauth_pipelining"
postconf "smtpd_end_of_data_restrictions=reject_unauth_pipelining"

CLIENTBASE="smtpd_client_restrictions=permit_mynetworks permit_sasl_authenticated check_client_access=cdb:client_whitelist reject_unauth_pipelining"
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
postconf "virtual_mailbox_maps=cdb:/etc/postfix/vmail_mailbox"
postconf "virtual_minimum_uid=${UID}"
postconf "virtual_uid_maps=static:${UID}"
postconf "virtual_gid_maps=static:${GID}"
postconf "virtual_alias_maps=cdb:/etc/postfix/vmail_aliases"

# Create submission/inet entry in master.cf matching smtp/inet

if [ $(postconf -M  submission/inet 2> /dev/null | wc -l) = 0 ]; then
    a=$(postconf -M smtp/inet|sed -e 's/^smtp/submission/g')
    postconf -M -e submission/inet="$a"
fi

postconf -F smtp/inet | while read x; do
    if [ "${x%% *}" != "smtp/inet/service" ]&&[ "${x%% *}" != "smtp/inet/command" ]; then
        v=${x#* = }
        k=${x%% *}
        kk="submission/${k#*/}"
        vv=$(postconf -F "${kk}")
        if [ "$v" != "${vv#* = }" ]; then
            echo "Warning: $x != $vv"
        fi
    fi
done
postconf -e -F submission/inet/command=smtpd
postconf -P submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject
postconf -P submission/inet/smtpd_tls_security_level=encrypt
postconf -P submission/inet/smtpd_sasl_auth_enable=yes
postconf -P submission/inet/smtpd_sasl_authenticated_header=yes
postconf -P submission/inet/cyrus_sasl_config_path=/etc/postfix/sasl
postconf -P submission/inet/smtpd_sasl_local_domain=${MAINDOMAIN}

POSTFIXSASLCONF=/etc/postfix/sasl/smtpd.conf
echo "pwcheck_method: saslauthd" > ${POSTFIXSASLCONF}
echo "mech_list: CRAM-MD5 DIGEST-MD5 LOGIN PLAIN" >> ${POSTFIXSASLCONF}


SASLCONFBASE=/etc/default/saslauthd
SASLCONF=${SASLCONFBASE}-postfix
grep -v ^# /etc/default/saslauthd | grep -v ^$ > $SASLCONF
echo 'START=yes' >> $SASLCONF
echo 'DESC="${DESC} for Postfix"' >> $SASLCONF
echo 'NAME="saslauthd-postf"' >> $SASLCONF
echo 'OPTIONS="-c -m /var/spool/postfix/var/run/saslauthd"' >> /etc/default/saslauthd-postfix
dpkg-statoverride --remove /var/spool/postfix/var/run/saslauthd
dpkg-statoverride --add root sasl 710 /var/spool/postfix/var/run/saslauthd
groups postfix | fmt -w 1|grep '^sasl$' > /dev/null || adduser postfix sasl

SASLAUTHDPASSWD=/etc/saslauthd_virtual_passwd
touch $SASLAUTHDPASSWD
chown root:shadow $SASLAUTHDPASSWD
chmod 610 $SASLAUTHDPASSWD
echo "auth required pam_pwdfile.so debug pwdfile=$SASLAUTHDPASSWD" > smtp
echo "account required pam_permit.so" >> smtp
service saslauthd restart




service postfix restart
systemctl daemon-reload