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

  * [Challenge script](https://github.com/jcdubacq/jcdubacq.github.io/blob/main/certbot-bmn/certbot-bmn-jcdubacq-challenge.sh)
  * [Cleanup script](https://github.com/jcdubacq/jcdubacq.github.io/blob/main/certbot-bmn/certbot-bmn-jcdubacq-cleanup.sh) (executed automatically after challenge)
  * [Global cleanup](https://github.com/jcdubacq/jcdubacq.github.io/blob/main/certbot-bmn/certbot-bmn-jcdubacq-globalcleanup.sh) (tries to remove all former challenges, to be executed manually in case something goes wrong)

The main script (challenge) is doing the following:

  * Sets up basic variables (access to BookMyName account, logs, cleanup)
  * Deal with the generic subdomain case by creating a DOMAIN variable which is the challenged domain or the base domain in case of generic subdomain
  * Inserts the DNS record using wget
  * Waits till the record is visible in some public DNS server (`8.8.8.8` is a public DNS server operated by Google, there are others).
  * Cares to not go beyond 40 minutes of waiting time (my personal test sometimes reached 9 minutes, so that should be enough).
  * Logs all of this, and exits.

For a new machine, I need to issue the following:

```sh
# Execute as root (or sudo everything)
apt install certbot bind9-dnsutils
mkdir -p /root/lib/certbot/secrets
chmod 700 /root/lib/certbot/secrets
cd /root/lib/certbot

# Set BMNUSER and BMNPASS in shell-script syntax in /root/lib/certbot/secrets/bmnpasswords.sh
echo 'BMNUSER="Jwhatever"' > /root/lib/certbot/secrets/bmnpasswords.sh
echo 'BMNPASS="wh4tEver"' >> /root/lib/certbot/secrets/bmnpasswords.sh

# Install the three utilies in /root/lib/certbot
wget 'https://raw.githubusercontent.com/jcdubacq/jcdubacq.github.io/main/certbot-bmn/certbot-bmn-jcdubacq-challenge.sh'
wget 'https://raw.githubusercontent.com/jcdubacq/jcdubacq.github.io/main/certbot-bmn/certbot-bmn-jcdubacq-cleanup.sh'
wget 'https://raw.githubusercontent.com/jcdubacq/jcdubacq.github.io/main/certbot-bmn/certbot-bmn-jcdubacq-globalcleanup.sh'
chmod +x /root/lib/certbot/certbot-bmn-jcdubacq-*.sh

# Run the first certification process and answer all questions truthfully
certbot certonly --manual --preferred-challenges=dns --manual-auth-hook /root/lib/certbot/certbot-bmn-jcdubacq-challenge.sh --manual-cleanup-hook /root/lib/certbot/certbot-bmn-jcdubacq-cleanup.sh -d example.com -d mail.example.com
```

That's about it. If all is correct, a few minutes between each challenge should elapse (4-8 minutes when I tried), and you should get certificates in `/etc/letsencrypt/live/example.com/` (of course, replace `example.com` with your own domain everywhere, unless you are the owner of `example.com` yourself)[^1].

By default, a cron job/systemd timer is installed when installing certbot, which will try to renew the certificate as often as needed (twice a day, which may be too frequently, but monthly is certainly not frequent enough; I trusted the Debian maintainers to do the right thing here). `certbot renew` is the command that should be issued by your cron job.

Note that you can add more subdomains by issuing (as root) `certbot --expand newsubdomain.example.com`.

[^1]: This shouldn't happen because of [RFC2606](https://www.rfc-editor.org/rfc/rfc2606.txt).