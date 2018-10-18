import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal
import net, asyncdispatch, asyncnet, streams, threadpool
import logging
import algorithm
import redisclient, redisparser, docopt
#import spinny, colorize

import vboxpkg/vbox
import zosclientpkg/zosclient
import zosapp/settings
import zosapp/apphelp
import zosapp/sshexec





# """
# errorCodes
# 1: can't create configdir
# 2: sshkey not found
# 3: container not found
# 4: vbox not found
# 5: unconfigured zos
# 6: unknown command
# 7: ssh tools not installed
# """


var L* = newConsoleLogger()
var fL* = newFileLogger("zos.log", fmtStr = verboseFmtStr)
addHandler(L)
addHandler(fL)

let sshtools = @["ssh", "scp"]

proc sshBinsCheck() = 
  for b in sshtools:
    if findExe(b) == "":
      error("ssh tools aren't installed")
      quit 7


proc prepareConfig() = 
  try:
    createDir(configdir)
  except:
    error(fmt"couldn't create {configdir}")
    quit 1

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
  currentconnection*: Redis 
  currentconnectionConfig*:  ZosConnectionConfig

proc currentconnection(this: App): Redis =
  result = open(this.currentconnectionConfig.address, this.currentconnectionConfig.port.Port, true)

proc initApp(): App = 
  let currentconnectionConfig =  getCurrentConnectionConfig()
  result = App(currentconnectionConfig:currentconnectionConfig)

proc cmd*(this:App, command: string="core.ping", arguments="{}", timeout=5): string =
  result = this.currentconnection.zosCore(command, arguments, timeout, appconfig["debug"] == "true")
  echo $result

proc exec*(this:App, command: string="hostname", timeout:int=5, debug=false): string =
  result = this.currentconnection.zosBash(command,timeout, appconfig["debug"] == "true")
  echo $result


proc setdefault*(name="local", debug=false)=
  var tbl = loadConfig(configfile)
  tbl.setSectionKey("app", "defaultzos", name)
  tbl.setSectionKey("app", "debug", $debug)
  tbl.writeConfig(configfile)
  

proc configure*(name="local", address="127.0.0.1", port=4444, setdefault=false) =
  var tbl = loadConfig(configfile)
  tbl.setSectionKey(name, "address", address)
  tbl.setSectionKey(name, "port", $port)
  let defaultsshfile = getHomeDir() / ".ssh" / "id_rsa" 
  var keypath= ""

  tbl.writeConfig(configfile)
  if setdefault or not isConfigured():
    setdefault(name)
  
proc showconfig*() =
  echo readFile(configfile)

proc init(name="local", datadiskSize=20, memory=4, redisPort=4444, ) = 
  # TODO: add cores parameter.
  let isopath = downloadZOSIso()
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
      let con = open("127.0.0.1", redisPort.Port, true)
      echo $con.execCommand("PING", @[])
      ponged = true
      break
    except:
      sleep(5000)

  if ponged:
    configure(name, "127.0.0.1", redisPort, setdefault=true)
    info("created zos machine and we are ready.")
  else:
    error("couldn't prepare zos machine.")
  



  # configure and make that machine the default

proc containersInspect(this:App): string=
  let resp = parseJson(this.currentconnection.zosCoreWithJsonNode("corex.list", nil))
  result = resp.pretty(2)

proc containerInspect(this:App, containerid:int): string =
  let resp = parseJson(this.currentconnection.zosCoreWithJsonNode("corex.list", nil))
  if not resp.hasKey($containerid):
    error(fmt"container {containerid} not found.")
    quit 3
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


proc containerInfo(this:App, containerid:int): string =
  let parsedJson = parseJson(this.containerInspect(containerid))
  let id = $containerid
  let cpu = parsedJson["cpu"].getFloat()
  let root = parsedJson["container"]["arguments"]["root"].getStr()
  let name = parsedJson["container"]["arguments"]["hostname"].getStr()
  let hostname = parsedJson["container"]["arguments"]["hostname"].getStr()
  let pid = parsedJson["container"]["pid"].getInt()
  let cont = ContainerInfo(id:id, cpu:cpu, root:root, hostname:hostname, pid:pid)
  result = parseJson($$(cont)).pretty(2)


