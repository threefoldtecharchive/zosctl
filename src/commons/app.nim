import strutils, strformat, os, ospaths, osproc, tables, parsecfg, json, marshal, logging
import net, asyncdispatch, asyncnet, streams, threadpool, uri
import logging
import algorithm
import base64

import redisclient, redisparser
import asciitables
import docopt
#import spinny, colorize

import ./logger
import ./settings
import ./apphelp
import ./sshexec
import ./errorcodes
import ./hostnamegenerator

# import vboxpkg/vbox
import ../zosclientpkg/zosclient




type App* = object of RootObj
  ## App type represents zos application 
  ## currentconnectionConfig the redis connection information (address and port.)
  currentconnectionConfig*:  ZosConnectionConfig

proc currentconnection*(this: App): Redis =
  ## Gets the current connection to the active zos machine.
  result = open(this.currentconnectionConfig.address, this.currentconnectionConfig.port.Port, true)

proc setContainerKV*(this:App, containerid:int, k, v: string) =
  ## Set containerid related key `k` to value `v`
  let theKey = fmt"container:{containerid}:{k}"
  discard this.currentconnection().setk(theKey, v)

# proc deleteContainerKV(this:App, containerid:int, k:string) =
#   let theKey = (fmt"container:{containerid}:{k}")
#   discard this.currentconnection().del(theKey, [theKey])

proc getContainerKey*(this: App, containerid:int, k:string): string =
  ## Get containerid related key `k`
  let theKey = fmt"container:{containerid}:{k}"
  # echo fmt"getting key {theKey}"
  result = $this.currentconnection().get(theKey)

proc existsContainerKey*(this: App, containerid:int, k:string): bool =
  ## Check if key `k` exists related to container with id `containerid`
  let theKey = fmt"container:{containerid}:{k}"
  result = this.currentconnection().exists(theKey) 


proc initApp*(): App = 
  ## Initialize Application 
  ## Returns App object
  let currentconnectionConfig =  getCurrentConnectionConfig()
  result = App(currentconnectionConfig:currentconnectionConfig)


proc cmd*(this:App, command: string="core.ping", arguments="{}", timeout=5): string =
  ## Execute command `command` with json serialized arguments `arguments`
  ## command: any valid zero-os command (default core.ping)
  ## arguments: serialized json string
  result = this.currentconnection.zosCore(command, arguments, timeout)
  debug(fmt"executing zero-os command: {command}\nresult:{result}")
  echo $result

proc exec*(this:App, command: string="hostname", timeout:int=5): string =
  ## Execute command `command` in shell in zero-os
  ## command: any valid shell command (default is hostname)
  result = this.currentconnection.zosBash(command,timeout)
  debug(fmt"executing shell command: {command}\nresult:{result}")
  echo $result

proc containersInspect*(this:App): string=
  ## Inspects the containers in the active zero-os machine
  ## returns json result of all containers info
  let resp = parseJson(this.currentconnection.zosCoreWithJsonNode("corex.list", nil))
  result = resp.pretty(2)

proc containerInspect*(this:App, containerid:int): string =
  ## Inspects the container `containerid` in the active zero-os machine
  ## returns json result of `containerid` info
  let resp = parseJson(this.currentconnection.zosCoreWithJsonNode("corex.list", nil))
  if not resp.hasKey($containerid):
    error(fmt"container {containerid} not found.")
    quit containerNotFound
  else:
    result = resp[$containerid].pretty(2) 

type ContainerInfo* = object of RootObj
  ## Type representing container info
  ## id: container id
  ## CPU: cpu utilization
  ## root: flist the container is started from
  ## hostname: container hostname
  ## name: container name
  ## storage: storage the flist is loaded from (the hub)
  ## pid: container process id
  ## ports: forwarded ports from the host to the container
  id*: string
  cpu*: float
  root*: string
  hostname*: string
  name*: string
  storage*: string
  pid*: int
  ports*: string


proc containerInfo*(this:App, containerid:int): string =
  ## returns the container `containerid` info in the active zero-os machine as json.
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


