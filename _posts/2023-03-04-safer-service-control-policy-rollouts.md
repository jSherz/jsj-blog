---
layout: post
title: "Safer AWS Service Control Policy (SCP) rollouts"
date: 2023-03-11 16:01:00 +0000
categories:

- AWS
- "Service Control Policy"
- SCP
- "Control Tower"

---

We use [Service Control Policies] (SCPs) in AWS to restrict dangerous actions
at the account or organization unit level. In an ideal world, you'd design an
SCP upfront when a new use case arrives, and then adapt it as that use case
evolves over time. Here in the real world, we often have to roll out changes to
policies, including SCPs, to live workloads.

[Service Control Policies]: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html

Let's explore how we can test changes to our SCPs.

**NB:** all of the code samples contained in this article are from the
accompanying [project on GitHub].

[project on GitHub]: https://github.com/jSherz/safer-scp-rollouts

## Background: CloudTrail and Policy Simulator

We're going to use a combination of two services to better understand if the
actions our users and services are currently performing will be blocked when we
roll out our SCP changes. It's assumed that you've already got [CloudTrail]
configured to record all AWS API events in all regions in the account(s) that
you want to apply the new policies to. CloudTrail records AWS API actions like
someone creating a new S3 bucket or adding permissions to an IAM role. It
doesn't record _data_ events by default. Examples of data events include
reading or writing objects in S3 buckets or storing data in DynamoDB. These can
be incredibly high volume, and there's a significant cost to capturing them in
an active AWS account.

[Policy Simulator] has an interface that I really struggle to use, but is an
incredibly valuable service that lets you test API operations against an IAM
principal like a role or user without actually performing the API operation.
You can use it to understand if an action is permitted for a given user or
service, and even test out policy changes without touching the live resources.
It's got an API, and that's what we're going to use to test out changes to our
SCPs!

[Policy Simulator]: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html

### How much does recording data events cost?

Let's take a simple example: you have an API running at 10 RPS. It's powered by
a Lambda function that's invoked once per API request and DynamoDB that's
called twice per request.

31 days in a month x 86400 seconds in a day x 10 RPS = ~27 million requests per
month.

(2 DynamoDB data events + 1 Lambda data event) * 27 million = ~81 million

CloudTrail's charge for 81 million data events is $81 a month. We're not
accounting for the S3 or CloudWatch Logs cost on top of that.

Your context will decide if it's worth the cost to store data events, and the
retention that's required. If you don't store data events, you'll have to
manually test your SCP changes against those actions.

[CloudTrail]: https://aws.amazon.com/cloudtrail

## A third tool in our belt - CloudWatch Logs (Insights)

CloudTrail includes the ability to search through the last ninety days of
events, but I've never had much joy finding the event(s) I'm really interested
in. You may find that your CloudTrail events are already being shipped to a
CloudWatch Log Group, for example if your organization-wide CloudTrail was
created by [Control Tower].

In this post, we're going to use CloudWatch as our source of CloudTrail data.
It's not feasible to run every single API event through Policy Simulator, so
we're going to aggregate them on a schedule and then produce a report of any
API actions that we think are going to be allowed or denied. We can compare the
result after changes to the existing CloudTrail event which details if the
event was previously allowed or denied.

[Control Tower]: https://aws.amazon.com/controltower

## Aggregating CloudTrail events with CloudWatch Logs Insights

Let's start with the default query that CloudWatch Logs Insights presents us
with when we launch the interface:

```
fields @timestamp, @message, @logStream, @log
| sort @timestamp desc
| limit 20
```

The first line selects fields that will be shown in the table of results when
our query is run. We can expand items individually to view the rest of the
data. The second line orders the results to show the newest logs first. The
last is a very conservative limit on how many results will be returned. When
we use the CloudTrail logs to simulate policy actions, we're most interested in
the IAM principal performing the action, and what they're trying to do. Let's
adapt the `fields` line to highlight that information:

```
fields eventSource, eventName, userIdentity.type, userIdentity.arn, userIdentity.sessionIssuer.arn
| sort @timestamp desc
| limit 20
```

We use the user identity ARN and the session issuer ARN as the latter is more
useful for role-based access, and the former covers off other principals like
users.

Example results look like this:

