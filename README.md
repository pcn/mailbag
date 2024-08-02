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
~~I haven't dived into why, or maybe how to better do this, but it seems
to me that there is a communications channel that I'm missing that's
required for the mta to communicate with the courierd to properly
deliver local mail. When they're not running in the same container, enqueued
mail gets bounched or dropped (via backscatter protection) so I'm
going to create 2 courier directories and mount one each for the msa and mta,
and run the courierd in each of those containers.~~

Identified, still needs fixing: need a common temp dir to be
mounted. On an old .deb-based installation, it happens in
`/var/lib/courier/tmp/`

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


## The context file
In the context required on the host, the list of domains in the
`mta.accept_mail_for` list will be rendered via the templates that are
copied into the mta container at build time so that it can receive
email for those and only those domains.

The context file needs to be placed on the host, outside of the containers, so it can be mapped into the 
containers for rendering (e.g. mta esmtpacceptmailfor at startup) and so it can be used to
extract required values for the unit files (e.g network variables)

The context file will be placed in `/etc/mailbag/context.json`, and
must be based on the contents of `examples/example-context.json`

Unit files will extract keys from the context via jq

## Current todo, in priority order

- [X] Fix logging so that it comes out of stdout and is handled by docker, better yet systemd
- [X] Confirm mta+starttls works
- [X] spin up impad-ssl
- [X] Figure out story for auto-building of dbs at startup (spam IPs, userdb, etc.)
- [X] Figure out how to start authdaemond in each container so the local socket is available
- [ ] document context for each component, add render-template to each container, run on startup with a bound context file
- [ ] tinydns under runit working
- [ ] document how tinydns is configured to work; using `make` on the host?

- [ ] Figure out story for auto-renewal of certs
- [ ] Figure out+document k9+mutt+offlineimap3+mu4e with imap
- [X] Build images via github actions and distribute via ghcr.io
- [ ] Make generating the context.json easier so that the containers can be configured

### Current blocker
document context file


### Past issues: courier-mtpd not working over ssl/tls/starttls
solution: courier doesn't fool around with `\n` pretending to be `\r\n` and `openssl s_client`
doesn't do what telnet does and provide a `\r` for free. So yeah, it works.

This is deeply discouraging, but it seems that when esmptd is invoked from couriertls,
the esmtpd just reads and doesn't process anything. 

This is what a trace on the process looks like:

```
brk(0x55ca39ac5000)                     = 0x55ca39ac5000
chdir("/usr/lib/courier")               = 0
fcntl(0, F_SETFL, O_RDONLY|O_NONBLOCK)  = 0
fcntl(1, F_SETFL, O_RDONLY|O_NONBLOCK)  = 0
access("/etc/courier/vhost.172.18.0.2", F_OK) = -1 ENOENT (No such file or directory)
socket(AF_UNIX, SOCK_DGRAM|SOCK_CLOEXEC, 0) = 5
connect(5, {sa_family=AF_UNIX, sun_path="/dev/log"}, 110) = 0
openat(AT_FDCWD, "/etc/courier/esmtptimeout", O_RDONLY) = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/courier/esmtptimeoutdata", O_RDONLY) = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/courier/esmtpgreeting", O_RDONLY) = -1 ENOENT (No such file or directory)
openat(AT_FDCWD, "/etc/courier/me", O_RDONLY) = -1 ENOENT (No such file or directory)
uname({sysname="Linux", nodename="testmail-mta.rton.me", ...}) = 0
openat(AT_FDCWD, "/usr/lib/x86_64-linux-gnu/gconv/gconv-modules.cache", O_RDONLY) = 6
newfstatat(6, "", {st_mode=S_IFREG|0644, st_size=27002, ...}, AT_EMPTY_PATH) = 0
close(6)                                = 0
futex(0x7fcfed33ea6c, FUTEX_WAKE_PRIVATE, 2147483647) = 0
brk(0x55ca39ae7000)                     = 0x55ca39ae7000
brk(0x55ca39adf000)                     = 0x55ca39adf000
pselect6(2, NULL, [1], NULL, {tv_sec=300, tv_nsec=0}, NULL) = 1 (out [1], left {tv_sec=299, tv_nsec=999997391})
writev(1, [{iov_base="220 ", iov_len=4}, {iov_base="testmail-mta.rton.me ESMTP", iov_len=26}, {iov_base="\r\n", iov_len=2}], 3) = 32
rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[PIPE], sa_flags=SA_RESTORER|SA_RESTART, sa_restorer=0x7fcfed166520}, {sa_handler=SIG_DFL, sa_mask=[], sa_flags=0}, 8) = 0
openat(AT_FDCWD, "/etc/localtime", O_RDONLY|O_CLOEXEC) = 6
newfstatat(6, "", {st_mode=S_IFREG|0644, st_size=114, ...}, AT_EMPTY_PATH) = 0
newfstatat(6, "", {st_mode=S_IFREG|0644, st_size=114, ...}, AT_EMPTY_PATH) = 0
read(6, "TZif2\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\1\0\0\0\4\0\0\0\0\0\0UTC\0TZif2\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\1\0\0\0\4\0\0\0\0\0\0UTC\0\nUTC0\n", 4096) = 114
lseek(6, -60, SEEK_CUR)                 = 54
read(6, "TZif2\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\1\0\0\0\4\0\0\0\0\0\0UTC\0\nUTC0\n", 4096) = 60
close(6)                                = 0
sendto(5, "<22>Jun 22 21:18:27 courieresmtpd-ssl: started,ip=[::ffff:76.121.130.175],port=[54510]", 86, MSG_NOSIGNAL, NULL, 0) = 86
openat(AT_FDCWD, "/etc/courier/sizelimit", O_RDONLY) = 6
newfstatat(6, "", {st_mode=S_IFREG|0644, st_size=8, ...}, AT_EMPTY_PATH) = 0
read(6, "1000000\n", 4096)              = 8
close(6)                                = 0
pselect6(1, [0], NULL, NULL, {tv_sec=600, tv_nsec=0}, NULL) = 1 (in [0], left {tv_sec=597, tv_nsec=959076613})
read(0, "ehlo baby\n", 5120)            = 10
pselect6(1, [0], NULL, NULL, {tv_sec=598, tv_nsec=0}, NULL) = 1 (in [0], left {tv_sec=597, tv_nsec=431048060})
read(0, "\n", 5110)                     = 1
pselect6(1, [0], NULL, NULL, {tv_sec=598, tv_nsec=0}, NULL) = 1 (in [0], left {tv_sec=593, tv_nsec=737487866})
read(0, "help me out here\n", 5109)     = 17
pselect6(1, [0], NULL, NULL, {tv_sec=593, tv_nsec=0}, NULL) = 1 (in [0], left {tv_sec=592, tv_nsec=82476151})
read(0, "\n", 5092)                     = 1
pselect6(1, [0], NULL, NULL, {tv_sec=592, tv_nsec=0}, NULL <detached ...>
```

There should be a response to the ehlo

### Non-goals
#### starttls
Something is happening between the courieresmtpd and couriertls process where the pipe
seems to die. This is making startls challening, and it shouldn't be? I'm not sure
what I'm missing, exactly, but I'm going to skip that and start an smtp+ssl port and
do mail submission over that port



## Build containers

The makefile builds containers, which is equivalent to the dockerfiles themselves. So just :
```
make
``` 

which runs the `build-artifacts` target which also generates necessary prerequisites.


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

