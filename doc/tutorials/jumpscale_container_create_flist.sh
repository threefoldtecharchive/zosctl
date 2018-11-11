set -ex 

sh jumpscale_container_fresh_install.sh

#NOW PUT INSTRUCTIONS HERE IN js9 or other to create flist on public TF hub so people can install from this flist

zos container exec 'curl https://gist.githubusercontent.com/xmonader/9ff372fa62ec6e63cefb769c8b85b87c/raw/eb19fa951a05db5f8a8013f6270661ec2b6fbc5a/create_js9_flist.sh > /tmp/create_js9_flist.sh'
zos container exec 'bash /tmp/create_js9_flist.sh'

#maybe first some cleanup instructions (find->delete)

