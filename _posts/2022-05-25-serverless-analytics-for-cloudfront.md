---
layout: post
title: "Serverless analytics for CloudFront Distributions"
date: 2022-05-25 18:52:00 +0100
categories:
- Serverless
- CloudFront
- S3
- CloudTrail
- GitHub Actions
---

CloudFront and S3 make a great combination for hosting static websites, just
like this blog that's generated with [Jekyll]. There are a number of popular
analytics tools, but many compromise the privacy of your users, require
JavaScript, or have a monthly fee that's prohibitive for a hobbyist website.
[GoAccess] is a versatile tool that can be used to generate real-time or
static analytics based on logs from many webservers, including CloudFront.
We can use a combination of GitHub Actions and GoAccess to produce a
regularly updated snapshot of our CloudFront Distributions analytics.
CloudFront access logs are roughly 15 minutes behind real time, so we're not
losing much by only viewing them as static snapshots.

[Jekyll]: https://jekyllrb.com/
[GoAccess]: https://goaccess.io/

To generate our analytics, we'll have CloudFront store logs in an S3 bucket,
download them on a schedule and then produce a static report. We can upload
the report files to a secure location, e.g. a different S3 bucket and
CloudFront Distribution that uses Lambda@Edge to authenticate users.

Here's how our CloudFront Distribution is configured in Terraform to do access
logging:

```terraform
resource "aws_cloudfront_distribution" "website" {
  /* ... */

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.access_logs.bucket_regional_domain_name
  }

  /* ... */
}
```

We could use any method of running some scripts on a schedule, for example AWS
CodeBuild with EventBridge, or a cron job on an EC2 instance. We'll use GitHub
Actions because it has no infrastructure we have to manage, and we can
collocate the analytics job in the same repository that defines the
infrastructure.

The premise of our job is:

```bash
# Download some access logs
aws s3 sync \
  --exclude "*" \
  --include "DISTRIBUTION_ID.2022-05*" \
  --no-progress \
  s3://my-logs-bucket .

# Generate the report
goaccess ....

# Upload the files
aws s3 sync report s3://secure-bucket
```

But how do we quantify the cost of running this reporting on a regular basis,
e.g. every hour? If we run the `aws s3 sync` command shown above on our logs
bucket, we can examine [CloudTrail] entries to understand what API calls are 
required. Let's put together a [CloudWatch Insights] query that will find the
number of API calls required:

[CloudTrail]: https://aws.amazon.com/cloudtrail/
[CloudWatch Insights]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html

```
filter eventSource == "s3.amazonaws.com" and requestParameters.bucketName == "my-website-logs"
  | fields @timestamp, @message
  | stats count(*) by eventName
```

| eventName                  | count(*) |
|----------------------------|----------|
| GetObject                  | 11988    |
| PutObject                  | 1        |
| ListObjects                | 32       |
| GetBucketPolicyStatus      | 2        |
| GetBucketPublicAccessBlock | 2        |
| GetBucketAcl               | 2        |

Not seeing any results? Make sure you have CloudTrail setup with data events
recorded for your access logs bucket. Be careful! Data events are **not free**.

That's quite a few calls to GetObject! You'll notice that there's a 
PutObject call in there, which indicates that we're not filtering this down to
just the IAM principal syncing those files. Let's do that:

```
filter eventSource == "s3.amazonaws.com" and requestParameters.bucketName == "my-website-logs"
  | filter userIdentity.sessionContext.sessionIssuer.arn == "arn:aws:iam::123456789012:role/github-actions"
  | fields @timestamp, @message
  | stats count(*) by eventName
```

With the above filtering in place, the results look a lot more sensible:

| eventName                  | count(*) |
|----------------------------|----------|
| GetObject                  | 11988    |
| ListObjects                | 32       |

So how much will that cost? Let's assume we're calculating this for a month
with 30 days, performing this work once an hour and have an accurate figure for
the number of logs we'll save each month. That would be around 23k list requests
and 8.6m get requests, or $3.57 a month. Let's not forget egress! Downloading
our 49MB of files 720 times adds another roughly $3.24 to our bill. These
numbers will vary greatly depending on the traffic your distribution receives -
don't take the above figures as realistic for you, get CloudTrail fired up
and do the math!

OK back to the analytics. Let's start by determining a CRON schedule we'd like
to update our figures on. For the current month's data, we could do three times
a day:

```yaml
name: 'Analytics'

on:
  schedule:
    - cron: '41 5 * * *'
    - cron: '41 11 * * *'
    - cron: '41 17 * * *'
  workflow_dispatch:
```

Wondering why 41 minutes past the hour was chosen? GitHub will delay actions
that are run at busy periods, e.g. on the top of the hour. If we're looking
back at previous month's data, we might just do this once a month. Try out
your ideas in [crontab.guru] to find what's right for your needs.

[crontab.guru]: https://crontab.guru/

With the triggers set, we can start our job by authenticating with AWS and
installing GoAccess:

```yaml
jobs:
  analyse:
    name: 'analyse'
    runs-on: ubuntu-20.04

    defaults:
      run:
        shell: bash

    permissions:
      contents: read
      id-token: write

    steps:
      - name: Checkout
        uses: actions/checkout@v2

      - name: Authenticate with AWS
        uses: aws-actions/configure-aws-credentials@v1
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions
          aws-region: eu-west-1

      - name: Install GoAccess
        run: |
          sudo apt-get update && \
          sudo apt-get install --yes libmaxminddb-dev && \
          aws s3 cp s3://my-assets/goaccess-1.5.7.tar.gz goaccess.tar.gz && \
          tar -xf goaccess.tar.gz && \
          mv goaccess-* goaccess && \
          cd goaccess && \
          ./configure --enable-utf8 --enable-geoip=mmdb && \
          make && \
          sudo make install
```

