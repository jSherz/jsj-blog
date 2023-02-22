---
layout: post
title: "Pre-signed URLs in AWS S3 - gotchas that got me"
date: 2023-02-22 21:21:00 +0000
categories:
- AWS
- S3
- "Simple Storage Service"
---

[Pre-signed URLs] are a convenient way of us having our users directly download
or upload a file from or to S3. They're especially helpful when we want to
avoid the overhead of processing the file that's being (up|down)loaded on
our services. Your choice of compute option generates a link and returns it to
the client's device. Additional code on the client then performs the operation
communicating directly with S3. Simple, right? Wrong! Here are some of the
gotchas or footguns I've run into using pre-signed URLs. Let my pain be your
gain.

[Pre-signed URLs]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html

## SDK OK?

The following examples will be using version three of the AWS SDK for
JavaScript and TypeScript. The examples should be broadly applicable to any
language.

## 'Role' on the first footgun: expiry times

When we generate a pre-signed URL, we will normally set an expiry time to give
the user finite time to (up|down)load a file. It's worth noting that if your
service is using an IAM role for authentication (it should if it's hosted in
AWS), the role's session expiry time will cut short whatever value you set in
the SDK.

Let's assume a role with a session expiry time at the minimum, fifteen minutes:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam... \
  --role-session-name gotchas \
  --duration-seconds 900
```

```json
"todo"
```

Let's then export those credentials into our environment:

```
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export AWS_SESSION_TOKEN=
```

Finally, let's run the following SDK example:

```typescript
import { S3Client } from "@aws-sdk/client-s3";

const client = new S3Client({});

const result = await client.presignedUrl({
    Expires: 3600, // one hour?
});

console.log("Here is your URL:", result.URL)
```

```bash
ts-node example1.ts
```

Wait fifteen minutes after running this example and then try your pre-signed
URL. What do you expect to happen? Should it be valid because our expiry time
is one hour from now? I certainly expected that to be the case, but it
expires in a measly fifteen minutes.

**NB:** you can find the full source code for any of these examples on my 
[GitHub].

[GitHub]: https://github.com/jSherz/presigned-urls-in-s3-gotchas

Have a look at the roles that are used by your services in the AWS console.
What is the maximum role session time? If you create a pre-signed URL with one
of these roles, you'll get _at most_ that amount of time. We can actually
see how much time is remaining on our current session. The following SDK
example is run as part of example two in the above GitHub project. It spits out
the remaining role session time every minute in an ECS Fargate task.

```typescript
setTimeout(() => {
    // Check how long is left in the session
    // Spit it out to the logs
}, 60 * 1000);
```

This example illustrates that you don't get the role's maximum session time for
your signed links, you get the maximum of your role's remaining session time
and the expiry time you pass to the SDK.

### Workarounds

If your desired expiry time fits within the maximum role session time, you
can ask the SDK to request a role session that lasts longer than the default of
one hour. We must also explicitly ask the SDK to refresh its credentials if
we have _less_ time remaining in our session than we want to grant to the user
of the pre-signed URL. The method will vary slightly depending on the source of
your credentials.

The absolute maximum time we can have is twelve hours. See the
[documentation for STS AssumeRole].

[documentation for STS AssumeRole]: https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html

```typescript
// First we ask for more time
creds.fromFargate(2000000);

// When we come to generate the presigned URL, we check there is sufficient 
// time left
if (remainingSessionTime.isSmol()) {
    client.refresh();
}
```

If your desired expiry time is above twelve hours, the remaining option is an
IAM user. You might choose to lock this user down to only one IAM action (e.g.
`s3:GetObject`) and then have the access keys generated and saved into Secrets
Manager in a fully automated fashion that avoids and humans handling them.
Secrets Manager's rotation feature and a custom Lambda function achieves this
and gives you frequent, automated, rotation. Auditing of the S3 bucket itself,
for example by enabling CloudTrail data events, doesn't hurt either!

See example three in the [GitHub] repo for a full working implementation of
this.
