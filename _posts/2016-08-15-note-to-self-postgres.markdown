---
layout: post
title: "Note to self: if you want PostgreSQL to accept your non-lowercase database name, enclosure its name with quotes"
date: 2016-08-15 13:50:01 +0100
categories: docker configserver firewall iptables csf debian systemd
---
The following creates the database `frustratingerror`:

```sql
CREATE DATABASE FrustratingError;
```

The following creates the database `FrustratingError`:

```sql
CREATE DATABASE "FrustratingError";
```
