
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