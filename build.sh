rm -f /usr/local/bin/zos
# export NIM_LIB_PREFIX
# export NIMBLE_DIR
export PATH=$HOME/.nimble/bin:/usr/local/bin:/usr/bin:/bin
export NIM_LIB_PREFIX=$HOME/.nimble/lib
export NIMBLE_DIR=$HOME/.nimble

sudo nimble uninstall zos -y > /dev/null 2>&1
sudo nimble uninstall redisclient -y  > /dev/null 2>&1
sudo nimble uninstall redisparser -y > /dev/null 2>&1
rm -f /tmp/nimblecache/nimblepkg/*

set -ex
nimble install redisclient@#head

brew install openssl@1.1

sudo nim c -d:ssl  --dynlibOverride:ssl --dynlibOverride:crypto --threads:on --passC:'-I/usr/local/opt/openssl\@1.1/include/' --passL:'-lssl -lcrypto -lpcre' --passL:'-L/usr/local/opt/openssl\@1.1/lib/' src/zos.nim

sudo cp src/zos /usr/local/bin/zos
