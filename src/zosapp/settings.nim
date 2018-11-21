import ospaths

let configdir* = ospaths.getConfigDir()
let configfile* = configdir / "zos.toml"

let appTimeout* = 30 
let pingTimeout* = 5