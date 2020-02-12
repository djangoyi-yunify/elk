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

upgrade() {
  true
}

request() {
  local reqFile=$1
  local action=$(head -1 $reqFile) body=$(tail -n +2 $reqFile)
  local method=${action% *} target=${action#* } result

  result=$(cat <<- REQ_EOF |
    $(echo $body)
REQ_EOF
  curl -s -m 10 -w "%{http_code}" -H 'Content-Type: application/json' -X$method $ES_VIP:9200/$target -d@-)
  [[ $result == *'"acknowledged":true'* ]] || [[ $result == *'"failures":[]'* ]] || {
    echo "Failed to execute [$method $target]: $result"
    local reqName=$(basename $reqFile)
    return ${reqName%.req}
  }
}

checkEsStatus() {
  curl -s -m 5 $ES_VIP:9200 | grep -q '"number" : "'$ELK_VERSION'",'
}

getIndexStatus() {
  curl -s -m 5 -o /dev/null -w '%{http_code}' $ES_VIP:9200/_cat/indices/$1
}

upgradeIndex() {
  [ "$APPCTL_UPGRADE_ENABLED" = "true" ] || return 0
  retry 60 1 0 checkEsStatus
  if [ "$(getIndexStatus .kibana)" = "200" ] && [ "$(getIndexStatus .kibana6)" = "404" ]; then
    for reqFile in $(ls /opt/app/conf/kibana/upgrade/*.req); do
      request $reqFile || {
        revertUpgradeIndex
        return 11
      }
    done
  fi
}

revertUpgradeIndex() {
  for reqFile in $(ls -r /opt/app/conf/kibana/upgrade/revert/*.req); do
    request $reqFile || true
  done
}
