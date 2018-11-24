---
layout: post
title: "Providing password-based access to a private S3 bucket with Lambda and CloudFront"
date: 2017-10-26 19:13:00 +0100
categories: infrastructure aws s3 bucket password lambda cloudfront
---
Amazon&rsquo;s Simple Storage Service doesn&rsquo;t natively support password-protected
access, however we can use a CloudFront distribution and private ACL to
control access to the bucket and then use Lambda to issue signed cookies after
validating a password.

<div style="width:100%;height:0;padding-bottom:56%;position:relative;"><iframe src="https://giphy.com/embed/3o7aD0ZXjRddZhqdXy" width="100%" height="100%" style="position:absolute" frameBorder="0" class="giphy-embed" allowFullScreen></iframe></div><p><a href="https://giphy.com/gifs/3o7aD0ZXjRddZhqdXy">via GIPHY</a></p>

## How it works

1. A user visits the CloudFront distribution. This could either be directly to
   the *abcde.cloudfront.net* hostname or a CNAME. You can also setup SSL with
   an Amazon provided certificate.

2. They are denied access, as the bucket has a `private` ACL.

3. CloudFront is configured with a custom error page that presents a login page.

   *See:* [bucket-access-button.html on GitHub](https://github.com/jSherz/bucket-access-button/blob/master/bucket-access-button.html)

4. The user enters the password, and this is validated with a lambda function.

   *See:* [bucket-access-button.js on GitHub](https://github.com/jSherz/bucket-access-button/blob/master/bucket_access_button.js)

5. The lambda function returns the values for several cookies. These aren&rsquo;t set
   by the function itself / API Gateway as it would require setting up a custom
   domain name for API Gateway and also using the same domain for the CloudFront
   distribution.

6. The login page sets the cookies using the provided values, and redirects the
   user back to the homepage.

## Tutorial

**Protip:** For an easy way to create all of the required infrastructure, I&rsquo;ve created a [Terraform module](https://github.com/jSherz/bucket-access-button/tree/master/terraform_example).

1. Create a bucket with a [private ACL](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html).
   The ACL prevents direct access to the bucket.

   *Do not set up bucket website hosting.*

2. Create a [CloudFront distribution](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-creating.html)
   that points to the S3 bucket and also a [CloudFront origin identity](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).

3. Upload the `bucket-access-button.html` to your S3 bucket and rename it to `login.html`.

4. On your CloudFront distribution, add a [custom error response](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/custom-error-pages.html)
   that redirects errors with code `403` to `/login.html` and a `200` status code.

   *This step will show users the login page, even if they don&rsquo;t have access to the access the object directly.*

5. In the "Security Credentials" section of IAM, create a [CloudFront private key](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-trusted-signers.html).

6. Create a [new KMS key](https://docs.aws.amazon.com/kms/latest/developerguide/create-keys.html)
   and [encrypt the CloudFront private key](https://docs.aws.amazon.com/cli/latest/reference/kms/encrypt.html).

7. Create a new lambda function using the `bucket-access-button.js` linked above.
   You will have to set the following environment variables.

   * `ENCRYPTED_PASSWORD`

      The password that will protect access to your bucket, encrypted with the
      above KMS key.

   * `ENCRYPTED_CLOUDFRONT_PRIVATE_KEY`

      The encrypted CloudFront private key from step 6.

   * `CLOUDFRONT_KEYPAIR_ID`

      The ID associated with your CloudFront private key.

   * `CLOUDFRONT_DOMAIN_NAME`

      The hostname of your CloudFront distribution (or CNAME if applicable).

8. Create a new IAM role for the lambda function, with access to `kms:Decrypt`
   with the above key.

8. Create an API Gateway REST API, resource and method that points to your new lambda function.

   **NB:** Ensure you use the "Enable CORS" option on your method.

9. Point users to the CloudFront distribution and provide them the password!
