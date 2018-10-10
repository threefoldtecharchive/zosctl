import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal
import net, asyncdispatch, asyncnet
import redisclient, redisparser, uuid, docopt
import vboxpkg/vbox
import zosclientpkg/zosclient


let doc = """
Usage:
  zos
  zos help
  zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]
  zos configure --name=<zosmachine> --address=<address> [--port=<port>] [--sshkey=<sshkeyname>] [--secret=<secret>] [--setdefault]
  zos showconfig
  zos setdefault <zosmachine>
  zos cmd <zoscommand> [--jsonargs=<args>]
  zos exec <bashcommand> 
  zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--privileged] [--extraconfig=<extraconfig>] [--on=<zosmachine>]
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

  zos --version


Options:
  -h --help                       Show this screen.
  --version                       Show version.
  --on=<zosmachine>               Zero-OS machine instance name [default: local].
  --disksize=<disksize>           disk size [default: 1000]
  --memory=<memorysize>           memory size [default: 2048]
  --redisport=<redisport>         redis port [default: 4444]
  --port=<port>                   zero-os port [default: 6379]
  --sshkey=<sshkeyname>           sshkey name [default: id_rsa]
  --secret=<secret>               secret [default:]
  --setdefault                    sets the configured machine to be default one
  --privileged                    privileged container [default: false]
  --hostname=<hostname>           container hostname [default:]
  --jsonargs=<jsonargs>           json encoded arguments [default: "{}"]
  --extraconfig=<extraconfig>     configurations for building container json encoded [default: "{}"]
            mount: a dict with {host_source: container_target} mount points.
                where host_source directory must exists.
                host_source can be a url to a flist to mount.
            host_network: Specify if the container should share the same network stack as the host.
                      if True, container creation ignores both zerotier, bridge and ports arguments below. Not
                      giving errors if provided.
            nics: Configure the attached nics to the container
              each nic object is a dict of the format
              {
                  'type': nic_type # one of default, bridge, zerotier, macvlan, passthrough, vlan, or vxlan (note, vlan and vxlan only supported by ovs)
                  'id': id # depends on the type
                      bridge: bridge name,
                      zerotier: network id,
                      macvlan: the parent link name,
                      passthrough: the link name,
                      vlan: the vlan tag,
                      vxlan: the vxlan id
                  'name': name of the nic inside the container (ignored in zerotier type)
                  'hwaddr': Mac address of nic.
                  'config': { # config is only honored for bridge, vlan, and vxlan types
                      'dhcp': bool,
                      'cidr': static_ip # ip/mask
                      'gateway': gateway
                      'dns': [dns]
                  }
              }
            port: A dict of host_port: container_port pairs (only if default networking is enabled)
                Example:
                  `port={8080: 80, 7000:7000}`
                Source Format: NUMBER, IP:NUMBER, IP/MAST:NUMBER, or DEV:NUMBER
            storage: A Url to the ardb storage to use to mount the root flist (or any other mount that requires g8fs)
                  if not provided, the default one from core0 configuration will be used.
            identity: Container Zerotier identity, Only used if at least one of the nics is of type zerotier
            env: a dict with the environment variables needed to be set for the container
            cgroups: custom list of cgroups to apply to this container on creation. formated as [(subsystem, name), ...]
                  please refer to the cgroup api for more detailes.
            config: a map with the config file path as a key and content as a value. This only works when creating a VM from an flist. The
            config files are written to the machine before booting.
            Example:
            config = {'/root/.ssh/authorized_keys': '<PUBLIC KEYS>'}

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
      secret*: string

proc newZosConnectionConfig(name, address: string, port:int, sshkey=getHomeDir()/".ssh/id_rsa", secret=""): ZosConnectionConfig = 
  result = ZosConnectionConfig(name:name, address:address, port:port, sshkey:sshkey, secret:secret)
  
proc getConnectionConfigForInstance(name: string): ZosConnectionConfig =
  let tbl = loadConfig(configfile)
  let address = tbl.getSectionValue(name, "address")
  let parsed = tbl.getSectionValue(name, "port")
  let sshkey = tbl.getSectionValue(name, "sshkey")
  let secret = tbl.getSectionValue(name, "secret")
  var port = 6379
  try:
    port = parseInt(parsed)
  except:
    echo fmt"Invalid port value: {parsed} will use default for now."
  result = newZosConnectionConfig(name, address, port, sshkey, secret)

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
  

proc configure*(name="local", address="127.0.0.1", port=4444, sshkeyname="", secret="", setdefault=false) =
  var tbl = loadConfig(configfile)
  tbl.setSectionKey(name, "address", address)
  tbl.setSectionKey(name, "port", $port)
  tbl.setSectionKey(name, "secret", secret)
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

proc init(name="local", datadiskSize=1000, memory=2048, redisPort=4444) = 
  # TODO: add cores parameter.
  let isopath = downloadZOSIso()
  try:
    newVM(name, "/tmp/zos.iso", datadiskSize, memory, redisPort)
  except:
    echo "[-] Error: " & getCurrentExceptionMsg()
  echo fmt"Created machine {name}"

  var args = ""

  when defined linux:
    if not existsEnv("DISPLAY"):
      args = "--type headless"
  let cmd = fmt"""startvm {args} "{name}" """
  discard executeVBoxManage(cmd)
  echo fmt"Started VM {name}"
  # configure and make that machine the default
  configure(name, "127.0.0.1", redisPort)

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
  


proc newContainer(name="", root="", zosmachine="", hostname="", privileged=false, extraconfig="{}", timeout=30):int = 
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
  extraArgs = parseJson(extraconfig)

  # echo fmt"extraconfig: {extraconfig} {extraArgs}"
  # echo extraArgs.type.name

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
  
  echo fmt"args: {args}"
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
    echo "EL" & $el
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
      let secret = $args["--secret"]
      if args["--setdefault"]:
        configure(name, address, port, sshkeyname, secret, true) 
      else:
        configure(name, address, port, sshkeyname, secret) 
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
      let secret = $args["--secret"]
      if args["--setdefault"]:
        configure(name, address, port, sshkeyname, secret, true) 
      else:
        configure(name, address, port, sshkeyname, secret) 
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
      let zosmachine = $args["--on"]
      var privileged=false
      if args["--privileged"]:
        privileged=true
      let extraconfig = $args["--extraconfig"]
      echo fmt"dispatch creating {containername} on machine {zosmachine} {rootflist} {privileged} {extraconfig}"
      discard newContainer(containername, rootflist, zosmachine, hostname, privileged, extraconfig)
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
  
