using System.Text.Json;
using System.Security.Cryptography;
using AMD.BootCamp.WinUI.Models;
using AMD.BootCamp.WinUI.Services;

if (args.Length is < 2 or > 4)
{
    Console.Error.WriteLine("Usage: ProfileSelfTest <profile.json> <official-package-folder> [additional-official-package-folder] [verified-installer-folder]");
    return 2;
}

var profilePath = Path.GetFullPath(args[0]);
var sourceRoot = Path.GetFullPath(args[1]);
var profile = JsonSerializer.Deserialize<DriverProfile>(
                  await File.ReadAllTextAsync(profilePath),
                  new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
              ?? throw new InvalidDataException("Profile JSON is empty.");
ProfileCatalog.Validate(profile);
profile.SourcePath = profilePath;

var additionalSourcePaths = profile.RequiresAdditionalSource
    ? args.Length >= 3
        ? profile.AdditionalSources.ToDictionary(
            source => source.Id,
            _ => Path.GetFullPath(args[2]),
            StringComparer.OrdinalIgnoreCase)
        : throw new InvalidDataException("This profile requires an additional official package folder.")
    : null;
var installerFolderArgumentIndex = profile.RequiresAdditionalSource ? 3 : 2;

var scratch = Path.Combine(Path.GetTempPath(), $"AMD-BootCamp-ProfileTest-{Guid.NewGuid():N}");
var extractedRoot = Path.Combine(scratch, "extracted");
var minimalSource = Path.Combine(extractedRoot, "Packages", "Drivers", "Display2", "WT6A_INF");
var prepared = Path.Combine(scratch, "prepared");

try
{
    foreach (var rule in profile.Files)
    {
        var source = ProfileCatalog.SafeCombine(sourceRoot, rule.Path);
        var target = ProfileCatalog.SafeCombine(minimalSource, rule.Path);
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.Copy(source, target);
    }

    var log = new AppLogger(Path.Combine(scratch, "logs"));
    log.LineAdded += (_, line) => Console.WriteLine(line);
    var packages = new PackageService(log, new PowerShellBridge(log));
    var discovered = packages.DiscoverPackageRoots(profile, [extractedRoot]);
    if (!discovered.Contains(minimalSource, StringComparer.OrdinalIgnoreCase))
        throw new InvalidDataException("Fresh AMD extraction package discovery self-test failed.");
    Console.WriteLine("PACKAGE_DISCOVERY_TEST=PASS");
    var audit = await packages.AuditAsync(profile, minimalSource, supplementalSourcePaths: additionalSourcePaths);
    var result = await packages.PrepareUnsignedForValidationAsync(audit, prepared);

    Console.WriteLine($"SELF_TEST=PASS");
    Console.WriteLine($"PROFILE={profile.Id}");
    Console.WriteLine($"FILES={audit.Files.Count}");
    Console.WriteLine($"OUTPUT={result.OutputRoot}");

    var payload = new byte[2 * 1024 * 1024 + 37];
    new Random(5500).NextBytes(payload);
    payload[0] = (byte)'M';
    payload[1] = (byte)'Z';
    var downloadProfile = JsonSerializer.Deserialize<DriverProfile>(JsonSerializer.Serialize(profile))
                          ?? throw new InvalidDataException("Could not clone the download test profile.");
    downloadProfile.InstallerFileName = "download-stream-self-test.exe";
    downloadProfile.InstallerSha256 = Convert.ToHexString(SHA256.HashData(payload));
    downloadProfile.InstallerSize = payload.LongLength;
    downloadProfile.InstallerUrl = "https://drivers.amd.com/drivers/download-stream-self-test.exe";
    downloadProfile.InstallerUrls = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["windows10"] = downloadProfile.InstallerUrl,
        ["windows11"] = downloadProfile.InstallerUrl
    };
    var downloadTestFolder = Path.Combine(scratch, "download-test");
    var downloadTest = new DriverDownloadService(log, new StaticContentHandler(payload));
    var concurrentResults = await Task.WhenAll(
        downloadTest.DownloadAsync(downloadProfile, downloadTestFolder),
        downloadTest.DownloadAsync(downloadProfile, downloadTestFolder));
    if (concurrentResults.Select(x => x.Path).Distinct(StringComparer.OrdinalIgnoreCase).Count() != 1 ||
        !File.Exists(concurrentResults[0].Path) ||
        Directory.EnumerateFiles(downloadTestFolder, "*.partial*", SearchOption.TopDirectoryOnly).Any())
        throw new InvalidDataException("Concurrent download stream self-test failed.");
    Console.WriteLine("DOWNLOAD_STREAM_TEST=PASS");

    if (args.Length > installerFolderArgumentIndex)
    {
        var installerFolder = Path.GetFullPath(args[installerFolderArgumentIndex]);
        var installerCandidate = Path.Combine(installerFolder, profile.InstallerFileName);
        if (File.Exists(installerCandidate))
        {
            var downloads = new DriverDownloadService(log);
            var installer = await downloads.DownloadAsync(profile, installerFolder);
            Console.WriteLine($"INSTALLER_REUSE=PASS");
            Console.WriteLine($"INSTALLER={installer.Path}");
        }
        else
        {
            Console.WriteLine("INSTALLER_REUSE=SKIP (verified installer is not present)");
        }
    }
    return 0;
}
finally
{
    if (Directory.Exists(scratch)) Directory.Delete(scratch, recursive: true);
}

file sealed class StaticContentHandler(byte[] content) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        if (request.Headers.Referrer?.Host.EndsWith("amd.com", StringComparison.OrdinalIgnoreCase) != true ||
            !request.Headers.UserAgent.ToString().Contains("Mozilla/5.0", StringComparison.Ordinal))
            throw new InvalidDataException("AMD download request headers were not configured correctly.");
        var response = new HttpResponseMessage(System.Net.HttpStatusCode.OK)
        {
            RequestMessage = request,
            Content = new ByteArrayContent(content)
        };
        response.Content.Headers.ContentLength = content.LongLength;
        response.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
        return Task.FromResult(response);
    }
}
