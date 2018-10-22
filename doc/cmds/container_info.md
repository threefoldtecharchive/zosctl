# info

gives you a small information about the container (i.e hostname, flist, storage..)


## info on all containers

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

## info on specific container 

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


