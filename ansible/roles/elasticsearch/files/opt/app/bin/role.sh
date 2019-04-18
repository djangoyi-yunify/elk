#!/usr/bin/env bash

set -e

svcNames="elasticsearch caddy"

postInit() {
  mkdir -p /data/elasticsearch/{data,logs,analysis} \
           /opt/app/conf/elasticsearch/scripts
  chown -R elasticsearch.svc /data \
           /opt/app/conf/elasticsearch/scripts

  mkdir -p /data/caddy/logs
  chown -R caddy.svc /data/caddy /data/elasticsearch/analysis
}

preStart() {
  sysctl -qw vm.max_map_count=262144
  sysctl -qw vm.swappiness=0
}

