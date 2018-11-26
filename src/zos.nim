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
import zosapp/hostnamegenerator


var L* = newConsoleLogger(levelThreshold=lvlInfo)
var fL* = newFileLogger("zos.log", levelThreshold=lvlAll, fmtStr = verboseFmtStr)
addHandler(L)
addHandler(fL)

let sshtools = @["ssh", "scp", "sshfs"]

proc sshBinsCheck() = 
  for b in sshtools:
    if findExe(b) == "":
      error(fmt"ssh tools aren't installed: can't find {b} in \$PATH")
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
  
  let sshconfigFile = getHomeDir() / ".ssh" / "config"
  let sshconfigFileBackup = getHomeDir() / ".ssh" / "config.backup"
  let sshconfigTemplate = """
Host *
  StrictHostKeyChecking no
  ForwardAgent yes

"""
  if fileExists(sshconfigFile):
    let content = readFile(sshconfigFile)
    if not content.contains(sshconfigTemplate):
      copyFile(sshconfigFile, sshconfigFileBackup)
      debug(fmt"copied {sshconfigFile} to {sshconfigFileBackup}")
      let oldContent = readFile(sshconfigFile)
      let newContent = sshconfigTemplate & oldContent 
      writeFile(sshconfigFile, sshconfigTemplate)
  else:
      writeFile(sshconfigFile, sshconfigTemplate)


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
  else:
    result = os.getEnv("GRID_ZEROTIER_ID", "9bee8941b5717835") # pub tf network.
  debug(fmt"using zerotier network {result}")

let zerotierId = getZerotierId()

type ZosConnectionConfig  = object
      name*: string
      address*: string
      port*: int
      sshkey*: string 
      isvbox*: bool

proc newZosConnectionConfig(name, address: string, port:int, sshkey=getHomeDir()/".ssh/id_rsa", isvbox=false): ZosConnectionConfig  = 
  result = ZosConnectionConfig(name:name, address:address, port:port, sshkey:sshkey, isvbox:isvbox)
  
proc getConnectionConfigForInstance(name: string): ZosConnectionConfig  =
  var tbl = loadConfig(configfile)
  let address = tbl.getSectionValue(name, "address")
  let parsed = tbl.getSectionValue(name, "port")
  let sshkey = tbl.getSectionValue(name, "sshkey")

  var isvbox = false
  try:
    isvbox = tbl.getSectionValue(name, "isvbox") == "true"
  except:
    debug(fmt"machine {name} is not on virtualbox")
    discard
  
  tbl.writeConfig(configfile)
  var port = 6379
  try:
    port = parseInt(parsed)
  except:
    warn(fmt"invalid port value: >{parsed}< will use default for now.")
  
  result = newZosConnectionConfig(name, address, port, sshkey, isvbox)


proc getCurrentConnectionConfig(): ZosConnectionConfig =
  let tbl = loadConfig(configfile)
  let name = tbl.getSectionValue("app", "defaultzos")
  result = getConnectionConfigForInstance(name)

proc activeZosIsVbox(): bool = 
  return getCurrentConnectionConfig().isvbox == true

type App = object of RootObj
  currentconnectionConfig*:  ZosConnectionConfig

proc currentconnection*(this: App): Redis =
  result = open(this.currentconnectionConfig.address, this.currentconnectionConfig.port.Port, true)

proc setContainerKV(this:App, containerid:int, k, v: string) =
  let theKey = fmt"container:{containerid}:{k}"
  # echo fmt"Setting {theKey} to {v}"
  discard this.currentconnection().setk(theKey, v)

# proc deleteContainerKV(this:App, containerid:int, k:string) =
#   let theKey = (fmt"container:{containerid}:{k}")
#   discard this.currentconnection().del(theKey, [theKey])

proc getContainerKey(this: App, containerid:int, k:string): string =
  let theKey = fmt"container:{containerid}:{k}"
  # echo fmt"getting key {theKey}"
  result = $this.currentconnection().get(theKey)

