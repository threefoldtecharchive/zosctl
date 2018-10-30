import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal
import net, asyncdispatch, asyncnet, streams, threadpool
import logging
import algorithm
import base64
import redisclient, redisparser, docopt
#import spinny, colorize

import vboxpkg/vbox
import zosclientpkg/zosclient
import zosapp/settings
import zosapp/apphelp
import zosapp/sshexec
import zosapp/errorcodes
import zosapp/namegenerator

let appTimeout = 30 
let pingTimeout = 5

var L* = newConsoleLogger()
var fL* = newFileLogger("zos.log", fmtStr = verboseFmtStr)
addHandler(L)
addHandler(fL)

let sshtools = @["ssh", "scp"]

proc sshBinsCheck() = 
  for b in sshtools:
    if findExe(b) == "":
      error("ssh tools aren't installed")
      quit sshToolsNotInstalled

proc prepareConfig() = 
  try:
    createDir(configdir)
  except:
    error(fmt"couldn't create {configdir}")
    quit cantCreateConfigDir

  if not fileExists(configfile):
    open(configfile, fmWrite).close()
    var t = loadConfig(configfile)
    t.setSectionKey("app", "debug", "false")
    t.writeConfig(configfile)
    info(firstTimeMessage)

prepareConfig()

proc getAppConfig(): OrderedTableRef[string, string] =
  let tbl = loadConfig(configfile)
  result = tbl.getOrDefault("app")

let appconfig = getAppConfig()

proc isConfigured*(): bool =
  return appconfig.hasKey("defaultzos") == true


proc getActiveZosName*(): string =
  return appconfig["defaultzos"]

proc isDebug*(): bool =
  return appconfig["debug"] == "true"

let debug = isDebug()

proc getZerotierId*(): string =
  if os.existsEnv("GRID_ZEROTIER_ID_TESTING"):
    result = os.getEnv("GRID_ZEROTIER_ID_TESTING")    
    info(fmt"using special zerotier network {result}")
  else:
    result = os.getEnv("GRID_ZEROTIER_ID", "9bee8941b5717835") # pub tf network.

let zerotierId = getZerotierId()

type ZosConnectionConfig  = object
      name*: string
      address*: string
      port*: int
      sshkey*: string 

proc newZosConnectionConfig(name, address: string, port:int, sshkey=getHomeDir()/".ssh/id_rsa"): ZosConnectionConfig  = 
  result = ZosConnectionConfig(name:name, address:address, port:port, sshkey:sshkey)
  
proc getConnectionConfigForInstance(name: string): ZosConnectionConfig  =
  let tbl = loadConfig(configfile)
  let address = tbl.getSectionValue(name, "address")
  let parsed = tbl.getSectionValue(name, "port")
  let sshkey = tbl.getSectionValue(name, "sshkey")
  var port = 6379
  try:
    port = parseInt(parsed)
  except:
    warn("Invalid port value: {parsed} will use default for now.")
  result = newZosConnectionConfig(name, address, port, sshkey)

proc getCurrentConnectionConfig(): ZosConnectionConfig =
  let tbl = loadConfig(configfile)
  let name = tbl.getSectionValue("app", "defaultzos")
  result = getConnectionConfigForInstance(name)

type App = object of RootObj
  currentconnectionConfig*:  ZosConnectionConfig

proc currentconnection*(this: App): Redis =
  result = open(this.currentconnectionConfig.address, this.currentconnectionConfig.port.Port, true)

proc initApp(): App = 
  let currentconnectionConfig =  getCurrentConnectionConfig()
  result = App(currentconnectionConfig:currentconnectionConfig)

proc cmd*(this:App, command: string="core.ping", arguments="{}", timeout=5): string =
  result = this.currentconnection.zosCore(command, arguments, timeout, debug)
  echo $result

proc exec*(this:App, command: string="hostname", timeout:int=5, debug=false): string =
  result = this.currentconnection.zosBash(command,timeout, debug)
  echo $result


proc setdefault*(name="local", debug=false)=
  var tbl = loadConfig(configfile)
  if not tbl.hasKey(name):
    error(fmt"instance {name} isn't configured to be used as default")
    quit instanceNotConfigured
  tbl.setSectionKey("app", "defaultzos", name)
  tbl.setSectionKey("app", "debug", $debug)
  tbl.writeConfig(configfile)
  

