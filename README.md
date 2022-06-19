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
