---
layout: post
title: "Building an automatic backup verification pipeline: Elasticsearch edition"
date: 2019-06-09 10:22:00 +0100
categories:
 - Elasticsearch
 - snapshots
 - backup
 - CodeBuild
 - Docker
---

If you don't restore and verify your backups, you don't know that they'll
actually work when the time comes. Doing this manually is time consuming, easily
forgotten and a great candidate for being automated. I'm sure you can imagine
that we'd normally be talking about backups for a database or perhaps some
archived Elasticsearch indices, but even your local GitLab instance or Minecraft
server backups deserve some love. Once you've applied the pattern to one setup,
you can repeat the same blueprint over and over again, changing only the part
that performs the verification.

For our Elasticsearch example, we're going to make some assumptions about the
snapshots that we're taking and will use those assumptions to test the backups.
Namely, we're going to perform a very basic count of the number of documents in
each index that we restore and expect it to be over a threshold. This is an
extremely simplistic test that would be suited to log data, but requires
adaptation for nearly any other data set.

We'll use the Elasticsearch snapshot repository plugin for S3 to send our
backups straight into the processing ‘pipeline'. See the [ES docs] for setting
this up. Once the snapshot has been created and uploaded, we can configure the
S3 bucket to send a notification to a Lambda function. Although it would be
convenient to also have the Lambda function restore the backup and then verify
that it's OK, it's unlikely that we would have enough disk space, processing
power or time to perform those steps. There are a few options we might consider
for the compute part of this task, each with their own pros and cons:

[ES docs]: https://www.elastic.co/guide/en/elasticsearch/plugins/current/repository-s3.html

* **Spinning up an EC2 instance**

    We can do this fairly easily by baking an AMI that contains all of the
    required software (e.g. with [Packer]) and then using the user-data to tell
    the instance which backup it should target. We'd have to manage the
    lifecycle of the instance, making sure it gets terminated once the
    verification is complete, but that could easily be achieved if the instance
    is allowed to self destruct.

    One advantage of this method is that we can use a spot instance, even with a
    [blocked out reservation of time] to ensure the process completes. This
    might make it more cost effective if you're restoring many backups on a
    frequent basis and the wide range of instance types available also means we
    have great choice of the types of compute and storage we can use.

* **Lambda function**

    As discussed above, the runtime limit on Lambda functions and lack of disk
    space makes them unsuitable for this task.

* **ECS task (Fargate)**

    Fargate removes the need for us to have instances running and lets us use a
    Docker container for the restoration and verification. The downside is that
    it has a reasonably small amount of disk space (10GB, which has to include
    the OS and software) so isn't suitable for all but the smallest backups.

* **ECS task (EC2 instance backed)**

    If we have an existing ECS cluster with instances ready to go, we could use
    them to run the verification job. This may be desirable if you have a large
    ECS cluster that you'd like to re-use (e.g. if it contains lots of spot or
    reserved instances). The downsides are that it may be difficult to schedule
    the container if your ECS instances don't have much disk space or compute
    available and the delay if you have to scale up the ECS cluster to
    accommodate the restoration tasks.

