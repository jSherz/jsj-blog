---
layout: post
title: "Installing f.lux on CentOS"
date: 2015-11-16 23:10:05 +0000
categories: centos oss f.lux
---
When working late at night, I enjoy using the excellent [f.lux](https://justgetflux.com/) app. Unfortunately, setting it up on CentOS wasn't as easy as I'd hoped. Below are the steps I took to get it working.

## Step 1 - install dependencies

{% highlight shell %}
sudo pip install pexpect
sudo yum install gnome-python2-gconf pyxdg python-appindicator
{% endhighlight %}

## Step 2 - install f.lux

{% highlight shell %}
git clone https://github.com/Kilian/f.lux-indicator-applet.git
cd f.lux-indicator-applet
sudo python setup.py install
{% endhighlight %}

Didn't work for you? Post an issue on [this blog's repo](https://github.com/jSherz/jsj-blog) with the steps you had to follow and I'll add them to this guide.
