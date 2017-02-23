---
layout: post
title: "Want faster Ansible runs? Try enabling pipelining!"
date: 2017-02-23 20:05:06 +0100
categories: ansible infrastructure platform engineering
---

I've always wondered if there's a way to speed up Ansible executions as creating
a new SSH connection for each command seemed excessive. However, I'd never
looked for a solution until today when I discovered a very neat feature that
shares SSH connections called pipelining.

Enabling it as simple as adding the following to an `ansible.cfg` file located
somewhere it can be picked up by Ansible (for me this was in the same directory
as my playbook):

```
[ssh_connection]
pipelining = False
```

Tada! Now a playbook that took several minutes was done in a fraction of that
time.

**NB:** As written in the [Ansible configuration docs](https://docs.ansible.com/ansible/intro_configuration.html#pipelining):
"This can result in a very significant performance improvement when enabled,
however when using “sudo:” operations you must first disable ‘requiretty’ in
/etc/sudoers on all managed hosts."
