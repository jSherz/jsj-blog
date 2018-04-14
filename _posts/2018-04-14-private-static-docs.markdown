---
layout: post
title: "Securing private docs with CloudFront & Lambda@Edge"
date: 2018-04-14 09:31:00 +0100
categories: s3 CloudFront Lambda@Edge Jekyll docs ReadTheDocs
---

In [a previous article]({% post_url 2017-10-26-password-protecting-bucket %}),
we looked at a method of restricting access to a CloudFront distribution with
the use of a CloudFront private key that could sign cookies granting access to
private files or even a static website.

With [AWS Lambda@Edge](https://docs.aws.amazon.com/lambda/latest/dg/lambda-edge.html),
we can remove a few of the steps in that article and replace them with a Lambda
function that runs on each of the CloudFront edge nodes that will handle
authenticating users and protecting a private S3 bucket that contains our
internal static site or docs.

## Step 1. The Bucket

To begin, we're going to create an S3 bucket that has a "private" access
control list (ACL). The ACL is very important as it prevents users from
accessing the files inside of it without passing through our CloudFront
distribution (and thus Lambda function).

*NB:* The below example is for eu-west-1, so you may need to update the
LocationConstraint.

```bash
aws s3api create-bucket --bucket jsherz-com-docs-test \
                        --acl private \
                        --create-bucket-configuration LocationConstraint=eu-west-1
```

Our next step is to create a CloudFront origin access identity. This can be
assigned to a CloudFront distribution and then used in an S3 bucket policy
to allow CloudFront to serve the bucket's files even though they're private.

```bash
aws cloudfront create-cloud-front-origin-access-identity \
    --cloud-front-origin-access-identity-config \
        CallerReference='Private docs',Comment='Private docs'
```

After we've created that, note down the canonical user ID (called S3CanonicalUserId
in the response) and then adapt the following command to set our bucket's policy:

```bash
aws s3api put-bucket-policy --bucket jsherz-com-docs-test \
    --policy '{
    "Version":"2012-10-17",
    "Id":"PolicyForCloudFrontPrivateContent",
    "Statement":[
        {
        "Sid": "Grant a CloudFront Origin Identity access to support private content",
        "Effect": "Allow",
        "Principal": {"CanonicalUser":"......"},
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::jsherz-com-docs-test/*"
        }
    ]
}'
```

For more information about the origin access identity and the above policy, see:

