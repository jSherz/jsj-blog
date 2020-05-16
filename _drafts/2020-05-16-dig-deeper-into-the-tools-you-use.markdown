---
layout: post
title: "Dig deeper into the tools you use"
date: 2020-05-16 12:48:00 +0100
categories:
  - TypeScript
  - Node.JS
  - Node
  - JavaScript
---

I did a talk recently at a local meet up about doing devil style practises in a
small team and how you can achieve quite a lot without huge, dedicated develops
resource inside your organisation. I think it's really valuable. Teo. Try and
apply a lot of the principles ofthe develops and sight reliability engineering,
even if you can't do them all perfectly, or even if you have to do them on a
much smaller scale than some of the big companies are, especially with things
around. Monitoring metrics on DH Centralised logging. You can gain a huge amount
of value without either a large mint lee expenditure on infrastructure or lots
of operational stuff that will actually managed the tools that you use. One of
the participants at that tech meet up asked me a question at the end of the talk
and said, Why don't youse communities? I think this is a good advance. Good
example, off the constant fight we have in tech around the battle between what's
the latest, greatest shiny thing that some of the big players are using on what
works really well for your team or organisation. But in our discussion about
that topic. Hey asked why would wanted to be so familiar with, um, the
technology before adopting it. And I said to him that Cuban, I see is a very
complicated piece of technology, and so if I were going to recommend it to my
team, I would want Teo very thoroughly understand it before that point that
followed the excellent get hub Siri's by Chelsea Hightower called Cuban as he's
the hard way where you go about setting up a Cuban issues cluster in Google
Cloud from scratch. It shows you the number of components that are involved in
your application running on Cuban aunties and also covered some of the topics
like generating certificates that allow components to authenticate with each
other on DH, configuring and running them. One of the problems with adopting a
new tool or system is that a managed provider of the system hides a lot of the
complexity from you, but you may still have to deal with that complexity in the
future. On one of the key areas is with fault finding in the system. If you've
been through trying to set up or run a piece of technology, for example, a
database Q system or message broker. Then you often find out that something
doesn't work. Perhaps you haven't configured it quite correctly, or it can't
communicate with another piece of the application. Right? Texture. Andi, when
you're trying, Teo diagnosed that fault or a shoe, you're forced to get familiar
with the configuration, so you see what options are available. Onda, also with
the error reporting functionality that the system has. Often you find that
systems that run a very large scale, like elastic search don't don't put much
information by default purely because it would be overwhelming in a large scale
system. But you might actually want to know a lot more about what's going on.
You might also find that the technology is very hard to debug if the logs that
it produces aren't very helpful, or if components fail without producing any
logging, it all. One common case of this, it is pull logging around timeout.

when setting up a system from scratch on reading through the documentation and
configuration files they provided. You often see a lot of hints around how they
intend you to deploy the software or you see things to do with they requirements
of the machine that's actually going to run it. All the machines will run it.
So, for example, it might suggest that you store a particular directory in on a
separate disc because the performance of that directory is very important. Or it
might say that you shouldn't store two components on the same system. For
example, with CAFTA, they recommend not having zookeeper on the same machine is
the calf gannet itself. When you've been through these phases of reading
documentation, looking at best practises for deployments, potentially even
watching videos and how the software is deployed, performance tested and
operated, large companies or elsewhere, you got a much better idea when looking
at trial providers or manage service riders of what they're providing and how
closely it fits with what the best practise might be for that software. You
might see that, for example, with a Catholic a provider, they are storing
zookeeper on the caftan owed. But accept that because it saves some money over
having a dedicated zookeeper cluster where each member of the cluster is on a
separate machine. But at least if you've been to the configuration file and
you've read the documentation on DH red around the system a bit, you can make
better decisions about, um, whether that clam provide his method of running. It
is appropriate for your use case.
