package com.zylkerkart.storefront.config;

import java.util.concurrent.TimeUnit;

import nz.net.ultraq.thymeleaf.layoutdialect.LayoutDialect;
import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.core5.util.Timeout;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class WebConfig {

    @Bean
    public RestTemplate restTemplate() {
        // Apache HttpClient 5 instead of the default HttpURLConnection-based
        // SimpleClientHttpRequestFactory: the Site24x7 Java agent disables
        // distributed tracing for java.net.HttpURLConnection, so backing
        // RestTemplate with Apache HttpClient 5 keeps inter-service hops traced.
        ConnectionConfig connectionConfig = ConnectionConfig.custom()
                .setConnectTimeout(Timeout.of(3000, TimeUnit.MILLISECONDS))   // 3s connect
                .setSocketTimeout(Timeout.of(5000, TimeUnit.MILLISECONDS))    // 5s read
                .build();

        PoolingHttpClientConnectionManager connectionManager = new PoolingHttpClientConnectionManager();
        connectionManager.setDefaultConnectionConfig(connectionConfig);

        CloseableHttpClient httpClient = HttpClients.custom()
                .setConnectionManager(connectionManager)
                .build();

        return new RestTemplate(new HttpComponentsClientHttpRequestFactory(httpClient));
    }

    @Bean
    public LayoutDialect layoutDialect() {
        return new LayoutDialect();
    }
}
