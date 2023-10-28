---
layout: post
title: "Tracking unauthorised AWS API calls to drive platform improvements"
date: 2023-10-28 17:56:00 +0100
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
Identity and Access Management (IAM). In this post, we're going to explore how
we can use data you're (hopefully) already collecting to understand what's
happening in our AWS organization, and to attempt to preempt user needs and
requests.

Wanting to skip straight to the code? Check out [the solution on GitHub].

[the solution on GitHub]: https://github.com/jSherz/tracking-unauthorised-aws-api-calls

## CloudTrail

If you've missed it, CloudTrail is an AWS Service that records an audit log of
API calls. It's really easy to setup, can aggregate API calls from all accounts
in an AWS organization, and is cost-effective to boot.

This article assumes that you've configured CloudTrail in the organization
management account to aggregate all API calls into a single S3 bucket.

Here's an example CloudTrail log:

```json
{
  "eventVersion": "1.09",
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "AROAT2EYEKAEIO6FE237W:james@jsherz.com",
    "arn": "arn:aws:sts::123123123123:assumed-role/AWSReservedSSO_administrator-access_0c88b0f85221b941/james@jsherz.com",
    "accountId": "123123123123",
    "accessKeyId": "ASIAT2EYEKAEBTRIY4VI",
    "sessionContext": {
      "sessionIssuer": {
        "type": "Role",
        "principalId": "AROAT2EYEKAEIO6FE237W",
        "arn": "arn:aws:iam::123123123123:role/aws-reserved/sso.amazonaws.com/eu-west-1/AWSReservedSSO_administrator-access_0c88b0f85221b941",
        "accountId": "123123123123",
        "userName": "AWSReservedSSO_administrator-access_0c88b0f85221b941"
      },
      "attributes": {
        "creationDate": "2023-10-24T20:20:48Z",
        "mfaAuthenticated": "false"
      }
    }
  },
  "eventTime": "2023-10-24T20:20:50Z",
  "eventSource": "support.amazonaws.com",
  "eventName": "DescribeTrustedAdvisorChecks",
  "awsRegion": "us-east-1",
  "sourceIPAddress": "123.123.123.123",
  "userAgent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36",
  "errorCode": "AccessDenied",
  "errorMessage": "User: arn:aws:sts::123123123123:assumed-role/AWSReservedSSO_administrator-access_0c88b0f85221b941/james@jsherz.com is not authorized to perform: support:DescribeTrustedAdvisorChecks with an explicit deny in a service control policy",
  "requestParameters": null,
  "responseElements": null,
  "requestID": "54d4f88c-3097-449a-8fb7-aa59b37646d2",
  "eventID": "675a51b3-9706-45ec-88ce-1de54a23649f",
  "readOnly": true,
  "eventType": "AwsApiCall",
  "managementEvent": true,
  "recipientAccountId": "123123123123",
  "eventCategory": "Management",
  "tlsDetails": {
    "tlsVersion": "TLSv1.2",
    "cipherSuite": "ECDHE-RSA-AES128-GCM-SHA256",
    "clientProvidedHostHeader": "support.us-east-1.amazonaws.com"
  },
  "sessionCredentialFromConsole": "true"
}
```

If we zoom in to the `errorMessage`, we can see that this API call was blocked
as the result of a Service Control Policy (SCP):

> User: ...james is not authorized to perform:
> support:DescribeTrustedAdvisorChecks with an explicit deny in a service
> control policy

## What can we learn from unauthorised API calls?

We're not trying to detect security breaches or users doing things they're not
supposed to in this solution. Instead, we're looking for the following:

* **API activity in regions we don't expect;**

  This could be user error, or could indicate a region should be enabled /
  allowed for a particular workload.

* **Users trying to use new services;**

  It's very likely that users will be faster than a platform team to try new
  services - probably before everything's in place to allow them access.

  If it makes sense for the new service to be enabled in an SCP, we can add
  this to our todo list and get it enabled before the user demand really kicks
  in. One example of this is the [User Notifications] service that AWS launched
  to let users centralise and customise notifications.

