import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal
import net, asyncdispatch, asyncnet
import redisclient, redisparser, docopt
import vboxpkg/vbox
import zosclientpkg/zosclient


let doc = """
Usage:
  zos
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--setdefault]
  zos showconfig
  zos setdefault <zosmachine>
  zos cmd <zoscommand> [--jsonargs=<args>]
  zos exec <bashcommand> 
  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--privileged] [--on=<zosmachine>]
  zos container inspect
  zos container info
  zos container list
  zos container <id> inspect
  zos container <id> info
  zos container <id> delete
  zos container <id> zerotierinfo
  zos container <id> zerotierlist
  zos container <id> exec <command>
  zos container <id> sshenable
  zos container <id> sshinfo
  zos container <id> shell
  zos help init
  zos help configure
  zos help setdefault
  zos help showconfig
  zos help cmd
  zos help exec
  zos help container
  zos --version


Options:
  -h --help                       Show this screen.
  --version                       Show version.
  --on=<zosmachine>               Zero-OS machine instance name.
  --disksize=<disksize>           disk size in GB [default: 2]
  --memory=<memorysize>           memory size in GB [default: 2]
  --redisport=<redisport>         redis port [default: 4444]
  --port=<port>                   zero-os port [default: 6379]
  --sshkey=<sshkeyname>           sshkey name [default: id_rsa]
  --setdefault                    sets the configured machine to be default one
  --privileged                    privileged container [default: false]
  --hostname=<hostname>           container hostname [default:]
  --jsonargs=<jsonargs>           json encoded arguments [default: "{}"]
"""


let configdir = ospaths.getConfigDir()
let configfile = configdir / "zos.toml"

proc getCurrentAppConfig(): OrderedTableRef[string, string] =
  let tbl = loadConfig(configfile)
  result = tbl.getOrDefault("app")

proc isConfigured*(): bool =
  let tbl = getCurrentAppConfig()
  return tbl["defaultzos"] != "false"
  
if not fileExists(configfile):
  open(configfile, fmWrite).close()
  var t = loadConfig(configfile)
  t.setSectionKey("app", "defaultzos", "false")
  t.setSectionKey("app", "debug", "false")
  t.writeConfig(configfile)


let firstTimeMessage = """First time to run zos?
To create new machine in VirtualBox use
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]

To configure it to use a specific zosmachine 
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--secret=<secret>]
"""

let currentAppConfig = getCurrentAppConfig()

var zerotierId: string
if os.existsEnv("GRID_ZEROTIER_ID_TESTING"):
  zerotierId = "9bee8941b55787f3" #  "" pub xmonader network
else:
  zerotierId = os.getEnv("GRID_ZEROTIER_ID", "9bee8941b5717835") # pub tf network.

proc sandboxContainer(name:string,  host="localhost", port=6379, timeout=30, debug=false):int =
  echo name, host, $port
  result = 0
type ZosConnectionConfig = object
      name*: string
      address*: string
      port*: int
      sshkey*: string 

proc newZosConnectionConfig(name, address: string, port:int, sshkey=getHomeDir()/".ssh/id_rsa"): ZosConnectionConfig = 
  result = ZosConnectionConfig(name:name, address:address, port:port, sshkey:sshkey)
  
proc getConnectionConfigForInstance(name: string): ZosConnectionConfig =
  let tbl = loadConfig(configfile)
  let address = tbl.getSectionValue(name, "address")
  let parsed = tbl.getSectionValue(name, "port")
  let sshkey = tbl.getSectionValue(name, "sshkey")
  var port = 6379
  try:
    port = parseInt(parsed)
  except:
    echo fmt"Invalid port value: {parsed} will use default for now."
  result = newZosConnectionConfig(name, address, port, sshkey)

proc getCurrentConnectionConfig(): ZosConnectionConfig =
  let tbl = loadConfig(configfile)
  let name = tbl.getSectionValue("app", "defaultzos")
  result = getConnectionConfigForInstance(name)

proc getContainerConfig(containerid:int): OrderedTableRef[string, string] = 
  var tbl = loadConfig(configfile)
  if tbl.hasKey(fmt"container-{containerid}"):
    return tbl[fmt"container-{containerid}"]
  else:
    tbl.setSectionKey(fmt("container-{containerid}"), "sshenabled", "false")
  tbl.writeConfig(configfile)
  return tbl[fmt"container-{containerid}"]

let appconfig = getCurrentAppConfig()


proc cmd*(command: string="core.ping", arguments="{}", timeout=5): string =
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)
  result = currentconnection.zosCore(command, arguments, timeout, appconfig["debug"] == "true")
  echo $result

proc exec*(command: string="hostname", timeout:int=5, debug=false): string =
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)
  result = currentconnection.zosBash(command,timeout, appconfig["debug"] == "true")
  echo $result


