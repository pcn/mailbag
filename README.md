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

## courier userdb
Courier's userdb provides a reasonable source format for virtual
hosting users It makes sense to me to have a startup script so that a
host will have `/etc/courier/userdb` be a mounted docker volume which
is just a file mode `0600` containing data for vmail users. On
starting a container, whether it be mta or imapd or whatever, the db
would get created on startup in that container

It's a bit wasteful of CPU resources, but I don't expect the DB to be rebuilt often, and
it prevents stale data from ending up on the host or effects of upgrades going weirdly.

The makeuserdb script can still be run within the container when/if needed

## Current todo, in priority order

- [ ] Fix logging so that it comes out of stdout and is handled by docker, better yet systemd
- [ ] Confirm mta+starttls works
- [ ] spin up impad
- [ ] Figure out story for auto-building of dbs at startup (spam IPs, userdb, etc.)
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

