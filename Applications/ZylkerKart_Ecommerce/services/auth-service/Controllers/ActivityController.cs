using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using ZylkerKart.AuthService.Data;
using ZylkerKart.AuthService.DTOs;
using ZylkerKart.AuthService.Models;

namespace ZylkerKart.AuthService.Controllers;

[ApiController]
[Route("activity")]
public class ActivityController : ControllerBase
{
    private readonly AuthDbContext _db;

    public ActivityController(AuthDbContext db)
    {
        _db = db;
    }

    /// <summary>
    /// Log a user activity event (e.g. order_placed).
    /// Called internally by order-service after each successful order.
    /// </summary>
    [HttpPost("log")]
    public async Task<IActionResult> LogActivity([FromBody] ActivityLogRequest request)
    {
        try
        {
            var activity = new UserActivity
            {
                UserId     = request.UserId,
                OrderId    = request.OrderId,
                ActivityType = request.ActivityType,
                Metadata   = request.Metadata != null
                    ? JsonSerializer.Serialize(request.Metadata)
                    : null,
                CreatedAt  = DateTime.UtcNow
            };

            _db.UserActivities.Add(activity);
            await _db.SaveChangesAsync();

            return Ok(new { success = true, id = activity.Id });
        }
        catch (Exception ex)
        {
            // Log but don't expose internals
            Console.Error.WriteLine($"[Activity] Log error: {ex.Message}");
            return StatusCode(500, new { success = false, error = "Failed to log activity" });
        }
    }
}
