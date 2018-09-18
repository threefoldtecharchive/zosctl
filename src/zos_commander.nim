import  redisclient, redisparser
import os, strutils, strformat, osproc, tables, uri
import uuid, json, tables, net, strformat, asyncdispatch, asyncnet, strutils, ospaths


proc flagifyId(id: string): string =
  result = fmt"result:{id}:flag" 

proc resultifyId(id: string): string = 
  result = fmt"result:{id}" 

proc newUUID(): string = 
  var cmduid: Tuuid
  uuid_generate_random(cmduid)
  result = cmduid.to_hex

proc getResponseString*(id: string, con: Redis|AsyncRedis, timeout=10): Future[string] {.multisync.} = 
  let exists = $(await con.execCommand("EXISTS", @[flagifyId(id)]))
  if exists == "1":
    let reskey = resultifyId(id)
    result = $(await con.execCommand("BRPOPLPUSH", @[reskey, reskey, $timeout]))


proc zosSend(payload: JsonNode, bash=false, host="localhost", port=4444, timeout=5, debug=false): string =
  let cmdid = payload["id"].getStr()

  if debug == true:
    echo "payload" & $payload
  
  let con = open(host, port.Port, true)
  let flag = flagifyId(cmdid)
  let reskey = resultifyId(cmdid) 

  var cmdres: RedisValue
  cmdres = con.execCommand("RPUSH", @["core:default", $payload])
  if debug:
    echo $cmdres
  cmdres = con.execCommand("BRPOPLPUSH", @[flag, flag, $timeout])
  if debug:
    echo $cmdres

  let parsed = parseJson(getResponseString(cmdid, con))
  let response_state = $parsed["state"].getStr()
  if response_state != "SUCCESS":
    echo "FAILED TO EXECUTE"
    echo $parsed
    quit 1
  else:
    if bash == true:
      if parsed["code"].getInt() == 0:
        echo parsed["streams"][0].getStr() # stdout
      else:
        echo parsed["streams"][1].getStr() # stderr
    else:
      echo parsed["data"].getStr()
    
  return $parsed

proc zosBash(command: string="hostname", host: string="localhost", port=4444, timeout:int=5, debug=false): string =
  let cmdid = newUUID()
  let payload = %*{
    "id": cmdid,
    "command": "bash",
    "queue": nil,
    "arguments": %*{"script":command, "stdin":""},
    "max_time": nil,
    "stream": false,
    "tags": nil
  }
  return zosSend(payload, true, host, port, timeout, debug)

proc zosCorePrivate(command: string="core.ping", payloadNode:JsonNode=nil, host: string="localhost", port=4444, timeout:int=5, debug=false): string =

  let cmdid = newUUID()
  let payload = %*{
    "id": cmdid,
    "command": command,
    "arguments": nil,
    "queue": nil,
    "max_time": nil,
    "stream": false,
    "tags": nil
  }
  if payloadNode != nil:
    payload["arguments"] = payloadNode
  return zosSend(payload, false, host, port, timeout, debug)
    

proc zosCore(command: string="core.ping", arguments:string, host: string="localhost", port=4444, timeout:int=5, debug=false): string =
  let payloadNode = %*arguments
  let cmdid = newUUID()
  let payload = %*{
    "id": cmdid,
    "command": command,
    "arguments": %*payloadNode,
    "queue": nil,
    "max_time": nil,
    "stream": false,
    "tags": nil
  }
  return zosSend(payload, false, host, port, timeout, debug)
    

type 
    VirtualBoxClient = ref object of RootObj

proc executeVBoxManage(cmd: string): TaintedString =
    let command = "vboxmanage " & cmd
    let (output, rc) = execCmdEx(command)
    if rc != 0:
        raise newException(Exception, fmt"Failed to execute {command}  \n{output}") 
    return output

proc executeVBoxManageModify(cmd: string): TaintedString= 
    let command = "vboxmanage modifyvm " & cmd
    echo fmt"** executing command {command}"
    let (output, rc) = execCmdEx(command)
    if rc != 0:
        raise newException(Exception, fmt"Failed to execute {command} \n{output}") 
    return output
    
type VM = object of RootObj
  name*: string
  guid*: string

type Disk = object of RootObj
    path*: string

proc initDisk*(path: string): Disk =
    return Disk(path:path)

proc initVM*(name: string, guid: string): VM =
    return VM(name:name, guid:guid)

proc getPath*(this: VM|string): string =
  when this is string:
    return fmt"{getHomeDir()}VirtualBox VMs/{this}"
  else:
    return fmt"{getHomeDir()}VirtualBox VMs/{this.name}"


proc listVMs*(): seq[VM] =
  var vms = newSeq[VM]()
  let output = executeVBoxManage("list vms")
  for line in output.splitLines():
      if not (line.startsWith("\"") and line.endsWith("}")):
          continue
      let parts = line.splitWhitespace()
      let machineName = parts[0].strip()[1..^2].toLower()
      let machineGuid = parts[1].strip()[1..^2].toLower()
      vms.add(initVM(machineName, machineGuid))
  return vms


