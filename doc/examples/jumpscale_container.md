
```bash

export name="jumpscale"
#install jumpscale container
# zos container new --name=jumpscale_build --root="https://hub.grid.tf/tf-official-apps/ubuntu-bionic-build.flist"

#example 0robot 
zos container new --name=zrobot --root="https://hub.grid.tf/tf-autobuilder/threefoldtech-0-robot-autostart-development-00c7c736c0.flist"

zos container sshenable

#cannot do dynamic yet, need to fill in
export IPADDR=10.244.90.194


#install pip3 (python package installer)
ssh -A root@$IPADDR "apt update;apt upgrade -y;apt install python3-pip -y"

#install jumpscale 
export BRANCH=development_960
export BRANCH=development_simple_
ssh -A root@$IPADDR "curl https://raw.githubusercontent.com/threefoldtech/jumpscale_core/$BRANCH/install.sh?$RANDOM > /tmp/install_jumpscale.sh;bash /tmp/install_jumpscale.sh"

```
