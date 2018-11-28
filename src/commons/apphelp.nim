import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal, net, logging
import docopt 
import ./logger
import ./errorcodes

let firstTimeMessage* = """First time to run zos?
To create new machine in VirtualBox use
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>] [--reset]

To configure it to use a specific zosmachine 
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--secret=<secret>]
"""


let doc* = """
Usage:
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>] [--reset]
  zos configure --name=<zosmachine> [--address=<address>] [--port=<port>] [--setdefault] [--vbox]
  zos remove --name=<zosmachine>
  zos forgetvm --name=<zosmachine>
  zos ping
  zos showconfig
  zos setdefault <zosmachine>
  zos showactiveconfig
  zos showactive
  zos cmd <zoscommand> [--jsonargs=<args>]
  zos exec <command>
  zos container new [--name=<name>] [--root=<rootflist>] [--hostname=<hostname>] [--ports=<ports>] [--env=<envvars>] [--sshkey=<sshkey>] [--privileged] [--ssh]
  zos container inspect
  zos container info [--json]
  zos container list [--json]
  zos container <id> inspect
  zos container <id> info
  zos container <id> delete
  zos container <id> zerotierinfo
  zos container <id> zerotierlist
  zos container zerotierinfo
  zos container zerotierlist
  zos container <id> zosexec <command>
  zos container zosexec <command>
  zos container <id> sshenable
  zos container <id> sshinfo
  zos container <id> shell
  zos container <id> exec <command>
  zos container <id> js9 <command>
  zos container js9 <command>
  zos container <id> mount <src> <dest>
  zos container mount <src> <dest>
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
  --name=<name>                   container name [default:]
  --root=<rootflist>              root flist [default: https://hub.grid.tf/tf-bootable/ubuntu:18.04.flist]
  --disksize=<disksize>           disk size in GB [default: 20]
  --memory=<memorysize>           memory size in GB [default: 4]
  --address=<address>             zos ip [default: 127.0.0.1]
  --redisport=<redisport>         redis port [default: 4444]
  --port=<port>                   zero-os port [default: 6379]
  --sshkey=<sshkey>               sshkey name or full path [default:]
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
  ## Shows help for certain command or all if `cmdname` is empty.
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
            removes zero-os virtualbox machine and its configuration. 

    """
  elif cmdname == "forgetvm":
    echo """
           zos forgetvm --name=<zosmachine>
            removes machine configurations. 

    """

  elif cmdname == "showconfig":
    echo """
        zos showconfig
            shows application config
        """
  elif cmdname == "setdefault":
    echo """
        zos setdefault <zosmachine>
          sets the default instance to work with.
    """
  elif cmdname == "showdefault":
    echo """
        zos showdefault
          shows default configured instance.

    """
  elif cmdname == "showactive":
    echo """
        zos showactive
          shows active machine zos configured against.
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

  zos container new [--name=<name>] [--root=<rootflist>] [--hostname=<hostname>] [--ports=<ports>] [--env=<envvars>] [--sshkey=<sshkey>] [--privileged] [--ssh]
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

  zos container <id> mount <src> <dest>
    mount src on specific container to dest using sshfs 
    
  zos container mount <src> <dest>
    mount src on the last zos created container to dest using sshfs 
 
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

proc checkArgs*(args: Table[string, Value]) =
  ## Entry point for checking arguments passed to zos if they're valid
  ## `args` are coming from docopt parsing
  if args["--name"]:
    if $args["--name"] == "app":
      error("invalid name app")
      quit malformedArgs
  if args["--disksize"]:
    let disksize = $args["--disksize"]
    try:
      discard parseInt($args["--disksize"])
    except:
      error("invalid --disksize {disksize}")
      quit malformedArgs
  if args["--memory"]:
    let memory = $args["--memory"]
    try:
      discard parseInt($args["--memory"])
    except:
      error("invalid --memory {memory}")
      quit malformedArgs
  if args["--address"]:
    let address = $args["--address"]
    try:
      discard $parseIpAddress(address) 
    except:
      error(fmt"invalid --address {address}")
      quit malformedArgs
  if args["--port"]:
    let port = $args["--port"]
    var porterror =false
    if not port.isDigit():
      porterror = true
    try:
      if port.parseInt() > 65535: # may raise overflow error
        porterror = true
    except:
        porterror = true
    
    if porterror:
      error(fmt("invalid --port {port} (should be a number and less than 65535)"))
      quit malformedArgs 

  if args["--redisport"]:
    let redisport = $args["--redisport"]
    var porterror = false
    if not redisport.isDigit():
      porterror = true
    try:
      if redisport.parseInt() > 65535: # may raise overflow error
        porterror = true
    except:
      porterror = true
  
    if porterror:
      error(fmt"invalid --redisport {redisport} (should be a number and less than 65535)")
      quit malformedArgs
    
  if args["<id>"]:
    let contid = $args["<id>"]
    try:
      discard parseInt($args["<id>"])
    except:
      error(fmt"invalid container id {contid}")
      quit malformedArgs
  if args["--jsonargs"]:
    let jsonargs = $args["--jsonargs"]
    try:
      discard parseJson($args["--jsonargs"])
    except:
      error("invalid --jsonargs {jsonargs}")
      quit malformedArgs
  
