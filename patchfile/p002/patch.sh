#!/usr/bin/env bash
VERSION=002
LOG_FILE=/data/patch.log
BACK_FOLDER=/data/patch_back/${VERSION}
PATCH_FOLDER=/data/patch${VERSION}

set -eo pipefail

log() {
  echo "$1" >> $LOG_FILE
}

apply() {
  log "backup"
  mkdir -p $BACK_FOLDER
  if [ ! -f $BACK_FOLDER/elasticsearch.sh ]; then
    cp /opt/app/bin/node/elasticsearch.sh $BACK_FOLDER
  fi

  log "replace"
  cp -f $PATCH_FOLDER/elasticsearch.sh /opt/app/bin/node/elasticsearch.sh

  log "done"
}

rollback() {
  log "restore"
  cp -f $BACK_FOLDER/elasticsearch.sh /opt/app/bin/node/elasticsearch.sh
  log "done"
}