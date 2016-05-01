---
layout: post
title: "Installing RancherOS on OpenNebula"
date: 2016-05-01 11:23:00 +0100
categories: docker rancher rancheros opennebula
---

At the time of writing, [Rancher](https://github.com/rancher/os) does not publish VM images that are not aimed at a particular cloud provider and I therefore set about installing RancherOS with just the provided ISO.

## Step 1: Download and import images

To begin, download the RancherOS ISO and then upload it into OpenNebula's image system.

```bash
sudo -u oneadmin -i
cd /tmp
wget https://releases.rancher.com/os/latest/rancheros.iso
oneimage create --name RancherOS --path /tmp/rancheros.iso \
                --prefix hd --type CDROM -d default
```

The image type `CDROM` is used as the ISO is used to install the OS rather than as a boot disk. Although it may be possible to boot from the image with a different prefix than `hd`, this is the one I got working first (using `vd` did not work).

Now that we have an installer ISO, let's create a blank [qcow2](https://en.wikipedia.org/wiki/Qcow) image that will be used as the OS disk and then import it into OpenNebula.

```bash
qemu-img create -f qcow2 -o size=10G /tmp/blank.qcow2
oneimage create --name Blank --path /tmp/blank.qcow2 \
                --prefix vd --type OS -d default --driver qcow2
```

In this case, we specify the `qcow2` driver, type and prefix for an OS disk.

## Step 2: Creating a template

Once the images have been imported, we can create a template to use for RancherOS. It is composed of the following parts:

* A boot disk (Blank) for the OS to be installed on.

* A cdrom (RancherOS) to install the OS with.

* The correct boot order for installing and then using RancherOS.

* A network adapter.

The following template is an example of the above requirements.

```
CONTEXT=[
  NETWORK="YES",
  SSH_PUBLIC_KEY="$USER[SSH_PUBLIC_KEY]" ]
CPU="2"
DISK=[
  IMAGE="Blank 10GB",
  IMAGE_UNAME="james",
  SIZE="10240" ]
DISK=[
  IMAGE="RancherOS v0.4.4",
  IMAGE_UNAME="james" ]
GRAPHICS=[
  LISTEN="0.0.0.0",
  TYPE="vnc" ]
MEMORY="2048"
NIC=[
  NETWORK="Main",
  NETWORK_UNAME="james" ]
OS=[
  ARCH="x86_64",
  BOOT="hd,cdrom" ]
```

You can either adapt the above or manually create one with the `onetemplate` tool or SunStone GUI.

*NB:* As the RancherOS ISO does not support OpenNebula's contextualization, we must manually configure networking (shown below).

### Documentation

* [Creating and using OpenNebula templates](http://docs.opennebula.org/4.14/user/virtual_resource_management/vm_guide.html)
* [OpenNebula template syntax](http://docs.opennebula.org/4.14/user/references/template.html)

## Step 3: Creating a VM

Create a new VM with the template that was configured in the previous step and then use the built-in VNC client (part of the SunStone GUI) to see the console. If the above was done correctly, the VM should have booted from the RancherOS ISO.

## Step 4: Install RancherOS onto the main disk

Once the VM has booted, login with the username `rancher` and password `rancher`. Following the instructions on the [RancherOS documentation](docs.rancher.com/os/running-rancheros/server/install-to-disk/), install RancherOS to `/dev/vda` and then (when asked) choose to reboot. If everything was installed correctly, the VM will now boot from RancherOS on the hard drive.

An example cloud config is shown below (see [the RancherOS cloud config reference](http://docs.rancher.com/os/cloud-config/)).

```yaml
#cloud-config
ssh_authorized_keys:
  - ssh-rsa AAAAB3...igrw== MyKey

rancher:
  network:
    interfaces:
      eth*:
        dhcp: false
      eth0:
        address: 192.168.100.100/24
        gateway: 192.168.100.1
        mtu: 1500
      # If this MAC address happens to match eth0, eth0 will be programmed to use DHCP.
      "mac=ea:34:71:66:90:12:01":
        dhcp: true
    dns:
      nameservers:
        - 8.8.8.8
        - 8.8.4.4
```

Once you've made a cloud config file with all of the required configuration, use the `ros` command to install RancherOS to the main disk.

```bash
vi cloud-config.yml
sudo ros install -c cloud-config.yml -d /dev/vda
```

## Step 5: Install the RancherOS server

Login to the VM with one of the SSH keys configured above and then use the following command to install the server (where `1.2.3.4` is the VM IP address configured in the `cloud-config.yml` above).

```bash
ssh rancher@1.2.3.4
# In the VM
sudo docker run -d --restart=always -p 8080:8080 rancher/server
```

In a few minutes, your new RancherOS install will be visible at `http://1.2.3.4:8080`. Enjoy!

If anything isn't clear please contact me via Twitter or the e-mail shown below and I'll do my best to update this guide.
