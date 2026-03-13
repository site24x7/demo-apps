using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using ZylkerKart.AuthService.Data;
using ZylkerKart.AuthService.DTOs;
using ZylkerKart.AuthService.Models;

namespace ZylkerKart.AuthService.Services;

public interface IAuthService
{
    Task<AuthResponse> Register(RegisterRequest request);
    Task<AuthResponse> Login(LoginRequest request, string? ipAddress, string? userAgent);
    Task<AuthResponse> RefreshToken(string refreshToken);
    Task<ValidateResponse> ValidateToken(string token);
    Task Logout(string refreshToken);
}

public class AuthServiceImpl : IAuthService
{
    private readonly AuthDbContext _db;
    private readonly IJwtService _jwt;
    private readonly int _refreshDays;

    public AuthServiceImpl(AuthDbContext db, IJwtService jwt)
    {
        _db = db;
        _jwt = jwt;
        _refreshDays = int.TryParse(
            Environment.GetEnvironmentVariable("JWT_REFRESH_EXPIRY_DAYS"), out var d) ? d : 7;
    }

    public async Task<AuthResponse> Register(RegisterRequest request)
    {
        // Check if email already exists
        if (await _db.Users.AnyAsync(u => u.Email == request.Email))
            throw new InvalidOperationException("Email already registered");

        var user = new User
        {
            Email = request.Email.ToLower().Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            FullName = request.FullName,
            Phone = request.Phone,
            Address = request.Address,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        _db.Users.Add(user);
        await _db.SaveChangesAsync();

        // Log activity
        _db.UserActivities.Add(new UserActivity
        {
            UserId = user.Id,
            ActivityType = "register",
            Metadata = JsonSerializer.Serialize(new { message = "New user registration" })
        });
        await _db.SaveChangesAsync();

        return await GenerateAuthResponse(user);
    }

    public async Task<AuthResponse> Login(LoginRequest request, string? ipAddress, string? userAgent)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == request.Email.ToLower().Trim());

        if (user == null)
        {
            throw new UnauthorizedAccessException("Invalid email or password");
        }

        // Check if account is locked
        if (user.IsLocked)
        {
            throw new UnauthorizedAccessException("Account is locked. Please contact support.");
        }

        // Verify password
        if (!BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
        {
            user.FailedAttempts++;
            if (user.FailedAttempts >= 5)
            {
                user.IsLocked = true;
                user.FailedAttempts = 0;
            }
            user.UpdatedAt = DateTime.UtcNow;

            _db.UserActivities.Add(new UserActivity
            {
                UserId = user.Id,
                ActivityType = "login",
                Metadata = JsonSerializer.Serialize(new
                {
                    success = false,
                    ip_address = ipAddress,
                    user_agent = userAgent,
                    message = $"Wrong password (attempts: {user.FailedAttempts})"
                })
            });
            await _db.SaveChangesAsync();

            throw new UnauthorizedAccessException("Invalid email or password");
        }

        // Reset failed attempts on successful login
        user.FailedAttempts = 0;
        user.UpdatedAt = DateTime.UtcNow;

        _db.UserActivities.Add(new UserActivity
        {
            UserId = user.Id,
            ActivityType = "login",
            Metadata = JsonSerializer.Serialize(new
            {
                success = true,
                ip_address = ipAddress,
                user_agent = userAgent
            })
        });
        await _db.SaveChangesAsync();

        return await GenerateAuthResponse(user);
    }

    public async Task<AuthResponse> RefreshToken(string refreshToken)
    {
        var storedToken = await _db.RefreshTokens
            .Include(t => t.User)
            .FirstOrDefaultAsync(t => t.Token == refreshToken && !t.IsRevoked);

        if (storedToken == null || storedToken.ExpiresAt < DateTime.UtcNow)
            throw new UnauthorizedAccessException("Invalid or expired refresh token");

        // Revoke old token
        storedToken.IsRevoked = true;
        await _db.SaveChangesAsync();

        return await GenerateAuthResponse(storedToken.User!);
    }

    public async Task<ValidateResponse> ValidateToken(string token)
    {
        var principal = _jwt.ValidateToken(token);
        if (principal == null)
            return new ValidateResponse { Valid = false, Message = "Invalid token" };

        var userIdClaim = principal.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)
            ?? principal.FindFirst("sub");
        if (userIdClaim == null || !int.TryParse(userIdClaim.Value, out var userId))
            return new ValidateResponse { Valid = false, Message = "Invalid token claims" };

        var user = await _db.Users.FindAsync(userId);
        if (user == null || user.IsLocked)
            return new ValidateResponse { Valid = false, Message = "User not found or locked" };

        return new ValidateResponse
        {
            Valid = true,
            User = new UserDto
            {
                Id = user.Id,
                Email = user.Email,
                FullName = user.FullName,
                Phone = user.Phone,
                Address = user.Address
            }
        };
    }

    public async Task Logout(string refreshToken)
    {
        var token = await _db.RefreshTokens.FirstOrDefaultAsync(t => t.Token == refreshToken);
        if (token != null)
        {
            token.IsRevoked = true;

            _db.UserActivities.Add(new UserActivity
            {
                UserId = token.UserId,
                ActivityType = "logout"
            });
            await _db.SaveChangesAsync();
        }
    }

    private async Task<AuthResponse> GenerateAuthResponse(User user)
    {
        var accessToken = _jwt.GenerateAccessToken(user);
        var refreshToken = _jwt.GenerateRefreshToken();

        // Save refresh token
        _db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            Token = refreshToken,
            ExpiresAt = DateTime.UtcNow.AddDays(_refreshDays),
            CreatedAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        return new AuthResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresIn = int.TryParse(
                Environment.GetEnvironmentVariable("JWT_EXPIRY_MINUTES"), out var m) ? m * 60 : 900,
            User = new UserDto
            {
                Id = user.Id,
                Email = user.Email,
                FullName = user.FullName,
                Phone = user.Phone,
                Address = user.Address
            }
        };
    }
}
