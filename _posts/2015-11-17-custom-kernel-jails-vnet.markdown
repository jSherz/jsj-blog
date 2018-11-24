---
layout: post
title: "Compiling a custom FreeBSD kernel to enable VNET support for jails"
date: 2015-11-17 19:13:00 +0000
categories: freebsd jails kernel vnet
---
One issue I had while replacing FreeNAS with FreeBSD was that, by defualt, vnet support isn&rsquo;t enabled in the kernel. To resolve this, I compiled a custom kernel as follows:

## Step 1 - download the kernel sources

Change the FreeBSD version, as appropriate.

{% highlight shell %}
pkg install subversion
svn checkout http://svn.freebsd.org/base/release/10.2.0/ /usr/src
{% endhighlight %}

## Step 2 - create a custom config

{% highlight shell %}
cd /usr/src/sys/amd64/conf # Replace amd64 with the desired architecture
cp GENERIC MYKERNEL
{% endhighlight %}

Once you&rsquo;ve got a copy of the generic kernel configuration (`MYKERNEL`), make any required changes. In my case, I added the following, as per the instructions on the [iocage README](https://github.com/iocage/iocage/blob/master/README.md):

{% highlight shell %}
options         VIMAGE # VNET/Vimage support
options         RACCT  # Resource containers
options         RCTL   # same as above
{% endhighlight %}

## Step 3 - build and install the kernel

{% highlight shell %}
cd /usr/src
make buildkernel KERNCONF=MYKERNEL
make installkernel KERNCONF=MYKERNEL
{% endhighlight %}

Let me know if you have any questions or... more importantly, if there&rsquo;s an easier way of doing this!

## Sources

Thanks to:

* [http://wiki.polymorf.fr/index.php/Howto:FreeBSD_jail_vnet](http://wiki.polymorf.fr/index.php/Howto:FreeBSD_jail_vnet)
* [http://www.rhyous.com/2012/05/09/how-to-build-and-install-a-custom-kernel-on-freebsd/](http://www.rhyous.com/2012/05/09/how-to-build-and-install-a-custom-kernel-on-freebsd/)
* [https://www.freebsd.org/doc/handbook/kernelconfig-config.html](https://www.freebsd.org/doc/handbook/kernelconfig-config.html)
