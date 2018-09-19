import  redisclient, redisparser
import os, strutils, strformat, osproc, tables, uri
import uuid, json, tables, net, strformat, asyncdispatch, asyncnet, strutils, ospaths
import vboxpkg/vbox
import zosclientpkg/zosclient


if findExe("vboxmanage").isNilOrEmpty():
  echo "Please make sure to have VirtualBox installed"
  quit 1



proc startContainer(name:string, root:string, hostname:string, privileged=false, extraconfig="",  host="localhost", port=6379, timeout=30, debug=false, info=false):int = 
  if info == true:
    echo """
    extraconfig is json encoded string contains
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
  echo zosCoreWithJsonNode(command, args, host, port, timeout, debug)
  # echo name, flist, host, $port
  result = 0

proc stopContainer(id:int,  host="localhost", port=6379, timeout=30, debug=false):int =

  let command = "corex.terminate"
  let arguments = %*{"container": id}
  discard zosCoreWithJsonNode(command, arguments, host, port, timeout, debug)
  result = 0

proc sandboxContainer(name:string,  host="localhost", port=6379, timeout=30, debug=false):int =
  echo name, host, $port
  result = 0

proc listContainers(host="localhost", port=6379):int = 
  let resp = parseJson(zosCoreWithJsonNode("corex.list", nil, host, port))
  echo resp.pretty(2)

  result = 0

proc init(vboxMachineName="local", datadiskSize=1000, memory=2048, redisPort=4444): int = 
  # TODO: add cores parameter.
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
  dispatchMulti([startContainer], [stopContainer], [listContainers], [sandboxContainer], [init], [zosCore], [zosBash])
