# Tech notes from @jcdubacq

## Installation of mail server

  * [Bare-bones system setup](system.html)
  * [Certbot setup for Bookmyname](certbot.html)


### Choice of servers

  * SMTP: postfix, because it works. I managed to understand vaguely how, so that's a bonus.
  * IMAP+SASL: courier vs dovecot : theoretically, it shouldn't matter, but as it is the purveyor of the SASL authentication, which I use, it changes the settings of postfix, so that's it also. I historically used courier-imap, but have used dovecot at some point, and may switch again. Switching would make a good exercise.
  * fetchmail: I use external accounts, so fetchmail will bring all accounts into local ones. I like having all my mail in one place for archival.

I will detail soon how I set up all of these.

