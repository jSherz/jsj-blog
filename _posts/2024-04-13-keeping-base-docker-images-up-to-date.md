---
layout: post
title: "Keeping base and CI/CD Docker images up-to-date in AWS"
date: 2024-04-13 14:47:00 +0100
categories:
  - AWS
  - Docker
---

If you're building containerised services, or using a CI/CD system, you'll
likely end up building base images that contain the customisations that fit
your organisation's needs. For example, you might update OS packages, install a
newer version of a package manager, or install the CLI tool(s) of your chosen
cloud provider. Keeping these images up-to-date can become a maintenance
burden, especially if you want to keep several versions available for different
programming languages or runtimes.

Let's explore how we can automate this process.

In the [shersoft-ltd/evergreen-ci-and-base-images] repository, we'll start by
creating some Amazon Elastic Container Registry (ECR) repositories for our
images (modules/ecr-repository/main.tf):

```terraform
resource "aws_ecr_repository" "main" {
  name = var.name
}
```

We're going to be making lots of images each day, so let's also add in a
lifecycle policy that will clean up any draft images, and those that are
untagged:

```terraform
resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.id

  policy = jsonencode({
    "rules" : [
      {
        "rulePriority" : 1,
        "description" : "Retire draft images.",
        "selection" : {
          "tagStatus" : "tagged",
          "tagPrefixList" : [
            "draft"
          ],
          "countType" : "sinceImagePushed",
          "countUnit" : "days",
          "countNumber" : 1
        },
        "action" : {
          "type" : "expire"
        }
      },
      {
        "rulePriority" : 2,
        "description" : "Retire untagged images.",
        "selection" : {
          "tagStatus" : "untagged",
          "countType" : "sinceImagePushed",
          "countUnit" : "days",
          "countNumber" : 1
        },
        "action" : {
          "type" : "expire"
        }
      }
    ]
  })
}
```

With that in place, we'll setup the following file structure:

```
runtimes/node/Dockerfile
runtimes/node/self-test.js
runtimes/node/self-test.sh
runtimes/node-ci-cd/Dockerfile
runtimes/node-ci-cd/self-test.js
runtimes/node-ci-cd/self-test.sh
runtimes/python/Dockerfile
runtimes/python/self-test.py
runtimes/python/self-test.sh
```

Each runtime we're building images for will have a `Dockerfile` that defines
how to build the image, and a `self-test.sh` file that will be used to verify
that the built image works as we expect. Let's have a look at the Dockerfile
for the `node` runtime:

```Dockerfile
ARG RUNTIME
ARG VERSION

FROM node:${VERSION}

# Try and minimise active vulnerabilities by updating all OS packages
RUN apt-get update && \
    apt-get dist-upgrade --yes && \
    rm -rf /var/lib/apt/lists/*

COPY self-test.js /usr/local/bin/self-test.js
COPY self-test.sh /usr/local/bin/self-test
```

We'll support teams developing in multiple runtime versions by varying the base
image with the `VERSION` environment variable. For example, this could be `18`
or `20` for Node LTS versions. If we had to vary the setup greatly by version,
we could use if functions in the Dockerfile, or call different scripts or
different Dockerfiles based on versions.

The repo linked above ([shersoft-ltd/evergreen-ci-and-base-images]) contains a
full GitHub Workflow and CodePipeline / CodeBuild example. Let's have a look at
the GitHub version first. We'll define a workflow that is run for pull
requests, merges to the default branch and that also refreshes the images each
day:

```yaml
name: 'Build, verify and publish'

on:
  push:
    branches:
      - main
  pull_request:
  schedule:
    - cron: '25 6 * * *'
```

The first job will build the images and publish them with a `draft-*` tag. This
lets us try them out in later stages, and also pull them down locally if
required.

