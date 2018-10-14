import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal

let firstTimeMessage* = """First time to run zos?
To create new machine in VirtualBox use
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]

To configure it to use a specific zosmachine 
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--secret=<secret>]
"""


let doc* = """
Usage:
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]
  zos configure --name=<zosmachine> [--address=<address>] [--port=<port>] [--sshkey=<sshkeyname>] [--setdefault]
  zos showconfig
  zos setdefault <zosmachine>
  zos cmd <zoscommand> [--jsonargs=<args>]
  zos exec <command>
  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--privileged] [--ssh] [--on=<zosmachine>]
  zos container inspect
  zos container info
  zos container list
  zos container <id> inspect
  zos container <id> info
  zos container <id> delete
  zos container <id> zerotierinfo
  zos container <id> zerotierlist
  zos container <id> zosexec <command>
  zos container <id> sshenable
  zos container <id> sshinfo
  zos container <id> shell
  zos container <id> exec <command>
  zos container shell
  zos container exec <command>
  zos help <cmdname>

  zos --version


Options:
  -h --help                       Show this screen.
  --version                       Show version.
  --on=<zosmachine>               Zero-OS machine instance name.
  --disksize=<disksize>           disk size in GB [default: 20]
  --memory=<memorysize>           memory size in GB [default: 4]
  --address=<address>             zos ip [default: 127.0.0.1]
  --redisport=<redisport>         redis port [default: 4444]
  --port=<port>                   zero-os port [default: 6379]
  --sshkey=<sshkeyname>           sshkey name [default: id_rsa]
  --setdefault                    sets the configured machine to be default one
  --privileged                    privileged container [default: false]
  --ssh                           enable ssh on container [default: false]
  --hostname=<hostname>           container hostname [default:]
  --jsonargs=<jsonargs>           json encoded arguments [default: "{}"]
"""


proc getHelp*(cmdname:string) =
  if cmdname == "":
    echo doc 
  elif cmdname == "init":
    echo """
          zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]

          creates a new virtualbox machine named zosmachine with optional disksize 1GB and memory 2GB  
            --disksize=<disksize>           disk size [default: 1000]
            --memory=<memorysize>           memory size [default: 2048]
            --port=<port>  

    """
  elif cmdname == "configure":
    echo """
          zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--setdefault]
            configures instance with name zosmachine on address <address>
            --port=<port>                   zero-os port [default: 6379]
            --sshkey=<sshkeyname>           sshkey name [default: id_rsa]
            --setdefault                    sets the configured machine to be default one
            
            """
  elif cmdname == "showconfig":
    echo """
        zos showconfig
            Shows application config
        """
  elif cmdname == "setdefault":
    echo """
        zos setdefault <zosmachine>
          Sets the default instance to work with
    """
  elif cmdname == "cmd":
    echo """
        zos cmd <zoscommand>
          executes zero-os command e.g "core.ping" (can be very dangerous)
    """
  elif cmdname == "exec":
    echo """
        zos exec <command> 
          execute shell command on zero-os host e.g "ls /root -al" (can be very dangerous)
    """
  elif cmdname == "container":
    echo """

  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--privileged] [--on=<zosmachine>] [--ssh]
    creates a new container 

  zos container inspect
    inspect the current running container (showing full info)

  zos container info
    shows summarized info on running containers
  zos container list
    alias to `zos container info`

  zos container <id> inspect
    shows detailed information on container 

  zos container <id> info
    show summarized container info

  zos container <id> delete
    deletes containers

  zos container <id> zerotierinfo
    shows zerotier info of a container

  zos container <id> zerotierlist
    shows zerotier networks info

  zos container <id> exec <command>
    executes a command on a specific container

  zos container <id> sshenable
    enables ssh on a container

  zos container <id> sshinfo
    shows sshinfo to access container

  zos container <id> shell
    ssh into a container
    """

  else:
    echo firstTimeMessage
    echo doc

