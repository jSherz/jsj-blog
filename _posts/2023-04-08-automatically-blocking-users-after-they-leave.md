---
layout: post
title: "Automatically blocking users from AWS after they leave your organization"
date: 2023-04-10 17:07:00 +0100
categories:
  - AWS
  - "Service Control Policy"
  - "Identity Center"
  - "Identity & Access Management"

---

If your responsibilities include controlling access to systems, you'll never be
far away from the realities of people joining and leaving your workplace. In
AWS, we're advised to use the Identity Center (née SSO) to manage access to
accounts with varying permissions. Let's cover a bit of a footgun with people
who are removed from Identity Center, and how we can automatically ensure their
access is removed.

## Identity Center sessions

There are a number of sessions at play in Identity Center (described in
[the AWS documentation]). When you login to an AWS account via Identity Center,
you're assuming a role. Your role session timeout is configurable in Identity
Center itself, and can be up to 12 hours. When your account is disabled or
deleted, the credentials you received when assuming the role remain valid. Not
good for people leaving the business, especially unhappy leavers!

[the AWS documentation]: https://docs.aws.amazon.com/singlesignon/latest/userguide/authconcept.html#sessionsconcept

If you temporarily assign someone access to an account via Identity Center,
then take that access away, they only lose access when their temporary role
credentials expire. If your access strategy includes temporary access, that's
an important caveat to bear in mind.

We can aim to mitigate some of this risk by lowering the session timeout, but
this produces a lacklustre experience for your users. Can we have the best of
both worlds, a sensible session time and properly controlled access?

It's assumed for the rest of this article that you're using Identity Center
with an external identity provider like Okta, Azure AD or Google Workspaces.
This solution works regardless, but we'll talk about the solution as if you're
turning off the access in an external system first.

## AWS' solution

The [solution recommended by AWS] for this problem is to add the principals
who have been removed to a [Service Control Policy] (SCP). This does solve the
problem nearly instantly, but we don't want to have to maintain this policy
ourselves. Any manual human intervention will greatly slow our response time
to users being removed from the identity source linked to Identity Center,
and the blast radius of an SCP that's attached to all accounts is phenomenal.

[solution recommended by AWS]: https://aws.amazon.com/blogs/security/how-to-revoke-federated-users-active-aws-sessions/
[Service Control Policy]: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html

Here's the SCP we'll be automatically managing, direct from AWS' blog post:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:userid": [
            "*:JohnDoe@example.com",
            "*:MaryMajor@example.com"
          ]
        }
      }
    },
    {
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:SourceIdentity": [
            "JohnDoe@example.com",
            "MaryMajor@example.com"
          ]
        }
      }
    }
  ]
}
```

**NB:** it's worth reading the original AWS blog post to learn more about the
above SCP and its caveats.

## Designing a better solution

We can listen for events published to [EventBridge] when users are enabled,
disabled or deleted. When a user is disabled or deleted, we want to immediately
block their access to AWS. If the user is later enabled again, we'll remove the
block - for example if their user was modified in error.

![An architecture diagram showing how the identity provider is connected to Identity Center, Directory Service and EventBridge](/assets/automatically-blocking-users-after-they-leave/view1.png)

[EventBridge]: https://aws.amazon.com/eventbridge/

The source of truth for our users is the external Identity Provider, but
Identity Center keeps a copy of the users and groups relevant to AWS in the
AWS Directory Service. When the Identity Provider resources change, it uses
[SCIM] to push updates to AWS. The Directory Service then fires EventBridge
events that we can listen to in our application.

[SCIM]: https://developer.okta.com/docs/concepts/scim/

We're going to listen for events on users in Identity Center. If a user is
disabled or deleted, we're going to add them to a DynamoDB table of users
that were removed in the last 24 hours. This will ensure that multiple
leavers can be processed and placed into our SCP, and that any remaining
role sessions will have closed.

<img alt="An architecture diagram showing how the EventBridge will route events into our DynamoDB table with Lambda functions" src="/assets/automatically-blocking-users-after-they-leave/view2.png" width="800"/>

Three Lambda functions facilitate adding and removing user exclusions as
applicable. We'll use [condition expressions] to store the list of excluded
users in one item and ensure that multiple writers don't conflict with each
other. The updated item will be published to a DynamoDB stream, and we'll use
one final Lambda to form a Service Control Policy (SCP) that blocks access.

[condition expressions]: https://www.alexdebrie.com/posts/dynamodb-condition-expressions/

<img alt="An architecture diagram showing DynamoDB sending stream updates to our Lambda that updates AWS Organizations" src="/assets/automatically-blocking-users-after-they-leave/view3.png" width="600"/>

## Conclusion

It's a shame that we have to handle this use case ourselves, but this solution
removes a lot of the manual effort in removing access to AWS. You can find the
complete solution, including all Lambda function code and the Terraform to
deploy it on GitHub at [jSherz/automate-aws-access-removal].

[jSherz/automate-aws-access-removal]: https://github.com/jSherz/automate-aws-access-removal

### Caveats

Don't forget to review [the solution recommended by AWS], including the caveats
they list. Here's a brief summary and some extra things to consider:

* The AWS Organizations management account is not affected by SCPs, and thus a
  user would keep their existing access to it.

* We don't handle terminating Identity Center sessions which, at the time of
  writing, must be handled manually.

* Identity Center users could maliciously try to keep access by a number of
  methods, including:

  * assuming roles that won't be blocked by the SCP;

  * creating IAM users and keeping the access keys;

  * setting up a role that's trusted by OIDC-based access, for example with a
    secret GitHub repo they control;

  * creating an EC2 instance with their SSH key;

  * running a scheduled job, e.g. in a CI/CD pipeline, that grants them some 
    form of access.

[the solution recommended by AWS]: https://aws.amazon.com/blogs/security/how-to-revoke-federated-users-active-aws-sessions/
