nimble zosbuild && ./zos container list && ./zos container new --name=mycont --root="https://hub.grid.tf/tf-bootable/ubuntu:lts.flist" 
# nimble zosbuild && ./zos container list && ./zos container new --name=mycont --root="https://hub.grid.tf/tf-official-apps/ubuntu-bionic-build.flist" --extraconfig='{"port":{"2215":22}, "config":{}, "nics":[{"type":"default"}]}'
./zos container list