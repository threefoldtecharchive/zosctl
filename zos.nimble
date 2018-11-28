
# Package

version       = "0.1.0"
author        = "Ahmed T. Youssef"
description   = "spawn and manage zero-os containers locally or on the grid easily"
license       = "Apache-2.0"
srcDir        = "src"
bin           = @["zos"]


# Dependencies
requires "nim >= 0.19", "docopt#head", "redisclient >= 0.1.1", "asciitables >= 0.1.0", "uuids"

task zos, "Creating zos binary":
    exec "nimble build -d:ssl --threads:on"

task zosStatic, "Creating static binary":
    exec "nim musl --threads:on -d:release -d:pcre -d:openssl src/zos.nim"
    exec "cp zos zosStatic"

