import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal

let firstTimeMessage* = """First time to run zos?
To create new machine in VirtualBox use
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>] [--reset]

To configure it to use a specific zosmachine 
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--secret=<secret>]
"""


let doc* = """
Usage:
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>] [--reset]
  zos configure --name=<zosmachine> [--address=<address>] [--port=<port>] [--setdefault]
  zos remove --name=<zosmachine>
  zos ping
  zos showconfig
  zos setdefault <zosmachine>
  zos cmd <zoscommand> [--jsonargs=<args>]
  zos exec <command>
  zos container new --name=<name> --root=<rootflist> [--hostname=<hostname>] [--ports=<ports>] [--env=<envvars>] [--sshkey=<sshkey>] [--privileged] [--ssh]
  zos container inspect
  zos container info [--json]
  zos container list [--json]
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
  zos container sshenable
  zos container sshinfo
  zos container shell
  zos container exec <command>
  zos container <id> upload <file> <dest>
  zos container <id> download <file> <dest>
  zos container upload <file> <dest>
  zos container download <file> <dest>
  zos help <cmdname>

  zos --version


Options:
  -h --help                       Show this screen.
  --version                       Show version.
  --disksize=<disksize>           disk size in GB [default: 20]
  --memory=<memorysize>           memory size in GB [default: 4]
  --address=<address>             zos ip [default: 127.0.0.1]
  --redisport=<redisport>         redis port [default: 4444]
  --port=<port>                   zero-os port [default: 6379]
  --sshkey=<sshkey>               sshkey name or full path [default: id_rsa]
  --setdefault                    sets the configured machine to be default one
  --privileged                    privileged container [default: false]
  --ssh                           enable ssh on container [default: false]
  --hostname=<hostname>           container hostname [default:]
  --ports=<ports>                 portforwards [default:]
  --jsonargs=<jsonargs>           json encoded arguments [default: "{}"]
  --reset                         resets the zos virtualbox machine  
  --json                          shows json output               
"""


proc getHelp*(cmdname:string) =
  if cmdname == "":
    echo doc 
  elif cmdname == "init":
    echo """
          zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>] [--reset]

          creates a new virtualbox machine named zosmachine with optional disksize 20 GB and memory 4GB  
            --disksize=<disksize>           disk size in GB [default: 20]
            --memory=<memorysize>           memory size in GB [default: 4]
            --port=<port>                   redis port [default:4444]
            --reset                         resets the zos virtualbox machine                 

    """
  elif cmdname == "ping":
    echo """
    zos ping
      checks connection to active zos machine.

    """
  elif cmdname == "configure":
    echo """
          zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--setdefault]
            configures instance with name zosmachine on address <address>
            --port=<port>                   zero-os port [default: 6379]
            --setdefault                    sets the configured machine to be default one
            
            """
  elif cmdname == "remove":
    echo """
           zos remove --name=<zosmachine>
            removes zero-os virtualbox machine 

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
        zos cmd <zoscommand> [--jsonargs='{}']
          executes zero-os command e.g "core.ping" (can be very dangerous)
        
        example:
          zos cmd "filesystem.open" --jsonargs='{"file":"/root/.ssh/authorized_keys", "mode":"r"}'
          "0ed49546-1ead-49da-a852-345a2e298891"

    """
  elif cmdname == "exec":
    echo """
        zos exec <command> 
          execute shell command on zero-os host e.g "ls /root -al" (can be very dangerous)
    """
  elif cmdname == "container":
    echo """

  zos container new --name=<name> --root=<rootflist> [--hostname=<hostname>] [--ports=<ports>] [--env=<envvars>] [--sshkey=<sshkey>] [--privileged] [--ssh]
    creates a new container 

  zos container inspect
    inspect the current running container (showing full info)

  zos container info [--json]
    shows summarized info on running containers
  zos container list [--json]
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

  zos container <id> upload <file> <dest>
    upload <file> to <dest> on container <id>

  zos container <id> download <file> <dest>
    download <file> to <dest> from container <id>

  zos container upload <file> <dest>
    uploads the <file> to <dest> on the last created container by zos

  zos container download <file> <dest>
    downloads <file> to <dest> from the last created container by zos    

    """

  else:
    echo firstTimeMessage
    echo doc

