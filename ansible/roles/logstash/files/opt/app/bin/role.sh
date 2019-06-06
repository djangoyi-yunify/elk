#!/usr/bin/env bash

set -e

svcNames="logstash caddy"
svcPorts="9600 80"

prepareDirs() {
  local dataDir=/data/logstash esDir=/data/elasticsearch
  local cfgDir=$dataDir/config pluginsDir=$dataDir/plugins queueDir=$dataDir/queue
  mkdir -p /data/elasticsearch/dicts /data/logstash/{config,data,logs,plugins,queue}
  local lsTmplFile=/data/elasticsearch/dicts/logstash.json
  [ -f "$lsTmplFile" ] || cp /opt/app/conf/logstash/template.json $lsTmplFile

  chown -R logstash.svc /data/logstash

  mkdir -p /data/caddy/logs
  chown -R caddy.svc /data/{caddy,elasticsearch}
  find /data/elasticsearch/dicts -type f -exec chmod +r {} \;
  chown -R ubuntu.svc /data/logstash/{config,plugins}
}

init() {
  _init
  prepareDirs
  local htmlPath=/data/elasticsearch/index.html
  [ -e $htmlPath ] || ln -s /opt/app/conf/caddy/index.html $htmlPath
}

checkVersion() {
  curl -s -m 3 $MY_IP:9600 | grep -q '"version":"'$ELK_VERSION'"'
}

check() {
  _check
  checkVersion
}

testConf() {
  . /opt/app/conf/logstash/.env
  pushd /data/logstash
  $LS_HOME/bin/logstash --path.settings $LS_SETTINGS_DIR -t
  popd
}

update() {
  return 0
}

upgrade() {
  testConf
  execute init
}
