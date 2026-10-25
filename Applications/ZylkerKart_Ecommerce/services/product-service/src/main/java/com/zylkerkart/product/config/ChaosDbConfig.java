package com.zylkerkart.product.config;

import com.site24x7.labs.chaos.fault.resource.ResourceFaultInjector;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.sql.DataSource;

/**
 * Registers the app DataSource for the Chaos SDK's app-induced DB faults
 * (n_plus_one, full_table_scan, thundering_herd, unbounded_query, connection_leak).
 *
 * The SDK's Spring Boot starter is meant to do this itself, but in 1.2.0 its
 * JDBC proxy wraps the DataSource first and the registration step then skips
 * the proxied bean, so nothing is registered. Registering again once the SDK
 * is fixed is harmless.
 */
@Configuration
public class ChaosDbConfig {

    @Bean
    public ApplicationRunner chaosDbRegistration(ObjectProvider<ResourceFaultInjector> injector,
                                                 DataSource dataSource) {
        return args -> injector.ifAvailable(i -> i.registerDataSource(dataSource));
    }
}
