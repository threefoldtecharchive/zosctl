import logging

var L* = newConsoleLogger(levelThreshold=lvlInfo)
var fL* = newFileLogger("zos.log", levelThreshold=lvlAll, fmtStr = verboseFmtStr)
addHandler(L)
addHandler(fL)
