using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Site24x7.Chaos.Extensions;
using ZylkerKart.AuthService.Data;
using ZylkerKart.AuthService.Services;

var builder = WebApplication.CreateBuilder(args);

// ─── Database ───────────────────────────────────────────────
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
    ?? $"Server={Environment.GetEnvironmentVariable("DB_HOST") ?? "mysql"};" +
       $"Port={Environment.GetEnvironmentVariable("DB_PORT") ?? "3306"};" +
       $"Database={Environment.GetEnvironmentVariable("DB_NAME") ?? "db_auth"};" +
       $"User={Environment.GetEnvironmentVariable("DB_USER") ?? "root"};" +
       $"Password={Environment.GetEnvironmentVariable("DB_PASSWORD") ?? "ZylkerKart@2024"}";

builder.Services.AddDbContext<AuthDbContext>(options =>
    options.UseMySql(connectionString, new MySqlServerVersion(new Version(8, 0, 0))));

// ─── JWT Authentication ─────────────────────────────────────
var jwtSecret = Environment.GetEnvironmentVariable("JWT_SECRET") ?? "ZylkerKart_JWT_S3cret_K3y_2026_Pr0duction";
var key = Encoding.UTF8.GetBytes(jwtSecret);

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(key),
            ValidateIssuer = true,
            ValidIssuer = "ZylkerKart",
            ValidateAudience = true,
            ValidAudience = "ZylkerKart",
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        };
    });

// ─── Services ───────────────────────────────────────────────
builder.Services.AddScoped<IAuthService, AuthServiceImpl>();
builder.Services.AddScoped<IJwtService, JwtService>();

builder.Services.AddControllers();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

builder.Services.AddEndpointsApiExplorer();

// ─── Chaos SDK ──────────────────────────────────────────────
var chaosEnabled = Environment.GetEnvironmentVariable("CHAOS_SDK_ENABLED")?.ToLower() != "false";
if (chaosEnabled)
{
    try
    {
        builder.Services.AddSite24x7Chaos(options =>
        {
            options.AppName = Environment.GetEnvironmentVariable("CHAOS_SDK_APP_NAME") ?? "auth-service";
            options.ConfigDir = Environment.GetEnvironmentVariable("CHAOS_SDK_CONFIG_DIR") ?? "/var/site24x7-labs/faults";
            options.Enabled = true;
        });
        Console.WriteLine("Chaos SDK registered");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Failed to register Chaos SDK: {ex.Message}");
    }
}

var app = builder.Build();

// Retry DB connection
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
    for (int i = 0; i < 30; i++)
    {
        try
        {
            db.Database.CanConnect();
            Console.WriteLine($"Connected to MySQL ({Environment.GetEnvironmentVariable("DB_HOST") ?? "mysql"})");
            break;
        }
        catch
        {
            Console.WriteLine($"Waiting for MySQL... attempt {i + 1}/30");
            Thread.Sleep(2000);
        }
    }
}

app.UseCors();

// Site24x7 Labs Chaos SDK middleware (before auth so faults can intercept early)
if (chaosEnabled)
{
    try
    {
        app.UseSite24x7Chaos();
        Console.WriteLine("Chaos SDK middleware enabled");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Failed to enable Chaos SDK middleware: {ex.Message}");
    }
}

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

var port = Environment.GetEnvironmentVariable("PORT") ?? "8085";
Console.WriteLine($"🔐 Auth Service running on port {port}");

app.Run($"http://0.0.0.0:{port}");