proc existsContainerKey(this: App, containerid:int, k:string): bool =
  let theKey = fmt"container:{containerid}:{k}"
  result = this.currentconnection().exists(theKey) 


proc initApp(): App = 
  let currentconnectionConfig =  getCurrentConnectionConfig()
  result = App(currentconnectionConfig:currentconnectionConfig)

proc cmd*(this:App, command: string="core.ping", arguments="{}", timeout=5): string =
  result = this.currentconnection.zosCore(command, arguments, timeout, debug)
  debug(fmt"executing zero-os command: {command}\nresult:{result}")
  echo $result

proc exec*(this:App, command: string="hostname", timeout:int=5, debug=false): string =
  result = this.currentconnection.zosBash(command,timeout, debug)
  debug(fmt"executing shell command: {command}\nresult:{result}")
  echo $result

proc setdefault*(name="local", debug=false)=
  var tbl = loadConfig(configfile)
  if not tbl.hasKey(name):
    error(fmt"instance {name} isn't configured to be used as default")
    quit instanceNotConfigured
  tbl.setSectionKey("app", "defaultzos", name)
  tbl.setSectionKey("app", "debug", $debug)
  debug(fmt("changed defaultzos to {name}"))
  tbl.writeConfig(configfile)
  

proc configure*(name="local", address="127.0.0.1", port=4444, setdefault=false, vbox=false) =
  var tbl = loadConfig(configfile)
  debug(fmt("configured machine {name} on {address}:{port} isvbox:{vbox}"))
  tbl.setSectionKey(name, "address", address)
  tbl.setSectionKey(name, "port", $port)
  tbl.setSectionKey(name, "isvbox", $(vbox==true))

  tbl.writeConfig(configfile)
  if setdefault or not isConfigured():
    setdefault(name)
  
proc showconfig*() =
  echo readFile(configfile)

proc showDefaultConfig*() =
  let tbl = loadConfig(configfile)
  let activeZos = getActiveZosName()
  if tbl.hasKey(activeZos):
    echo tbl[activeZos]

proc showActive*() = 
  echo getActiveZosName()

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
    configure(name, "127.0.0.1", redisPort, setdefault=true,vbox=true)
  else:
    error(fmt"couldn't prepare zos machine {name} address:127.0.0.1 redisPort:{redisPort} isvbox: true")
  
# proc removeContainerFromConfig*(this:App, containerid:int) =
#   let activeZos = getActiveZosName()
#   var tbl = loadConfig(configfile)
#   let containerKey = fmt"container-{activeZos}-{containerid}"
#   if tbl.hasKey(containerKey):
#     tbl.del(containerKey)
#   tbl.writeConfig(configfile)

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


proc checkContainerExists(this:App, containerid:int): bool=
  try:
    discard this.containerInfo(containerid)
    result = true
  except:
    result = false

proc quitIfContainerDoesntExist(this: App, containerid:int) =
  if not this.checkContainerExists(containerid):
    error(fmt("container {containerid} doesn't exist."))
    quit containerDoesntExist

proc getContainerInfoList(this:App): seq[ContainerInfo] =
  result = newSeq[ContainerInfo]()
  let parsedJson = parseJson(this.containersInspect())
  if parsedJson.len > 0:
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
  
  if info.len == 0:
    info("machine doesn't have any active containers.")
  else:
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

# proc syncContainersIds(this: App) =
#   # updates the configfile with the still existing containers.
#   # less likely we will need to crossreference against the IPs to make sure
#   # if they're the same containers or the node was reinstalled?
#   let activeZos = getActiveZosName()
#   let conf = loadConfig(configfile)