* **CodeBuild**

    Another container based solution which doesn't require the manual
    provisioning of EC2 instances is CodeBuild. There are a few tiers of compute
    available and we get 64GB of disk space with the smallest tier or 128GB of
    space with the two larger tiers. Additionally, we can put the CodeBuild
    Docker daemon into privileged mode and launch new containers to run the
    service that we're restoring a backup for. This might be desirable if you're
    a Docker shop and have backups for a server that's a pain to manually
    install (e.g. if it's not available in your OS repos).

[Packer]: https://www.packer.io
[blocked out reservation of time]: https://aws.amazon.com/blogs/aws/new-ec2-spot-blocks-for-defined-duration-workloads/

The right solution for you really depends on what your team is geared up to work
with and if you have existing infrastructure you'd like to re-use. In this post,
we're going to use CodeBuild as it's an incredible convenient way to get the
containers we'll use to run Elasticsearch.

## A brief segue into ES snapshots

Once Elasticsearch has backed up the data to S3, we're going to use a Lambda
function to start the CodeBuild job. We'll configure a notification on the S3
bucket to trigger the Lambda, and that will rely on the ability to filter the
file names, and only look for the "snap-XXXXXX.dat" objects. These contain the
metadata for our snapshots, and will be used as an indication that a new
snapshot is ready to be processed. The Lambda function is incredible small and
is available in the [repo that accompanies this post].

Once we get the notification and our verification job is triggered, we can parse
out the snapshot UUID from the filename:

```python
snapshot_file = os.environ["SNAPSHOT_FILE"]
snapshot_uuid = snapshot_file[:-4].split("-")[1]

print("Notified for snapshot with UUID %s" % snapshot_uuid)
```

The Lambda function will provide the environment variable we're using to get the
snapshot file name. Once we know which snapshot we're looking for, we'll then
download the file in the snapshot repo that points to the latest repository
metadata:

```python
# Downloading snapshot index
latest_index = s3.get_object(
    Bucket=bucket,
    Key='index.latest'
)

latest_index_num = int(latest_index['Body'].read().hex(), 16)
index_path = 'index-%d' % latest_index_num

print("Using snapshot index %s" % index_path)
```

`index.latest` simply contains a number that we'll use to find the actual
metadata, which we'll download and parse as JSON:

```python
index_file = s3.get_object(
    Bucket=bucket,
    Key=index_path
)

metadata = json.loads(index_file['Body'].read())
```

The Elasticsearch API doesn't allow us to query information about the snapshots
with the UUID, so we now need to find the name of the snapshot:

```python
matches = list(filter(lambda s: s['uuid'] == snapshot_uuid, metadata['snapshots']))

if len(matches) == 0:
    raise Exception('Failed to find snapshot with UUID %s' % snapshot_uuid)

snapshot = matches[0]

print("Restoring snapshot %s" % snapshot['name'])
```

Once we have that, we can identify which indices the snapshot contains. We'll
use this later to verify each one contains valid data:

```python
snapshot_info = requests.get("%s/_snapshot/%s/%s" % (es_url, es_repo, snapshot["name"])).json()

indices = snapshot_info["snapshots"][0]["indices"]

print("Snapshot contains indices %s" % ", ".join(indices))
```

With the initial metadata checks out the way, it's time to restore the index and
then wait for the restoration job to complete.

## Restoring and verifying the backup

Although the above example is related to Elasticsearch, you can perform a
similar process with any other data store. Consider SQL Server. You might have a
maintenance task that stores `.bak` files on your local machine, a Scheduled
Task to upload the file to S3 and then trigger the Lambda. Instead of restoring
the backup as we'll do below, you could spin up an RDS instance and then query
that to ensure the backup works and contains the correct information.

When we call the ES API to restore the snapshot, we can choose to have it
immediately respond and acknowledge that the processing of restoring the data
has begun, or wait until the restoration has completed. Our HTTP client and the
target server would likely timeout for any sizeable amount of data, and so we'll
have it return immediately and then poll the API to see when it's finished:

```python
requests.post(
    '%s/_snapshot/%s/%s/_restore?wait_for_completion=false' % (es_url, es_repo, snapshot['name'])).json()


# Poll for status
def check_all_complete():
    print('Checking if all shards are recovered...')

    for index in indices:
        recovery_data = requests.get('%s/%s/_recovery' % (es_url, index)).json()

        if index in recovery_data and all(map(lambda shard: shard['stage'] == 'DONE', recovery_data[index]['shards'])):
            print('Index %s is complete' % index)
        else:
            print('Still waiting for index %s' % index)
            return False
    return True


while not check_all_complete():
    time.sleep(3)
```

You'll notice that the time between requests is minute (3 seconds) and thus
we'll be frequently calling the API when no change has occurred. Adjust this
value to suit your backup process. If if takes 5 minutes to restore your data,
try every 30 seconds. If it takes two hours to restore the backup, checking
every minute or five minutes won't hurt.

Once we've restored the backup, we then get to the final stage of determining if
the data is valid. The following example is an extremely basic check in which
we're looking for particular number of documents. A better verification process
would examine the data and check it has the fields we expect.

```python
for index in indices:
    count_query = requests.get('%s/%s/_count' % (es_url, index)).json()

    print('Index %s has %d documents' % (index, count_query['count']))

    if count_query['count'] <= 100000:
        # page engineers
        # cry
        # ???
        print('AAAAH %s IS MISSING DOCS :O :O :O' % index)
```

## What about the CodeBuild job?

I wanted to focus on the verification part of the process as I think that's the
most universal between any data store. All we're really aiming to do is start
the job, wait for it to complete (with retying) and then check the data.

There are many ways to achieve the following setup, but the CodeBuild job that
kicks off the verification process starts by launching Elasticsearch:

```bash
docker pull docker.elastic.co/elasticsearch/elasticsearch:7.1.1

docker run \
    --publish 9200:9200 \
    --rm \
    --env "discovery.type=single-node" \
    --detach \
    --name elasticsearch \
    docker.elastic.co/elasticsearch/elasticsearch:7.1.1
```

We then install the S3 repository plugin:

```bash
docker exec elasticsearch bin/elasticsearch-plugin install repository-s3 --batch
```

After that's ready, we need to authenticate the S3 snapshot repository against
AWS. In order to reuse the same authentication that our build job has, we can
query the container metadata API and pull out the relevant credentials. We'll
then store these in the Elasticsearch keystore:

```bash
curl "http://169.254.170.2"${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI} > creds

docker exec elasticsearch sh -c "echo \"$(cat creds | jq --raw-output .AccessKeyId)\" | bin/elasticsearch-keystore add --stdin s3.client.default.access_key"
docker exec elasticsearch sh -c "echo \"$(cat creds | jq --raw-output .SecretAccessKey)\" | bin/elasticsearch-keystore add --stdin s3.client.default.secret_key"
docker exec elasticsearch sh -c "echo \"$(cat creds | jq --raw-output .Token)\" | bin/elasticsearch-keystore add --stdin s3.client.default.session_token"

docker restart elasticsearch
```

Once Elasticsearch has been setup and is restarting, we'll repeatedly try to
connect to it until it's ready and available:

```bash
ES_READY=false
while [ $ES_READY != true ]
do
    curl http://localhost:9200 && ES_READY=true || echo Waiting for ES...
    sleep 1
done
```

Once reachable, we'll then create the snapshot repository itself and then kick
off the verification script:

```bash
cat << EOF > creds-json
{
    "type": "s3",
    "settings": {
        "bucket": "${SNAPSHOT_BUCKET}",
        "readonly": true
    }
}
EOF

curl \
    -H "Content-Type: application/json" \
    -XPUT \
    -d @creds-json \
    http://localhost:9200/_snapshot/${ES_REPO}

aws s3 cp s3://${SNAPSHOT_BUCKET}/verify.py verify.py
aws s3 cp s3://${SNAPSHOT_BUCKET}/requirements.txt requirements.txt
pip install -r requirements.txt
python verify.py
```

`verify.py` is the script that you've seen described above that restores the
snapshot and then counts the documents in each of the restored indices.

## Putting it all together

The infrastructure folder in the [repo that accompanies this post] has a Lambda
function, the verification script and the Terraform config required to set this
all up. It's a very basic example but illustrates the components that we need:

* Knowledge of how the backups for our data store are structured, and access to
  them.

* A trigger that's called when a backup is ready for testing.

* Some form of verification to check the data is OK, performed using the compute
  choice that's most applicable to us (e.g. a spot EC2 instance or CodeBuild
  job).

[repo that accompanies this post]: https://github.com/jSherz/backup-verification-pipeline

Hopefully this post provides some inspiration for you to start verifying your
backups automatically and ensure they work and contain the correct data. It can
be fiddly to get this kind of process going, but it's a great way to learn about
the data store(s) you use and also to ensure that the backups you're taking will
work if you ever need to rely on them.
