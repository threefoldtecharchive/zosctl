import osproc, strformat, ospaths, os

proc sshExec*(cmd:string): int =
  let p = startProcess("/usr/bin/ssh", args=[cmd], options={poInteractive, poParentStreams})
  result = p.waitForExit()


# proc rsyncUploadFile*(src: string, sshDest:string): int =
#   let cmd = fmt"""rsync -avz ssh --progress {src} {sshDest} """ 
#   echo cmd

# proc rsyncDownloadFile*(sshSrc:string , dest:string) = 
#   let cmd = fmt"""rsync -avzhe ssh --progress {sshSrc} {dest}""" 
#   echo cmd

proc getAgentPublicKeys*(): string = 
  let (output, rc) = execCmdEx("ssh-add -L")
  if rc == 0:
    return $output

proc getPublicSshKeyByName*(keyname="id_rsa"): string =
  let path = getHomeDir() / ".ssh" / fmt"{keyname}.pub"
  if fileExists(path):
    result = readFile(path)

proc getPublicSshkeyFromKeyPath*(keypath=getHomeDir()/".ssh"/"id_rsa"):string = 
  if fileExists(keypath):
    result = readFile(keypath & ".pub")

proc rsyncUpload*(src: string, sshDest:string, isDir=false):string =
  var rflag = ""
  if isDir:
    rflag = "-r"

  result = fmt"""scp {rflag} {src} {sshDest} """ 
  echo result 

proc rsyncDownload*(sshSrc:string , dest:string, isDir=false):string = 
  var rflag = ""
  if isDir:
    rflag = "-r"

  result = fmt"""scp {rflag} {sshSrc} {dest}""" 
  echo result

