#!/usr/bin/env bash

# Default hook functions named starting with _, e.g. _init(), _start(), etc.
# Specific roles can override the default hooks like:
#   start() {
#     _start
#     ...
#   }
#
# Specific hooks will be executed if exist, otherwise the default ones.

for envFile in /opt/app/bin/*.env; do . $envFile; done

# Error codes
EC_CHECK_INACTIVE=200
EC_CHECK_PORT_ERR=201
EC_CHECK_PROTO_ERR=202

command=$1
args="${@:2}"

log() {
  logger -t appctl --id=$$ [cmd=$command] "$@"
}

retry() {
  local tried=0
  local maxAttempts=$1
  local interval=$2
  local stopCode=$3
  local cmd="${@:4}"
  local retCode=0
  while [ $tried -lt $maxAttempts ]; do
    $cmd && return 0 || {
      retCode=$?
      if [ "$retCode" = "$stopCode" ]; then
        log "'$cmd' returned with stop code $stopCode. Stopping ..." && return $retCode
      fi
    }
    sleep $interval
    tried=$((tried+1))
  done

  log "'$cmd' still returned errors after $tried attempts. Stopping ..." && return $retCode
}

execute() {
  local cmd=$1
  [ "$(type -t $cmd)" = "function" ] || cmd=_$cmd
  $cmd ${@:2}
}

getServices() {
  if [ "$1" = "-a" ]; then
    echo $SERVICES
  else
    echo $SERVICES | xargs -n1 | awk -F/ '$2=="true"'
  fi
}

isSvcEnabled() {
  [ "$(echo $(getServices -a) | xargs -n1 | awk -F/ '$1=="'$1'" {print $2}')" = "true" ]
}

checkActive() {
  systemctl is-active -q $1
}

checkEndpoint() {
  local host=$MY_IP proto=${1%:*} port=${1#*:}
  if [ "$proto" = "tcp" ]; then
    nc -z -w5 $host $port
  elif [ "$proto" = "udp" ]; then
    nc -z -u -q5 -w5 $host $port
  elif [ "$proto" = "http" ]; then
    local code="$(curl -s -o /dev/null -w "%{http_code}" $host:$port)"
    [[ "$code" =~ ^(200|302|401|403|404)$ ]]
  else
    return $EC_CHECK_PROTO_ERR
  fi
}

isInitialized() {
  local svcs="$(getServices -a)"
  [ "$(systemctl is-enabled ${svcs%%/*})" = "disabled" ]
}

initSvc() {
  systemctl unmask -q ${svc%%/*}
}

checkSvc() {
  checkActive ${svc%%/*} || {
    log "Service '$svc' is inactive."
    return $EC_CHECK_INACTIVE
  }
  local endpoints=$(echo $svc | awk -F/ '{print $3}')
  local endpoint; for endpoint in ${endpoints//,/ }; do
    checkEndpoint $endpoint || {
      log "Endpoint '$endpoint' is unreachable."
      return $EC_CHECK_PORT_ERR
    }
  done
}

startSvc() {
  systemctl start ${svc%%/*}
}

stopSvc() {
  systemctl stop ${svc%%/*}
}

restartSvc() {
  stopSvc $svc && startSvc $svc
}

### app management

_init() {
  mkdir -p /data/appctl/logs
  chown -R syslog.adm /data/appctl/logs

  rm -rf /data/lost+found

  local svc; for svc in $(getServices -a); do initSvc $svc; done
}

_revive() {
  local svc; for svc in $(getServices); do
    if [ "$1" == "--check-only" ]; then
      checkSvc $svc
    else
      checkSvc $svc || restartSvc $svc
    fi
  done
}

_check() {
  execute revive --check-only
}

_start() {
  isInitialized || {
    execute init
    systemctl restart rsyslog # output to log files under /data
  }

  local svc; for svc in $(getServices); do startSvc $svc; done
}

_stop() {
  local svc; for svc in $(getServices -a | xargs -n1 | tac); do stopSvc $svc; done
}

_restart() {
  local svc; for svc in $(getServices); do restartSvc $svc; done
}

_update() {
  if ! isInitialized; then return 0; fi # only update after initialized

  local svc; for svc in ${@:-${MY_ROLE%%-*}}; do
    stopSvc $svc
    if isSvcEnabled $svc; then startSvc $svc; fi
  done
}

. /opt/app/bin/role.sh

set -eo pipefail

execute $command $args
