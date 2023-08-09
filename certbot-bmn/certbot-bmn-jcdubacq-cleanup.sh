#!/bin/sh
# These are redefined in bmnpasswords to real value of the bmnaccount
BMNUSER="Jwhatever"
BMNPASS="wh4tEver"

. /root/lib/certbot/secrets/bmnpasswords.sh

CLEANUP="/root/lib/certbot/cleanuplist.txt"
LOGFILE="/root/lib/certbot/log.txt"

DOMAIN="${CERTBOT_DOMAIN#\*.}"

echo "$(date) Called cleanup for ${DOMAIN}" >> "${LOGFILE}"
env|grep CERTBOT_ >> "${LOGFILE}"

echo "_acme-challenge.${DOMAIN}:${CERTBOT_VALIDATION}" >> "${CLEANUP}"
wget  -q -O - "https://${BMNUSER}:${BMNPASS}@www.bookmyname.com/dyndns/?hostname=_acme-challenge.$DOMAIN&type=txt&ttl=300&do=remove&value=\"${CERTBOT_VALIDATION}\"" >> "${LOGFILE}"

if [ $? -gt 0 ]; then
    echo "$(date) DNS cleanup failed for ${DOMAIN}" >> "${LOGFILE}"
    exit 1
fi

grep -v "^${DOMAIN}:${CERTBOT_VALIDATION}" < "${CLEANUP}" > "${CLEANUP}.new"
mv "${CLEANUP}.new" "${CLEANUP}"
