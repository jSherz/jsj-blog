---
layout: post
title: "Configuring ConfigServer Firewall (CSF) for Docker (Debian 8)"
date: 2016-05-16 13:29:00 +0100
categories: docker configserver firewall iptables csf debian systemd
---
By default, the [Docker daemon](https://docs.docker.com/engine/reference/commandline/daemon/) will automatically configure iptables rules that allow communication with containers and, additionally, the outside world through the use of exposed ports. If you&rsquo;re like me and using ConfigServer Firewall, this may not be desirable as these rules will bypass the firewall configuration and let anyone access the exposed container ports.

To get around this, it&rsquo;s possible to disable the automatic iptables rules with the use of a systemd drop-in:

`/etc/systemd/system/docker.service.d/10-no-iptables.conf`

```
[Service]
ExecStart=/usr/bin/docker daemon -H fd:// --iptables=false
```

This file will override the `ExecStart` section of the main `docker.service` file and will prevent the Docker daemon from configuring iptables. As a result of the above, containers will no longer be able to communicate with the host, and vice-versa. To fix this, we can add a `csfpost.sh` script that will be triggered after the ConfigServer firewall has been started or reloaded.

`/etc/csf/csfpost.sh`

```bash
#!/bin/sh

echo "[DOCKER] Setting up FW rules."

iptables -N DOCKER

# Masquerade outbound connections from containers
iptables -t nat -A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE

# Accept established connections to the docker containers
iptables -t filter -A FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow docker containers to communicate with themselves & outside world
iptables -t filter -A FORWARD -i docker0 ! -o docker0 -j ACCEPT
iptables -t filter -A FORWARD -i docker0 -o docker0 -j ACCEPT

echo "[DOCKER] Done."
```

Followed by making the file executable:

```bash
sudo chmod +x /etc/csf/csfpost.sh
```

Once we&rsquo;ve added this script, we then need to add an exception to allow container traffic through the firewall. This can be done by adding the following line to the `/etc/csf/csf.allow` file:

```
172.17.0.0/16
```

After reloading the systemd daemon to pickup these changes, reloading the ConfigServer firewall and restarting the docker daemon, the containers should again be able to communicate with each other and the host. However, ports exposed on containers should not be reachable from the outside world.

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo csf -r
```
