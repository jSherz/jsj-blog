---
layout: post
title: "Enforcing AWS tags the right way - not with Tag Policies"
date: 2023-06-14 20:18:00 +0100
categories:
  - AWS
  - security
  - Terraform
  - CloudFormation
---

Tags are essential in AWS. They let us allocate costs to different teams,
projects, services or business areas, and can be critical in operational
response, for example if a piece of dangerously insecure infrastructure is
created. In [Shift security left with AWS Config], I discussed providing
near-instant feedback to builders when their resources don't meet our
compliance needs. That whole approach revolves around tags!

[Shift security left with AWS Config]: {% post_url 2023-05-27-shift-security-left-aws-config %}

With a set of tagging standards agreed in your organisation, your next thought
is likely "so how do we enforce these?", and the obvious looking solution is
AWS' [Tag Policies]. Let's examine challenges using Tag Policies and how we can
achieve a better result.

[Tag Policies]: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html

## What's so bad about Tag Policies?

### Resource support and wildcards

If we read [the documentation of supported resources], we'll immediately see
that many AWS resources just aren't supported. Additionally, there's a real mix
of services that do and don't support a wildcard syntax, e.g. `athena:*` to
target all Athena resources. This matters as we're trying to fit as much as we
can into the 10,000-character limit applied to each individual policy. How many
characters does it take to include all the supported resources, taking
advantage of wildcards where possible? 4,681. Per tag! With the rest of the
JSON document and the tag name included, we can fit about two tags per policy.
We can attach a maximum of ten policies to one organisational unit, so that 
gives us a maximum of twenty tags with the resources supported today. If you
need to exceed that number, you can add layers of tag policies in nested
organisational units to overcome the limit. I don't understand why we can't
have wildcards for every service, or even a `*:*` to target every resource, but
you didn't come to AWS for great user experience now, did you?!

[the documentation of supported resources]: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_supported-resources-enforcement.html

### Bad documentation

An additional challenge with the documentation page linked above is that some
of the values are wrong. If we take the complete list of resources and place
them into the editor in the UI, we get errors that look like this:

![AWS Organizations tag policy editor shows a JSON error - one of the resources specified is not allowed](/assets/enforce-aws-tag-compliance/tag-policy-error.png)

`backup:*`, `elasticmapreduce:*` and `wisdom:knowledge` are specified in the
docs, but aren't accepted by AWS. My preferred approach is to spelunk my way
through the source code of the UI to find the _real_ allowed values.

![Transpiled JavaScript code showing valid tag resource values](/assets/enforce-aws-tag-compliance/resources-in-source-code.png)

Taking the above list gives us 334 allowed resource types, a far cry from the
290 documented in the console. The full diff can be found at the end of the
article.

### No tags, no problem!

If we create a resource in AWS with no tags at all, or with a tag in the policy
missing, the policies aren't applied, and thus we get off scot-free. You might
be tempted to enforce the use of tags with Service Control Policies (SCPs), but
many services and tools apply the tags with a second operation once the
resource has been created or updated. The net result? We can't enforce that a
user provides the tags we want to mandate.

## What's the solution?

We've spent a fair amount of time diving into why Tag Policies aren't a great
way to ensure tag compliance, so what can we do instead? Luckily, [AWS Config]
allows us to inspect the tags on a resource and write custom rules to check
they're as we expect. If you haven't heard of Config, it's a service that
evaluates a number of rules against your resources to decide if they meet
certain compliance criteria, for example checking an S3 bucket isn't open to
the public. In [Shift security left with AWS Config], I use the query feature
of Config to write an SQL query that fetches tags for any supported resource.
Super handy!

Let's write a custom Config rule that checks a resource has the tags we
require:

TODO

## See also