#   var containersIds:seq[int] = @[]
#   for sectionKey, tbl in conf:
#     if sectionKey.startsWith(fmt"container-{activeZos}") == true:
#       containersIds.add(parseInt(sectionKey.split("-")[2]))
  
  # if containersIds.len == 0:
  #   error("you need to create containers using zos to use them implicitly")
  #   quit containerDoesntExist

  # let actualContainersInfo = this.getContainerInfoList()
  # var actualContainersIds: seq[int] = @[]
  # for c in actualContainersInfo:
  #   let cid = parseInt(c.id)
  #   actualContainersIds.add(cid)

  # for cid in containersIds:
  #   if not actualContainersIds.contains(cid):
  #     this.removeContainerFromConfig(cid)

proc getLastContainerId(this:App): int = 
  # TODO: should fail if the key doesn't exist
  let exists = this.currentconnection().exists("zos:lastcontainerid")
  if exists:
    result = ($this.currentconnection().get("zos:lastcontainerid")).parseInt()
  else:
    error("zos can only be used to manage containers created by it.")
    quit didntCreateZosContainersYet


proc getZerotierIp(this:App, containerid:int): string = 

  if this.existsContainerKey(containerid, "zerotierip") and ($this.getContainerKey(containerid, "zerotierip")).count(".") == 3:
    return this.getContainerKey(containerid, "zerotierip") 
  for trial in countup(0, 120):
    try:
      let ztsJson = zosCoreWithJsonNode(this.currentconnection, "corex.zerotier.list", %*{"container":containerid})
      let parsedZts = parseJson(ztsJson)
      if len(parsedZts)>0:
        let assignedAddresses = parsedZts[0]["assignedAddresses"].getElems()
        for el in assignedAddresses:
          var ip = el.getStr()
          if ip.count('.') == 3:
            # potential ip4
            if ip.contains("/"):
              ip = ip[0..<ip.find("/")]
            try:
              ip = $parseIpAddress(ip)
              this.setContainerKV(containerid, "zerotierip", ip)
              return ip
            except:
              sleep(1000)
    except:
      info("retrying to get connectivity information.")
      discard
    sleep(1000)
  error(fmt"couldn't get zerotier information for container {containerid}")
  quit cantGetZerotierInfo


proc getContainerIp(this:App, containerid: int): string = 
  let activeZos = getActiveZosName()
  let invbox = activeZosIsVbox()

  var done = false
  var ip = ""

  info("waiting for private network connectivity")

  if this.existsContainerKey(containerid, "ip") and ($this.getContainerKey(containerid, "ip")).count(".") == 3:
     return this.getContainerKey(containerid, "ip") 

  var hostIp = ""
  if invbox:
    hostIp = this.currentconnection().getZosHostOnlyInterfaceIp()
  else:
    hostIp = getCurrentConnectionConfig().address
  if hostIp != "":
    try:
      discard $parseIpAddress(hostIp)
      this.setContainerKV(containerid, "ip", hostIp)
      return hostIp
    except:
      error(fmt"couldn't get {containerid} host ip {hostIp}")
  else:
    error(fmt"couldn't get {containerid} host ip")
    quit noHostOnlyInterfaceIp


proc getContainerConfig(this:App, containerid:int): Table[string, string] = 
  let activeZos = getActiveZosName()
  
  var result = initTable[string, string]()
  result["port"] = $this.getContainerKey(containerid, "sshport")
  result["ip"] = $this.getContainerIp(containerid)

  return result

