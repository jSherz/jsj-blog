---
layout: post
title: "Shift security left with AWS Config"
date: 2023-05-27 19:17:00 +0100
categories:
  - AWS
  - security
  - Terraform
  - Lambda
---

No-one likes a telling off from the security team, and we can't rely on good
will and experience to keep our infrastructure secure: we have to make
comprehensive guardrails. One of the services commonly used to achieve that is
[AWS Config].

[AWS Config]: https://aws.amazon.com/config/

## What is AWS Config?

**NB:** if you're playing around with AWS Config in a lab environment, please
be aware of the pricing. _It's not free_ and I spent around ~£20 deploying a
realistic set of rules to my lab environment (~114 rules, ~7 AWS accounts) and
leaving them running for a fortnight.

AWS Config lets you define rules that check your resources are built against
best practices - both AWS' and those of your own organization. Example rules
include:

* Checking an S3 bucket has a public access block enabled.
* Checking a DynamoDB table has Point-in-Time-Recovery (PITR) enabled.
* Checking an IAM user has MFA enabled.

The full list is in the docs: [List of AWS Config Managed Rules]

[List of AWS Config Managed Rules]: https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html

## How are AWS Config rules defined?

<img alt="AWS config rules are defined in conformance packs, organization conformance packs, and in the AWS account itself. You can also add custom rules." src="/assets/shift-security-left-aws-config/config-rule-sources.png" style="max-width: 500px"/>

There are a number of sources for Config rules. You might define a
"conformance pack", a YAML-based template for a set of rules and their
configuration. You could also define an organization conformance pack in your
management account and deploy it to all member accounts. Some AWS security
services also manage the creation of rules, e.g. the "security standards" that
are part of [Security Hub]. These rule sources can be combined with rules
deployed to individual accounts, for example if a workload has stricter
compliance needs than the rest of your organization.

[Security Hub]: https://aws.amazon.com/security-hub/

## Where do AWS Config reports go?

![A screenshot showing four AWS accounts and the number of config rules failing in each.](/assets/shift-security-left-aws-config/config-aggregator.png)

One of the more powerful features of AWS Config is being able to aggregate all
findings into a central account in your AWS organization. We can centrally
deploy rules, and then have each account report back with non-compliant
infrastructure.

So far, so good!

## Flow and fast feedback

We've had a whistle-stop tour of what Config rules are, how they're defined,
and how reporting is done, but how does that help us as a human building
infrastructure? We're interested in keeping flow with our current piece of
work, not on fancy dashboards in a far away account. How can we ensure our
infrastructure meets the required standards without an e-mail arriving from
another team two weeks after we made it?

### Developer-centric tooling

One option we have is to embed a tool like [terraform-compliance] or [cdk-nag]
in our build pipeline. This is a big help, but there's some effort required to
keep the rules of those tools in-sync with the Config rules to our AWS account.

[terraform-compliance]: https://terraform-compliance.com/
[cdk-nag]: https://github.com/cdklabs/cdk-nag

### Feedback in the Pull Request

You can love or hate Pull Requests, but many teams use them as a way to prepare
work before it's checked in to their main branch. What if we could get feedback
on our infrastructure before we've even hit the big green merge button?

Let's make it happen!

**PS:** if you want to skip straight to the code, checkout
[jSherz/shift-security-left-aws-config] on GitHub.

[jSherz/shift-security-left-aws-config]: https://github.com/jSherz/shift-security-left-aws-config

## A quick segue into tags

This solution will rely on tags that indicate which project the infrastructure
resources are for, and which git branch they're deployed from. I really hope
you've already got a tagging standard defined in your organization, but if not
there really is no time like the present to start.

No strategy? ["Defining and publishing a tagging schema"] in the AWS docs is a
great place to start, and you'll notice that the tags below follow a similar
standard.

["Defining and publishing a tagging schema"]: https://docs.aws.amazon.com/whitepapers/latest/tagging-best-practices/defining-and-publishing-a-tagging-schema.html

We're going to use two tags for our resources:

| Tag name                    | Example value                                            | Purpose                                                       |
|-----------------------------|----------------------------------------------------------|---------------------------------------------------------------|
| jsherz-com:workload:project | git@github.com:jSherz/shift-security-left-aws-config.git | Identifies which GitHub project contains this infrastructure. |
| jsherz-com:workload:ref     | feature/my-cool-thing                                    | Helps us find the right Pull Request for this infrastructure. |

