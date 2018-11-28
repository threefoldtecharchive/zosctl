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
