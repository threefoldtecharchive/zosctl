import os
import json
import subprocess

class Zos_Control:
    def __init__(self):
        self.node="10.102.64.213"

    def conf_node_virtualbox(self):
        # create zos node locally using VirtualBox
        conf_node_VB = subprocess.run(["zos init --name=new"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # removes zero-os virtualbox machine
        remove_node_VB = subprocess.run(["zos remove --name=new"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    def zos_showconfig():
        zos_showconfig = subprocess.run(["zos showconfig"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        print(zos_showconfig.stdout.decode())

    def conf_node():
        try:
            conf_node1 = subprocess.run(["zos configure --name=node1 --address=self.node --port=6379"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
            conf_node2 = subprocess.run(["zos configure --name=node2 --address=self.node --port=6379 --setdefault"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) # need to try it with more options
            node_reach = subprocess.run(["zos ping"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) # need to check this part        
        except subprocess.CalledProcessError as err:
            print('ERROR:', err)
            exit

    def zos_setdefault():
        node_setdefault = subprocess.run(["zos setdefault node1"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    def zoshost_exec():
        zos_host_exec = subprocess.run(["zos exec 'ls /root -al'"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        print(zos_host_exec.stdout.decode())

    def cmd():
        zos_cmd = subprocess.run(["zos cmd 'core.ping'"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        print(zos_cmd.stdout.decode())

    def create_container():
        """ 
            this function to create container on certain node 
            and this function return continer ID
        """
        container = subprocess.run(["zos container new --name=test_create --root=https://hub.grid.tf/thabet/redis.flist"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) # need to try more options here 
        # print putput of continer 
        print(container.stdout.decode())
        # return continer ID
        container_num = container.stdout.decode().split("\n")[2].split(":")[-1]
        return container_num

    def containers_inspect(self):
        """
            inspect the current running 
            container (showing full info)
        """
        con_num = self.create_container()
        container_inspect = subprocess.run(["zos container inspect"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        container_inspect_ID = subprocess.run(["zos container {} inspect".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    def containers_info(self):
        """
            show summarized container info
        """
        container_info = subprocess.run(["zos container info"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        container_info_json = subprocess.run(["zos container info --json"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        # zos container list --json (alias to `zos container info`)
        container_list = subprocess.run(["zos container list --json"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        # showing info for certain container
        con_num = self.create_container()
        container_info_ID = subprocess.run(["zos container {} info".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 

    def continer_sshinfo(self):
        """
            show ssh info for certain container
        """
        con_num = self.create_container()
        container_ssh_info = subprocess.run(["zos container sshenable"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        container_ssh_info_ID = subprocess.run(["zos container {} sshenable".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 

    def continer_delete(self):
        """
            function to delete container
        """
        con_num = self.create_container()
        continer_delete = subprocess.run(["zos container {} delete".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
     
    def zerotier(self):
        """
            zerotier info for certain container 
        """
        con_num = self.create_container()
        container_zerotierinfo = subprocess.run(["zos container {} zerotierinfo".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        container_zerotierlist = subprocess.run(["zos container {} zerotierlist".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    def file_transfer(self):
        """
            function to test upload & download for 
            files and directories from and to certain continer
        """
        con_num = self.create_container()
        # create file to test upload function
        file_test = os.system('touch /tmp/test') # need to check first if it created or not
        file_upload_file = subprocess.run(["zos container upload /tmp/test /tmp/"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        file_upload_file_id = subprocess.run(["zos container {} upload /tmp/test /tmp/".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # add download code 

    # shell & execute functions 
        """
            zos container shell  
            zos container <id> shell
            zos container <id> exec <command>
            zos container exec <command>
            zos container <id> zosexec <command> 
        """


