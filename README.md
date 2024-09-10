# My Home-Grown Cluster Adventure<br>#ADefinatelyNotByAiGeneratedIntro
Welcome to the epicenter of my personal tech revolution! This isn't just another Kubernetes cluster—it's my foray into the world of self-hosted, cutting-edge infrastructure. Born from a long-held dream and fueled by an insatiable curiosity, this project is where high-performance computing meets the comfort of my own home.

Imagine having the power of a tech giant's data center right in your living room. That's exactly what I've set out to create. This Kubernetes cluster isn't just a collection of nodes and containers; it's a testament to the democratization of technology, a playground for innovation, and my very own digital sandbox where the only limit is my imagination.

From orchestrating complex applications to experimenting with the latest in cloud-native technologies, this project is my ticket to the bleeding edge of modern infrastructure. It's where I'll be pushing boundaries, breaking things (and fixing them), and ultimately, mastering the art of Kubernetes.

So, buckle up and dive in with me. Whether you're here to learn, to be inspired, or to embark on your own Kubernetes journey, you're in for an exhilarating ride. Welcome to my Kubernetes Cluster Project—where dreams of personal servers become reality, and the future of computing is homemade.

### Hardware
```bash
NAME           ROLES                        IP             CPU  RAM                       
server-node-1  control-plane, etcd, master  192.168.1.101  8    32
server-node-2  control-plane, etcd, master  192.168.1.102  4    32
server-node-3  control-plane, etcd, master  192.168.1.103  4    16
agent-node-1                                NaN            12   64
```

### Software
- [Fedora CoreOS](https://fedoraproject.org/coreos/)
- [K3S Kubernetes](https://k3s.io/) 
- [Rancher](https://www.rancher.com/)
- [Longhorn](https://longhorn.io/)

## Table of Contents
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)
- [Acknowledgements](#acknowledgements)

## Installation
1. Create an [Ignition Config](/os/ignition_configs/first_node_config.yaml) for the first Server Node.
   - Ignition is the provisioning utility used by Fedora CoreOS to manipulate disks, create users, and configure the system.
   - The provided config file sets up the core user, configures SSH access, sets up system services (including k3s), and configures storage for Longhorn.

2. Download and install [Fedora CoreOS](https://fedoraproject.org/coreos/).
   - Fedora CoreOS is a minimal, container-focused operating system, ideal for running Kubernetes.
   - Use [Rufus](https://rufus.ie/) or a similar tool to create a bootable USB drive with the Fedora CoreOS image.
   - While other operating systems like Fedora Server or Proxmox could be used, Fedora CoreOS provides a streamlined, immutable infrastructure that's well-suited for Kubernetes deployments.

3. Boot the node from the USB drive and apply the Ignition config.
   - During the boot process, you'll need to specify the location of your Ignition config file.
   - This will configure the system according to your specifications, including setting up k3s.

4. Repeat the process for additional nodes.
   - For worker nodes, you'll need to create separate Ignition configs that join the k3s cluster rather than initializing it.
   - Ensure each node has a unique hostname and IP address.

5. Verify that all nodes are up and running.
   - SSH into each node to confirm successful boot and configuration.
   - On the first node, use `kubectl get nodes` to verify that all nodes have joined the cluster.

6. Configure network settings if necessary.
   - Ensure all nodes can communicate with each other.
   - Set up any required port forwarding on your router for external access.

### Installing Rancher

```bash
# Example command line instructions
pip install -r requirements.txt
```

### Installing Longhorn

```bash
# Example command line instructions
pip install -r requirements.txt
```

## License
This project is licensed under the terms of the Creative Commons Attribution 4.0 International License (CC BY 4.0) and the All Rights Reserved License. See the [LICENSE](LICENSE.txt) file for details.

## Contact
[Github](https://github.com/Knaeckebrothero) <br>
[Mail](mailto:OverlyGenericAddress@pm.me) <br>
