coreSvcs="
haproxy:9200
keepalived
kibana:5601
caddy:80
"

extraSvcs="
cerebro:9000
elastichd:9800
elasticsearch-head:9100
elasticsearch-hq:5000
elasticsearch-sql:8080
"

isSvcDisabledByUser() {
  local varName=$(echo enable_${1//-/_} | tr [a-z] [A-Z])
  [ "${!varName}" = "false" ]
}

svcs="$coreSvcs"
for extraSvc in $extraSvcs; do
  isSvcDisabledByUser ${extraSvc%:*} || svcs="$svcs $extraSvc"
done

svcNames="$(echo $svcs | sed -r 's/:[0-9]+//g')"
svcPorts="$(echo $svcs | sed -r 's/[a-z-]+:?//g')"

prepareDirs() {
  for svc in $coreSvcs $extraSvcs; do
    local svcName=${svc%:*}
    mkdir -p /data/$svcName/{data,logs}
    local svcUser=$svcName
    [[ ! "$svcName" =~ ^haproxy|keepalived$ ]] || svcUser=syslog
    chown -R $svcUser.svc /data/$svcName
  done
}

init() {
  _init
  prepareDirs
  ln -sf /opt/app/conf/caddy/index.html /data/index.html
}

check() {
  _check
  nc -w3 -z $ES_VIP 9200
}

toggleServiceStatus() {
  local svcName=$1
  if isSvcDisabledByUser $svcName; then
    systemctl stop $svcName
    systemctl disable $svcName
  else
    systemctl enable $svcName
    systemctl start $svcName
  fi
}

update() {
  local svc
  for svc in $(echo $coreSvcs | sed -r 's/:[0-9]+//g'); do systemctl restart $svc; done
  for svc in $(echo $extraSvcs | sed -r 's/:[0-9]+//g'); do toggleServiceStatus $svc; done
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
