#!/usr/bin/env bash

EC_NO_ES_NODES=20
EC_SCLIN_NO_HEALTH=21
EC_SCLIN_UNHEALTHY=22
EC_SCLIN_PORT_OPEN=23
EC_SCLIN_EXCIP_NOACK=120
EC_SCLIN_LACK_NODES=121 # Be careful to avoid overlap with cURL
EC_SCLIN_ERR_COUNTING=122 # the leaving nodes are still holding data
EC_SCLIN_HOLDING_DATA=123 # the leaving nodes are still holding data

svcNames="elasticsearch caddy"
svcPorts="9200 80"

prepareEsDir() {
  local esDir=${1:-elasticsearch}
  mkdir -p /data/$esDir/{dump,logs,repo}
  for dir in $(ls -d /data*); do
    rm -rf $dir/lost+found
    mkdir -p $dir/$esDir/data
    chown -R elasticsearch.svc /$dir/$esDir
  done
}

prepareCaddyDir() {
  mkdir -p /data/caddy/logs /data/elasticsearch/analysis
  chown -R caddy.svc /data/caddy /data/elasticsearch/analysis
  find /data/elasticsearch/analysis -type f -exec chmod +r {} \;
}

init() {
  _init
  prepareEsDir
  prepareCaddyDir
}

start() {
  cp /opt/app/conf/caddy/index.html /data/elasticsearch
  _start
}

restart() {
  if [ -z "$1" ]; then _restart && return 0; fi

  local earliest="$(($(date +%s%3N) - 5000))"
  if [ "$1" = "role" ]; then
    restartNodes "$ROLE_NODES" $earliest $IS_MASTER
  else
    if [[ "$1" =~ "master" ]]; then restartNodes "$MASTER_NODES" $earliest true; fi
    if [[ "$1" =~ "data" ]]; then restartNodes "$DATA_NODES" $earliest; fi
  fi
}

restartNodes() {
  local nodes="$1" earliest=$2 isMaster=${3:-false}
  local node; for node in $nodes; do
    if [ "$node" = "$MY_IP" ]; then
      _restart
      exit 0
    else
      retry 60 2 0 checkNodeRestarted $earliest $node || log "WARN: Node '$node' seems not restarted within 2 minutes."
      $isMaster || retry 600 2 0 checkNodeShardsLoaded $node || log "WARN: Node '$node' seems not loaded within 20 minutes."
    fi
  done
}

checkNodeRestarted() {
  local earliest=$1 node=${2:-$MY_IP} startTime
  startTime="$(curl -s -m 3 $node:9200/_nodes/$node/jvm | jq -r '.nodes | to_entries[] | .value | .jvm | .start_time_in_millis')"
  [ -n "$startTime" ] && [ $startTime -ge $earliest ]
}

checkNodeShardsLoaded() {
  local node=${1:-$MY_IP} shards
  shards="$(curl -s -m 3 $node:9200/_cat/shards?h=ip,state | awk 'BEGIN { count=0 } $1=="'$node'" && $2=="INITIALIZING" { count++ } END { print count }')"
  [ -n "$shards" ] && [ "$shards" -eq 0 ]
  shards="$(curl -s -m 3 $node:9200/_cluster/health | jq -r '.initializing_shards')"
  [ -n "$shards" ] && [ "$shards" -eq 0 ]
}

jsonHeader='Content-Type: application/json'
preScaleIn() {
  . /opt/app/bin/scaling.env
  [ -n "$LEAVING_DATA_NODES" ] && [ "$MY_IP" = "${STABLE_DATA_NODES%% *}" ] || return 0
  setExcludeIp "\"${LEAVING_DATA_NODES// /,}\""
  sleep 5 # give some time to start relocating.
  retry 8640 1 $EC_SCLIN_LACK_NODES checkClusterScaled 10 && retry 15 1 0 checkShardsMovedAway || {
    local retCode=$?
    log "Failed to relocate shards with exit code '$retCode'. Revert cluster settings."
    setExcludeIp null
    return $retCode
  }
}

