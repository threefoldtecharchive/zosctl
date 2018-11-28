import logging

var L* = newConsoleLogger(levelThreshold=lvlInfo)
var fL* = newFileLogger("zos.log", levelThreshold=lvlAll, fmtStr = verboseFmtStr) ## logs saved in zos.log
addHandler(L)
addHandler(fL)
