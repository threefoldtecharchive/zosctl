import  redisclient, redisparser
import uuid, json, tables, net, strformat, asyncdispatch, asyncnet, strutils


proc flagifyId(id: string): string =
  result = fmt"result:{id}:flag" 

proc resultifyId(id: string): string = 
  result = fmt"result:{id}" 


proc getResponseString*(id: string, con: Redis|AsyncRedis, timeout=10): Future[string] {.multisync.} = 
  let exists = $(await con.execCommand("EXISTS", @[flagifyId(id)]))
  if exists == "1":
    let reskey = resultifyId(id)
    result = $(await con.execCommand("BRPOPLPUSH", @[reskey, reskey, $timeout]))

  

proc zosSend(command: string="core.ping",  bash=false, host: string="localhost", timeout:int=5, debug=false) =
    var cmduid: Tuuid
    uuid_generate_random(cmduid)
    let cmdid = cmduid.to_hex

    let payload = %*{
      "id": cmdid,
      "command": command,
      "queue": nil,
      "max_time": nil,
      "stream": false,
      "tags": nil
    }
    if bash == true:
      payload["command"] = %*"bash"
      payload["arguments"] = %*{"script":command, "stdin":""}

    if debug == true:
      echo "payload" & $payload
    let con = open(host, 4444.Port, true)
    let flag = flagifyId(cmdid)
    let reskey = resultifyId(cmdid) 
    discard con.execCommand("RPUSH", @["core:default", $payload])
    discard con.execCommand("BRPOPLPUSH", @[flag, flag, $timeout])

    let parsed = parseJson(getResponseString(cmdid, con))
    let response_state = $parsed["state"].getStr()
    if response_state != "SUCCESS":
      echo "FAILED TO EXECUTE"
      echo $parsed
      quit 1
    else:
      if bash == true:
        if parsed["code"].getInt() == 0:
          echo parsed["streams"][0].getStr() # stdout
        else:
          echo parsed["streams"][1].getStr() # stderr
      else:
        echo parsed["data"].getStr()
        

when isMainModule:
  import cligen
  dispatchMulti([zosSend])