proc getVMByName*(vmName: string) : VM =
  for vm in listVMs():
    if vmName == vm.name:
      return vm
  # should raise here..

proc getVMByGuid*(vmGuid: string) : VM =
  for vm in listVMs():
    if vmGuid == vm.guid:
      return vm
  # should raise here..
  

proc parseSectionsStartsWith(output: string, sectionStart:string): seq[TableRef[string, string]] =
  var sections = newSeq[TableRef[string, string]]()
  var currentTable: TableRef[string, string]
  for line in output.splitLines():
      if line.len == 0:
          continue
      if line.startsWith(sectionStart):
          # push new section
          currentTable = newTable[string, string]()
          sections.add(currentTable)
      else:
          if sections.len > 0:
              let parts = line.split(":", maxSplit=1)
              if len(parts) == 2:
                  currentTable[parts[0].strip().toLower()] = parts[1].strip().toLower()
              else:
                  currentTable[parts[0].strip().toLower()]  = ""
              
  return sections

proc listVDisks*(): seq[TableRef[string, string]] =
  var vdisks = newSeq[TableRef[string, string]]()
  let output = executeVBoxManage("list hdds -l")
  return parseSectionsStartsWith(output, "UUID")

proc listHostOnlyInterfaces*(): seq[TableRef[string, string]] = 
  var hosts = newSeq[TableRef[string, string]]()
  let output = executeVBoxManage("list hostonlyifs -l -s")
  return parseSectionsStartsWith(output, "Name")
  

proc modify*(this: VM, cmd: string): string =
  let command = fmt"{this.name} {cmd}"
  return executeVBoxManageModify(cmd)

proc exists*(this: VM): bool =
  for vm in listVMs():
      if this.name in vm.name or this.guid in vm.guid:
          return true
  return false

proc create*(this: Disk, size:int=1000): Disk =
  try:
    discard executeVBoxManage(fmt"""createhd --filename "{this.path}" --size {size}""")
  except:
    discard # IMPORTANT FIXME
  return this

proc diskInfo*(this: Disk): TableRef[string, string] = 
  let disks = listVDisks()
  for disk in disks:
      if disk.hasKey("Location") and disk["Location"] == this.path:
          return disk
  return newTable[string, string]()

proc size*(this: Disk): int =
  let capacity = this.diskInfo()["capacity"]
  if "mbyte" in capacity.toLower():
    let cap = capacity.split(" ", 1)[0]
    try:
        return parseInt(cap)
    except:
        return 0

proc state*(this: Disk): string = 
  return this.diskInfo()["state"]

proc diskUUID*(this: Disk): string =
  return this.diskInfo()["uuid"]


proc vmGuid*(this: Disk): string =
  let vmsline = this.diskInfo()["in use by vms"]
  # In use by VMs:  ReactOS (UUID: dfbaab53-4ffc-408b-b47d-5097d68d5325)
  if "UUID" in vmsline:
      let vmguid = vmsline[vmsline.find("UUID:")+5..^2]
      return vmguid
  


proc delete*(this: Disk): string =
  discard executeVBoxManage(fmt"closemedium disk {this.diskUUID()} --delete")

proc createDisk(this: VM, name:string, size:int=10000): Disk =
  var d = initDisk(fmt"{this.getPath()}/{name}.vdi")
  return d.create(size)


proc newVM(vmName: string, isoPath: string="/tmp/zos.iso", datadiskSize:int=1000, memory:int=2000, redisPort=4444) = 

  let cmd = fmt"""createvm --name "{vmName}" --ostype "Linux_64" --register """
  discard executeVBoxManage(cmd)
  
  var cmdsmodify = fmt"""
--memory={memory}
--ioapic on
--boot1 dvd --boot2 disk
--nic1 nat
#--nic2 hostonly
#--hostonlyadapter2 vboxnet0
--vrde on 
--natpf1 "redis,tcp,,{redisPort},,6379" """
  for l in cmdsmodify.splitLines:
    if l.isNilOrEmpty() or l.startsWith("#"):
      continue
    discard executeVBoxManageModify(fmt"""{vmName} {l}""")

  let vm = getVMByName(vmName)

  if datadisksize > 0:
      let disk = vm.createDisk(fmt"main{vmName}", datadiskSize)
      discard executeVBoxManage(fmt"""storagectl {vmName} --name "SATA Controller" --add sata  --controller IntelAHCI """)
      discard executeVBoxManage(fmt"""storageattach {vmName} --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "{disk.path}" """)

  discard executeVBoxManage(fmt"""storagectl {vmName} --name "IDE Controller" --add ide """)
  discard executeVBoxManage(fmt"""storageattach "{vmName}" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium {isoPath} """)

proc vmInfo(this: VM|string): TableRef[string, string] =
  var vmName = ""
  when this is VM:
    vmName = this.name
  else:
    vmName = this
  let output = executeVBoxManage(fmt"showvminfo {vmName}")
  let res = parseSectionsStartsWith(output, "Name:")
  if len(res) > 0:
      return res[0]
  return newTable[string, string]()

