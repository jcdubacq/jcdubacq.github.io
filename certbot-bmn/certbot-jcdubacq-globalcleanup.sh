#!/bin/sh
# These are redefined in bmnpasswords to real value of the bmnaccount
BMNUSER="Jwhatever"
BMNPASS="wh4tEver"

. /root/lib/certbot/secrets/bmnpasswords.sh

CLEANUP="/root/lib/certbot/cleanuplist.txt"

echo "Called global cleanup"

cp ${CLEANUP} ${CLEANUP}.new
while read line 0<&3; do
    DOMAIN=${line%%:*}
    CERTBOT_VALIDATION=${line#*:}
    wget  -q -O - "https://${BMNUSER}:${BMNPASS}@www.bookmyname.com/dyndns/?hostname=_acme-challenge.$DOMAIN&type=txt&ttl=300&do=remove&value=\"${CERTBOT_VALIDATION}\""
    if [ $? -gt 0 ]; then
        echo "$(date) DNS cleanup failed for ${DOMAIN}"
        exit 1
    fi
    grep -v "^${DOMAIN}:${CERTBOT_VALIDATION}" < ${CLEANUP}.new > ${CLEANUP}.newnew
    mv ${CLEANUP}.newnew ${CLEANUP}.new
done 3< ${CLEANUP}
mv ${CLEANUP}.new ${CLEANUP}
