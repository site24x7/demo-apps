using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ZylkerKart.AuthService.Models;

[Table("users")]
public class User
{
    [Key]
    [Column("id")]
    public int Id { get; set; }

    [Required]
    [Column("email")]
    [MaxLength(255)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [Column("password_hash")]
    [MaxLength(255)]
    public string PasswordHash { get; set; } = string.Empty;

    [Required]
    [Column("full_name")]
    [MaxLength(255)]
    public string FullName { get; set; } = string.Empty;

    [Column("phone")]
    [MaxLength(20)]
    public string? Phone { get; set; }

    [Column("address")]
    public string? Address { get; set; }

    [Column("is_locked")]
    public bool IsLocked { get; set; }

    [Column("failed_attempts")]
    public int FailedAttempts { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [Column("updated_at")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

[Table("refresh_tokens")]
public class RefreshToken
{
    [Key]
    [Column("id")]
    public int Id { get; set; }

    [Column("user_id")]
    public int UserId { get; set; }

    [Required]
    [Column("token")]
    [MaxLength(512)]
    public string Token { get; set; } = string.Empty;

    [Column("expires_at")]
    public DateTime ExpiresAt { get; set; }

    [Column("is_revoked")]
    public bool IsRevoked { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [ForeignKey("UserId")]
    public User? User { get; set; }
}

[Table("user_activity")]
public class UserActivity
{
    [Key]
    [Column("id")]
    public int Id { get; set; }

    [Column("user_id")]
    public int UserId { get; set; }

    [Column("order_id")]
    public int? OrderId { get; set; }

    [Column("transaction_id")]
    public int? TransactionId { get; set; }

    [Required]
    [Column("activity_type")]
    [MaxLength(50)]
    public string ActivityType { get; set; } = string.Empty;

    [Column("metadata", TypeName = "json")]
    public string? Metadata { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