| eventSource          | eventName    | userIdentity.type                               | userIdentity.arn                                                                                             | userIdentity.sessionIssuer.arn                                                                                               |
|----------------------|--------------|-------------------------------------------------|--------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| signin.amazonaws.com | ConsoleLogin | AssumedRole                                     | arn:aws:sts::123456789012:assumed-role/AWSReservedSSO_administrator-access_8da98b2be4e76617/james@jsherz.com | arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-1/AWSReservedSSO_administrator-access_8da98b2be4e76617 |
| s3.amazonaws.com     | GetBucketAcl | AWSService                                      |                                                                                                              |                                                                                                                              |
| s3.amazonaws.com     | PutObject    | arn:aws:iam::123456789012:user/example-iam-user |                                                                                                              |

**NB:** After running your search, click "Export results" to have the option to
export a markdown table, CSV or spreadsheet.

The majority of CloudTrail logs you'll view are the same sorts of principals
performing the same sorts of actions. We want to aggregate these results to
reduce the number of policy simulations that we have to run. Let's add in a
`stats` directive:

```
fields eventSource, eventName, userIdentity.type, userIdentity.arn, userIdentity.sessionIssuer.arn
| stats count(*) by eventSource, eventName, userIdentity.type, userIdentity.arn, userIdentity.sessionIssuer.arn
| sort @timestamp desc
| limit 20
```

A new column now appears showing the number of similar rows we've managed to
group together:

| eventSource            | eventName                  | userIdentity.type | userIdentity.arn | userIdentity.sessionIssuer.arn | count(*) |
|------------------------|----------------------------|-------------------|------------------|--------------------------------|----------|
| dynamodb.amazonaws.com | DescribeContinuousBackups  | AssumedRole       | ...              | ...                            | 1        |
| sso.amazonaws.com      | ListProfilesForApplication | Unknown           |                  |                                | 2        |
| s3.amazonaws.com       | GetBucketAcl               | AWSService        |                  |                                | 23       |
| logs.amazonaws.com     | StartQuery                 | AssumedRole       | ...              | ...                            | 3        |
| health.amazonaws.com   | DescribeEventAggregates    | AssumedRole       | ...              | ...                            | 12       |

We've still got a lot of duplicate entries, as the `userIdentity.arn` includes
the role session name - a dynamic value. Let's use `coalesce` and an alias to
prefer the session issuer ARN if it's available, and to fall back to the user
identity ARN if not.

```
fields eventSource, eventName, userIdentity.type, coalesce(userIdentity.sessionContext.sessionIssuer.arn, userIdentity.arn) as principalArn
| stats count(*) by eventSource, eventName, userIdentity.type, principalArn
| sort @timestamp desc
| limit 20
```

Much better! We've now got the role ARN for roles, and the principal's ARN for
everything else.

At this point, we're no longer even viewing the `@timestamp`, so let's remove
the `sort`:

```
fields eventSource, eventName, userIdentity.type, coalesce(userIdentity.sessionContext.sessionIssuer.arn, userIdentity.arn) as principalArn
| stats count(*) by eventSource, eventName, userIdentity.type, principalArn
| limit 20
```

We also want a comprehensive view of the data - we need to test all the API
actions that are happening in the account against our SCP changes. To that end,
let's also remove the limit:

```
fields eventSource, eventName, userIdentity.type, coalesce(userIdentity.sessionContext.sessionIssuer.arn, userIdentity.arn) as principalArn
| stats count(*) by eventSource, eventName, userIdentity.type, principalArn
```

In my sandbox AWS organization that only runs a couple of live workloads, this
returns about 1000 principal and action combinations that we'd have to test.
It may not be relevant to you to simulate the policies with the principal
involved, and so you could reduce that number down further if required:

```
fields eventSource, eventName
| stats count(*) by eventSource, eventName
```

## Simulating API actions against a (new|updated) SCP

Now that we've found an estimate of the number of simulations we will need to
run, we can't start examining how we'd use Policy Simulator to test our new
SCP. Let's start with an example SCP from [the AWS documentation]:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": [
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DeleteDashboards",
        "cloudwatch:DisableAlarmActions",
        "cloudwatch:PutDashboard",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:SetAlarmState"
      ],
      "Resource": "*"
    }
  ]
}
```

[the AWS documentation]: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples_cloudwatch.html

Can we add this SCP to the organization-under-test? Let's use the
`SimulateCustomPolicy` API method and find out! We'll start by installing the
relevant AWS SDK, in our case into a TypeScript project.

```bash
yarn add @aws-sdk/client-iam
```

We'll take a few example IAM actions from our CloudTrail data and see if they
are denied by this policy:

```typescript
const client = new IAMClient({});

const result = await client.send(
    new SimulateCustomPolicyCommand({
        PolicyInputList: [policy],
        ActionNames: [
            "acm:ListCertificates",
            "backup:ListBackupPlans",
            // ...
            "sts:AssumeRoleWithSAML",
            "workspaces:DescribeWorkspaces",
        ],
    }),
);

