package com.zylkerbank.portal.config;

import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.core5.util.Timeout;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.concurrent.TimeUnit;

@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Bean
    @Primary
    public RestTemplate restTemplate() {
        return buildRestTemplate(3000, 5000, 100, 20);
    }

    @Bean(name = "aiRestTemplate")
    public RestTemplate aiRestTemplate() {
        return buildRestTemplate(3000, 30000, 20, 10);
    }

    private RestTemplate buildRestTemplate(long connectMs, long socketMs, int maxTotal, int maxPerRoute) {
        ConnectionConfig connectionConfig = ConnectionConfig.custom()
                .setConnectTimeout(Timeout.of(connectMs, TimeUnit.MILLISECONDS))
                .setSocketTimeout(Timeout.of(socketMs, TimeUnit.MILLISECONDS))
                .build();

        PoolingHttpClientConnectionManager connectionManager = new PoolingHttpClientConnectionManager();
        connectionManager.setMaxTotal(maxTotal);
        connectionManager.setDefaultMaxPerRoute(maxPerRoute);
        connectionManager.setDefaultConnectionConfig(connectionConfig);

        CloseableHttpClient httpClient = HttpClients.custom()
                .setConnectionManager(connectionManager)
                .build();

        HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory(httpClient);
        RestTemplate template = new RestTemplate(factory);
        template.getInterceptors().add(new TraceparentInterceptor());
        return template;
    }

    @Bean
    public AuthInterceptor authInterceptor() {
        return new AuthInterceptor();
    }

    @Bean
    public CsrfInterceptor csrfInterceptor() {
        return new CsrfInterceptor();
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        // CSRF runs across all application routes except static assets
        registry.addInterceptor(csrfInterceptor())
                .addPathPatterns("/**")
                .excludePathPatterns("/assets/**", "/assets1/**", "/favicon.ico");

        // Auth protects authenticated customer pages and APIs
        registry.addInterceptor(authInterceptor())
                .addPathPatterns(
                        "/dashboard",
                        "/account",
                        "/transfer/**",
                        "/receive/**",
                        "/cards/**",
                        "/transactions",
                        "/api/chat",
                        "/api/recipients/**"
                );
    }

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/assets/**")
                .addResourceLocations("classpath:/static/assets/")
                .setCachePeriod(0);
        registry.addResourceHandler("/assets1/**")
                .addResourceLocations("classpath:/static/assets1/")
                .setCachePeriod(0);
    }
}
