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
for around nine months, I'm ready to offer my comparison of the only two I know
confidently: Terraform and CDK. I'll start by saying that I believe both are
excellent tools but have their own flaws - I don't think there's a perfect IaC
tool, nor do I think that such a tool is the goal. We have to learn the quirks
of the technologies we use to earn a living, and do our best to work around
them.

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

  It must be possible to make code changes locally and understand how they'd
  change AWS resources without actually modifying anything.

* **Wide support for AWS resources:** I need everything from serverless, to
  container-based services, to organization resources and account-level
  settings.

  If an AWS resource isn't supported, it shouldn't be difficult to build
  support for it.

* **Ability to work in a messy world:** If I'm making a complex piece of
  infrastructure for the first time, I'll often go via the relevant AWS wizard
  in the web console and then recreate it in IaC. I want a tool that makes that
  development flow simple, even when resources have many properties.

  I want the ability to refactor my IaC code without disrupting live services.

  I want the ability to change resources by hand to mitigate or resolve
  incidents and then to go back and make sure I don't miss those changes in
  IaC.

* **TypeScript support:** If the tool uses an existing programming language, it
  must support TypeScript as a first-class citizen.

  The following opinions will be given from the perspective of a TypeScript
  developer turned Cloud Engineer.

## Where do I think CDK has advantages?

I'll try and give a quick summary of CDK in-case you're new to the tool:

* It supports many languages, one of them being TypeScript.

* Infrastructure resources and common ways to tie them together have been
  modelled into object-oriented (OO) programming paradigms.

* CDK does not deploy infrastructure directly, it uses CloudFormation under
  the hood.

* CDK has "constructs", which are roughly comparable to Terraform modules.
  They start at level one which is a simple wrapper around a CloudFormation
  resource, and get progressively toward full-blown application templates as
  you reach the highest level of four.

  If you've ever had the argument about which React components fit where in the
  model of atoms, molecules, organisms, etc. you'll feel right at home arguing
  about which level your CDK construct should be.

If your team is already well versed in one of the languages supported by CDK,
it's very easy for them to hit the ground running creating AWS resources. Their
mental model of OO techniques will let them connect resources together and have
the permissions automatically configured on each end - it almost feels like
magic, and using managed services like EventBridge, Lambda, SQS, SNS is a real
treat. You don't have to understand all the components - it "just works".

Lambda functions and container images coexist effortlessly in a repo that
contains the infrastructure to deploy them. I think this is a fantastic dev
experience, and is why I created [a Terraform module] for doing this with
NodeJS-based Lambdas.

[a Terraform module]: https://jsherz.com/terraform/lambda/2023/04/22/lambda-packaging-in-terraform.html

CloudFormation and Terraform are in a constant race to keep up with all the
new and changing resources in AWS. If you're ever missing a resource you need,
it's trivial to use the [AwsCustomResource] construct to create it - in
Terraform you'd likely have to rely on a third-party provider, or create one.

[AwsCustomResource]: https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.custom_resources.AwsCustomResource.html

## Where do I think Terraform has advantages?

### Breadth of resource support

Terraform can be faster at creating resources than CloudFormation, depending on
the size of your project. It also supports a great deal more AWS resources. I
don't understand why AWS' own product lags behind third-party offerings, but it
does. Although the aforementioned AwsCustomResource construct helps you to
create custom resources easily, you'll be doing this often as a Platform
Engineer working in CDK. The construct does not gracefully handle many of AWS'
error conditions, and thus you'll likely find yourself creating a custom
version that's more robust when dealing with resources like those found in
AWS Organizations.

### IaC in an imperfect world

When you run a plan to see how your infrastructure would be changed by
Terraform, it assesses the current state of everything it manages first. In
CloudFormation, this is called "drift detection", and it's a completely
separate process. By my maths, there are 992 CloudFormation resources at the
time of writing. Drift detection is supported in 498. What does that mean for
half of the resource types you can create? Any person or tool can change or
delete them, and CloudFormation will have no understanding of what's happened.
I believe that the world is messy, and I believe that it's vital to check what
you have before you make changes. What happens if I respond to an incident and
ClickOps my way to a quick solution, then fail to revert the infrastructure
_precisely_ to how it was before? CloudFormation will never know. It will chug
along hopelessly as if nothing's changed. What happens if I accidentally
delete a resource that doesn't support drift detection? CloudFormation just
assumes it's still there. In all of these cases, I'm the human making mistakes.
I'm at fault. What do I want from an IaC tool? Help to get back to a known good
state, whatever happens to the resources.

### Support for refactoring

There are few things I find more satisfying than performing a large refactoring
in IaC without any disruptions or changes to live resources. In Terraform, you
can move whole groups of resources, change their local name (akin to an ID in
CDK) and not have any impact on what's live in AWS. Terraform state
modification can go very wrong, just like a git rebase or similarly powerful
tools, but to an expert user it's invaluable. In CDK, resources are named based
on their location in the constructs you have, and thus any refactoring is
disruptive. AWS themselves recommend that you rely heavily on tags and keep
CDK's default resource naming, but support for finding resources in the AWS
console by tags is very hit-and-miss. Where do you inspect the state of
resources in an incident? In the console. CloudFormation does support importing
existing resources into its management, but only ~60% of the resources it has
available. You must also get the configuration exactly matching first -
Terraform on the other hand will just update it to be in the state you desire.

### KISS

A very contentious point in the choice of Terraform over other tools is the
Domain Specific Language (DSL) that it uses: Hashicorp Configuration Language
(HCL). My take? It makes you do some weird things, but in exchange you avoid
much of the complexity of how code could - but shouldn't - be structured. Logic
is commonplace in CDK apps, and in my view that mandates tests of the code
itself. I don't feel this way in Terraform, I'd just focus on testing that the
actual resources are built correctly. I have fairly strong opinions about the
use of frameworks for application development: I believe you either use a
framework, or end up writing your own. The difference is that a pre-made
framework has documentation, tutorials, and (some) consistency between projects
that use it. With CDK, you're on your own building infrastructure in a fully
fledged OO programming language. If you're from a development background, that
may feel like an advantage. For me, the constraints of HCL push you toward
simplicity.

With the above said, you might be desperate to tell me that you've got
brilliantly complex IaC solutions that cannot be expressed with the logic
available in HCL. My suggestion? Generate a Terraform variables file that acts
as a faux projection of the infrastructure you want to make and do so in a
programming language of your choice.

### Referencing existing infrastructure

TBC

* Querying state file and looking for resource in .terraform folder is quick and easy.
* Resources created by constructs (e.g. log groups), not cleaned up properly. Plugging things together isn't simple as you have to understand these things created and get them made properly.
* Quality of diffs in CDK is abysmal.
* Quick note about Serverless Application Model and Serverless Framework - both still use CFN. Same double abstraction, but SAM is at least closer.
* CloudFormation builds some resources in two API calls - prevents SCPs being used with tags set. Compare to Terraform for accurate representation.
* Does CFN indicate when resource will be replaced or updated?

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
