import os, strutils, strformat, osproc, tables, uri
import json, tables, net, strformat, asyncdispatch, asyncnet, strutils, ospaths

type 
  VirtualBoxClient* = ref object of RootObj

proc executeVBoxManage*(cmd: string, die=true): TaintedString =
  ## Execute vboxmange command
  ## die raises exception if true otherwise fails silently
  let command = "vboxmanage " & cmd
  let (output, rc) = execCmdEx(command)
  if rc != 0 and die==true:
      raise newException(Exception, fmt"Failed to execute {command}  \n{output}") 
  return output

proc executeVBoxManageModify*(cmd: string, die=true): TaintedString= 
  ## Execute vboxmange modifyvm command
  ## die raises exception if true otherwise fails silently
  let command = "vboxmanage modifyvm " & cmd
  echo fmt"** executing command {command}"
  let (output, rc) = execCmdEx(command)
  if rc != 0 and die==true:
      raise newException(Exception, fmt"Failed to execute {command} \n{output}") 
  return output
  
type VM* = object of RootObj
  ## Type representing VM 
  ## VM is typically referenced by name or guid
  name*: string
  guid*: string

type Disk* = object of RootObj
  ## Type representing Disks
  ## Referenced by path
  path*: string

proc initDisk*(path: string): Disk =
  ## Initialize Disk object by Path
  return Disk(path:path)

proc initVM*(name: string, guid: string): VM =
  ## Initialize VM object using name and guid
  return VM(name:name, guid:guid)

proc getPath*(this: VM|string): string =
  ## Get path of the actual directory of the VM on harddisk
  when this is string:
    return fmt"{getHomeDir()}VirtualBox VMs/{this}"
  else:
    return fmt"{getHomeDir()}VirtualBox VMs/{this.name}"

proc startVm*(this: VM|string) =
  ## Start vm either by object of VM type or by name
  var name = ""
  when this is VM:
    name = this.name
  else:
    name = this

  if not this.isRunning():
    var args = ""
    when defined linux:
      if not existsEnv("DISPLAY"):
        args = "--type headless"
    let cmd = fmt"""startvm {args} "{name}" """
    discard executeVBoxManage(cmd)

proc listVMs*(): seq[VM] =
  ## Lists VMs
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
  ## Gets VM object by Name
  for vm in listVMs():
    if vmName == vm.name:
      return vm
  raise newException(ValueError, fmt"{vmName} not found")


proc getVMByGuid*(vmGuid: string) : VM =
  ## Gets VM object by GUID
  for vm in listVMs():
    if vmGuid == vm.guid:
      return vm
  raise newException(ValueError, fmt"{vmGuid} not found")


proc parseSectionsStartsWith(output: string, sectionStart:string): seq[TableRef[string, string]] =
  var sections = newSeq[TableRef[string, string]]()
  var currentTable: TableRef[string, string]
  for line in output.splitLines():
      if line.len == 0:
          continue
      if line.startsWith(sectionStart):
          # push new section
          currentTable = newTable[string, string]()
          let parts = line.split(":", maxSplit=1)
          if len(parts) == 2:
              currentTable[parts[0].strip().toLower()] = parts[1].strip().toLower()
          else:
              currentTable[parts[0].strip().toLower()]  = ""


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
  ## Lists VDisks
  var vdisks = newSeq[TableRef[string, string]]()
  let output = executeVBoxManage("list hdds -l")
  return parseSectionsStartsWith(output, "UUID")

proc listHostOnlyInterfaces*(): seq[TableRef[string, string]] = 
  ## Lists HostOnly Interfaces
  var hosts = newSeq[TableRef[string, string]]()
  let output = executeVBoxManage("list hostonlyifs -l -s")
  return parseSectionsStartsWith(output, "Name")


proc hasHostOnlyInterface*(name:string): bool =
  ## Checks if Virtualbox has Hostonly interface with name `name`
  let output = executeVBoxManage("list hostonlyifs -l -s") 
  return output.contains(name)

proc modify*(this: VM, cmd: string): string =
  ## Modify VM with command `cmd`
  let command = fmt"{this.name} {cmd}"
  return executeVBoxManageModify(cmd)

proc exists*(this: VM|string): bool =
  ## Check if VM exists
  for vm in listVMs():
      when this is VM:
        if vm.name == this.name or this.guid == vm.guid:
          return true
      else:
        if this == vm.guid or this == vm.name:
          return true

  return false

proc create*(this: Disk, size:int=1000): Disk =
  ## Creates actual disk from Disk object
  try:
    discard executeVBoxManage(fmt"""createhd --filename "{this.path}" --size {size}""")
  except:
    discard # IMPORTANT FIXME
  return this

proc diskInfo*(this: Disk): TableRef[string, string] = 
  ## Gets disk information
  let disks = listVDisks()
  for disk in disks:
      if disk.hasKey("Location") and disk["Location"] == this.path:
          return disk
  return newTable[string, string]()

proc size*(this: Disk): int =
  ## Gets disk size
  let capacity = this.diskInfo()["capacity"]
  if "mbyte" in capacity.toLower():
    let cap = capacity.split(" ", 1)[0]
    try:
        return parseInt(cap)
    except:
        return 0

