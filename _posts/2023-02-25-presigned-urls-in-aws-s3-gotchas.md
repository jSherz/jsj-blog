---
layout: post
title: "Pre-signed URLs in AWS S3 - gotchas that got me"
date: 2023-02-25 16:39:00 +0000
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
  --role-arn arn:aws:iam::123456789012:role/pre-signed-urls-expiry-time-cli-testing \
  --role-session-name gotchas \
  --duration-seconds 900
```

If you're following along with the [examples project on GitHub], the role ARN
is the CloudFormation output "expirytimeclitestingroleoutput".

[examples project on GitHub]: https://github.com/jSherz/pre-signed-urls-in-s3-gotchas

```json
{
  "Credentials": {
    "AccessKeyId": "ASIA________________",
    "SecretAccessKey": "_______________________________________",
    "SessionToken": "...",
    "Expiration": "2023-02-25T14:31:38+00:00"
  },
  "AssumedRoleUser": {
    "AssumedRoleId": "...",
    "Arn": "..."
  }
}
```

Let's then export those credentials into our environment:

```
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

Finally, let's run the following SDK example:

```bash
yarn ts-node src/example1.ts
```

```typescript
import {
    CloudFormationClient,
    DescribeStacksCommand,
} from "@aws-sdk/client-cloudformation";
import {GetObjectCommand, S3Client} from "@aws-sdk/client-s3";
import {getSignedUrl} from "@aws-sdk/s3-request-presigner";

(async () => {
    const s3Client = new S3Client({});

    const cfnClient = new CloudFormationClient({});

    const stacks = await cfnClient.send(
        new DescribeStacksCommand({
            StackName: "presigned-urls",
        }),
    );

    if (!stacks.Stacks || !stacks.Stacks[0] || !stacks.Stacks[0].Outputs) {
        throw new Error("Could not find stack - have you deployed this project?");
    }

    const command = new GetObjectCommand({
        Bucket: stacks.Stacks[0].Outputs.find(
            (output) => output.OutputKey === "bucketoutput",
        )!.OutputValue!,
        Key: "example1.txt",
    });

    const url = await getSignedUrl(s3Client, command, {
        expiresIn: 3600, // one hour
    });

    console.log("Here is your URL:", url);
})().catch(console.error);
```

Wait fifteen minutes after running this example and then try your pre-signed
URL. What do you expect to happen? Should it be valid because our expiry time
is one hour from now? I certainly expected that to be the case, but it
expires in a measly fifteen minutes.

Have a look at the roles that are used by your services in the AWS console.
What is the maximum role session time? If you create a pre-signed URL with one
of these roles, you'll get _at most_ that amount of time. We can actually
see how much time is remaining on our current session. The following SDK
example is run as part of example two in the above GitHub project. It spits out
the remaining role session time every minute. It's best run on an EC2 instance
unless you're using AWS Identity Centre locally.

```bash
yarn ts-node src/example2.ts
```

```typescript
import { S3Client } from "@aws-sdk/client-s3";

const s3Client = new S3Client({});

setInterval(async () => {
    try {
        const currentCredentials = await s3Client.config.credentials();

        const now = new Date();

        if (currentCredentials.expiration) {
            const remainingSeconds =
                (currentCredentials.expiration.getTime() - now.getTime()) / 1000;

            console.log(`Your session has ${remainingSeconds} seconds left.`);
        } else {
            console.log("Could not detect how many seconds left in your session.");
        }
    } catch (err) {
        console.error("Failed to check credential expiry", err);
        process.exit(1);
    }
}, 60 * 1000);
```

This example illustrates that you don't get the role's maximum session time for
your signed links, you get the maximum of your role's remaining session time
and the expiry time you pass to the SDK.

If you leave the above example running, you'll see that AWS' SDKs automatically
refresh the credentials when required.

```
Your session has 3598.468 seconds left.
Your session has 3538.895 seconds left.
...
Your session has 478.635 seconds left.
Your session has 418.631 seconds left.
Your session has 358.629 seconds left.
Your session has 3598.262 seconds left.
```

