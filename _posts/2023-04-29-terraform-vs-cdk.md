---
layout: post
title: "Terraform vs. CDK"
date: 2023-04-29 10:45:00 +0100
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
magic. Using managed services like EventBridge, Lambda, SQS, and SNS is a real
treat. You don't have to understand all the components - it "just works".

Lambda functions and container images coexist effortlessly in a repo that
contains the infrastructure to deploy them. I think this is a fantastic dev
experience, and is why I created [a Terraform provider] for doing this with
NodeJS-based Lambdas.

[a Terraform provider]: https://jsherz.com/terraform/lambda/2023/04/22/lambda-packaging-in-terraform.html

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
can move whole groups of resources, change their logical name (akin to an ID in
CDK) and not have any impact on what's live in AWS. Terraform state
modification can go very wrong, just like a git rebase or similarly powerful
tools, but to an expert user it's invaluable. In CDK, resources are named based
on their location in the constructs you have, and thus any refactoring is
disruptive. AWS themselves recommend that you rely heavily on tags and keep
CDK's default resource naming, but support for finding resources in the AWS
console by tags is very hit-and-miss. Where do you inspect the state of
resources in an incident? In the console.

CloudFormation does support importing existing resources into its management,
but only ~60% of the ones it has available. You must also get the
configuration exactly matching first - Terraform on the other hand will just
update it to be in the state you desire. The `cdk import` command is a great
help in orchestrating this, but it's still in the early stages of development,
and I've hit some bugs where it wouldn't accept the same input that
CloudFormation requires for an equivalent import.

### KISS

A very contentious point in the choice of Terraform over other tools is the
Domain Specific Language (DSL) that it uses: Hashicorp Configuration Language
(HCL). My take? It makes you do some weird things, but in exchange you avoid
much of the complexity of how code could - but shouldn't - be structured. You
don't have to write tests for how Postgres handles your SQL - you just write
tests on the result - and I believe that this is the same with the choice of
an imperative/OO language vs. a declarative one for IaC.

I have fairly strong opinions about the use of frameworks for application
development: I believe you either use a framework, or end up writing your own.
The difference is that a pre-made framework has documentation, tutorials, and
(some) consistency between projects that use it. With CDK, you're on your own
building infrastructure in a fully fledged OO programming language. If you're
from a development background, that may feel like an advantage. For me, the
constraints of HCL push you toward simplicity and a consistent structure.

With the above said, you might be desperate to tell me that you've got
brilliantly complex IaC solutions that cannot be expressed with the logic
available in HCL. My suggestion? Generate a Terraform variables file that acts
as a faux projection of the infrastructure you want to make, and do so in a
programming language of your choice.

How many times have I had to do this in the last ~5 years of building
infrastructure as a day job? Twice.

### Referencing existing infrastructure

Terraform has "data sources" that allow you to reference existing pieces of
infrastructure. CloudFormation supports looking up values from SSM parameters
and Secrets Manager secrets, and also CDK has lookups for a limited number of
items:

* Amazon Machine Images (AMIs)
* Availability Zones (AZs)
* Route53 Hosted Zone
* SSM Parameters
* VPCs
* VPC Endpoint Service AZ
* Load balancers
* Load balancer listeners
* Security groups
* KMS keys
* "plugin"

At the time of writing, Terraform has about 487 data sources. Not too shabby
compared to the above list of eleven.

When CDK queries AWS for these items, it caches the response in the file
`cdk.context.json`. If the underlying resource changes, e.g. if an update was
made to the VPC you were referencing, it's not updated in that context file,
and you'll never know something is now different. You as the user would have to
know that it had changed, manually clear the context entry, re-run a synth and
then commit the updated file.

As Platform Engineers, we often lookup values like the current organization ID
and account IDs to use in resource policies. These have to be provided to CDK,
likely with a script made in a programming language of your choice that
populates context values. We can additionally use multiple Terraform providers
to query existing infrastructure in a variety of cloud providers, SaaS tools
and even different AWS accounts or regions.

There is light at the end of the tunnel for CDK: the final "plugin" CDK context
provider. This is [marked Amazon-internal only] at the time of writing, but
I've used it successfully with a client to find data like the aforementioned
organization ID, or the IDs of organizational units.

[marked Amazon-internal only]: https://github.com/aws/aws-cdk/blob/c81d115955dbb27ce873ed7c9d71cc0dc8eacf99/packages/aws-cdk/lib/api/plugin/plugin.ts#L108

### Oh, for the love of tags!

AWS' tag policies support a woefully small number of resources compared to the
total number available. The official advice is to combine them with SCPs that
block the creation or modification of infrastructure that doesn't include tags.
This is a complete non-starter in CDK/CloudFormation - it tags the resources
with a separate API call after they've been created.

Many CloudFormation resources are also missing the property to set tags, and
thus you're back to writing custom constructs with AwsCustomResource.

## What would I change to improve CDK?

Here's a moonshot idea for you: CDK should ditch CloudFormation. I mean it! If
AWS wants to have CDK as its prized and primary IaC tool, it needs to rid
itself from the poor developer experience of CloudFormation. Bin the quirks.
Stop waiting for Godot and start building out real support for all AWS
resources. The third parties have managed it - why can't AWS?

The included L2/L3 CDK constructs do not encompass many of AWS' best practices
by default. If AWS says you should have a public access block on an S3 bucket,
CDK should have it on and force you to turn it off if you _really_ need to.
[cdk-nag] should be vacuumed up and consumed into the main project and be on
for all users. Why not make it the premier, shift-left, belt and braces tool
that makes it hard to get infrastructure wrong?

[cdk-nag]: https://github.com/cdklabs/cdk-nag

Finally, I'm keeping a close eye on how the plugin system goes. I'd really love
to see an easy way to adopt many plugins, each which supply resource lookups.
Perhaps an entry in the `cdk.json` file could have a list of them as NPM
packages? Pretty please?

## What would I change to improve Terraform?

I'm too far detached from the experiences of a new user to comment on
Terraform's state management here. Terraform Cloud is a delightful service but
the pricing for concurrent runs is abhorrent. Why not make it work like all the
other CI tools and just bill by the minute? If that were the case, new users
could have a much smoother landing into Terraform by starting with it, and
sticking with it as they work in a team.

I'd happily pay for bug bounties to have new resources added, or updates made.
Many companies use Terraform without paying a penny toward its development, and
perhaps there's a market for a commercial support plan that gives priority to
your requests in exchange for funding?

## What about cdktf? Is that the best of both worlds?

Any tool like Serverless Framework, cdktf or CDK has a double layer of
abstraction: you must understand how the top-level tool's configuration is
translated to the lower-level tool's configuration, and then how that appears
as AWS resources. When I tried it, cdktf had much of the OO paradigm magic
missing - perhaps this will change over time, and it will appear more like the
main CDK project. It's also not possible to swap backends between
CloudFormation and Terraform - I think this is a real shame as it makes either
choice more of a one-way door.

## What tool will I use going forward?

I'm sure I don't need to spell it out, but I'll be using Terraform for all of
my projects going forward, and recommending that clients I work with do the
same. Learning CDK was a very valuable experience in and of itself, and I think
all people writing Terraform day-to-day should give it a good go to compare and
discover improvements they could make to their own methods or approach.

Without CDK, I'd have never written [a Terraform provider] to achieve the same
developer experience collocating Lambda code in a Terraform project. The OO
paradigms and permission magic has really pushed me to reconsider how I design
Terraform modules and the experience that I'm providing with them. It's set the
bar very high - and now I have to see if I can have my cake.tf and eat it.
