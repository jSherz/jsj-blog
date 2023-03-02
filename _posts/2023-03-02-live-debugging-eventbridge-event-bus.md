---
layout: post
title: "Live debugging EventBridge Event Buses"
date: 2023-03-02 20:19:00 +0000
categories:

- AWS
- EventBridge
- "Event Bus"

---

![An animation showing events describing products being updated and created arriving on an Event Bus.](/assets/live-debugging-eventbridge-event-bus/demo.gif)

When you hear the term "Event Bus" you might start getting flashbacks to days
spent reading a book on Java design patterns. Fear not - these days they're
back in fashion, especially with the AWS service CloudWatch Events that
morphed and evolved into its own offering under the EventBridge moniker.

We could debug EventBridge Event Buses through conventional means like [logs]
and [tracing], but where's the fun in that? Sometimes it's just far easier to
understand what's going on in your systems with a visual display. Demos that
show an auto-refreshing screen in CloudWatch logs just don't _pop_ in the same
way as seeing new events arrive on-screen with a flash of colour. Let's fix
that!

[logs]: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes-event-target.html#pipes-targets-specifics-cwl
[tracing]: https://aws.amazon.com/blogs/compute/using-aws-x-ray-tracing-with-amazon-eventbridge/

OK let's segue to the serious side for just a moment: this blog post is an
accompaniment to [a GitHub project] that shows how API Gateway can be used to
host a websocket API that receives events from EventBridge and passes them on
to users of a React Single Page Application (SPA). It's a practical but fun
way of showing how you can send and receive events and do something useful,
designed as a learning aid for users who are new to EventBridge. Here's the
architecture:

[a GitHub project]: https://github.com/jSherz/live-debugging-event-bridge

![An architecture diagram showing events flowing from a Lambda function into Event Bridge and out to websocket users via API Gateway](/assets/live-debugging-eventbridge-event-bus/Live Debugging EventBridge.drawio.png)

**PS:** you can download the above PNG and open it in diagrams.net to play with
it.

As a user of the application, we start toward the top of the diagram by
connecting to the websocket API hosted by API Gateway. A connection Lambda
function is triggered which adds our connection ID to a DynamoDB table of all
the current users. When the generator Lambda on the left of the diagram is
triggered, it sends test events into our Event Bus. It's got some random delays
for added dramatic effect.

A rule is attached to the Event Bus, and this sends our events to a Lambda
function that checks the DynamoDB table for users and forwards them on as
websocket messages. When a user disconnects, another Lambda function is
triggered to remove their connection ID from the table.

Checkout [the source of those Lambdas on GitHub] to see how each one works.

[the source of those Lambdas on GitHub]: https://github.com/jSherz/live-debugging-event-bridge/tree/main/infrastructure/src/handlers

You've seen the gif. You've got the code. Go forth and share fun demos with
your team as you show them the power of fully managed event sending.
