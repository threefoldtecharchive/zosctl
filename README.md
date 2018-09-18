# container_cmd
zos-container manager can be used on local or remote zos machine

## Building
- nimble build -d:ssl

## Preparing local zos machine
```bash
./container_cmd newZos -v zmachine3 --redisPort 4444
```
This will create a local virtual machine `zmachine3` with ZOS installed and forwards the localhost 4444 to zos redis port 6379


## Interacting with ZOS

### ZOS Builtin commands

### Examples

- `ping`
```
./container_cmd zosCore --command="core.ping" --host 127.0.0.1 --port 4444
```
You should see response
```
"PONG Version: development @Revision: f61e80169fda9cf5246305feb3fde3cadd831f3c"
```


- `disk.list`
```
~> ./container_cmd zosCore --command="disk.list" --host 127.0.0.1 --port 4444
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
- info.dmi
This commands requires extra arguments to be passed like specifying types this can be achieved by sending the payload of the command in `--arguments` switch as encoded json string. (you need to consult the zero-os documentation about various commands and their parameters)
```./container_cmd zosCore --command="info.dmi" --host 127.0.0.1 --port 4444 --arguments='{"types":["bios"]}'```

Output

```
{
  "BIOS Information": {
    "handleline": "Handle 0x0000, DMI type 0, 20 bytes",
    "title": "BIOS Information",
    "typestr": "BIOS",
    "typenum": 0,
    "properties": {
      "Address": {
        "value": "0xE0000"
      },
      "Characteristics": {
        "value": "",
        "items": [
          "ISA is supported",
          "PCI is supported",
          "Boot from CD is supported",
          "Selectable boot is supported",
          "8042 keyboard services are supported (int 9h)",
          "CGA/mono video services are supported (int 10h)",
          "ACPI is supported"
        ]
      },
      "ROM Size": {
        "value": "128 kB"
      },
      "Release Date": {
        "value": "12/01/2006"
      },
      "Runtime Size": {
        "value": "128 kB"
      },
      "Vendor": {
        "value": "innotek GmbH"
      },
      "Version": {
        "value": "VirtualBox"
      }
    }
  }
}
```
### User defined commands

you can use zosBash subcommand to execute bash commands on the zos directly
```
~> ./container_cmd zosBash --command="ls /var" --host127.0.0.1 --port 4444
cache
empty
lib
lock
log
run


~> ./container_cmd zosBash --command="ls /root -al" --host 127.0.0.1 --port 4444
total 0
drwxr-xr-x    3 root     root            60 Sep 17 13:09 .
drwxrwxrwt   14 root     root           340 Sep 17 16:28 ..
drwx------    2 root     root            60 Sep 17 13:09 .ssh


~> ./container_cmd zosBash --command="cat /root/.ssh/authorized_keys" --host 127.0.0.1 --port 4444
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCj0pqf2qalrmOTZma/Pl/U6rNZaP3373o/3w71xaG79ZtZZmeYspcUmMx9462AsbkA6T9RmxqrNBYnN9W+8XgTtRH9k/KQ83tui5eB3/zPtTi5ujX2geIn+h8PerG1Y96akj6vfFkR2jQld4WWHVzZAY9eEJ1IeMA30tz/LtAuyxxCLKsU/nZSsT2G0sHE0mKb9bnqy1FnmtG2oqZe5hZ5rEpePTKrh7y/Ev3zSQnnmQot6xErN51vOwdR22hJFlX75VoO+q6LJT2g82xezGsbLEv9QIRYcGby1RbjWsXjjfP6trD/+w8gYyVjjIqA6sexs7WXINeeZ4NLXIwPEVmt

.... output omitted

```


### Spawning container
Typically you want to spawn a container using flist and specifying hostname, name, and maybe extra configurations like portforwards, nics, mounts..

```
./container_cmd startContainer --name=rediscont3 --hostname aredishost --root="https://hub.grid.tf/thabet/redis.flist" --
extraconfig='{"port":{"3000":3500}, "nics":[{"type":"default"}]}' --port=4444
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


### Listing running containers
 ```./container_cmd listContainers --port=4444``

```
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

```
./container_cmd stopContainer --id=3 --port 4444
./container_cmd stopContainer --id=11 --port 4444
```

```
FAILED TO EXECUTE with error {"id":"8a6a61e0-dca4-43c6-b9e8-b8c78822eb2c","command":"corex.terminate","data":"\"no container with id '11'\"","streams":["",""],"level":20,"state":"ERROR","code":500,"starttime":1537258389944,"time":0,"tags":null,"container":0}
{
  "id": "8a6a61e0-dca4-43c6-b9e8-b8c78822eb2c",
  "command": "corex.terminate",
  "data": "\"no container with id '11'\"",
  "streams": [
    "",
    ""
  ],
  "level": 20,
  "state": "ERROR",
  "code": 500,
  "starttime": 1537258389944,
  "time": 0,
  "tags": null,
  "container": 0
}
```

