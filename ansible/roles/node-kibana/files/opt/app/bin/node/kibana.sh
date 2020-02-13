prepareDirs() {
  local svc; for svc in $(getServices -a); do
    local svcName=${svc%%/*}
    mkdir -p /data/$svcName/{data,logs}
    local svcUser=$svcName
    if [[ "$svcName" =~ ^haproxy|keepalived$ ]]; then svcUser=syslog; fi
    chown -R $svcUser.svc /data/$svcName
  done
}

initNode() {
  _initNode
  prepareDirs
  ln -sf /opt/app/conf/caddy/index.html /data/index.html
}

checkSvc() {
  _checkSvc $@ || return $?
  if [ "$1" == "kibana" ]; then checkEndpoint http:9200 $ES_VIP; fi
}
