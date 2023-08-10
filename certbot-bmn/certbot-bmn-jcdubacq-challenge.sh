#!/bin/sh

# These are redefined in bmnpasswords to real value of the bmnaccount
BMNUSER="Jwhatever"
BMNPASS="wh4tEver"

. /root/lib/certbot/secrets/bmnpasswords.sh

DNSTESTSERVER=8.8.8.8
CLEANUP="/root/lib/certbot/cleanuplist.txt"
LOGFILE="/root/lib/certbot/log.txt"

DOMAIN=${CERTBOT_DOMAIN#\*.}

echo "$(date) Called challenge to domain ${DOMAIN} for ${CERTBOT_DOMAIN}" >> $LOGFILE
env|grep CERTBOT_ >> $LOGFILE


echo "${DOMAIN}:${CERTBOT_VALIDATION}" >> $CLEANUP
wget  -q -O - "https://${BMNUSER}:${BMNPASS}@www.bookmyname.com/dyndns/?hostname=_acme-challenge.$DOMAIN&type=txt&ttl=300&do=add&value=\"${CERTBOT_VALIDATION}\""  >> $LOGFILE

if [ $? -gt 0 ]; then
    echo "$(date) DNS addition failed for $DOMAIN" >> $LOGFILE
    exit 1
fi

counter=0
while true; do
    if [ "$counter" -gt 40 ]; then
        echo "$(date) DNS propagation failed for $DOMAIN" >> $LOGILE
        exit 1
    fi
    counter=$((counter+1))
    echo -n "$(date) Verification #${counter}..." >> $LOGFILE
    RECORD=$(dig @$DNSTESTSERVER _acme-challenge.$DOMAIN TXT +short | tr -d "\""  | grep "$CERTBOT_VALIDATION")
    echo -n "returned ${RECORD}..." >> $LOGFILE
    if [ "${RECORD}" = "$CERTBOT_VALIDATION" ]; then
        echo "propagated!" >> $LOGFILE
        sleep 5
        exit 0
    else
        echo "not yet!" >> $LOGFILE
        sleep 60
    fi
done
exit 2 # Should never reach this point
