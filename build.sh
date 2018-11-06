rm /usr/local/bin/zos
# export NIM_LIB_PREFIX
# export NIMBLE_DIR
export PATH=$HOME/.nimble/bin:/usr/local/bin:/usr/bin:/bin
export NIM_LIB_PREFIX=$HOME/.nimble/lib
export NIMBLE_DIR=$HOME/.nimble
set -ex

export LDFLAGS="-L/usr/local/opt/openssl/lib"
export CPPFLAGS="-I/usr/local/opt/openssl/include"
export DYLD_LIBRARY_PATH="/usr/local/opt/openssl/lib"

sudo nimble build -d:ssl --threads:on
sudo cp zos /usr/local/bin
