
## Building the project

### Nim installation
https://nim-lang.org/install.html (0.19 is required)

#### Nimble installation
https://github.com/nim-lang/nimble#installation (0.9 is required)

### build zos

- clone `git clone https://github.com/threefoldtech/zosctl`
- switch to directory `cd zos` 
- we need to make sure that redisclient and redisparser on 0.1.1 
`nimble uninstall redisclient`

`nimble uninstall redisparser`, then
- build using `nimble zos`

#### Building on OSX 

execute `nimble zosMac`

or invoke the `build.sh` script manually 

```bash
#example script to install

brew install nim 
mkdir -p  ~/code/github;cd ~/code/github
git clone https://github.com/threefoldtech/zos 
cd zos
sudo nimble build -d:ssl --threads:on
sudo cp zos /usr/local/bin
```
> You can use install_osx.sh the repository


##### OpenSSL problems on Mac 
Having version less than 1.1 will require an upgrade (or at least having the new version available on the system)

- `brew install openssl@1.1`
- build the binary
```bash
nim c -d:ssl  --dynlibOverride:ssl --dynlibOverride:crypto --threads:on --passC:'-I/usr/local/opt/openssl\@1.1/include/' --passL:'-lssl -lcrypto -lpcre' --passL:'-L/usr/local/opt/openssl\@1.1/lib/' src/zos.nim
```
- `cp src/zos /usr/local/bin`


#### Generating docs
- we have task `genDocs` to generate html code documentation in `src/htmldocs` and it's invoked using `nimble genDocs`
- browsable from `src/htmldocs` or https://htmlpreview.github.io/?https://raw.githubusercontent.com/threefoldtech/zos/development/src/htmldocs/commons/app.html


