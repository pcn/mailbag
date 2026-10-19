#!/usr/bin/env python3
"""Ask an SMTP listener whether it accepts a recipient, without sending mail.

    smtp_rcpt.py --host farout-mta.rton.me --port 25 --to someone@example.org

Connects, upgrades with STARTTLS (verifying the certificate; --cafile for a
private CA), sends MAIL FROM:<> and RCPT TO:<to>, then RSET and QUIT, so no
message is ever queued. Prints "RCPT <to> <code>" and exits 0 whenever the
conversation completed, whatever the code: goss asserts on the code. Exits 1
only when the conversation itself failed. Standard library only.
"""
import argparse
import smtplib
import ssl
import sys


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--host", required=True)
    p.add_argument("--port", required=True, type=int)
    p.add_argument("--to", required=True)
    p.add_argument("--cafile", help="trust only this CA bundle (default: system trust)")
    a = p.parse_args()
    try:
        s = smtplib.SMTP(a.host, a.port, timeout=30)
        s.ehlo()
        s.starttls(context=ssl.create_default_context(cafile=a.cafile))
        s.ehlo()
        s.mail("")
        code, _ = s.rcpt(a.to)
        s.rset()
        s.quit()
    except Exception as e:
        print(f"FAIL {type(e).__name__}: {e}")
        sys.exit(1)
    print(f"RCPT {a.to} {code}")


if __name__ == "__main__":
    main()
