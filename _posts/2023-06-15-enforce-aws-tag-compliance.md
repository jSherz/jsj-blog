---
layout: post
title: "Enforcing AWS tags the right way - without Tag Policies"
date: 2023-06-15 19:12:00 +0100
categories:
  - AWS
  - security
  - Terraform
  - CloudFormation
---

Tags are essential in AWS. They let us allocate costs to different teams,
projects, services or business areas, and can be critical in operational
response. For example, if a piece of dangerously insecure infrastructure is
created, and you want to identify the right team to fix it without impacting
availability. In [Shift security left with AWS Config], I discussed providing
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

If you read [the documentation of supported resources], you'll immediately see
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
290 in the documentation. The full diff can be found at the end of the article.

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
evaluates your resources to decide if they meet certain compliance criteria,
for example checking an S3 bucket isn't open to the public. In
[Shift security left with AWS Config], I use a feature of Config to write an
SQL query that fetches tags for any supported resource. Super handy!

[AWS Config]: https://aws.amazon.com/config/

Let's write a custom Config rule that checks a resource has the tags we
require. We're going to use the CloudFormation Guard Domain-Specific-Language
(DSL), but you can also make custom Config rules with Lambda functions.

We'll start by requiring a tag that we want to enforce for all resource types:

```
tags["shersoft-ltd:workload:project"] !empty
```

If you want to follow along in the console while you're developing your rule,
see these steps:

<video muted controls>
    <source src="/assets/enforce-aws-tag-compliance/add-config-rule-demo.webm" type="video/webm">
</video>

With the rule in place, we can immediately see which resource are and aren't
compliant. We can expand our Config rule to cover some other tags:

```
tags["shersoft-ltd:workload:project"] !empty

tags["shersoft-ltd:workload:ref"] !empty

tags["shersoft-ltd:devops:environment"] !empty
```

We could additionally ensure that the tag value matches one of a set of allowed
values. Let's do that with the environment tag:

```
tags["shersoft-ltd:devops:environment"] == /staging|production/
```

At this point, you might be wondering how you can debug rules written in the
Guard language, especially without incurring the cost of repeated Config
evaluations. Luckily there's a CLI that we can use for this purpose. Install
it following [the instructions on GitHub]. I'm on a Mac, so will just do:

[the instructions on GitHub]: https://github.com/aws-cloudformation/cloudformation-guard#installation

```bash
brew install cloudformation-guard
```

We'll take the configuration item JSON, in this case a CodeArtifact repo, and
place it into `resource.json`:

```json
{
  "version": "1.3",
  "accountId": "123456789012",
  "configurationItemCaptureTime": "2023-05-24T19:50:28.418Z",
  "configurationItemStatus": "ResourceDiscovered",
  "configurationStateId": "1684957828418",
  "configurationItemMD5Hash": "",
  "arn": "arn:aws:codeartifact:eu-west-1:123456789012:repository/test/repo",
  "resourceType": "AWS::CodeArtifact::Repository",
  "resourceId": "arn:aws:codeartifact:eu-west-1:123456789012:repository/test/repo",
  "resourceName": "repo",
  "awsRegion": "eu-west-1",
  "availabilityZone": "Regional",
  "tags": {},
  "relatedEvents": [],
  "relationships": [],
  "configuration": {
    "RepositoryName": "my-little-repo",
    "Name": "repo",
    "DomainName": "test",
    "DomainOwner": "123456789012",
    "Arn": "arn:aws:codeartifact:eu-west-1:123456789012:repository/test/repo",
    "ExternalConnections": [],
    "Upstreams": [
      "npm-store"
    ],
    "Tags": []
  },
  "supplementaryConfiguration": {},
  "resourceTransitionStatus": "None"
}
```

You'll see that it's got no tags. With that in place, we'll put the tag rule
we're developing into `tag-rule.guard`, and run the CLI:

```bash
cfn-guard validate --rules tag-rule.guard --data resource.json
```

We'll be given detailed debugging information about the rule evaluation -
scroll to the right in the code pane to view the full message:

```
resource.json Status = FAIL
FAILED rules
tag-rule.guard/default    FAIL
---
Evaluation of rules tag-rule.guard against data resource.json
--
Property traversed until [/tags] in data [resource.json] is not compliant with [tag-rule.guard/default] due to retrieval error. Error Message [Could not find key shersoft-ltd:workload:project inside struct at path /tags[L:13,C:10]]
Property traversed until [/tags] in data [resource.json] is not compliant with [tag-rule.guard/default] due to retrieval error. Error Message [Could not find key shersoft-ltd:workload:ref inside struct at path /tags[L:13,C:10]]
Property traversed until [/tags] in data [resource.json] is not compliant with [tag-rule.guard/default] due to retrieval error. Error Message [Could not find key shersoft-ltd:devops:environment inside struct at path /tags[L:13,C:10]]
--
```

How about with all tags present, and an invalid tag value in environment? Try
updating the tags property in resource.json:

```json5
{
  // ...
  "tags": {
    "shersoft-ltd:workload:project": "test",
    "shersoft-ltd:workload:ref": "test",
    "shersoft-ltd:devops:environment": "lemons"
  },
  // ...
}
```

Then re-run the validate command:

```bash
cfn-guard validate --rules tag-rule.guard --data resource.json
```

We get a new error!

```
... provided value ["lemons"] did not match expected value ["/staging|production/"]...
```

This allows us to rapidly iterate on our tag Config rule for free. We could
even store the configuration items as a set of JSON test fixtures, call the CLI
and then verify the resulting output in integration tests.

Tag Policies let us select resource types that we want to enforce the tags for,
and we can achieve the same thing in our Config rule:

```
rule check_retention_tag when resourceType == "AWS::S3::Bucket" {
  tags["shersoft-ltd:compliance:retention"] !empty
}
```

`cfn-guard` will now indicate that it didn't check for that tag:

```
Rule [tag-rule.guard/check_retention_tag] is not applicable for template [resource.json]
```

## Conclusion

Tag Policies have a number of practical limitations, including their lack of
resource support, and requiring SCPs that are incompatible with some IaC tools.
We can use a custom Config rule to mandate a set of tags based on the
resource type, and achieve tagging harmony across our AWS organisation.

## See also

* [Tagging Best Practices - AWS Whitepapers](https://docs.aws.amazon.com/whitepapers/latest/tagging-best-practices/tagging-best-practices.html)
* [Writing AWS CloudFormation Guard rules - AWS Documentation](https://docs.aws.amazon.com/cfn-guard/latest/ug/writing-rules.html)
* [Creating AWS Config Custom Policy Rules - AWS Documentation](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules_cfn-guard.html)

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
