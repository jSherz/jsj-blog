---
layout: post
title: "Building a cheap and simple utility website with AWS Lambda"
date: 2019-02-10 10:24:00 +0100
categories: Lambda AWS cheap utility service bootstrap jQuery
---

It doesn't take much programming or web development to hit the first point where
you'd like a simple tool to escape special characters in some text or base 64
encode a value (or similar). Recently, I ran into a problem where I needed to
test some input against a particular version of a Java library and for others to
be able to perform the same task without my intervention. AWS Lambda is a great
candidate for these stateless utilities as it's so cheap to run and has minimal
operational overhead.

## The problem

For this example, we're going to build a utility that validates a configuration
file for the

In this example, we're going to build a utility that validates the provided SSH
public key is in an accepted ~format~ (RSA) and also is for a 2048 or 4096 bit
private key. Different tools of various vintages produce SSH keys that are in
different formats (e.g. OpenSSH or Putty) and so we want to provide an easy way
for users to validate that their public key will be accepted by a fictitious
Java system. I'm sure many of you have wrestled with legacy Java applications
that produce obscure error messages in your careers and thus hopefully this
example won't feel too far fetched.

## The Java Lambda function

We're going to use the API Gateway proxy integration and so will be parsing
andproducing JSON objects that contain the user's request and tell API Gateway
how to respond to a user respectively.

In the code example below, we start by decoding the incoming request and
themdetermining if it's a GET or POST request. For simplicities sake, we'll
serve the user a static HTML page when they make a GET request to our Lambda
function and will have them make a POST AJAX request back to the same endpoint
to validate their SSH public key.

<request setup>

The HTML page we'll serve will be a static bootstrap page with jQuery doing
thecross-browser heavy lifting of the AJAX request. Once the user has received
the page and made A POST request back, we'll validate their key and then return
an API Gateway compatible response.

## Building the Lambda deployment bundle

We can use Maven and the shade plugin to produce a single jar file containing
the Lambda code and all application dependencies, as detailed below:

<maven project>

## Putting it all together

Once we've built the single jar, we can upload it to AWS Lambda and then create
an API Gateway API and endpoint to call the function.

When the user views our API (example link), they're shown the HTML page which
they can then use to make a POST request and validate their SSH public key. The
cost of Lambda is so low that a utility service like this is almost free and
gives us an easy way to let users perform a task that would require a local Java
install and program with minimal effort.