### Workarounds

The role session duration depends on the service you've assigned the role to.
For example, an EC2 instance profile can have a session that lasts up to six
hours. See "[Using presigned URLs]" for more information.

[Using presigned URLs]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html

If your desired expiry time fits within that limit, we just have to ensure
that we refresh the credentials when we detect there isn't enough time left in
the session. Anything longer than that requires the use of an IAM user. You
might choose to lock this user down to only one IAM action (e.g.
`s3:GetObject`) and then have the access keys generated and saved into
Secrets Manager in a fully automated fashion that avoids and humans handling
them. Secrets Manager's rotation feature and a custom Lambda function
achieves this and gives you frequent, automated, rotation. Auditing of the
S3 bucket itself, for example by enabling CloudTrail data events, doesn't
hurt either!

**Why can't we use a larger session duration?**

At the time of writing, the instance metadata APIs (including for
containerized workloads) don't support being asked for a longer session
duration. See the AWS documentation page linked above for the latest values.

**Why can't we use a call to the STS AssumeRole API with a longer duration?**

When a role assumes another role, it has a maximum session duration of an hour.
See "[Can I increase the IAM role chaining session duration limit?]" for more
information.

[Can I increase the IAM role chaining session duration limit?]: https://aws.amazon.com/premiumsupport/knowledge-center/iam-role-chaining-limit/

Here's an example that demonstrates force-refreshing. It works with a local
session powered by AWS Identity Centre.

```bash
yarn ts-node src/example3.ts
```

```typescript
import { S3Client } from "@aws-sdk/client-s3";

const s3Client = new S3Client({});

setInterval(async () => {
    try {
        const currentCredentials = await s3Client.config.credentials();

        const now = new Date();

        if (currentCredentials.expiration) {
            const remainingSeconds =
                (currentCredentials.expiration.getTime() - now.getTime()) / 1000;

            console.log(`Your session has ${remainingSeconds} seconds left.`);

            /*
              Many credential providers default to credentials valid for one hour, so
              purposely refresh this early to watch it happen.
             */
            if (remainingSeconds < 3570) {
                console.log("Forcing credential refresh.");
                const updatedCredentials = await s3Client.config.credentials({
                    forceRefresh: true,
                });

                const updatedNow = new Date();

                const updatedRemainingSeconds =
                    (updatedCredentials.expiration!.getTime() - updatedNow.getTime()) /
                    1000;

                console.log(
                    `Your refreshed session has ${updatedRemainingSeconds} seconds left.`,
                );
            }
        } else {
            throw new Error("This example must be run with AWS Identity Centre.");
        }
    } catch (err) {
        console.error("Failed to check credential expiry", err);
        process.exit(1);
    }
}, 1000);
```

## Local development vs. deployed

The issues discussed above are exasperated when you're comparing your local
development environment and the deployed version. If you're still using access
keys for local development and your service uses a role, I'd highly recommend
modifying the role to allow you to assume it while you're in development and
then assuming it for your testing. That'll give you a much more realistic
setup, and make it far easier to compare pre-signed URLs if you ever get a
signature error in one place but not in another.

```bash
# 1. Modify the role's trust policy to allow you to assume it

# 2. Assume the role
aws sts assume-role --role-arn ... --role-session-name local-testing

# 3. Use those new credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# 4. Launch the service you're testing
npm run start
```

## Error messages when exposing the link to your users

Let's say you want to produce a download link to a report. One option is to
render a page that has the pre-signed link, like so:

```html
<a href="https://my-cool-bucket.s3.eu-west-1.amazonaws.com/....">Download</a>
```

If your user copies the link and either bookmarks it or shares it, it's likely
that it won't work when they come back to use it again. AWS's error message
isn't very end-user friendly, nor is it branded like your application.

### Workarounds

An alternative option is to present the user a link that will redirect them to
S3 when used:

