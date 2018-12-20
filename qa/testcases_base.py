from jumpscale import j
import unittest

class BaseTest(unittest.TestCase):
    def __init__(self):
        self.Node = "10.102.147.99"
        self.zos_client = j.clients.zos.get('test', data={'host':self.Node, 'port':'6379'})

    def create_container(self, container_name):
        # create container on specific node using Zero-os client
        self.flist = "https://hub.grid.tf/tf-bootable/ubuntu:lts.flist"
        self.zos_client.containers.create(con_name, self.flist)
    
    def list_container(self, container_name):
        # list all containers on ceratin node and return the container_id
        containers = self.zos_client.containers.list()
        for con in containers:               
            if con.name == con_name:
                return con.id