proc setdefault*(name="local", debug=false)=
  var tbl = loadConfig(configfile)
  tbl.setSectionKey("app", "defaultzos", name)
  tbl.setSectionKey("app", "debug", $debug)
  tbl.writeConfig(configfile)
  

proc configure*(name="local", address="127.0.0.1", port=4444, sshkeyname="", setdefault=false) =
  var tbl = loadConfig(configfile)
  tbl.setSectionKey(name, "address", address)
  tbl.setSectionKey(name, "port", $port)
  let defaultsshfile = getHomeDir() / ".ssh" / "id_rsa" 
  var keypath= ""

  # HARDEN FOR SSHKEY FILE VALIDATION..
  
  if sshkeyname != "":
    keypath = getHomeDir() / ".ssh" / sshkeyname
    if not existsFile(keypath):
      echo fmt"SSH Key not found: {keypath}"
      quit 6
  else:
    if not existsFile(defaultsshfile):
      echo fmt"SSH Key not found: {keypath}"
      quit 6 

  keypath = defaultsshfile
  tbl.setSectionKey(name, "sshkey", keypath)
  tbl.writeConfig(configfile)
  if setdefault:
    setdefault(name)
  

proc showconfig*() =
  let tbl = loadConfig(configfile)
  echo $tbl.getOrDefault("app")

proc init(name="local", datadiskSize=2, memory=4, redisPort=4444) = 
  # TODO: add cores parameter.
  let isopath = downloadZOSIso()
  try:
    newVM(name, "/tmp/zos.iso", datadiskSize*1024, memory*1024, redisPort)
  except:
    echo "[-] Error: " & getCurrentExceptionMsg()
  echo fmt"Created machine {name}"

  var args = ""

  when defined linux:
    if not existsEnv("DISPLAY"):
      args = "--type headless"
  configure(name, "127.0.0.1", redisPort, setdefault=true)
  let cmd = fmt"""startvm {args} "{name}" &"""
  discard executeVBoxManage(cmd)
  echo fmt"Started VM {name}"
  
  # give it 10 mins
  var trials = 0
  while trials != 120:
    try:
      let con = open("127.0.0.1", redisPort.Port, true)
    except:
      echo "Still pending to have a connection to zos"
      sleep(5)
      trials += 5
  # configure and make that machine the default

proc containersInspect(): string=
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)
  let resp = parseJson(currentconnection.zosCoreWithJsonNode("corex.list", nil))
  result = resp.pretty(2)

proc containerInspect(containerid:int): string =
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)
  let resp = parseJson(currentconnection.zosCoreWithJsonNode("corex.list", nil))
  if not resp.hasKey($containerid):
    echo fmt"container {containerid} not found."
    quit 3
  else:
    result = resp[$containerid].pretty(2) 

type ContainerInfo = object of RootObj
  id*: string
  cpu*: float
  root*: string
  hostname*: string
  pid*: int

proc containerInfo(containerid:int): string =
  let parsedJson = parseJson(containerInspect(containerid))
  let id = $containerid
  let cpu = parsedJson["cpu"].getFloat()
  let root = parsedJson["container"]["arguments"]["root"].getStr()
  let hostname = parsedJson["container"]["arguments"]["hostname"].getStr()
  let pid = parsedJson["container"]["pid"].getInt()
  let cont = ContainerInfo(id:id, cpu:cpu, root:root, hostname:hostname, pid:pid)
  result = parseJson($$(cont)).pretty(2)


proc containersInfo(): string =
  var info = newSeq[ContainerInfo]()
  let parsedJson = parseJson(containersInspect())
  for k,v in parsedJson.pairs:
    let id = k
    let cpu = parsedJson[k]["cpu"].getFloat()
    let root = parsedJson[k]["container"]["arguments"]["root"].getStr()
    let hostname = parsedJson[k]["container"]["arguments"]["hostname"].getStr()
    let pid = parsedJson[k]["container"]["pid"].getInt()
    info.add(ContainerInfo(id:id, cpu:cpu, root:root, hostname:hostname, pid:pid))
  result = parseJson($$(info)).pretty(2)


