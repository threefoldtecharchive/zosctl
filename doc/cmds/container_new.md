# creating new container

```bash
  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--sshkey=<sshkey>] [--privileged] [--ssh] 
```

- `--name` is the name of container (also the hostname if not specified)
- `--root` root flist
- `--hostname` hostname
- `--sshkey` sshkey to authenticate with (will use agent if not specified and fallback to default id_rsa if there weren't any keys in agent)
- `--ssh` directly enable ssh


```bash
./zos container new --name=reem2 --root="https://hub.grid.tf/tf-bootable/ubuntu:lts.flist" 
```