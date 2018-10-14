import strutils, strformat, os, ospaths, osproc, tables, uri, parsecfg, json, marshal
import net, asyncdispatch, asyncnet, streams
import logging
import algorithm
import redisclient, redisparser, docopt
import vboxpkg/vbox
import zosclientpkg/zosclient
import zosapp/settings
import zosapp/apphelp
import zosapp/sshexec


var L = newConsoleLogger()
var fL = newFileLogger("zos.log", fmtStr = verboseFmtStr)
addHandler(L)
addHandler(fL)

# """
# errorCodes
# 1: can't create configdir
# 2: sshkey not found
# 3: container not found
# 4: vbox not found
# 5: unconfigured zos
# 6: unknown command
# """

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


var zerotierId: string
if os.existsEnv("GRID_ZEROTIER_ID_TESTING"):
  zerotierId = os.getEnv("GRID_ZEROTIER_ID_TESTING")    
  info(fmt"using special zerotier network {zerotierId}")
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
    warn("Invalid port value: {parsed} will use default for now.")
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
      error("SSH Key not found: {keypath}")
      quit 2
  else:
    if not existsFile(defaultsshfile):
      error(fmt"SSH Key not found: {keypath}")
      quit  2

  keypath = defaultsshfile
  tbl.setSectionKey(name, "sshkey", keypath)
  tbl.writeConfig(configfile)
  if setdefault or not isConfigured():
    setdefault(name)
  

proc showconfig*() =
  echo readFile(configfile)

proc init(name="local", datadiskSize=20, memory=4, redisPort=4444) = 
  # TODO: add cores parameter.
  let isopath = downloadZOSIso()
  try:
    newVM(name, "/tmp/zos.iso", datadiskSize*1024, memory*1024, redisPort)
  except:
    error(getCurrentExceptionMsg())
  info(fmt"Created machine {name}")

  var args = ""

  when defined linux:
    if not existsEnv("DISPLAY"):
      args = "--type headless"
  configure(name, "127.0.0.1", redisPort, setdefault=true)
  let cmd = fmt"""startvm {args} "{name}" &"""
  discard executeVBoxManage(cmd)
  info(fmt"Started VM {name}")
  
  # give it 10 mins
  var trials = 0
  while trials != 120:
    try:
      let con = open("127.0.0.1", redisPort.Port, true)
    except:
      info("still pending to have a connection to zos")
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
    error(fmt"container {containerid} not found.")
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


proc getContainerInfoList(): seq[ContainerInfo] =
  result = newSeq[ContainerInfo]()
  let parsedJson = parseJson(containersInspect())
  for k,v in parsedJson.pairs:
    let id = k
    let cpu = parsedJson[k]["cpu"].getFloat()
    let root = parsedJson[k]["container"]["arguments"]["root"].getStr()
    let hostname = parsedJson[k]["container"]["arguments"]["hostname"].getStr()
    let pid = parsedJson[k]["container"]["pid"].getInt()
    result.add(ContainerInfo(id:id, cpu:cpu, root:root, hostname:hostname, pid:pid))
    result = result.sortedByIt(parseInt(it.id))
  
proc containersInfo(): string =
  let info = getContainerInfoList()
  result = parseJson($$(info)).pretty(2)


proc getLastContainerId(): string = 
  let info = getContainerInfoList()
  result = info[^1].id


proc newContainer(name:string, root:string, zosmachine="", hostname="", privileged=false, timeout=30):int = 
  let currentconnectionConfig = getCurrentConnectionConfig()
  if name == "":
    error("Please provide a container name")
    quit 3
  if root == "":
    error("Please provide flist url https://hub.grid.tf/thabet/redis.flist")
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
  
  let appconfig = getAppConfig()
  let command = "corex.create"
  info(fmt"new container: {command} {args}") 
  
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

      tbl.setSectionKey(fmt("container-{containerid}"), "ip", ip)
      tbl.writeConfig(configfile)

      result = fmt"ssh root@{ip}"
      info(result)
      break

when isMainModule:
  let args = docopt(doc, version="zos 0.1.0")

  if not isConfigured():
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
      let sshkeyname = $args["--sshkey"]
      if args["--setdefault"]:
        configure(name, address, port, sshkeyname, true) 
      else:
        configure(name, address, port, sshkeyname) 
    elif args["setdefault"]:
      let name = $args["<zosmachine>"]
      setdefault(name)

  else:
    let currentconnectionConfig = getCurrentConnectionConfig()
 
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
      let command = $args["<command>"]
      # echo fmt"Dispatching {command}"
      discard exec(command)
    elif args["--ssh"] and not args["container"]:
      let command = $args["<command>"]
      let sshstring = fmt"ssh root@{currentconnectionConfig.address} '{command}'"
      discard execCmd(sshstring)
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
      var zosmachine = getAppConfig()["defaultzos"]
      if args["--on"]:
        zosmachine = $args["<zosmachine>"]
      var privileged=false
      if args["--privileged"]:
        privileged=true
      echo fmt"dispatch creating {containername} on machine {zosmachine} {rootflist} {privileged}"
      discard newContainer(containername, rootflist, zosmachine, hostname, privileged)
      if args["--ssh"]:
        discard sshEnable(parseInt(getLastContainerId()))
    elif args["container"] and args["zosexec"]:
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
      echo sshEnable(containerid)
    elif args["container"] and args["sshinfo"]:
      let containerid = parseInt($args["<id>"])
      echo sshEnable(containerid)
    elif args["container"] and args["shell"]:
      var containerid = parseInt(getLastContainerId())
      try:
        containerid = parseInt($args["<id>"])
      except:
        discard
      let sshcmd = sshEnable(containerid, true)
      discard sshExec(sshcmd)
    elif args["container"] and args["exec"]:
      var containerid = parseInt(getLastContainerId())
      try:
        containerid = parseInt($args["<id>"])
      except:
        discard
      let sshcmd = sshEnable(containerid, false) & fmt""" '{args["<command>"]}'"""
      discard execCmd(sshcmd)
      # discard sshExec(sshcmd)
    else:
      getHelp("")
      quit 6
  