proc newContainer(name="", root="", zosmachine="", hostname="", privileged=false, timeout=30):int = 
  let currentconnectionConfig = getCurrentConnectionConfig()
  if name == "":
    echo "Please provide a container name"
    quit 2
  if root == "":
    echo "Please provide flist url https://hub.grid.tf/thabet/redis.flist"

  var connectionConfig: ZosConnectionConfig
  if zosmachine == appconfig["defaultzos"]:
    connectionConfig = currentconnectionConfig
  else:
    connectionConfig = getConnectionConfigForInstance(zosmachine)

  let currentconnection = open(connectionConfig.address, connectionConfig.port.Port, true)

  var containerHostName = hostname
  if containerHostName == "":
    containerHostName = name
  
  var args = %*{
    "name": name,
    "hostname": containerHostName,
    "root": root,
    "privileged": privileged,
  }
  
  var extraArgs: JsonNode
  extraArgs = newJObject()

  if not extraArgs.hasKey("nics"):
    extraArgs["nics"] = %*[ %*{"type": "default"}, %*{"type": "zerotier", "id":zerotierId}]

  if not extraArgs.hasKey("config"):
    extraArgs["config"] = newJObject()
  
  echo fmt"sshkeypath: {connectionConfig.sshkey}"
  if not extraArgs["config"].hasKey("/root/.ssh/authorized_keys"):
    extraArgs["config"]["/root/.ssh/authorized_keys"] = %*(open(connectionConfig.sshkey & ".pub", fmRead).readAll())

  if extraArgs != nil:
    for k,v in extraArgs.pairs:
      args[k] = %*v
  
  let appconfig = getCurrentAppConfig()
  let command = "corex.create"
  echo fmt"new container: {command} {args}" 
  
  echo currentconnection.zosCoreWithJsonNode(command, args, timeout, appconfig["debug"] == "true")


proc stopContainer(id:int, timeout=30) =
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)
  let command = "corex.terminate"
  let arguments = %*{"container": id}
  discard currentconnection.zosCoreWithJsonNode(command, arguments, timeout, appconfig["debug"] == "true")


proc execContainer*(containerid:int, command: string="hostname", timeout=5): string =
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)
  result = currentconnection.containersCore(containerid, command, "", timeout, appconfig["debug"] == "true")
  echo $result

proc cmdContainer*(containerid:int, command: string, timeout=5): string =
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)
  result = currentconnection.zosContainerCmd(containerid, command, timeout, appconfig["debug"] == "true")
  
  echo $result  

proc sshEnable*(containerid:int, sshconnectionstring=false): string =
  let currentconnectionConfig = getCurrentConnectionConfig()
  let currentconnection = open(currentconnectionConfig.address, currentconnectionConfig.port.Port, true)

  var currentContainerConfig = getContainerConfig(containerid)
  if currentContainerConfig.hasKey("ip"):
    if not sshconnectionstring:
      return fmt"""ssh root@{currentContainerConfig["ip"]} -i {currentconnectionConfig.sshkey}"""
    else:
      return fmt"""root@{currentContainerConfig["ip"]} -i {currentconnectionConfig.sshkey}"""

  discard execContainer(containerid, "mkdir -p /root/.ssh")
  discard execContainer(containerid, "chmod 700 -R /etc/ssh")
  discard execContainer(containerid, "service ssh start")

  var tbl = loadConfig(configfile)
  tbl.setSectionKey(fmt("container-{containerid}"), "sshenabled", "true")

  let ztsJson = zosCoreWithJsonNode(currentconnection, "corex.zerotier.list", %*{"container":containerid})  
  let parsedZts = parseJson(ztsJson)
  # if len(parsedZts)>0:
  let assignedAddresses = parsedZts[0]["assignedAddresses"].getElems()
  echo "assignedAddresses " & $assignedAddresses
  for el in assignedAddresses:
    var ip = el.getStr()
    if ip.count('.') == 3:
      # potential ip4
      if ip.contains("/"):
        ip = ip[0..<ip.find("/")]
      try:
        echo $parseIpAddress(ip)
      except:
        echo getCurrentExceptionMsg()
        continue

      echo fmt"setting ip to {ip}"
      tbl.setSectionKey(fmt("container-{containerid}"), "ip", ip)
      tbl.writeConfig(configfile)

      result = fmt"ssh root@{ip}"
      echo result

