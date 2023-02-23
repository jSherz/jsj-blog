---
layout: post
title: "Pre-signed URLs in AWS S3 - gotchas that got me"
date: 2023-02-23 22:26:00 +0000
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