* **AWS API calls that have changed IAM actions;**

  AWS occasionally switches to new IAM actions for the same operations, or to
  achieve the same objective. An example of this would be the AWS portal
  changes that introduced the migration from `aws-portal` to `billing`,
  `accounts`, `purchase-orders`, and `tax`. Users might hit these permissions
  as they're navigating around the AWS console, but still be able to achieve
  their goals. If this happens, they might not immediately report a problem,
  but we could still do with fixing the broken access.

* **New API calls or IAM actions that have been added to services;**

  Services are often expanding to include new IAM prefixes, for example the
  addition of `pipes:*`, `scheduler:*` or `schemas:*` to EventBridge. As above,
  a user clicking around in the console might hit these, and we can add them to
  relevant SCPs nice and quickly.

[User Notifications]: https://aws.amazon.com/notifications/

## Solution architecture

When we talk about searching through CloudTrail data at scale, your mind might
immediately jump to [CloudTrail Lake]. CloudTrail Lake lets you run SQL-like
queries against CloudTrail data, and can store it for an impressive seven
years! If you're not doing a lot of searching of your CloudTrail data, the
$2.50 / GB storage pricing (scales down above 5 TB) might feel a little
prohibitive. We're going to use [Athena] to search through the CloudTrail data
you'll already have stored in S3. We'll only be charged per query, so we can
try this solution and decide if it provides value before committing to the
likes of CloudTrail Lake. The mapping of S3 data to fields in Athena will be
stored in [Glue], and the whole thing will be orchestrated with EventBridge and
Lambda.

[CloudTrail Lake]: https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-lake.html
[Athena]: https://aws.amazon.com/athena/
[Glue]: https://aws.amazon.com/glue/

![EventBridge triggers a Lambda function on a schedule, it queries Athena. Athena uses Glue for the schema, and reads CloudTrail data from an S3 bucket.](/assets/tracking-unauthorised-aws-api-calls/architecture-diagram.png)

Our Lambda function will be triggered on a schedule, and will read the AWS
account data from AWS Organizations. We need these account IDs as the S3 data
is stored in the following format:

> s3://\<bucket name>/AWSLogs/\<org ID>/\<account ID>/CloudTrail/\<region>/\<YYYY>/\<MM>/\<DD>/

You can view [the solution on GitHub], but we're setting Athena up to scan only
the data that is required to answer our query. If we provide the account IDs
and regions, it can automatically calculate which "folders" in S3 it has to
look through. It's even smart enough to turn the timestamp as a date into every
required value. For example, this query:

```sql
SELECT * FROM my_table
WHERE timestamp >= '2023/10/01'
```

Would look in all the folders from `2023/10/01`, `2023/10/02`, `2023/10/03`,
all the way up to the current date.

Here's what our full Athena query will look like:

```sql
SELECT eventsource, eventname, COUNT(*) as num_occurrences
FROM cloudtrail
WHERE 1 = 1
-- Only look at the last period
AND timestamp >= '${startDate}'
-- Cause Athena to look through each auto-generated partition
AND account_id IN (
    '111111111111',
    '222222222222',
    -- ...
)
AND region IN ('eu-west-1', 'us-east-1')
-- Exclude Config as it's very noisy
AND sourceipaddress != 'config.amazonaws.com'
-- Only denied requests
AND errorcode IS NOT NULL
AND (
    errorcode LIKE '%AccessDenied%'
 OR errorcode LIKE '%Forbidden%'
 OR errorcode LIKE '%Unauthorized%'
)
GROUP BY eventsource, eventname
ORDER BY num_occurrences DESC;
```

When it's run successfully, we can send an e-mail report to a mailing list or
distribution list of our choice, and review these by hand once a week (or a
cadence that makes sense for your context):

<img alt="A table showing AWS services and IAM actions that were denied" src="/assets/tracking-unauthorised-aws-api-calls/access-report.png" style="max-width: 700px"/>

That's a wrap! If you think this could provide value in your team, check out
[the solution on GitHub].
