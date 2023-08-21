# Graphics for explaining mail transmission

These graphics use [Mermaid](https://mermaid.js.org/), but for some
reason they don't render on Github pages, but they do (as of 08/2023) on
github.com. Go figure.

## Outgoing smtp with relay

```mermaid
sequenceDiagram
    participant Emitter
    participant mail.example.com
    participant relay.isp.com
    participant Destination
    Emitter->>mail.example.com: submission (SASL auth with "emitter@example.com")
    mail.example.com-->>Emitter: accepts email
    mail.example.com->>relay.isp.com: submission (SASL auth with "account@isp.com"
    Note right of relay.isp.com: hopefully doesn't check mismatch between<br/>SASL login (account@isp.com)<br/>envelope From (emitter@example.com)
    relay.isp.com-->>mail.example.com: accepts email
    relay.isp.com->>Destination: generic smtp (no authentication)
    Destination->>mail.example.com: checks SPF records of mail.example.com
    mail.example.com-->>Destination: has listed relay.isp.com SMTP servers in the SPF records for example.com, OK
    Destination-->>relay.isp.com: accepts mail (final delivery)
```
## Outgoing smtp without relay

```mermaid
sequenceDiagram
    participant Emitter
    participant mail.example.com
    participant Destination
    Emitter->>mail.example.com: submission (SASL auth with "emitter@example.com")
    mail.example.com-->>Emitter: accepts email
    mail.example.com->>Destination: generic smtp (no authentication)
    Destination->>mail.example.com: checks SPF records of mail.example.com
    mail.example.com-->>Destination: has listed itself in the SPF records for example.com, OK
    Destination-->>relay.isp.com: accepts mail (final delivery)
```


## Relaying smtp

```mermaid
sequenceDiagram
    participant Emitter
    participant mail.example.com
    participant otherexample.net
    participant Destination
    Emitter->>mail.example.com: submission (SASL auth with "emitter@example.com") with sender someone@otherexample.net
    critical Account details for address?
    mail.example.com-->>Emitter: accepts email
    option No, tries to deliver (itself or through relay)
    mail.example.com->>Destination: generic smtp (no authentication)
    Destination->>otherexample.net: checks SPF records of otherexample.net
    otherexample.net-->>Destination: not listed, KO
    Destination-->>mail.example.com: refuses mail
    option No, tries to forward to otherexample.net through generic smtp
    mail.example.com->>otherexample.net: generic smtp (no authentication)
    otherexample.net-->>mail.example.com: I am the sender, not the destination. KO.
    Note right of otherexample.net: If otherexample.net accepts these emails,<br/>Then it is an open relay and will be blacklisted quickly
    option Yes, forwards with authentication
    mail.example.com->>otherexample.net: submission (SASL auth with "someone@otherexample.net") with sender someone@otherexample.net
    otherexample.net-->>mail.example.com: accepts mail
    otherexample.net->>Destination: delivers mail by usual means
    end
```


