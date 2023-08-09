# Let's Encrypt setup

My DNS registrar and server is
[Bookmyname](https://www.bookmyname.com/), a somewhat tech-friendly
(meaning non-tech-hostile) registrar operated as a subcompany of Iliad,
the company behind Free.fr, one of the large telecom company in France.

There is an [API](https://fr.faqs.bookmyname.com/frfaqs/dyndns) that is usable to modify the DNS records of your domains, at least for what I need: publishing TXT records for my domain.

Certbot is the interface to [Let's Encrypt](https://letsencrypt.org/fr/), an initiative to further the use of certificates for a safer internet. It is sponsored by really big names (Chrome, AWS, Mozilla, Cisco, EFF, Meta, IBM, etc.) and operated as a non-profit, so it's pretty reliable. I need cryptography signature to work, but my use is non-professional, so not paying is a feature.

Certbot uses several methods to ensure that you are in control of the domain it signs. The three methods are `http`, `https` and `dns`, and the first two require a direct access to ports 80 or 443 of the bare domain name (e.g. https://example.com/). Since I am setting up a mail server which may or **may not** be the web server for the domain, I am settling for `dns` authentication of my ownership of the domain.

Fortunately, it is possible to ask the `certbot` program to issue the challenges to a script, which permits to inject the challenges in the DNS records. This was [already made for BookMyName](https://wiki.jaxx.org/misc/scripts/letsencrypt-bookmyname-dnschallenge) but the script was a bit too crude for my taste, and I wanted to understand what I did. So I rewrote it (using the tools I prefer).

So I built three scripts:

  * Challenge script
  * Cleanup script (executed automatically after challenge)
  * Global cleanup (tries to remove all former challenges, to be executed manually in case something goes wrong)

The main script (challenge) is

For a new machine, I need to issue the following:

```sh
# Execute as root (or sudo everything)
apt install certbot bind9-dnsutils
mkdir -p /root/lib/certbot/secrets
chmod 700 /root/lib/certbot/secrets

# Set BMNUSER and BMNPASS in shell-script syntax in /root/lib/certbot/secrets/bmnpasswords.sh
echo 'BMNUSER="Jwhatever"' > /root/lib/certbot/secrets/bmnpasswords.sh
echo 'BMNPASS="wh4tEver"' >> /root/lib/certbot/secrets/bmnpasswords.sh

# Install the three utilies in /root/lib/certbot
chmod +x /root/lib/certbot/bmn-jcdubacq-*.sh

# Run the first certification process and answer all questions truthfully
certbot certonly --manual --preferred-challenges=dns --manual-auth-hook /root/lib/certbot/bmn-jcdubacq-challenge.sh --manual-cleanup-hook /root/lib/certbot/bmn-jcdubacq-cleanup.sh -d example.com -d mail.example.com

'''
