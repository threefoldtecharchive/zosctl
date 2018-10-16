
```bash

export name="jumpscale"

#install jumpscale container
zos container new --name=$name --root="https://hub.grid.tf/tf-official-apps/ubuntu-bionic-build.flist"
export NR=2

zos container $NR  sshenable

#cannot do dynamic yet, need to fill in
export IPADDR=10.244.90.194


#install pip3 (python package installer)
ssh -A root@$IPADDR "apt update;apt upgrade -y;apt install python3-pip -y"

#install jumpscale
ssh -A root@$IPADDR "curl https://raw.githubusercontent.com/threefoldtech/jumpscale_core/development_simple/install.sh?$RANDOM > /tmp/install_jumpscale.sh;bash /tmp/install_jumpscale.sh"

```