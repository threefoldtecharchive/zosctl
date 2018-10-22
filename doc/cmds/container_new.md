# creating new container

```bash
  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--sshkey=<sshkey>] [--privileged] [--ssh] 
```

- `--name` is the name of container (also the hostname if not specified)
- `--root` root flist
- `--hostname` hostname
- `--sshkey` sshkey to authenticate with (will use agent if not specified and fallback to default id_rsa if there weren't any keys in agent)
- `--ssh` directly enable ssh
- `--ports` list of portforwards hostport:containerport separated by comma (e.g `80:80,600:6000`)

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


