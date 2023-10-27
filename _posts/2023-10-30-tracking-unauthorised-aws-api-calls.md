---
layout: post
title: "Tracking unauthorised AWS API calls to drive platform improvements"
date: 2023-10-30 08:00:00 +0100
categories:
  - AWS
  - Athena
  - Glue
  - CloudTrail
---

In the DevOps space, it's really tempting to hit everything with the automation
stick. However, I'd argue there are plenty of valid reasons for wanting a
human in the loop. If you're part of a platform team, you'll be used to
balancing the needs and desires of multiple teams - especially when it comes to
Identity and Access Management (IAM). In this post we're going to explore how
we can use data you're (hopefully) already collecting to understand what's
happening in our AWS organization, and to inform change????

## CloudTrail

If you've missed it, CloudTrail is an AWS Service that records an audit log of
API calls. It's really easy to setup, can aggregate API calls from all accounts
in the organization and is cost-effective to boot.

This article assumes that you've configured CloudTrail in the organization
management account to aggregate all API calls into one S3 bucket.

## What can we learn from unauthorised API calls?

We're not trying to detect security breaches or users doing things they're not
supposed to in this solution. Instead, we're looking for the following:

* API activity in regions we don't expect;
* Users trying to use new services;
* AWS API calls that have changed IAM actions;
* New API calls or IAM actions that have been added to services;

## Solution architecture



![EventBridge triggers a Lambda function on a schedule, it queries Athena. Athena uses Glue for the schema, and reads CloudTrail data from an S3 bucket.](/assets/tracking-unauthorised-aws-api-calls/architecture-diagram.png)
