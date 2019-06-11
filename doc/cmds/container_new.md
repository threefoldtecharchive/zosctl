# creating new container

`container new` command helps with creating new containers 

```bash
  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--sshkey=<sshkey>] [--privileged] [--ssh] 
```
And it accepts arguments:
- `--name` is the name of container (also the hostname if not specified)
- `--root` root flist
- `--hostname` hostname
- `--sshkey` sshkey to authenticate with (will use ssh-agent if not specified and fallback to default id_rsa if there weren't any keys in agent)
- `--ssh` directly enable ssh
- `--ports` list of portforwards hostport:containerport separated by comma (e.g `80:80,600:6000`)
- `--env` list of environment variables separated by comma (e.g `HOME:/root,TOKEN:aaaaa` )
- `--zerotier` zerotier network id

```bash
./zos container new --name=reem2 --root="https://hub.grid.tf/tf-bootable/ubuntu:lts.flist" 
```
```bash
./zos container new --name=anderwxyz --root="https://hub.grid.tf/thabet/redis.flist" --ports="9001:11000"
INFO dispatch creating anderwxyz on machine https://hub.grid.tf/thabet/redis.flist false
INFO new container: corex.create {"name":"anderwxyz","hostname":"anderwxyz","root":"https://hub.grid.tf/thabet/redis.flist","privileged":false,"port":{"9001":11000},"nics":[{"type":"default"},{"type":"zerotier","id":"9bee8941b5717835"}],"config":{"/root/.ssh/authorized_keys":"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCeq1MFCQOv3OCLO1HxdQl8V0CxAwt5AzdsNOL91wmHiG9ocgnq2yipv7qz+uCS0AdyOSzB9umyLcOZl2apnuyzSOd+2k6Cj9ipkgVx4nx4q5W1xt4MWIwKPfbfBA9gDMVpaGYpT6ZEv2ykFPnjG0obXzIjAaOsRthawuEF8bPZku1yi83SDtpU7I0pLOl3oifuwPpXTAVkK6GabSfbCJQWBDSYXXM20eRcAhIMmt79zo78FNItHmWpfPxPTWlYW02f7vVxTN/LUeRFoaNXXY+cuPxmcmXp912kW0vhK9IvWXqGAEuSycUOwync/yj+8f7dRU7upFGqd6bXUh67iMl7 ahmed@ahmedheaven\n"}}
350
INFO still trying to get ip..
10.244.13.130


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


## zerotier examples

```bash

➜  zos git:(development) ✗ ./zos container new --name=zero11 --root=https://hub.grid.tf/tf-official-apps/threefoldtech-0-db-release-1.0.0.flist --hostname=zero11
INFO preparing container
INFO sending instructions to host
INFO container 7 is created.
INFO creating portforward from 1029 to 22
INFO waiting for private network connectivity
container private address: 192.168.56.101
➜  zos git:(development) ✗ ./zos container zerotierlist
[
  {
    "allowDefault": false,
    "allowGlobal": false,
    "allowManaged": true,
    "assignedAddresses": [],
    "bridge": false,
    "broadcastEnabled": false,
    "dhcp": false,
    "id": "9bee8941b5717835",
    "mac": "36:e3:ce:4a:bb:c4",
    "mtu": 2800,
    "name": "",
    "netconfRevision": 0,
    "nwid": "9bee8941b5717835",
    "portDeviceName": "zt3jn7qoma",
    "portError": 0,
    "routes": [],
    "status": "REQUESTING_CONFIGURATION",
    "type": "PRIVATE"
  }
]
➜  zos git:(development) ✗ 
➜  zos git:(development) ✗                             
➜  zos git:(development) ✗ ./zos container new --name=zero12 --root=https://hub.grid.tf/tf-official-apps/threefoldtech-0-db-release-1.0.0.flist --hostname=zero12 --zerotier=9bee8941b55787f3
INFO preparing container
INFO sending instructions to host
INFO container 8 is created.
INFO creating portforward from 1030 to 22
INFO waiting for private network connectivity
container private address: 192.168.56.101
➜  zos git:(development) ✗ ./zos container zerotierlist
[
  {
    "allowDefault": false,
    "allowGlobal": false,
    "allowManaged": true,
    "assignedAddresses": [],
    "bridge": false,
    "broadcastEnabled": false,
    "dhcp": false,
    "id": "9bee8941b55787f3",
    "mac": "f2:e1:0f:0e:99:d7",
    "mtu": 2800,
    "name": "",
    "netconfRevision": 0,
    "nwid": "9bee8941b55787f3",
    "portDeviceName": "zt3jn55rsg",
    "portError": 0,
    "routes": [],
    "status": "REQUESTING_CONFIGURATION",
    "type": "PRIVATE"
  }
]
➜  zos git:(development) ✗ 
```