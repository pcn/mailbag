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

## Context file

This example uses `bust-mta.spacey.org` as the dns name that will the hostname 
and the file path that was created above. Put this into `context.json`

```json
{
  "mda": {
    "mail_path": {
      "host": "/opt/vmail",
      "container": "/opt/vmail"
    }
  },
  "mta": {
    "dns_name": "bust-mta.spacey.org",
    "tls_keyfile": "/etc/letsencrypt/live/bust.spacey.org/fullchain.pem",
    "tls_certfile": "/etc/letsencrypt/live/bust.spacey.org/cert.pem"
  },
  "imap": {
    "dns_name": "bust-imap.spacey.org"
  },
  "postgres": {
    "password": "BIG_SECRET",
    "name": "vmaildb",
    "container_label": "postgres:14.3-alpine"
  },
  "docker": {
    "network_name": "vmail"
  },
  "userdb": {
    "directory": "/etc/authlib/userdb"
  }
}
```

## And render
Using the result of `cargo build`:

```
pcn@peternorton-7f1729:~/mailbag$ templater/target/debug/render-template  --context context.json --template unit-files/courier-mta.service.template ; echo
[Unit]
Description=courier-mta Service
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker exec %n stop
ExecStartPre=-/usr/bin/docker rm %n
ExecStart=/usr/bin/docker run --rm --name %n \
    --hostname bust-mta.spacey.org \
    -v /etc/letsencrypt/live/bust.spacey.org/fullchain.pem:/usr/lib/courier/share/esmtpd.pem \
    -v /opt/vmail:/opt/vmail \
    -p 25:25 \
    %n:latest

ExecStop=/usr/bin/docker kill %n

[Install]
WantedBy=default.target
```
