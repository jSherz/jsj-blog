---
layout: post
title: "Adding a grub menu option to reboot to the BIOS / UEFI settings on CentOS"
date: 2015-11-21 22:18:00 +0000
categories: centos grub grub2 bios uefi boot
---

I recently played around with a few Linux distros and ended up keeping CentOS as my daily driver. One thing I missed, however, was having the "System settings" option on the grub menu that would reboot the computer into the BIOS / UEFI options (present in Ubuntu & Debian).

To add this option on CentOS, create the following file and paste in the shell script below (note that 50 is an arbitrary number that determines the order of the grub helper scripts being run).

````
/etc/grub.d/50_uefi-firmware
````

{% highlight shell %}
#! /bin/sh
set -e

# grub-mkconfig helper script.
# Copyright (C) 2012  Free Software Foundation, Inc.
#
# GRUB is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# GRUB is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GRUB.  If not, see <http://www.gnu.org/licenses/>.

. "/usr/share/grub/grub-mkconfig_lib"

efi_vars_dir=/sys/firmware/efi/vars
EFI_GLOBAL_VARIABLE=8be4df61-93ca-11d2-aa0d-00e098032b8c
OsIndications="$efi_vars_dir/OsIndicationsSupported-$EFI_GLOBAL_VARIABLE/data"

if [ -e "$OsIndications" ] && \
   [ "$(( $(printf 0x%x \'"$(cat $OsIndications | cut -b1)") & 1 ))" = 1 ]; then
  LABEL="System setup"

  gettext_printf "Adding boot menu entry for EFI firmware configuration\n" >&2

  onstr="$(gettext_printf "(on %s)" "${DEVICE}")"

  cat << EOF
menuentry '$LABEL' \$menuentry_id_option 'uefi-firmware' {
 fwsetup
}
EOF
fi
{% endhighlight %}

Then make the script executable:

{% highlight shell %}
chmod +x /etc/grub.d/50_uefi-firmware
{% endhighlight %}

Once it's executable, you can see the menu entry that will be added by running `grub2-mkconfig`. If successful, it will return something similar to the following (providing you're booting into an EFI install).

{% highlight shell %}
# ...

### BEGIN /etc/grub.d/50_uefi-firmware ###
Adding boot menu entry for EFI firmware configuration
menuentry 'System setup' $menuentry_id_option 'uefi-firmware' {
 fwsetup
}
### END /etc/grub.d/50_uefi-firmware ###

# ...
{% endhighlight %}

If everything looks OK, you can then update your grub config file as follows.

````
grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
````
