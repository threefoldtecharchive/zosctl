import logging, ospaths


## Global logging service for the application
## console logger is configured for levelinfo (lvlInfo) or higher
## file logger (zos.log) configured for all logging levels.

var L* = newConsoleLogger(levelThreshold=lvlInfo)
var fL* = newFileLogger(getTempDir() / "zos.log", levelThreshold=lvlAll, fmtStr = verboseFmtStr) ## logs saved in zos.log
addHandler(L)
addHandler(fL)
