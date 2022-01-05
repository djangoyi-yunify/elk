FROM dockerhub.qingcloud.com/qingcloud/elasticsearch:v1.2.6

COPY templates/*  /etc/confd/templates/

RUN rm -f /etc/confd/confd.toml

EXPOSE 9200 9300

ENTRYPOINT ["/opt/qingcloud/app-agent/bin/confd"]
