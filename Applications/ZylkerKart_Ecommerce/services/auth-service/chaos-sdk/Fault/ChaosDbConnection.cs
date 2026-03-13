// Site24x7 Labs Chaos SDK for .NET — Database Fault Injector
//
// Wraps System.Data.Common.DbConnection to intercept database operations
// and inject 3 fault types:
//   1. jdbc_exception          — Throw a database error before the query.
//   2. jdbc_latency            — Delay before the query executes.
//   3. jdbc_connection_pool_drain — Hold connections to starve the pool.
//
// Usage:
//   var innerConn = new NpgsqlConnection(connectionString);
//   var chaosConn = new ChaosDbConnection(innerConn, engine);
//   await chaosConn.OpenAsync();

using System.Data;
using System.Data.Common;

namespace Site24x7.Chaos.Fault;

/// <summary>
/// <see cref="DbConnection"/> decorator that injects database faults
/// (exception, latency, connection pool drain) on each operation.
/// </summary>
public sealed class ChaosDbConnection : DbConnection
{
    private const string FaultPrefix = "jdbc_";
    private readonly DbConnection _inner;
    private readonly ChaosEngine _engine;

    public ChaosDbConnection(DbConnection inner, ChaosEngine engine)
    {
        _inner = inner ?? throw new ArgumentNullException(nameof(inner));
        _engine = engine ?? throw new ArgumentNullException(nameof(engine));
    }

    /// <summary>The wrapped inner connection.</summary>
    public DbConnection InnerConnection => _inner;

    // ------------------------------------------------------------------
    // DbConnection overrides
    // ------------------------------------------------------------------

    public override string ConnectionString
    {
        get => _inner.ConnectionString;
        set => _inner.ConnectionString = value;
    }

    public override string Database => _inner.Database;
    public override string DataSource => _inner.DataSource;
    public override string ServerVersion => _inner.ServerVersion;
    public override ConnectionState State => _inner.State;

    public override void Open()
    {
        EvaluatePoolDrain();
        EvaluateFaults();
        _inner.Open();
    }

    public override async Task OpenAsync(CancellationToken cancellationToken)
    {
        EvaluatePoolDrain();
        await EvaluateFaultsAsync(cancellationToken);
        await _inner.OpenAsync(cancellationToken);
    }

    public override void Close() => _inner.Close();

    public override void ChangeDatabase(string databaseName) => _inner.ChangeDatabase(databaseName);

    protected override DbTransaction BeginDbTransaction(IsolationLevel isolationLevel)
    {
        EvaluateFaults();
        return _inner.BeginTransaction(isolationLevel);
    }

    protected override DbCommand CreateDbCommand()
    {
        var cmd = _inner.CreateCommand();
        return new ChaosDbCommand(cmd, _engine);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _inner.Dispose();
        base.Dispose(disposing);
    }

    // ------------------------------------------------------------------
    // Fault evaluation
    // ------------------------------------------------------------------

    private void EvaluateFaults()
    {
        if (!_engine.Enabled) return;

        var rules = _engine.FindMatchingRules(FaultPrefix);
        foreach (var rule in rules)
        {
            if (!_engine.ShouldFire(rule)) continue;

            switch (rule.FaultType)
            {
                case FaultTypes.JdbcException:
                {
                    var javaClass = ConfigHelpers.GetString(rule, "exception_class", "java.sql.SQLException");
                    var message = ConfigHelpers.GetString(rule, "message", "Injected database fault");
                    var sqlState = ConfigHelpers.GetString(rule, "sql_state", "HY000");
                    Console.WriteLine($"[chaos-sdk] Injecting JDBC exception: {javaClass} - {message} (state: {sqlState})");
                    throw ExceptionMap.Resolve(javaClass, $"{message} [SQLSTATE: {sqlState}]");
                }

                case FaultTypes.JdbcLatency:
                {
                    var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 3000);
                    Console.WriteLine($"[chaos-sdk] Injecting JDBC latency: {delayMs}ms");
                    Thread.Sleep(delayMs);
                    return; // Continue after delay
                }
            }
        }
    }

    private async Task EvaluateFaultsAsync(CancellationToken ct)
    {
        if (!_engine.Enabled) return;

        var rules = _engine.FindMatchingRules(FaultPrefix);
        foreach (var rule in rules)
        {
            if (!_engine.ShouldFire(rule)) continue;

            switch (rule.FaultType)
            {
                case FaultTypes.JdbcException:
                {
                    var javaClass = ConfigHelpers.GetString(rule, "exception_class", "java.sql.SQLException");
                    var message = ConfigHelpers.GetString(rule, "message", "Injected database fault");
                    var sqlState = ConfigHelpers.GetString(rule, "sql_state", "HY000");
                    Console.WriteLine($"[chaos-sdk] Injecting JDBC exception: {javaClass} - {message} (state: {sqlState})");
                    throw ExceptionMap.Resolve(javaClass, $"{message} [SQLSTATE: {sqlState}]");
                }

                case FaultTypes.JdbcLatency:
                {
                    var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 3000);
                    Console.WriteLine($"[chaos-sdk] Injecting JDBC latency: {delayMs}ms");
                    await Task.Delay(delayMs, ct);
                    return;
                }
            }
        }
    }

    private void EvaluatePoolDrain()
    {
        if (!_engine.Enabled) return;

        var rules = _engine.FindMatchingRules(FaultPrefix);
        foreach (var rule in rules)
        {
            if (rule.FaultType != FaultTypes.JdbcConnectionPoolDrain) continue;
            if (!_engine.ShouldFire(rule)) continue;

            var holdDurationMs = ConfigHelpers.Clamp(
                ConfigHelpers.GetInt(rule, "hold_duration_ms", 5000), 1000, 60000);
            Console.WriteLine($"[chaos-sdk] Injecting JDBC connection pool drain: hold for {holdDurationMs}ms");
            Thread.Sleep(holdDurationMs);
            throw new InvalidOperationException("Connection pool exhausted (chaos fault)");
        }
    }
}

