
# Upload files 

```bash
~> ./zos container exec 'ls /tmp' 

ztkey
~>  echo "MYUPLOADED FILE" > /tmp/myfile
~>  ./zos container upload /tmp/myfile /tmp 
scp  /tmp/myfile root@10.244.104.71:/tmp 
myfile                                                       100%   16    11.0KB/s   00:00    
~>  ./zos container exec 'ls /tmp'
myfile
ztkey
~>  ./zos container exec 'cat /tmp/myfile'
MYUPLOADED FILE
```


# Upload dirs

```bash

./zos container upload ~/wspace/zos/src/ /root/




 * Starting OpenBSD Secure Shell server sshd
   ...done.

scp -r /home/ahmed/wspace/zos/src/ root@10.244.203.46:/root/
errorcodes.nim                                                                   100%  615     6.2KB/s   00:00
apphelp.nim                                                                      100% 6229    41.7KB/s   00:00
settings.nim                                                                     100%   97     1.4KB/s   00:00
sshexec.nim                                                                      100% 1269    15.5KB/s   00:00
zos                                                                              100% 3199KB  91.4KB/s   00:35

zos                                                                              100% 3199KB  88.9KB/s   00:36
zos                                                                              100% 3199KB  60.4KB/s   00:53
vbox.nim                                                                         100% 9494    54.4KB/s   00:00
zosclient.nim                                                                    100% 5051    39.8KB/s   00:00
zos.nim                                                                          100%   28KB  63.8KB/s   00:00



 ./zos container exec 'ls /root/src -alh'
 * Starting OpenBSD Secure Shell server sshd
   ...done.

total 3.2M
drwxrwxr-x 1 root root   70 Oct 22 18:26 .
drwx------ 1 root root   52 Oct 22 18:25 ..
drwxrwxr-x 1 root root   16 Oct 22 18:26 vboxpkg
-rwxr-xr-x 1 root root 3.2M Oct 22 18:26 zos
drwxrwxr-x 1 root root   96 Oct 22 18:25 zosapp
drwxrwxr-x 1 root root   26 Oct 22 18:26 zosclientpkg
-rw-r--r-- 1 root root  29K Oct 22 18:26 zos.nim
```