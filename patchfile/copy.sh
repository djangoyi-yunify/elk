#!/usr/bin/env bash

CUR_PATH=$(cd $(dirname $BASH_SOURCE) && pwd)

es_copy() {
  # back
  mkdir -p $CUR_PATH/back
  if [ ! -f $CUR_PATH/back/elasticsearch.sh.tmpl ]; then
    cp /etc/confd/templates/elasticsearch.sh.tmpl $CUR_PATH/back
  fi
  cp -f $CUR_PATH/etc/confd/templates/elasticsearch.sh.tmpl /etc/confd/templates/elasticsearch.sh.tmpl
}

es_info() {
  ls -l /etc/confd/templates/elasticsearch.sh.tmpl
  cat /etc/confd/templates/elasticsearch.sh.tmpl | grep log4j
}

backupJar() {
  local from
  local folder
  local status
  local info=$(cat $CUR_PATH/back-copy.conf)
  for line in $(echo "$info"); do
    from=$(echo $line | cut -d':' -f1)
    folder=$(echo $line | cut -d':' -f2)
    status=$(echo $line | cut -d':' -f3)
    if [ $status = "yes" ]; then continue; fi
    if [ -n "$folder" ]; then
      mkdir -p $CUR_PATH/back/$folder
      cp -rf $from $CUR_PATH/back/$folder
    else
      cp -rf $from $CUR_PATH/back
    fi
    sed -i "s#$from:$folder:$status#$from:$folder:yes#g" $CUR_PATH/back-copy.conf
  done
}

replaceJar() {
  local target
  local oldpath
  local newpath
  local subinfo
  local status
  local tmp
  local info=$(cat $CUR_PATH/replace-copy.conf)
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
    cp -rf $CUR_PATH/replace/$tmp $target
    chown -R logstash $target
    sed -i "s#$target:$oldpath:$newpath:$subinfo:$status#$target:$oldpath:$newpath:$subinfo:yes#g" $CUR_PATH/replace-copy.conf
  done
}

lst_copy() {
  # back
  mkdir -p $CUR_PATH/back
  if [ ! -f $CUR_PATH/back/logstash.sh.tmpl ]; then
    cp /etc/confd/templates/logstash.sh.tmpl $CUR_PATH/back
  fi
  backupJar

  cp -f $CUR_PATH/etc/confd/templates/logstash.sh.tmpl /etc/confd/templates/logstash.sh.tmpl
  replaceJar
}

lst_info() {
  ls -l /etc/confd/templates/logstash.sh.tmpl
  cat /etc/confd/templates/logstash.sh.tmpl | grep log4j
  local target
  local oldpath
  local newpath
  local subinfo
  local status
  local tmp
  local info=$(cat $CUR_PATH/replace-copy.conf)
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