when isMainModule:
  if findExe("vboxmanage") == "":
    echo "Please make sure to have VirtualBox installed"
    quit 3 
  
  let args = docopt(doc, version="zos 0.1.0")
  
  if args["help"]:
    if args["init"]:
      echo """
            zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]

            creates a new virtualbox machine named zosmachine with optional disksize 1GB and memory 2GB  
              --disksize=<disksize>           disk size [default: 1000]
              --memory=<memorysize>           memory size [default: 2048]
              --port=<port>  

      """
    elif args["configure"]:
      echo """
            zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--setdefault]
              configures instance with name zosmachine on address <address>
              --port=<port>                   zero-os port [default: 6379]
              --sshkey=<sshkeyname>           sshkey name [default: id_rsa]
              --setdefault                    sets the configured machine to be default one
              
              """
    elif args["showconfig"]:
      echo """
            Shows application config
           """
    elif args["setdefault"]:
      echo """
          zos setdefault <zosmachine>
            Sets the default instance to work with
      """
    elif args["cmd"]:
      echo """
          zos cmd <zoscommand>
            executes zero-os command e.g "core.ping"
      """
    elif args["exec"]:
      echo """
          zos exec <bashcommand> 
            execute shell command on zero-os host e.g "ls /root -al"
      """
    elif args["container"]:
      echo """

  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--privileged] [--on=<zosmachine>]
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
    quit 0
  if not isConfigured():
    if args["init"]:
      let name = $args["--name"]
      let disksize = parseInt($args["--disksize"])
      let memory = parseInt($args["--memory"])
      let redisport = parseInt($args["--redisport"])
      # echo fmt"dispatching {name} {disksize} {memory} {redisport}"
      init(name, disksize, memory, redisport)
    elif args["configure"]:
      let name = $args["--name"]
      let address = $args["--address"]
      let port = parseInt($args["--port"])
      let sshkeyname = $args["--sshkey"]
      if args["--setdefault"]:
        configure(name, address, port, sshkeyname, true) 
      else:
        configure(name, address, port, sshkeyname) 
    elif args["setdefault"]:
      let name = $args["<zosmachine>"]
      setdefault(name)
    else:
      echo firstTimeMessage
      # echo doc
      quit 5
  else:
    if args["init"]:
      let name = $args["--name"]
      let disksize = parseInt($args["--disksize"])
      let memory = parseInt($args["--memory"])
      let redisport = parseInt($args["--redisport"])
      # echo fmt"dispatching {name} {disksize} {memory} {redisport}"
      init(name, disksize, memory, redisport)
    elif args["configure"]:
      let name = $args["--name"]
      let address = $args["--address"]
      let port = parseInt($args["--port"])
      let sshkeyname = $args["--sshkey"]
      if args["--setdefault"]:
        configure(name, address, port, sshkeyname, true) 
      else:
        configure(name, address, port, sshkeyname) 
    elif args["setdefault"]:
      let name = $args["<zosmachine>"]
      setdefault(name)
    elif args["showconfig"]:
      # echo "asking to show config"
      showconfig()
    elif args["cmd"]:
      let command = $args["<zoscommand>"]
      let jsonargs = $args["--jsonargs"]
      # echo fmt"Dispatching {command} {jsonargs}"
      discard cmd(command, jsonargs)
      ### more... 
    elif args["exec"] and not args["container"]:
      let command = $args["<bashcommand>"]
      # echo fmt"Dispatching {command}"
      discard exec(command)
    elif args["inspect"] and args["<id>"]:
      let containerid = parseInt($args["<id>"])
      echo containerInspect(containerid)
    elif args["inspect"] and not args["<id>"]:
      # echo fmt"dispatch to list containers"
      echo containersInspect()
    elif args["info"] and args["<id>"]:
      let containerid = parseInt($args["<id>"])
      echo containerInfo(containerid)
    elif args["info"] or args["list"] and not args["<id>"]:
      # echo fmt"dispatch to list containers"
      echo containersInfo()
    elif args["delete"]:
      let containerid = parseInt($args["<id>"])
      # echo fmt"dispatching to delete {containerid}"
      stopContainer(containerid)
    elif args["container"] and args["new"]:
      let containername = $args["--name"]
      let rootflist = $args["--root"]
      var hostname = containername 
      if args["--hostname"]:
        hostname = $args["<hostname>"]
      var zosmachine = getCurrentAppConfig()["defaultzos"]
      if args["--on"]:
        zosmachine = $args["<zosmachine>"]
      var privileged=false
      if args["--privileged"]:
        privileged=true
      echo fmt"dispatch creating {containername} on machine {zosmachine} {rootflist} {privileged}"
      discard newContainer(containername, rootflist, zosmachine, hostname, privileged)
    elif args["container"] and args["exec"]:
      let containerid = parseInt($args["<id>"])
      let command = $args["<command>"]
      discard execContainer(containerid, command)
      # echo fmt"dispatch container exec {containerid} {command}"
    elif args["container"] and args["zerotierlist"]:
      let containerid = parseInt($args["<id>"])
      discard cmdContainer(containerid, "corex.zerotier.list")
    elif args["container"] and args["zerotierinfo"]:
      let containerid = parseInt($args["<id>"])
      discard cmdContainer(containerid, "corex.zerotier.info")
    elif args["container"] and args["sshenable"]:
      let containerid = parseInt($args["<id>"])
      echo fmt"Enabling ssh for container {containerid}"
      echo sshEnable(containerid)
    elif args["container"] and args["sshinfo"]:
      let containerid = parseInt($args["<id>"])
      echo fmt"Enabling ssh for container {containerid}"
      echo sshEnable(containerid)
    elif args["container"] and args["shell"]:
      let containerid = parseInt($args["<id>"])
      let sshcmd = sshEnable(containerid, true)
      let p = startProcess("/usr/bin/ssh", args=[sshcmd], options={poInteractive, poParentStreams})
      discard p.waitForExit()
    else:
      echo "Unsupported command"
  