proc newContainer(this:App, name:string, root:string, hostname="", privileged=false, timeout=30, sshkey="", ports="", env=""):int =
  let activeZos = getActiveZosName()
  var containerHostName = hostname
  if containerHostName == "":
    containerHostName = name

  info(fmt"preparing container")

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
  if keys == "" or sshkey != "":
    # NO KEY IN AGENT
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

  extraArgs["config"]["/root/.ssh/authorized_keys"] = %*(keys)

  if extraArgs != nil:
    for k,v in extraArgs.pairs:
      args[k] = %*v

  let appconfig = getAppConfig() 
  let command = "corex.create"
  
  info(fmt"sending instructions to host")

  let containerid = this.currentconnection().zosCoreWithJsonNode(command, args, timeout, debug)
  try:
    result = parseInt(containerid)
    discard this.currentconnection.setk("zos:lastcontainerid", containerid)
  except:
    error(getCurrentExceptionMsg())
    error("couldn't create container")
    quit cantCreateContainer
  
  info(fmt"container {result} is created.")

  var containerSshport = 22
  args = %*{
    "number": 1
  }
  try:
    containerSshport = this.currentconnection().zosCoreWithJsonNode("socat.reserve", args).parseJson()[0].getInt()
  except:
    error(fmt"can't reserve port for container {result}")
    error(getCurrentExceptionMsg())
    quit cantReservePort

  var tbl = loadConfig(configfile)
  this.setContainerKV(result, "sshkey", configuredsshkey)
  this.setContainerKV(result, "layeredssh", "false")
  this.setContainerKV(result, "sshenabled", "false")
  this.setContainerKV(result, "sshport", $containerSshport)
  
  # now create portforward on zos host (sshport) to 22 on that container.
  args = %*{
    "port": containerSshport,
  }
  info(fmt"opening port {containerSshport}")
  discard this.currentconnection().zosCoreWithJsonNode("nft.open_port", args)
  args = %*{ 
    "container": parseInt(containerid),
    "host_port": $containerSshport,
    "container_port": 22
  }
  discard this.currentconnection().zosCoreWithJsonNode("corex.portforward-add", args)
  info(fmt"creating portforward from {containerSshport} to 22")


proc layerSSH(this:App, containerid:int, timeout=30) =
  let activeZos = getActiveZosName()
  #let sshflist = "https://hub.grid.tf/thabet/busyssh.flist"
  let sshflist = "https://hub.grid.tf/tf-bootable/ubuntu:18.04.flist"

  var tbl = loadConfig(configfile)

  let layeredssh = this.getContainerKey(containerid, "layeredssh") 

  if layeredssh == "false" or layeredssh.strip().len == 0:
    let parsedJson = parseJson(this.containerInspect(containerid))
    let id = $containerid
    let cpu = parsedJson["cpu"].getFloat()
    let root = parsedJson["container"]["arguments"]["root"].getStr()
    if root != sshflist:
      info("adding SSH support to your container")

      var args = %*{
        "container": containerid,
        "flist": sshflist
      }
      let command = "corex.flist-layer"
      discard this.currentconnection.zosCoreWithJsonNode(command, args, timeout, debug)
    info("SSH support enabled")
    this.setContainerKV(containerid, "layeredssh", "true")
  

proc stopContainer*(this:App, containerid:int, timeout=30) =
  let activeZos = getActiveZosName()
  let command = "corex.terminate"
  let arguments = %*{"container": containerid}
  discard this.currentconnection.zosCoreWithJsonNode(command, arguments, timeout, debug)


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
  let invbox = activeZosIsVbox()
  
  let configuredsshkey = $this.getContainerKey(containerid, "sshkey")
  let configuredsshport = $this.getContainerKey(containerid, "sshport")

  let sshport = parseInt(configuredsshport) 
  let contIp = this.getContainerIp(containerid)
  # echo "sshport: " & $sshport
  # echo "contip : " & contIp

  if not invbox:
    if configuredsshkey != "false":
      result = fmt"""root@{contIp} -p {sshport} -i {configuredsshkey}"""
    else:
      result = fmt"""root@{contIp} -p {sshport}"""
  else:
    if configuredsshkey != "false":
      result = fmt"""root@{contIp} -p {sshport} -i {configuredsshkey}"""
    else:
      result = fmt"""root@{contIp} -p {sshport} """


