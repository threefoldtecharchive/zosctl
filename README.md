# zos
zos-container manager can be used on local or remote zos machine

## Building
Project is built using `nimble zos` or `nimble build -d:ssl`

### examples on OSX

```bash
#example script to install
brew install nim 
mkdir -p  ~/code/github;cd ~/code/github
git clone https://github.com/threefoldtech/zos 
cd zos
nimble build -d:ssl
```

## Using zos for the first time
In the first time of using zos you will see a friendly message indicating what you should do

```bash
To create new machine in VirtualBox use
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]

To configure it to use a specific zosmachine
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--secret=<secret>]
```

## Preparing local zos machine
```bash
zos init --name=mymachine [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]
```
This will create a local virtual machine `mymachine` with ZOS installed and forwards the `localhost 4444` to zos redis port `6379`
- memorysize is defaulted to 2 GB
- disk size is defaulted to 1 GB disk


## Using an existing Zos machine
Lots of time you will have a local development of zero-os using qemu, and to configure zos against that you can use `configure` subcommand to do so

```bash
./zos configure --name local --address 192.168.122.147 --port 6379  
```
To configure an existing zos machine named `local` to use address `192.168.122.147` and port `6379`

## Interacting with ZOS


### ZOS Builtin commands

### Examples

- `ping`
```
./zos cmd "core.ping" 
```
You should see response
```
"PONG Version: development @Revision: f61e80169fda9cf5246305feb3fde3cadd831f3c"
```


- `disk.list`
```
~> ./zos cmd "disk.list" 
```
Output:
```
[
  {
    "name": "sda",
    "kname": "sda",
    "maj:min": "8:0",
    "fstype": null,
    "mountpoint": null,
    "label": null,
    "uuid": null,
    "parttype": null,
    "partlabel": null,
    "partuuid": null,
    "partflags": null,
    "ra": "128",
    "ro": "0",
    "rm": "0",
    "hotplug": "0",
    "model": "VBOX HARDDISK   ",
    "serial": "VBf3f81d08-69a57200",
    "state": "running",
    "owner": "root",
    "group": "disk",
    "mode": "brw-rw----",
    "alignment": "0",
    "min-io": "512",
    "opt-io": "0",
    "phy-sec": "512",
    "log-sec": "512",
    "rota": "1",
    "sched": "cfq",
    "rq-size": "128",
    "type": "disk",
    "disc-aln": "0",
    "disc-gran": "0",
    "disc-max": "0",
    "disc-zero": "0",
    "wsame": "0",
    "wwn": null,
    "rand": "1",
    "pkname": null,
    "hctl": "2:0:0:0",
    "tran": "sata",
    "subsystems": "block:scsi:pci",
    "rev": "1.0 ",
    "vendor": "ATA     ",
    "children": [
      {
        "name": "sda1",
        "kname": "sda1",
        "maj:min": "8:1",
        "fstype": "btrfs",
        "mountpoint": "/mnt/storagepools/sp_zos-cache",
        "label": "sp_zos-cache",
        "uuid": "884020ea-54dc-4e63-9d27-d37f28fe1b0f",
        "parttype": "0fc63daf-8483-4772-8e79-3d69d8477de4",
        "partlabel": "primary",
        "partuuid": "79b8def9-aec2-4f86-bece-afba45c482a5",
        "partflags": null,
        "ra": "128",
        "ro": "0",
        "rm": "0",
        "hotplug": "0",
        "model": "",
        "serial": "",
        "size": "1046478848",
        "state": null,
        "owner": "root",
        "group": "disk",
        "mode": "brw-rw----",
        "alignment": "0",
        "min-io": "512",
        "opt-io": "0",
        "phy-sec": "512",
        "log-sec": "512",
        "rota": "1",
        "sched": "cfq",
        "rq-size": "128",
        "type": "part",
        "disc-aln": "0",
        "disc-gran": "0",
        "disc-max": "0",
        "disc-zero": "0",
        "wsame": "0",
        "wwn": null,
        "rand": "1",
        "pkname": "sda",
        "hctl": null,
        "tran": "",
        "subsystems": "block:scsi:pci",
        "rev": null,
        "vendor": null
      }
    ],
    "start": 0,
    "end": 1048575999,
    "size": 1048576000,
    "blocksize": 512,
    "table": "gpt",
    "free": [
      {
        "start": 17408,
        "end": 1048575,
        "size": 1031168
      },
      {
        "start": 1047527424,
        "end": 1048559103,
        "size": 1031680
      }
    ]
  },
  {
    "name": "sr0",
    "kname": "sr0",
    "maj:min": "11:0",
    "fstype": "iso9660",
    "mountpoint": null,
    "label": "iPXE",
    "uuid": "2018-09-11-11-46-27-00",
    "parttype": null,
    "partlabel": null,
    "partuuid": null,
    "partflags": null,
    "ra": "128",
    "ro": "0",
    "rm": "1",
    "hotplug": "1",
    "model": "CD-ROM          ",
    "serial": "VB0-01f003f6",
    "state": "running",
    "owner": "root",
    "group": "cdrom",
    "mode": "brw-rw----",
    "alignment": "0",
    "min-io": "2048",
    "opt-io": "0",
    "phy-sec": "2048",
    "log-sec": "2048",
    "rota": "1",
    "sched": "cfq",
    "rq-size": "128",
    "type": "rom",
    "disc-aln": "0",
    "disc-gran": "0",
    "disc-max": "0",
    "disc-zero": "0",
    "wsame": "0",
    "wwn": null,
    "rand": "1",
    "pkname": null,
    "hctl": "0:0:0:0",
    "tran": "ata",
    "subsystems": "block:scsi:pci",
    "rev": "1.0 ",
    "vendor": "VBOX    ",
    "start": 0,
    "end": 0,
    "size": 0,
    "blocksize": 2048,
    "table": "",
    "free": null
  }
]
```

