using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using AMD.BootCamp.WinUI.Models;

namespace AMD.BootCamp.WinUI.Services;

public sealed class DriverDownloadService
{
    private const string BrowserUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36";

    private static readonly ConcurrentDictionary<string, SemaphoreSlim> DownloadGates =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly AppLogger _log;
    private readonly HttpClient _client;

    public DriverDownloadService(AppLogger log, HttpMessageHandler? handler = null)
    {
        _log = log;
        _client = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = true })
        {
            Timeout = Timeout.InfiniteTimeSpan
        };
        _client.DefaultRequestHeaders.UserAgent.ParseAdd(BrowserUserAgent);
    }

    public async Task<DriverDownloadResult> DownloadAsync(
        DriverProfile profile,
        string destinationFolder,
        IProgress<DownloadProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ProfileCatalog.Validate(profile);
        var installerUrl = profile.ResolveInstallerUrl();
        if (string.IsNullOrWhiteSpace(installerUrl))
            throw new InvalidOperationException("This profile does not provide an automatic download URL.");

        Directory.CreateDirectory(destinationFolder);
        var destination = Path.Combine(destinationFolder, profile.InstallerFileName);
        var gate = DownloadGates.GetOrAdd(destination, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken);
        try
        {
            return await DownloadLockedAsync(profile, installerUrl, destination, progress, cancellationToken);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<(DriverProfile Profile, DriverDownloadResult Result)> IdentifyInstallerAsync(
        string path,
        IEnumerable<DriverProfile> profiles,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("AMD installer was not found.", path);
        if (!await HasExecutableHeaderAsync(path, cancellationToken))
            throw new InvalidDataException("The selected file is not a Windows executable installer.");

        var info = new FileInfo(path);
        var hash = await ComputeSha256Async(path, cancellationToken);
        var profile = profiles
            .Where(x => x.HasInstallerForCurrentWindows)
            .Where(x => x.InstallerSha256.Equals(hash, StringComparison.OrdinalIgnoreCase))
            .Where(x => x.InstallerSize <= 0 || x.InstallerSize == info.Length)
            .OrderBy(x => x.IsUserVisible ? 0 : 1)
            .ThenBy(x => ProfileUsesBinaryPatch(x) ? 1 : 0)
            .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
        if (profile is null)
        {
            throw new InvalidDataException(
                $"The selected installer does not match any loaded profile. Bytes={info.Length:N0}; SHA-256={hash}");
        }

        _log.Info($"Selected verified AMD {profile.MarketingVersion} installer: {path} ({info.Length:N0} bytes, SHA-256 {hash})");
        return (profile, new DriverDownloadResult(path, true, info.Length, hash));
    }

    private async Task<DriverDownloadResult> DownloadLockedAsync(
        DriverProfile profile,
        string installerUrl,
        string destination,
        IProgress<DownloadProgress>? progress,
        CancellationToken cancellationToken)
    {
        _log.Info($"Detected {DriverProfile.CurrentWindowsDisplayName}; selected the matching AMD download route.");
        var existing = await VerifyInstallerAsync(destination, profile, cancellationToken);
        if (existing.IsValid)
        {
            _log.Info($"Using previously verified AMD installer: {destination}");
            progress?.Report(new DownloadProgress(existing.Bytes, existing.Bytes, 100, 0, TimeSpan.Zero));
            return new DriverDownloadResult(destination, true, existing.Bytes, existing.Sha256);
        }

        await using var downloadLock = await AcquireDownloadLockAsync(destination, profile, cancellationToken);
        existing = await VerifyInstallerAsync(destination, profile, cancellationToken);
        if (existing.IsValid)
        {
            _log.Info($"Another app instance completed the verified download: {destination}");
            progress?.Report(new DownloadProgress(existing.Bytes, existing.Bytes, 100, 0, TimeSpan.Zero));
            return new DriverDownloadResult(destination, true, existing.Bytes, existing.Sha256);
        }

        TryDelete(destination + ".partial");
        var partial = $"{destination}.partial.{Environment.ProcessId}.{Guid.NewGuid():N}";
        try
        {
            _log.Info($"Downloading official AMD {profile.MarketingVersion} package from {installerUrl}");
            using var request = CreateRequest(profile, installerUrl);
            using var response = await _client.SendAsync(request,
                HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            response.EnsureSuccessStatusCode();
            ValidateResponse(response, profile);

            var length = response.Content.Headers.ContentLength ??
                         (profile.InstallerSize > 0 ? profile.InstallerSize : null);
            var stopwatch = Stopwatch.StartNew();
            var lastReport = TimeSpan.Zero;
            long total = 0;

            await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken))
            await using (var output = new FileStream(partial, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                             1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
            {
                var buffer = new byte[1024 * 1024];
                while (true)
                {
                    var read = await input.ReadAsync(buffer, cancellationToken);
                    if (read == 0) break;
                    await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                    total += read;

                    if (stopwatch.Elapsed - lastReport >= TimeSpan.FromMilliseconds(250))
                    {
                        ReportProgress(progress, total, length, stopwatch.Elapsed);
                        lastReport = stopwatch.Elapsed;
                    }
                }
                await output.FlushAsync(cancellationToken);
            }

            ReportProgress(progress, total, length, stopwatch.Elapsed);
            if (profile.InstallerSize > 0 && total != profile.InstallerSize)
                throw new InvalidDataException(
                    $"AMD installer download is incomplete: received {total:N0} of {profile.InstallerSize:N0} bytes.");
            if (!await HasExecutableHeaderAsync(partial, cancellationToken))
                throw new InvalidDataException(
                    "AMD returned a web page instead of the installer. Open the official page and try again.");

            progress?.Report(new DownloadProgress(total, length, 100, 0, null, IsVerifying: true));
            var actualHash = await ComputeSha256Async(partial, cancellationToken);
            if (!actualHash.Equals(profile.InstallerSha256, StringComparison.OrdinalIgnoreCase))
            {
                _log.Error($"AMD installer SHA-256 mismatch. Expected={profile.InstallerSha256}; " +
                           $"Actual={actualHash}; Bytes={total:N0}");
                throw new InvalidDataException(
                    $"Downloaded AMD installer SHA-256 does not match the selected profile. Actual: {actualHash}");
            }

            File.Move(partial, destination, overwrite: true);
            progress?.Report(new DownloadProgress(total, length, 100, 0, TimeSpan.Zero));
            _log.Info($"Verified AMD installer: {destination} ({total:N0} bytes, SHA-256 {actualHash})");
            return new DriverDownloadResult(destination, false, total, actualHash);
        }
        finally
        {
            TryDelete(partial);
            TryDelete(destination + ".partial");
        }
    }

    private static HttpRequestMessage CreateRequest(DriverProfile profile, string installerUrl)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, installerUrl);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/octet-stream"));
        if (Uri.TryCreate(profile.OfficialPageUrl, UriKind.Absolute, out var officialPage))
        {
            var builder = new UriBuilder(officialPage) { Fragment = string.Empty };
            request.Headers.Referrer = builder.Uri;
        }
        return request;
    }

    private static void ValidateResponse(HttpResponseMessage response, DriverProfile profile)
    {
        var finalUri = response.RequestMessage?.RequestUri;
        ProfileCatalog.EnsureOfficialAmdUri(finalUri);
        var mediaType = response.Content.Headers.ContentType?.MediaType;
        if (finalUri?.AbsolutePath.Contains("Download-Incomplete", StringComparison.OrdinalIgnoreCase) == true ||
            string.Equals(mediaType, "text/html", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException(
                "AMD redirected the request to its download-incomplete page instead of sending the installer.");

        var length = response.Content.Headers.ContentLength;
        if (profile.InstallerSize > 0 && length is > 0 && length.Value != profile.InstallerSize)
            throw new InvalidDataException(
                $"AMD returned an unexpected file size: {length.Value:N0} bytes (expected {profile.InstallerSize:N0}).");
    }

    private static void ReportProgress(
        IProgress<DownloadProgress>? progress,
        long bytes,
        long? totalBytes,
        TimeSpan elapsed)
    {
        if (progress is null) return;
        var speed = elapsed.TotalSeconds > 0 ? bytes / elapsed.TotalSeconds : 0;
        var percent = totalBytes is > 0 ? Math.Clamp(bytes * 100d / totalBytes.Value, 0, 100) : 0;
        TimeSpan? remaining = totalBytes is > 0 && speed > 0
            ? TimeSpan.FromSeconds(Math.Max(0, (totalBytes.Value - bytes) / speed))
            : null;
        progress.Report(new DownloadProgress(bytes, totalBytes, percent, speed, remaining));
    }

    private async Task<FileStream> AcquireDownloadLockAsync(
        string destination,
        DriverProfile profile,
        CancellationToken cancellationToken)
    {
        var lockPath = destination + ".download.lock";
        var waitingLogged = false;
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None,
                    1, FileOptions.Asynchronous | FileOptions.DeleteOnClose);
            }
            catch (IOException)
            {
                if (!waitingLogged)
                {
                    _log.Warning("Another app instance is downloading this AMD package. Waiting for it to finish.");
                    waitingLogged = true;
                }
                if ((await VerifyInstallerAsync(destination, profile, cancellationToken)).IsValid)
                    continue;
                await Task.Delay(1000, cancellationToken);
            }
            catch (UnauthorizedAccessException ex)
            {
                throw new InvalidOperationException(
                    $"The download folder is not writable: {Path.GetDirectoryName(destination)}", ex);
            }
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public static void LaunchInstaller(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("Downloaded AMD installer was not found.", path);
        Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
    }

    public static void OpenOfficialPage(DriverProfile profile)
    {
        if (string.IsNullOrWhiteSpace(profile.OfficialPageUrl)) return;
        Process.Start(new ProcessStartInfo { FileName = profile.OfficialPageUrl, UseShellExecute = true });
    }

    private static async Task<(bool IsValid, long Bytes, string Sha256)> VerifyInstallerAsync(
        string path,
        DriverProfile profile,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(path)) return (false, 0, string.Empty);
        var info = new FileInfo(path);
        if (profile.InstallerSize > 0 && info.Length != profile.InstallerSize)
            return (false, info.Length, string.Empty);
        var hash = await ComputeSha256Async(path, cancellationToken);
        return (hash.Equals(profile.InstallerSha256, StringComparison.OrdinalIgnoreCase), info.Length, hash);
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
            1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken));
    }

    private static async Task<bool> HasExecutableHeaderAsync(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
            2, FileOptions.Asynchronous | FileOptions.SequentialScan);
        var header = new byte[2];
        return await stream.ReadAsync(header, cancellationToken) == 2 && header[0] == (byte)'M' && header[1] == (byte)'Z';
    }

    private static bool ProfileUsesBinaryPatch(DriverProfile profile) =>
        profile.KernelDriverModified ||
        profile.Patches.Any(p => p.Type.StartsWith("Binary", StringComparison.OrdinalIgnoreCase));
}
