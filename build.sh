rm /usr/local/bin/zos
# export NIM_LIB_PREFIX
# export NIMBLE_DIR
export PATH=$HOME/.nimble/bin:/usr/local/bin:/usr/bin:/bin
export NIM_LIB_PREFIX=$HOME/.nimble/lib
export NIMBLE_DIR=$HOME/.nimble

sudo nimble uninstall zos - y
sudo nimble uninstall redisclient -y 
sudo nimble uninstall redisparser -y

nimble install redisclient@#head

brew install openssl@1.1

# redisclient & redisparser must be 0.1.1
nimble uninstall redisclient
nimble uninstall redisparser
sudo nim c -d:ssl  --dynlibOverride:ssl --dynlibOverride:crypto --threads:on --passC:'-I/usr/local/opt/openssl\@1.1/include/' --passL:'-lssl -lcrypto -lpcre' --passL:'-L/usr/local/opt/openssl\@1.1/lib/' src/zos.nim

# sudo nimble build -d:ssl --threads:on
# sudo nimble build -d:openssl10 --threads:on

sudo cp src/zos /usr/local/bin/zos
