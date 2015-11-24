=============================================
Kubernetes with OpenContrail Heat Template
=============================================

These Heat templates will deploy Nova instances running Kubernetes with OpenContrail on top of OpenStack. The cluster uses OpenContrail to provide an overlay network connecting pods deployed on different nodes.

It reuses Vagrant deployment described by Pedro Marques at http://www.opencontrail.org/installing-kubernetes-opencontrail/

Stack consists following virtual machines:

* **k8s-deploy** - VM used for loading and launching deployment script of Kubernetes. Whole k8s provisioning by Ansible is lauched from this host.
* **k8s-master** - Kubernetes controller with OpenContrail services.
* **k8s-gateway** - OpenContrail gateway
* **k8s-node-01** - Kubernetes nodes
* **k8s-node-02** - Kubernetes nodes

There are two virtual networks:

* **external network** - 10.0.2.0/24 it is used for external access (subnet conected to SNAT router). 
* **underlay network** - 192.168.1.0/24 it used as Kubernetes private communication.

Deploying Stack
=================

*/template/k8s_single_opencontrail.hot* template define several env parameters that can be used to configure stack. The environments parameters are defined in */env/k8s_single_opencontrail.env.sample*

You need to modify your floating ip network_id in env and other variables related to your OpenStack:

.. code-block:: yaml

	parameters:
	  ...
	  instance_flavor: m1.large
	  instance_flavor_controller: m1.large
	  public_net_id: 627d621d-db43-4bcd-a403-814316c38fe9
	  ...

Heat template contains also predefined private and public SSH keypair. Public is located in env file and private is loaded inside **k8s-deploy** user data. It is used for future Ansible provisioning. You can modify it in template.

Then you can run the Heat template

.. code-block:: bash

	heat stack-create -f k8s_single_opencontrail.hot -e pk8s_single_opencontrail.env.sample my-kube-cluster

Heat template contains wait condition to wait until Ansible provisioning is done. Timeout is defined to one hour.

Now you have to add static routes to you k8s-gateway. This depends on your Neutron backend in OpenStack. Our OpenStack use OpenContrail as Neutron plugin, so we had to add following static routes to port 192.168.1.254:

* 10.254.0.0/16
* 100.64.0.0/16

At the end of the script we should be able to login to k8s-deploy instance through your floating ip and ssh key.

* **kubectl get nodes**
  This should show two nodes: k8s-node-01 and k8s-node-02.
    
* **kubectl --namespace=kube-system get pods**
    This command should show that the kube-dns pod is running

* **kubectl --namespace=opencontrail get pods**
    This command should show that the opencontrail pods are running

* **curl http://localhost:8082/virtual-networks | python -m json.tool**
	This should display a list of virtual-networks created in the opencontrail api

* **netstat -nt | grep 5269**
    We expect 3 established TCP sessions for the control channel (xmpp) between the master and the nodes/gateway.

Deploy Kubernetes application Guestbook
=========================================

Once the cluster is operational, one can start an example application such as “guestbook-go”. Pedro Marques has all-in-one deployment by Ansible. Connect to k8s-deploy and then run foloowing playbook.

.. code-block:: bash

	wget https://raw.githubusercontent.com/pedro-r-marques/examples/master/ec2-k8s-cluster/examples.yml
	ansible-playbook -i contrib/ansible/inventory examples.yml

This will launch Guestbook application, which you can check:

.. code-block:: bash

	root@k8s-master:~# kubectl get po
	NAME                 READY     STATUS    RESTARTS   AGE
	curlpod              1/1       Running   17         17h
	guestbook-d1xqn      1/1       Running   0          20h
	guestbook-griil      1/1       Running   0          20h
	guestbook-xngse      1/1       Running   0          20h
	redis-master-b420b   1/1       Running   0          20h
	redis-slave-7p18n    1/1       Running   0          20h
	redis-slave-965gv    1/1       Running   0          20h

	root@k8s-master:~# kubectl get svc
	NAME           CLUSTER_IP       EXTERNAL_IP      PORT(S)    SELECTOR                AGE
	guestbook      10.254.6.219     100.64.255.252   3000/TCP   app=guestbook           20h
	kubernetes     10.254.0.1       <none>           443/TCP    <none>                  1d
	redis-master   10.254.127.77    <none>           6379/TCP   app=redis,role=master   20h
	redis-slave    10.254.155.182   <none>           6379/TCP   app=redis,role=slave    20h

Now you can access external IP and port by curl

.. code-block:: bash

	root@k8s-master:~# curl 100.64.255.252:3000
	<!DOCTYPE html>
	<html lang="en">
	  <head>
	
	....


* https://github.com/pedro-r-marques/contrib/tree/opencontrail/ansible
* http://www.opencontrail.org/installing-kubernetes-opencontrail/