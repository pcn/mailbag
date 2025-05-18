# Simple tool to expand some templated values

This is just [the example render-template from minijinja](https://github.com/mitsuhiko/minijinja/tree/main/examples/render-template).

## Prerequisites

### System Dependencies

On a fresh Debian-based system, install required packages:

```bash
sudo apt update
sudo apt install -y git build-essential pkg-config libssl-dev
```

### Rust Toolchain

This tool is written in Rust and requires the Rust toolchain to build. If you don't have Rust installed, visit [https://www.rust-lang.org/tools/install](https://www.rust-lang.org/tools/install) and follow the installation instructions:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

## Request certs that will be referenced later, using the web server challenge

```
sudo certbot certonly --standalone -d mail.example.com,smtp.example.com,imap.example.com
[ answer some questions here ... and then ]

Obtaining a new certificate
Performing the following challenges:
http-01 challenge for imap.example.com
http-01 challenge for smtp.example.com
http-01 challenge for mail.example.com
Waiting for verification...
Cleaning up challenges

```

This will produce a key and a cert with all of the provided names as
subject alternative names (presuming they're all on the same IP address)

## Context file

The file `examples/example-context.json` should be moved to context.json, and 
the following entries must be changed:

- mta.dns_name
- mta.accept_mail_for[]
- msa.dns_name
- imapd_ssl.dns_name
- domain.name
- domain.zone


## And render
Using the result of `cargo build`:

```
$ templater/target/debug/render-template --context context.json --template unit-files/courier-mta.service.template ; echo
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
