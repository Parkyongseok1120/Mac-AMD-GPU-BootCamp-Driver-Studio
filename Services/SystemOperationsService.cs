using System.Text.Json;
using AMD.BootCamp.WinUI.Models;

namespace AMD.BootCamp.WinUI.Services;

public sealed class SystemOperationsService
{
    private readonly AppLogger _log;
    private readonly PowerShellBridge _bridge;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true, WriteIndented = true };
    public static string BackupRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "AMD BootCamp Driver Studio", "Backups");
    public static string InstallResultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AMD BootCamp Driver Studio", "install-result.json");

    public SystemOperationsService(AppLogger log, PowerShellBridge bridge)
    {
        _log = log;
        _bridge = bridge;
    }

    public async Task<SecurityStatus> GetStatusAsync(DriverProfile profile, CancellationToken cancellationToken = default)
    {
        var result = await _bridge.RunScriptAsync("System-Bridge.ps1",
        ["-Action", "Status", "-ProfilePath", profile.SourcePath], cancellationToken);
        PowerShellBridge.EnsureSuccess(result, "System status query");
        var json = result.StandardOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Last(x => x.TrimStart().StartsWith('{'));
        return JsonSerializer.Deserialize<SecurityStatus>(json, JsonOptions)
               ?? throw new InvalidDataException("System status JSON is invalid.");
    }

    public async Task EnableTestSigningAsync(DriverProfile profile, CancellationToken cancellationToken = default)
    {
        var result = await _bridge.RunScriptAsync("System-Bridge.ps1",
        ["-Action", "EnableTestSigning", "-ProfilePath", profile.SourcePath], cancellationToken);
        PowerShellBridge.EnsureSuccess(result, "Enable test-signing mode");
    }

    public async Task DisableTestSigningAsync(DriverProfile profile, CancellationToken cancellationToken = default)
    {
        var result = await _bridge.RunScriptAsync("System-Bridge.ps1",
        ["-Action", "DisableTestSigning", "-ProfilePath", profile.SourcePath], cancellationToken);
        PowerShellBridge.EnsureSuccess(result, "Disable test-signing mode");
    }

    public async Task ConfigureDefaultsAsync(
        DriverProfile profile,
        bool blockWindowsUpdate,
        bool suppressAdrenalin,
        CancellationToken cancellationToken = default)
    {
        var result = await _bridge.RunScriptAsync("System-Bridge.ps1",
        [
            "-Action", "ConfigureDefaults",
            "-ProfilePath", profile.SourcePath,
            "-BlockWindowsUpdate", blockWindowsUpdate ? "true" : "false",
            "-SuppressAdrenalin", suppressAdrenalin ? "true" : "false"
        ], cancellationToken);
        PowerShellBridge.EnsureSuccess(result, "Configure default driver policies");
    }

    public async Task<string> InstallAsync(
        DriverProfile profile,
        string preparedRoot,
        bool blockWindowsUpdate,
        bool suppressAdrenalin,
        CancellationToken cancellationToken = default)
    {
        var result = await _bridge.RunScriptAsync("System-Bridge.ps1",
        [
            "-Action", "Install",
            "-ProfilePath", profile.SourcePath,
            "-PackageRoot", preparedRoot,
            "-BlockWindowsUpdate", blockWindowsUpdate ? "true" : "false",
            "-SuppressAdrenalin", suppressAdrenalin ? "true" : "false"
        ], cancellationToken);
        PowerShellBridge.EnsureSuccess(result, "Driver installation");
        return result.StandardOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
                   .LastOrDefault(x => x.StartsWith("BACKUP=", StringComparison.OrdinalIgnoreCase))?
                   .Split('=', 2)[1] ?? string.Empty;
    }

    public void StartDetachedInstall(
        DriverProfile profile,
        string preparedRoot,
        bool blockWindowsUpdate,
        bool suppressAdrenalin,
        string relaunchExecutable)
    {
        if (!File.Exists(relaunchExecutable))
            throw new FileNotFoundException("The application executable used for relaunch was not found.", relaunchExecutable);

        _bridge.StartDetachedScript("Install-Worker.ps1",
        [
            "-ProfilePath", profile.SourcePath,
            "-PackageRoot", preparedRoot,
            "-BlockWindowsUpdate", blockWindowsUpdate ? "true" : "false",
            "-SuppressAdrenalin", suppressAdrenalin ? "true" : "false",
            "-RelaunchExecutable", relaunchExecutable,
            "-LogPath", _log.LogPath
        ]);
    }

    public async Task RestoreAsync(DriverProfile profile, string backupFolder, CancellationToken cancellationToken = default)
    {
        var result = await _bridge.RunScriptAsync("System-Bridge.ps1",
        [
            "-Action", "Restore",
            "-ProfilePath", profile.SourcePath,
            "-BackupFolder", backupFolder
        ], cancellationToken);
        PowerShellBridge.EnsureSuccess(result, "Backup restoration");
    }

    public async Task<InstallResultSnapshot?> LoadInstallResultAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(InstallResultPath)) return null;
        await using var stream = File.OpenRead(InstallResultPath);
        return await JsonSerializer.DeserializeAsync<InstallResultSnapshot>(stream, JsonOptions, cancellationToken);
    }

    public async Task SaveInstallResultAsync(InstallResultSnapshot snapshot, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(InstallResultPath)!);
        await using var stream = new FileStream(InstallResultPath, FileMode.Create, FileAccess.Write, FileShare.None);
        await JsonSerializer.SerializeAsync(stream, snapshot, JsonOptions, cancellationToken);
    }

    public void ClearInstallResult()
    {
        if (File.Exists(InstallResultPath)) File.Delete(InstallResultPath);
    }

    public IReadOnlyList<string> ListBackups()
    {
        var root = BackupRoot;
        if (!Directory.Exists(root)) return [];
        return Directory.EnumerateDirectories(root)
            .Where(x => Directory.EnumerateFiles(x, "*.inf", SearchOption.AllDirectories).Any())
            .OrderByDescending(x => x)
            .ToList();
    }

    public void RestartComputer()
    {
        _log.Warning("Restart requested by user.");
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "shutdown.exe",
            Arguments = "/r /t 5 /c \"AMD Boot Camp Driver Studio restart\"",
            UseShellExecute = false,
            CreateNoWindow = true
        });
    }
}
