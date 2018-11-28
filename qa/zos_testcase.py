import os
import json
import unittest
import subprocess
from jumpscale import j
from netaddr import valid_ipv4
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
        default_init = subprocess.run(["./zos init --name=default_init --port=12345 --reset"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        default_init_1 = subprocess.run(["./zos init --name=default_init_1 --port=123456 --reset"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

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
        assertEqual(node,'default_init' , msg = "default_init node is set as default")   # check with Thabet about the file

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
        output_showactiveconfig = json.loads(showactiveconfig.stdout.decode())
        # need to check if the output contains (address, isvbox, port)
        self.assertIn("address", output_showactiveconfig, msg=None)
        self.assertIn("port", output_showactiveconfig, msg=None)
        self.assertIn("isvbox", output_showactiveconfig, msg=None)

    def test_create_container(): 
        """
            test create container 
            connect to vm instance remotely using js9 client and check the new created vms 
        """
        container1 =  subprocess.run(["./zos container new --name=container1 --root=https://hub.grid.tf/thabet/redis.flist"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        container2 =  subprocess.run(["./zos container new --name=container2"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        test_con = j.clients.zos.get('test', data={'host':'127.0.0.1', 'port':'12345'})
        con_list = test_con.containers.list()
        self.assertIn("2", con_list, msg="first container is created correctly")
        self.assertIn("3", con_list, msg="second container is created correctly")

    def test_containers_list(self):     
        """
            test list containers
        """
        container_list = subprocess.run(["./zos container list --json"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        output_container_list = json.loads(container_list.stdout.decode())
        self.assertIn("id", output_container_list, msg=None)
        self.assertIn("cpu", output_container_list, msg=None)
        self.assertIn("root", output_container_list, msg=None)
        self.assertIn("storage", output_container_list, msg=None)
        self.assertIn("pid", output_container_list, msg=None)
        self.assertIn("ports", output_container_list, msg="container list command is working correctly")

    def test_container_sshinfo(self):
        """
            show ssh info for certain container
        """
        container_ssh_info = subprocess.run(["./zos container sshenable"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 
        username = container_ssh_info.stdout.decode().split("\n")[6].startswith("root") # check if it starts with root word 
        self.assertTrue(username, True, msg=None)
        ip = container_ssh_info.stdout.decode().split("\n")[6].split(" ")[0].split("@")[1]
        ip_check = valid_ipv4(ip)
        self.assertTrue(ip_check, True, msg=None)

    def file_upload(self):
        """
            function to test upload for files to certain continer
        """
        # create file to test upload function
        file_test = os.system('touch /tmp/test') 
        file_upload_file = subprocess.run(["./zos container upload /tmp/test /tmp/"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # check if the file is uploaded correctly or not using zos exec command line

    def container_mount(self):
        """
            test mount command 
        """
        os.system("mkdir /tmp/testmount")
        test_container_mount = subprocess.run(["./zos container mount / /tmp/testmount"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        os.system("ls /tmp/ | grep testmount")
        

    def container_delete(self):
        """
            test delete container function
        """
        # delete the last container (container 3) which i just created
        delete_container = subprocess.run(["./zos container delete"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # check the list of containers on vm instance node
        test_con = j.clients.zos.get('test', data={'host':'127.0.0.1', 'port':'12345'})
        con_list = test_con.containers.list()
        ########--> 
    
    def tearDown(self):
        pass

    @classmethod
    def tearDownClass(cls):
        # delete the vm instance
        default_init_remove = subprocess.run(["zos remove --name=default_init"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        default_init_1_remove = subprocess.run(["zos remove --name=default_init_1"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    if __name__ == '__main__':
        unittest.main()