```html
<a href="https://download.example.com/files/report.pdf">Download</a>
```

When they navigate to the link you'll authenticate them, generate the
pre-signed URL and use the `Location` header to send them to S3. If they
bookmark or share the link, they'll be re-authenticated and get a fresh
pre-signed URL at the time of use.

## Error messages when your client application uses the URL

I'd also suggest building in robust error handling to your client applications
(e.g. a Single Page App) when they're making use of pre-signed URLs. If you
generate the link when the user first navigates to the page, it may expire
before they've completed the operation. For example, they may open another
window to find the file(s) that they want to upload and then pop out for lunch.
When they try and use your webapp to upload their file(s), it'll error as the
pre-signed URL has expired.

### Workarounds

Generate the pre-signed URL just before it's about to be used. For example,
you might respond to the on change event for the file input that the user uses
to select their file(s). At that point, you'll show a loading spinner, make the
call to your API for the pre-signed URL and then perform the upload.

## Whitespace \[in environment variables\]

A 'fun quirk' of the pre-signing process is that it'll happily sign URLs for
you that will never be valid. If you're unlucky enough to include any
whitespace around your access keys, you'll still get a pre-signed URL, but it
just won't work. This _should_ be a pretty rare problem given that you're
hopefully using IAM roles and the automatic provisioning of credentials, e.g.
with an EC2 Instance Profile, a Fargate task role, a Kubernetes plugin in EKS
or Identity Centre (née SSO) on your local machine.

I have a toy Kubernetes cluster that runs outside of AWS and uses access keys
over another solution like [IAM Roles Anywhere] out of pure ease / simplicity.
I recently base64 encoded the access keys I was going to apply to my service
like this:

```bash
echo AKIAmykey | base64
```

The seasoned players will immediately spot what I've done. `echo` adds a
newline by default, and thus my access keys had a `\n` at the end. Queue a
solid hour of head scratching wondering why the damn thing wouldn't work when
the same keys were fine on my laptop.

[IAM Roles Anywhere]: https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html

### Workarounds

Avoid the use of access keys. If you have to use them, take care when setting
environment variables to ensure you don't have any extra characters hanging
around.

## Not reading the full error message

This one might sound a little silly, but hear me out. The error returned when
a signature mismatch happens is very descriptive. It lists out exactly what AWS
signed when it tried to check the signature was valid. The problem comes if
your error handling or error reporting system or logger or whatever else
doesn't let you see the full thing (it's returned as a response body). If
that's the case, you'll be chasing your tail trying to work out what's wrong.

### Workarounds

Log / report / inspect the full response body returned by AWS if you get a
signature mismatch error.

## Missing headers that need to be signed

Here's an example of client code that ensures the object you're uploading is
encrypted. We can always enable default bucket encryption, but you might also
be tempted to enforce encryption using a bucket policy that denies any requests
not made with the encryption header set. If you're using that setup, you'll
want to have clients upload their file(s) as follows:

```typescript
// We're using the axios HTTP client for a quick example
await axios.put(
    // Here's the URL, returned by an API call we've just made
    presignedUrlResponse.data.url,
    // We're using a FormData object to upload the file on an SPA
    formData.get("file"),
    {
        /*
          Here we use the default server-side encryption - see the link below for
          the Customer Managed Key version:
    
          https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html
         */
        headers: {
            "x-amz-server-side-encryption": "AES256",
        },
    }
);
```

### Workarounds

When we sign the URL on the server, we must ensure that the relevant additional
headers are signed too:

```typescript
const command = new PutObjectCommand({
    Bucket: "my-test-bucket",
    Key: `${customerId}/${uploadId}.xlsx`,
    /*
      We don't explicitly spell out the header here, but this parameter will be
      translated into that header getting signed when the URL is generated.
     */
    ServerSideEncryption: ServerSideEncryption.AES256,
});

const url = await getSignedUrl(s3Client, command, {
    expiresIn: 60,
});
```
