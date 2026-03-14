package com.zylkerkart.storefront.config;

import nz.net.ultraq.thymeleaf.layoutdialect.LayoutDialect;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class WebConfig {

    @Bean
    public RestTemplate restTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5000);  // 5s connect
        factory.setReadTimeout(10000);    // 10s read
        return new RestTemplate(factory);
    }

    @Bean
    public LayoutDialect layoutDialect() {
        return new LayoutDialect();
    }
}
