# zos
zos is container manager for [zero-os operating system](https://github.com/threefoldtech/0-core) and it can be used on local or remote zos machine (development mode)

## Nim installation
https://nim-lang.org/install.html (0.19 is required)

## Nimble installation
https://github.com/nim-lang/nimble#installation (0.9 is required)


### Binaries
- [Linux](https://github.com/threefoldtech/zos/releases) (dynamically linked requires pcre, and openssl)

## Building the project

- clone `git clone https://github.com/threefoldtech/zos`
- switch to directory `cd zos` 
- build using `nimble zos`

### Building on OSX 
```bash
#example script to install

brew install nim 
mkdir -p  ~/code/github;cd ~/code/github
git clone https://github.com/threefoldtech/zos 
cd zos
sudo nimble build -d:ssl --threads:on
sudo cp zos /usr/local/bin
```
> You can use install_osx.sh the repositor

#### Note
- if you face this error on MacOS while installing nimble
```
Could not download: Please upgrade your OpenSSL library, it does not support the necessary protocols. OpenSSL error is: error:14077410:SSL routines:SSL23_GET_SERVER_HELLO:sslv3 alert handshake failure
```

use this link to fix it (MacOS Version: 10.11.6 & Openssl Version: 0.9.8zh )

https://github.com/nim-lang/nimble#troubleshooting

### Examples on OSX

```bash
#example script to install
bash install_osx.sh
```

## Commands documentation
zos commands documentation is available at [Commands reference](doc/cmds/README.md)

## Using zos for the first time
In the first time of using zos you will see a friendly message indicating what you should do

```bash
To create new machine in VirtualBox use
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]

To configure it to use a specific zosmachine
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--secret=<secret>]
```

## Preparing local Zero-OS machine
```bash
zos init --name=mymachine [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]
```

This will create a local virtual machine `mymachine` with ZOS installed and forwards the `localhost 4444` to zos redis port `6379`
- memorysize is defaulted to 4 GB
- disk size is defaulted to 20 GB disk

more on [init command](doc/cmds/init.md)

### Example
```bash
./zos init --name=firstmachine --disksize=1 --memory=2 --redisport=5555
** executing command vboxmanage modifyvm firstmachine   --memory=2048
** executing command vboxmanage modifyvm firstmachine   --ioapic on
** executing command vboxmanage modifyvm firstmachine   --boot1 dvd --boot2 disk
** executing command vboxmanage modifyvm firstmachine   --nic1 nat
** executing command vboxmanage modifyvm firstmachine   --vrde on 
** executing command vboxmanage modifyvm firstmachine   --natpf1 "redis,tcp,,5555,,6379" 
INFO created machine firstmachine
INFO preparing zos machine...
```
At this moment zos is preparing your machine on virtualbox and it may take sometime depending on your internet 
> There's a work on progress to make speed that up for the next init calls.

## Using an existing Zero-OS machine
Lots of time you will have a local development of zero-os using qemu, and to configure zos against that you can use `configure` subcommand to do so

```bash
./zos configure --name=local --address=192.168.122.147 --port=6379  
```
To configure an existing zos machine named `local` to use address `192.168.122.147` and port `6379`

more on [configure command](doc/cmds/configure.md)

## Zos configurations
- Configurations `zos.toml` is saved in your configurations directory (e.g `~/.config` in linux)


- You should you [`zos showconfig`](doc/cmds/showconfig.md) to see the current configurations 

```bash
[app]
debug=false
defaultzos=firstmachine
[local]
address=127.0.0.1
port=7777
[container-mycont]
sshenabled=false
[container-cont1]
sshenabled=true
ip=10.244.106.212
[firstmachine]
address=127.0.0.1
port=5555

```

- `defaultzos` means the active zos machine to be used in zos interactions and its connection information is in section `firstmachine`


## Interacting with ZOS

### Checking connectivity
ping command is a wrapper around `cmd "core.ping"` and can be used to check connectivity

```
./zos ping 
```
You should see response
```
"PONG Version: development @Revision: f61e80169fda9cf5246305feb3fde3cadd831f3c"
```

More info info at [ping cmd](/doc/cmds/ping.md)


### ZOS Builtin commands

Zero-OS supports [many commands](https://github.com/threefoldtech/0-core/blob/development/docs/interacting/commands/README.md) and you can use them using `zos cmd COMMAND_NAME [--jsonargs=]`

### Examples

- `ping`
```
./zos ping 
```
You should see response
```
"PONG Version: development @Revision: f61e80169fda9cf5246305feb3fde3cadd831f3c"
```

More info info at [doc/cmd](doc/cmds/ping.md)


### User defined commands

you can use [exec](doc/cmds/exec.md) subcommand to execute bash commands on the zos directly
```
~> ./zos exec "ls /var"
cache
empty
lib
lock
log
run


~> ./zos exec "ls /root -al"
total 0
drwxr-xr-x    3 root     root            60 Sep 17 13:09 .
drwxrwxrwt   14 root     root           340 Sep 17 16:28 ..
drwx------    2 root     root            60 Sep 17 13:09 .ssh


~> ./zos exec "cat /root/.ssh/authorized_keys"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCj0pqf2qalrmOTZma/Pl/U6rNZaP3373o/3w71xaG79ZtZZmeYspcUmMx9462AsbkA6T9RmxqrNBYnN9W+8XgTtRH9k/KQ83tui5eB3/zPtTi5ujX2geIn+h8PerG1Y96akj6vfFkR2jQld4WWHVzZAY9eEJ1IeMA30tz/LtAuyxxCLKsU/nZSsT2G0sHE0mKb9bnqy1FnmtG2oqZe5hZ5rEpePTKrh7y/Ev3zSQnnmQot6xErN51vOwdR22hJFlX75VoO+q6LJT2g82xezGsbLEv9QIRYcGby1RbjWsXjjfP6trD/+w8gYyVjjIqA6sexs7WXINeeZ4NLXIwPEVmt

.... output omitted

```


### Spawning container
Typically you want to spawn a container using flist and specifying hostname, name, and maybe extra configurations like portforwards, nics

```bash
./zos container new --name=reem2 --root="https://hub.grid.tf/tf-bootable/ubuntu:lts.flist"
```
Output (new container id)
```
2
```
For more info check [container new command page](doc/cmds/container_new.md)

### Container information

[container info](doc/cmds/container_info) subcommand is used to get information about single or all containers

```bash
./zos container 350 info
{
  "id": "350",
  "cpu": 0.0,
  "root": "https://hub.grid.tf/thabet/redis.flist",
  "hostname": "anderwxyz",
  "name": "",
  "storage": "",
  "pid": 12273,
  "ports": "90

```

using `./zos container list` or `./zos container info` will give us information about all the containers

```bash
 ./zos container list
[
  {
    "id": "1",
    "cpu": 0.02948726340828401,
    "root": "https://hub.grid.tf/tf-autobuilder/threefoldtech-0-robot-autostart-development.flist",
    "hostname": "",
    "name": "",
    "storage": "zdb://hub.grid.tf:9900",
    "pid": 523
  },
  {
    "id": "2",
    "cpu": 0.0,
    "root": "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist",
    "hostname": "reem2",
    "name": "reem2",
    "storage": "zdb://hub.grid.tf:9900",
    "pid": 5111
  }
]

```

### Inspect single container
using [`inspect` command](doc/cmds/container_inspect.md) will give us full information about the container
```bash
./zos container 1 inspect
{
  "cpu": 0.01674105440884163,
  "rss": 7946240,
  "vms": 398368768,
  "swap": 0,
  "container": {
    "arguments": {
      "root": "https://hub.grid.tf/tf-autobuilder/threefoldtech-0-robot-autostart-development.flist",
      "mount": {
        "/var/cache/zrobot/config": "/opt/code/local/stdorg/config",
        "/var/cache/zrobot/data": "/opt/var/data/zrobot/zrobot_data",
        "/var/cache/zrobot/jsconfig": "/root/jumpscale/cfg",
        "/var/cache/zrobot/ssh": "/root/.ssh",
        "/var/run/redis.sock": "/tmp/redis.sock"
      },
      "host_network": false,
      "identity": "",
      "nics": [
        {
          "type": "default",
          "id": "",
          "hwaddr": "",
          "config": {
            "dhcp": false,
            "cidr": "",
            "gateway": "",
            "dns": null
          },
          "monitor": false,
          "state": "configured"
        }
      ],
      "port": {
        "6600": 6600
      },
      "privileged": false,
      "hostname": "",
      "storage": "zdb://hub.grid.tf:9900",
      "name": "zrobot",
      "tags": [
        "zrobot"
      ],
      "env": {
        "HOME": "/root",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8"
      },
      "cgroups": [
        [
          "devices",
          "corex"
        ]
      ],
      "config": null
    },
    "root": "/mnt/containers/1",
    "pid": 446
  }
}

and calling the command without specific container will get us fully detailed information about all the containers

```
`./zos container inspect`
Shows a detailed information about the container


### Terminating a container
Using subcommand [`delete`](doc/cmds/container_delete.md)
```bash
./zos container 5 delete  
```


### Enabling SSH
Enabling ssh on the container is as easy as `./zos container 2 sshenable`

```bash
./zos container 2 sshenable                                                                          30.79  
ssh root@10.244.104.71

```

more info on [container sshenable](doc/cmds/container_sshenable)

> Can be called without argument and will enable ssh on the last container created.

### Access SSH
Executing `./zos container 3 shell` will connect through SSH 

> Calling `zos container 3 shell` will understand that you want to enablessh and will do it for you.

```bash

./zos container 2 shell
Welcome to Ubuntu 16.04 LTS (GNU/Linux 4.14.36-Zero-OS x86_64)

 * Documentation:  https://help.ubuntu.com/
Last login: Tue Oct 16 08:33:38 2018 from 10.244.131.242
root@reem2:~# 

```
more info on [container shell](doc/cmds/container_shell)

### Upload/Download files 
```bash
~> ./zos container exec 'ls /tmp' 

ztkey
~>  echo "MYUPLOADED FILE" > /tmp/myfile
~>  ./zos container upload /tmp/myfile /tmp 
scp  /tmp/myfile root@10.244.104.71:/tmp 
myfile                                                       100%   16    11.0KB/s   00:00    
~>  ./zos container exec 'ls /tmp'
myfile
ztkey
~>  ./zos container exec 'cat /tmp/myfile'
MYUPLOADED FILE
```

```
~> ./zos container download /tmp/myfile /tmp/downloadedmyfile
scp -r root@10.244.104.71:/tmp/myfile /tmp/downloadedmyfile
myfile                                                                                                                                 100%   16    10.4KB/s   00:00

~> cat /tmp/downloadedmyfile
MYUPLOADED FILE
```
