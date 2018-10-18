
### Getting SSH info

shows ssh connection string to the container `./zos container 2 sshinfo`
```bash
./zos container 189 sshinfo 
root@10.244.163.53 -i /home/ahmed/.ssh/id_rsa


```

> also it works against the latest container created by zos 
```bash
./zos container sshinfo
root@10.244.163.53 -i /home/ahmed/.ssh/id_rsa
````

