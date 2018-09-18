
## config management

the configuration is kept in

 ~/.config/zos.toml
 
 zos remembers connections to different ZOSes
 
 each of them is dict inside the zos.toml
 
 arguments per instance
 
 - name
 - ipaddress
 - port
 - secret (or empty)
 - sshkey name (if only 1 loaded, will use that one


## init local virtualbox environment

### requirements

- have virtualbox installed on local machine

### default usage

```bash
zos init
```

will create a local virtualbox zero-os
name of ZOS = 'local'

specs
- 2 GB memory
- 10 GB local virtual disk
- 2 cpu cores (if host machine has 4, otherwise 1)

### arguments

...

## configure remote ZOS environment

### requirements

- Zero-OS nodes where redis connection can be created to

### default usage

```bash
zos configure -n myname -p 4444 -s secret1
```

arguments
```
-n or --name=
-a or --address= ip addr
-p or --port=
-s or --secret= . is optional secret to connect to the redis
```

when connecting to redis will check if SSL can be used, if yes will use it and remember in configuration

## use ZOS for containers

```
zos container new -o $optional_zosname -n aname -...
zos container delete -n aname
zos container list
zos container duplication -n aname -d newname ... can overrule mem & maybe some other params
zos container exec -n name 
zos container ssh -n name .  #enable ssh and open ssh session to it, print the port used for ssh
zos container sshenable -n name #enables ssh but does not go to it, print the port used for ssh
```

-o means on a specified ZOS VM, if not specified then its 'local'

## use ZOS for containers advanced (phase 2)

```
zos container export #export to S3 destination or SSH destination using restic
zos container import #flist is the result of the impoirt
zos container flistcreate -n aname -p /sourcepathtostartfrom ...
```

## commands

```
zos container cmd ...
```

## zdb

```
zos zdb new ...
zos zdb delete
zos zdb list
```

## 3bot

```
zos 3bot init            #starts 3bot in development mode (jumpscale, ssh, ...)
zos builder connect -d /mnt/mypath .  #connects over ssh my local path to the builder 3bot
```
 ## builder
 
 ```
zos builder new -n name     #starts ubuntu 18.04 in build config
zos builder prefab -n name -c ... #execute a prefab command onto the container using prefab on 3bot
```

example prefab command:
```
p.runtimes.python.build()
```
p is the prefab obj


