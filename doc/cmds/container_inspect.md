# container inspect
using `inspect` command
```bash
./zos container 1 inspect
{
  "cpu": 0.01674105440884163,
  "rss": 7946240,
  "vms": 398368768,
  "swap": 0,
  "container": {
    "arguments": {
      "root": "https://hub.grid.tf/tf-autobuilder/threefoldtech-0-robot-autostart-development.flist",
      "mount": {
        "/var/cache/zrobot/config": "/opt/code/local/stdorg/config",
        "/var/cache/zrobot/data": "/opt/var/data/zrobot/zrobot_data",
        "/var/cache/zrobot/jsconfig": "/root/jumpscale/cfg",
        "/var/cache/zrobot/ssh": "/root/.ssh",
        "/var/run/redis.sock": "/tmp/redis.sock"
      },
      "host_network": false,
      "identity": "",
      "nics": [
        {
          "type": "default",
          "id": "",
          "hwaddr": "",
          "config": {
            "dhcp": false,
            "cidr": "",
            "gateway": "",
            "dns": null
          },
          "monitor": false,
          "state": "configured"
        }
      ],
      "port": {
        "6600": 6600
      },
      "privileged": false,
      "hostname": "",
      "storage": "zdb://hub.grid.tf:9900",
      "name": "zrobot",
      "tags": [
        "zrobot"
      ],
      "env": {
        "HOME": "/root",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8"
      },
      "cgroups": [
        [
          "devices",
          "corex"
        ]
      ],
      "config": null
    },
    "root": "/mnt/containers/1",
    "pid": 446
  }
}
```
### Inspect all containers
`./zos container inspect`
Shows a detailed information about the container

