package com.qingcloud.appcenter.elk;

import org.apache.http.HttpHost;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.client.RequestOptions;
import org.elasticsearch.client.RestClient;
import org.elasticsearch.client.RestHighLevelClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@SpringBootApplication
public class EsClient implements CommandLineRunner {
  private Logger logger = LoggerFactory.getLogger(getClass());

  public static void main(String[] args) {
    SpringApplication.run(EsClient.class, args).close();
  }

  @Override
  public void run(String... args) {
    try (RestHighLevelClient client = new RestHighLevelClient(RestClient.builder(
      new HttpHost("192.168.2.4", 9200, "http"),
      new HttpHost("192.168.2.50", 9200, "http"),
      new HttpHost("192.168.2.51", 9200, "http")
    ) )){
      Map<String, Object> data = new HashMap<>();
      data.put("name", "Jack");
      IndexRequest req = new IndexRequest("customers", "_doc", UUID.randomUUID().toString()).source(data);
      client.index(req, RequestOptions.DEFAULT);
    } catch (IOException e) {
      logger.error("Failed to index: ", e);
    }
  }
}

