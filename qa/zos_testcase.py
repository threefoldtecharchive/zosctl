import os
import json
import unittest
import subprocess
from jumpscale import j
from configparser import ConfigParser

class SimpleTest(unittest.TestCase):

    """
    test cases to test using ZOS with virtualbaox instance 
    """
    @classmethod
    def setUpClass(cls):
        """
        create VM instance and then create containers on top of it 
        """
        self.default_init = subprocess.run(["./zos init --name=default_init --port=12345 --reset"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        self.default_init_1 = subprocess.run(["./zos init --name=default_init_1 --port=123456 --reset"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)


    def setUp(self):
        pass

    def test_setdefault():
        """
        check if certain node is used as default or not
        """
        set_default = subprocess.run(["./zos setdefault default_init"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # check if the default_init node is used as default or not
        parser = ConfigParser()
        parser.read("~/.config/zos.toml')
        node = parser.get('app', 'defaultzos')
        assertEqual(node,'default_init' , msg = "default_init node is set as default")   # check with Thabet

    def test_ping(self):
        """
        test zos ping command 
        
        ./zos ping            
            "PONG Version: development @Revision: ffe97313ef00b018d3d66e3343d68fa107217df5"
        """
        ping = subprocess.run(["./zos ping"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        testping = ping.stdout.decode().split()
        self.assertIn("PONG",testping, msg="the node is pingable")

    def test_showconfig(self):
        """
            test showconfig command 
        """
        showconfig =  subprocess.run(["./zos showconfig"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        output = showconfig.stdout.decode()
        self.assertIn("defaultzos", output, msg="showconfig command is working correctly")

    def test_showactive(self):
        """
            test showactive command
        """
        showactive =  subprocess.run(["./zos showactive"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        output = showactive.stdout.decode()
        self.assertIn("default_init", output, msg="default_init node is an active node")

    def test_showactiveconfig(self):
        showactiveconfig =  subprocess.run(["./zos showactiveconfig"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        output = json.loads(showactiveconfig.stdout.decode())
        # need to check if the output contains (address, isvbox, port)
        if 'address' and 'isvbox' and 'port' not in output:
            raise ValueError("wrong output") 

    def test_create_container(): 
        """
            test create container 
            connect to vm instance remotely using js9 client and check the new created vms 
        """
        container1 =  subprocess.run(["./zos container new --name=container1 --root=https://hub.grid.tf/thabet/redis.flist"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        container2 =  subprocess.run(["./zos container new --name=container2"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        test_con = j.clients.zos.get('test', data={'host':'127.0.0.1', 'port':'12345'})
        con_list = test_con.containers.list()
        self.assertIn("3" and "2", con_list.keys(), msg="two containers are created correctly")
        
    def test_containers_list(self):    
        """
            test list containers
        """
        container_list = subprocess.run(["./zos container list --json"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) # need to test the output 
        
    def test_containers_info(self):
        """
        show summarized container info
        """
        container_info = subprocess.run(["./zos container info"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        container_info_json = subprocess.run(["./zos container info --json"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)  
        # showing info for certain container (need to check if it will passed to this function as list or string)
        con_num = self.test_create_container()
        container_info_ID = subprocess.run(["./zos container {} info".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        # need to check container list

    def test_containers_inspect(self):
        """
            inspect the current running 
            container (showing full info)
        """
        con_num = self.test_create_container()
        container_inspect = subprocess.run(["./zos container inspect"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        container_inspect_ID = subprocess.run(["./zos container {} inspect".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
    
    def test_container_sshinfo(self):
        """
            show ssh info for certain container
        """
        con_num = self.test_create_container()
        container_ssh_info = subprocess.run(["./zos container sshenable"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        container_ssh_info_ID = subprocess.run(["./zos container {} sshenable".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 

    def test_zerotier(self):   # may be not exist anymore 
        """
            zerotier info for certain container 
        """
        con_num = self.test_create_container()
        container_zerotierinfo = subprocess.run(["./zos container {} zerotierinfo".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        container_zerotierinfo_no_id = subprocess.run(["./zos container zerotierinfo"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        container_zerotierlist = subprocess.run(["./zos container {} zerotierlist".format(con_num)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        container_zerotierlist_no_id = subprocess.run(["./zos container zerotierlist"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    def test_container_sshinfo():

    def file_transfer(self):
        """
            function to test upload & download for 
            files and directories from and to certain continer
        """
        con_num = self.create_container()
        # create file to test upload function
        file_test = os.system('touch /tmp/test') 
        file_upload_file = subprocess.run(["./zos container upload /tmp/test /tmp/"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # check if the file is uploaded correctly or not using zos exec command line



    def tearDown(self):
        pass

    @classmethod
    def tearDownClass(cls):
        # delete the vm instance
        container_list = subprocess.run(["zos remove --name=default_init"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    if __name__ == '__main__':
        unittest.main()