You'll note that I'm downloading the files from an S3 bucket I own and then
building it on every run. It would be more efficient to build it once and then
just `make install` the result each time, but what is a blog post without
something you can copy, paste and improve?! I prefer to fetch assets from my
own hosting if I'm doing something on a schedule, primarily because I don't
want to use excessive bandwidth from a project that is providing me with 
something for free. Additionally, we're tying the availability of those file(s)
to a resource in our control. Nothing sucks more than every CI job in your 
company failing because an obscure site hosting a tarball you use is down.

With the files in place, we can then have two slightly different steps depending
on which job we're running, one for this month's analytics:

```yaml
      - name: Generate analytics
        run: |
          THIS_MONTH=$(date "+%Y-%m") && \
          mkdir $THIS_MONTH && \
          aws s3 sync --exclude "*" --include "DISTRIBUTION_ID.$THIS_MONTH*" --no-progress s3://my-website-logs . && \
          mv DISTRIBUTION_ID.$THIS_MONTH* $THIS_MONTH/ && \
          for f in $THIS_MONTH/*.gz; do gunzip -c $f >> this-month.log ; done && \
          cat this-month.log | goaccess -a -o html --log-format CLOUDFRONT - > this-month.html && \
          aws s3 cp this-month.html s3://my-destination/this-months-stats/
```

And one for a job that looks at many months, perhaps including the current one:

```yaml
      - name: Generate analytics
        run: |
          TWO_MONTHS_AGO=$(date --date 'now - 2 months' "+%Y-%m") && \
          ONE_MONTH_AGO=$(date --date 'now - 1 month' "+%Y-%m") && \
          THIS_MONTH=$(date "+%Y-%m") && \
          mkdir $TWO_MONTHS_AGO $ONE_MONTH_AGO $THIS_MONTH && \
          aws s3 sync --exclude "*" --include "ED1VZP9YJFXGU.$TWO_MONTHS_AGO*" --include "ED1VZP9YJFXGU.$ONE_MONTH_AGO*" --include "ED1VZP9YJFXGU.$THIS_MONTH*" --no-progress s3://jsj-prod-jsherz-com-website-logs . && \
          mv ED1VZP9YJFXGU.$TWO_MONTHS_AGO* $TWO_MONTHS_AGO/ && \
          mv ED1VZP9YJFXGU.$ONE_MONTH_AGO* $ONE_MONTH_AGO/ && \
          mv ED1VZP9YJFXGU.$THIS_MONTH* $THIS_MONTH/ && \
          for f in $TWO_MONTHS_AGO/*.gz; do gunzip -c $f >> two-months-ago.log ; done && \
          for f in $ONE_MONTH_AGO/*.gz; do gunzip -c $f >> one-month-ago.log ; done && \
          for f in $THIS_MONTH/*.gz; do gunzip -c $f >> this-month.log ; done && \
          cat two-months-ago.log | goaccess -a -o html --log-format CLOUDFRONT - > two-months-ago.html && \
          cat one-month-ago.log | goaccess -a -o html --log-format CLOUDFRONT - > one-month-ago.html && \
          cat this-month.log | goaccess -a -o html --log-format CLOUDFRONT - > this-month.html && \
          aws s3 cp two-months-ago.html s3://my-destination/ && \
          aws s3 cp one-month-ago.html s3://my-destination/ && \
          aws s3 cp this-month.html s3://my-destination/
```

If you're a DRY enthusiast, you might want to adapt the above into some lean
bash functions or Python masterpiece, but I just wanted something that works
simply and effectively for my use case.

Let's break down what we're doing in these jobs. We start by using the `date`
command to find out the current month, last month and two months ago. We format
that value into a YYYY-MM string:

```bash
date --date 'now - 2 months' "+%Y-%m"

# outputs: 2022-03
```

With that, we can make some directories for our log files:

```bash
mkdir $TWO_MONTHS_AGO $ONE_MONTH_AGO $THIS_MONTH
```

We'll use `aws s3 sync` with some exclude and include filters to first exclude
all files, then add in just the ones that we're interested in (the last 3
months in this case). Prefix / key design in S3 is really important when you're
trying to power use cases like the one we're doing today. Imagine if the files
were named in `DD-MM-YYYY` format!

```bash
aws s3 sync \
  --exclude "*" \
  --include "ED1VZP9YJFXGU.$TWO_MONTHS_AGO*" \
  --include "ED1VZP9YJFXGU.$ONE_MONTH_AGO*" \
  --include "ED1VZP9YJFXGU.$THIS_MONTH*" \
  --no-progress \
  s3://my-website-logs .
```

The smart people linked in the "References" section of this post then handed me
a nice bash one-liner to combine all of those log files into one big file for
the month:

```bash
for f in $TWO_MONTHS_AGO/*.gz; do gunzip -c $f >> two-months-ago.log ; done
```

All finished off with a call to goaccess to generate the report:

```bash
cat two-months-ago.log | goaccess -a -o html --log-format CLOUDFRONT - > two-months-ago.html
```

That's it! Load up your secured destination bucket and look at some pretty 
charts:

![A chart showing a varying but small number of unique visitors to this blog.](/assets/serverless-analytics-for-cloudfront/pretty-charts.png)

## References

This article wouldn't have been possible without the following resources:

* [DIY Analytics with GoAccess](https://serialized.net/2017/07/diy-goaccess-analytics/)
* [Analyse CloudFront logs with goaccess](https://megamorf.gitlab.io/2021/03/08/analyse-cloudfront-logs-with-goaccess/)
* [Doing Date Math on the Command Line, Part I](https://www.linuxjournal.com/content/doing-date-math-command-line-part-i)
