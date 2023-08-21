# Graphics for explaining mail transmission

These graphics use [Mermaid](https://mermaid.js.org/), but for some
reason they don't render on Github pages, but they do (as of 08/2023) on
github.com. Go figure.

## Outgoing smtp with rela
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
    Destination->mail.example.com: checks that SPF records of mail.example.com
    mail.example.com-->Destination: has listed relay.isp.com SMTP servers in the SPF records for example.com
    Destination-->>relay.isp.com: accepts mail (final delivery)
```