scale() {
  local inout=${1:?in/out should be specified}
  . /opt/app/bin/scaling.env
  [ "$inout" = "in" -a -n "$LEAVING_DATA_NODES$LEAVING_MASTER_NODES" ] ||
    [ "$inout" = "out" -a -n "$JOINING_DATA_NODES$JOINING_MASTER_NODES" ] || return 0

  local rolling=master,data
  MASTER_NODES="$STABLE_MASTER_NODES" DATA_NODES="$STABLE_DATA_NODES" restart $rolling
}

destroy() {
  . /opt/app/bin/scaling.env

  # This is the 2nd step to remove a data node (shards are assumed to be already moved away in the 1st step).
  # Assumed stopping this node will not bring the cluster unhealthy because it has no data now.
  if [ -n "$LEAVING_DATA_NODES" ] && [[ "$LEAVING_DATA_NODES|$STABLE_DATA_NODES" =~ " " ]]; then
    execute stop
    retry 10 1 0 checkPortClosed
    checkClusterScaled 10 || {
      local retCode=$?
      log "Reverting scale-in as the cluster is not healthy or my shards were not relocated/assigned ..."
      execute start
      setExcludeIp null
      return $retCode
    }
  fi
}

setExcludeIp() {
  local ip=${1:-null} url resp ack
  url="${STABLE_DATA_NODES%% *}:9200/_cluster/settings"
  resp="$(curl -s -m 10 -H "$jsonHeader" -XPUT "$url" -d@- <<- SCALE_IN_EOF
    {
      "transient": {
        "cluster.routing.allocation.exclude._ip": $ip
      }
    }
SCALE_IN_EOF
  )"
  ack="$(echo $resp | jq -r '.acknowledged')"
  [ "$ack" = "true" ] || {
    log "Failed to exclude IP '$ip' with URL '$url': '$resp'."
    return $EC_SCLIN_EXCIP_NOACK
  }
}

