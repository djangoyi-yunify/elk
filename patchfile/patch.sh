#!/usr/bin/env bash
VERSION=001
LOG_FILE=/data/patch.log
NODE_ENV_FILE=/opt/app/bin/envs/node.env
BACK_FOLDER=/data/patch_back
PATCH_FOLDER=/data/patch${VERSION}
CONFD_PATH=/opt/qingcloud/app-agent/bin

set -eo pipefail

source $NODE_ENV_FILE

log() {
  echo "$1" >> $LOG_FILE
}

backupJar() {
  local from
  local folder
  local status
  local info=$(cat $PATCH_FOLDER/back.conf)
  for line in $(echo "$info"); do
    from=$(echo $line | cut -d':' -f1)
    folder=$(echo $line | cut -d':' -f2)
    status=$(echo $line | cut -d':' -f3)
    if [ $status = "yes" ]; then continue; fi
    if [ -n "$folder" ]; then
      mkdir -p $BACK_FOLDER/$folder
      cp -rf $from $BACK_FOLDER/$folder
    else
      cp -rf $from $BACK_FOLDER
    fi
    sed -i "s#$from:$folder:$status#$from:$folder:yes#g" $PATCH_FOLDER/back.conf
  done
}

replaceJar() {
  local target
  local oldpath
  local newpath
  local subinfo
  local status
  local tmp
  local info=$(cat $PATCH_FOLDER/replace.conf)
  for line in $(echo "$info"); do
    target=$(echo $line | cut -d':' -f1)
    oldpath=$(echo $line | cut -d':' -f2)
    newpath=$(echo $line | cut -d':' -f3)
    subinfo=$(echo $line | cut -d':' -f4)
    status=$(echo $line | cut -d':' -f5)
    if [ $status = "yes" ]; then continue; fi
    tmp=${oldpath%%/*}
    rm -rf $target/$tmp
    if [ -z "$subinfo" ]; then
      tmp=$newpath
    fi
    cp -rf $PATCH_FOLDER/replace/$tmp $target
    chown -R logstash $target
    sed -i "s#$target:$oldpath:$newpath:$subinfo:$status#$target:$oldpath:$newpath:$subinfo:yes#g" $PATCH_FOLDER/replace.conf
  done
}

apply() {
  log "backup"
  mkdir -p $BACK_FOLDER
  if [ $NODE_CTL = "elasticsearch" ]; then
    if [ ! -f $BACK_FOLDER/elasticsearch.sh.tmpl ]; then
      cp /etc/confd/templates/elasticsearch.sh.tmpl $BACK_FOLDER
    fi
  else
    if [ ! -f $BACK_FOLDER/logstash.sh.tmpl ]; then
      cp /etc/confd/templates/logstash.sh.tmpl $BACK_FOLDER
    fi
    backupJar
  fi

  log "replace"
  if [ $NODE_CTL = "elasticsearch" ]; then
    cp -f $PATCH_FOLDER/etc/confd/templates/elasticsearch.sh.tmpl /etc/confd/templates/elasticsearch.sh.tmpl
  else
    cp -f $PATCH_FOLDER/etc/confd/templates/logstash.sh.tmpl /etc/confd/templates/logstash.sh.tmpl
    replaceJar
  fi

  $CONFD_PATH/confd --onetime
  if [ $NODE_CTL = "logstash" ]; then
    systemctl restart logstash.service || :
  fi
  log "done"
}

restoreJar() {
  local target
  local oldpath
  local newpath
  local subinfo
  local status
  local tmp
  local info=$(cat $PATCH_FOLDER/replace.conf)
  for line in $(echo "$info"); do
    target=$(echo $line | cut -d':' -f1)
    oldpath=$(echo $line | cut -d':' -f2)
    newpath=$(echo $line | cut -d':' -f3)
    subinfo=$(echo $line | cut -d':' -f4)
    status=$(echo $line | cut -d':' -f5)
    if [ $status = "no" ]; then continue; fi
    tmp=${newpath%%/*}
    rm -rf $target/$tmp
    if [ -n "$subinfo" ]; then
      tmp=$subinfo/$tmp
    else
      tmp=$oldpath
    fi
    cp -rf $BACK_FOLDER/$tmp $target
    chown -R logstash $target
    sed -i "s#$target:$oldpath:$newpath:$subinfo:$status#$target:$oldpath:$newpath:$subinfo:no#g" $PATCH_FOLDER/replace.conf
  done
}

rollback() {
  log "restore"
  if [ $NODE_CTL = "elasticsearch" ]; then
    cp -f $BACK_FOLDER/elasticsearch.sh.tmpl /etc/confd/templates/elasticsearch.sh.tmpl
  else
    cp -f $BACK_FOLDER/logstash.sh.tmpl /etc/confd/templates/logstash.sh.tmpl
    restoreJar
  fi
  $CONFD_PATH/confd --onetime
  if [ $NODE_CTL = "logstash" ]; then
    systemctl restart logstash.service || :
  fi
  log "done"
}

info() {
  local target
  local oldpath
  local newpath
  local subinfo
  local status
  local tmp
  local info=$(cat $PATCH_FOLDER/replace.conf)
  for line in $(echo "$info"); do
    target=$(echo $line | cut -d':' -f1)
    oldpath=$(echo $line | cut -d':' -f2)
    newpath=$(echo $line | cut -d':' -f3)
    subinfo=$(echo $line | cut -d':' -f4)
    status=$(echo $line | cut -d':' -f5)
    if [ "$status" = yes ]; then
      ls -l $target/$newpath
    else
      ls -l $target/$oldpath
    fi
  done
}

dev() {
  :
}

command=$1

if [ "$command" = "apply" ]; then
  apply
elif [ "$command" = "rollback" ]; then
  rollback
elif [ "$command" = "dev" ]; then
  dev
elif [ "$command" = "info" ]; then
  info
else
  echo 'usage: patch [ apply | rollback | info ]'
fi