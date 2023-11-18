---
layout: post
title: "Running a GitHub Actions pipeline for every AWS account in an organization"
date: 2023-11-18 20:33:00 +0000
categories:
  - AWS
  - GitHub
  - Actions
  - CI
---

<img alt="A GitHub Actions pipeline showing nine accounts being deployed to" src="/assets/running-a-github-actions-pipeline-for-every-aws-account/preview.png" width="600"/>

If you're already deploying software with GitHub Actions, you might be
wondering if you could use the same mechanism to deploy infrastructure that's
standard across all accounts. AWS provides CloudFormation StackSets for this
use-case, but you may be using an alternative Infrastructure as Code (IaC)
tool, and want to keep consistency across all your projects.

Start by creating an action in the `.github/workflows` folder in your project.
We'll call ours `github-actions-deploy.yml`. We'll give our action a name, and
have it run for merge requests and merges to our default branch:

```yaml
name: 'Terraform'

on:
  push:
    branches:
      - main
  pull_request:
```

With that out the way, we'll add an environment variable for the organization
management account ID:

```yaml
env:
  ORGANIZATION_MANAGEMENT_ACCOUNT_ID: 123123123123
```

We'll be using Terraform as our IaC tool, and so we'll ensure only one instance
of the job can run at once:

```yaml
concurrency: terraform
```

The string `terraform` could be anything, but it fits for our use-case. Let's
start the main body of the GitHub Action with a `setup` job that will look up
all the account IDs in the AWS organization:

{% raw %}
```yaml
jobs:
  setup:
    name: 'setup'
    runs-on: ubuntu-22.04

    #
    # Use bash for more advanced shell features and to ensure consistency if we
    # change the base image at a later date.
    #
    defaults:
      run:
        shell: bash

    #
    # We'll be using OIDC-based authentication for AWS, so we need an ID token
    # to be made available in our job.
    #
    # See: https://github.com/aws-actions/configure-aws-credentials
    #
    permissions:
      contents: read
      id-token: write

    #
    # Publish the "account_ids" output once it's been calculated below.
    #
    outputs:
      account_ids: ${{steps.list_accounts.outputs.account_ids}}

    steps:
      #
      # Download the latest code.
      #
      - name: Checkout
        uses: actions/checkout@v4

      #
      # We're using Terraform, so we need to install it.
      #
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.3

      #
      # Perform OIDC-based authentication in our AWS management account, using
      # a role called "github-actions".
      #
      - name: Authenticate with AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{env.ORGANIZATION_MANAGEMENT_ACCOUNT_ID}}:role/github-actions
          aws-region: eu-west-1
          mask-aws-account-id: false

      #
      # Find active accounts and share them as an environment variable.
      #
      - name: List accounts
        id: list_accounts
        run: |
          echo "account_ids="$(aws organizations list-accounts | jq '.Accounts | map(select(.Status == "ACTIVE")) | map(select(.Id != "${{env.ORGANIZATION_MANAGEMENT_ACCOUNT_ID}}")) | map(.Id)') >> "$GITHUB_OUTPUT"
```
{% endraw %}

To break the final step down further, we start by listing all AWS accounts:

```bash
aws organizations list-accounts
```

With that out the way, we use `jq` to find only active accounts, filter out the
organization management account, and then form a list of IDs.

{% raw %}
```
# Look in the Accounts key of the response from AWS
.Accounts |

# Filter to only active accounts
map(select(.Status == "ACTIVE")) |

# Filter out the management account
map(select(.Id != "${{env.ORGANIZATION_MANAGEMENT_ACCOUNT_ID}}")) |

# Turn it into a list of IDs
map(.Id)'
```
{% endraw %}

The output is a JSON array in this form:

```json
[
  "111111111111",
  "222222222222",
  "333333333333",
  "444444444444"
]
```

To create an environment variable for future steps or jobs to use, we create an
entry in the following form and then append it to a file that GitHub defines in
the `$GITHUB_OUTPUT` environment variable.

```
account_ids=...
```

The last step is the outputs that we've already run into above:

{% raw %}
```yaml
outputs:
  account_ids: ${{steps.list_accounts.outputs.account_ids}}
```
{% endraw %}

With the account IDs available, let's see how we can run a deployment job for
each account:

{% raw %}
```yaml
jobs:
  deploy:
    #
    # Create a relationship between these deployment jobs and the setup job to
    # ensure the account_ids variable is made available here.
    #
    needs: setup

    strategy:
      #
      # Don't quit all jobs if one account fails.
      #
      fail-fast: false

      #
      # Create a job for each account ID, and each AWS region that we're
      # interested in.
      #
      matrix:
        account_id: ${{fromJson(needs.setup.outputs.account_ids)}}
        region:
          - eu-west-1

    #
    # Define the rest of your deployment as usual.
    #
    steps:
      - name: Do the AWS stuff
```
{% endraw %}

You'll likely find that you need the account ID and region in your deployment
job. Here's an example of dynamically configuring a Terraform backend and
workspace based on the account and region we're deploying to:

{% raw %}
```yaml
jobs:
  deploy:
    steps:
      - name: Terraform init
        run: |
          terraform init \
            -backend-config="bucket=my-biz-landing-zone-${{env.ORGANIZATION_MANAGEMENT_ACCOUNT_ID}}-${{matrix.region}}-tf-state" \
            -backend-config="region=${{matrix.region}}"
          terraform workspace select -or-create ${{matrix.account_id}}
```
{% endraw %}

We could also use the Terraform convention for setting variables based on
environment variables:

{% raw %}
```yaml
- name: Terraform plan
  run: terraform plan -out plan
  env:
    TF_VAR_management_account_id: ${{env.ORGANIZATION_MANAGEMENT_ACCOUNT_ID}}
    TF_VAR_account_id: ${{matrix.account_id}}
    TF_VAR_region: ${{matrix.region}}
    TF_VAR_ref: ${{github.ref_name}}
```
{% endraw %}

## Conclusion

With the AWS CLI, and a bit of JSON wrangling, we can easily run an IaC tool
like Terraform against each AWS account in an organization. For the full GitHub
Action, check out [this gist].

[this gist]: https://gist.github.com/jSherz/4b87cee90d3f61dcb23ccca6ca4ca9aa

Happy shipping!
