FROM ruby:2.6-slim

RUN mkdir -p /usr/src/blog && \
    apt-get update && \
    apt-get install build-essential --yes

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
