# container <id> mount SRC DEST

Mounting container directory through ssh fuse filesystem `sshfs`


```
 ./zos container mount /root /tmp/cont-root2                           ✔  ahmed@ahmedheaven
INFO sshing to container 6 on local
[3/4] Waiting for private network connectivity
~>  mount | grep cont-root2                   
root@10.244.50.38:/root on /tmp/cont-root2 type fuse.sshfs (rw,nosuid,nodev,relatime,user_id=1000,group_id=1000)

echo 'FROM HERE' > /tmp/cont-root2/amessage                           ✔  ahmed@ahmedheaven
~>  ./zos container exec 'ls /'               
[3/4] Waiting for private network connectivity
 * sshd is running

bin
boot
coreX
dev
etc
home
initrd.img
initrd.img.old
lib
lib64
media
mnt
opt
proc
root
run
sbin
srv
sys
tmp
usr
var
vmlinuz
vmlinuz.old
~>  ./zos container exec 'ls /root'           
[3/4] Waiting for private network connectivity
 * sshd is running

amessage
imhere
imhere2
~>  ./zos container exec 'cat /root/amessage' 
[3/4] Waiting for private network connectivity
 * sshd is running

FROM HERE

```
## errors
Need to have `sshfs` installed on your machine.