```yaml
jobs:
  build-images:
    runs-on: ubuntu-latest
    timeout-minutes: 5

    # We're going to authenticate with AWS, so we'll need an OIDC token
    permissions:
      contents: read
      id-token: write

    # Here's where we can define which runtime(s) and version(s) we're using
    strategy:
      matrix:
        image:
          - runtime: node
            version: 18
          - runtime: node
            version: 20
          - runtime: node-ci-cd
            version: 18
          - runtime: node-ci-cd
            version: 20
          - runtime: python
            version: 3.11
          - runtime: python
            version: 3.12
      fail-fast: false

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate with AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/github-actions
          aws-region: eu-west-1

      - name: Login to Amazon ECR
        id: login_to_ecr
        uses: aws-actions/amazon-ecr-login@v2

      # We build images for multiple platforms, and use QEMU for platforms
      # that we're not running on
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build, tag, and push draft image to Amazon ECR
        env:
          REGISTRY: ${{ steps.login_to_ecr.outputs.registry }}
          RUNTIME: ${{ matrix.image.runtime }}
          VERSION: ${{ matrix.image.version }}
        working-directory: runtimes/${{ matrix.image.runtime }}
        run: |
          docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --tag ${REGISTRY}/${RUNTIME}:draft-${VERSION}-${{ github.sha }} \
            --build-arg RUNTIME=${RUNTIME} \
            --build-arg VERSION=${VERSION} \
            --push \
            .
```

The next job will pull down the image we just built, and will run the self test
script that's defined in the `Dockerfile`. The self test script could do things
like:

* Ensure certain language or runtime features are available;

* Install a package to verify the package manager is working;

* Check the runtime version that's installed, and where it's installed;

* Check the package manager version that's installed, and where it's installed.

```yaml
  verify-images:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    needs:
      - build-images

    permissions:
      contents: read
      id-token: write

    strategy:
      matrix:
        image:
          - runtime: node
            version: 18
          - runtime: node
            version: 20
          - runtime: node-ci-cd
            version: 18
          - runtime: node-ci-cd
            version: 20
          - runtime: python
            version: 3.11
          - runtime: python
            version: 3.12
      fail-fast: false

    steps:
      - name: Authenticate with AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/github-actions
          aws-region: eu-west-1

      - name: Login to Amazon ECR
        id: login_to_ecr
        uses: aws-actions/amazon-ecr-login@v2

      # The 'setup-test' script is setup as a command in the `Dockerfile`
      - name: Run verification script
        env:
          REGISTRY: ${{ steps.login_to_ecr.outputs.registry }}
          RUNTIME: ${{ matrix.image.runtime }}
          VERSION: ${{ matrix.image.version }}
        run: docker run --entrypoint self-test ${REGISTRY}/${RUNTIME}:draft-${VERSION}-${{ github.sha }}
```

The final job then tags the image as the final version, and cleans up the
`draft-*` tag.

```yaml
  push-images:
    runs-on: ubuntu-latest
    timeout-minutes: 5

    needs:
      - verify-images

    permissions:
      contents: read
      id-token: write

    strategy:
      matrix:
        image:
          - runtime: node
            version: 18
          - runtime: node
            version: 20
          - runtime: node-ci-cd
            version: 18
          - runtime: node-ci-cd
            version: 20
          - runtime: python
            version: 3.11
          - runtime: python
            version: 3.12
      fail-fast: false

    if: (github.event_name == 'push' && github.ref == 'refs/heads/main') || github.event_name == 'schedule'

    steps:
      - name: Authenticate with AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/github-actions
          aws-region: eu-west-1

      - name: Login to Amazon ECR
        id: login_to_ecr
        uses: aws-actions/amazon-ecr-login@v2

      # We can use this command to avoid pulling, tagging, and pushing the image
      - name: Publish Docker image without draft prefix
        env:
          REGISTRY: ${{ steps.login_to_ecr.outputs.registry }}
          RUNTIME: ${{ matrix.image.runtime }}
          VERSION: ${{ matrix.image.version }}
        run: docker buildx imagetools create --tag ${REGISTRY}/${RUNTIME}:${VERSION} ${REGISTRY}/${RUNTIME}:draft-${{ matrix.image.version }}-${{ github.sha }}

      # Now we use ECR's API via the AWS CLI to clean up the tag
      - name: Remove draft tag
        env:
          REGISTRY: ${{ steps.login_to_ecr.outputs.registry }}
          RUNTIME: ${{ matrix.image.runtime }}
          VERSION: ${{ matrix.image.version }}
        run: |
          aws ecr \
            batch-delete-image \
            --repository-name ${RUNTIME} \
            --image-ids imageTag=draft-${VERSION}-${{ github.sha }}
```

