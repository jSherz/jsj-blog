#!/usr/bin/env bash

set -uexo pipefail

cd /usr/src/blog

bundle install --path vendor/bundle
bundle exec jekyll serve --host 0.0.0.0
