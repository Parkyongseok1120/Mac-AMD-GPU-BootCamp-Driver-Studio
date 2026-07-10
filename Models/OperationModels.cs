namespace AMD.BootCamp.WinUI.Models;

public sealed record DetectedGpu(string Name, string PnpDeviceId, string Status, uint ErrorCode);

public sealed record PackageAuditResult(
    DriverProfile Profile,
    string PackageRoot,
    IReadOnlyList<(string Path, string Sha256)> Files,
    bool IsValid,
    IReadOnlyDictionary<string, PackageSourceAuditResult>? AdditionalSources = null);

public sealed record PackageSourceAuditResult(
    PackageSourceDefinition Source,
    string PackageRoot,
    IReadOnlyList<(string Path, string Sha256)> Files);

public sealed record PrepareResult(string OutputRoot, string ManifestPath, string CertificateThumbprint);

public sealed class SecurityStatus
{
    public bool HardwarePresent { get; set; }
    public string GpuName { get; set; } = string.Empty;
    public string HardwareId { get; set; } = string.Empty;
    public uint ProblemCode { get; set; }
    public bool SecureBootEnabled { get; set; }
    public bool TestSigningConfigured { get; set; }
    public bool TestSigningActive { get; set; }
    public bool CertificateImported { get; set; }
    public string DriverVersion { get; set; } = string.Empty;
    public string DriverInf { get; set; } = string.Empty;
}

public sealed class InstallResultSnapshot
{
    public string ProfileId { get; set; } = string.Empty;
    public string PackageRoot { get; set; } = string.Empty;
    public string LogPath { get; set; } = string.Empty;
    public string BackupFolder { get; set; } = string.Empty;
    public bool Success { get; set; }
    public int ExitCode { get; set; }
    public string Message { get; set; } = string.Empty;
    public string Error { get; set; } = string.Empty;
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset CompletedAt { get; set; }
}

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);

public sealed record DownloadProgress(
    long BytesReceived,
    long? TotalBytes,
    double Percent,
    double BytesPerSecond,
    TimeSpan? EstimatedRemaining,
    bool IsVerifying = false);

public sealed record DriverDownloadResult(
    string Path,
    bool ReusedExisting,
    long Bytes,
    string Sha256);