The CodeBuild version is considerably more involved, as we'll build each
platform (e.g. ARM / X86) as a separate job. This technique is adapted from the
AWS blog post [Creating multi-architecture Docker images to support 
Graviton2 using AWS CodeBuild and AWS CodePipeline].

[Creating multi-architecture Docker images to support Graviton2 using AWS CodeBuild and AWS CodePipeline]: https://aws.amazon.com/blogs/devops/creating-multi-architecture-docker-images-to-support-graviton2-using-aws-codebuild-and-aws-codepipeline/

Let's start with the build job:

```yaml
version: 0.2

batch:
  fast-fail: false
  build-graph:
    # This is very similar to the matrix we provided to GitHub Actions, even if
    # it's a bit more verbose. We define each of the runtime(s) and version(s)
    # to build.
    - identifier: node_18_arm
      env:
        type: ARM_CONTAINER
        image: aws/codebuild/amazonlinux2-aarch64-standard:3.0
        variables:
          RUNTIME: node
          VERSION: "18"
          ARCHITECTURE: arm
      ignore-failure: false

    - identifier: node_18_x86
      env:
        type: LINUX_CONTAINER
        variables:
          RUNTIME: node
          VERSION: "18"
          ARCHITECTURE: x86
      ignore-failure: false

    - identifier: node_20_arm
      env:
        type: ARM_CONTAINER
        image: aws/codebuild/amazonlinux2-aarch64-standard:3.0
        variables:
          RUNTIME: node
          VERSION: "20"
          ARCHITECTURE: arm
      ignore-failure: false

    - identifier: node_20_x86
      env:
        type: LINUX_CONTAINER
        variables:
          RUNTIME: node
          VERSION: "20"
          ARCHITECTURE: x86
      ignore-failure: false

    - identifier: node_ci_cd_18_arm
      env:
        type: ARM_CONTAINER
        image: aws/codebuild/amazonlinux2-aarch64-standard:3.0
        variables:
          RUNTIME: node-ci-cd
          VERSION: "18"
          ARCHITECTURE: arm
      ignore-failure: false

    - identifier: node_ci_cd_18_x86
      env:
        type: LINUX_CONTAINER
        variables:
          RUNTIME: node-ci-cd
          VERSION: "18"
          ARCHITECTURE: x86
      ignore-failure: false

    - identifier: node_ci_cd_20_arm
      env:
        type: ARM_CONTAINER
        image: aws/codebuild/amazonlinux2-aarch64-standard:3.0
        variables:
          RUNTIME: node-ci-cd
          VERSION: "20"
          ARCHITECTURE: arm
      ignore-failure: false

    - identifier: node_ci_cd_20_x86
      env:
        type: LINUX_CONTAINER
        variables:
          RUNTIME: node-ci-cd
          VERSION: "20"
          ARCHITECTURE: x86
      ignore-failure: false

    - identifier: python_3_11_arm
      env:
        type: ARM_CONTAINER
        image: aws/codebuild/amazonlinux2-aarch64-standard:3.0
        variables:
          RUNTIME: python
          VERSION: "3.11"
          ARCHITECTURE: arm
      ignore-failure: false

    - identifier: python_3_11_x86
      env:
        type: LINUX_CONTAINER
        variables:
          RUNTIME: python
          VERSION: "3.11"
          ARCHITECTURE: x86
      ignore-failure: false

    - identifier: python_3_12_arm
      env:
        type: ARM_CONTAINER
        image: aws/codebuild/amazonlinux2-aarch64-standard:3.0
        variables:
          RUNTIME: python
          VERSION: "3.12"
          ARCHITECTURE: arm
      ignore-failure: false

    - identifier: python_3_12_x86
      env:
        type: LINUX_CONTAINER
        variables:
          RUNTIME: python
          VERSION: "3.12"
          ARCHITECTURE: x86
      ignore-failure: false

phases:
  pre_build:
    commands:
      - echo Login in to Amazon ECR
      - aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $REGISTRY

  build:
    commands:
      - echo Check Docker version
      - docker version

      - echo Move into correct directory
      - cd runtimes/$RUNTIME

      - echo Build, tag, and push draft image to Amazon ECR
      - docker buildx build --tag ${REGISTRY}/${RUNTIME}:draft-${VERSION}-${ARCHITECTURE}-${CODEBUILD_RESOLVED_SOURCE_VERSION} --build-arg RUNTIME=${RUNTIME} --build-arg VERSION=${VERSION} --push .
```