proc sshEnable*(this: App, containerid:int): string =
  let activeZos = getActiveZosName()
  this.layerSSH(containerid)

  discard this.getContainerIp(containerid)
  let sshenabled = this.getContainerKey(containerid, "sshenabled") 
  if sshenabled == "false" or sshenabled != "":
    # discard this.execContainer(containerid, "busybox mkdir -p /root/.ssh")
    # discard this.execContainer(containerid, "busybox chmod 700 -R /etc/ssh")

    # discard this.execContainer(containerid, "busybox mkdir -p /run/sshd")
    # discard this.execContainer(containerid, "/usr/sbin/sshd -D")
    # discard this.execContainer(containerid, "busybox --install")
    # discard this.execContainer(containerid, "mkdir -p /sbin")

    ## TODO: why zero-os can't resolve paths of binaries?
    # Specify the full path for now..
    discard this.execContainer(containerid, "/bin/mkdir -p /root/.ssh")
    discard this.execContainer(containerid, "/bin/chmod 700 -R /etc/ssh")

    this.setContainerKV(containerid, "sshenabled", "true")

  discard this.execContainerSilently(containerid, "service ssh start")
  discard this.execContainer(containerid, "service ssh status")
  # discard this.execContainer(containerid, "netstat -ntlp")

  result = this.sshInfo(containerid)


proc removeVmConfig*(this:App, name:string) = 
  debug(fmt"removing vm info {name}")
  let activeZos = getActiveZosName()
  var tbl = loadConfig(configfile)
  if tbl.hasKey(name):
    tbl.del(name)
  if activeZos == name:
    tbl["app"].del("defaultzos")
  tbl.writeConfig(configfile)

# proc authorizeContainer(this:App, containerid:int, sshkey=""): int = 
#   result = containerid
#   let activeZos = getActiveZosName()

#   var keys = ""
#   var configuredsshkey = ""
#   if sshkey == "":
#     keys = getAgentPublicKeys()
#   else:
    
#     let sshDirRelativeKey = getHomeDir() / ".ssh" / fmt"{sshkey}"
#     let sshDirRelativePubKey = getHomeDir() / ".ssh" / fmt"{sshkey}.pub"

#     let defaultSshKey = getHomeDir() / ".ssh" / fmt"id_rsa"
#     let defaultSshPubKey = getHomeDir() / ".ssh" / fmt"id_rsa.pub"
    
#     var k = ""
#     if fileExists(sshkey):
#       k = readFile(sshkey & ".pub")
#       configuredsshkey = sshkey
#     elif fileExists(sshDirRelativeKey):
#       configuredsshkey = sshDirRelativeKey
#       k = readFile(sshDirRelativePubKey)
#     elif fileExists(defaultSshKey):
#       configuredsshkey = defaultSshKey
#       k =  readFile(defaultSshPubKey)

#     keys &= k

#   if keys == "":
#     error("couldn't find sshkeys in agent or in default paths [generate one with ssh-keygen]")
#     quit cantFindSshKeys

#   discard this.exec("mkdir -p /mnt/containers/{containerid}/root/.ssh")
#   discard this.exec("mkdir -p /mnt/containers/{containerid}/var/run/sshd")
#   discard this.exec("touch /mnt/containers/{containerid}/root/.ssh/authorized_keys")

#   var args = %*{
#    "file": fmt"/mnt/containers/{containerid}/root/.ssh/authorized_keys",
#    "mode":"a"
#   }

#   var fd = this.currentconnection().zosCoreWithJsonNode("filesystem.open", args)
#   if fd.startsWith("\""):
#     fd = fd[1..^2]  # double quotes encoded
#   let content = base64.encode(keys)

#   args = %*{
#    "fd": fd,
#    "block": content
#   }

#   discard this.currentconnection().zosCoreWithJsonNode("filesystem.write", args)

#   this.setContainerKV(containerid, "sshkey", configuredsshkey)
#   this.setContainerKV(containerid, "layeredssh", "false")

#   discard this.getContainerIp(containerid)

#   echo $this.sshEnable(containerid)


