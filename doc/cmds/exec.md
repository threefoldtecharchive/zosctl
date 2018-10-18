# zos exec
Executes bash command in zero-os machine (can be very dangerous)


```
~> ./zos exec 'ls /roota -alh'
ls: /roota: No such file or directory


~> ./zos exec 'ls /root -alh 
total 0
drwxr-xr-x    3 root     root          60 Oct 14 13:44 .
drwxrwxrwt   14 root     root         340 Oct 16  2018 ..
drwx------    2 root     root          60 Oct 14 13:44 .ssh

```