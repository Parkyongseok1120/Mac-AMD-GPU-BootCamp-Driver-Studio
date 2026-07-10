using System.Text.Json;
using AMD.BootCamp.WinUI.Models;

namespace AMD.BootCamp.WinUI.Services;

public sealed class ProfileCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip
    };

    private readonly AppLogger _log;

    public ProfileCatalog(AppLogger log) => _log = log;

    public async Task<IReadOnlyList<DriverProfile>> LoadAsync(CancellationToken cancellationToken = default)
    {
        var byId = new Dictionary<string, DriverProfile>(StringComparer.OrdinalIgnoreCase);
        var folders = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "Profiles"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "AMD BootCamp Driver Studio", "Profiles")
        };

        Directory.CreateDirectory(folders[1]);
        foreach (var folder in folders)
        {
            if (!Directory.Exists(folder)) continue;
            foreach (var file in Directory.EnumerateFiles(folder, "*.json", SearchOption.TopDirectoryOnly))
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    await using var stream = File.OpenRead(file);
                    var profile = await JsonSerializer.DeserializeAsync<DriverProfile>(stream, JsonOptions, cancellationToken)
                        ?? throw new InvalidDataException("Profile JSON is empty.");
                    Validate(profile);
                    if (profile.InstallationMode.Equals("legacy-binary-patch", StringComparison.OrdinalIgnoreCase))
                        profile.IsUserVisible = false;
                    profile.SourcePath = file;
                    byId[profile.Id] = profile;
                    _log.Info($"Loaded profile {profile.Id} from {file}");
                }
                catch (Exception ex)
                {
                    _log.Warning($"Skipped invalid profile {file}: {ex.Message}");
                }
            }
        }
        return byId.Values
            .OrderByDescending(x => x.MarketingVersion)
            .ThenBy(x => ProfileUsesBinaryPatch(x) ? 99 : 0)
            .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public static void Validate(DriverProfile profile)
    {
        if (profile.SchemaVersion is not (1 or 2)) throw new InvalidDataException($"Unsupported schema: {profile.SchemaVersion}");
        if (string.IsNullOrWhiteSpace(profile.Id) || string.IsNullOrWhiteSpace(profile.InfName))
            throw new InvalidDataException("Profile ID and INF name are required.");
        if (profile.SupportedHardwareIds.Count == 0 || profile.Files.Count == 0)
            throw new InvalidDataException("Hardware IDs and file rules are required.");

        foreach (var path in profile.Files.Select(x => x.Path)
                     .Concat(profile.Patches.Select(x => x.File))
                     .Append(profile.KernelDriverPath)
                     .Append(profile.CatalogFile))
        {
            EnsureSafeRelativePath(path);
        }

        var allowedModes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "legacy-binary-patch", "inf-only", "original-kernel-hybrid", "whql-anchor"
        };
        if (!allowedModes.Contains(profile.InstallationMode))
            throw new InvalidDataException($"Unknown installation mode: {profile.InstallationMode}");

        var sourceIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var source in profile.AdditionalSources)
        {
            if (string.IsNullOrWhiteSpace(source.Id) || !sourceIds.Add(source.Id) ||
                string.IsNullOrWhiteSpace(source.InfName) || source.Files.Count == 0)
                throw new InvalidDataException("Each additional package source needs a unique ID, INF name, and file rules.");
            EnsureSafeRelativePath(source.InfName);
            foreach (var path in source.Files.Select(x => x.Path)) EnsureSafeRelativePath(path);
            foreach (var file in source.Files)
            {
                if (file.Sha256.Length != 64 || !file.Sha256.All(Uri.IsHexDigit))
                    throw new InvalidDataException($"Invalid SHA-256 for source {source.Id}/{file.Path}");
            }
        }

        foreach (var copy in profile.SourceFileCopies)
        {
            if (!sourceIds.Contains(copy.SourceId))
                throw new InvalidDataException($"Unknown source ID in copy rule: {copy.SourceId}");
            EnsureSafeRelativePath(copy.SourcePath);
            EnsureSafeRelativePath(copy.DestinationPath);
            if (copy.Sha256.Length != 64 || !copy.Sha256.All(Uri.IsHexDigit))
                throw new InvalidDataException($"Invalid SHA-256 for copied source file: {copy.SourcePath}");
        }

        foreach (var assertion in profile.RuntimeFileAssertions)
        {
            EnsureSafeRelativePath(assertion.Path);
            if (assertion.Sha256.Length != 64 || !assertion.Sha256.All(Uri.IsHexDigit))
                throw new InvalidDataException($"Invalid runtime assertion hash: {assertion.Path}");
        }

        if (profile.InstallationMode is "inf-only" or "original-kernel-hybrid")
        {
            if (profile.UsesBinaryPatch)
                throw new InvalidDataException($"{profile.InstallationMode} must not contain a binary patch or a modified kernel driver.");
        }
        if (profile.InstallationMode == "original-kernel-hybrid" &&
            (profile.AdditionalSources.Count == 0 || profile.SourceFileCopies.Count == 0))
            throw new InvalidDataException("An original-kernel-hybrid profile requires an additional source and explicit copy rules.");
        foreach (var file in profile.Files)
        {
            if (file.Sha256.Length != 64 || !file.Sha256.All(Uri.IsHexDigit))
                throw new InvalidDataException($"Invalid SHA-256 for {file.Path}");
        }

        var installerUrls = profile.InstallerUrls.Values
            .Append(profile.InstallerUrl)
            .Where(url => !string.IsNullOrWhiteSpace(url))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (installerUrls.Count > 0)
        {
            foreach (var installerUrl in installerUrls)
            {
                if (!Uri.TryCreate(installerUrl, UriKind.Absolute, out var uri))
                    throw new InvalidDataException("Installer URL is invalid.");
                EnsureOfficialAmdUri(uri);
            }
            if (string.IsNullOrWhiteSpace(profile.InstallerFileName) ||
                Path.GetFileName(profile.InstallerFileName) != profile.InstallerFileName)
                throw new InvalidDataException("Installer file name is invalid.");
            if (profile.InstallerSha256.Length != 64 || !profile.InstallerSha256.All(Uri.IsHexDigit))
                throw new InvalidDataException("Installer SHA-256 is invalid.");
            if (profile.InstallerSize < 0)
                throw new InvalidDataException("Installer size cannot be negative.");
        }
        if (!string.IsNullOrWhiteSpace(profile.OfficialPageUrl))
        {
            if (!Uri.TryCreate(profile.OfficialPageUrl, UriKind.Absolute, out var officialPage))
                throw new InvalidDataException("Official page URL is invalid.");
            EnsureOfficialAmdUri(officialPage);
        }
    }

    public static string SafeCombine(string root, string relative)
    {
        EnsureSafeRelativePath(relative);
        var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"Path escaped package root: {relative}");
        return full;
    }

    public static void EnsureOfficialAmdUri(Uri? uri)
    {
        if (uri is null || uri.Scheme != Uri.UriSchemeHttps ||
            !(uri.Host.Equals("amd.com", StringComparison.OrdinalIgnoreCase) ||
              uri.Host.EndsWith(".amd.com", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException("URL must use HTTPS on an official AMD domain.");
    }

    private static bool ProfileUsesBinaryPatch(DriverProfile profile) =>
        profile.KernelDriverModified ||
        profile.Patches.Any(p => p.Type.StartsWith("Binary", StringComparison.OrdinalIgnoreCase));

    private static void EnsureSafeRelativePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path) || path.Split('/', '\\').Contains(".."))
            throw new InvalidDataException($"Unsafe relative path: {path}");
    }
}