proc isRunning(this: VM): bool = 
  let vminfo = this.vmInfo()
  return vminfo.hasKey("state") and vminfo["state"] == "running"


proc downloadZOSIso(networkId: string="", overwrite:bool=false): string =
  var downloadLink = ""
  var destPath = ""

  if networkId.len == 0:
    downloadLink = "https://bootstrap.grid.tf/iso/development/0/development%20debug"
    destPath = "/tmp/zos.iso"
  else:
    downloadLink = fmt"https://bootstrap.grid.tf/iso/development/{networkId}/development%20debug"
    destPath = fmt"/tmp/zos_{networkId}.iso"

  echo fmt"DOWNLOAD LINK: {downloadLink}"
  if overwrite == true or not fileExists(destpath):
    let cmd = fmt"curl {downloadLink} --output {destPath}" 
    let (output, rc) = execCmdEx(cmd)
    if rc != 0:
      raise newException(Exception, fmt"couldn't download {downloadLink}")
  if fileExists(destPath):
    return destPath
  else:
    raise newException(Exception, fmt"couldn't download {downloadLink}")



proc startContainer(name:string, root:string, hostname:string, privileged=false, extraconfig="",  host="localhost", port=6379, timeout=30, debug=false):int = 

  discard """
    Creater a new container with the given root flist, mount points and
    zerotier id, and connected to the given bridges
    :param root_url: The root filesystem flist
    :param mount: a dict with {host_source: container_target} mount points.
                  where host_source directory must exists.
                  host_source can be a url to a flist to mount.
    :param host_network: Specify if the container should share the same network stack as the host.
                        if True, container creation ignores both zerotier, bridge and ports arguments below. Not
                        giving errors if provided.
    :param nics: Configure the attached nics to the container
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
    :param port: A dict of host_port: container_port pairs (only if default networking is enabled)
                  Example:
                    `port={8080: 80, 7000:7000}`
                  Source Format: NUMBER, IP:NUMBER, IP/MAST:NUMBER, or DEV:NUMBER
    :param hostname: Specific hostname you want to give to the container.
                    if None it will automatically be set to core-x,
                    x beeing the ID of the container
    :param privileged: If true, container runs in privileged mode.
    :param storage: A Url to the ardb storage to use to mount the root flist (or any other mount that requires g8fs)
                    if not provided, the default one from core0 configuration will be used.
    :param name: Optional name for the container
    :param identity: Container Zerotier identity, Only used if at least one of the nics is of type zerotier
    :param env: a dict with the environment variables needed to be set for the container
    :param cgroups: custom list of cgroups to apply to this container on creation. formated as [(subsystem, name), ...]
                    please refer to the cgroup api for more detailes.
    :param config: a map with the config file path as a key and content as a value. This only works when creating a VM from an flist. The
            config files are written to the machine before booting.
            Example:
            config = {'/root/.ssh/authorized_keys': '<PUBLIC KEYS>'}
    """
  let args = %*{
    "name": name,
    "hostname": hostname,
    "root": root,
    "privileged": privileged,
  }
  

  var extraArgs: JsonNode
  if not extraconfig.isNilOrEmpty():
    extraArgs = parseJson(extraconfig)
  
  if extraArgs != nil:
    for k,v in extraArgs.pairs:
      args[k] = %*v

  let command = "corex.create"
  discard zosCorePrivate(command, args, host, port, timeout, debug)
  # echo name, flist, host, $port
  result = 0

proc stopContainer(id:int,  host="localhost", port=6379, timeout=30, debug=false):int =

  let command = "corex.terminate"
  let arguments = %*{"container": id}
  discard zosCorePrivate(command, arguments, host, port, timeout, debug)
  result = 0

proc sandboxContainer(name:string,  host="localhost", port=6379, timeout=30, debug=false):int =
  echo name, host, $port
  result = 0

proc listContainers(host="localhost", port=6379):int = 
  let resp = parseJson(zosCorePrivate("corex.list", nil, host, port))
  echo $(resp["data"].getStr().parseJson().pretty(2))

  result = 0

proc newZos(vboxMachineName="myzosmachine", datadiskSize=1000, memory=1000, redisPort=4444): int = 
  let isopath = downloadZOSIso()
  try:
    newVM(vboxMachineName, "/tmp/zos.iso", datadiskSize, memory, redisPort)
  except:
    echo "ERROR HAPPENED " & getCurrentExceptionMsg()
  echo fmt"Created machine {vboxMachineName}"

  var args = ""

  when defined linux:
    if not existsEnv("DISPLAY"):
      args = "--type headless"
  let cmd = fmt"""startvm {args} "{vboxMachineName}" """
  discard executeVBoxManage(cmd)
  echo fmt"Started VM {vboxMachineName}"
  result = 0


when isMainModule:
  import cligen
  dispatchMulti([startContainer], [stopContainer], [listContainers], [sandboxContainer], [newZos], [zosCore], [zosBash])
