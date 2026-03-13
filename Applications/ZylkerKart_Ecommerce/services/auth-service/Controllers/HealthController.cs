using Microsoft.AspNetCore.Mvc;

namespace ZylkerKart.AuthService.Controllers;

[ApiController]
public class HealthController : ControllerBase
{
    private readonly Data.AuthDbContext _db;

    public HealthController(Data.AuthDbContext db) => _db = db;

    [HttpGet("health")]
    public IActionResult Health()
    {
        var dbStatus = "UP";
        try
        {
            _db.Database.CanConnect();
        }
        catch
        {
            dbStatus = "DOWN";
        }

        var status = dbStatus == "UP" ? "UP" : "DEGRADED";
        var code = status == "UP" ? 200 : 503;

        return StatusCode(code, new
        {
            service = "auth-service",
            status,
            checks = new { mysql = new { status = dbStatus } }
        });
    }
}
