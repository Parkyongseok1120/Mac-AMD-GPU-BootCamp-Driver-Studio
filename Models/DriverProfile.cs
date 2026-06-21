using System.Text.Json;
using System.Text.Json.Serialization;

namespace AMD.BootCamp.WinUI.Models;

public sealed class DriverProfile
{
    public int SchemaVersion { get; set; } = 1;
    public string Id { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string MarketingVersion { get; set; } = string.Empty;
    public string PackageVersion { get; set; } = string.Empty;
    public string DriverVersion { get; set; } = string.Empty;
    public string InfName { get; set; } = string.Empty;
    public string KernelDriverPath { get; set; } = string.Empty;
    public string CatalogFile { get; set; } = string.Empty;
    public string CertificateSubject { get; set; } = "CN=Local AMD BootCamp Test Driver";
    public string OfficialPageUrl { get; set; } = string.Empty;
    public string InstallerUrl { get; set; } = string.Empty;
    public Dictionary<string, string> InstallerUrls { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public string InstallerFileName { get; set; } = string.Empty;
    public string InstallerSha256 { get; set; } = string.Empty;
    public long InstallerSize { get; set; }
    public List<string> PackageRootCandidates { get; set; } = ["."];
    public List<string> SupportedHardwareIds { get; set; } = [];
    public List<FileRule> Files { get; set; } = [];
    public List<PatchOperation> Patches { get; set; } = [];
    public List<RegistrySetting> RegistrySettings { get; set; } = [];

    [JsonIgnore]
    public string SourcePath { get; set; } = string.Empty;
    [JsonIgnore]
    public string DownloadActionText { get; set; } = "Download";
    [JsonIgnore]
    public string OfficialPageActionText { get; set; } = "Official page";
    [JsonIgnore]
    public string WindowsCompatibilityText { get; set; } = "Windows 10 / Windows 11 (64-bit)";

    [JsonIgnore]
    public static string CurrentWindowsKey => OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000)
        ? "windows11"
        : "windows10";

    [JsonIgnore]
    public static string CurrentWindowsDisplayName => CurrentWindowsKey == "windows11" ? "Windows 11" : "Windows 10";

    public string ResolveInstallerUrl()
    {
        if (InstallerUrls.TryGetValue(CurrentWindowsKey, out var versionUrl) && !string.IsNullOrWhiteSpace(versionUrl))
            return versionUrl;
        return InstallerUrl;
    }

    [JsonIgnore]
    public bool HasInstallerForCurrentWindows => !string.IsNullOrWhiteSpace(ResolveInstallerUrl());

    public override string ToString() => DisplayName;
}

public sealed class AppSettings
{
    public string Language { get; set; } = "ko-KR";
    public string DownloadFolder { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    public bool BlockWindowsUpdateDrivers { get; set; } = true;
    public bool SuppressAdrenalinUpdates { get; set; } = true;
    public string SourceFolder { get; set; } = @"C:\AMD";
    public string PreparedFolder { get; set; } = string.Empty;
    public string PreparedProfileId { get; set; } = string.Empty;
    public string LastDownloadedInstaller { get; set; } = string.Empty;
}

public sealed class FileRule
{
    public string Path { get; set; } = string.Empty;
    public string Sha256 { get; set; } = string.Empty;
    public string? PatchedSha256 { get; set; }
}

public sealed class PatchOperation
{
    public string Type { get; set; } = string.Empty;
    public string File { get; set; } = string.Empty;
    public string? Search { get; set; }
    public string? Replacement { get; set; }
    public int ExpectedOccurrences { get; set; } = 1;
    public long Offset { get; set; }
    public string? ExpectedHex { get; set; }
    public string? ReplacementHex { get; set; }
    public string? DataHex { get; set; }
    public List<Int32Update> Int32Updates { get; set; } = [];
}

public sealed class Int32Update
{
    public long Offset { get; set; }
    public int ExpectedValue { get; set; }
    public int Value { get; set; }
}

public sealed class RegistrySetting
{
    public string Root { get; set; } = "DisplayClass";
    public string SubKey { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Kind { get; set; } = "DWord";
    public JsonElement Value { get; set; }
}
