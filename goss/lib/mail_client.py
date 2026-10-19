#!/usr/bin/env python3
"""One mail round trip for goss/mail-delivery.yaml: submit a uniquely tagged
message on one port, then poll IMAPS until it arrives and check it.

    mail_client.py --host farout-mta.rton.me --port 587 --tls starttls --auth \
        --imap-host farout-imap.rton.me --user canary@example.org \
        --password-file /root/.mailbag-canary-pass \
        --token mailbag-delivery-20261019T031533Z-587 \
        --expect-by courier-msa --expect-with ESMTPSA

Exits 0 only when the message was accepted, retrieved within --timeout, its
body carries the token, and a Received header shows it came in through the
expected deployment with the expected protocol. The test message is deleted
afterwards unless --keep. Standard library only, so it runs with the node's
plain python3. The password is read from a file and never printed.
"""
import argparse
import email
import imaplib
import re
import smtplib
import ssl
import sys
import time


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--host", required=True, help="submission hostname")
    p.add_argument("--port", required=True, type=int)
    p.add_argument("--tls", required=True, choices=["starttls", "implicit"])
    p.add_argument("--auth", action="store_true", help="SMTP AUTH before sending")
    p.add_argument("--imap-host", required=True)
    p.add_argument("--imap-port", type=int, default=993)
    p.add_argument("--user", required=True, help="the mailbox: sender, login and reader")
    p.add_argument("--to", help="recipient, e.g. an alias of --user (default: --user)")
    p.add_argument("--password-file", required=True)
    p.add_argument("--cafile", help="trust only this CA bundle (default: system trust)")
    p.add_argument("--token", required=True, help="unique Subject and body marker")
    p.add_argument("--expect-by", required=True,
                   help="deployment whose pod must appear in Received, e.g. courier-mta")
    p.add_argument("--expect-with", required=True, help="e.g. ESMTPS or ESMTPSA")
    p.add_argument("--timeout", type=float, default=90.0, help="seconds to wait for delivery")
    p.add_argument("--keep", action="store_true", help="leave the message in the INBOX")
    return p.parse_args()


def fail(port, what, err=None):
    detail = f": {type(err).__name__}: {err}" if err is not None else ""
    print(f"[{port}] FAIL {what}{detail}")
    sys.exit(1)


def submit(a, password, ctx):
    to = a.to or a.user
    msg = (f"From: {a.user}\r\nTo: {to}\r\nSubject: {a.token}\r\n"
           f"\r\n{a.token}\r\n")
    if a.tls == "implicit":
        s = smtplib.SMTP_SSL(a.host, a.port, context=ctx, timeout=30)
        s.ehlo()
    else:
        s = smtplib.SMTP(a.host, a.port, timeout=30)
        s.ehlo()
        s.starttls(context=ctx)
        s.ehlo()
    tls = f"{s.sock.version()} {s.sock.cipher()[0]}"
    if a.auth:
        s.login(a.user, password)
    refused = s.sendmail(a.user, [to], msg)
    s.quit()
    if refused:
        raise smtplib.SMTPRecipientsRefused(refused)
    return tls


def retrieve(a, password, ctx):
    """Poll until the token's message arrives; return (imap, msg id, message)."""
    im = imaplib.IMAP4_SSL(a.imap_host, a.imap_port, ssl_context=ctx)
    im.login(a.user, password)
    deadline = time.monotonic() + a.timeout
    while True:
        im.select("INBOX")
        _, data = im.search(None, "SUBJECT", f'"{a.token}"')
        ids = data[0].split()
        if ids:
            _, parts = im.fetch(ids[-1], "(BODY.PEEK[])")
            return im, ids[-1], email.message_from_bytes(parts[0][1])
        if time.monotonic() >= deadline:
            im.logout()
            return None, None, None
        time.sleep(2)


def main():
    a = parse_args()
    with open(a.password_file) as f:
        password = f.read().strip()
    ctx = ssl.create_default_context(cafile=a.cafile)  # verifies chain and hostname

    try:
        tls = submit(a, password, ctx)
    except Exception as e:
        fail(a.port, "submit", e)
    print(f"[{a.port}] submitted {a.token} over {tls}{' with AUTH' if a.auth else ''}")

    started = time.monotonic()
    try:
        im, mid, msg = retrieve(a, password, ctx)
    except Exception as e:
        fail(a.port, "IMAPS retrieval", e)
    if msg is None:
        fail(a.port, f"not delivered to {a.user} within {a.timeout:.0f}s")
    print(f"[{a.port}] retrieved over IMAPS after {time.monotonic() - started:.1f}s")

    ok = True
    body = msg.get_payload(decode=True) or b""
    if a.token.encode() not in body:
        print(f"[{a.port}] FAIL body does not carry the token")
        ok = False
    # "by courier-msa-<replicaset hash>-<pod suffix> with ESMTPSA": exactly two
    # suffix segments, so courier-mta never matches a courier-mta-ssl pod.
    want = re.compile(rf"\bby {re.escape(a.expect_by)}-[a-z0-9]+-[a-z0-9]+ "
                      rf"with {re.escape(a.expect_with)}\b")
    received = [" ".join(h.split()) for h in msg.get_all("Received", [])]
    match = next((h for h in received if want.search(h)), None)
    if match:
        print(f"[{a.port}] Received: {want.search(match).group(0)}")
    else:
        print(f"[{a.port}] FAIL no Received header 'by {a.expect_by}-... with {a.expect_with}'")
        for h in received:
            print(f"        Received: {h[:160]}")
        ok = False

    if not a.keep:
        im.store(mid, "+FLAGS", "\\Deleted")
        im.expunge()
    im.logout()

    if ok:
        print(f"[{a.port}] OK")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
