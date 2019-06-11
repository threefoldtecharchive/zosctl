# container <id> invoke 'CMD'

Invokes `runs` command on container using 0-core system without waiting for its exit.
 
```bash

~> ./zos container new --name=zerodb5 --root=https://hub.grid.tf/tf-official-apps/threefoldtech-0-db-release-1.0.0.flist --hostname=zerodb5
INFO preparing container
INFO sending instructions to host
INFO container 17 is created.
INFO creating portforward from 1030 to 22
INFO waiting for private network connectivity
container private address: 192.168.56.101

~> ./zos exec 'ip netns exec 17 netstat -nltp '
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 172.18.0.18:26861       0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 127.0.0.1:26861         0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 172.18.0.18:27343       0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 172.18.0.18:27344       0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 ::1:26861               :::*                    LISTEN      2908/zerotier-one

~> ./zos container 17 invoke '/bin/zdb'       
~> ./zos exec 'ip netns exec 17 netstat -nltp '
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 0.0.0.0:9900            0.0.0.0:*               LISTEN      2928/zdb
tcp        0      0 172.18.0.18:26861       0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 127.0.0.1:26861         0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 172.18.0.18:27343       0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 172.18.0.18:27344       0.0.0.0:*               LISTEN      2908/zerotier-one
tcp        0      0 ::1:26861               :::*                    LISTEN      2908/zerotier-one
```