proc configure*(name="local", address="127.0.0.1", port=4444, setdefault=false) =
  var tbl = loadConfig(configfile)
  tbl.setSectionKey(name, "address", address)
  tbl.setSectionKey(name, "port", $port)

  tbl.writeConfig(configfile)
  if setdefault or not isConfigured():
    setdefault(name)
  
proc showconfig*() =
  echo readFile(configfile)

proc init(name="local", datadiskSize=20, memory=4, redisPort=4444) = 
  # TODO: add cores parameter.
  let isopath = downloadZOSIso()
  let (taken, byVm) = portAlreadyForwarded(redisPort)
  if taken == true and byVm != name:
    error(fmt"port {redisPort} already taken by {byVm}")
    quit portForwardExists
  if not exists(name):
    try:
      newVM(name, "/tmp/zos.iso", datadiskSize*1024, memory*1024, redisPort)
    except:
      error(getCurrentExceptionMsg())
    info(fmt"created machine {name}")
  else:
    info(fmt"machine {name} exists already")

  if isRunning(name): 
    info("machine already running")
    quit 0

  spawn(startVm(name))
  
  info("preparing zos machine...may take a while..") # should show a spinner here.
  # give it 10 mins
  var ponged = false
  for i in countup(0, 500):
    try:
      var con = open("127.0.0.1", redisPort.Port, true)
      con.timeout = 1000
      echo $con.execCommand("PING", @[])
      ponged = true
      break
    except:
      sleep(5000)

  if ponged:
    info("created zos machine and we are ready.")
    configure(name, "127.0.0.1", redisPort, setdefault=true)

  else:
    error("couldn't prepare zos machine.")
  
proc removeContainerFromConfig*(this:App, containerid:int) =
  let activeZos = getActiveZosName()
  var tbl = loadConfig(configfile)
  let containerKey = fmt"container-{activeZos}-{containerid}"
  if tbl.hasKey(containerKey):
    tbl.del(containerKey)
  tbl.writeConfig(configfile)

proc containersInspect(this:App): string=
  let resp = parseJson(this.currentconnection.zosCoreWithJsonNode("corex.list", nil))
  result = resp.pretty(2)

proc containerInspect(this:App, containerid:int): string =
  let resp = parseJson(this.currentconnection.zosCoreWithJsonNode("corex.list", nil))
  if not resp.hasKey($containerid):
    error(fmt"container {containerid} not found.")
    quit containerNotFound
  else:
    result = resp[$containerid].pretty(2) 

type ContainerInfo = object of RootObj
  id*: string
  cpu*: float
  root*: string
  hostname*: string
  name*: string
  storage*: string
  pid*: int
  ports*: string


proc containerInfo(this:App, containerid:int): string =
  let parsedJson = parseJson(this.containerInspect(containerid))
  let id = $containerid
  let cpu = parsedJson["cpu"].getFloat()
  let root = parsedJson["container"]["arguments"]["root"].getStr()
  let name = parsedJson["container"]["arguments"]["name"].getStr()
  let hostname = parsedJson["container"]["arguments"]["hostname"].getStr()
  let pid = parsedJson["container"]["pid"].getInt()

  var ports = "" 
  if parsedJson["container"]["arguments"]["port"].len > 0:
    for k, v in parsedJson["container"]["arguments"]["port"].pairs:
      let vnum = v.getInt()
      ports &= fmt"{k}:{vnum},"
  
  if ports != "":
    ports = ports[0..^2] # strip last comma
  let cont = ContainerInfo(id:id, cpu:cpu, root:root, name:name, hostname:hostname, ports:ports, pid:pid)
  result = parseJson($$(cont)).pretty(2)


proc getContainerInfoList(this:App): seq[ContainerInfo] =
  result = newSeq[ContainerInfo]()
  let parsedJson = parseJson(this.containersInspect())
  
  for k,v in parsedJson.pairs:
    let id = k
    let cpu = parsedJson[k]["cpu"].getFloat()
    let root = parsedJson[k]["container"]["arguments"]["root"].getStr()
    let name = parsedJson[k]["container"]["arguments"]["name"].getStr()
    let hostname = parsedJson[k]["container"]["arguments"]["hostname"].getStr()
    let storage = parsedJson[k]["container"]["arguments"]["storage"].getStr()
    let pid = parsedJson[k]["container"]["pid"].getInt()

    var ports = "" 
    if parsedJson[k]["container"]["arguments"]["port"].len > 0:
      for k, v in parsedJson[k]["container"]["arguments"]["port"].pairs:
        let vnum = v.getInt()
        ports &= fmt"{k}:{vnum},"
    if ports != "":
      ports = ports[0..^2] # strip last comma
    
    let cont = ContainerInfo(id:id, cpu:cpu, root:root, name:name, hostname:hostname, ports:ports, pid:pid)
    result.add(cont)

  result = result.sortedByIt(parseInt(it.id))
  