* [Tagging Best Practices - AWS Whitepapers](https://docs.aws.amazon.com/whitepapers/latest/tagging-best-practices/tagging-best-practices.html)

### The full documentation vs. source code diff for Tag Policy resources

```diff
*** /Users/jsj/scratch.txt	2023-06-14 21:10:16
--- /Users/jsj/scratch_2.txt	2023-06-14 21:10:16
***************
*** 1,8 ****
--- 1,11 ----
  "acm-pca:certificate-authority",
  "acm:*",
  "acm:certificate",
+ "amplifyuibuilder:app/environment/components",
+ "amplifyuibuilder:app/environment/themes",
  "amplifyuibuilder:component",
  "amplifyuibuilder:theme",
+ "aoss:collection",
  "apigateway:apikeys",
  "apigateway:domainnames",
  "apigateway:restapis",
***************
*** 27,33 ****
  "backup-gateway:gateway",
  "backup-gateway:hypervisor",
  "backup-gateway:vm",
- "backup:*",
  "backup:backupPlan",
  "backup:backupVault",
  "batch:job",
--- 30,35 ----
***************
*** 36,42 ****
--- 38,52 ----
  "bugbust:event",
  "chime:app-instance",
  "chime:app-instance-user",
+ "chime:app-instance/channel",
+ "chime:app-instance/user",
  "chime:channel",
+ "chime:media-pipeline",
+ "chime:meeting",
+ "cleanrooms:collaboration",
+ "cleanrooms:configuredtable",
+ "cleanrooms:membership",
+ "cleanrooms:membership/configuredtableassociation",
  "cloud9:environment",
  "cloudfront:*",
  "cloudfront:distribution",
***************
*** 47,52 ****
--- 57,63 ----
  "cloudwatch:alarm",
  "codebuild:*",
  "codebuild:project",
+ "codecatalyst:connections",
  "codecommit:*",
  "codecommit:repository",
  "codeguru-reviewer:association",
***************
*** 68,78 ****
--- 79,96 ----
  "config:config-aggregator",
  "config:config-rule",
  "connect:contact-flow",
+ "connect:instance/agent",
+ "connect:instance/contact-flow",
+ "connect:instance/integration-association",
+ "connect:instance/queue",
+ "connect:instance/routing-profile",
+ "connect:instance/transfer-destination",
  "connect:integration-association",
  "connect:queue",
  "connect:quick-connect",
  "connect:routing-profile",
  "connect:user",
+ "diode-messaging:mapping",
  "directconnect:*",
  "directconnect:dxcon",
  "directconnect:dxlag",
***************
*** 133,141 ****
  "elasticloadbalancing:*",
  "elasticloadbalancing:loadbalancer",
  "elasticloadbalancing:targetgroup",
- "elasticmapreduce:*",
  "elasticmapreduce:cluster",
  "elasticmapreduce:editor",
  "es:domain",
  "events:*",
  "events:event-bus",
--- 151,159 ----
  "elasticloadbalancing:*",
  "elasticloadbalancing:loadbalancer",
  "elasticloadbalancing:targetgroup",
  "elasticmapreduce:cluster",
  "elasticmapreduce:editor",
+ "emr-serverless:applications",
  "es:domain",
  "events:*",
  "events:event-bus",
***************
*** 171,176 ****
--- 189,195 ----
  "iam:saml-provider",
  "iam:server-certificate",
  "inspector2:filter",
+ "internetmonitor:monitor",
  "iotanalytics:*",
  "iotanalytics:channel",
  "iotanalytics:dataset",
***************
*** 180,185 ****
--- 199,208 ----
  "iotevents:detectorModel",
  "iotevents:input",
  "iotfleethub:application",
+ "iotroborunner:site",
+ "iotroborunner:site/destination",
+ "iotroborunner:site/worker-fleet",
+ "iotroborunner:site/worker-fleet/worker",
  "iotsitewise:asset",
  "iotsitewise:asset-model",
  "kinesisanalytics:*",
***************
*** 197,206 ****
--- 220,241 ----
  "network-firewall:firewall-policy",
  "network-firewall:stateful-rulegroup",
  "network-firewall:stateless-rulegroup",
+ "oam:link",
+ "oam:sink",
+ "omics:annotationStore",
+ "omics:referenceStore",
+ "omics:referenceStore/reference",
+ "omics:run",
+ "omics:runGroup",
+ "omics:sequenceStore",
+ "omics:sequenceStore/readSet",
+ "omics:variantStore",
+ "omics:workflow",
  "organizations:account",
  "organizations:ou",
  "organizations:policy",
  "organizations:root",
+ "pipes:pipe",
  "ram:*",
  "ram:resource-share",
  "rbin:rule",
***************
*** 215,220 ****
--- 250,257 ----
  "rds:secgrp",
  "rds:subgrp",
  "rds:target-group",
+ "redshift-serverless:namespace",
+ "redshift-serverless:workgroup",
  "redshift:*",
  "redshift:cluster",
  "redshift:dbgroup",
***************
*** 245,259 ****
  "sagemaker:model-package",
  "sagemaker:model-package-group",
  "sagemaker:pipeline",
! "sagemaker:processing-job ",
  "sagemaker:project",
  "sagemaker:training-job",
  "secretsmanager:*",
  "secretsmanager:secret",
  "servicecatalog:application",
  "servicecatalog:attributeGroup",
  "servicecatalog:portfolio",
  "servicecatalog:product",
  "sns:topic",
  "sqs:queue",
  "ssm-contacts:contact",
--- 282,302 ----
  "sagemaker:model-package",
  "sagemaker:model-package-group",
  "sagemaker:pipeline",
! "sagemaker:processing-job",
  "sagemaker:project",
  "sagemaker:training-job",
+ "scheduler:schedule-group",
  "secretsmanager:*",
  "secretsmanager:secret",
  "servicecatalog:application",
  "servicecatalog:attributeGroup",
  "servicecatalog:portfolio",
  "servicecatalog:product",
+ "sms-voice:configuration-set",
+ "sms-voice:opt-out-list",
+ "sms-voice:phone-number",
+ "sms-voice:pool",
+ "sms-voice:sender-id",
  "sns:topic",
  "sqs:queue",
  "ssm-contacts:contact",
***************
*** 276,287 ****
  "transfer:user",
  "transfer:workflow",
  "wellarchitected:workload",
  "wisdom:assistant",
  "wisdom:association",
  "wisdom:content",
! "wisdom:knowledge",
  "wisdom:session",
! "worklink:fleet"
  "workspaces:*",
  "workspaces:directory",
  "workspaces:workspace",
--- 319,331 ----
  "transfer:user",
  "transfer:workflow",
  "wellarchitected:workload",
+ "wickr:network",
  "wisdom:assistant",
  "wisdom:association",
  "wisdom:content",
! "wisdom:knowledge-base",
  "wisdom:session",
! "worklink:fleet",
  "workspaces:*",
  "workspaces:directory",
  "workspaces:workspace",
```