proc handleUnconfigured(args:Table[string, Value]) =
  if args["init"]:
    if findExe("vboxmanage") == "":
      error("please make sure to have VirtualBox installed")
      quit vboxNotInstalled

    let name = $args["--name"]
    let disksize = parseInt($args["--disksize"])
    let memory = parseInt($args["--memory"])
    let redisport = parseInt($args["--redisport"])
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
    let activeZos = getActiveZosName()
    try:
      vmDelete(name)
      info(fmt"deleted vm {name}")
    except:
      discard # clear error here..
    app.removeVmConfig(name)
  
  proc handleForgetVm() = 
    let name = $args["--name"]
    app.removeVmConfig(name)
  
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
  
  proc handleShowActive() =
    showActive()

  proc handleShowActiveConfig() =
    showDefaultConfig()

  proc handlePing() =
    discard app.cmd("core.ping", "")

  proc handleCmd() =
    let command = $args["<zoscommand>"]
    let jsonargs = $args["--jsonargs"]
    # echo fmt"Dispatching {command} {jsonargs}"
    try:
      discard app.cmd(command, jsonargs)
    except:
      error(fmt"can't execute command {command}")
      error(getCurrentExceptionMsg())
      quit(cmdFailed)

  proc handleExec() = 
    let command = $args["<command>"]
    # echo fmt"Dispatching {command}"
    try:
      discard app.exec(command)
    except:
      error(fmt"can't execute command {command}")
      error(getCurrentExceptionMsg())
      quit(cmdFailed)

  proc handleContainersInspect() =
    echo app.containersInspect()
  
  proc handleContainerInspect() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    echo app.containerInspect(containerid)

  proc handleContainersInfo() =
    var showjson = false
    if args["--json"]:
      showjson = true
    echo app.containersInfo(showjson)
  
  proc handleContainerInfo() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    echo app.containerInfo(containerid)
   
  proc handleContainerDelete() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
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
    echo fmt"container private address: ", app.getContainerIp(containerId)

    if args["--ssh"]:
      discard app.sshEnable(containerId)

  # proc handleContainerAuthorize() =
  #   let containerid = parseInt($args["<id>"])
  #   var sshkey = ""
  #   if args["--sshkey"]:
  #     sshkey = $args["--sshkey"]
  #   echo $app.authorizeContainer(containerid, sshkey=sshkey)

  proc handleContainerZosExec() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    let command = $args["<command>"]
    discard app.execContainer(containerid, command)

  proc handleSshEnable() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    echo app.sshEnable(containerid)

  proc handleSshInfo() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    echo app.sshEnable(containerid)

  proc handleContainerShell() = 
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    let zosMachine = getActiveZosName()
    debug(fmt"sshing to container {containerid} on {zosMachine}")
    let sshcmd = "ssh -A " & app.sshEnable(containerid)
    debug(fmt("executing sshcmd {sshcmd}"))
    discard execCmd(sshcmd)


  proc handleContainerMount() = 
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    let srcPath = $args["<src>"]
    let destPath = $args["<dest>"]


    let (output, rc) = execCmdEx("mount")
    if destPath in output:
      error(fmt"{destPath} is already mounted. umount it using `umount {destPath}`")
      quit pathAlreadyMounted

    if not dirExists(destPath):
      debug(fmt("dest {destPath} doesn't exist and zos will create it"))
      createDir(destPath)

    let zosMachine = getActiveZosName()
    debug(fmt"sshing to container {containerid} on {zosMachine}")
    let containerConfig = app.getContainerConfig(containerid)
    let containerIp = containerConfig["ip"]
    let containerSshport = containerConfig["port"]

    let sshcmd = fmt"sshfs -p {containerSshport} root@{containerIp}:{srcPath} {destPath}"
    debug(fmt("sshfs command: {sshcmd}"))
    discard execCmd(sshcmd)

  proc handleContainerJumpscaleCommand() = 
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    var jscommand = args["<command>"]

    let sshcmd = "ssh " & app.sshEnable(containerid) & fmt""" 'js_shell "{args["<command>"]}" ' """
    debug(fmt"executing command: {sshcmd}")
    discard execCmd(sshcmd)

  
  proc handleContainerExec() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)

    let sshcmd = "ssh " & app.sshEnable(containerid) & fmt""" '{args["<command>"]}'"""
    debug(fmt("executing sshcmd {sshcmd}"))
    discard execCmd(sshcmd)

  proc handleContainerUpload() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    discard app.sshEnable(containerid) 

    let file = $args["<file>"]
    if not (fileExists(file) or dirExists(file)):
      error(fmt"file {file} doesn't exist")
      quit fileDoesntExist
    let dest = $args["<dest>"]
    let containerConfig = app.getContainerConfig(containerid)

    let sshDest = fmt"""root@{containerConfig["ip"]}:{dest}"""

    var isDir = false
    if dirExists(file):
      isDir=true
    let portFlag = fmt"""-P {containerConfig["port"]}"""
    let uploadCmd = rsyncUpload(file, sshDest, isDir, portFlag)
    debug(fmt"uploading files to container {uploadCmd}")
    discard execCmd(uploadCmd)
  
  proc handleContainerDownload() = 
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    discard app.sshEnable(containerid) 

    let file = $args["<file>"]
    let dest = $args["<dest>"]
    let containerConfig = app.getContainerConfig(containerid)

    let sshSrc = fmt"""root@{containerConfig["ip"]}:{file}"""
    var isDir = true # always true.
    let portFlag = fmt"""-P {containerConfig["port"]}"""
    let downloadCmd = rsyncDownload(sshSrc, dest, isDir, portFlag)
    discard execCmd(downloadCmd)
  
  proc handleContainerZerotierInfo() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    try:
      discard app.cmdContainer(containerid, "corex.zerotier.info")
    except:
      error(fmt"couldn't get zerotierinfo for container {containerid}")
      quit cantGetZerotierInfo
  
  proc handleContainerZerotierList() =
    var containerid = app.getLastContainerId()
    try:
      containerid = parseInt($args["<id>"])
    except:
      discard
    app.quitIfContainerDoesntExist(containerid)
    try:
      discard app.cmdContainer(containerid, "corex.zerotier.list")
    except:
      error(fmt"couldn't get zerotierinfo for container {containerid}")
      quit cantGetZerotierInfo

  if args["init"]:
    handleInit()
  elif args["remove"]:
    handleRemove()
  elif args["forgetvm"]:
    handleForgetVm()
  elif args["configure"]:
    handleConfigure()
  elif args["setdefault"]:
    handleSetDefault()
  elif args["showconfig"]:
    handleShowConfig()
  elif args["showactiveconfig"]:
    handleShowActiveConfig()
  elif args["showactive"]:
    handleShowActive()
  else: 
    # commands requires active zos connection.
    try:
      var con = app.currentconnection()
      con.timeout = 5000
      discard con.execCommand("PING", @[])
      con.timeout = 0
    except:
      echo(getCurrentExceptionMsg())
      let activeName = getActiveZosName()
      error(fmt"[-]can't reach zos instance <{activeName}> at {app.currentconnectionConfig.address}:{app.currentconnectionConfig.port}")
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
      handleContainerZerotierList()
    elif args["container"] and args["zerotierinfo"]:
      handleContainerZerotierInfo()
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
    elif args["container"] and args["mount"]:
      handleContainerMount()
    else:
      getHelp("")
      quit unknownCommand

const buildBranchName = staticExec("git rev-parse --abbrev-ref HEAD")
const buildCommit = staticExec("git rev-parse HEAD")
      

when isMainModule:
  proc checkArgs(args: Table[string, Value]) =
    # check
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
    
  let args = docopt(doc, version=fmt"zos 0.1.0 ({buildBranchName}#{buildCommit})")

  checkArgs(args)
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