### User defined commands

you can use zosBash subcommand to execute bash commands on the zos directly
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
Typically you want to spawn a container using flist and specifying hostname, name, and maybe extra configurations like portforwards, nics, mounts..

```
 ./zos container new --name=mycont --root="https://hub.grid.tf/tf-bootable/ubuntu:lts.flist" --privileged  --extraconfig='{"config":{}}'
```
Output (new container id)
```
2
```

#### extraconfig
Please consult the documentation for more updated info on the allowed configurations
```
    extraconfig is json encoded string contains
      mount: a dict with {host_source: container_target} mount points.
                    where host_source directory must exists.
                    host_source can be a url to a flist to mount.
      host_network: Specify if the container should share the same network stack as the host.
                          if True, container creation ignores both zerotier, bridge and ports arguments below. Not
                          giving errors if provided.
      nics: Configure the attached nics to the container
                  each nic object is a dict of the format
                  {
                      'type': nic_type # one of default, bridge, zerotier, macvlan, passthrough, vlan, or vxlan (note, vlan and vxlan only supported by ovs)
                      'id': id # depends on the type
                          bridge: bridge name,
                          zerotier: network id,
                          macvlan: the parent link name,
                          passthrough: the link name,
                          vlan: the vlan tag,
                          vxlan: the vxlan id
                      'name': name of the nic inside the container (ignored in zerotier type)
                      'hwaddr': Mac address of nic.
                      'config': { # config is only honored for bridge, vlan, and vxlan types
                          'dhcp': bool,
                          'cidr': static_ip # ip/mask
                          'gateway': gateway
                          'dns': [dns]
                      }
                  }
      port: A dict of host_port: container_port pairs (only if default networking is enabled)
                    Example:
                      `port={8080: 80, 7000:7000}`
                    Source Format: NUMBER, IP:NUMBER, IP/MAST:NUMBER, or DEV:NUMBER
      storage: A Url to the ardb storage to use to mount the root flist (or any other mount that requires g8fs)
                      if not provided, the default one from core0 configuration will be used.
      identity: Container Zerotier identity, Only used if at least one of the nics is of type zerotier
      env: a dict with the environment variables needed to be set for the container
      cgroups: custom list of cgroups to apply to this container on creation. formated as [(subsystem, name), ...]
                      please refer to the cgroup api for more detailes.
      config: a map with the config file path as a key and content as a value. This only works when creating a VM from an flist. The
              config files are written to the machine before booting.
              Example:
              config = {'/root/.ssh/authorized_keys': '<PUBLIC KEYS>'}
```

### Container information

```bash
./zos container 5 info                                                       
{
  "id": "5",
  "cpu": 0.0,
  "root": "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist",
  "hostname": "dmdm",
  "pid": 29671
```

### Containers information
using `./zos container list` or `./zos container info`

```bash
[
  {
    "id": "1",
    "cpu": 0.03423186237547345,
    "root": "https://hub.grid.tf/tf-autobuilder/threefoldtech-0-robot-autostart-development.flist",
    "hostname": "",
    "pid": 446
  },
  {
    "id": "2",
    "cpu": 0.01141061719069141,
    "root": "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist",
    "hostname": "\"\"",
    "pid": 2207
  },
  {
    "id": "3",
    "cpu": 0.0,
    "root": "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist",
    "hostname": "nil",
    "pid": 27567
  },
  {
    "id": "4",
    "cpu": 0.0,
    "root": "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist",
    "hostname": "nil",
    "pid": 28848
  },
  {
    "id": "5",
    "cpu": 0.0,
    "root": "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist",
    "hostname": "dmdm",
    "pid": 29671
  }
]
```

### Inspect single container
using `inspect` command
```bash
./zos container 1 inspect                                                     ✔  ahmed@ahmedheaven
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
```
### Inspect all containers
`./zos container inspect`
Shows a detailed information about the container

### Listing running containers

```bash
./zos container list
{  "1": {
    "cpu": 0.0216872378245448,
    "rss": 7151616,
    "vms": 271065088,
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
        ]
      },
      "root": "/mnt/containers/1",
      "pid": 493
    }
  },
  "2": {
    "cpu": 0,
    "rss": 5808128,
    "vms": 269983744,
    "swap": 0,
    "container": {
      "arguments": {
        "root": "https://hub.grid.tf/thabet/redis.flist",
        "mount": null,
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
          "3000": 3500
        },
        "privileged": false,
        "hostname": "aredishost",
        "storage": "zdb://hub.grid.tf:9900",
        "name": "rediscont3",
        "tags": null,
        "env": null,
        "cgroups": [
          [
            "devices",
            "corex"
          ]
        ]
      },
      "root": "/mnt/containers/2",
      "pid": 11243
    }
  }
}
```


### Terminating a container
using subcommand `delete`
```bash
./zos container 5 delete  
```


### Enabling SSH
enabling ssh on the container is as easy as `./zos container 3 sshenable`


### Access SSH
executing `./zos container 3 shell` will connect through ssh

