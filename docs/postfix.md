# Postfix configuration

## Setting

A self-hosted mail server, with capability to receive mail to several
domain names, with only a few real users (updating aliases can be done
by hand). Access to my ISP for e-mail sending if relay by an large
operator is required.

The server should behave as expected of a large email provider,
especially offer a submission port to send mail to any recipient (with
authentication).

The server may also serve as a relay host for a very limited number of
addresses used by me (and for which I know the passwords).

## Goals

Postfix must play many roles. Its role is to move mail from some machine to another, using the SMTP protocol. It must receive mail and forward it to the right place in a large diversity of cases:

  1. The server is responsible for some mail emitted locally (mostly
     administration stuff) and goes locally.
     
  2. The server is responsible for a few domains. It must accept
     submissions coming from any point of the network if they have a
     final destination it is responsible for. However, it must check if
     the emitter of the mail is somewhat a good player in the SMTP
     protocol.
  3. It is responsible for managing aliases, of which I use many. I
     actually have a "one target, one address" policy to know where spam
     comes from. Also, there are mails that should go to two users with
     one address, but not as a shared account.
  4. It is responsible for helping the local users to send through their
     email, from wherever they are. This is not required, but useful for
     my setup. There are three cases that must be dealt with:
      1. Emitter is authenticated, and emitter address is from a domain
         it is responsible for (as above). Then it must either deliver
         it, or ensure somebody else will.
      2. Emitter is authenticated, and emitter address is a registered
         address, with a registered smtp submission port that acts for
         this domain as just above. Then it must accept the mail and
         forward it to a remote registered smtp submission port.
      3. Emitter is authenticated, and none of the options above apply:
         it must try to deliver the mail (itself, or forward to another
         system).

This last case should, ideally, not happen because of **SPF**. SPF is a
protocol that ensures that each domain has a public limited range of
mail emission point (for the SMTP protocol), and if one tries to deliver
mail from outside this public range (which would be the last case
above), the email is bound to be rejected (either silently or not),
**and the emission point will be blacklisted for all smtp
communications** (since that emission point is our system, we do not
want that).

Note that `postfix` is **not responsible for**:

  * Transmitting the stored emails (the ones that are considered
    *received*) to the email client. This is the role of an
    [IMAP server or a POP server](courier.md).



## Basics

First, let's install: `apt install postfix postfix-cdb postfix-pcre libpam-pwdfile whois`

So, let's configure postfix.

First of all, we will have a generic smtpd server that will take care of
all domains for which we are responsible. A second smtpd server
(submission smtpd) will then be set up for authenticated submissions.

They will both share a lot of settings.

### Common settings

Some common (convenience settings) follow:
```sh
# We are up to date
compatibility_level = 3.5
# Who are we?
mydomain = example.com
myhostname = mail.example.com
# This last one may surprise, but we will never receive "local" mail, only "virtual domain mail"
mydestination =
# The server is not a client, so we don't notify incoming messages
biff = no
# Personal choice: no mail over 50MB. Considered a lot in many places.
message_size_limit = 50480000
# Notification of problems to postmaster (default is only resource,software)
notify_classes=bounce,resource,software
```

So the only surprising thing is that we disable the "local" mail delivery, preferring "virtual domain" mail delivery. This fits our needs, since the server is a mail server that will have no real users, except the admin, which will anyway also be a user of the virtual domain.

### Address rewriting and local administrative mail delivery

In our list of goals, the use case #1 (deliver mail locally) will be
merged with #2 and the local delivery will be done through address
rewriting.

So, let's concentrate on the address rewriting part. This is used only
for marginal cases here, namely:

  * root address, which I like to be distinguishable, and will be given
    their own aliases. If the mail server is called `box`, then I want
    the apparent address to be `root.box` and it delivered to me.
  * the `@mail.example.com` part should be rewritten to `@example.com`,
    because on the opposite, the server name should never appear in
    visible places.

