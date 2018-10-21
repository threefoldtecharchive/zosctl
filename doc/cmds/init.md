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

INFO created machine kds
INFO preparing zos machine...
PONG
INFO preparing machine..
INFO created zos machine and we are ready.

```


### reset
```bash
~>  ./zos init --name=local3 --disksize=1 --memory=1                                  
WARN local3 is already configured against 1234 and you want it to use 4444
continue? [Y/n]: 
n

~> ./zos init --name=local2 --redisport=1234                                                             ✔  ahmed@ahmedheaven  3.22  
WARN local2 is already configured against 2345 and you want it to use 1234
continue? [Y/n]: 
n
```

- init machine with the existing name using the old port will start it again
- init machine with the existing name and different port will show confirmation message and will remove the old one if you press `y`
- init machine and passing `--reset` to it will remove the machine and start over


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

