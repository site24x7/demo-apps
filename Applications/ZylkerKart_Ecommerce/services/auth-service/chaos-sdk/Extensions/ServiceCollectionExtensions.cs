// Site24x7 Labs Chaos SDK for .NET — DI Extensions
//
// Provides AddSite24x7Chaos() and UseSite24x7Chaos() for clean
// ASP.NET Core integration.
//
// Usage:
//   builder.Services.AddSite24x7Chaos(options => {
//       options.AppName = "order-service";
//   });
//   var app = builder.Build();
//   app.UseSite24x7Chaos();

using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Site24x7.Chaos.Fault;

namespace Site24x7.Chaos.Extensions;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Register the Chaos SDK services. Call this in <c>builder.Services</c>.
    /// </summary>
    /// <param name="services">The service collection.</param>
    /// <param name="configure">Action to configure <see cref="ChaosOptions"/>.</param>
    public static IServiceCollection AddSite24x7Chaos(
        this IServiceCollection services,
        Action<ChaosOptions> configure)
    {
        var options = new ChaosOptions();
        configure(options);

        // Detect framework version at startup
        if (string.IsNullOrEmpty(options.FrameworkVersion))
        {
            options.FrameworkVersion = Environment.Version.ToString();
        }

        // Create and register the SDK as a singleton (starts watcher + heartbeat)
        var sdk = new ChaosSDK(options);

        services.AddSingleton(sdk);
        services.AddSingleton(sdk.Engine);

        // Register the inbound HTTP fault middleware
        services.TryAddSingleton<HttpFaultMiddleware>();

        // Register the outbound HTTP client handler (DelegatingHandler is transient)
        services.AddTransient<ChaosHttpClientHandler>();

        return services;
    }

    /// <summary>
    /// Add the Chaos SDK inbound HTTP fault middleware to the pipeline.
    /// Call this early in <c>app.Use...</c> (before routing) to intercept requests.
    /// </summary>
    public static IApplicationBuilder UseSite24x7Chaos(this IApplicationBuilder app)
    {
        // Resolve the SDK to ensure it is started
        _ = app.ApplicationServices.GetRequiredService<ChaosSDK>();

        // Register the inbound HTTP fault middleware
        app.UseMiddleware<HttpFaultMiddleware>();

        return app;
    }

    /// <summary>
    /// Add the chaos HTTP client fault handler to an <see cref="IHttpClientBuilder"/>.
    /// </summary>
    /// <param name="builder">The HttpClient builder.</param>
    public static IHttpClientBuilder AddChaosHandler(this IHttpClientBuilder builder)
    {
        return builder.AddHttpMessageHandler<ChaosHttpClientHandler>();
    }
}