proc containersInfo(this:App, showjson=false): string =
  let info = this.getContainerInfoList()
  
  if showjson == true:
    result = parseJson($$(info)).pretty(2)
  else:
    var widths = @[0,0,0,0]  #id, name, ports, root
    for k, v in info:
      if len($v.id) > widths[0]:
        widths[0] = len($v.id)
      if len($v.name) > widths[1]:
        widths[1] = len($v.name)
      if len($v.ports) > widths[2]:
        widths[2] = len($v.ports)
      if len($v.root) > widths[3]:
        widths[3] = len($v.root)
    
    var sumWidths = 0
    for w in widths:
      sumWidths += w

    
    echo "-".repeat(sumWidths)

    let extraPadding = 5
    echo "| ID"  & " ".repeat(widths[0]+ extraPadding-4) & "| Name" & " ".repeat(widths[1]+extraPadding-6) & "| Ports" & " ".repeat(widths[2]+extraPadding-6 ) & "| Root" &  " ".repeat(widths[3]-6)
    echo "-".repeat(sumWidths)
 

    for k, v in info:
      let nroot = replace(v.root, "https://hub.grid.tf/", "").strip()
      echo "|" & $v.id & " ".repeat(widths[0]-len($v.id)-1 + extraPadding) & "|" & v.name & " ".repeat(widths[1]-len(v.name)-1 + extraPadding) & "|" & v.ports & " ".repeat(widths[2]-len(v.ports)+extraPadding) & "|" & nroot & " ".repeat(widths[3]-len(v.root)+ extraPadding-2) & "|"
      echo "-".repeat(sumWidths)
    result = ""

proc syncContainersIds(this: App) =
  # updates the configfile with the still existing containers.
  # less likely we will need to crossreference against the IPs to make sure
  # if they're the same containers or the node was reinstalled?
  let activeZos = getActiveZosName()
  let conf = loadConfig(configfile)

  var containersIds:seq[int] = @[]
  for sectionKey, tbl in conf:
    if sectionKey.startsWith(fmt"container-{activeZos}") == true:
      containersIds.add(parseInt(sectionKey.split("-")[2]))
  
  if containersIds.len == 0:
    error("you need to create containers using zos to use them implicitly")
    quit containerDoesntExist

  let actualContainersInfo = this.getContainerInfoList()
  var actualContainersIds: seq[int] = @[]
  for c in actualContainersInfo:
    let cid = parseInt(c.id)
    actualContainersIds.add(cid)

  for cid in containersIds:
    if not actualContainersIds.contains(cid):
      this.removeContainerFromConfig(cid)


proc getLastContainerId(this:App): int = 
  # make sure to sync containers information from zero-os first
  # just in case of deletion from other application.
  this.syncContainersIds()
  let activeZos = getActiveZosName()
  let conf = loadConfig(configfile)

  var containersIds:seq[int] = @[]
  for sectionKey, tbl in conf:
    if sectionKey.startsWith(fmt"container-{activeZos}") == true:
      containersIds.add(parseInt(sectionKey.split("-")[2]))
  
  if containersIds.len == 0:
    error("you need to create containers using zos to use them implicitly")
    quit containerDoesntExist
    
  result = containersIds.sorted(system.cmp[int], Descending)[0]
  

proc getContainerNameById*(this:App, containerid:int): string =
  let allContainers = this.getContainerInfoList()
  var name = ""
  for c in allContainers:
    if c.id == $containerid:
      return c.name
      

proc getContainerConfig(this:App, containerid:int): OrderedTableRef[string, string] = 
  let containerName = this.getContainerNameById(containerid)
  let activeZos = getActiveZosName()

  var tbl = loadConfig(configfile)
  if tbl.hasKey(fmt"container-{activeZos}-{containerid}"):
    return tbl[fmt"container-{activeZos}-{containerid}"]
  else:
    tbl.setSectionKey(fmt("container-{activeZos}-{containerid}"), "sshenabled", "false")
  tbl.writeConfig(configfile)
  return tbl[fmt"container-{activeZos}-{containerid}"]
    

