import osproc, strformat

proc sshExec*(cmd:string): int =
  let p = startProcess("/usr/bin/ssh", args=[cmd], options={poInteractive, poParentStreams})
  result = p.waitForExit()


# proc rsyncUploadFile*(src: string, sshDest:string): int =
#   let cmd = fmt"""rsync -avz ssh --progress {src} {sshDest} """ 
#   echo cmd

# proc rsyncDownloadFile*(sshSrc:string , dest:string) = 
#   let cmd = fmt"""rsync -avzhe ssh --progress {sshSrc} {dest}""" 
#   echo cmd


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

