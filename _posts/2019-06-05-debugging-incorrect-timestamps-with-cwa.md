---
layout: post
title: "Debugging incorrect timestamps in the unified CloudWatch Agent"
date: 2019-06-05 18:21:00 +0100
categories:
 - AWS
 - CloudWatch
 - logs
---

Logs are unhelpful at best and thoroughly misleading if not stored with the
correct timestamp. A few seconds off is most likely good-enough, but if your log
shipping fails for a period of time or you're trying to make sense of the order
of a number of events that happen in quick succession, any inaccuracy is
incredibly frustrating.

The unified AWS CloudWatch Agent that replaces the old method of shipping logs
and metrics has a facility to read in a timestamp format and then parse your
logs against it to extract the exact time. If the format doesn't match the log
entry, it'll be uploaded with the current time, which may be a few seconds or
many days wrong. An example timestamp format pattern is shown below:

`/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
```json
{
    "logs": {
        "force_flush_interval": 5,
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/traefik/traefik.log",
                        "log_group_name": "/services/load-balancer/var/log/traefik/traefik.log",
                        "log_stream_name": "{instance_id}",
                        "timestamp_format": "time=\"%Y-%m-%dT%H-%M-%SZ\"",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
```

The `timestamp_format` values are specified in the [AWS documentation] but can
be hard to get just right. We can ease the pain slightly by observing that the
CloudWatch Agent is converting our JSON configuration into toml:

```
2019/06/05 17:16:50 I! Detected the host is EC2
Valid Json input schema.
No csm configuration found.
No metric configuration found.
Configuration validation first phase succeeded

2019/06/05 17:16:50 I! Config has been translated into TOML /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.toml
```

If we open up this toml file, we get a parsed version of our timestamp pattern
that's a regular expression:

```
[[inputs.tail.file_config]]
  file_path = "/var/log/traefik/traefik.log"
  from_beginning = true
  log_group_name = "/services/load-balancer/var/log/traefik/traefik.log"
  log_stream_name = "i-0d4db1f64e660665f"
  pipe = false
  timestamp_layout = "time=\"2006-01-02T15-04-05Z\""
  timestamp_regex = "(time=\"\\d{4}-\\d{2}-\\d{2}T\\d{2}-\\d{2}-\\d{2}Z\")"
  timezone = "UTC"
```

From there, we can either test out the regex in a tool like [rubular] or see the
layout with an example data to understand where we've gone wrong. In my example,
I'd put dashes in the time portion of the timestamp rather than colons. Oops!

Happy bug hunting!

[AWS documentation]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html
[rubular]: https://rubular.com/r/2hYXmtXMwTYMyP
