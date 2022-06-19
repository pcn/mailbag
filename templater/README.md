# Simple tool to expand some templated values

This is just [the example render-template from minijinja](https://github.com/mitsuhiko/minijinja/tree/main/examples/render-template).

## Request certs that will be referenced later, using the web server challenge

```
sudo certbot certonly --standalone -d bust.spacey.org,bust-mta.spacey.org,bust-imap.spacey.org
[ answer some questions here ... and then ]

Obtaining a new certificate
Performing the following challenges:
http-01 challenge for bust-imap.spacey.org
http-01 challenge for bust-mta.spacey.org
http-01 challenge for bust.spacey.org
Waiting for verification...
Cleaning up challenges

```

This will produce a key and a cert with all of the provided names as
subject alternative names (presuming they're all on the same IP address)

## Annoted context file

This example uses `bust-mta.spacey.org` as the dns name that the 

```json
{
  "mta": {
    "dns-name": "bust.spacey.org",
    "tls-keyfile": "/etc/letsencrypt/live/bust.spacey.org/fullchain.pem",
    "tls-certfile": "/etc/letsencrypt/live/bust.spacey.org/cert.pem"
  },
  "imap": {
    "dns-name": "thename-imap.zone.tld"
  }
}
```
