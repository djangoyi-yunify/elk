#!/usr/bin/env bash

set -e

. /opt/app/bin/.env

# Error codes
EC_DEFAULT=1          # default
EC_RETRY_FAILED=2

command=$1
args="${@:2}"

log() {
  logger -t appctl --id=$$ [cmd=$command] "$@"
}

retry() {
  local tried=0
  local maxAttempts=$1
  local interval=$2
  local cmd="${@:3}"
  local retCode=$EC_RETRY_FAILED
  while [ $tried -lt $maxAttempts ]; do
    sleep $interval
    tried=$((tried+1))
    $cmd && return 0 || {
      retCode=$?
      log "'$cmd' ($tried/$maxAttempts) returned an error."
    }
  done

  log "'$cmd' still returned errors after $tried attempts. Stopping ..." && return $retCode
}

reverseSvcNames() {
  echo $svcNames | tr ' ' '\n' | tac | tr '\n' ' '
}

rolectl() {
  systemctl $@
}

svc() {
  for svcName in $svcNames; do
    systemctl $@ $svcName
  done
}

preInit() { :; }

postInit() { :; }

init() {
  preInit

  rm -rf /data/lost+found
  for svcName in $svcNames; do
    mkdir -p /data/$svcName/{data,logs}
    local svcUser=$svcName
    grep -qE "^$svcName:" /etc/passwd || svcUser=root
    chown -R $svcUser.svc /data/$svcName
  done

  svc enable

  postInit
}

check() {
  svc is-active -q
}

preStart() { :; }

postStart() { :; }

start() {
  preStart
  svc start
  postStart
}

preStop() { :; }

postStop() { :; }

stop() {
  preStop
  svcNames="$(reverseSvcNames)" svc stop
  postStop
}

restart() {
  stop && start
}

update() {
  svc is-enabled -q || return 0

  restart
}

. /opt/app/bin/role.sh

$command $args