console.log("Results were truncated?", result.IsTruncated ? "yes" : "no");

for (const evaluationResult of result.EvaluationResults || []) {
    console.log(
        evaluationResult.EvalActionName,
        evaluationResult.EvalDecision,
        evaluationResult.EvalDecisionDetails,
    );
}
```

We get an output similar to the following:

```
Results were truncated? no
acm:ListCertificates implicitDeny undefined
backup:ListBackupPlans implicitDeny undefined
...
sts:AssumeRoleWithSAML implicitDeny undefined
workspaces:DescribeWorkspaces implicitDeny undefined
```

As you can see above - our policy does not explicitly `Deny` our test actions,
and thus the SCP would be safe to apply. Let's try again with a few actions
from CloudWatch:

```typescript
const result2 = await client.send(
    new SimulateCustomPolicyCommand({
        PolicyInputList: [policy],
        ActionNames: [
            "cloudwatch:GetMetricData",
            "cloudwatch:DeleteDashboards",
            "cloudwatch:DescribeAlarmHistory",
        ],
    }),
);
```

Here are the results:

```
Results were truncated? no
cloudwatch:GetMetricData implicitDeny undefined
cloudwatch:DeleteDashboards explicitDeny undefined
cloudwatch:DescribeAlarmHistory implicitDeny undefined
```

We can observe that we're not allowed to delete dashboards as that would be
explicitly blocked by our SCP. The other actions would be fine as long as our
principal has the permissions to perform them.

**NB:** you can find the above code for searching CloudTrail logs in CloudWatch
in the [project on GitHub].

## Challenges simulating policies

We've covered a very simple case of a policy that has no conditions and does
not mention specific IAM principals. Before we cover more involved SCPs, let's
talk about a few challenges we have using CloudTrail data in this way.

### Matching CloudTrail events to IAM actions

Let's query for every unique event source (service name) in my test org:

```
fields eventSource
| stats count(*) by eventSource
```

That produces results that look like the following:

```
access-analyzer.amazonaws.com,96
acm.amazonaws.com,40
amazonmq.amazonaws.com,28
apigateway.amazonaws.com,145
```

We can remove the ".amazonaws.com" bit and the count, leaving us with what
looks like an IAM prefix.

If we take the resulting list of ninety-seven services, how many do you think
would be the correct IAM action prefix? By my maths, eighty-three of them are
the same, and the rest are slightly different or rely on more than one prefix:

| Service name from CloudTrail             | IAM prefix(es)          |
|------------------------------------------|-------------------------|
| amazonmq.amazonaws.com                   | mq                      |
| apigateway.amazonaws.com                 | apigateway, execute-api |
| application-insights.amazonaws.com       | applicationinsights     |
| billingconsole.amazonaws.com             | billing                 |
| cloudcontrolapi.amazonaws.com            | cloudformation          |
| codeguru-reviewer.amazonaws.com          | codeguru                |
| datasync.amazonaws.com                   | resourcedatasync        |
| monitoring.amazonaws.com                 | cloudwatch              |
| servicecatalog-appregistry.amazonaws.com | servicecatalog          |
| tagging.amazonaws.com                    | tag                     |
| taxconsole.amazonaws.com                 | tax                     |

The rest are items like "signin" which doesn't exist as an IAM prefix, and some
quirks like "resource-explorer-2" where you actually need permissions for
"resource-explorer" as well if you want to use it in the console.

I can't find an official mapping or list of the above data that exists at the
time of writing (March 2023). If you know of one, I'd be really grateful if you
pop me an e-mail! AWS' Cloud Development Kit (CDK) has a file that will get you
close in [the aws-cdk-lib package] - see
custom-resources/lib/aws-custom-resource/sdk-api-metadata.json in the
aws-cdk-lib folder of your node_modules after installing it. That file is not
perfect. For example, many CloudWatch API actions are given the "monitoring"
IAM prefix, even though there are thirty-nine IAM actions with the "cloudwatch"
prefix. A further option I stumbled upon thanks to [a StackOverflow post] is to
download the data that powers the AWS Policy Generator. This produces a pure
JavaScript file intended to be used with an existing application, so let's
write a small script to download it and make it applicable for us:

[the aws-cdk-lib package]: https://github.com/aws/aws-cdk/tree/v2.67.0/packages/aws-cdk-lib

```typescript
import axios from "axios";
import {promises as fs} from "fs";
import * as path from "path";