proc containerHasIP(this: App, containerid:int): bool = 
  let containerConfig = this.getContainerConfig(containerid)
  return containerConfig.hasKey("ip")


proc getContainerIp(this:App, containerid: int): string = 
  let activeZos = getActiveZosName()
  
  var done = false
  var ip = ""

  echo fmt"[3/4] Waiting for private network connectivity"

  for trial in countup(0, 120):
    try:
      let ztsJson = zosCoreWithJsonNode(this.currentconnection, "corex.zerotier.list", %*{"container":containerid})
      let parsedZts = parseJson(ztsJson)
      # if len(parsedZts)>0:
      var tbl = loadConfig(configfile)
      let assignedAddresses = parsedZts[0]["assignedAddresses"].getElems()
      for el in assignedAddresses:
        var ip = el.getStr()
        if ip.count('.') == 3:
          # potential ip4
          if ip.contains("/"):
            ip = ip[0..<ip.find("/")]
          try:
            ip = $parseIpAddress(ip)
            tbl.setSectionKey(fmt("container-{activeZos}-{containerid}"), "ip", ip)
            tbl.writeConfig(configfile)
            return ip

          except:
            sleep(1000)
    except:
      discard

    sleep(1000)

  error(fmt"couldn't get zerotier information for container {containerid}")



proc newContainer(this:App, name:string, root:string, hostname="", privileged=false, timeout=30, sshkey="", ports="", env=""):int =
  let activeZos = getActiveZosName()
  var containerHostName = hostname
  if containerHostName == "":
    containerHostName = name

  echo fmt"[...] Preparing container"

  var portsMap = initTable[string,int]()
  if ports != "":
    for pair in ports.split(","):
      let mypair = pair.strip() #
      if not pair.contains(":"):
        error(fmt"""malformed ports {ports}: should be "hostport1:containerport1,hostport2:containerport2" """)
        quit malformedArgs
      let parts = mypair.split(":")
      if len(parts) != 2:
        error(fmt"""malformed ports {ports}: should be "hostport1:containerport1,hostport2:containerport2" """)
        quit malformedArgs
  
      let hostport = parts[0]
      let containerport = parts[1]
      if not hostport.isDigit():
        error(fmt"""malformed ports {ports}: {hostport} isn't a digit""")
        quit malformedArgs
      if not hostport.isDigit():
        error(fmt"""malformed ports {ports}: {hostport} isn't a digit""")
        quit malformedArgs
      portsMap[hostport] = parseInt(containerport)

  var envMap = initTable[string,string]()
  if env != "":
    for pair in env.split(","):
      let mypair = pair.strip()
      if not pair.contains(":"):
        error(fmt"""malformed environent variable: should be "key:value" """)
        quit malformedArgs
      let parts = mypair.split(":", maxSplit=1)
      if len(parts) != 2:
        error(fmt"""malformed environent variable: should be "key:value" """)
        quit malformedArgs

      let key = parts[0]
      let value = parts[1]
      envMap[key] = value

  var args = %*{
    "name": name,
    "hostname": containerHostName,
    "root": root,
    "privileged": privileged,
  }
  var extraArgs: JsonNode
  extraArgs = newJObject()

  extraArgs["port"] = newJObject()
  for k, v in portsMap.pairs:
    extraArgs["port"][k] = %*v
  

  extraArgs["env"] = newJObject()
  for k, v in envMap.pairs:
    extraArgs["env"][k] = %*v
 
  if not extraArgs.hasKey("nics"):
    extraArgs["nics"] = %*[ %*{"type": "default"}, %*{"type": "zerotier", "id":zerotierId}]

  if not extraArgs.hasKey("config"):
    extraArgs["config"] = newJObject()
  
  var keys = ""
  var configuredsshkey = "false"

  if sshkey == "":
    keys = getAgentPublicKeys()
  else:
    
    let sshDirRelativeKey = getHomeDir() / ".ssh" / fmt"{sshkey}"
    let sshDirRelativePubKey = getHomeDir() / ".ssh" / fmt"{sshkey}.pub"

    let defaultSshKey = getHomeDir() / ".ssh" / fmt"id_rsa"
    let defaultSshPubKey = getHomeDir() / ".ssh" / fmt"id_rsa.pub"
    
    var k = ""
    if fileExists(sshkey):
      k = readFile(sshkey & ".pub")
      configuredsshkey = sshkey
    elif fileExists(sshDirRelativeKey):
      configuredsshkey = sshDirRelativeKey
      k = readFile(sshDirRelativePubKey)
    elif fileExists(defaultSshKey):
      configuredsshkey = defaultSshKey
      k =  readFile(defaultSshPubKey)

    keys &= k
  
  if keys == "":
    error("couldn't find sshkeys in agent or in default paths [generate one with ssh-keygen]")
    quit cantFindSshKeys

  # if not extraArgs["config"].hasKey("/root/.ssh/authorized_keys"):
  extraArgs["config"]["/root/.ssh/authorized_keys"] = %*(keys)

  if extraArgs != nil:
    for k,v in extraArgs.pairs:
      args[k] = %*v

  let appconfig = getAppConfig() 
  let command = "corex.create"
  
  # info(fmt"new container: {command} {args}")
  echo fmt"[1/4] Sending instructions to host"
  
  let contId = this.currentconnection.zosCoreWithJsonNode(command, args, timeout, debug)
  try:
    result = parseInt(contId)
  except:
    # if debug:
    error(getCurrentExceptionMsg())
    echo "couldn't create container"
    quit cantCreateContainer
  
  var tbl = loadConfig(configfile)
  tbl.setSectionKey(fmt"container-{activeZos}-{result}", "sshkey", configuredsshkey)
  tbl.setSectionKey(fmt"container-{activeZos}-{result}", "layeredssh", "false")
  tbl.writeConfig(configfile)

  echo fmt"[2/4] Container created. Identifier: {result}"


