---
layout: post
title: "Right-sizing Lambda functions that process files"
date: 2023-04-16 16:49:00 +0100
categories:
  - AWS
  - Lambda
  - S3

---

I'd hazard a guess that most serverless teams will develop architectures that
look like this:

**S3 BUCKET - LAMBDA**

We start with some form of file arriving into the system, for example a daily
report or data export. Perhaps we're integrating with a legacy system that
supports SFTP, and we're using [AWS Transfer] to handle the file transfer
without managing any servers. We could alternatively be having users upload
files to import their new users into our SaaS product, in which case we would
likely be taking advantage of [pre-signed URLs] (check out [this post] for
some common footguns and workaround with those). Regardless of our use-case,
files arrive into an S3 bucket, and we must process them in a timely manner.

[AWS Transfer]: https://aws.amazon.com/aws-transfer-family/
[pre-signed URLs]:
[this post]: 

• Measuring the right Lambda function size for a given input.
• Rescuing things when they go wrong - automated?
• Choosing an appropriate Lambda function in a clever way.
• Cost savings vs them all being big Lambdas.
