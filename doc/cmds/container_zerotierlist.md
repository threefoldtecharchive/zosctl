# container <id> zerotierlist


Shows assigned addresses , mac, mtu, routes, status .. etc
```bash

./zos container 189  zerotierlist
[
  {
    "allowDefault": false,
    "allowGlobal": false,
    "allowManaged": true,
    "assignedAddresses": [
      "fc2e:9ff1:744a:4877:c9cc:0000:0000:0001/40",
      "10.244.163.53/16"
    ],
    "bridge": false,
    "broadcastEnabled": true,
    "dhcp": false,
    "id": "9bee8941b5717835",
    "mac": "36:32:39:c2:88:45",
    "mtu": 2800,
    "name": "tfgrid_public",
    "netconfRevision": 3,
    "nwid": "9bee8941b5717835",
    "portDeviceName": "zt3jn7qoma",
    "portError": 0,
    "routes": [
      {
        "flags": 0,
        "metric": 0,
        "target": "10.244.0.0/16",
        "via": null
      }
    ],
    "status": "OK",
    "type": "PUBLIC"
  }
]


```