proc layerSSH(this:App, containerid:int, timeout=30) =
  let activeZos = getActiveZosName()
  #let sshflist = "https://hub.grid.tf/thabet/busyssh.flist"
  let sshflist = "https://hub.grid.tf/tf-bootable/ubuntu:18.04.flist"

  var tbl = loadConfig(configfile)

  let containerName = this.getContainerNameById(containerid)
  let containerKey = fmt"container-{activeZos}-{containerid}"
  if tbl.hasKey(containerKey): 
    if tbl[containerKey]["layeredssh"] == "false":
      let parsedJson = parseJson(this.containerInspect(containerid))
      let id = $containerid
      let cpu = parsedJson["cpu"].getFloat()
      let root = parsedJson["container"]["arguments"]["root"].getStr()
      if root != sshflist:
        echo "[...] Adding SSH support to your container"

        var args = %*{
          "container": containerid,
          "flist": sshflist
        }

        let command = "corex.flist-layer"
        discard this.currentconnection.zosCoreWithJsonNode(command, args, timeout, debug)
      
      echo "[...] SSH support enabled"
      tbl[containerKey]["layeredssh"] = "true"
  
  tbl.writeConfig(configfile)



proc stopContainer*(this:App, containerid:int, timeout=30) =
  let activeZos = getActiveZosName()
  let containerName = this.getContainerNameById(containerid)
  let command = "corex.terminate"
  let arguments = %*{"container": containerid}
  discard this.currentconnection.zosCoreWithJsonNode(command, arguments, timeout, debug)

  this.removeContainerFromConfig(containerid)

proc execContainer*(this:App, containerid:int, command: string="hostname", timeout=5): string =
  result = this.currentconnection.containersCore(containerid, command, "", timeout, debug)
  echo $result

proc execContainerSilently*(this:App, containerid:int, command: string="hostname", timeout=5): string =
  result = this.currentconnection.containersCore(containerid, command, "", timeout, debug)

proc cmdContainer*(this:App, containerid:int, command: string, timeout=5): string =
  result = this.currentconnection.zosContainerCmd(containerid, command, timeout, debug)
  echo $result  



proc sshInfo*(this:App, containerid: int): string = 
  let activeZos = getActiveZosName()

  let containerName = this.getContainerNameById(containerid)
  var currentContainerConfig = this.getContainerConfig(containerid)

  var tbl = loadConfig(configfile)
  let configuredsshkey = tbl[fmt"container-{activeZos}-{containerid}"].getOrDefault("sshkey", "false")

  var connectionString = ""
  if currentContainerConfig.hasKey("ip"):
    if configuredsshkey != "false":
      connectionString = fmt"""root@{currentContainerConfig["ip"]} -i {configuredsshkey}"""
    else:
      connectionString = fmt"""root@{currentContainerConfig["ip"]}"""

  return connectionString

