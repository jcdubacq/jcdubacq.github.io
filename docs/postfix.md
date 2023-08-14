# Postfix configuration

## Goals

Postfix must play many roles. Its role is to move mail from some machine to another, using the SMTP protocol. It must receive mail and forward it to the right place in a large diversity of cases:

  1. It is responsible for some mail emitted locally (mostly administration stuff) and goes locally.
  2. It is responsible for a few domains. It must accept submissions coming from any point of the network if they have a final destination it is responsible for. However, it must check if the emitter of the mail is somewhat a good player in the SMTP protocol.
  3. It is responsible for managing aliases, of which I use many. I actually have a "one target, one address" policy to know where spam comes from. Also, there are mails that should go to two users with one address, but not as a shared account.
  4. It is responsible for helping the local users to send through their email, from wherever they are. This is not required, but useful for my setup. There are three cases that must be dealt with:
    1. Emitter is authenticated, and emitter address is from a domain it is responsible for (as above). Then it must either deliver it, or ensure somebody else will.
    2. Emitter is authenticated, and emitter address is a registered address, with a registered smtp submission port that acts for this domain as just above. Then it must accept the mail and forward it to the registered smtp submission port.
    3. Emitter is authenticated, and none of the options above apply: it must try to deliver the mail (itself, or forward to another system).

This last case should, ideally, not happen because of **SPF**. SPF is a protocol that ensures that each domain has a public limited range of mail emission point (for the SMTP protocol), and if one tries to deliver mail from outside this public range (which would be the last case above), the email is bound to be rejected (either silently or not), **and the emission point will be blacklisted for all smtp communications** (since that emission point is our system, we do not want that).

Note that `postfix` is **not responsible for**:

  * Transmitting the stored emails (the ones that are considered "arrived") to the email client. This is the role of an [IMAP server or a POP server](courier.md).

## Basics

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
```

So the only surprising thing is that we disable the "local" mail delivery, preferring "virtual domain" mail delivery. This fits our needs, since the server is a mail server that will have no real users, except the admin, which will anyway also be a user of the virtual domain.

### Address rewriting and local administrative mail delivery

In our list of requirements, the use case #1 (deliver mail locally) will be merged with #2 and the local delivery will be done through address rewriting.

So, let's concentrate on the address rewriting part. This is used only for marginal cases here, namely:

  * root address, which I like to be distinguishable, and will be given their own aliases. If the mail server is called `box`, then I want the apparent address to be `root.box` and it delivered to me.
  * the `@mail.example.com` part should be rewritten to `@example.com`, because on the opposite, the server name should never appear in visible places.

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

This entry should serve only for email goal #2 above, i.e. mail whose final destination is one of the domains we are responsible for. The SMTP daemon will listen to port 25, and listed as MX in the domains.

First, we must cater to the possibility of TLS on this channel, without enforcing it because public MX must allow clear communication according to [RFC 2487](https://datatracker.ietf.org/doc/html/rfc2487).

```sh
CERTIFICATEDIR=/etc/letsencrypt/live/example.com
postconf smtpd_tls_cert_file=${CERTFICATEDIR}/fullchain.pem
postconf smtpd_tls_key_file=${CERTFICATEDIR}/privkey.pem
postconf smtpd_tls_session_cache_database='btree:${data_directory}/smtp_scache'
postconf smtpd_tls_security_level=may
```

Of course, I will use the certificates created in [Let's Encrypt setup](certbot.html). If you have your own certificates, adjust the paths.

Then, the emails must be *filtered*. This is done by using restrictions
at various levels of the SMTP transaction. The parameters are all called `smtpd_something_restrictions`. First, we need to give a few ideas about what is *safe* and what is *unsafe*. Since all my real users will submit mail through the secure interface offered by goal #4, and each internal machine will be setup so that they use the same interface, no unauthentified SMTP communication will take place internally. Also, my internal network has a wifi access, which cannot be guaranteed to be safe. So **the internal network will be treated as hostile**. Also, I am not reasonably sure to be able to deal with all the IPV6 funkiness for now, so I limit the listening interfaces to IPV4[^1]. Thus it is reasonable to use:
```sh
postconf mynetworks=127.0.0.0/8
postconf inet_protocols=ipv4
```

### smtpd restrictions

Now, we must filter the bad players. I took inspiration from [this article](https://www.linuxbabe.com/mail-server/block-email-spam-postfix) but with some caveats. More will be done later (SPF policy check, possibly greylisting and spam filtering), but for now, I just want something reliable (the three measures I mentioned require more plumbing).

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
exceptions (`check_helo_access=cdb:helo_whitelist`).

The following restriction is the sender restriction. From various
readings, it looks like there is a small chance that badly configured
Exchange systems used badly formatted RCPT FROM: addresses in 2008, but
I expect this is no more a problem. As always, let's include also a
whitelist (which can be a blacklist by adding REJECT instead of OK).  So
let's go with the triplet `check_sender_access=cdb:sender_whitelist
reject_non_fqdn_sender reject_unknown_sender_domain`. This is quite
basic and should be good for even the less restrictive level.

Then, the recipient restrictions. Here, we are on firm ground, because
the recipient is what we control. We can add `reject_non_fqdn_recipient
reject_unknown_recipient_domain reject_unknown_sender_domain
reject_unlisted_sender` quite safely to the classical `permit_mynetworks
check_sender_access cdb:recipient_whitelist`...`reject_unauth_destination`
[^2].  Again, we put a whitelist there (that can also be a blacklist),
but one has to be very careful to not add there recipients we won't be
able to deal with later.

As for the last two stages (data and end of data restrictions), I prefer to go with a minimalistic test for `reject_unauth_pipelining` that probably won't ever be used, since it is already written at the `smtpd_client_restrictions`. 

### More filtering

To explain later, but at this point, one should include setup for various policy tools such as `SPF policy checker`, `postgrey`, `rspamd` and other useful tools. These go into `smtpd`.

### Delivery

Remember that we have to know how to *deliver* the mails. I used to put lots of procmail rules, but nowadays, my setup is much simpler (and deals with sorting and filtering on the other side of IMAP).

My setup is such that:

  * There is a specific user on my system that will own all mailboxes.
  * Same for the group
  * The enumeration of all real accounts will be in a table (given the immutability of my address base, a fixed table is enough)
  * The enumeration of aliases will be in another table (but for the same reasons, a fixed table is enough, too)
  * The second table will contain the `root` aliases, because of goal #1 (remember we merged goal #1 into goal #2).

The first table will be generated from a script, the second one is maintained by hand.

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

TODO
```
configuration delay_warning_time = 1h
confirm_delay_cleared = yes
```

## Mail emission (outgoing)

TODO

[^1]: Clearly, there shouldn't be any problem listening on IPV6 nowadays. However, this requires caution, as always. This footnote should be deleted when I get the time to rewrite this document and be sure it's without problems.
[^2]: we can trust our networks, since we restricted it to our self-address (127.0.0.1/8). Do not add permit_mynetworks everywhere if you have a network with potentially hostile elements, such as a wifi network (no wifi network is completely secure).