proc state*(this: Disk): string = 
  ## Gets disk state
  return this.diskInfo()["state"]

proc diskUUID*(this: Disk): string =
  ## Gets disk UUID
  return this.diskInfo()["uuid"]


proc vmGuid*(this: Disk): string =
  ## Get guid of the VM
  let vmsline = this.diskInfo()["in use by vms"]
  # In use by VMs:  ReactOS (UUID: dfbaab53-4ffc-408b-b47d-5097d68d5325)
  if "UUID" in vmsline:
      let vmguid = vmsline[vmsline.find("UUID:")+5..^2]
      return vmguid

proc vmDisks*(this: VM): seq[string] =
  ## Gets sequence of disk names of the VM
  let vdisks = listVDisks()
  for disk in vdisks:
    if disk.hasKey("in use by vms"):
      if disk["in use by vms"].contains(this.guid):
        result.add(disk["uuid"])

proc delete*(this: Disk|string): string =
  ## Deletes disk by name or by object.
  when this is string:
    discard executeVBoxManage(fmt"closemedium disk {this} --delete")
  else:
    discard executeVBoxManage(fmt"closemedium disk {this.diskUUID()} --delete")

proc createDisk*(this: VM, name:string, size:int=10000): Disk =
  ## Create disk on VM  with name `name` and size in megabytes (defaults to 10000)
  var d = initDisk(fmt"{this.getPath()}/{name}.vdi")
  return d.create(size)


proc newVM*(vmName: string, isoPath: string="/tmp/zos.iso", datadiskSize:int=1000, memory:int=2000, redisPort=4444) = 
  ## Create new zero-os machine using `iso` from the bootstrap service.

  # try create hostonly interface and if it fails it's fine.
  if not hasHostOnlyInterface("vboxnet0"):
    discard executeVBoxManage("hostonlyif create", die=false)

  let cmd = fmt"""createvm --name "{vmName}" --ostype "Linux_64" --register """
  discard executeVBoxManage(cmd)

  var cmdsmodify = fmt"""--memory={memory}  --ioapic on --boot1 dvd --boot2 disk --nic1 nat --nic2 hostonly --hostonlyadapter2 vboxnet0 --vrde on --natpf1 "redis,tcp,,{redisPort},,6379" """
  # for l in cmdsmodify.splitLines:
  #   if l == "" or l.startsWith("#"):
      # continue
  discard executeVBoxManageModify(fmt"""{vmName} {cmdsmodify}""")
    
  var vm: VM
  try:
    vm = getVMByName(vmName)
  except:
    echo fmt"[-]the created vm {vmName} doesn't exist"
    quit 117
  

  if datadisksize > 0:
      let disk = vm.createDisk(fmt"main{vmName}", datadiskSize)
      discard executeVBoxManage(fmt"""storagectl {vmName} --name "SATA Controller" --add sata  --controller IntelAHCI """)
      discard executeVBoxManage(fmt"""storageattach {vmName} --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "{disk.path}" """)
  
  discard executeVBoxManage(fmt"""storagectl {vmName} --name "IDE Controller" --add ide """)
  discard executeVBoxManage(fmt"""storageattach "{vmName}" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium {isoPath} """)


proc vmInfo*(this: VM|string): TableRef[string, string] =
  ## Gets VM information
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

proc isRunning*(this: VM|string): bool =
  ## Check if VM is running 
  let vminfo = this.vmInfo()
  return vminfo.hasKey("state") and vminfo["state"].contains("running")


proc vmDelete*(this: VM|string) =
  ## Delete VM
  var vm: VM
  var vmguid = ""
  var vmname = ""

  when this is string:
    vmguid = this
    vmname = this
  else:
    vmguid = this.guid 
    vmname = this.name 

  var found = false
  try:
    vm = getVMByName(vmname)
    found = true
  except:
    try:
      vm = getVMByGuid(vmguid)
      found = true
    except:
      discard
  
  if found:
    let maxtrials = 15
    if this.isRunning():
      try:
        discard executeVBoxManage(fmt"controlvm {vm.guid} poweroff")
      except:
        echo "ERROR: " & getCurrentExceptionMsg()
    # for d in vm.vmDisks():
    #   try:
    #   discard delete(d) 

    discard executeVBoxManage(fmt"unregistervm {vm.guid} --delete")
    try:
      removeDir(vm.getPath())
    except:
      echo "ERROR: " & getCurrentExceptionMsg()


proc portAlreadyForwarded*(p:int): (bool, string) =
  ## Check if the port already is forwarded
  ## Returns true and machine name if there's a portforward and false otherwise
  var taken = false
  var vmName = ""
  for vm in listVMs(): 
    try:
      let vminfo = executeVBoxManage(fmt"""showvminfo {vm.name}""")
      if vminfo.contains(fmt"host port = {p}"):
        vmName = vm.name
        taken = true
        break
    except:
      # can't find registered machine error.
      discard 
  return (taken ,vmName)


proc downloadZOSIso*(networkId: string="", overwrite:bool=false): string =
  ## Download Zero-OS iso image
  ## networkId to work against specific zerotier network
  ## Overwrite forces redownload
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

