# Troubleshooting guide

## IO timeouts or can't look up hub.grid.tf

If you're getting errors like this one
```bash
./zos container new                                                                                                           ✔  ahmed@ahmedheaven
INFO preparing container
INFO sending instructions to host

STDOUT:

STDERR:

DATA:
"mount-root-flist(Get https://hub.grid.tf/tf-bootable/ubuntu:18.04.flist: dial tcp: lookup hub.grid.tf on 10.0.2.3:53: read udp 10.0.2.15:56159-\u003e10.0.2.3:53: i/o timeout)"

```
Most likely your /etc/resolv.conf isn't configured correctly

### Fix
update your resolv.conf with nameserver like `8.8.8.8`
```bash
./zos exec 'echo nameserver 8.8.8.8 > /etc/resolv.conf'
```

## OpenSSL on Mac

Having version less than 1.1 will require an upgrade (or at least having the new version available on the system)

### Fix

- `brew install openssl@1.1`
- build the binary
```bash
nim c -d:ssl  --dynlibOverride:ssl --dynlibOverride:crypto --threads:on --passC:'-I/usr/local/opt/openssl\@1.1/include/' --passL:'-lssl -lcrypto -lpcre' --passL:'-L/usr/local/opt/openssl\@1.1/lib/' src/zos.nim
```
- `cp src/zos /usr/local/bin`



##  virtualbox gives -s unknown option 

Most likely your virtualbox is outdated (make sure you have >= 5.2)

## sshtools not installed
zos requires `sshfs`, `scp`, `ssh` dependencies 