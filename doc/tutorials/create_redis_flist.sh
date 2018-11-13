sh jumpscale_container_fresh_install.sh

#NOW PUT INSTRUCTIONS HERE IN js9 or other to create flist on public TF hub so people can install from this flist

sudo umount /tmp/container-tmp
zos container exec 'rm -rf /tmp/redisdata'
zos container exec 'curl https://gist.githubusercontent.com/muhamadazmy/9648e483952c092f9e49b13c34dc3518/raw/2190cef40e75dda44112ac9d31840c958980cd16/copy-chroot.sh > /usr/bin/copy-chroot'
zos container exec 'chmod +x /usr/bin/copy-chroot && apt-get install redis-server redis-tools -y && mkdir /tmp/redisdata'
zos container exec '/usr/bin/copy-chroot /usr/bin/redis-server /tmp/redisdata && /usr/bin/copy-chroot /usr/bin/redis-cli /tmp/redisdata'
zos container exec 'cd /tmp/redisdata && tar -czf redisflist.tar.gz .' 
zos container exec 'mv /tmp/redisdata/redisflist.tar.gz /tmp/'
mkdir -p /tmp/container-tmp
zos container mount /tmp /tmp/container-tmp

echo "Flist available on /tmp/container-tmp/redisflist.tar.gz"

#maybe first some cleanup instructions (find->delete)

