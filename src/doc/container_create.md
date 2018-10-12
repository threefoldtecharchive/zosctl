# how to create a container and run it in ZOS


```bash
#To create new machine in VirtualBox use


#e.g. ubuntu 16.04
./zos container new --name=mycont --root="https://hub.grid.tf/tf-bootable/ubuntu:lts.flist"
./zos container new --name=ub18 --root="https://hub.grid.tf/tf-bootable/ubuntu:18.04.flist"

#e.g. ubuntu 18.04
#BUT with a predefined ssh login/passwd root/rooter
./zos container new --name=mycont --root="https://hub.grid.tf/tf-official-apps/ubuntu-bionic-build.flist"

```

to check if its there

```bash
bash-3.2$ zos container list
[
  {
    "id": "1",
    "cpu": 0.007175177296659887,
    "root": "https://hub.grid.tf/tf-autobuilder/threefoldtech-0-robot-autostart-development.flist",
    "hostname": "",
    "pid": 506
  },
  {
    "id": "2",
    "cpu": 0.0,
    "root": "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist",
    "hostname": "mycont",
    "pid": 1785
  }
]
```

## to enable ssh

```bash
zos container 5 sshenable
```