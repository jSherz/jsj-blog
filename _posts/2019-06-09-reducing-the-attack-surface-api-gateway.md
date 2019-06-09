---
layout: post
title: "Reducing the attack service of a web app with an API Gateway"
date: 2019-06-09 10:22:00 +0100
categories:
 - API Gateway
 - AWS
 - security
 - proxy
---

Wouldn't it be great if you didn't have to expose your web applications to the
internet? If you could just bind them to `127.0.0.1` and never have anyone reach
them? They wouldn't be as useful, admittedly, but they'd certainly be more
secure. I often look back at CVE reports and think "what could I have done to
avoid being vulnerable to that"? One option that's always appealing is the use
of a Web Application Firewall that is smart enough to know problematic requests
to look for and block. Perhaps it detects an SQL Injection attack because no
legitimate user would be sending your webapp a `DELETE FROM`. Maybe it knows
that it has to block [particular file upload requests] to avoid an attacker
taking over your web server. Regardless of the methods employed, many Web
Application Firewalls rely on known vulnerabilities and/or may be out of reach
price wise for small hobby projects.

[particular file upload requests]: https://www.forbes.com/sites/thomasbrewster/2017/09/14/equifax-hack-the-result-of-patched-vulnerability/

In this post, we're going to look at a simple method to reduce the attack
surface for a web app. Like anything in security, it's not a silver bullet and
so is paired well with other layers of defence. Our target use case for this
approach is a web application that we haven't developed ourselves and yet must
host publicly accessible to the internet. It's only useful where we can have
separate, privileged, access to the same web service.

## API Gateways

There are lots of options for API Gateway software, but we're going to use the
AWS API Gateway as it's easy to setup, fully managed and billed based on usage.
It's not as feature rich as some competing products, but its low cost and
management overhead make it very appealing for smaller budgets or hobby
projects.

* Other API Gateways

* Desirable features

## The approach

We're relying on the assumption that part of the exploitability of a web app is
derived from the variety of requests that can be made to it. We'll consider the
following parts of the HTTP request as attack vectors:

* The URI

    If we allow anyone access to any URL, they can call any API endpoint, even
    if they wouldn't have the permission to do so or it's a scarcely used
    debugging route.

    Authentication would normally control access here, but doesn't defend
    against endpoints that we either don't have knowledge of, don't intend to be
    anonymous.

* Headers

    