- [Using an Origin Access Identity to Restrict Access to Your Amazon S3 Content](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [Granting Permission to an Amazon CloudFront Origin Identity
](https://docs.aws.amazon.com/AmazonS3/latest/dev/example-bucket-policies.html#example-bucket-policies-use-case-6)

## Step 2. The Lambda Function

Now that we've set up our bucket & origin access identity, we can create the
Lambda function that will authenticate users. In this example, we're going to
use a static / hard-coded list of users and [basic auth](https://en.wikipedia.org/wiki/Basic_access_authentication)
to identify them. For a more advanced setup, you could authenticate the user
against an external source (e.g. database, LDAP) and then issue them with a
stateless session token like a JSON Web Token.

You can view the full source code to this Lambda function in [its git repository](https://github.com/jSherz/lambda-at-edge-basic-auth).

Begin by creating an IAM role to use with the Lambda function:

```bash
aws iam create-role --role authenticate-docs \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": {
            "Effect": "Allow",
            "Principal": {"Service": [
                "lambda.amazonaws.com",
                "edgelambda.amazonaws.com"
            ]},
            "Action": "sts:AssumeRole"
        }
    }'

aws iam put-role-policy --role-name authenticate-docs \
    --policy-name AllowPushingLogsToCloudWatch \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:*:*:*"
            ]
            }
        ]
    }'
```

With the role created, we can proceed to make the Lambda function itself. Swap
out the `000000000000` AWS account ID for your own when executing this command.

*NB:* The Lambda function must be created in North Virginia (us-east-1) to be
used with Lambda@Edge / CloudFront.

```bash
wget https://github.com/jSherz/lambda-at-edge-basic-auth/releases/download/v1.0/lambda-at-edge-basic-auth.zip

aws lambda create-function \
    --function-name authenticate-docs \
    --region us-east-1 \
    --zip-file fileb://lambda-at-edge-basic-auth.zip \
    --runtime nodejs6.10 \
    --handler index.handler \
    --role arn:aws:iam::000000000000:role/authenticate-docs
```

To use the Lambda function with CloudFront, we must publish a version. Every
time you update the function, you must publish a new version and then update
your CloudFront distribution(s).

```bash
aws lambda publish-version --region us-east-1 \
                            --function-name authenticate-docs
```

OK! We're getting closer. Last step (I promise), CloudFront.

## Step 3. The CloudFront Distribution

This is a bit of a lengthy command, but we've got a lot of settings to go
through. If you prefer, you can create the CloudFront distribution through the
AWS console. The key parts are the "Origins" section that identifies that we
want to use our CloudFront origin access identity with the S3 bucket and also
the "LambdaFunctionAssociations" that ensures requests are authenticated with
our Lambda function.

```bash
aws cloudfront create-distribution \
    --distribution-config '{
        "CallerReference": "Private docs",
        "Aliases": {
            "Quantity": 0
        },
        "DefaultRootObject": "index.html",
        "Origins": {
            "Quantity": 1,
            "Items": [
                {
                    "S3OriginConfig": {
                        "OriginAccessIdentity": "origin-access-identity/cloudfront/ABC123ABC123"
                    },
                    "OriginPath": "",
                    "CustomHeaders": {
                        "Quantity": 0
                    },
                    "Id": "s3",
                    "DomainName": "jsherz-com-docs-test.s3-eu-west-1.amazonaws.com"
                }
            ]
        },
        "DefaultCacheBehavior": {
            "FieldLevelEncryptionId": "",
            "TrustedSigners": {
                "Enabled": false,
                "Quantity": 0
            },
            "LambdaFunctionAssociations": {
                "Quantity": 1,
                "Items": [
                    {
                        "LambdaFunctionARN": "arn:aws:lambda:us-east-1:000000000000:function:authenticate-docs:1",
                        "EventType": "viewer-request"
                    }
                ]
            },
            "TargetOriginId": "s3",
            "ViewerProtocolPolicy": "redirect-to-https",
            "ForwardedValues": {
                "Headers": {
                    "Quantity": 0
                },
                "Cookies": {
                    "Forward": "none"
                },
                "QueryStringCacheKeys": {
                    "Quantity": 0
                },
                "QueryString": false
            },
            "MaxTTL": 86400,
            "SmoothStreaming": false,
            "DefaultTTL": 3600,
            "AllowedMethods": {
                "Items": [
                    "HEAD",
                    "GET",
                    "OPTIONS"
                ],
                "CachedMethods": {
                    "Items": [
                        "HEAD",
                        "GET"
                    ],
                    "Quantity": 2
                },
                "Quantity": 3
            },
            "MinTTL": 0,
            "Compress": false
        },
        "CacheBehaviors": {
            "Quantity": 0
        },
        "CustomErrorResponses": {
            "Quantity": 0
        },
        "Comment": "Private docs",
        "Logging": {
            "Enabled": false,
            "IncludeCookies": false,
            "Bucket": "",
            "Prefix": ""
        },
        "PriceClass": "PriceClass_200",
        "Enabled": true,
        "ViewerCertificate": {
            "CloudFrontDefaultCertificate": true,
            "MinimumProtocolVersion": "TLSv1.1_2016",
            "CertificateSource": "cloudfront"
        },
        "Restrictions": {
            "GeoRestriction": {
                "RestrictionType": "none",
                "Quantity": 0
            }
        },
        "HttpVersion": "http2",
        "IsIPV6Enabled": true
    }'
```

Once the CloudFront distribution has been created, you can visit it and check
that the authentication is working as you expect. A demo can be seen at: [https://dnks3lqae48yt.cloudfront.net](https://dnks3lqae48yt.cloudfront.net).
See the Lambda code for some valid users.

### Caveats

* The Lambda function must be published to a specific version for use with
    CloudFront. In the above example, we used the version 1 specified by ":1"
    in the LambdaFunctionAssociations above. As you update the Lambda function,
    ensure you publish the latest version and update the CloudFront
    distribution.

* Before uploading your docs or internal static site, check that you can't
    access the bucket directly and that requests to the CloudFront distribution
    are being authenticated.

* If creating the CloudFront distribution through the console, ensure that you
    set "Restrict Viewer Access" to "No" in the cache behaviour settings.

* Ensure the hostname you give for the S3 bucket includes the region (see above
    for a working example).

* When testing the distribution is setup correctly, upload an index.html file
    to the S3 bucket or you may see an "Access Denied" error.

## That's it!

I hope that you managed to follow along and get everything working (or if you
chose not to that the examples were clear enough). Contributions to [the Lambda function](https://github.com/jSherz/lambda-at-edge-basic-auth)
are welcome - including security reviews!