proc getContainerInfoList(this:App): seq[ContainerInfo] =
  result = newSeq[ContainerInfo]()
  let parsedJson = parseJson(this.containersInspect())
  for k,v in parsedJson.pairs:
    let id = k
    let cpu = parsedJson[k]["cpu"].getFloat()
    let root = parsedJson[k]["container"]["arguments"]["root"].getStr()
    let name = parsedJson[k]["container"]["arguments"]["hostname"].getStr()
    let hostname = parsedJson[k]["container"]["arguments"]["hostname"].getStr()
    let storage = parsedJson[k]["container"]["arguments"]["storage"].getStr()
    let pid = parsedJson[k]["container"]["pid"].getInt()
    result.add(ContainerInfo(id:id, cpu:cpu, root:root, name:name, hostname:hostname, storage:storage, pid:pid))

  result = result.sortedByIt(parseInt(it.id))
  
proc containersInfo(this:App): string =
  let info = this.getContainerInfoList()
  result = parseJson($$(info)).pretty(2)

proc getLastContainerId(this:App): int = 
  let conf = loadConfig(configfile)

  var containersIds:seq[int] = @[]
  for sectionKey, tbl in conf:
    if sectionKey.startsWith("container"):
      containersIds.add(parseInt(sectionKey.split("-")[2]))
  
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
  for trial in countup(0, 30):
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
            sleep(2000)
    except:
      sleep(2000)
  
  error(fmt"couldn't get zerotier information for container {containerid}")

  
proc newContainer(this:App, name:string, root:string, hostname="", privileged=false, timeout=30, sshkey=""):int = 
  let activeZos = getActiveZosName()
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
    quit 8

  # if not extraArgs["config"].hasKey("/root/.ssh/authorized_keys"):
  extraArgs["config"]["/root/.ssh/authorized_keys"] = %*(keys)

  if extraArgs != nil:
    for k,v in extraArgs.pairs:
      args[k] = %*v

  let appconfig = getAppConfig() 
  let command = "corex.create"
  info(fmt"new container: {command} {args}") 
  
  let contId = this.currentconnection.zosCoreWithJsonNode(command, args, timeout, appconfig["debug"] == "true")
  result = parseInt(contId)
  
  var tbl = loadConfig(configfile)
  tbl.setSectionKey(fmt"container-{activeZos}-{result}", "sshkey", configuredsshkey)
  tbl.setSectionKey(fmt"container-{activeZos}-{result}", "layeredssh", "false")
  tbl.writeConfig(configfile)

  echo result


proc layerSSH(this:App, containerid:int, timeout=30) =
  let activeZos = getActiveZosName()
  let sshflist = "https://hub.grid.tf/thabet/busyssh.flist"

  var tbl = loadConfig(configfile)
  info("layering sshflist on container")

  let containerName = this.getContainerNameById(containerid)
  let containerKey = fmt"container-{activeZos}-{containerid}" 
  if tbl[containerKey]["layeredssh"] == "false":
    var args = %*{
      "container": containerid,
      "flist": sshflist
    }
    let command = "corex.flist-layer"
    info("layering sshflist on container")
    discard this.currentconnection.zosCoreWithJsonNode(command, args, timeout, appconfig["debug"] == "true")
  
  else:
    tbl[containerKey]["layeredssh"] = "true"
    tbl.writeConfig(configfile)


proc stopContainer*(this:App, containerid:int, timeout=30) =
  let activeZos = getActiveZosName()
  let containerName = this.getContainerNameById(containerid)
  let command = "corex.terminate"
  let arguments = %*{"container": containerid}
  discard this.currentconnection.zosCoreWithJsonNode(command, arguments, timeout, appconfig["debug"] == "true")

  var tbl = loadConfig(configfile)
  let containerKey = fmt"container-{activeZos}-{containerid}"
  if tbl.hasKey(containerKey):
    tbl.del(containerKey)
  tbl.writeConfig(configfile)

proc execContainer*(this:App, containerid:int, command: string="hostname", timeout=5): string =
  result = this.currentconnection.containersCore(containerid, command, "", timeout, appconfig["debug"] == "true")
  echo $result

