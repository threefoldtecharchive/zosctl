import os, strutils, strformat, osproc, tables, uri
import json, tables, net, strformat, asyncdispatch, asyncnet, strutils, ospaths

type 
  VirtualBoxClient* = ref object of RootObj

proc executeVBoxManage*(cmd: string): TaintedString =
  let command = "vboxmanage " & cmd
  let (output, rc) = execCmdEx(command)
  if rc != 0:
      raise newException(Exception, fmt"Failed to execute {command}  \n{output}") 
  return output

proc executeVBoxManageModify*(cmd: string): TaintedString= 
  let command = "vboxmanage modifyvm " & cmd
  echo fmt"** executing command {command}"
  let (output, rc) = execCmdEx(command)
  if rc != 0:
      raise newException(Exception, fmt"Failed to execute {command} \n{output}") 
  return output
  
type VM* = object of RootObj
  name*: string
  guid*: string

type Disk* = object of RootObj
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


proc startVm*(this: VM|string) =
  var name = ""
  when this is VM:
    name = this.name
  else:
    name = this

  var args = ""
  when defined linux:
    if not existsEnv("DISPLAY"):
      args = "--type headless"
  let cmd = fmt"""startvm {args} "{name}" """
  discard executeVBoxManage(cmd)

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

proc exists*(this: VM|string): bool =
  for vm in listVMs():
      when this is VM:
        if this.name in vm.name or this.guid in vm.guid:
            return true
      else:
        return this in vm.guid or this in vm.name

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


proc createDisk*(this: VM, name:string, size:int=10000): Disk =
  var d = initDisk(fmt"{this.getPath()}/{name}.vdi")
  return d.create(size)


proc newVM*(vmName: string, isoPath: string="/tmp/zos.iso", datadiskSize:int=1000, memory:int=2000, redisPort=4444) = 


  let cmd = fmt"""createvm --name "{vmName}" --ostype "Linux_64" --register """
  discard executeVBoxManage(cmd)

  var cmdsmodify = fmt"""
  --memory={memory}
  --ioapic on
  --boot1 dvd --boot2 disk
  --nic1 nat
  --vrde on 
  --natpf1 "redis,tcp,,{redisPort},,6379" """
  for l in cmdsmodify.splitLines:
    if l == "" or l.startsWith("#"):
      continue
    discard executeVBoxManageModify(fmt"""{vmName} {l}""")

  let vm = getVMByName(vmName)

  if datadisksize > 0:
      let disk = vm.createDisk(fmt"main{vmName}", datadiskSize)
      discard executeVBoxManage(fmt"""storagectl {vmName} --name "SATA Controller" --add sata  --controller IntelAHCI """)
      discard executeVBoxManage(fmt"""storageattach {vmName} --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "{disk.path}" """)

  discard executeVBoxManage(fmt"""storagectl {vmName} --name "IDE Controller" --add ide """)
  discard executeVBoxManage(fmt"""storageattach "{vmName}" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium {isoPath} """)

proc vmInfo*(this: VM|string): TableRef[string, string] =
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


proc downloadZOSIso*(networkId: string="", overwrite:bool=false): string =
  var downloadLink = ""
  var destPath = ""

  if networkId.len == 0:
    downloadLink = "https://bootstrap.grid.tf/iso/development/0/development%20debug"
    destPath = "/tmp/zos.iso"
  else:
    downloadLink = fmt"https://bootstrap.grid.tf/iso/development/{networkId}/development%20debug"
    destPath = fmt"/tmp/zos_{networkId}.iso"

  # echo fmt"DOWNLOAD LINK: {downloadLink}"
  if overwrite == true or not fileExists(destpath):
    let cmd = fmt"curl {downloadLink} --output {destPath}" 
    let (output, rc) = execCmdEx(cmd)
    if rc != 0:
      raise newException(Exception, fmt"couldn't download {downloadLink}")
  if fileExists(destPath):
    return destPath
  else:
    raise newException(Exception, fmt"couldn't download {downloadLink}")

