# zos init

Goal is to configure a virtualbox hypervisor and start it with a zero-os OS.

## what will it do

- will look for ~/.ssh/id_rsa 
- will download a zero-os to boot from
- will start a VM with the name as specified

## result should be a 

- VM with the name as specified, you can use your virtualbox ui tool to see that the zero-os is booted

## what if it goes wrong

- VM should be in '~/VirtualBox VMs/$MYCHOSEN_NAME'
- you can redo the init, but then make sure you remove this directory


## example

```bash
zos init --name=kds --disksize=20000 --memory=6000
** executing command vboxmanage modifyvm kds   --memory=6000
** executing command vboxmanage modifyvm kds   --ioapic on
** executing command vboxmanage modifyvm kds   --boot1 dvd --boot2 disk
** executing command vboxmanage modifyvm kds   --nic1 nat
** executing command vboxmanage modifyvm kds   --vrde on
** executing command vboxmanage modifyvm kds   --natpf1 "redis,tcp,,4444,,6379"
Created machine kds
```

![](images/zos_vb.png)

## to test

```bash
bash-3.2$ ./zos container list
[
  {
    "id": "1",
    "cpu": 0.01239797792233564,
    "root": "https://hub.grid.tf/tf-autobuilder/threefoldtech-0-robot-autostart-development.flist",
    "hostname": "",
    "pid": 506
  }
]
```


