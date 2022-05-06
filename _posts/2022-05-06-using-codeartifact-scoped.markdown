---
layout: post
title: "Using AWS CodeArtifact to host just your private NPM packages"
date: 2022-05-06 21:30:00 +0100
categories:
  - AWS
  - NPM
  - NodeJS
  - CodeArtifact
---

It's always frustrated me that [NPM]'s organisation / teams support doesn't
include the facility to have an automation token that's **not** tied to a user.
As the person whose token always seems to end up shared across a plethora of CI
pipelines, I was really excited to see AWS [CodeArtifact] launch with support
for publishing NPM packages. We can have the best of both worlds (NPM's egress
pricing and AWS' permissions) by scoping NPM or Yarn to only use a CodeArtifact
for a specific namespace.

For example, we can create a CodeArtifact domain and repository with Terraform:

```terraform
resource "aws_codeartifact_domain" "main" {
  domain = "jsherz-com"
}

resource "aws_codeartifact_repository" "main" {
  domain     = aws_codeartifact_domain.main.domain
  repository = "npm"
}
```

Then we can authenticate with CodeArtifact, only for packages in `@jsherz-com`:

```
aws codeartifact login \
    --tool npm \
    --repository npm \
    --domain jsherz-com \
    --domain-owner 123456789012 \
    --namespace @jsherz-com
```

When we use NPM as follows, it will speak to CodeArtifact:

```
npm install @jsherz-com/lovely-eslint-config
```

For everything else, it goes to the public registry with no AWS involvement /
egress:

```
npm install eslint
```

[NPM]: https://npmjs.com
[CodeArtifact]: https://docs.aws.amazon.com/codeartifact
