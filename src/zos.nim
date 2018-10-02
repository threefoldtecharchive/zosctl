import  redisclient, redisparser
import os, strutils, strformat, osproc, tables, uri
import uuid, json, tables, net, strformat, asyncdispatch, asyncnet, strutils, ospaths
import vboxpkg/vbox
import zosclientpkg/zosclient
import parsecfg
import typetraits



let configdir = ospaths.getConfigDir()
let configfile = configdir / "zos.toml"



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
  var port = 6379
  try:
    port = parseInt(parsed)
  except:
    echo fmt"Invalid port value: {parsed} will use default for now."
  result = newZosConnectionConfig(name, address, port)



proc getCurrentConnectionConfig(): ZosConnectionConfig =
  let tbl = loadConfig(configfile)
  let name = tbl.getSectionValue("app", "defaultzos")

  result = getConnectionConfigForInstance(name)


proc getCurrentAppConfig(): OrderedTableRef[string, string] =
  let tbl = loadConfig(configfile)
  result = tbl.getOrDefault("app")


let currentconnection = getCurrentConnectionConfig()
let appconfig = getCurrentAppConfig()


proc cmd*(command: string="core.ping", arguments="{}", timeout=5): string =
  result = zosCore(command, arguments, currentconnection.address, currentconnection.port, timeout, appconfig["debug"] == "true")
  echo $result


proc exec*(command: string="hostname", timeout:int=5, debug=false): string =
  return zosBash(command, currentconnection.address, currentconnection.port, timeout, appconfig["debug"] == "true")


proc configure*(name="local", address="127.0.0.1", port=4444, sshkey="", secret="") =
  var tbl = loadConfig(configfile)
  tbl.setSectionKey(name, "address", address)
  tbl.setSectionKey(name, "port", $port)
  tbl.setSectionKey(name, "secret", secret)
  var sshkeyfilename = ""
  let defaultsshfile = getHomeDir() / ".ssh" / "id_rsa" 


  # HARDEN FOR SSHKEY FILE VALIDATION..
  if sshkey == "":
    if existsFile(defaultsshfile):
      sshkeyfilename = defaultsshfile
  else:
    if existsFile(sshkey):
      sshkeyfilename = sshkey
    tbl.setSectionKey(name, "sshkey", sshkeyfilename)
  tbl.writeConfig(configfile)
  

proc setdefault*(name="local", debug=false)=
  var tbl = loadConfig(configfile)
  tbl.setSectionKey("app", "defaultzos", name)
  tbl.setSectionKey("app", "debug", $debug)
  tbl.writeConfig(configfile)


proc isConfigured*(): bool =
  let tbl = getCurrentAppConfig()
  return tbl["defaultzos"].len() != 0

  
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


proc listContainers() =
  let resp = parseJson(zosCoreWithJsonNode("corex.list", nil, currentconnection.address, currentconnection.port))
  echo resp.pretty(2)


proc newContainer(name="", root="", zosmachine="", hostname="", privileged=false, extraconfig="{}", timeout=30):int = 
  if name == "":
    echo "Please provide a container name"
    quit 2
  if root == "":
    echo "Please provide flist url https://hub.grid.tf/thabet/redis.flist"

  var connection: ZosConnectionConfig
  if zosmachine == appconfig["defaultzos"]:
    connection = currentconnection
  else:
    connection = getConnectionConfigForInstance(zosmachine)

  var containerHostName = hostname
  if containerHostName == "":
    containerHostName = name
  let currentconnection = getCurrentConnectionConfig()
  var args = %*{
    "name": name,
    "hostname": containerHostName,
    "root": root,
    "privileged": privileged,
  }

  var extraArgs: JsonNode
  extraArgs = parseJson(extraconfig)

  echo fmt"extraconfig: {extraconfig} {extraArgs}"
  echo extraArgs.type.name

  # FIXME NOW:
  if not extraArgs.hasKey("nics"):
    extraArgs["nics"] = %*{"type": "default"}

  if not extraArgs.hasKey("config"):
    echo "DOENST HAVE CONFIG KEY"
    extraArgs["config"] = newJObject()

  echo fmt"sshkeypath: {currentconnection.sshkey}"
  if not extraArgs["config"].hasKey("/root/.ssh/authorized_keys"):
    extraArgs["config"]["/root/.ssh/authorized_keys"] = %*(open(currentconnection.sshkey & ".pub", fmRead).readAll())

  if extraArgs != nil:
    for k,v in extraArgs.pairs:
      args[k] = %*v
  
  # args["config"]["authorized_keys"] = %*open(authorizedkeys, fmRead).readAll()

  echo fmt"args: {args}"
  let appconfig = getCurrentAppConfig()
  let command = "corex.create"
  echo fmt"new container: {command} {args}" 
  
  echo zosCoreWithJsonNode(command, args, currentconnection.address, currentconnection.port, timeout, appconfig["debug"] == "true")


