#!/usr/bin/env python3

# Test connecting using tls to the mta-ssl on port 465
import smtplib
import sys
import json

context = json.load(open('../context.json'))
print(json.dumps(context))
sys.exit(1)

(host, port, user, passw) = sys.argv[1].split(':')
print(f"Host and port and user and passw are {host}, {port}, {user}, {passw}")


# initialize connection to our email server, we will use Outlook here
smtp = smtplib.SMTP_SSL(host, port=port)

smtp.ehlo()  # send the extended hello to our server
print("Got through ehlo")
# smtp.starttls()  # tell server we want to communicate with TLS encryption

smtp.login(user, passw)  # login to our email server
print("Logged in")

msg = f"""Subject: test
From: {user}

Hi
"""
smtp.sendmail('spacey@spacey.org', user,
              msg)

smtp.quit()  # finally, don't forget to close the connection