const outputPath = path.join(process.cwd(), "src", "service-iam-data.js");

const response = await axios.get(
    "https://awspolicygen.s3.amazonaws.com/js/policies.js",
);

await fs.writeFile(
    outputPath,
    `const app = {};
${response.data}
module.exports = app;
`,
);
```

[a StackOverflow post]: https://stackoverflow.com/a/65058224

We'll avoid using the `checkJs` option in TypeScript, and we'll instead provide
some typings that make it easier to work with the above file:

```typescript
declare module "*/service-iam-data.js" {
    export interface IService {
        StringPrefix: string;
        Actions: string[];
        ARNFormat?: string;
        ARNRegex?: string;
        conditionKeys?: string[];
        HasResource: boolean;
    }

    export interface IPolicyType {
        Name: string;
        AssociatedService: string[];
    }

    export const PolicyEditorConfig: {
        conditionOperators: string[];
        conditionKeys: string[];
        serviceMap: Record<string, IService>;
        policyTypes: Record<string, IPolicyType>;
        VPCPolicyServiceActionMap: Record<string, string[]>;
    };
}
```

### Remapping services

We can overcome the first challenge with a simple map of the incoming service
name and what we'd like it to become:

```typescript
const serviceNameOverrides: Record<string, string> = {
    amazonmq: "mq",
    "application-insights": "applicationinsights",
    tagging: "tag",
};
```

### Remapping the "eventName" to a different service

Next, we'll remap some of the `eventName` values coming in from CloudTrail to a
different IAM prefix:

```typescript
export type EventSource = string;
export type EventName = string;

const eventSourceOverrides: Record<
    EventSource,
    Record<EventName, EventSource>
> = {
    // ...
    billingconsole: {
        // ...
        GetAllPurchaseOrders: "aws-portal",
        GetBillingAddress: "aws-portal",
        // ...
    },
    // ...
    taxconsole: {
        GetTaxExemptionTypes: "tax",
    },
};
```

### Excluding events we're not interested in

Some CloudTrail events note that something happened, not that a user or service
has attempted to perform an action with an API call. We want to exclude these
from our analysis:

```typescript
export type EventSource = string;
export type EventName = string;

const excludedActions: Record<EventSource, Record<EventName, boolean>> = {
  // ...
  "cognito-idp": {
    Error_GET: true,
    Login_GET: true,
    SAML2Response_POST: true,
    Token_POST: true,
  },
  // ...
  signin: {
    ConsoleLogin: true,
    // ...
  },
  // ...
};
```

### Remapping the "eventName" to the appropriate IAM actions

Many of the CloudTrail `eventName` values aren't the same as the IAM action
required to generate that event. In some cases, one event requires two IAM
prefixes. We'll create a map to get the right IAM actions(s) for each event:

```typescript
export type EventSource = string;
export type EventName = string;

const actionOverrides: Record<EventSource, Record<EventName, EventName[]>> = {
  "aws-portal": {
    // ...
    GetAccountEDPStatus: ["ViewPortal"],
    // ...
  },
  kms: {
    ReEncrypt: ["ReEncryptFrom", "ReEncryptTo"],
  },
  lambda: {
    "/^AddPermission.*/": ["AddPermission"],
    "/^GetFunction.*/": ["GetFunction"],
    // ...
  },
  // ...
  sso: {
    "ListProfiles, GetProfile": ["GetProfile", "ListProfiles"],
  },
};
```

### Bringing it all together

With all of the above nastiness out of the way, we can now query CloudWatch for
our CloudTrail data, and simulate it against a candidate SCP. The full code for
these commands is located in the [project on GitHub]:

```bash
# See the README for the full setup
yarn build

# Your choice of auth method
export AWS_PROFILE=master
aws sso login

# Query with CloudWatch Logs Insights
node dist/fetch-actions

