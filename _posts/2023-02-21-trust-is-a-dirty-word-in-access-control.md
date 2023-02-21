---
layout: post
title: "Trust is a dirty word in access control"
date: 2023-02-21 20:19:00 +0100
categories:
- trust
- authorization
- access
- "Identity & Access Management"
- AWS
---

There are plenty of words you wouldn't use in a conversation at work. Maybe
they feel inappropriate; maybe they're considered unacceptable in the culture
of your organization, country or region. I want to add another word to the
naughty list: trust. Specifically, I want to challenge you and state that we
shouldn't be using "trust" when we talk about access control and authorization.

I'm guilty of being someone who hoarded access in the past, someone who kept
the keys to the kingdom and paid out piecemeal odds and ends of permissions as
and when the pressure of giving in to an access request outweighed the energy I
had to question it. When I reflected on why I didn't want to grant that 
access, I arrived at the following list.

I didn't trust the person or team:
  * to treat the data with care;
  * to build the tooling required to make supporting an application sustainable;
  * to build infrastructure and software securely;
  * to have others act in the same way that I internally held as correct;
  * to audit the access they granted and used;
  * to interrogate if their access was really required, or if it was just a 
    convenience.

To all of the above problems, I took the easy route: I used access control or
authorization as a sticking plaster to avoid having to solve the underlying
problems. I'm here to tell you that I was wrong, and that I needed to replace
that judgement based on trust to robust controls and guidance that help anyone
I work with get it right. I'd even go as far to suggest that we often have
conversations about access where in our heads we're thinking about trust, but
what we verbalize is something else.

So what's my beef with trust?

## When does trust start and end?

If you grant access to someone when you trust them, you have to wait for that
trust to build. Do you grant them access on the first day of the job or in your
team? How about week one? Month one? Month six? After the background check has
passed? If you trust someone enough to hire them, have them be a representative
of your company, to work in your office, to pay them to do a job, why can't you
trust them with access? Surely any delay to that is a delay to them being 
productive and thus earning your trust?

I argue we should assign access based on need, and that need starts
immediately. It's not a static thing either - it changes and should have 
robust review over time. Get a human to look at access on a regular basis -
you'll always turn a rock over with something spooky underneath.

## What access does Billy Big Bollocks get?

What access does a manger get? How about senior manager? VP? Director? C-suite
executive? I'd argue that it should be based just around their needs, rather
than anything to do with trust. Would you tell your boss' boss' boss that
you don't trust them with access? Of course not! Well, at least I wouldn't. I'd
try to bring them on side: talk them through the principle of least privilege,
and get them what they _require to do their job_.

## What happens to trusted users who get hacked?

It's hard to avoid news stories about big businesses where a single user was
spear phished and suddenly your delightful sourcecode is plastered across
the internet. Our most trusted colleagues are still humans who make mistakes 
like anyone, and their access makes them a juicy target. The amount we trust
them doesn't change the risk their access attracts or the consequences when 
things don't go to plan.

If we apply the principles discussed below, we limit what they have access to
and keep detailed auditing about what they do. That's a good thing when we're
all one slip away from entering our details into crontoso.com instead of
contoso.com. Challenge/response authentication like FIDO2 tokens and good 
working practices to store passwords in a password manager that will only 
autofill on the right websites don't hurt either!

## Name-calling and sitting alone at the lunch table

If we don't address the underlying problems that we attempt to resolve with
limiting access, we also risk infantilizing our colleagues and treating them
like they're not trusted - even if we do actually trust them. Build robust
controls that help them understand the state of their own infrastructure and
solve their own security related findings. Point them to the same talks, docs
and other materials that won you over and shaped your approach to security.
Write the most minimal policies that are a good fit for your organization's 
needs and hold your teams to account for following them.

## Practical solutions to my big list of distrust

Regardless of if you agree with my premise above, it's worth us discussing
practical ways you can improve how you and your colleagues use data. I'll give
examples in AWS-speak, but other clouds have equivalent options.

### Treat data with care

Write a policy that makes expectations clear with input from key stakeholders, 
socialize it, performance manage people who don't follow it. Sorry, that's
the best I've got for that one.

### Tooling to make supporting an application sustainable

