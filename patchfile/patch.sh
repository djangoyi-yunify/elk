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
    if [ ! -f $BACK_FOLDER/log4j-core-2.13.3.jar ]; then
      cp /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.13.3.jar $BACK_FOLDER
    fi
  fi

  log "replace"
  if [ $NODE_CTL = "elasticsearch" ]; then
    cp -f $PATCH_FOLDER/etc/confd/templates/elasticsearch.sh.tmpl /etc/confd/templates/elasticsearch.sh.tmpl
  else
    cp -f $PATCH_FOLDER/etc/confd/templates/logstash.sh.tmpl /etc/confd/templates/logstash.sh.tmpl
    cp -f $PATCH_FOLDER/usr/share/logstash/logstash-core/lib/jars/log4j-core-2.13.3.jar /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.13.3.jar
    chown logstash:svc /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.13.3.jar
  fi

  $CONFD_PATH/confd --onetime
  log "done"
}

rollback() {
  log "restore"
  if [ $NODE_CTL = "elasticsearch" ]; then
    cp -f $BACK_FOLDER/elasticsearch.sh.tmpl /etc/confd/templates/elasticsearch.sh.tmpl
  else
    cp -f $BACK_FOLDER/logstash.sh.tmpl /etc/confd/templates/logstash.sh.tmpl
    cp -f $BACK_FOLDER/log4j-core-2.13.3.jar /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.13.3.jar
    chown logstash:svc /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.13.3.jar
  fi

  $CONFD_PATH/confd --onetime
  log "done"
}

info() {
  if [ $NODE_CTL = "elasticsearch" ]; then
    ls -l /etc/confd/templates/elasticsearch.sh.tmpl
    cat /etc/confd/templates/elasticsearch.sh.tmpl | grep log4j
  else
    ls -l /etc/confd/templates/logstash.sh.tmpl
    cat /etc/confd/templates/logstash.sh.tmpl | grep log4j
    if [ -f $BACK_FOLDER/log4j-core-2.13.3.jar ]; then
      echo "*****backup jar info*****"
      /usr/bin/jar -tf $BACK_FOLDER/log4j-core-2.13.3.jar | grep -i jndi
    fi
    echo "*****sys jar info*****"
    /usr/bin/jar -tf /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.13.3.jar | grep -i jndi
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