proc sshEnable*(this: App, containerid:int): string =
  let activeZos = getActiveZosName()
  this.layerSSH(containerid)

  discard this.getContainerIp(containerid)
  var tbl = loadConfig(configfile)
  if tbl[fmt("container-{activeZos}-{containerid}")].getOrDefault("sshenabled", "false") == "false":
    # discard this.execContainer(containerid, "busybox mkdir -p /root/.ssh")
    # discard this.execContainer(containerid, "busybox chmod 700 -R /etc/ssh")

    # discard this.execContainer(containerid, "busybox mkdir -p /run/sshd")
    # discard this.execContainer(containerid, "/usr/sbin/sshd -D")
    # discard this.execContainer(containerid, "busybox --install")
    # discard this.execContainer(containerid, "mkdir -p /sbin")

    discard this.execContainer(containerid, "mkdir -p /root/.ssh")
    discard this.execContainer(containerid, "chmod 700 -R /etc/ssh")

    tbl.setSectionKey(fmt("container-{activeZos}-{containerid}"), "sshenabled", "true")
    tbl.writeConfig(configfile)
  discard this.execContainerSilently(containerid, "service ssh start")
  discard this.execContainer(containerid, "service ssh status")
  # discard this.execContainer(containerid, "netstat -ntlp")

  result = this.sshInfo(containerid)




proc authorizeContainer(this:App, containerid:int, sshkey=""): int = 
  result = containerid
  let activeZos = getActiveZosName()

  var keys = ""
  var configuredsshkey = ""
  if sshkey == "":
    keys = getAgentPublicKeys()
  else:
    
    let sshDirRelativeKey = getHomeDir() / ".ssh" / fmt"{sshkey}"
    let sshDirRelativePubKey = getHomeDir() / ".ssh" / fmt"{sshkey}.pub"

    let defaultSshKey = getHomeDir() / ".ssh" / fmt"id_rsa"
    let defaultSshPubKey = getHomeDir() / ".ssh" / fmt"id_rsa.pub"
    
    var k = ""
    if fileExists(sshkey):
      k = readFile(sshkey & ".pub")
      configuredsshkey = sshkey
    elif fileExists(sshDirRelativeKey):
      configuredsshkey = sshDirRelativeKey
      k = readFile(sshDirRelativePubKey)
    elif fileExists(defaultSshKey):
      configuredsshkey = defaultSshKey
      k =  readFile(defaultSshPubKey)

    keys &= k

  if keys == "":
    error("couldn't find sshkeys in agent or in default paths [generate one with ssh-keygen]")
    quit cantFindSshKeys

  discard this.exec("mkdir -p /mnt/containers/{containerid}/root/.ssh")
  discard this.exec("mkdir -p /mnt/containers/{containerid}/var/run/sshd")
  discard this.exec("touch /mnt/containers/{containerid}/root/.ssh/authorized_keys")

  var args = %*{
   "file": fmt"/mnt/containers/{containerid}/root/.ssh/authorized_keys",
   "mode":"a"
  }

  var fd = this.currentconnection().zosCoreWithJsonNode("filesystem.open", args)
  if fd.startsWith("\""):
    fd = fd[1..^2]  # double quotes encoded
  let content = base64.encode(keys)

  args = %*{
   "fd": fd,
   "block": content
  }

  discard this.currentconnection().zosCoreWithJsonNode("filesystem.write", args)

  var tbl = loadConfig(configfile)
  tbl.setSectionKey(fmt"container-{activeZos}-{result}", "sshkey", configuredsshkey)
  tbl.setSectionKey(fmt"container-{activeZos}-{result}", "layeredssh", "false")
  tbl.writeConfig(configfile)
  discard this.getContainerIp(containerid)

  echo $this.sshEnable(containerid)


proc handleUnconfigured(args:Table[string, Value]) =
  if args["init"]:
    if findExe("vboxmanage") == "":
      error("please make sure to have VirtualBox installed")
      quit vboxNotInstalled

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
    if args["--setdefault"]:
      configure(name, address, port, true) 
    else:
      configure(name, address, port) 
  elif args["setdefault"]:
    let name = $args["<zosmachine>"]
    setdefault(name)