Once built, we can verify each image. I've removed the batch configuration to
keep this example shorter:

```yaml
version: 0.2

batch:
  fast-fail: false
  # ... snipped - see GitHub repo ...

phases:
  pre_build:
    commands:
      - echo Login in to Amazon ECR
      - aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $REGISTRY

  build:
    commands:
      - echo Test built image
      - docker run --entrypoint self-test ${REGISTRY}/${RUNTIME}:draft-${VERSION}-${ARCHITECTURE}-${CODEBUILD_RESOLVED_SOURCE_VERSION}
```

Finally, we can push the published versions and clean up the draft tags. We
don't have to repeat this for each architecture, so the batch configuration is
slightly less involved.

```yaml
version: 0.2

batch:
  fast-fail: false
  build-graph:
    - identifier: node_18
      env:
        variables:
          RUNTIME: node
          VERSION: "18"
      ignore-failure: false

    - identifier: node_20
      env:
        variables:
          RUNTIME: node
          VERSION: "20"
      ignore-failure: false

    - identifier: node_ci_cd_18
      env:
        variables:
          RUNTIME: node-ci-cd
          VERSION: "18"
      ignore-failure: false

    - identifier: node_ci_cd_20
      env:
        variables:
          RUNTIME: node-ci-cd
          VERSION: "20"
      ignore-failure: false

    - identifier: python_3_11
      env:
        variables:
          RUNTIME: python
          VERSION: "3.11"
      ignore-failure: false

    - identifier: python_3_12
      env:
        variables:
          RUNTIME: python
          VERSION: "3.12"
      ignore-failure: false

phases:
  pre_build:
    commands:
      - echo Login in to Amazon ECR
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY

  build:
    commands:
      - echo Publish ARM image
      - docker pull ${REGISTRY}/${RUNTIME}:draft-${VERSION}-arm-${CODEBUILD_RESOLVED_SOURCE_VERSION}
      - docker tag ${REGISTRY}/${RUNTIME}:draft-${VERSION}-arm-${CODEBUILD_RESOLVED_SOURCE_VERSION} ${REGISTRY}/${RUNTIME}:${VERSION}-arm
      - docker push ${REGISTRY}/${RUNTIME}:${VERSION}-arm

      - echo Publish X86 image
      - docker pull ${REGISTRY}/${RUNTIME}:draft-${VERSION}-x86-${CODEBUILD_RESOLVED_SOURCE_VERSION}
      - docker tag ${REGISTRY}/${RUNTIME}:draft-${VERSION}-x86-${CODEBUILD_RESOLVED_SOURCE_VERSION} ${REGISTRY}/${RUNTIME}:${VERSION}-x86
      - docker push ${REGISTRY}/${RUNTIME}:${VERSION}-x86

      - echo Create multi-arch image
      - docker manifest create ${REGISTRY}/${RUNTIME}:${VERSION} ${REGISTRY}/${RUNTIME}:${VERSION}-arm ${REGISTRY}/${RUNTIME}:${VERSION}-x86

      - echo Publish image
      - docker manifest push ${REGISTRY}/${RUNTIME}:${VERSION}

      - echo Delete draft tags
      - aws ecr batch-delete-image --repository-name ${RUNTIME} --image-ids imageTag=draft-${VERSION}-arm-${CODEBUILD_RESOLVED_SOURCE_VERSION} imageTag=draft-${VERSION}-x86-${CODEBUILD_RESOLVED_SOURCE_VERSION}
```

## Conclusion

With a little help from a CI/CD system, we can keep a set of Docker images that
fit our team's needs up-to-date and minimise the number of active
vulnerabilities in them. Our service image Dockerfiles can avoid some
repetition, as they'll know that the OS packages are already up-to-date and
ready to go.

Check out the GitHub repo ([shersoft-ltd/evergreen-ci-and-base-images]) to see
the full examples in GitHub Actions and CodePipeline/CodeBuild.

[shersoft-ltd/evergreen-ci-and-base-images]: https://github.com/shersoft-ltd/evergreen-ci-and-base-images
