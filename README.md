# Goals

- Run a self-hosted MTA+MSA 
- Run a self-hosted IMAPd
- Support virtualhosted email
- Renewal of certs via letsencrypt with short certs
- Map stateful things from the host
- systemd unit files for each component to be run that mounts the appropriate host directories as volumes

Use certbot to renew the cert for the site. Since certbot associates one cert per IP address,
assume one cert per hostname, so it would probably make sense that for a host called `<foo>.<domain>` create the following names A records
as well:
- `<foo>-mta.<domain>`
- `<foo>-imap.<domain>`

etc.

## Daemons and their groupings
I haven't dived into why, or maybe how to better do this, but it seems
to me that there is a communications channel that I'm missing that's
required for the mta to communicate with the courierd to properly
deliver local mail. When they're not running in the same container, enqueued
mail gets bounched or dropped (via backscatter protection) so I'm
going to create 2 courier directories and mount one each for the msa and mta,
and run the courierd in each of those containers.

## courier userdb
Courier's userdb provides a reasonable source format for virtual
hosting users It makes sense to me to have a startup script so that a
host will have `/etc/courier/userdb` be a mounted docker volume which
is just a file mode `0600` containing data for vmail users. On
starting a container, whether it be mta or imapd or whatever, the db
would get created on startup in that container

It's a bit wasteful of CPU resources, but I don't expect the DB to be rebuilt often, and
it prevents stale data from ending up on the host or effects of upgrades going weirdly.

The makeuserdb script can still be run within the container when/if needed. 

Creating a user is done like this...

And the offlineimap doesn't do hmac-sha1 or hmac-sha256. So hmac-md5 is it for now?

```
userdbpw -hmac-sha256 | userdb -f /etc/authlib/userdb/rton.me  spacey@testmail.rton.me set hmac-sha256pw
userdbpw -hmac-md5 | userdb -f /etc/authlib/userdb/rton.me spacey@testmail.rton.me set hmac-md5pw
userdb -f /etc/authlib/userdb/rton.me spacey@testmail.rton.me set gid=300
userdb -f /etc/authlib/userdb/rton.me spacey@testmail.rton.me set uid=300
userdb -f /etc/authlib/userdb/rton.me spacey@testmail.rton.me set home=/opt/vmail/testmail.rton.me/spacey
makeuserdb
# Now make the maildir
/usr/lib/courier/bin/maildirmake /opt/vmail/testmail.rton.me/spacey/Maildir
chown -R vmail:vmail /opt/vmail/testmail.rton.me/spacey

makeuserdb
```

In the context required on the host, the list of domains in the `mta.accept_mail_for` list will be
compiled into the mta container so that it can receive email for those and only those domains.

## Current todo, in priority order

- [X] Fix logging so that it comes out of stdout and is handled by docker, better yet systemd
- [X] Confirm mta+starttls works
- [X] spin up impad-ssl
- [X] Figure out story for auto-building of dbs at startup (spam IPs, userdb, etc.)
- [X] Figure out how to start authdaemond in each container so the local socket is available
- [ ] Troubleshoot why starttls seems to freeze up

- [ ] Figure out story for auto-renewal of certs
- [ ] Figure out+document k9+mutt+mu4e with imap


## Build containers

Run the build script, phase 1 build deb packages from the current courier-mta:

```
./build-base.sh
```

That will produce a tarball with all of the courier deb packages.

Then produce container images for each services:

```
./build-services.sh
```

## On the internet-facing host

### Update your local rsyslog to get more mail info

Set your rsyslog.conf to log mail.info so the local rsyslog will
handle the mail log

```
mail.info                       -/var/log/mail.info
```

### Install docker

From [the instructions for using a repo](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository).

In case the instructions change, this is what it is:

## 2022-06-18 instructions

```
sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```
Add the gpg key to the keyring
```
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

Add the apt repository
```
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
```

and install the docker engine etc.

```
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

#### Install emacs

```
sudo apt install -y emacs-nox
```

### Install unit files

```
sudo cp unit-files/courier-mta.service /etc/systemd/system/
```

Enable the unit

```
sudo systemctl enable courier-mta.service
```

### Make the path for the virtual mail storage

```
mkdir /opt/vmail/<the zone>
```


## Make a virtual users in the database

