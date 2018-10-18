# cmd

`./zos cmd <cmdname>` is used to execute zero-os buitlin commands like ping, disk.list ..etc

##  `ping`
```
./zos cmd "core.ping" 
```
You should see response
```
"PONG Version: development @Revision: f61e80169fda9cf5246305feb3fde3cadd831f3c"
```


## `disk.list`
```
~> ./zos cmd "disk.list" 
```
Output:
```
[
  {
    "name": "sda",
    "kname": "sda",
    "maj:min": "8:0",
    "fstype": null,
    "mountpoint": null,
    "label": null,
    "uuid": null,
    "parttype": null,
    "partlabel": null,
    "partuuid": null,
    "partflags": null,
    "ra": "128",
    "ro": "0",
    "rm": "0",
    "hotplug": "0",
    "model": "VBOX HARDDISK   ",
    "serial": "VBf3f81d08-69a57200",
    "state": "running",
    "owner": "root",
    "group": "disk",
    "mode": "brw-rw----",
    "alignment": "0",
    "min-io": "512",
    "opt-io": "0",
    "phy-sec": "512",
    "log-sec": "512",
    "rota": "1",
    "sched": "cfq",
    "rq-size": "128",
    "type": "disk",
    "disc-aln": "0",
    "disc-gran": "0",
    "disc-max": "0",
    "disc-zero": "0",
    "wsame": "0",
    "wwn": null,
    "rand": "1",
    "pkname": null,
    "hctl": "2:0:0:0",
    "tran": "sata",
    "subsystems": "block:scsi:pci",
    "rev": "1.0 ",
    "vendor": "ATA     ",
    "children": [
      {
        "name": "sda1",
        "kname": "sda1",
        "maj:min": "8:1",
        "fstype": "btrfs",
        "mountpoint": "/mnt/storagepools/sp_zos-cache",
        "label": "sp_zos-cache",
        "uuid": "884020ea-54dc-4e63-9d27-d37f28fe1b0f",
        "parttype": "0fc63daf-8483-4772-8e79-3d69d8477de4",
        "partlabel": "primary",
        "partuuid": "79b8def9-aec2-4f86-bece-afba45c482a5",
        "partflags": null,
        "ra": "128",
        "ro": "0",
        "rm": "0",
        "hotplug": "0",
        "model": "",
        "serial": "",
        "size": "1046478848",
        "state": null,
        "owner": "root",
        "group": "disk",
        "mode": "brw-rw----",
        "alignment": "0",
        "min-io": "512",
        "opt-io": "0",
        "phy-sec": "512",
        "log-sec": "512",
        "rota": "1",
        "sched": "cfq",
        "rq-size": "128",
        "type": "part",
        "disc-aln": "0",
        "disc-gran": "0",
        "disc-max": "0",
        "disc-zero": "0",
        "wsame": "0",
        "wwn": null,
        "rand": "1",
        "pkname": "sda",
        "hctl": null,
        "tran": "",
        "subsystems": "block:scsi:pci",
        "rev": null,
        "vendor": null
      }
    ],
    "start": 0,
    "end": 1048575999,
    "size": 1048576000,
    "blocksize": 512,
    "table": "gpt",
    "free": [
      {
        "start": 17408,
        "end": 1048575,
        "size": 1031168
      },
      {
        "start": 1047527424,
        "end": 1048559103,
        "size": 1031680
      }
    ]
  },
  {
    "name": "sr0",
    "kname": "sr0",
    "maj:min": "11:0",
    "fstype": "iso9660",
    "mountpoint": null,
    "label": "iPXE",
    "uuid": "2018-09-11-11-46-27-00",
    "parttype": null,
    "partlabel": null,
    "partuuid": null,
    "partflags": null,
    "ra": "128",
    "ro": "0",
    "rm": "1",
    "hotplug": "1",
    "model": "CD-ROM          ",
    "serial": "VB0-01f003f6",
    "state": "running",
    "owner": "root",
    "group": "cdrom",
    "mode": "brw-rw----",
    "alignment": "0",
    "min-io": "2048",
    "opt-io": "0",
    "phy-sec": "2048",
    "log-sec": "2048",
    "rota": "1",
    "sched": "cfq",
    "rq-size": "128",
    "type": "rom",
    "disc-aln": "0",
    "disc-gran": "0",
    "disc-max": "0",
    "disc-zero": "0",
    "wsame": "0",
    "wwn": null,
    "rand": "1",
    "pkname": null,
    "hctl": "0:0:0:0",
    "tran": "ata",
    "subsystems": "block:scsi:pci",
    "rev": "1.0 ",
    "vendor": "VBOX    ",
    "start": 0,
    "end": 0,
    "size": 0,
    "blocksize": 2048,
    "table": "",
    "free": null
  }
]
```
