---
layout: post
title: "Making lots of the same thing in IaC (CDK & Terraform)"
date: 2023-10-18 20:09:00 +0100
categories:
  - AWS
  - CDK
  - Terraform
---

It's a common requirement in Infrastructure as Code (IaC) tools like CDK and
Terraform to make many of the same thing, with slightly differing properties.
Let's use a fictional example in which we're writing an audit service that
receives notifications from other services when a user performs an action.
Here's our architecture:

![Services A-F running in AWS ECS Fargate push user actions to their own SQS queues. The audit service polls each SQS queue for messages and stores them in a data store.](/assets/making-lots-of-the-same-thing-in-iac/architecture.drawio.png)

The designer of the audit service specified that each incoming service should
get its own SQS queue. Let's model that in IaC.

In CDK, that might look like this:

```typescript
import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import { Queue } from "aws-cdk-lib/aws-sqs";

const SERVICES = [
    "service-a",
    "service-b",
    "service-d",
    "service-e",
    "service-f",
];

export class AuditServiceStack extends cdk.Stack {
    constructor(scope: Construct, id: string, props?: cdk.StackProps) {
        super(scope, id, props);

        this.createIncomingQueues();
    }

    private createIncomingQueues() {
        for (let i = 0; i < SERVICES.length; i++) {
            new Queue(this, "incoming-queue-" + i, {
                queueName: `audit-service-incoming-${SERVICES[i]}`,
            });
        }
    }
}
```

In Terraform, that might look like this:

```terraform
locals {
  services = [
    "service-a",
    "service-b",
    "service-c",
    "service-d",
    "service-e",
    "service-f",
  ]
}

resource "aws_sqs_queue" "incoming" {
  count = length(local.services)

  name = "audit-service-incoming-${local.services[count.index]}"
}
```

Both of these code snippets create the same resources, and both have the same
caveat. What happens when we decide to retire service C, and thus take it out
of our list of services?

**CDK**

We make the change, run a `cdk diff` and get:

```
Stack AuditService
Resources
[-] AWS::SQS::Queue incoming-queue-5 incomingqueue58150E916 destroy
[~] AWS::SQS::Queue incoming-queue-2 incomingqueue2A2310290 replace
 └─ [~] QueueName (requires replacement)
     ├─ [-] audit-service-incoming-service-c
     └─ [+] audit-service-incoming-service-d
[~] AWS::SQS::Queue incoming-queue-3 incomingqueue366F6CA78 replace
 └─ [~] QueueName (requires replacement)
     ├─ [-] audit-service-incoming-service-d
     └─ [+] audit-service-incoming-service-e
[~] AWS::SQS::Queue incoming-queue-4 incomingqueue4F0571194 replace
 └─ [~] QueueName (requires replacement)
     ├─ [-] audit-service-incoming-service-e
     └─ [+] audit-service-incoming-service-f


✨  Number of stacks with differences: 1
```

**Terraform**

We make the change, run a `terraform plan` and get:

```
aws_sqs_queue.incoming[0]: Refreshing state... [id=https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-a]
aws_sqs_queue.incoming[4]: Refreshing state... [id=https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-e]
aws_sqs_queue.incoming[3]: Refreshing state... [id=https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-d]
aws_sqs_queue.incoming[1]: Refreshing state... [id=https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-b]
aws_sqs_queue.incoming[5]: Refreshing state... [id=https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-f]
aws_sqs_queue.incoming[2]: Refreshing state... [id=https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-c]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  - destroy
-/+ destroy and then create replacement

Terraform will perform the following actions:

  # aws_sqs_queue.incoming[2] must be replaced
-/+ resource "aws_sqs_queue" "incoming" {
      ~ arn                               = "arn:aws:sqs:eu-west-1:123123123123:audit-service-incoming-service-c" -> (known after apply)
      + deduplication_scope               = (known after apply)
      + fifo_throughput_limit             = (known after apply)
      ~ id                                = "https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-c" -> (known after apply)
      ~ kms_data_key_reuse_period_seconds = 300 -> (known after apply)
      ~ name                              = "audit-service-incoming-service-c" -> "audit-service-incoming-service-d" # forces replacement
      + name_prefix                       = (known after apply)
      + policy                            = (known after apply)
      + redrive_allow_policy              = (known after apply)
      + redrive_policy                    = (known after apply)
      ~ sqs_managed_sse_enabled           = true -> (known after apply)
      - tags                              = {} -> null
      ~ tags_all                          = {} -> (known after apply)
      ~ url                               = "https://sqs.eu-west-1.amazonaws.com/123123123123/audit-service-incoming-service-c" -> (known after apply)
        # (7 unchanged attributes hidden)
    }

  # aws_sqs_queue.incoming[3] must be replaced

~~ snipped for brevity ~~

  # aws_sqs_queue.incoming[4] must be replaced

~~ snipped for brevity ~~

  # aws_sqs_queue.incoming[5] will be destroyed

~~ snipped for brevity ~~

  # (because index [5] is out of range for count)

Plan: 3 to add, 0 to change, 4 to destroy.

───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Saved the plan to: plan

To perform exactly these actions, run the following command to apply:
    terraform apply "plan"
```

