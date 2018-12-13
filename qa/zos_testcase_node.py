import os
import json
import unittest
import subprocess
from jumpscale import j
from configparser import ConfigParser

def run_cmd(cmd):
    return subprocess.run([cmd], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

# create func which create a container using 0-OS and return the container id
def con_num(machine_name):
    test_con = j.clients.zos.get('test', data={'host':'10.102.147.99', 'port':'6379'})
    test_con.containers.create("test_del", "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist")
    containers = test_con.containers.list()
    for con in containers:               
        if con.name == machine_name:
            return con.id
         
class SimpleTest(unittest.TestCase):

    """
    test cases to test using ZOS with virtualbaox instance 
    """

    @classmethod
    def setUpClass(cls): 
        """
            configures instance with name zosmachine on address 
        """
        default_init = run_cmd("/usr/sbin/zos configure --name=default_init --address=10.102.147.99 --port=6379")

    def setUp(self):
        pass

    def test01_setdefault(self):
        """
        check if certain node is used as default or not
        """
        set_default = run_cmd("/root/zos setdefault default_init")
        # check if the default_init node is used as default or not
        parser = ConfigParser()
        parser.read("/root/.config/zos.toml")
        node = parser.get('app', 'defaultzos')
        self.assertEqual(node,'default_init' , msg = "default_init node isn't set as default")

    def test02_ping(self):
        """
        test zos ping command 
        
        ./zos ping            
            "PONG Version: development @Revision: ffe97313ef00b018d3d66e3343d68fa107217df5"
        """
        ping = run_cmd("/usr/sbin/zos ping")
        testping = ping.stdout.decode()
        self.assertIn("PONG",testping, msg="the node isn't pingable")

    def test_showconfig(self):
        """
            test showconfig command 
        """
        showconfig = run_cmd("/usr/sbin/zos showconfig")
        output = showconfig.stdout.decode()
        self.assertIn("defaultzos", output, msg="showconfig command isn't working correctly")

    def test03_showactive(self):
        """
            test showactive command
        """
        showactive = run_cmd("/usr/sbin/zos showactive")
        output = showactive.stdout.decode()
        self.assertIn("default_init", output, msg="default_init node is an active node")

    def test04_showactiveconfig(self):
        showactiveconfig = run_cmd("/usr/sbin/zos showactiveconfig")
        output_showactiveconfig = json.loads(showactiveconfig.stdout.decode())
        # need to check if the output contains (address, isvbox, port)
        self.assertIn("address", output_showactiveconfig, msg="wrong output the command should contain address part")
        self.assertIn("port", output_showactiveconfig, msg="wrong output the command should contain port part")
        self.assertIn("isvbox", output_showactiveconfig, msg="wrong output the command should contain isvbox part")

    def test05_cmd(self):
        """
            funcation to test command cmd in zos
        """
        test_cmd_node = run_cmd("/usr/sbin/zos cmd 'nft.list'")
        test_cmd_node_output = test_cmd_node.stdout.decode()
        self.assertIn("tcp", test_cmd_node_output, msg="cmd doesn't working correctly")

    def test06_create_container(self): 
        """
            test create container 
            connect to vm instance remotely using js9 client and check the new created vms 
        """
        container = run_cmd("/usr/sbin/zos container new --name=container")
        test_con = j.clients.zos.get('test', data={'host':'10.102.147.99', 'port':'6379'})
        con_list = test_con.containers.list()
        con_str = ' '.join(str(e) for e in con_list)
        self.assertIn("Container <container>", con_str, msg="second container isn't created correctly")

    def test07_containers_list(self):     
        """
            test list containers
        """
        container_list = run_cmd("/usr/sbin/zos container list --json")
        output_container_list = container_list.stdout.decode()
        self.assertIn("id", output_container_list, msg="container list output should contain id part")
        self.assertIn("cpu", output_container_list, msg="container list output should contain cpu part")
        self.assertIn("root", output_container_list, msg="container list output should contain root part")
        self.assertIn("storage", output_container_list, msg="container list output should contain storage part")
        self.assertIn("pid", output_container_list, msg="container list output should contain pid part")
        self.assertIn("ports", output_container_list, msg="container list output should contain ports part")
    
    def test08_container_sshinfo(self):
        """
            show ssh info for certain container
        """
        container_ssh_info = run_cmd("/usr/sbin/zos container sshinfo")
        # check if it return a vaild ip or not
        ip = container_ssh_info.stdout.decode().split()[len(container_ssh_info.stdout.decode().split()) - 3].split("@")[1]
        port = container_ssh_info.stdout.decode().split()[len(container_ssh_info.stdout.decode().split()) - 1]   
        ip_check = str(ip)
        self.assertIn("10.102.147.99", ip_check, msg = "it's not an vaild ip")
        return port

    def test09_file_upload(self):
        """
            function to test upload for files to certain container
        """
        # create file to test upload function
        os.system('touch /tmp/test_upload')
        file_upload = run_cmd("/usr/sbin/zos container upload /tmp/test_upload /tmp/")
        # test if the file is uploaded or not using ssh
        port = self.test08_container_sshinfo()
        check_upload = os.system("ssh root@10.102.147.99 -p {} 'ls /tmp/ | grep test_upload'".format(port))
        self.assertEqual(check_upload, 0, msg="upload function isn't working correctly")
    
    def test10_file_download(self):
        """
            function to test download for files to certain continer
        """ 
        file_download = run_cmd("/usr/sbin/zos container download /etc/profile /tmp/test_download")
        check_download = os.path.isfile('/tmp/test_download')
        self.assertTrue(check_download, msg="download function isn't working correctly")
    
    def test11_exec(self):
        """
            function to test exec cmd
        """
        exec_cmd = run_cmd("/usr/sbin/zos container exec 'touch /tmp/test_exec'")
        port = self.test08_container_sshinfo()
        check_exec = os.system("ssh root@10.102.147.99 -p {} 'ls /tmp/ | grep test_exec'".format(port))
        self.assertEqual(check_exec, 0, msg="exec function isn't working correctly")
        
    def test12_container_mount(self):
        """
            test mount command 
        """
        os.system("mkdir /tmp/testmount")
        test_container_mount = run_cmd("/usr/sbin/zos container mount / /tmp/testmount")
        test_mount = os.path.ismount("/tmp/testmount")
        self.assertTrue(test_mount, msg="mount point isn't set true")

    def test13_container_delete(self):
        """
            test delete container function
        """
        con_number = con_num("test_del")
        delete_container = run_cmd("/usr/sbin/zos container {} delete".format(con_number))  
        # check the list of containers on vm instance node
        test_con = j.clients.zos.get('test', data={'host':'10.102.147.99', 'port':'6379'})     
        con_list = test_con.containers.list()
        con_str = ' '.join(str(e) for e in con_list)
        self.assertNotIn("Container <test_delete>", con_list, msg="second container isn't deleted correctly")
        
    def tearDown(self):
        pass

    @classmethod
    def tearDownClass(cls):
        # delete zos container 
        con_number = con_num("container")
        delete_container = run_cmd("/usr/sbin/zos container {} delete".format(con_number))
        # delete zos node instance
        default_init_remove = run_cmd("/usr/sbin/zos remove --name=default_init")
               
    if __name__ == '__main__':
        unittest.main()
