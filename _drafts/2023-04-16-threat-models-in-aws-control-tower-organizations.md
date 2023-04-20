---
layout: post
title: "Threat models in AWS organizations managed with Control Tower"
date: 2023-04-16 16:49:00 +0100
categories:
  - AWS
  - "Control Tower"
  - "Identity & Access Management"

---

[Control Tower] can be a convenient way to setup an AWS organization with some
basic guard-rails and auditing configured. It brings an opinionated set of
accounts and infrastructure, including a number of roles it uses to perform
various actions. Let's explore how these resources link together and what we
must defend against as Cloud Engineers using Control Tower.

[Control Tower]: https://aws.amazon.com/controltower/
[CloudTrail]: https://aws.amazon.com/cloudtrail/

## A quick primer on accounts

Control Tower sets up the following accounts:


See **THE DOCUMENTATION** for a more detailed description of these.

## Resources deployed by Control Tower

To create a new account in Control Tower, we provision a product in
[Service Catalog]. You won't find much if you inspect the CloudFormation
template that's used here - it's really just a placeholder that makes
Control Tower perform actions behind the scenes. So what does Control Tower
actually do? For the majority of accounts in your organization that run
workloads (apps / services), it creates a handful of roles via SDK calls and
then it deploys CloudFormation StackSets to manage the remainder of the
infrastructure.

Here are the roles Control Tower creates:

| Role | Purpose |
|------|---------|
|      |         |
|      |         |
|      |         |
|      |         |
|      |         |

You can view the entire set of actions by creating a new account in your
organization and interrogating the CloudTrail logs.

[Service Catalog]: https://aws.amazon.com/servicecatalog/

## Delegated administrator accounts

A note on delegated administrator.

## Threat model for the audit account

For example a simple developer role being able to access anything.

## Threat model for the organization management account

For example use of the control tower role to delete CloudTrail resources.

## Service Control Policies (SCPs) and the management account

A note on SCPs in the management account.

## Practical mitigations

Practical mitigations.

A note on CI/CD in the master account and CI/CD in the audit account - for
example, replacing an existing system with AWS native tools like CodePipeline.
