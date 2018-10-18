

#some examples how to use client


## create connection to client

in js9 shell

```
data={}
data["port"]=4444
data["host"]="localhost"
data["ssl"]=True
cl=j.clients.zos.get(data=data)
```

## join the host ZOS to a zerotier network

```
cl.client.zerotier.leave("9bee8941b5717835")
cl.client.zerotier.join("9bee8941b5717835")
```

## see which zero-tier networks connected

```
cl.client.zerotier.list()
```

result
```
[{'allowDefault': False,
  'allowGlobal': False,
  'allowManaged': True,
  'assignedAddresses': [],
  'bridge': False,
  'broadcastEnabled': False,
  'dhcp': False,
  'id': '9bee8941b5717835',
  'mac': '36:57:1a:e4:1f:41',
  'mtu': 2800,
  'name': '',
  'netconfRevision': 0,
  'nwid': '9bee8941b5717835',
  'portDeviceName': 'zt3jn7qoma',
  'portError': 0,
  'routes': [],
  'status': 'REQUESTING_CONFIGURATION',
  'type': 'PRIVATE'}]
```

## create flist

```
c.client.flist.create("/root","/tmp/1","playground.hub.grid.tf:9910")
```

will upload the flist to a public hub