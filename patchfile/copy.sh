#!/usr/bin/env bash

CUR_PATH=$(cd $(dirname $BASH_SOURCE) && pwd)

es_copy() {
  # back
  mkdir -p $CUR_PATH/back
  if [ ! -f $CUR_PATH/back/elasticsearch.sh.tmpl ]; then
    cp /etc/confd/templates/elasticsearch.sh.tmpl $CUR_PATH/back
  fi

  # copy
  cp -f $CUR_PATH/etc/confd/templates/elasticsearch.sh.tmpl /etc/confd/templates/elasticsearch.sh.tmpl
}

es_info() {
  ls -l /etc/confd/templates/elasticsearch.sh.tmpl
  cat /etc/confd/templates/elasticsearch.sh.tmpl | grep log4j
}

lst_copy() {
  # back
  mkdir -p $CUR_PATH/back
  if [ ! -f $CUR_PATH/back/logstash.sh.tmpl ]; then
    cp /etc/confd/templates/logstash.sh.tmpl $CUR_PATH/back
  fi
  if [ ! -f $CUR_PATH/back/log4j-core-2.9.1.jar ]; then
    cp /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar $CUR_PATH/back
  fi

  # copy
  cp -f $CUR_PATH/etc/confd/templates/logstash.sh.tmpl /etc/confd/templates/logstash.sh.tmpl
  cp -f $CUR_PATH/usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar
}

lst_info() {
  ls -l /etc/confd/templates/logstash.sh.tmpl
  cat /etc/confd/templates/logstash.sh.tmpl | grep log4j
  ls -l /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar
  if [ -f $CUR_PATH/back/log4j-core-2.9.1.jar ]; then
    echo "*****backup jar info*****"
    /usr/bin/jar -tf $CUR_PATH/back/log4j-core-2.9.1.jar | grep -i jndi
  fi
  echo "*****sys jar info*****"
  /usr/bin/jar -tf /usr/share/logstash/logstash-core/lib/jars/log4j-core-2.9.1.jar | grep -i jndi
}

target=$1
command=$2
if [ "$target" = "es" ]; then
  if [ "$command" = "copy" ]; then
    es_copy
  else
    es_info
  fi
elif [ "$target" = "lst" ]; then
  if [ "$command" = "copy" ]; then
    lst_copy
  else
    lst_info
  fi
else
  echo "copy.sh [ es | lst ] [ copy | info ]"
fi