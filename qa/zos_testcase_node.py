import os
import json
import unittest
import subprocess
from jumpscale import j
from configparser import ConfigParser

def run_cmd(cmd):
    subprocess.run([cmd], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

class SimpleTest(unittest.TestCase):

    """
    test cases to test using ZOS with virtualbaox instance 
    """
    @classmethod
    def setUpClass(cls): 
        """
            configures instance with name zosmachine on address 
        """
        default_init = subprocess.run(["zos configure --name=default_init --address=10.102.147.99 --port=6379"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)

    def setUp(self):
        pass

    def test01_setdefault(self):
        """
        check if certain node is used as default or not
        """
        set_default = subprocess.run(["zos setdefault default_init"],  shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
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
        ping = subprocess.run(["zos ping"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        testping = ping.stdout.decode()
        self.assertIn("PONG",testping, msg="the node isn't pingable")

    def test_showconfig(self):
        """
            test showconfig command 
        """
        showconfig = subprocess.run(["zos showconfig"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        output = showconfig.stdout.decode()
        self.assertIn("defaultzos", output, msg="showconfig command isn't working correctly")

    def test03_showactive(self):
        """
            test showactive command
        """
        showactive = subprocess.run(["zos showactive"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        output = showactive.stdout.decode()
        self.assertIn("default_init", output, msg="default_init node is an active node")

    def test04_showactiveconfig(self):
        showactiveconfig = subprocess.run(["zos showactiveconfig"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        output_showactiveconfig = json.loads(showactiveconfig.stdout.decode())
        # need to check if the output contains (address, isvbox, port)
        self.assertIn("address", output_showactiveconfig, msg="wrong output the command should contain address part")
        self.assertIn("port", output_showactiveconfig, msg="wrong output the command should contain port part")
        self.assertIn("isvbox", output_showactiveconfig, msg="wrong output the command should contain isvbox part")

    def test05_cmd(self):
        """
            funcation to test command cmd in zos
        """
        test_cmd_node = subprocess.run(["zos cmd 'nft.list'"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        test_cmd_node_output = test_cmd_node.stdout.decode()
        self.assertIn("tcp", test_cmd_node_output, msg="cmd doesn't working correctly")

    def test06_create_container(self): 
        """
            test create container 
            connect to vm instance remotely using js9 client and check the new created vms 
        """
        container2 = subprocess.run(["zos container new --name=container2"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        cont_num = container2.stdout.decode().split("\n")[2].split(" ")[2]
        test_con = j.clients.zos.get('test', data={'host':'10.102.147.99', 'port':'6379'})
        con_list = test_con.containers.list()
        con_str = ' '.join(str(e) for e in con_list)
        self.assertIn("Container <container2>", con_str, msg="second container isn't created correctly")
        return cont_num

    def test07_containers_list(self):     
        """
            test list containers
        """
        container_list = subprocess.run(["zos container list --json"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
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
        container_ssh_info = subprocess.run(["zos container sshinfo"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # check if it return a vaild ip or not
        ip = container_ssh_info.stdout.decode().split("\n")[len(container_ssh_info.stdout.decode().split("\n")) - 2].split(" ")[0].split("@")[1]
        port = container_ssh_info.stdout.decode().split("\n")[len(container_ssh_info.stdout.decode().split("\n")) - 2].split(" ")[2]
        ip_check = str(ip)
        self.assertIn("10.102.147.99", ip_check, msg = "it's not an vaild ip")
        return ip, port

    def test09_file_upload(self):
        """
            function to test upload for files to certain container
        """
        # create file to test upload function
        os.system('touch /tmp/test')
        file_upload = subprocess.run(["zos container upload /tmp/test /tmp/"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # test if the file is uploaded or not 
        ip, port = self.test08_container_sshinfo()
        os.system('mkdir /tmp/test_upload')
        os.system('scp -P {} root@{}:/tmp/test /tmp/test_upload/'.format(port, ip))
        check_upload = os.path.isfile('/tmp/test_upload/test')
        self.assertTrue(check_upload, msg="upload function isn't working correctly")

    def test10_file_download(self):
        """
            function to test download for files to certain continer
        """ 
        file_download = subprocess.run(["zos container download /etc/shadow /tmp/"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        check_download = os.path.isfile('/tmp/shadow')
        self.assertTrue(check_download, msg="download function isn't working correctly")
    
    def test11_exec(self):
        """
            function to test exec cmd
        """
        exec_cmd = subprocess.run(["zos container exec 'touch /tmp/test_exec'"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        check_exec_cmd = subprocess.run(["/usr/sbin/zos container exec 'ls /tmp/ | grep test_exec'"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        check_exec_cmd_test = check_exec_cmd.stdout.decode()
        self.assertIn("test_exec", check_exec_cmd_test, msg="exec function doesn't working correctly")

    def test12_container_mount(self):
        """
            test mount command 
        """
        os.system("mkdir /tmp/testmount")
        test_container_mount = subprocess.run(["zos container mount / /tmp/testmount"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        test_mount = os.path.ismount("/tmp/testmount")
        self.assertTrue(test_mount, msg="mount point isn't set true")

    def test13_container_delete(self):
        """
            test delete container function
        """
        # delete the last container (container 3) which i just created
        con_number = self.test06_create_container()
        delete_container = subprocess.run(["zos container {} delete".format(con_number)], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        # check the list of containers on vm instance node
        test_con = j.clients.zos.get('test', data={'host':'10.102.147.99', 'port':'6379'})     
        con_list = test_con.containers.list()
        con_str = ' '.join(str(e) for e in con_list)
        self.assertNotIn("Container <container2>", con_list, msg="second container isn't deleted correctly")
        
    def tearDown(self):
        pass

    @classmethod
    def tearDownClass(cls):
        # # delete the vm instance
        default_init_remove = subprocess.run(["zos remove --name=default_init"], shell=True, stdout = subprocess.PIPE, stderr = subprocess.PIPE)
        
    if __name__ == '__main__':
        unittest.main()
