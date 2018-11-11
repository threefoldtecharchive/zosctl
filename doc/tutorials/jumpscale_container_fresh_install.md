
example basic script how to install a full local jumpscale

```bash

export name="jumpscale"
#get container
zos container new --name=js9 

zos container sshenable

#not really needed but good practice
zos container exec "apt update;apt upgrade -y"

#install jumpscale 
zos container exec "curl https://raw.githubusercontent.com/threefoldtech/jumpscale_core/development_960/install.sh?$RANDOM > /tmp/install_jumpscale.sh;bash /tmp/install_jumpscale.sh"

#to follow progress go to other command line and do
zos container exec "tail -f /tmp/jumpscale_install.log"
```
