# Install docker

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

## Install emacs

```
sudo apt install -y emacs-nox
```