proc stopContainer(id:int, timeout=30) =
  let command = "corex.terminate"
  let arguments = %*{"container": id}
  discard zosCoreWithJsonNode(command, arguments, currentconnection.address, currentconnection.port, timeout, appconfig["debug"] == "true")


proc execContainer*(containerid:int, command: string="hostname", timeout=5): string =
  result = containersCore(containerid, command, "", currentconnection.address, currentconnection.port, timeout, appconfig["debug"] == "true")
  echo $result


when isMainModule:
  if not fileExists(configfile):
    open(configfile, fmWrite).close()
  
  if findExe("vboxmanage") == "":
    echo "Please make sure to have VirtualBox installed"
    quit 1
  
  if not isConfigured():
    echo "Please run `zos configure` first"
    quit 2

  import docopt
  
  let doc = """
  
  Usage:
    zos init --name=<zosmachine> [--disksize=<disksize>] [--memory=<memorysize>] [--redisport=<redisport>]
    zos configure --name=<zosmachine> --address=<address> --port=<port> [--sshkey=<sshkeyname>] [--secret=<secret>]
    zos showconfig
    zos setdefault <zosmachine>
    zos cmd <zoscommand> [--jsonargs=<args>]
    zos exec <bashcommand> 
    zos container list
    zos container delete <containerid>
    zos container new --name=<container> --root=<rootflist> [--hostname=<hostname>] [--privileged] [--extraconfig=<extraconfig>] [--on=<zosmachine>]
    zos container <containerid> exec <command>
    zos container enablessh
    zos container shell
    zos --version

  
  Options:
    -h --help                       Show this screen.
    --version                       Show version.
    --on=<zosmachine>               Zero-OS machine instance name [default: local].
    --disksize=<disksize>           disk size [default: 1000]
    --memory=<memorysize>           memory size [default: 2048]
    --redisport=<redisport>         redis port [default: 4444]
    --sshkey=<sshkeyname>           sshkey name [default: id_rsa]
    --secret=<secret>               secret
    --privileged                    privileged container [default: false]
    --hostname=<hostname>           container hostname [default: ""]
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
  let args = docopt(doc, version="zos 0.1.0")
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
    # echo fmt"dispatching {name} {address} {port} {sshkeyname}"
    configure(name, address, port, sshkeyname, secret)
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
    echo fmt"Dispatching {command}"
    discard exec(command)
  elif args["list"]:
    # echo fmt"dispatch to list containers"
    listContainers()
  elif args["delete"]:
    let containerid = parseInt($args["<containerid>"])
    # echo fmt"dispatching to delete {containerid}"
    stopContainer(containerid)
  elif args["container"] and args["new"]:
    let containername = $args["--name"]
    let rootflist = $args["--root"]
    let hostname = $args["--hostname"]
    let zosmachine = $args["--on"]
    var privileged=false
    if args["--privileged"]:
      privileged=true
    let extraconfig = $args["--extraconfig"]
    echo fmt"dispatch creating {containername} on machine {zosmachine} {rootflist} {privileged} {extraconfig}"
    discard newContainer(containername, rootflist, zosmachine, hostname, privileged, extraconfig)
  elif args["container"] and args["exec"]:
    let containerid = parseInt($args["<containerid>"])
    let command = $args["<command>"]
    discard execContainer(containerid, command)
    # echo fmt"dispatch container exec {containerid} {command}"
  else:
    echo "Unsupported command"
  