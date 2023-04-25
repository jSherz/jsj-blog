---
layout: post
title: "Terraform vs. CDK"
date: 2023-04-24 15:24:00 +0100
categories:
  - AWS
  - CDK
  - Terraform

---

At the time of writing, there are at least five mature options for deploying
Infrastructure as Code (IaC) to AWS. After working professionally with CDK
for around nine months, I'm now ready to offer my comparison of the only two I
know confidently: Terraform and CDK. I'll start by saying that I believe both
are excellent tools and have their own flaws. I'm exceptionally grateful to the
Terraform community, including HashiCorp employees, for the time and energy
spent keeping up with AWS changes.

## My goals for an IaC tool

It's unlikely that you have exactly the same needs that I do, so let's start by
discussing what drives my choice of an IaC tool:

* **Manageable barrier to entry:** I don't care if a tool has a learning curve
  or takes some time to bed in. I want capable engineers to be able to make
  small changes to mature projects in an afternoon, but I'm much more focused
  on how the tool performs over time.

* **Suitable for enterprises:** My cynical view is that many projects, not just
  IaC ones, optimise for the experience of "zero to something". Following a
  simple tutorial and deploying a serverless API in under thirty minutes is
  very gratifying, but I need a solution that works well when you're building
  to best practices and encapsulating organization-wide standards.

  I don't mind "zero to something" being a bit tricky if "zero to gold-plated"
  is easier in a given tool.

* **Fast feedback for iterative development:** Deploying changes should be
  rapid when you're in the development phase in an appropriate AWS account.

* **Wide support for AWS resources:** I need everything from serverless, to
  containerised, to organization resources and account-level settings.

* **Ability to work in a messy world:** If I'm making a complex piece of
  infrastructure for the first time, I'll often go via the relevant AWS wizard
  in the web console and then recreate it in IaC. I want a tool that makes that
  development flow simple, even when resources have many properties.

  I want the ability to refactor my IaC code without disrupting live services.

  I want the ability to change resources by hand to mitigate or resolve
  incidents and then to go back and make sure I don't miss those changes in
  IaC.

## Where do I think CDK has advantages?

* Heavy serverless.
* No use of existing resources.
* Easy to throw away most or all resources.
* Custom resources and calls are much easier, but much more necessary.

## Where do I think Terraform has advantages?

* Speed.
* Nice resources.
* Importing.
* Drift detection.
* Any services where retrying is required.
  * Retrying behaviour of CloudFormation is not as robust as Terraform -
    solution: lots of custom glue code to make resources.

## What would I change to improve CDK?

* Ditch CloudFormation.
* Constructs do not include best practices, especially when they’re for your 
  org - must make Terraform modules.
* Plugin API: Lack of common lookups is painful, including by tag.

## What would I change to improve Terraform?

* Commercial support with SLAs around resource updates.
* Bounties on new resources / bug fixes.

## What about cdktf? Is that the best of both worlds?

* No.
* Same abstraction overhead as CloudFormation + CDK.
* Lacks the OO DX of normal CDK.
* Not interchangeable with CDK - one way door.

## What tool will I use going forward?

* Terraform.
  * With my Lambda provider.
