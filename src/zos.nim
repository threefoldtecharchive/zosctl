import strutils, strformat, os, ospaths, osproc, tables, parsecfg, json, marshal, logging
import net, asyncdispatch, asyncnet, streams, threadpool, uri
import logging
import algorithm
import base64

import redisclient, redisparser
import docopt

import commons/logger
import commons/settings
import commons/apphelp
import commons/sshexec
import commons/errorcodes
import commons/hostnamegenerator
import commons/app
import vboxpkg/vbox
import zosclientpkg/zosclient


proc setdefault*(name="local")=
  ## Sets the default machine in zos to work against
  ## name is the name of the configured instance in zos
  var tbl = loadConfig(configFile)
  if not tbl.hasKey(name):
    error(fmt"instance {name} isn't configured to be used as default")
    quit instanceNotConfigured
  tbl.setSectionKey("app", "defaultzos", name)
  tbl.setSectionKey("app", "debug", $isDebug())
  debug(fmt("changed defaultzos to {name}"))
  tbl.writeConfig(configFile)
  

proc configure*(name="local", address="127.0.0.1", port=4444, setdefault=false, vbox=false) =
  ## configures an instance 
  ## name: instance name
  ## address: reachable IP for that instance
  ## port: redis port
  ## setdefault: make it the default instance
  ## vbox: virtualbox machine or not
  var tbl = loadConfig(configFile)
  debug(fmt("configured machine {name} on {address}:{port} isvbox:{vbox}"))
  tbl.setSectionKey(name, "address", address)
  tbl.setSectionKey(name, "port", $port)
  tbl.setSectionKey(name, "isvbox", $(vbox==true))

  tbl.writeConfig(configFile)
  if setdefault or not isConfigured():
    setdefault(name)
  
proc showconfig*() =
  ## Shows zos configurations located in ~/.config/zos.toml (in case of linux and mac osx)
  echo readFile(configFile)

proc showDefaultConfig*() =
  ## Shows the default configuration for the active zos
  let tbl = loadConfig(configFile)
  let activeZos = getActiveZosName()
  if tbl.hasKey(activeZos):
    echo tbl[activeZos]

proc showActive*() = 
  ## Shows the active machine name
  echo getActiveZosName()

proc init(name="local", datadiskSize=20, memory=4, redisPort=4444) = 
  ## Initialize virtualbox machine with zero-os 
  ## name: machine name (default is local)
  ## datadiskSize: disk size in GB (default is 20)
  ## redisPort: portforward for redis of the zero-os in virtualbox (default 4444)
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


proc newContainer(this:App, name:string, root:string, hostname="", privileged=false, timeout=30, sshkey="", ports="", env=""):int =
  ## Create new container 
  ## name: container name if not set it'll be autogenerated 
  ## root: flist the container is starting from
  ## hostname machine hostname
  ## privileged: if the container is privileged or not
  ## sshkey: 
  ##         if the key is set (name or path) will use the key
  ##         if agent is running will use the keys in the agent
  ##         otherwise fallback to id_rsa
  ## ports: mapping from host to container
  ##        e.g: "2200:22" means forward port 2200 on the host to 22 on the container
  ##        e.g: "2200:22,3300:33" means forward port 2200 on the host to 22 on the container and 3300 on the host to 33 on the container 
  ## env:   mapping of environment variables while spawning the container
  ##        e.g: "TOK:asdasdasdas,PATH=/usr/local/bin"
  ## 
  ## Returns newely created container id
  ##
  ## Note: we use socat.reserve from zero-os to get a random port to allow ssh for the container using the zero-os machine ip
  ##
  ##

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

  let containerid = this.currentconnection().zosCoreWithJsonNode(command, args, timeout)
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

  var tbl = loadConfig(configFile)
  this.setContainerKV(result, "sshkey", configuredsshkey)
  this.setContainerKV(result, "layeredssh", "false")
  this.setContainerKV(result, "sshenabled", "false")
  this.setContainerKV(result, "sshport", $containerSshport)

  # now create portforward on zos host (sshport) to 22 on that container. no need to force nft.open_port

  args = %*{ 
    "container": parseInt(containerid),
    "host_port": $containerSshport,
    "container_port": 22
  }
  discard this.currentconnection().zosCoreWithJsonNode("corex.portforward-add", args)
  info(fmt"creating portforward from {containerSshport} to 22")


proc handleUnconfigured(args:Table[string, Value]) =
  ## Handle the case of unconfigured `zos`
  ## responsible for init, configure, setdefault commands
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
  ## handle commands of configured zos
  ## all of the available commands
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
            debug("vm delete error: " & getCurrentExceptionMsg())
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
      debug("vm delete error: " & getCurrentExceptionMsg())
    removeVmConfig(name)
  
  proc handleForgetVm() = 
    let name = $args["--name"]
    removeVmConfig(name)
  
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
      if existsEnv("ZOS_JWT"):
        # info("Authenticating to secure ZOS.")
        let res = $con.execCommand("AUTH", getEnv("ZOS_JWT"))
        if not res.contains("OK"):
          echo res
          quit invalidJwt

      let res = $con.execCommand("PING", @[])
      if not res.contains("PONG"):
        error(fmt"[-]can't ping zos. if running in secure mode make sure ZOS_JWT is set correctly.")
        quit cantPingZos
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

when isMainModule:
  let args = docopt(doc, version=fmt"zos {latestTag} ({buildBranchName}#{buildCommit})")
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
