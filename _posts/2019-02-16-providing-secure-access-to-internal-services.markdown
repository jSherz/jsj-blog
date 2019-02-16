---
layout: post
title: "Providing secure, authenticated access to an internal service running in ECS"
date: 2019-02-10 10:24:00 +0100
categories: ECS Cloudflare Argo Access sidecar Docker container
---

Gone are the days where every employee sits in an office cubicle from 9AM to
5:30PM, Monday to Friday. Having a physical location with the blinking lights of
a VPN appliance or whining server is no longer a given and thus the
'traditional' approach of whitelisting company IPs and having your colleagues
VPN in to the corporate network just isn't an option for some firms. The flip
side to this is that you're likely running several internal applications that
need to be accessible by some but aren't suitable for having publicly accessible
on the internet.

We can combine together two [Cloudflare] offerings to work around this problem
by first tunnelling an internal service that may not even have inbound internet
access to Cloudflare's network and then authenticating users that try and access
it against our corporate identity manager. In this example, we'll be running an
instance of [Grafana] inside Amazon Web Service's Elastic Container Service and
using GSuite to provide the authentication.

[Cloudflare]: https://www.cloudflare.com
[Grafana]: https://grafana.com

## Step 1 - establishing the tunnel

Although Grafana has authentication, we may not want to have the server that
it's running on directly accessible over the internet and so we'll run an ECS
service in a private subnet of our VPC. The subnet will have internet access
through a NAT gateway to a public subnet. You can find the task definition and
Dockerfiles in the [article repository].

The first tool in our belt is [Argo Tunnel] and is a product that allows you to
route traffic from Cloudflare's network to your service without exposing it to
the internet. We'll run the [cloudflared] daemon as a sidecar container to our
service and the Dockerfile & config file below show the setup that we're going
to use to receive traffic from Cloudflare and direct it to the main Grafana
container.

```
# config
```

```dockerfile
FROM grafana:latest
```

With the ECS service started, cloudflared will start and connect to Cloudflare.

## Step 2 - providing authenticated and secure access

Although the Argo Tunnel would let us provide public access to our internal
service, we want to add a layer of authentication to restrict it to only our
organisation's users. We can start by adding a new [Access] application in the
Cloudflare console and then setting up a rule to restrict access to only
specific users (if required).

- screenshots of setup

With the Argo Tunnel and Access application connected, we can now visit the
subdomain that we chose in the Access setup and will see the familiar login page
of our identity / SSO provider, in this case the Google login. Once
authenticated, we're then allowed to access our Grafana container and build the
beautiful dashboards that our service team deserves.

[cloudflared]: https://developers.cloudflare.com/argo-tunnel/quickstart/
[article repository]: https://example.com
[Access]: https://www.cloudflare.com/products/cloudflare-access/

## Further reading

* Argo docs
* Argo Tunnel docs
* Access docs
