# how to create a container and run it in ZOS


```bash
#e.g. ubuntu 18.04, will be empty 18.04 is the default
./zos container new --name=mycont 

```

to check if its there

```bash
bash-3.2$ zos container list
---------------------------------------------------------------------------------------------------------------
| ID  | Name      | Ports        | Root
---------------------------------------------------------------------------------------------------------------
|1    |zrobot     |6600:6600     |tf-autobuilder/threefoldtech-0-robot-autostart-development.flist             |
---------------------------------------------------------------------------------------------------------------
|2    |zrobot2    |              |tf-autobuilder/threefoldtech-digital_me-autostart-development_simple.flist   |
---------------------------------------------------------------------------------------------------------------
|3    |me         |              |tf-autobuilder/threefoldtech-digital_me-autostart-development_simple.flist   |
---------------------------------------------------------------------------------------------------------------
|4    |me         |              |tf-bootable/ubuntu:18.04.flist                                               |
---------------------------------------------------------------------------------------------------------------
```

## to enable ssh

```bash
zos container 5 sshenable
```