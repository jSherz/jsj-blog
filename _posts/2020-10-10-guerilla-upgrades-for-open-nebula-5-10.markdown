---
layout: post
title: "Guerrilla upgrades for OpenNebula 5.10 to 5.12"
date: 2020-10-10 18:13:00 +0100
categories:
  - OpenNebula
  - virtual machine
  - vm
  - KVM
---

I've used the [OpenNebula] project for several years to run virtual machines to
experiment with different Linux distros and software. Unfortunately, they made
the decision to continue releasing the main product as Open Source Software but
restrict the database migration scripts to non-commercial use\[[1]\] \[[2]\] (or
require you to pay). This would be fine for my use case but requires submitting
an application to be allowed to download the migration scripts, and no-one is
going to be responding to my requests over the weekend when I'm looking to
upgrade my cluster. Bring on the guerrilla upgrade!

[OpenNebula]: https://www.opennebula.io
[1]: https://forum.opennebula.io/t/towards-a-stronger-opennebula-community/8506
[2]: http://docs.opennebula.io/5.12/intro_release_notes/upgrades/start_here.html#previous-steps

## The target database

The software will happily create a fresh database for us and so we're going to
give it an alternative data source to use. I am migrating from a SQLite database
to MariaDB here, but you could easily stay with the same data store. Let's start
by stopping the daemon, moving the auth files out the way (facilitates a
bootstrapping of the database) and installing MariaDB:

```bash
sudo systemctl stop opennebula-sunstone
sudo systemctl stop opennebula

sudo mv /var/lib/one/.one /var/lib/one/.one-backup

sudo apt install mariadb-server-10.3
sudo systemctl enable mariadb
sudo systemctl start mariadb
```

Once we have a new database server running, we can login as root and create a
user for OpenNebula:

```bash
sudo mysql
```

```sql
CREATE USER 'open_nebula'@'localhost' IDENTIFIED BY 'password123';
CREATE SCHEMA open_nebula;
GRANT ALL PRIVILEGES ON open_nebula.* TO 'open_nebula'@'localhost';
FLUSH PRIVILEGES;

SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

Then we can configure OpenNebula by altering `/etc/one/oned.conf`:

```
DB = [ BACKEND = "mysql",
       SERVER  = "localhost",
       PORT    = 3306,
       USER    = "open_nebula",
       PASSWD  = "password123",
       DB_NAME = "open_nebula",
       CONNECTIONS = 25,
       COMPARE_BINARY = "no" ]
```

Once that's set, let's start the daemons:

```bash
sudo systemctl start opennebula
sudo systemctl start opennebula-sunstone
```

This should have created various tables in the MySQL database. Check
`/var/log/one/oned.log` if those haven't appeared.

## Sketchy data transfer

Once we've got a new target database, open both the original and target
databases in an editor of your choice. I chose DataGrip as it has great support
for both MySQL and SQLite.

We're now going to go through and copy components from the old database tables
to the new ones. This involves some thought as there are records that will
already exist that we don't want to overwrite (for example the "oneadmin" user
in the `user_pool` table). I had a very simple OpenNebula setup as I just have
one testing host and so here are some of the steps that I had to go through to
reverse engineer the correct data format and to migrate the data manually. More
involved installs will just require paying the money, supporting a great Open
Source (ish) project and accepting that vendors will do weird things to make you
pay for software that is 'free'. Non-commercial users can request the migration
scripts with a [contact form]. 2020: what a year, eh?!

[contact form]: https://opennebula.io/get-migration/

### acl

I made no changes to this table.

### cluster_datastore_relation, cluster_network_relation, cluster_pool

Data copied verbatim.

### cluster_vnc_bitmap

I made no changes here.

### datastore_pool

I compared the XML and decided I'd made no changes from the default values so I
left these the same.

### db_versioning

We don't want to poison the new database with our old version so I didn't copy
the data across.

### document_pool

I had no documents - good luck!

### group_pool, group_quotas

I didn't change these from the default so didn't copy them.

### history...

...is meant to be in the past. I just didn't copy it.

### hook_log, hook_pool

I didn't use any hooks so left these empty.

### host_monitoring

Another historic data table that I didn't use.

### host_pool

I copied the entry and then modified the XML to clear out some fields that are
no longer present and to add some new ones. To know what the target XML should
look like, I created a new dummy host, inspected its XML (in the "body" column)
and then made my old host look like it. Verify that you've not hosed it with the
CLI:

```bash
sudo onehost list
sudo onehost show 0
```

The [schemas in the source code] come in very handy for looking at the correct
field names.

[schemas in the source code]: https://github.com/OpenNebula/one/blob/master/src/oca/go/src/goca/schemas/host/host.go

### image_pool

Copied verbatim.

### local_db_versioning

Left untouched.

### logdb

I didn't copy this over.

### marketplace_pool, marketplaceapp_pool

I left the new values untouched and didn't copy anything.

### network_pool

Copied verbatim.

### network_vlan_bitmap

This was the same in both data stores for me.

### pool_control

I updated the `last_oid` value to be the one from the source data store and
added any missing rows. This table is responsible for knowing which ID to give
out to new resources (e.g. virtual machines) as they're created.

### secgroup_pool, system_attributes

Left untouched.

### template_pool

Copied verbatim.

### user_pool

I copied over a user I'd created verbatim. Note that the oneadmin user will have
a new password and it's located in the `/var/lib/one/.one/one_auth` file.

### user_quotas, vdc_pool, vm_import

Left untouched.

### vm_monitoring

A history table that I left in the past.

### vm_pool

Copied verbatim. Where the `lcm_state` column was `6`, I replaced the
timestamp-like value in the `state` column with a `6` as otherwise all of the
deleted VMs appeared in the list. I copied over the full `body` column into
`short_body` and it didn't explode so that might work for you too.

### vm_showback, vmgroup_pool, vn_template_pool, vrouter_pool, zone_pool

Left untouched.

## Weird and wonderful: the journey to supporting Open Source

It's a shame that the OpenNebula vendor decided that this was the route they
were taking with encouraging users to pay for the software or support it. I'd
much rather have the license change (but the migration scripts freely
downloadable) or additional modules being created to target enterprise
functionality like SSO which aren't shipped in the community edition. Attempting
to upgrade only to be told by the migration CLI that the migrations were missing
was a really confusing error. Just link me to the web shop next time. It's more
humane.

What's your view on publishing community versions of software that you can't
upgrade?