proc cmdContainer*(this:App, containerid:int, command: string, timeout=5): string =
  result = this.currentconnection.zosContainerCmd(containerid, command, timeout, appconfig["debug"] == "true")
  
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
  # this.layerSSH(containerid)

  var tbl = loadConfig(configfile)
  if tbl[fmt("container-{activeZos}-{containerid}")].getOrDefault("sshenabled", "false") == "false":
    # discard this.execContainer(containerid, "busybox mkdir -p /root/.ssh")
    # discard this.execContainer(containerid, "busybox chmod 700 -R /etc/ssh")

    # discard this.execContainer(containerid, "busybox mkdir -p /run/sshd")
    # discard this.execContainer(containerid, "/usr/sbin/sshd -D")

    discard this.execContainer(containerid, "mkdir -p /root/.ssh")
    discard this.execContainer(containerid, "chmod 700 -R /etc/ssh")
    discard this.execContainer(containerid, "service ssh start")

    tbl.setSectionKey(fmt("container-{activeZos}-{containerid}"), "sshenabled", "true")
    tbl.writeConfig(configfile)

  result = this.sshInfo(containerid)


proc handleUnconfigured(args:Table[string, Value]) =
  if args["init"]:
    if findExe("vboxmanage") == "":
      error("Please make sure to have VirtualBox installed")
      quit 4 

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

  var app = initApp()

  proc handleInit() = 
    var app = initApp()

    let name = $args["--name"]
    let disksize = parseInt($args["--disksize"])
    let memory = parseInt($args["--memory"])
    let redisport = parseInt($args["--redisport"])
    var reset = false
    if args["--reset"]:
      reset = true
    # echo fmt"dispatching {name} {disksize} {memory} {redisport}"
    if reset == true:
      vmDelete(name)
    init(name, disksize, memory, redisport)
  
  proc handleRemove() = 
    var app = initApp()

    let name = $args["--name"]
    vmDelete(name)
  
  proc handleConfigure() =
    var app = initApp()

    let name = $args["--name"]
    let address = $args["--address"]
    let port = parseInt($args["--port"])
    let sshkeyname = $args["--sshkey"]
    if args["--setdefault"]:
      configure(name, address, port, true) 
    else:
      configure(name, address, port) 

  proc handleSetDefault() =
    var app = initApp()

    let name = $args["<zosmachine>"]
    setdefault(name)

  proc handleShowConfig() = 
    var app = initApp()

    showconfig()

  proc handlePing() =
    var app = initApp()
    discard app.cmd("core.ping", "")

  proc handleCmd() =
    var app = initApp()

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
    echo app.containersInfo()
  
  proc handleContainerInfo() =
    let containerid = parseInt($args["<id>"])
    echo app.containerInfo(containerid)
   

  proc handleContainerDelete() =
    let containerid = parseInt($args["<id>"])
    # echo fmt"dispatching to delete {containerid}"
    app.stopContainer(containerid)

  proc handleContainerNew() =
    let containername = $args["--name"]
    let rootflist = $args["--root"]
    var hostname = containername 
    if args["--hostname"]:
      hostname = $args["<hostname>"]
    var privileged=false
    if args["--privileged"]:
      privileged=true
    var sshkey = ""
    if args["--sshkey"]:
      sshkey = $args["--sshkey"]
    echo fmt"dispatch creating {containername} on machine {rootflist} {privileged}"
    let containerId = app.newContainer(containername, rootflist, hostname, privileged, sshkey=sshkey)
    echo app.getContainerIp(containerid)
    if args["--ssh"]:
      discard app.sshEnable(app.getLastContainerId())


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
    let sshcmd = "ssh " & app.sshEnable(containerid)
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
      quit 9 
    let file = $args["<file>"]
    if not fileExists(file):
      error(fmt"file {file} doesn't exist")
      quit 7
    let dest = $args["<dest>"]
    let containerConfig = app.getContainerConfig(containerid)
    discard app.sshEnable(containerid) 

    let sshDest = fmt"""root@{containerConfig["ip"]}:{dest}"""

    var isDir = false
    if getFileInfo(file).kind == pcDir:
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
      quit 9
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
  elif args["ping"]:
    handlePing()
  elif args["cmd"]:
    handleCmd()
    ### more... 
  elif args["exec"] and not args["container"]:
    handleExec()
  
  # elif args["--ssh"] and not args["container"]:
  #   let command = $args["<command>"]
  #   let sshstring = fmt"ssh root@{currentconnectionConfig.address} '{command}'"
  #   discard execCmd(sshstring)
  elif args["inspect"] and args["<id>"]:
    handleContainerInspect()
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
  else:
    getHelp("")
    quit 6





when isMainModule:
  let args = docopt(doc, version="zos 0.1.0")
  if args["help"] and args["<cmdname>"]:
    getHelp($args["<cmdname>"])
    quit 0
  if args["help"]:
    getHelp("")
    quit 0
  
    
  if not isConfigured():
    handleUnconfigured(args)
  else:
    handleConfigured(args)
 