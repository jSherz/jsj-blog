---
layout: post
title: "Setting up the discovery of a network share / server with Avahi"
date: 2015-11-16 23:40:00 +0000
categories: centos oss f.lux
---
I recently replaced FreeNAS with FreeBSD after installing even basic tools in the main OS (without first using a jail) became tedious and I wanted to explore how each of the components (e.g sharing & plugins) were implemented.

Below is a service description file that Avahi will use to broadcast the server's share capabilities. It allows an easy one-click to find shares on OS10 and will also appear / work when using "Browse Network" in nautilus (tested on CentOS running Gnome Shell).

{% highlight xml %}
<service-group>
    <name replace-wildcards="no">Media Server</name>

    <service>
        <type>_afpovertcp._tcp</type>
        <port>548</port>
    </service>

    <service>
        <type>_smb._tcp</type>
        <port>139</port>
    </service>

    <service>
        <type>_device-info._tcp</type>
        <port>0</port>
        <txt-record>model=RackMac</txt-record>
    </service>
</service-group>
{% endhighlight %}

Or, to include the hostname in the displayed server name:

{% highlight xml %}
<service-group>
    <name replace-wildcards="yes">%h Server</name>

    <!-- ... -->
</service-group>
{% endhighlight %}

Save the above as `fileshares.service` and place the file in `/etc/avahi/services` or `/usr/local/etc/avahi/services` as appropriate. For some more info about the tags, there's `man avahi.service`.

The file describes both CIFS / SMB (Windows) shares and also AFP shares (Apple) so should work on OS10, Linux/Unix & Windows (with Bonjour installed).
