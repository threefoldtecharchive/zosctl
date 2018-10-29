
set -ex
rm /usr/local/bin/zos

#brew install nim 
#mkdir -p  ~/code/github;cd ~/code/github
#git clone https://github.com/threefoldtech/zos 
#cd zos
sudo nimble build -d:ssl --threads:on
sudo cp zos /usr/local/bin
