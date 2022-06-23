---
layout: post
title: "Break glass access in AWS with Step Functions"
date: 2022-06-23 19:52:00 +0100
categories:
- Step Functions
- SRE
- Lambda
- API Gateway
- serverless
- break glass access
---

No-one wants unfettered, widespread access to production all the time, but the
pager does have an awful habit of going off and - if your tooling fails you -
you might have to pop into a production account to have a look around. I've
recently been playing around with the use of AWS Step Functions to orchestrate
this access. Our journey starts in Slack, with a notification about an alert
or deployment that may require us to elevate our access in an emergency:

![A Slack message from the bot user "Live Laugh Ship" reports that a 
deployment has failed and presents two buttons, one to retry and another to 
get break glass access to production](/assets/break-glass-access-in-production/slack-notification-1.png)

When we press the "Break Glass Prod" button, Slack's interactivity feature sends
a webhook to API Gateway, which then starts up our Step Function and reports 
back with an ephemeral message:

![A Slack message saying "Glass broken - access incoming".](/assets/break-glass-access-in-production/slack-notification-2.png)

The Step Function has a few stages. First, we grant temporary access with AWS
SSO. Setting up a permission set ahead of time lets us easily assign emergency
access when required, while keeping the ability to develop and test the policy
outside the scope of this application. We then wait an hour (or configurable
amount of time) and revoke the access. After the access is gone, we wait for
CloudTrail to have reported back everything that the user did and then e-mail a
report to a user or delivery list. Here's what the report looks like:

![An example e-mail report in which the user's email is shown, along with
the date and time of their access. Two tables are below that information,
one showing the user's access in the AWS SSO portal, one showing their
actions once logged into an account.](/assets/break-glass-access-in-production/access-report.png)

Each of the activities in the Step Function is performed with Lambda. Step
Functions can make native AWS API calls themselves, but we're sprinkling
in some other logic and formatting that makes me lean towards some proper code.
The combination of API Gateway, Step Functions, DynamoDB and Lambda gives us a 
neat, serverless solution, perfect for a low traffic use case like this.

![A graph showing a Step Function with stages "Grant Access", "Wait For 
Access To Expire", "Revoke Access", "Wait For CloudTrail" and "Report Access".](/assets/break-glass-access-in-production/sfn-graph.png)

View the app code and Terraform infrastructure [on GitHub].

[on GitHub]: https://github.com/jSherz/break-glass-access