The names aren't important - you can customise the values in the code for this
solution - but we want to be able to quickly identify the right project that
contains the Infrastructure of Code (IaC) for the resources we build.

## Responding when resources fail compliance checks

We want to give a user feedback ASAP when their resources fail a compliance
check. We'll do this by listening for notifications from AWS Config and then
triggering a Lambda function which can add a GitHub Pull Request comment. It's
not as fast as the in-editor feedback you'd get with a compiler/linter, or the
in-pipeline feedback you'd get with a tool like terraform-compliance, but it
gives feedback that's accurate and up-to-date with our organization-wide
standards.

Here's what that feedback will look like:

<img alt="A screenshot from a comment on a Pull Request notifying the user that their S3 bucket is non-compliant" src="/assets/shift-security-left-aws-config/pull-request-feedback.png" style="max-width: 700px"/>

If the user can't identify what the rule relates to by name, they can click the
link to see its description in the AWS console. Additionally, they can view the
resources itself in the Config portal to find out any other rules that have
failed.

Here's what the architecture that powers that looks like:

<img alt="A diagram showing AWS Config sending an EventBridge event to the default event bus when a resource is non compliant. A Lambda function uses a rule to receive the event and add a comment to a GitHub Pull Request. The Lambda function uses Secrets Manager to retrieve an auth token and Config to get the resource's tags." src="/assets/shift-security-left-aws-config/architecture.png" style="max-width: 800px"/>

We listen to the default EventBridge event bus to be notified when a resource
has been detected as non-compliant. We'll grab credentials from Secrets
Manager, lookup the resource's tags and then add a comment to the relevant
Pull Request in GitHub.

## Putting it all together: the GitHub App

If you want to get stuck in to the code behind this solution, you can view the
[jSherz/shift-security-left-aws-config] project on GitHub.

Let's setup a GitHub App in our GitHub organization. It'll be private and thus
not available for any user/organization on GitHub to install.

1. Create the app _in your GitHub organization_:

    ![GitHub screenshot showing the option to create a new app.](/assets/shift-security-left-aws-config/github-app-setup1.png)

    ![GitHub screenshot showing app name selection.](/assets/shift-security-left-aws-config/github-app-setup2.png)

2. Use a service that can capture requests, e.g. webhook.site to listen for the
   app being installed in step 4:

   ![GitHub screenshot showing webhook.site being used as the callback URL.](/assets/shift-security-left-aws-config/github-app-setup3.png)

3. Allow read/write access of issues and pull requests:

   ![GitHub screenshot showing issues with read/write access.](/assets/shift-security-left-aws-config/github-app-setup4.png)

   ![GitHub screenshot showing pull requests with read/write access.](/assets/shift-security-left-aws-config/github-app-setup5.png)

4. Install the application:

   ![GitHub screenshot showing the install button to add the app to our organization.](/assets/shift-security-left-aws-config/github-app-setup6.png)

5. Note down the installation ID - we'll need it later.

## Putting it all together - AWS infrastructure

With the app setup, we can complete the final step of deploying the
[jSherz/shift-security-left-aws-config] project. I'll leave you to the
instructions in that README to get the Lambda function deployed and to
configure GitHub API access. It's (almost) as simple as a `terraform apply`.

## What did we achieve?

With that solution in place, we can tag the infrastructure deployed for our
Pull Requests and have near-instant feedback that helps us understand if
we're meeting our organization's compliance needs. Compliance isn't sexy, but
staying in a flow state and getting feedback on the spot sure is.

At least to me anyway.

Security is everyone's job, and now we've put the right tools into the hands of
the people building the infrastructure. They get to fix any problems before the
IaC code has even landed on the main/trunk branch.

## Further reading

We've scratched the surface of a few important services in this post. Here's
some ways to deepen your understanding:

* Find out which AWS Config rules your organization deploys, and how they're
  managed (e.g. organization conformance packs vs Security Hub standards vs
  deployed into each account).

* Evaluate your current tagging strategy. Does it let you easily find the
  source of a piece of infrastructure? How about the team that's responsible
  for it? Are Cost Allocation Tags configured to let you pinpoint who's
  spending what?

* If Config seems prohibitively expensive - even in lab use cases - what other
  tools are available? There are third-parties that fill the same niche, and
  even save you some pennies!
