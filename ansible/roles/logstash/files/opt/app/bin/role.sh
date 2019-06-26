svcNames="logstash caddy"
svcPorts="9600 80"

prepareDirs() {
  mkdir -p /data/elasticsearch/dicts /data/logstash/{config,data,dump,logs,plugins,queue}
  local lsTmplFile=/data/elasticsearch/dicts/logstash.json
  [ -e "$lsTmplFile" ] || cp /opt/app/conf/logstash/template.json $lsTmplFile

  chown -R logstash.svc /data/{elasticsearch,logstash}
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
  $LS_HOME/bin/logstash --path.settings $LS_SETTINGS_DIR -t
}

update() {
  true
}

upgrade() {
  timeout 6h appctl retry 1000 30 0 testConf || log "WARN: detected configuration failures and no human involved."
}