checkClusterScaled() {
  local timeout=${1:-10}
  local fields="$(echo '
    .status
    .relocating_shards
    .unassigned_shards
  ' | xargs echo)"
  local url="${STABLE_DATA_NODES%% *}:9200/_cluster/health?timeout=$(( $timeout - 1 ))s" \
        health status relocating unassigned
  health="$(curl -s -m $timeout -H "$jsonHeader" "$url" | jq -r "${fields// /,}" | xargs echo)"
  [ -n "$health" ] || return $EC_SCLIN_NO_HEALTH
  status="$(echo $health | awk '{print $1}')"
  relocating="$(echo $health | awk '{print $2}')"
  unassigned="$(echo $health | awk '{print $3}')"

  if [[ "$status" =~ ^(red|yellow)$ ]] && [ "$relocating" -eq 0 ] && [ "$unassigned" -gt 0 ]; then
    log "Insufficient nodes to assign shards: '$health'."
    return $EC_SCLIN_LACK_NODES
  fi

  [ "$status" = "green" ] && [ "$relocating" -eq 0 ] && [ "$unassigned" -eq 0 ] || {
    log "Not fully scaled yet: '$health'."
    return $EC_SCLIN_UNHEALTHY
  }
}

checkShardsMovedAway() {
  local url="${STABLE_DATA_NODES%% *}:9200/_nodes/${LEAVING_DATA_NODES// /,}/stats/indices/docs"
  local expr='.nodes | to_entries | reduce .[] as $item (0; . + $item.value.indices.docs.count)'
  local docsCount
  docsCount=$(curl -s -m 3 "$url" | jq "$expr") || {
    log "Failed to sum up docs count on the leaving nodes '$LEAVING_DATA_NODES' from '$url': $docsCount."
    return $EC_SCLIN_ERR_COUNTING
  }

  [ "$docsCount" = "0" ] || {
    log "Still holding data on leaving nodes '$LEAVING_DATA_NODES': docs=$docsCount."
    return $EC_SCLIN_HOLDING_DATA
  }
}

checkPortClosed() {
  nc -z -w1 $MY_IP ${1:-9200} && return $EC_SCLIN_PORT_OPEN || return 0
}

checkEsOutput() {
  [ "$(curl -s -m 9 $MY_IP:9200 | jq -r '.version.number')" = "$ELK_VERSION" ]
}

check() {
  _check
  checkEsOutput
}

measure() {
  if [ "$MY_SID" != "$ES_SID_1" ]; then return 0; fi

  local stats health
  stats=$(curl -s -m 3 $MY_IP:9200/_cluster/stats | jq -c "{
    cluster_docs_count: .indices.docs.count,
    cluster_docs_deleted_count: .indices.docs.deleted,
    cluster_indices_count: .indices.count,
    cluster_jvm_heap_used_in_percent: (10000 * (.nodes.jvm.mem.heap_used_in_bytes / .nodes.jvm.mem.heap_max_in_bytes)),
    cluster_jvm_threads_count: .nodes.jvm.threads,
    cluster_shards_primaries_count: .indices.shards.primaries,
    cluster_shards_replication_count: (.indices.shards.total - .indices.shards.primaries),
    cluster_status: .status
  }")
  health=$(curl -s -m 2 $MY_IP:9200/_cluster/health | jq -c "{
    active_shards_percent_as_number: (100 * .active_shards_percent_as_number),
    initializing_shards,
    number_of_in_flight_fetch,
    number_of_nodes,
    number_of_pending_tasks,
    relocating_shards,
    task_max_waiting_in_queue_millis,
    unassigned_shards
  }")

  [ -n "$stats" -a -n "$health" ] && echo $stats $health | jq -s add
}

update() {
  # Big clusters need long time to fully load loaded. Disable auto restart and let user manually trigger.
  return 0
}

prepareDryrun() {
  prepareEsDir es-dryrun
  sudo -u elasticsearch rsync -a \
    --exclude='analysis/' \
    --exclude='data/nodes/0/indices/*/*/index' \
    --exclude='data/nodes/0/indices/*/*/translog' \
    --exclude='dump/' \
    --exclude='logs/' \
    /data/elasticsearch/ /data/es-dryrun/

  rm -rf /opt/app/conf/es-dryrun
  cp -r /opt/app/conf/elasticsearch /opt/app/conf/es-dryrun
  chown -R root.svc /opt/app/conf/es-dryrun
  sed -i "s#/data/elasticsearch#/data/es-dryrun#g; s#/opt/app/conf/elasticsearch#/opt/app/conf/es-dryrun#g" \
    /opt/app/conf/es-dryrun/.env /opt/app/conf/es-dryrun/elasticsearch.yml /opt/app/conf/es-dryrun/jvm.options

  sed -ri "s/^(path.repo:).*$/\1 []/g" /opt/app/conf/es-dryrun/elasticsearch.yml
}

upgrade() {
  execute init
  execute start
  . /opt/app/bin/upgrade.env
  retry 10 1 0 checkNodeJoined
  retry 3600 2 0 checkNodeShardsLoaded || log 'WARN: still loading data. Moving to upgrade next one.'
}

checkAllNodesUp() {
  if [ -z "$ES_NODES" ]; then return $EC_NO_ES_NODES; fi

  local esNodes=$(echo "$ES_NODES," | tr -cd , | wc -c)
  [ "$(curl -s -m 5 $MY_IP:9200/_cluster/health | jq -r '.number_of_nodes')" = "$esNodes" ]
}

checkNodeJoined() {
  local result node=${1:-$MY_IP}
  result="$(curl -s -m 3 $node:9200/_cat/nodes | awk '$1 == "'$node'" && $8 ~ /^m?di$/ {print $1}')"
  [ "$result" = "$MY_IP" ]
}

checkStatusNotRed() {
  local health stat init relo
  health="$(curl -s -m 3 $MY_IP:9200/_cluster/health | jq ".status, .initializing_shards, relocating_shards" | xagrs echo)"
  stat="$(echo $health | awk '{print $1}')"
  init="$(echo $health | awk '{print $2}')"
  relo="$(echo $health | awk '{print $3}')"
  [[ "$stat" =~ ^yellow|green$ ]] && [ "$init" -eq 0 ] && [ "$relo" -eq 0 ]
}

clearDump() {
  if [ -d "$HEAP_DUMP_PATH" ]; then
    rm -rf $HEAP_DUMP_PATH/*.hprof
  elif [ -f "$HEAP_DUMP_PATH" ]; then
    rm -rf $HEAP_DUMP_PATH
  fi
}
