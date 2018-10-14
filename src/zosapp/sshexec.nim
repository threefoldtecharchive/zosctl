import osproc

proc sshExec*(cmd:string): int =
  let p = startProcess("/usr/bin/ssh", args=[cmd], options={poInteractive, poParentStreams})
  result = p.waitForExit()