// ---------------------------------------------------------------------------
// Chaos DbCommand — injects faults on ExecuteReader / ExecuteNonQuery / etc.
// ---------------------------------------------------------------------------

internal sealed class ChaosDbCommand : DbCommand
{
    private readonly DbCommand _inner;
    private readonly ChaosEngine _engine;

    public ChaosDbCommand(DbCommand inner, ChaosEngine engine)
    {
        _inner = inner;
        _engine = engine;
    }

    public override string CommandText
    {
        get => _inner.CommandText;
        set => _inner.CommandText = value;
    }

    public override int CommandTimeout
    {
        get => _inner.CommandTimeout;
        set => _inner.CommandTimeout = value;
    }

    public override CommandType CommandType
    {
        get => _inner.CommandType;
        set => _inner.CommandType = value;
    }

    public override bool DesignTimeVisible
    {
        get => _inner.DesignTimeVisible;
        set => _inner.DesignTimeVisible = value;
    }

    public override UpdateRowSource UpdatedRowSource
    {
        get => _inner.UpdatedRowSource;
        set => _inner.UpdatedRowSource = value;
    }

    protected override DbConnection? DbConnection
    {
        get => _inner.Connection;
        set => _inner.Connection = value;
    }

    protected override DbParameterCollection DbParameterCollection => _inner.Parameters;

    protected override DbTransaction? DbTransaction
    {
        get => _inner.Transaction;
        set => _inner.Transaction = value;
    }

    public override void Cancel() => _inner.Cancel();

    public override int ExecuteNonQuery()
    {
        EvaluateFaults();
        return _inner.ExecuteNonQuery();
    }

    public override object? ExecuteScalar()
    {
        EvaluateFaults();
        return _inner.ExecuteScalar();
    }

    public override void Prepare() => _inner.Prepare();

    protected override DbParameter CreateDbParameter() => _inner.CreateParameter();

    protected override DbDataReader ExecuteDbDataReader(CommandBehavior behavior)
    {
        EvaluateFaults();
        return _inner.ExecuteReader(behavior);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _inner.Dispose();
        base.Dispose(disposing);
    }

    private void EvaluateFaults()
    {
        if (!_engine.Enabled) return;

        var rules = _engine.FindMatchingRules("jdbc_");
        foreach (var rule in rules)
        {
            if (!_engine.ShouldFire(rule)) continue;

            switch (rule.FaultType)
            {
                case FaultTypes.JdbcException:
                {
                    var javaClass = ConfigHelpers.GetString(rule, "exception_class", "java.sql.SQLException");
                    var message = ConfigHelpers.GetString(rule, "message", "Injected database fault");
                    Console.WriteLine($"[chaos-sdk] Injecting JDBC exception on command: {javaClass} - {message}");
                    throw ExceptionMap.Resolve(javaClass, message);
                }

                case FaultTypes.JdbcLatency:
                {
                    var delayMs = ConfigHelpers.GetInt(rule, "delay_ms", 3000);
                    Console.WriteLine($"[chaos-sdk] Injecting JDBC latency on command: {delayMs}ms");
                    Thread.Sleep(delayMs);
                    return;
                }
            }
        }
    }
}
