#!/usr/bin/env bash

set -e

coreSvcNames="
kibana
caddy
nginx
"

extraSvcNames="
cerebro
elastichd
elasticsearch-head
elasticsearch-hq
elasticsearch-sql
"

isSvcDisabledByUser() {
  local varName=$(echo enable_${1//-/_} | tr [a-z] [A-Z])
  [ "${!varName}" = "false" ]
}

svcNames="$coreSvcNames"
for extraSvcName in $extraSvcNames; do
  isSvcDisabledByUser $extraSvcName || svcNames="$svcNames $extraSvcName"
done

toggleServiceStatus() {
  if isSvcDisabledByUser $1; then
    systemctl stop $1
    systemctl disable $1
  else
    systemctl enable $1
    systemctl start $1
  fi
}

update() {
  for svcName in $extraSvcNames; do
    toggleServiceStatus $svcName
  done
}
