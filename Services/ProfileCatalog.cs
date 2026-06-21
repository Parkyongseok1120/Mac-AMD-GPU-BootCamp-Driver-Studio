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
        return byId.Values.OrderByDescending(x => x.MarketingVersion).ToList();
    }

    public static void Validate(DriverProfile profile)
    {
        if (profile.SchemaVersion != 1) throw new InvalidDataException($"Unsupported schema: {profile.SchemaVersion}");
        if (string.IsNullOrWhiteSpace(profile.Id) || string.IsNullOrWhiteSpace(profile.InfName))
            throw new InvalidDataException("Profile ID and INF name are required.");
        if (profile.SupportedHardwareIds.Count == 0 || profile.Files.Count == 0 || profile.Patches.Count == 0)
            throw new InvalidDataException("Hardware IDs, file rules, and patches are required.");

        foreach (var path in profile.Files.Select(x => x.Path)
                     .Concat(profile.Patches.Select(x => x.File))
                     .Append(profile.KernelDriverPath)
                     .Append(profile.CatalogFile))
        {
            EnsureSafeRelativePath(path);
        }

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

    private static void EnsureSafeRelativePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path) || path.Split('/', '\\').Contains(".."))
            throw new InvalidDataException($"Unsafe relative path: {path}");
    }
}
