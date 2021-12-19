#!/usr/bin/env bash
VERSION=001
LOG_FILE=/data/patch.log
NODE_ENV_FILE=/opt/app/bin/app.env
BACK_FOLDER=/data/patch_back
PATCH_FOLDER=/data/patch${VERSION}
CONFD_PATH=/opt/qingcloud/app-agent/bin

set -eo pipefail

source $NODE_ENV_FILE

log() {
  echo "$1" >> $LOG_FILE
}

apply() {
  log "backup"
  mkdir -p $BACK_FOLDER
  local tmp
  if [ $MY_ROLE = "logstash" ]; then
    tmp="logstash"
  else
    tmp="elasticsearch"
  fi
  if [ ! -f $BACK_FOLDER/$tmp-make.sh.tmpl ]; then
    cp /etc/confd/templates/make.sh.tmpl $BACK_FOLDER/$tmp-make.sh.tmpl
  fi
  if [ $MY_ROLE = "logstash" ]; then
    if [ ! -f $BACK_FOLDER/log4j-core-2.9.1.jar ]; then
      cp /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar $BACK_FOLDER
    fi
  fi

  log "replace"
  cp -f $PATCH_FOLDER/etc/confd/templates/$tmp-make.sh.tmpl /etc/confd/templates/make.sh.tmpl
  if [ $MY_ROLE = "logstash" ]; then
    cp -f $PATCH_FOLDER/usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar
    chown logstash:svc /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar
  fi

  $CONFD_PATH/confd --onetime
  log "done"
}

rollback() {
  log "restore"
  local tmp
  if [ $MY_ROLE = "logstash" ]; then
    tmp="logstash"
  else
    tmp="elasticsearch"
  fi
  cp -f $BACK_FOLDER/$tmp-make.sh.tmpl /etc/confd/templates/make.sh.tmpl
  if [ $MY_ROLE = "logstash" ]; then
    cp -f $BACK_FOLDER/log4j-core-2.9.1.jar /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar
    chown logstash:svc /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar
  fi

  $CONFD_PATH/confd --onetime
  log "done"
}

info() {
  ls -l /etc/confd/templates/make.sh.tmpl
  cat /etc/confd/templates/make.sh.tmpl | grep log4j
  if [ $MY_ROLE = "logstash" ]; then
    if [ -f $BACK_FOLDER/log4j-core-2.9.1.jar ]; then
      echo "*****backup jar info*****"
      ls -l $BACK_FOLDER/log4j-core-2.9.1.jar
    fi
    echo "*****sys jar info*****"
    ls -l /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar
  fi
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