proc handleConfigured(args:Table[string, Value]) = 
  let app = initApp()
  
  proc handleInit() = 
    let name = $args["--name"]
    let disksize = parseInt($args["--disksize"])
    let memory = parseInt($args["--memory"])
    let redisport = parseInt($args["--redisport"])
    var reset = false
    if args["--reset"]:
      reset = true
    # echo fmt"dispatching {name} {disksize} {memory} {redisport}"
    if reset == true:
      try:
        vmDelete(name)
        info(fmt"deleted vm {name}")
      except:
        discard # clear error here..
    if exists(name):
      let vmzosconfig = getConnectionConfigForInstance(name)
      if redisport != vmzosconfig.port:
        warn(fmt"{name} is already configured against {vmzosconfig.port} and you want it to use {redisport}")
        echo "continue? [Y/n]: "
        let shouldContinue = stdin.readLine()
        if shouldContinue.toLowerAscii() == "y":
          try:
            vmDelete(name)
          except:
            discard # clear error here..
        else:
          quit 0

    init(name, disksize, memory, redisport)
  
  proc handleRemove() = 
    let name = $args["--name"]
    try:
      vmDelete(name)
      info(fmt"deleted vm {name}")
    except:
      discard # clear error here..
  
  proc handleConfigure() =
    let name = $args["--name"]
    let address = $args["--address"]
    let port = parseInt($args["--port"])
    let sshkeyname = $args["--sshkey"]
    if args["--setdefault"]:
      configure(name, address, port, true) 
    else:
      configure(name, address, port) 

  proc handleSetDefault() =
    let name = $args["<zosmachine>"]
    setdefault(name)

  proc handleShowConfig() = 
    showconfig()

  proc handlePing() =
    discard app.cmd("core.ping", "")

  proc handleCmd() =
    let command = $args["<zoscommand>"]
    let jsonargs = $args["--jsonargs"]
    # echo fmt"Dispatching {command} {jsonargs}"
    discard app.cmd(command, jsonargs)
  
  proc handleExec() = 
    let command = $args["<command>"]
    # echo fmt"Dispatching {command}"
    discard app.exec(command)

  proc handleContainersInspect() =
    echo app.containersInspect()
  
  proc handleContainerInspect() =
    let containerid = parseInt($args["<id>"])
    echo app.containerInspect(containerid)

  proc handleContainersInfo() =
    var showjson = false
    if args["--json"]:
      showjson = true
    echo app.containersInfo(showjson)
  
  proc handleContainerInfo() =
    let containerid = parseInt($args["<id>"])
    echo app.containerInfo(containerid)
   
  proc handleContainerDelete() =
    let containerid = parseInt($args["<id>"])
    # echo fmt"dispatching to delete {containerid}"
    app.stopContainer(containerid)

  proc handleContainerNew() =
    var containername = ""
    if not args["--name"]:
      containername = getRandomName()
    else:
      containername = $args["--name"]
    let rootflist = $args["--root"]


    var hostname = containername
    var ports = ""
    var env = ""
    if args["--hostname"]:
      hostname = $args["--hostname"]
    var privileged=false
    if args["--privileged"]:
      privileged=true
    var sshkey = ""
    if args["--sshkey"]:
      sshkey = $args["--sshkey"]
    if args["--ports"]:
      ports = $args["--ports"]
    if args["--env"]:
      env = $args["--env"]

    # info(fmt"dispatch creating {containername} on machine {rootflist} {privileged}")
    # info(fmt"Creating '{containername}' using root: {rootflist}")

    let containerId = app.newContainer(containername, rootflist, hostname, privileged, sshkey=sshkey, ports=ports, env=env)
    echo fmt"[4/4] Container private address: ", app.getContainerIp(containerId)

    if args["--ssh"]:
      discard app.sshEnable(containerId)

  proc handleContainerAuthorize() =
    let containerid = parseInt($args["<id>"])
    var sshkey = ""
    if args["--sshkey"]:
      sshkey = $args["--sshkey"]
    echo $app.authorizeContainer(containerid, sshkey=sshkey)


  proc handleContainerZosExec() =
    let containerid = parseInt($args["<id>"])
    let command = $args["<command>"]
    discard app.execContainer(containerid, command)

  proc handleSshEnable() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    echo app.sshEnable(containerid)

  proc handleSshInfo() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    echo app.sshEnable(containerid)

  proc handleContainerShell() = 
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    
    let zosMachine = getActiveZosName()
    info(fmt"sshing to container {containerid} on {zosMachine}")
    let sshcmd = "ssh " & app.sshEnable(containerid)
    discard execCmd(sshcmd)

  proc handleContainerJumpscaleCommand() = 
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    var jscommand = args["<command>"]

    let sshcmd = "ssh " & app.sshEnable(containerid) & fmt""" 'js_shell "{args["<command>"]}" ' """
    info(fmt"executing command: {sshcmd}")
    discard execCmd(sshcmd)

  
  proc handleContainerExec() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    let sshcmd = "ssh " & app.sshEnable(containerid) & fmt""" '{args["<command>"]}'"""
    discard execCmd(sshcmd)

  proc handleContainerUpload() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    if not app.containerHasIP(containerid):
      echo "Make sure to enable ssh first"
      quit sshIsntEnabled
    let file = $args["<file>"]
    if not (fileExists(file) or dirExists(file)):
      error(fmt"file {file} doesn't exist")
      quit fileDoesntExist
    let dest = $args["<dest>"]
    let containerConfig = app.getContainerConfig(containerid)
    discard app.sshEnable(containerid) 

    let sshDest = fmt"""root@{containerConfig["ip"]}:{dest}"""

    var isDir = false
    if dirExists(file):
      isDir=true
    discard execCmd(rsyncUpload(file, sshDest, isDir))
  
  proc handleContainerDownload() = 
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    if not app.containerHasIP(containerid):
      echo "Make sure to enable ssh first"
      quit sshIsntEnabled
    let file = $args["<file>"]
    let dest = $args["<dest>"]
    let containerConfig = app.getContainerConfig(containerid)
    discard app.sshEnable(containerid) 

    let sshSrc = fmt"""root@{containerConfig["ip"]}:{file}"""
    var isDir = true # always true.
    discard execCmd(rsyncDownload(sshSrc, dest, isDir))

  if args["init"]:
    handleInit()
  elif args["remove"]:
    handleRemove()
  elif args["configure"]:
    handleConfigure()
  elif args["setdefault"]:
    handleSetDefault()
  elif args["showconfig"]:
    handleShowConfig()
  else: 
    # commands requires active zos connection.
    try:
      var con = app.currentconnection()
      con.timeout = 5000
      discard con.execCommand("PING", @[])
    except:
      echo(getCurrentExceptionMsg())
      error("[-]can't reach zos")
      quit unreachableZos
    
    if args["ping"]:
      handlePing()
    elif args["cmd"]:
      handleCmd()
    elif args["exec"] and not args["container"]:
      handleExec()
    elif args["inspect"] and args["<id>"]:
      handleContainerInspect()
    # elif args["authorize"] and args["<id>"]:
    #   handleContainerAuthorize()
    elif args["inspect"] and not args["<id>"]:
      handleContainersInspect()
    elif args["info"] and args["<id>"]:
      handleContainerInfo()
    elif args["info"] or args["list"] and not args["<id>"]:
      # echo fmt"dispatch to list containers"
      handleContainersInfo()
    elif args["delete"]:
      handleContainerDelete()
    elif args["container"] and args["new"]:
      handleContainerNew()
    elif args["container"] and args["zosexec"]:
      handleContainerZosExec()
      # echo fmt"dispatch container exec {containerid} {command}"
    elif args["container"] and args["zerotierlist"]:
      let containerid = parseInt($args["<id>"])
      discard app.cmdContainer(containerid, "corex.zerotier.list")
    elif args["container"] and args["zerotierinfo"]:
      let containerid = parseInt($args["<id>"])
      discard app.cmdContainer(containerid, "corex.zerotier.info")
    elif args["container"] and args["sshenable"]:
      handleSshEnable()
    elif args["container"] and args["sshinfo"]:
      handleSshInfo()
    elif args["container"] and args["shell"]:
      handleContainerShell()
    elif args["container"] and args["exec"]:
      handleContainerExec()
    elif args["container"] and args["upload"]:
      handleContainerUpload()
    elif args["container"] and args["download"]:
      handleContainerDownload()
    elif args["container"] and args["js9"]:
      handleContainerJumpscaleCommand()
    else:
      getHelp("")
      quit unknownCommand

const buildBranchName = staticExec("git rev-parse --abbrev-ref HEAD")
const buildCommit = staticExec("git rev-parse HEAD")
      
when isMainModule:
  let args = docopt(doc, version=fmt"zos 0.1.0 ({buildBranchName}#{buildCommit})")
  if args["help"] and args["<cmdname>"]:
    getHelp($args["<cmdname>"])
    quit 0
  if args["help"]:
    getHelp("")
    quit 0
  
  if not isConfigured():
    handleUnconfigured(args)
  else:
    try:
      handleConfigured(args)
    except:
      echo getCurrentExceptionMsg()
      quit generalError