If you've ever tried selling the idea of writing a whole custom web-app purely
for internal support, you'll likely know that the idea can get some push back.
An awesome half-way house that lets you build auditable graphical interfaces
with granular access control is [Retool] (not sponsored). When I last deployed
it, it had the odd rough edge, but overall I think it's a superb way to drag
and drop your way to an interface anyone can use as fast as you can knock out
some SQL queries.

I find Retool a great way of building operational tasks into something that's
executable by anyone (hint hint in your run books), rather than something
that's executable by you, but only when you find that file you had somewhere
with that query in. Maybe it was in Notepad++. Or maybe IntelliJ. Or did you
save it in the Downloads folder?

Above and beyond operational work, you can also build applications that work
perfectly well for non-technical internal users who perform actions at low
volume. If you want to go big scale then do your performance testing homework.
YMMV and I'm just some guy on the internet who used it a while back.

My personal preferences for Retool:

* Use the git syncing.
* Have another colleague setup the git syncing, so you don't have to fiddle
  with it.
* Avoid users having direct access to databases unless it's break glass access.
* Store the database's admin user and Retool's own user in AWS Secrets 
  Manager, or really any service that lets you provably rotate the
  credentials after any human has had their grubby hands on them.
* Make use of Lambda functions, Step Functions and other AWS services to
  perform actions that get complicated enough for you to feel any sharp edges
  of Retool. You'll feel it when you get there!

  If you're not into all that serverless mumbo jumbo, just have it call your
  service's API using OAuth authentication powered by AWS Cognito.

Thank you to my wonderful ex-colleague Toby for the recommendation on this one.

[Retool]: https://retool.com

### Build software and infrastructure securely

For this element I'd recommend the combination of:

* AWS Organization Tag Policies to enforce tagging, including data 
  classification tags with well understood and enumerated values.
* Service Control Policies that block resources created without tags (where 
  possible).
* AWS Identity Centre (née SSO) configured with day-to-day access that limits
  access to resources containing sensitive data, e.g. PII, and break-glass
  access for anything else. Ooh an opportunity to plug another post:
  [Break glass access in AWS with Step Functions].
* AWS Config to tell you that your infrastructure doesn't comply with best
  practices.
  * Choose your compliance pack flavour of choice and attempt to hide the 
    subsequent bill from the accounts team.
  * Custom Config rules to ensure that data sources tagged as containing
    sensitive data have additional controls (discussed below).
* AWS Security Hub to collate the Config findings that you really should get
  around to reading and do something about (please setup notifications).
* OWASP or equivalent security materials being an integral part of mandatory
  training.

The above will (hopefully) ensure that non-compliant resources are identified
quickly and resolved by the team that made them. It _should_ help to keep data
access audited. On that topic...

[Break glass access in AWS with Step Functions]: https://jsherz.com/step%20functions/sre/lambda/api%20gateway/serverless/break%20glass%20access/2022/06/23/break-glass-access-in-production.html

### Auditing access

Plenty of services log to AWS CloudTrail, so you should have that on. For the
more "datary" stuff, it depends:

* S3 - mandate the use of CloudTrail data events when pesky humans have
  access to data deemed sensitive by the aforementioned tagging strategy.
* DynamoDB - as above.
* Insert data source that doesn't have good audit logging - restrict access to
  an internal tool like Retool and have it do the auditing part. If you can
  turn on auditing that's granular enough to see what a human or machine did
  after the fact, then great. Otherwise, limit access to just break glass
  scenarios.
  * This will cover your Postgres, Redis, Elasticsearch types.
  * Additionally, see if you can setup VPC Flow Logs targeting all traffic
    (not just blocked traffic) that happens between humans and the data source.
    For example, you might configure a Zero Trust Access tool to reach your
    Postgres database and then have all of its traffic recorded and archived
    away in a secure location. At least if the proverbial hits the fan you've
    got some indication of who it was. Favour Zero Trust Access tools over a
    classic VPN unless, you guessed it, it supports granular auditing.

As a general rule, if you can clearly audit what data was viewed or modified
then the service is a candidate for day-to-day direct access. If not, front it
with a tool like Retool or keep it to break-glass access only.

Don't forget to store the logs somewhere where your users cannot delete them.
Not even the ones you trust.

## Some sort of conclusion

That's my take on access control as it stands today. As noted before, I've
adapted this over time and made my fair share of mistakes with paths previously
trodden. If you've got opinions on access control or tips to help achieve the
above, share them with your lovely colleagues.