In both cases, we're deleting and recreating lots of resources unintentionally.
The example we've got here would lead to a temporary loss of audit events as we
delete and then recreate the queues. We'll also lose any messages that are
currently on the queues and waiting to be processed. Not good!

The CDK-heads reading may be screaming out "Hey James, that's an unrealistic 
example!" - and they'd be right to. Bare with me!

This kind of change can easily be missed in non-production environments if they
don't have a lot of traffic going through them, so we have to make sure we
consider the impact of our infrastructure changes - seeing no impact in a lower
environment is not a guarantee they'll 'just work' in the future.

How can we model these resources differently to avoid this problem?

### Using properties in resource identifiers

One option is to use a property of the resource that's unique for each
instance, for example the service name:

**CDK**

```diff
diff --git a/lib/audit-service-stack.ts b/lib/audit-service-stack.ts
index 7ca53e0..c7bb904 100644
--- a/lib/audit-service-stack.ts
+++ b/lib/audit-service-stack.ts
@@ -19,9 +19,9 @@ export class AuditServiceStack extends cdk.Stack {
   }
 
   private createIncomingQueues() {
-    for (let i = 0; i < SERVICES.length; i++) {
-      new Queue(this, "incoming-queue-" + i, {
-        queueName: `audit-service-incoming-${SERVICES[i]}`,
+    for (const service of SERVICES) {
+      new Queue(this, `incoming-queue-${service}`, {
+        queueName: `audit-service-incoming-${service}`,
         removalPolicy: RemovalPolicy.DESTROY,
       });
     }
```

In the above snippet, we replace the array index in CDK's logical ID with the
name of the service. Doing that in CDK feels a lot more natural to me anyway,
but there are cases where you can't use user input in the logical ID. If a user
forms the name with tokens (e.g. `Aws.ACCOUNT_ID` or a reference to another
resource), CDK will complain with the following error:

> ID components may not include unresolved tokens: ...

If you're the author of a downstream construct, you may not necessarily control
user input (properties), and so I'd recommend avoiding using it in logical IDs.

**Terraform**

So what does this look like in Terraform? Luckily, we have the `for_each`
operator:

```diff
diff --git a/main.tf b/main.tf
index 8fd59bf..ec8121c 100644
--- a/main.tf
+++ b/main.tf
@@ -10,7 +10,7 @@ locals {
 }
 
 resource "aws_sqs_queue" "incoming" {
-  count = length(local.services)
+  for_each = local.services
 
-  name = "audit-service-incoming-${local.services[count.index]}"
+  name = "audit-service-incoming-${each.key}"
 }
```

Unfortunately, running this gives us an error:

```
╷
│ Error: Invalid for_each argument
│
│   on main.tf line 13, in resource "aws_sqs_queue" "incoming":
│   13:   for_each = local.services
│     ├────────────────
│     │ local.services is tuple with 6 elements
│
│ The given "for_each" argument value is unsuitable: the "for_each" argument must be a map, or set of strings, and you have provided a value of type tuple.
╵
```

We can do some kind of value conversion ourselves, but my preference is to have
the user input a map of friendly names to resource names:

```diff
diff --git a/main.tf b/main.tf
index 8fd59bf..6d40064 100644
--- a/main.tf
+++ b/main.tf
@@ -1,16 +1,16 @@
 locals {
-  services = [
-    "service-a",
-    "service-b",
-    "service-c",
-    "service-d",
-    "service-e",
-    "service-f",
-  ]
+  services = {
+    service_a = "service-a",
+    service_b = "service-b",
+    service_c = "service-c",
+    service_d = "service-d",
+    service_e = "service-e",
+    service_f = "service-f",
+  }
 }
 
 resource "aws_sqs_queue" "incoming" {
-  count = length(local.services)
+  for_each = local.services
 
-  name = "audit-service-incoming-${local.services[count.index]}"
+  name = "audit-service-incoming-${each.value}"
 }
```

This might feel a little silly in our contrived example, but makes more sense
when the input data is not just a simple string value. For example:

```terraform
locals {
  services = {
    service_a = {
      name            = "service-a",
      allowed_regions = ["eu-west-1", "eu-west-2"],
      account_id      = ["1111111111111"]
    }
    service_b = {
      name            = "service-b",
      allowed_regions = ["eu-west-1"],
      account_ids     = ["222222222222"]
    }
    service_c = {
      name            = "service-c",
      allowed_regions = ["eu-west-1"],
      account_ids     = ["333333333333", "444444444444"]
    }
    service_d = {
      name            = "service-d",
      allowed_regions = ["us-east-1"],
      account_ids     = ["555555555555"]
    }
    service_e = {
      name            = "service-e",
      allowed_regions = ["eu-west-1", "us-east-1"],
      account_ids     = ["666666666666"]
    }
    service_f = {
      name            = "service-f",
      allowed_regions = ["eu-west-1", "eu-west-2"],
      account_ids     = ["777777777777"]
    }
  }
}
```

### Conclusion

Using sets, lists or arrays of items when making many of the same resource
requires care when chooing the logical identifier. Aim for a plan or diff that
changes the absolute bare minimum, and consider that a lack of complaints or
alarms in lower environments does not guarantee success in later ones.

As the designer of Terraform modules or CDK constructs, we have to understand
how user input will affect the logical IDs and resource names that we choose.
