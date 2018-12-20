import os
import json
import unittest
import subprocess
from configparser import ConfigParser
from testcases_base import BaseTest

def run_cmd(cmd):
    return subprocess.run([cmd], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
         
class ZosTest(BaseTest):

    """
    test cases to test using ZOS with virtualbaox instance 
    """

    @classmethod
    def setUpClass(cls): 
        """
            configures instance with name zosmachine on address 
        """
        default_init = run_cmd("zos configure --name=default_init --address={} --port=6379".format(self.Node))

    def setUp(self):
        pass

    def test01_setdefault(self):
        """
        check if certain node is used as default or not
        """
        set_default = run_cmd("zos setdefault default_init")
        # check if the default_init node is used as default or not
        parser = ConfigParser()
        parser.read("~/.config/zos.toml")
        node = parser.get('app', 'defaultzos')
        self.assertEqual(node,'default_init' , msg = "default_init node isn't set as default")

    def test02_ping(self):
        """
        test zos ping command 
        
        ./zos ping            
            "PONG Version: development @Revision: ffe97313ef00b018d3d66e3343d68fa107217df5"
        """
        ping = run_cmd("zos ping")
        testping = ping.stdout.decode()
        self.assertIn("PONG",testping, msg="the node isn't pingable")

    def test03_showconfig(self):
        """
            test showconfig command 
        """
        showconfig = run_cmd("zos showconfig")
        output = showconfig.stdout.decode()
        self.assertIn("defaultzos", output, msg="showconfig command isn't working correctly")

    def test04_showactive(self):
        """
            test showactive command
        """
        showactive = run_cmd("zos showactive")
        output = showactive.stdout.decode()
        self.assertIn("default_init", output, msg="default_init node is an active node")

    def test05_showactiveconfig(self):
        showactiveconfig = run_cmd("zos showactiveconfig")
        output_showactiveconfig = json.loads(showactiveconfig.stdout.decode())
        # need to check if the output contains (address, isvbox, port)
        self.assertIn("address", output_showactiveconfig, msg="wrong output the command should contain address part")
        self.assertIn("port", output_showactiveconfig, msg="wrong output the command should contain port part")
        self.assertIn("isvbox", output_showactiveconfig, msg="wrong output the command should contain isvbox part")

    def test06_cmd(self):
        """
            funcation to test command cmd in zos
        """
        test_cmd_node = run_cmd("zos cmd 'nft.list'")
        test_cmd_node_output = test_cmd_node.stdout.decode()
        self.assertIn("tcp", test_cmd_node_output, msg="cmd doesn't working correctly")

    def test07_create_container(self): 
        """
            test create container 
            connect to vm instance remotely using js9 client and check the new created vms 
        """
        container = run_cmd("zos container new --name=container")
        con_num = self.list_con(container)
        self.assertTrue(con_num, msg="container isn't created correctly")

    def test08_containers_list(self):     
        """
            test list containers
        """
        container_list = run_cmd("zos container list --json")
        output_container_list = container_list.stdout.decode()
        self.assertIn("id", output_container_list, msg="container list output should contain id part")
        self.assertIn("cpu", output_container_list, msg="container list output should contain cpu part")
        self.assertIn("root", output_container_list, msg="container list output should contain root part")
        self.assertIn("storage", output_container_list, msg="container list output should contain storage part")
        self.assertIn("pid", output_container_list, msg="container list output should contain pid part")
        self.assertIn("ports", output_container_list, msg="container list output should contain ports part")
    
    def test09_container_sshinfo(self):
        """
            show ssh info for certain container
        """
        container_ssh_info = run_cmd("zos container sshinfo")
        # check if it return a vaild ip or not
        ip = container_ssh_info.stdout.decode().split()[len(container_ssh_info.stdout.decode().split()) - 3].split("@")[1]
        port = container_ssh_info.stdout.decode().split()[len(container_ssh_info.stdout.decode().split()) - 1]   
        ip_check = str(ip)
        self.assertIn(self.Node, ip_check, msg = "it's not an vaild ip")
        return port

    def test10_file_upload(self):
        """
            function to test upload for files to certain container
        """
        # create file to test upload function
        os.system('touch /tmp/test_upload')
        file_upload = run_cmd("zos container upload /tmp/test_upload /tmp/")
        # test if the file is uploaded or not using ssh
        port = self.test08_container_sshinfo()
        check_upload = os.system("ssh root@{} -p {} 'ls /tmp/ | grep test_upload'".format(self.Node, port))
        self.assertEqual(check_upload, 0, msg="upload function isn't working correctly")
    
    def test11_file_download(self):
        """
            function to test download for files to certain continer
        """ 
        file_download = run_cmd("zos container download /etc/profile /tmp/test_download")
        check_download = os.path.isfile('/tmp/test_download')
        self.assertTrue(check_download, msg="download function isn't working correctly")
    
    def test12_exec(self):
        """
            function to test exec cmd
        """
        exec_cmd = run_cmd("zos container exec 'touch /tmp/test_exec'")
        port = self.test08_container_sshinfo()
        check_exec = os.system("ssh root@10.102.147.99 -p {} 'ls /tmp/ | grep test_exec'".format(port))
        self.assertEqual(check_exec, 0, msg="exec function isn't working correctly")
        
    def test13_container_mount(self):
        """
            test mount command 
        """
        os.system("mkdir /tmp/testmount")
        test_container_mount = run_cmd("zos container mount / /tmp/testmount")
        test_mount = os.path.ismount("/tmp/testmount")
        self.assertTrue(test_mount, msg="mount point isn't set true")

    def test14_container_delete(self):
        """
            test delete container function
        """
        self.create_container(test_del)
        con_number = self.list_container(test_del)
        delete_container = run_cmd("zos container {} delete".format(con_number))  
        # check the list of containers on zos node
        con_number = self.list_container(test_del)
        self.assertFalse(con_number, msg="container doesn't deleted correctly")
        
    def tearDown(self):
        pass
        
    @classmethod
    def tearDownClass(cls):
        # delete container from zero-os node
        con_number = self.list_con(container)
        delete_container = run_cmd("zos container {} delete".format(con_number))  
        # delete zos node instance
        default_init_remove = run_cmd("zos remove --name=default_init")
               
    if __name__ == '__main__':
        unittest.main()
