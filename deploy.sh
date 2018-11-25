#!/usr/bin/env bash

set -euxo pipefail

bundle exec jekyll build

aws s3 sync \
    --delete \
    --metadata-directive REPLACE \
    --cache-control "max-age=86400" \
    _site/ s3://jsherz.com/

DISTRIBUTION_ID=$(aws cloudfront list-distributions | jq --raw-output '.DistributionList.Items | map(select((.Aliases.Quantity >= 1) and (.Aliases.Items | contains(["jsherz.com"])))) | .[0].Id')

aws cloudfront create-invalidation --distribution-id ${DISTRIBUTION_ID} --path '/*'
