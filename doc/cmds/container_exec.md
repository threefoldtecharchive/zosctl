# container <id> 'CMD'

```bash

~> ./zos container exec 'ls /root -alh'


total 184K
drwx------ 1 root root   60 Oct 18 16:25 .
drwxr-xr-x 1 root root   36 Oct 18 16:24 ..
-rw------- 1 root root    5 Oct 18 16:24 .bash_history
-rw-r--r-- 1 root root 3.1K Oct 22  2015 .bashrc
drwx------ 1 root root   40 Oct 18 16:24 .cache
-rw-r--r-- 1 root root  148 Aug 17  2015 .profile
drwx------ 1 root root   30 Oct 18 16:24 .ssh
-rw-r--r-- 1 root root 180K Oct 18 16:25 zos.log
```

```bash
~> ./zos container exec 'hostname'
reem2
```

```bash
~> ./zos container exec 'ls /rootaa -alh'
ls: cannot access '/rootaa': No such file or directory

```