For this, we will use a canonical mapping in `/etc/postfix/canonical`:
```
/root@box.localnet/     root.box@example.com
/root@box.example.com/     root.box@example.com
/^(.*)@box.localnet/        ${1}@example.com
/^(.*)@.*\.example.com/        ${1}@example.com
```
and type:
```sh
postconf canonical_maps=pcre:/etc/postfix/canonical
```

## Incoming mail (port 25)

This entry should serve only for email goal #2 above, i.e. mail whose
final destination is one of the domains we are responsible for. The SMTP
daemon will listen to port 25, and listed as MX in the domains.

First, we must cater to the possibility of TLS on this channel, without
enforcing it because public MX must allow clear communication according
to [RFC 2487](https://datatracker.ietf.org/doc/html/rfc2487).

```sh
CERTIFICATEDIR=/etc/letsencrypt/live/example.com
postconf smtpd_tls_cert_file=${CERTFICATEDIR}/fullchain.pem
postconf smtpd_tls_key_file=${CERTFICATEDIR}/privkey.pem
postconf smtpd_tls_session_cache_database='btree:${data_directory}/smtp_scache'
postconf smtpd_tls_security_level=may
```

Of course, I will use the certificates created in [Let's Encrypt setup](certbot.html). If you have your own certificates, adjust the paths.

Then, the emails must be *filtered*. This is done by using restrictions
at various levels of the SMTP transaction. The parameters are all called
`smtpd_something_restrictions`. First, we need to give a few ideas about
what is *safe* and what is *unsafe*. Since all my real users will submit
mail through the secure interface offered by goal #4, and each internal
machine will be setup so that they use the same interface, no
unauthentified SMTP communication will take place internally. Also, my
internal network has a wifi access, which cannot be guaranteed to be
safe. So **the internal network will be treated as hostile**. Also, I am
not reasonably sure to be able to deal with all the IPV6 funkiness for
now, so I limit the listening interfaces to IPV4[^1]. Thus it is
reasonable to use:

```sh
postconf mynetworks=127.0.0.0/8
postconf inet_protocols=ipv4
```

### smtpd restrictions

Now, we must filter the bad players. I took inspiration from
[this article](https://www.linuxbabe.com/mail-server/block-email-spam-postfix)
but some of these I disagree with. More will be done later (SPF policy
check, possibly greylisting and spam filtering), but for now, I just
want something reliable (the three measures I mentioned require more
plumbing).

The order of the protocol is client, HELO, sender, recipient, data, end of data.

So, let's start with some considerations. In 2023, I expected that mail servers won't be behind a completely anonymous IP. *People* may well be, but they usually forward their outgoing mail to some fixed-IP relay, because major players deny SMTP access to relays without PTR records.

But assuming the PTR record points back to the same IP as the origin is hard, because of, for example, shared IP address (with port mapping). Since my own setup couldn't check this, it seems hard to refuse the same from others.

So one can come up with various compromises between accepting all legitimate emails but also many spams (mainly those coming from botnets), or risking a few legitimate misses and filtering out much of the spam.

In the main smtpd daemon, SASL is ignored, since there will be a specific port to use for authenticated submission.

The strongest configuration for `smtpd_client_restrictions` would be
`permit_mynetworks reject_unknown_client_hostname`. A middle ground is
`permit_mynetworks reject_unknown_reverse_client_hostname` and a no-fail
policy (for legitimate emails to always pass) would be do put an empty
setting. In all cases, prepending a (intially empty) access table is a
good idea. If you want to add an exception, just add whatever
IP/hostname is causing a rejection to this file followed by space(s)
followed by the literal string `OK` (and issue `postmap
client_whitelist.cdb`). We will also add here some good behavior rule
such as `reject_unauth_pipelining`.

Then come HELO/EHLO restrictions. HELO should be made mandatory
(`helo_required=yes`). At this point, one can express a strong
commitment to RFC: `reject_invalid_helo_hostname
reject_non_fqdn_helo_hostname reject_unknown_helo_hostname` is a must,
but I think a (initially empty) access table should be made ready for
exceptions (`check_helo_access=cdb:helo_whitelist`).[^3]

The following restriction is the `smtpd_sender_restrictions` set. From
various readings, it looks like there is a small chance that badly
configured Exchange systems used badly formatted RCPT FROM: addresses in
2008, but I expect this is no more a problem. As always, let's include
also a whitelist (which can be a blacklist by adding REJECT instead of
OK).  So let's go with the triplet
`check_sender_access=cdb:sender_whitelist reject_non_fqdn_sender
reject_unknown_sender_domain`. This is quite basic and should be good
for even the less restrictive level. `permit_mynetworks` is probably
harmless there, too, but I expect our locally configured software to use
syntactically correct addresses anyway.

Then, the recipient restrictions. Here, we are on firm ground, because
the recipient is what we control. We can add `reject_non_fqdn_recipient
reject_unknown_recipient_domain reject_unknown_sender_domain
reject_unlisted_sender` quite safely to the classical `permit_mynetworks
check_sender_access cdb:recipient_whitelist`...`reject_unauth_destination`
[^2].  Again, we put a whitelist there (that can also be a blacklist),
but one has to be very careful to not add there recipients we won't be
able to deal with later.

As for the last two stages (data and end of data restrictions), I prefer
to go with a minimalistic test for `reject_unauth_pipelining` that
probably won't ever be used, since it is already written at the
`smtpd_client_restrictions`.

### More filtering

To explain later, but at this point, one should include setup for
various policy tools such as `SPF policy checker`, `postgrey`, `rspamd`
and other useful tools. These go into `smtpd`.

### Delivery

Remember that we have to know how to *deliver* the mails, i.e. storing
these somewhere so that another software may retrieve these and serve
them to the userx. I used to put lots of procmail rules acting on my
email, but nowadays, my setup is much simpler (and deals with sorting
and filtering on the other side of IMAP).

My setup is such that:

  * There is a specific user on my system that will own all mailboxes.
  * Same for the group
  * The enumeration of all real accounts will be in a table (given the
    immutability of my address base, a fixed table is enough)
  * The enumeration of aliases will be in another table (but for the
    same reasons, a fixed table is enough, too)
  * The second table will contain the `root` aliases, because of goal #1
    (remember we merged goal #1 into goal #2).

The first table will be generated from a script, the second one is
maintained by hand.

So let's add this:
```
virtual_mailbox_domains = example.com, example.net
virtual_mailbox_base = /home/vmail
virtual_mailbox_maps = hash:/etc/postfix/vmail_mailbox
virtual_minimum_uid = 1000
virtual_uid_maps = static:1000
virtual_gid_maps = static:100
virtual_alias_maps = hash:/etc/postfix/vmail_aliases
```

## SMTP submission (port 587)

We want a service similar to the smtp port, but reserved for authenticated access. More requirements, more trust. First, we have to copy the entry in `master.cf`.

```sh
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
```

These are a lot of lines to ensure that a line of master.cf reads `smtp       inet  n       -       y       -       -       smtpd`

Now, this submission port must have specific differences compared to the generic smtp service: we must enforce authentication there. Then, we will modify the restrictions used on smtp so that authentication uses the same level of trust than, for example, being a local emitter.

So first, we should replace (completely) `smtpd_client_restrictions`
with `permit_sasl_authenticated reject`. Because the session shouldn't
begin if the client is not authenticated on this port. Remember that
because we set `smtpd_delay_reject`, the client has all the time to
issue the authentication procedure (`client` restrictions are therefore
not dealt with until the recipient is chosen).

Since we will require authentication, and therefore secrets exchanges, we will also force encryption on the connection. Note that this is allowed because the smtp service on port 25 still exists and doesn't require authentication.
And since we want the authentication mechanism will be SASL (only on this port), let's enable this too (we don't need to disable it on port 25, because this is the default value). Also, for traceability, we will add a header line in the mail reflecting the SASL authentication.

```sh
postconf -P submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject
postconf -P submission/inet/smtpd_tls_security_level=encrypt
postconf -P submission/inet/smtpd_sasl_security_options=noanonymous
postconf -P submission/inet/smtpd_sasl_auth_enable=yes
postconf -P submission/inet/smtpd_sasl_authenticated_header=yes
```

Since we have more trust, we can also allow the server to make better
bounce management. We can also be a bit more demanding of the emitting
apps.

```sh
postconf -P submission/inet/strict_8bitmime=yes
postconf -P submission/inet/configuration delay_warning_time=1h
postconf -P submission/inet/confirm_delay_cleared=yes
```

TODO: see if `reject_authenticated_sender_login_mismatch=yes` could fit
there.

### SASL authentication

Now, we have to configure the SASL authentication. This is crucial for
our operation. There are currently two ways of SASL authentication for
postfix: using `libsasl2` from Cyrus (a full IMAP suite, but libsasl2 is
detachable from it), or `dovecot`. For historical reasons, I don't use
`dovecot` (if I remember correctly, the only reason is that I bumped
into failing support for UTF-8 at some point).

There is a
[Debian wiki article](https://wiki.debian.org/PostfixAndSASL#Implementation_using_Cyrus_SASL)
about this topic, with all sorts of technical explanations.

So the task it two-fold:

  * Setup a saslauthd instance that lives inside the chroot of our postfix instance
  * create a database of user+passwords in the SASL format

The first task goes as in the article quoted above:

```sh
echo "pwcheck_method: saslauthd" > /etc/postfix/sasl/smtpd.conf
echo "mech_list: CRAM-MD5 DIGEST-MD5 LOGIN PLAIN" >> /etc/postfix/sasl/smtpd.conf
grep -v ^# /etc/default/saslauthd | grep -v ^$ > /etc/default/saslauthd-postfix
echo 'START=yes' >> /etc/default/saslauthd-postfix
echo 'DESC="${DESC} for Postfix"' >> /etc/default/saslauthd-postfix
echo 'NAME="saslauthd-postf"' >> /etc/default/saslauthd-postfix
echo 'OPTIONS="-c -m /var/spool/postfix/var/run/saslauthd"' >> /etc/default/saslauthd-postfix
dpkg-statoverride --add root sasl 710 /var/spool/postfix/var/run/saslauthd
adduser postfix sasl
service saslauthd restart
```

Remark that authentication was delegated to PAM (linux authentication
framework). So we add file `/etc/pam.d/smtp` (the name of the file is the value of `smtpd_sasl_service`, by default `smtp`). *Note to self: why not `smtpd`? This would be more consistent, but would differ from many tutorials and the default value for, well, theoretical consistency.*

**Question:** *"why didn't we use another way to authenticate through SASL protocol?"* The alternative was ① to use direct authentication by postfix in a database managed through libsasl2, or ② use through remote IMAP login instead of ③ the proposed solution. Both of these variants work, especially since I have a table with all users and passwords in it. But... `courier-imap` can be made to authenticate through PAM, too, so changing PAM to a database request can be duplicated for both services. So that's one point *against* direct authentication in a specific file format (①). Also, I have a faint memory of troubles with the chroot that contains the running processes of `postfix` (this may be untrue, but what is clear is that the mux file of `saslauthd` is in the chroot, so the communication is OK through this UNIX-socket). On the other side, the variant ② is working. The `courier-authlib` software has many interfaces including database requests for authentication. However, this implies one more network connection, so that's least half a point for solution ③. Also, Apache (the web server) can also authenticate with PAM, which means web services for virtual users will also be easily reachable without duplicating the information (half-point, maybe?).

So we leave out `smtpd_sasl_type`, `smtpd_sasl_service` and `smtpd_sasl_path` to their default values (`cyrus`, `smtp`, `smtpd`).

Next, we finish the `postfix` configuration:

```sh
postconf cyrus_sasl_config_path=/etc/postfix/sasl
postconf smtpd_sasl_local_domain=example.com
```

and the PAM configuration in `/etc/pam.d/smtp`:
```
auth required pam_pwdfile.so debug pwdfile=/etc/saslauthd_virtual_passwd
account required pam_permit.so
```

The second part (database filling) is just creating a line for each user in `/etc/saslauthd_virtual_passwd`. Here is the shell function that does this in my account management script:
```sh
addtosasldb() {
    login="$1"
    passwd="$2"
    log 2 "Updating $login sasldb password"
    # mkpasswd is from the whois package
    (echo -n "${login}@${MAINDOMAIN}:";echo "$passwd" | mkpasswd -s -m sha256crypt) >> ${SASLAUTHDPASSWD}
}
```

## Account management

The account management script was mentioned above. The [account script](account.html) is fully documented in its own page, but it is a shell script that builds the necessary databases from a simple text file. In the future, it will be replaced with a simple web interface (that can do import/export of the data).

## Mail emission (outgoing)

Please see the graphic to understand the
[transmission of outgoing email **with relay for our domains**](https://github.com/jcdubacq/jcdubacq.github.io/blob/main/docs/postfix-graphics.md#outgoing-smtp-with-relay),
and the next one to understand the
[transmission of outgoing email **without relay for our domains**](https://github.com/jcdubacq/jcdubacq.github.io/blob/main/docs/postfix-graphics.md#outgoing-smtp-without-relay). A
third graphic underlines what happens for
[outgoing email where the sender is not from our domains](https://github.com/jcdubacq/jcdubacq.github.io/blob/main/docs/postfix-graphics.md#relaying-smtp)
(this shouldn't happen in many systems, but is the goal 4.2 of my design
needs).

In the first graphic, the first exchange (Emitter⮂mail.example.com) has
already been done. The second exchange with relay
(mail.example.com⮂relay.isp.com) will be dealt with here.

The second graphic is quite similar, but the problem is that the other checks made at the last exchange (before *accepts mail*) can lead to a refusal. The various reasons in my case are:

  * Reverse DNS is OK (I have a PTR record), but the lookup of this PTR
    record in non-existent
  * My IP never changed (well, when I switched from DSL line to optic
    fiber, but at this point I really changed the network I used), but
    some blocking lists consider this is part of a dynamic IP allocation
    range. This may be true (I just never changed, that doesn't mean
    it's *static*). And some ISPs block
    
Remember the discussion I made in **smtp restrictions** above? Well,
that's the same one, but reversed.

Obviously, for the domains I am responsible for, I should use the *direct SMTP approach*. That's the essence of self-hosting. But it fails, and it fails too much. Since I care more about my emails arriving than some principles I cannot uphold anyway, I will use relaying to my ISP. I know that if I respect some rules, it will happily accept my emails on the submission port (with authentication). Without authentication, it accepts (as it should) only the emails it is the final destination of.

If one doesn't have such a relay available, I know some are available
either free (for a low traffic: I found one in three minutes for 200
emails/day) or for a fee.

The third graphic is, in fact, what happens when we *relay* a mail. As per goal 4.2, we want to do it only if we know who we are relaying, and are able to contact in his stead the correct provider. This means registered addresses, with password to the ISP. If we were to use a generic smtp service, the delivery may fail for many reasons, but the first is that either the domain declares SPF records and we won't be in it (so all sites checking SPF policy will refuse our mails), or there is no SPF (and nowadays, it's the site that won't be able to deliver mails to major mail providers).


TODO

[^1]: Clearly, there shouldn't be any problem listening on IPV6 nowadays. However, this requires caution, as always. This footnote should be deleted when I get the time to rewrite this document and be sure it's without problems.

[^2]: we can trust our networks, since we restricted it to our self-address (127.0.0.1/8). Do not add permit_mynetworks everywhere if you have a network with potentially hostile elements, such as a wifi network (no wifi network is completely secure).

[^3]: At this point, there is **no reason** to give special permissions for clients emanating from `mynetworks` (using `permit_mynetworks`), nor later to authenticated submitters, because being trusted doesn't mean emitting bad syntax.
