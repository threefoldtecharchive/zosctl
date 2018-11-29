## errorcodes module contains all error codes (exit codes) zos can exit with 


let cantCreateConfigDir* = 1                     ## Can't create configuration directory
let sshKeyNotFound* = 2                          ## ssh key wasn't found.
let containerNotFound* = 3                       ## Container isn't found
let vboxNotInstalled* = 4                        ## Virtualbox isn't installed
let unconfiguredZos* = 5                         ## Zos is unconfigured
let unknownCommand* = 6                          ## Unknown command
let depsNotInstalled* = 7                        ## Zos dependencies aren't installed.
let portForwardExists* = 8                       ## Portforward exists already
let cantFindSshKeys* = 9                         ## Can't find sshkeys.
let sshIsntEnabled* = 10                         ## SSH isn't enabled
let fileDoesntExist* = 11                        ## File Doesn't exist.
let unreachableZos* = 12                         ## Zos is unreachable
let cantCreateContainer* = 13                    ## Can't create container 
let generalError* = 14                           ## General Error (check zos.log for more debugging information)
let malformedArgs* = 15                          ## Arguments passed are incorrect 
let containerDoesntExist* = 16                   ## Cibtauber doesn't exist.
let instanceNotConfigured* = 17                  ## Instance not configured
let pathAlreadyMounted* = 18                     ## Path is already mounted
let noHostonlyInterface* = 19                    ## Virtualbox machine is started without hostonly interface
let didntCreateZosContainersYet* = 20            ## Didn't create any containers using zos yet.
let noHostOnlyInterfaceIp* = 21                  ## Can't resolve hostonly interface IP
let invalidMachineName* = 22                     ## Invalid machine name
let cantGetZerotierInfo* = 23                    ## Can't get zerotier information
let cmdFailed* = 24                              ## command execution failed
let cantReservePort* = 25                        ## Can't reserve port
let invalidJwt* = 26                             ## JWT is invalid
let cantPingZos* = 27                            ## Can't ping Zero-OS machine