proc checkContainerExists*(this:App, containerid:int): bool=
  ## checks if container `containerid` exists or not
  try:
    discard this.containerInfo(containerid)
    result = true
  except:
    result = false

proc quitIfContainerDoesntExist*(this: App, containerid:int) =
  ## quits with `containerDoesntExist` error if container doesn't exist
  if not this.checkContainerExists(containerid):
    error(fmt("container {containerid} doesn't exist."))
    quit containerDoesntExist

proc getContainerInfoList*(this:App): seq[ContainerInfo] =
  ## Get container info list 
  ## Returns a sequence of ContainerInfo objects
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
  
proc containersInfo*(this:App, showjson=false): string =
  ## Gets all the container info
  ## showjson: returns a json string if true
  ##           otherwise with return an ascii table.

  let info = this.getContainerInfoList()
  
  if info.len == 0:
    info("machine doesn't have any active containers.")
  else:
    if showjson == true:
      result = parseJson($$(info)).pretty(2)
    else:
      var t = newAsciiTable()
      t.separateRows = false
      t.setHeaders(@["ID", "Name", "Ports", "Root"])

      for k, v in info:
        let nroot = replace(v.root, "https://hub.grid.tf/", "").strip()
        t.addRow(@[$v.id, v.name, v.ports, nroot])
      result = t.render()

proc getLastContainerId*(this:App): int = 
  ## Gets the alst active container zos knows about
  ## the last container id is stored in zero-os redis with key `zos:lastcontainerid`
  ## if `zos:lastcontainerid` isn't set zos will quit with `didntCreateZosContainersYet` error.
  let exists = this.currentconnection().exists("zos:lastcontainerid")
  if exists:
    result = ($this.currentconnection().get("zos:lastcontainerid")).parseInt()
  else:
    error("zos can only be used to manage containers created by it.")
    quit didntCreateZosContainersYet


proc getZerotierIp*(this:App, containerid:int): string = 
  ## Get the zerotier ip for container `containerid`
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


proc getContainerIp*(this:App, containerid: int): string = 
  ## Get the IP of container `containerid`
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

proc getContainerConfig*(this:App, containerid:int): Table[string, string] = 
  ## Gets a table of container info (port and IP)
  let activeZos = getActiveZosName()
  
  var result = initTable[string, string]()
  result["port"] = $this.getContainerKey(containerid, "sshport")
  result["ip"] = $this.getContainerIp(containerid)

  return result

proc layerSSH*(this:App, containerid:int, timeout=30) =
  ## Layers ssh supported flist on top of the current image if it doesn't support ssh service.
  let activeZos = getActiveZosName()
  #let sshflist = "https://hub.grid.tf/thabet/busyssh.flist"
  let sshflist = "https://hub.grid.tf/tf-bootable/ubuntu:18.04.flist"

  var tbl = loadConfig(configFile)

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
      discard this.currentconnection.zosCoreWithJsonNode(command, args, timeout)
    info("SSH support enabled")
    this.setContainerKV(containerid, "layeredssh", "true")
  

proc stopContainer*(this:App, containerid:int, timeout=30) =
  ## Stops the container `containerid`
  let activeZos = getActiveZosName()
  let command = "corex.terminate"
  let arguments = %*{"container": containerid}
  discard this.currentconnection.zosCoreWithJsonNode(command, arguments, timeout)

  
proc execContainer*(this:App, containerid:int, command: string="hostname", timeout=5): string =
  ## Execute command `command` on container with id `containerid`
  ## And echos the result
  result = this.currentconnection.containersCore(containerid, command, "", timeout)
  echo $result
  
proc execContainerSilently*(this:App, containerid:int, command: string="hostname", timeout=5): string =
  ## Executes command `command` on container with id `containerid` 
  result = this.currentconnection.containersCore(containerid, command, "", timeout)

proc cmdContainer*(this:App, containerid:int, command: string, timeout=5): string =
  result = this.currentconnection.zosContainerCmd(containerid, command, timeout)
  echo $result  

  
proc sshInfo*(this:App, containerid: int): string = 
  ## Gets sshinfo (ip, sshport, key used) to connect to container `containerid`
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
  ## Enables ssh service on container `containerid`
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

