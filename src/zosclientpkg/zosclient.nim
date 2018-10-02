import  redisclient, redisparser
import os, strutils, strformat, osproc, tables, uri
import uuid, json, tables, net, strformat, asyncdispatch, asyncnet, strutils, ospaths


proc flagifyId*(id: string): string =
  result = fmt"result:{id}:flag" 

proc resultifyId*(id: string): string = 
  result = fmt"result:{id}" 

proc streamId*(id: string): string = 
  result = fmt"stream:{id}" 

proc newUUID*(): string = 
  var cmduid: Tuuid
  uuid_generate_random(cmduid)
  result = cmduid.to_hex

proc getResponseString*(con: Redis|AsyncRedis, id: string, timeout=10): Future[string] {.multisync.} = 
  let exists = $(await con.execCommand("EXISTS", @[flagifyId(id)]))
  if exists == "1":
    let reskey = resultifyId(id)
    result = $(await con.execCommand("BRPOPLPUSH", @[reskey, reskey, $timeout]))


proc outputFromResponse*(resp: string): string =
  let parsed = parseJson(resp)

  let response_state = $parsed["state"].getStr()
  if response_state != "SUCCESS":
    echo fmt"[-]{parsed}"
  else: 
    let dataStr = parsed["data"].getStr()
    result = dataStr
    let code = parsed["code"].getInt()
    let streamout = parsed["streams"][0].getStr()
    let streamerr = parsed["streams"][1].getStr()
    
    if dataStr != "":
      result = dataStr
    else:
      if streamout != "":
        result = streamout
      else:
        result = streamerr

proc zosSend*(con: Redis|AsyncRedis, payload: JsonNode, bash=false, timeout=5, debug=false): string =
  let cmdid = payload["id"].getStr()

  if debug == true:
    echo "payload" & $payload
 
  let flag = flagifyId(cmdid)
  let reskey = resultifyId(cmdid) 

  var cmdres: RedisValue
  cmdres = con.execCommand("RPUSH", @["core:default", $payload])
  if debug:
    echo $cmdres
  cmdres = con.execCommand("BRPOPLPUSH", @[flag, flag, $timeout])
  if debug:
    echo $cmdres

  result = outputFromResponse(con.getResponseString(cmdid))



proc containerSend*(con:Redis|AsyncRedis, payload: JsonNode, bash=false, timeout=5, debug=false): string =
  var first = con.zosSend(payload, bash, timeout, debug)
  echo(first)
  if first.startsWith("\""):
    first = first[1..^2]
  result = outputFromResponse(con.getResponseString(first))

proc containersCoreWithJsonNode*(con:Redis|AsyncRedis, containerid:int, command: string="hostname", payloadNode:JsonNode=nil, timeout:int=5, debug=false): string =
  let cmdid = newUUID()
  let containercmdId = newUUID()

  var payload = %*{
    "id": cmdid,
    "command": "corex.dispatch",
    "arguments": nil,
    "queue": nil,
    "max_time": nil,
    "stream": false,
    "tags": nil
  }
  let commandparts = command.split()
  var commandargs: seq[string] = @[]
  let binname = commandparts[0]
  if len(commandparts)>1:
    commandargs = commandparts[1..^1]

  payload["arguments"] = %*{
    "container": containerid,
    "command": {
        "command": "core.system",
        "arguments": %*{
          "name": commandparts[0],
          "args": commandargs,
          "dir":"",
          "stdin":"",
          "env":nil
        } ,
        "queue": nil,
        "max_time": nil,
        "stream": false,
        "tags": nil,
        "id": nil,
    },
  }
  result =  con.containerSend(payload, false, timeout, debug)

proc containersCore*(con:Redis|AsyncRedis, containerid: int, command: string="hostname", arguments="", timeout:int=5, debug=false):string =
  var payloadNode: JsonNode = nil
  if arguments != "":
    payloadNode = parseJson(arguments) 
  
  return con.containersCoreWithJsonNode(containerid, command, payloadNode,timeout, debug)

proc zosBash*(con:Redis|AsyncRedis, command: string="hostname", timeout:int=5, debug=false): string =
  let cmdid = newUUID()
  let payload = %*{
    "id": cmdid,
    "command": "bash",
    "queue": nil,
    "arguments": %*{"script":command, "stdin":""},
    "max_time": nil,
    "stream": false,
    "tags": nil
  }
  return con.zosSend(payload, true, timeout, debug)


proc zosCoreWithJsonNode*(con:Redis|AsyncRedis, command: string="core.ping", payloadNode:JsonNode=nil, timeout:int=5, debug=false): string =

  let cmdid = newUUID()
  let payload = %*{
    "id": cmdid,
    "command": command,
    "arguments": nil,
    "queue": nil,
    "max_time": nil,
    "stream": false,
    "tags": nil
  }
  if payloadNode != nil:
    payload["arguments"] = payloadNode

  return con.zosSend(payload, false,timeout, debug)
  

proc zosCore*( con:Redis|AsyncRedis, command: string="core.ping", arguments="", timeout:int=5, debug=false): string =
  var payloadNode: JsonNode = nil
  if arguments != "":
    payloadNode = parseJson(arguments) 
  return con.zosCoreWithJsonNode(command, payloadNode, timeout, debug)

    