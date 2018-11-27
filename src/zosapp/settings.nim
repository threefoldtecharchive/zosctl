import ospaths

let configdir* = ospaths.getConfigDir()
let configfile* = configdir / "zos.toml"

let appTimeout* = 5000 
let pingTimeout* = 5

const buildBranchName* = staticExec("git rev-parse --abbrev-ref HEAD")
const buildCommit* = staticExec("git rev-parse HEAD")
      