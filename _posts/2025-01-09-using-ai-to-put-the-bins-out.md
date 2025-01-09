---
layout: post
title: "Using AI to put the bins out"
date: 2025-01-09 19:56:00 +0000
categories:
  - AI
  - Bedrock
  - Claude
  - AWS
---

Aside from using GitHub's Copilot when coding, I've not dabbled much in the
tools that have appeared from the recent AI craze. Generating funny images is
one thing, but I haven't seen many use cases that are a meaningful improvement
over what I could search for or do manually. Over the Christmas period, I found
that I could request e-mail reminders from the local council for when I was due
to put a wheelie bin out the following morning. I already run my whole life on 
Todoist - it helps me with everything from keeping track of my tasks in the
working day to remembering birthdays - so I was keen to see if I could parse
the relevant information out from those e-mails and feed it into a Todoist API
call. Normally this would be a painful exercise in parsing information and
hoping that nothing about the structure of the e-mail changes over time, which
is never realistic. I started to wonder, could I use AI to process this text?

## Laying the foundations

As someone outside of most of the AI hype, I wanted to be able to try different
models and compare how well they worked for my use case. I didn't want to have
to sign up to multiple providers and load in some credits or pay for a
subscription, so I was very keen to try out AI models on AWS' Bedrock. I
started by finding a region with reasonable latency that had the models
available. At the time of writing, there are restrictions on access in
Ireland, but Frankfurt had everything I needed. I chose Meta's Llama 3.2 3B
Instruct v1 and Claude 3.5 Sonnet by Anthropic.

It only took a few minutes for my requests for these models to be approved,
and so it's on to the architecture design!

## An architecture for processing e-mails with AI

![AWS SES receives e-mails and saves them to an S3 bucket. It also notifies a Lambda function that reads from the S3 bucket and creates a task in the Todoist API.](/assets/using-ai-to-put-the-bins-out/architecture.png)

We'll use SES incoming to receive e-mails going to an address we chose, for
example `put-the@bin-out.example.com`. It will place the e-mail into an S3
bucket in its raw form, and then trigger a Lambda function. We'll use the
Lambda to call AWS Bedrock, process the message and send a REST request to the
Todoist API.

## When the machines can talk

Calling text-based models in Bedrock is simple as we can use a chat-style API
to give our AI instructions on how to behave. We can then feed it some user
input, in this case the e-mail, and have it respond back to us. But how do we
generate machine-readable output?

Bedrock lets us set a 'system' prompt that teaches the AI how to behave, and my
first iteration of this looked as follows:

```text
You are a bot that receives e-mails that might be about putting a bin out the
following day. Respond with a JSON object with the following fields:

- 'isReminder': checks if this is an e-mail about an upcoming collection.
- 'day': the day the bin should be put out in ISO 8601 format.
- 'bin': the type of bin that should be put out.
```

For chat messages, I sent something like this:

```
Here's the e-mail:

**email text here**
```

I stored this prompt as a string and then appended the text of the e-mail at
the bottom, but this didn't have good results. Often the AI would return extra
characters or other information outside the JSON object, and that made parsing
the response very challenging. I then found a brilliant tip: ask the AI to
improve the prompt you've given it!

## A quick tip for faster feedback

To iterate faster, I would recommend using the "Chat / Text" playground in
Bedrock. I did this in code the first time around, and that made things fiddly
when I had to switch from one model to the next.

![The AWS Bedrock Chat/Text Playground with a 'system' prompt text area and a window that looks like an instant messenger where you can enter text](/assets/using-ai-to-put-the-bins-out/chat-window.png)

## Machines telling machines what do to

The prompt for improving my prompt was very simple: "How can I improve this
prompt: &lt;existing prompt&gt;". I'll summarize the tips that the AI provided:

* **Use HTML-style tags.** I surrounded each part of the prompt in tags that
  look like HTML. For example:

  ```text
  <instructions>
  ...
  </instructions>
  
  <email>
  ...
  </email>
  ```

* **Clarify how the output should be delivered.** One thing I didn't think to
  do was to tell the AI not to include any extra characters other than the
  JSON. That made a surprisingly big difference.

* **Return a confidence score.** A really helpful diagnostic tool was asking
  the AI to add an additional field to the response body with a confidence
  score. If that was low, I could have my application return an error or refuse
  to create a task.

* **Add error handling.** I always specified the `isReminder` field in the
  prompt, but initially I didn't include clear instructions about how to handle
  error cases.

* **Clarify the problem space.** Sometimes the AI would be too smart and think
  of edge cases that can't be possible in the real world. For example, the
  council will never collect more than one bin in a day. I added extra
  instructions that defined these "rules" that may not be obvious to a
  computer.

## Did it work and would I do it again?

With some trial-and-error in prompt engineering, Bedrock returned trustworthy
JSON that I have successfully been parsing to power reminders. I've spent a
grand total of two cents on AI models so far, which feels like good value for
having a play and learning some more about how I can augment tricky text
processing jobs.

<img alt="The Todoist UI, showing a task for putting the general waste bin out." src="/assets/using-ai-to-put-the-bins-out/todoist-window.png" style="max-width: 70%">

As you can see above, it worked great for me - even if my use case is rubbish!
