authkeys=$(cat ~/.ssh/authorized_keys)
./zos containers-list

./zos containers-new -n cont2 --root https://hub.grid.tf/thabet/busyssh.flist -p --extraconfig  '{"port":{"2215":22}, "config":{}, "nics":[{"type":"default"}]}' --authorizedkeys ~/.ssh/authorized_keys
# ./zos containers-list