# Perform the analysis - see src/evaluate-cloudtrail-data.ts for the policy!
node dist/evaluate-cloudtrail-data
```

We'll get results that look like the following:

```
evaluating tagging:GetResources implicit deny
evaluating tagging:GetTagKeys implicit deny
evaluating taxconsole:GetTaxExemptionTypes implicit deny
evaluating transfer:ListWorkflows implicit deny
```

You can customise the code to suit a style of reporting that works for you and
your team. Perhaps you'll setup an automation that scans the CloudTrail data
daily and runs the simulations twice: once with the old policy and once with
the new policy.

### SCPs that involve a principal

If we have an SCP that involves a principal, we have to run the simulation for
each unique principal value to determine if it's allowed or denied. This vastly
increases the number of simulations that we have to run, and also the
complexity of finding the right data. One option is to run different kinds of
simulations for different kinds of policies:

* SCP containing only conditions on services that are allowed: query and
  analyse based on `eventSource`.
* SCP with IAM actions: query on `eventSource` and `eventName` - use both.
* SCP with principals: query only for relevant `eventSource` and `eventName`
  values. Produce a list of principals that are relevant. Simulate with those.

### SCPs with conditions

Before we conclude, let's look at a few more advanced SCPs and work on methods
to test them.

#### Region-based controls

Let's say you're blocking access to any region-specific services that aren't in
an allowed region. We can simulate that by passing some context into our call
to the policy simulator:

```typescript
import {
    ContextKeyTypeEnum,
    IAMClient,
    SimulateCustomPolicyCommand,
} from "@aws-sdk/client-iam";

const iamClient = new IAMClient({});

const euCentral1Result = await iamClient.send(
    new SimulateCustomPolicyCommand({
        PolicyInputList: [policyUnderTest],
        ActionNames: ["ec2:RunInstances"],
        ContextEntries: [
            {
                ContextKeyName: "aws:RequestedRegion",
                ContextKeyType: ContextKeyTypeEnum.STRING,
                ContextKeyValues: ["eu-central-1"],
            },
        ],
    }),
);
```

It's not the simplest to add, but we can also experiment with bypassing the
restrictions based on our principal:

```typescript
const euWest2ExemptResult = await iamClient.send(
    new SimulateCustomPolicyCommand({
        PolicyInputList: [policyUnderTest],
        ActionNames: ["ec2:RunInstances"],
        ContextEntries: [
            {
                ContextKeyName: "aws:RequestedRegion",
                ContextKeyType: ContextKeyTypeEnum.STRING,
                ContextKeyValues: ["eu-west-2"],
            },
            {
                ContextKeyName: "aws:PrincipalARN",
                ContextKeyType: ContextKeyTypeEnum.STRING,
                ContextKeyValues: [
                    "arn:aws:iam::123456789123:role/Role2AllowedToBypassThisSCP",
                ],
            },
        ],
    }),
);
```

We can't use the `CallerArn` parameter to `SimulateCustomPolicy` as it only
works for IAM users. With these conditions and more advanced policies, we're
getting into the territories of brittle testing that has to be tailored to
the exact policy wording.

Try this out in the [project on GitHub]:

```bash
node dist/scp-with-region-condition
```

```
eu-central-1:

ec2:RunInstances = implicitDeny

eu-west-2

ec2:RunInstances = explicitDeny

eu-west-2 exempt role

ec2:RunInstances = implicitDeny
```

#### Enforcing the use of multi-factor authentication

Let's have a go with one more example SCP that uses a different condition:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyStopAndTerminateWhenMFAIsNotPresent",
      "Effect": "Deny",
      "Action": [
        "ec2:StopInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": false
        }
      }
    }
  ]
}
```

We can adapt out previous example to test out three scenarios, one of which is
shown below:

```typescript
import {
    ContextKeyTypeEnum,
    IAMClient,
    SimulateCustomPolicyCommand,
} from "@aws-sdk/client-iam";

const iamClient = new IAMClient({});

const withMfaResult = await iamClient.send(
    new SimulateCustomPolicyCommand({
        PolicyInputList: [policyUnderTest],
        ActionNames: ["ec2:StopInstances"],
        ContextEntries: [
            {
                ContextKeyName: "aws:MultiFactorAuthPresent",
                ContextKeyType: ContextKeyTypeEnum.BOOLEAN,
                ContextKeyValues: ["true"],
            },
        ],
    }),
);
```

Let's try in the [project on GitHub]:

```bash
node dist/scp-with-mfa-condition
```

```
no context value:

ec2:StopInstances = explicitDeny

no MFA:

ec2:StopInstances = explicitDeny

with MFA:

ec2:StopInstances = implicitDeny
```

## Conclusion

We've seen that with some awkward wrangling, we can use CloudTrail data to test
SCPs before we roll them out. You'll have to make your own determination as to
whether the complexity and manual nature of this work is worth it for the SCPs
that you're trying to apply. Either way, I hope the CloudWatch Logs Insights
queries can be a useful example for your investigations into the access
happening in your AWS organization.

## See also

* [AWS Policy Generator](https://awspolicygen.s3.amazonaws.com/policygen.html)
* [AWS Policy Simulator](https://policysim.aws.amazon.com/)
* [List of all IAM actions, resources and conditions](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html)
* [Example service control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)
