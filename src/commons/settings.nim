import strutils, strformat, os, ospaths, osproc, tables, parsecfg, json, marshal, logging

import ./apphelp
import ./logger
import ./errorcodes

let configDir* = ospaths.getConfigDir()
let configFile* = configDir / "zos.toml"

let appTimeout* = 30
let pingTimeout* = 5

let appDeps* = @["ssh", "scp", "sshfs"]

const buildBranchName* = staticExec("git rev-parse --abbrev-ref HEAD")
const buildCommit* = staticExec("git rev-parse HEAD")

proc depsCheck*() = 
  ## Checks for dependencies for zos (mainly ssh tools ssh, scp, sshfs)
  for b in appDeps:
    if findExe(b) == "":
      error(fmt"Application dependencies aren't installed: can't find {b} in \$PATH")
      quit depsNotInstalled


let sshconfigFile* = getHomeDir() / ".ssh" / "config"
let sshconfigFileBackup* = getHomeDir() / ".ssh" / "config.backup"
let sshconfigTemplate* = """
Host *
  StrictHostKeyChecking no
  ForwardAgent yes
  
"""

proc prepareConfig*() = 
  ## Prepare configuration environment for zos
  try:
    createDir(configDir)
  except:
    error(fmt"couldn't create {configDir}")
    quit cantCreateConfigDir

  if not fileExists(configFile):
    open(configFile, fmWrite).close()
    var t = loadConfig(configFile)
    t.setSectionKey("app", "debug", "false")
    t.writeConfig(configFile)
    info(firstTimeMessage)
  
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


depsCheck()
prepareConfig()
      

proc getAppConfig*(): OrderedTableRef[string, string] =
  ## Gets the application section configuration
  let tbl = loadConfig(configFile)
  result = tbl.getOrDefault("app")

let appconfig* = getAppConfig()

proc isConfigured*(): bool =
  ## Checks if zos is already configured or not
  return appconfig.hasKey("defaultzos") == true

proc getActiveZosName*(): string =
  ## Gets the current active machine zos configured against.
  return appconfig["defaultzos"]


proc isDebug*(): bool =
  ## Checks if the application running in debug mode
  return appconfig["debug"] == "true" or (os.existsEnv("ZOS_DEBUG") and os.getEnv("ZOS_DEBUG") == "1")
  

proc getZerotierId*(): string =
  ## Gets the zerotier zos configured against 
  ## By default it's the TF_GRID_PUBLIC network 
  ## Can be overriden using GRID_ZEROTIER_ID_TESTING env variable 
  if os.existsEnv("GRID_ZEROTIER_ID_TESTING"):
    result = os.getEnv("GRID_ZEROTIER_ID_TESTING")    
  else:
    result = os.getEnv("GRID_ZEROTIER_ID", "9bee8941b5717835") # pub tf network.
  debug(fmt"using zerotier network {result}")

let zerotierId* = getZerotierId()


type ZosConnectionConfig*  = object
  ## Zero-OS machine configuration object 
  name*: string
  address*: string
  port*: int
  sshkey*: string 
  isvbox*: bool

proc newZosConnectionConfig*(name, address: string, port:int, sshkey=getHomeDir()/".ssh/id_rsa", isvbox=false): ZosConnectionConfig  = 
  ## Create new ZosConnectionConfig
  result = ZosConnectionConfig(name:name, address:address, port:port, sshkey:sshkey, isvbox:isvbox)
  
proc getConnectionConfigForInstance*(name: string): ZosConnectionConfig  =
  ## Get ZosConnectionConfig object for a specific instance
  var tbl = loadConfig(configFile)
  let address = tbl.getSectionValue(name, "address")
  let parsed = tbl.getSectionValue(name, "port")
  let sshkey = tbl.getSectionValue(name, "sshkey")

  var isvbox = false
  try:
    isvbox = tbl.getSectionValue(name, "isvbox") == "true"
  except:
    debug(fmt"machine {name} is not on virtualbox")
    discard
  
  tbl.writeConfig(configFile)
  var port = 6379
  try:
    port = parseInt(parsed)
  except:
    warn(fmt"invalid port value: >{parsed}< will use default for now.")
  
  result = newZosConnectionConfig(name, address, port, sshkey, isvbox)

proc getCurrentConnectionConfig*(): ZosConnectionConfig =
  ## Get the current connection configuration ZosConnectionConfig object.
  let tbl = loadConfig(configFile)
  let name = tbl.getSectionValue("app", "defaultzos")
  result = getConnectionConfigForInstance(name)

proc activeZosIsVbox*(): bool = 
  ## Returns true if the current machine is in VirtualBox
  return getCurrentConnectionConfig().isvbox == true
