---
layout: post
title: "Load balancing GRPC services in the Elastic Container Service with Traefik"
date: 2019-02-04 21:01:00 +0100
categories: GRPC ECS AWS Docker containers load-balancer ELB NLB ALB
---

Despite the popularity of Kubernetes, AWS's Elastic Container Service (ECS)
offering is fantastic for many containerised workloads and avoids a lot of the
complexity that comes from using and operating a full-blown container
orchestration platform. Add in Fargate with its attractive pricing and low
management overhead and you have a great way to easily host containers. One
challenge of using the managed AWS load balancers that work so effortlessly
with ECS services is that they don't support GRPC (or end-to-end HTTP2) and
thus you're left with layer 4 (TCP) load balancing that balances per connection
and not per call. This is problematic as load isn't spread evenly between
nodes, as seen in our example below in which 100 calls are made from a client
through an AWS Network Load Balancer (NLB) to two instances.

![This ECS task received all of our test requests](/assets/traefik-load-balancing/all-requests.jpg)

The above ECS task received all requests while the other task (pictured below)
received none.

![This ECS task received no requests](/assets/traefik-load-balancing/no-requests.jpg)

As you can see, the load isn't shared and we don't gain the scalability
benefits of having a second instance. While this is a challenge in proxy-based
load balancing, it's worth noting that there are [many other LB strategies for GRPC]
and you should evaluate what's right for your setup, rather than jumping to
proxy load balancing that may feel very familiar if your background is in
HTTP/1.1 REST based APIs.

Although they don't handle GRPC well, the built-in load balancers conveniently
add or remove targets as services scale. We can use Traefik to retain this
benefit whilst also adding call based load balancing for GRPC, advanced features
like circuit breakers or request tracing and even weighted [load balancing
strategies].

[many other LB strategies for GRPC]: https://grpc.io/blog/loadbalancing
[load balancing strategies]: https://docs.traefik.io/basics/#load-balancing

## ECS service setup

The example pictured above is sending requests to a toy Go based service that
produces random numbers falling between the supplied min & max. We start by
containerising it and then create a task definition and service to start some
containers. A key feature for us is the ability to use the "Docker labels"
section of the task definition to supply configuration to Traefik as we'll
see later in the Traefik web UI.

## Traefik configuration

Once we have the service running in ECS, we can configure and run one or more
Traefik instances that will be used to load balance our service. The Traefik
configuration file is pictured below and uses the ECS provider to search for
services to load balance and identify each of the tasks that are running for
our service.

```toml
debug = true

[entryPoints]
  [entryPoints.http]
  address = ":50051"

[api]

[ecs]
clusters = ["main"]
region = "eu-west-1"
# accessKeyId = "..."
# secretAccessKey = "..."
```

With the above config, we're turning on debug messages (useful to diagnose
authentication issues with AWS), creating the equivalent of a "listener" in
AWS terms (the entry point), enabling the Traefik UI and setting up access to
ECS. You'll need to run the load balancer as an IAM role or user with the
permission in the [ECS provider documentation].

After launching Traefik, it will pull down the running services in your ECS
cluster and on the web UI (port 8080), produce the following frontend(s) and
backend(s):

![The Traefik web UI shows one frontend with the Host service-rng-service-app and one backend with both of our containers](/assets/traefik-load-balancing/traefik.jpg)

Both of our containers have already been registered and we have a frontend that
we can now direct traffic to. The default rule configured by Traefik would send
all traffic for the host `service-rng-service-app` to our service but we can
change this by setting a Docker label of `traefik.frontend.rule` to any value we
like in the task definition. As our simple example isn't configuring SSL / TLS,
we'll also need to change the default protocol from "http" to "h2c" to handle the
GRPC requests. Once our service has redeployed, we can see that the "Route rule"
and protocol have been updated:

![The container in our task definition has a Docker label set to change the route rule](/assets/traefik-load-balancing/docker-label.jpg)

![The frontend in Traefik shows the new value](/assets/traefik-load-balancing/updated-route-rule.jpg)

There are a plethora of configuration items that can be set with Docker labels
and these are listed in the [ECS provider documentation]. As the load balancer
is updated automatically, ECS service operators aren't required to have access
to load balancer configuration to route traffic to their services.

[ECS provider documentation]: https://docs.traefik.io/configuration/backends/ecs/

## Our initial test again

As you can see in the logs below, the same 100 requests to the newly Traefik
proxied service are now shared evenly between the two backend service
instances.

![Two ECS task logs with equal load](/assets/traefik-load-balancing/after-traefik.jpg)


## Is this the right solution for me?

GRPC is load balanced in many different ways and it's very important to assess
which is the most relevant for your environment as proxy load balancing may not
be the most appropriate. See the GRPC documentation for examples of other load
balancing methodologies.

Even with the overhead of managing Traefik instances, the ease of use and
configuration coupled with the power of Traefik makes it a really appealing
option for load balancing GRPC-based ECS services.
