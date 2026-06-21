using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AMD.BootCamp.WinUI.Models;

namespace AMD.BootCamp.WinUI.Services;

public sealed class PackageService
{
    private readonly AppLogger _log;
    private readonly PowerShellBridge _bridge;

    public PackageService(AppLogger log, PowerShellBridge bridge)
    {
        _log = log;
        _bridge = bridge;
    }

    public async Task<PackageAuditResult> AuditAsync(
        DriverProfile profile,
        string selectedPath,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var root = ResolvePackageRoot(profile, selectedPath);
        var results = new List<(string Path, string Sha256)>();
        for (var index = 0; index < profile.Files.Count; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var rule = profile.Files[index];
            var file = ProfileCatalog.SafeCombine(root, rule.Path);
            if (!File.Exists(file)) throw new FileNotFoundException($"Required package file is missing: {rule.Path}", file);
            var hash = await ComputeSha256Async(file, cancellationToken);
            if (!hash.Equals(rule.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"SHA-256 mismatch for {rule.Path}. Expected {rule.Sha256}, actual {hash}.");
            results.Add((rule.Path, hash));
            progress?.Report((index + 1d) / profile.Files.Count);
            _log.Info($"Verified {rule.Path}: {hash}");
        }
        return new PackageAuditResult(profile, root, results, true);
    }

    public IReadOnlyList<string> DiscoverPackageRoots(DriverProfile profile, IEnumerable<string> searchRoots)
    {
        var matches = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var searchRoot in searchRoots.Where(x => !string.IsNullOrWhiteSpace(x)))
        {
            var root = Path.GetFullPath(searchRoot);
            if (!Directory.Exists(root)) continue;

            foreach (var candidate in profile.PackageRootCandidates)
            {
                var direct = Path.GetFullPath(Path.Combine(root, candidate.Replace('/', Path.DirectorySeparatorChar)));
                if (File.Exists(Path.Combine(direct, profile.InfName))) matches.Add(direct);
            }

            try
            {
                foreach (var inf in Directory.EnumerateFiles(root, profile.InfName, SearchOption.AllDirectories))
                    matches.Add(Path.GetDirectoryName(inf)!);
            }
            catch (UnauthorizedAccessException ex)
            {
                _log.Warning($"Some folders could not be searched below {root}: {ex.Message}");
            }
            catch (IOException ex)
            {
                _log.Warning($"Package search below {root} was incomplete: {ex.Message}");
            }
        }
        return matches.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
    }

    public async Task<PrepareResult> PrepareAsync(
        PackageAuditResult audit,
        string requestedDestination,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
        => await PrepareCoreAsync(audit, requestedDestination, progress, signPackage: true, cancellationToken);

    public async Task<PrepareResult> PrepareUnsignedForValidationAsync(
        PackageAuditResult audit,
        string requestedDestination,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
        => await PrepareCoreAsync(audit, requestedDestination, progress, signPackage: false, cancellationToken);

    private async Task<PrepareResult> PrepareCoreAsync(
        PackageAuditResult audit,
        string requestedDestination,
        IProgress<double>? progress,
        bool signPackage,
        CancellationToken cancellationToken)
    {
        if (!audit.IsValid) throw new InvalidOperationException("The source package has not passed verification.");
        var destination = GetUniqueDestination(requestedDestination);
        _log.Info($"Copying package to {destination}");
        await CopyDirectoryAsync(audit.PackageRoot, destination, progress, cancellationToken);

        await Task.Run(() =>
        {
            for (var i = 0; i < audit.Profile.Patches.Count; i++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                ApplyPatch(destination, audit.Profile.Patches[i]);
                progress?.Report(0.72 + (i + 1d) / audit.Profile.Patches.Count * 0.12);
            }
        }, cancellationToken);

        foreach (var rule in audit.Profile.Files.Where(x => !string.IsNullOrWhiteSpace(x.PatchedSha256)))
        {
            var path = ProfileCatalog.SafeCombine(destination, rule.Path);
            var hash = await ComputeSha256Async(path, cancellationToken);
            if (!hash.Equals(rule.PatchedSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"Patched SHA-256 mismatch for {rule.Path}. Expected {rule.PatchedSha256}, actual {hash}.");
        }

        var manifestPath = Path.Combine(destination, "BootCampStudio.manifest.json");
        var manifest = new
        {
            ToolVersion = "1.0.0",
            ProfileId = audit.Profile.Id,
            audit.Profile.MarketingVersion,
            audit.Profile.PackageVersion,
            audit.Profile.DriverVersion,
            HardwareIds = audit.Profile.SupportedHardwareIds,
            PreparedAt = DateTimeOffset.Now,
            SourceHashes = audit.Files.ToDictionary(x => x.Path, x => x.Sha256)
        };
        await File.WriteAllTextAsync(manifestPath,
            JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }), cancellationToken);

        var thumbprint = string.Empty;
        if (signPackage)
        {
            progress?.Report(0.86);
            var sign = await _bridge.RunScriptAsync("Sign-Package.ps1",
            [
                "-PackageRoot", destination,
                "-KernelDriverPath", audit.Profile.KernelDriverPath,
                "-CatalogFile", audit.Profile.CatalogFile,
                "-CertificateSubject", audit.Profile.CertificateSubject
            ], cancellationToken);
            PowerShellBridge.EnsureSuccess(sign, "Driver package signing");
            thumbprint = sign.StandardOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
                .LastOrDefault(x => x.StartsWith("THUMBPRINT=", StringComparison.OrdinalIgnoreCase))?
                .Split('=', 2)[1] ?? string.Empty;
        }
        progress?.Report(1);
        return new PrepareResult(destination, manifestPath, thumbprint);
    }

    public async Task ValidatePreparedAsync(DriverProfile profile, string root, CancellationToken cancellationToken = default)
    {
        // Authenticode signing intentionally changes the kernel binary. Its unsigned
        // patched hash is verified before signing; here the PowerShell bridge verifies
        // the resulting signature instead. Text/config files remain byte-exact.
        foreach (var rule in profile.Files.Where(x =>
                     !string.IsNullOrWhiteSpace(x.PatchedSha256) &&
                     !x.Path.Equals(profile.KernelDriverPath, StringComparison.OrdinalIgnoreCase)))
        {
            var hash = await ComputeSha256Async(ProfileCatalog.SafeCombine(root, rule.Path), cancellationToken);
            if (!hash.Equals(rule.PatchedSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"Prepared file validation failed: {rule.Path}");
        }
        var validate = await _bridge.RunScriptAsync("Sign-Package.ps1",
        [
            "-ValidateOnly",
            "-PackageRoot", root,
            "-KernelDriverPath", profile.KernelDriverPath,
            "-CatalogFile", profile.CatalogFile,
            "-CertificateSubject", profile.CertificateSubject
        ], cancellationToken);
        PowerShellBridge.EnsureSuccess(validate, "Prepared package signature validation");
    }

    private static string ResolvePackageRoot(DriverProfile profile, string selectedPath)
    {
        if (string.IsNullOrWhiteSpace(selectedPath)) throw new ArgumentException("Select an AMD package folder.");
        var basePath = File.Exists(selectedPath) ? Path.GetDirectoryName(selectedPath)! : selectedPath;
        if (!Directory.Exists(basePath)) throw new DirectoryNotFoundException(basePath);
        foreach (var candidate in profile.PackageRootCandidates)
        {
            var root = Path.GetFullPath(Path.Combine(basePath, candidate.Replace('/', Path.DirectorySeparatorChar)));
            if (File.Exists(Path.Combine(root, profile.InfName))) return root;
        }
        throw new DirectoryNotFoundException($"No package root matching profile {profile.Id} was found below {basePath}.");
    }

    private void ApplyPatch(string root, PatchOperation operation)
    {
        var path = ProfileCatalog.SafeCombine(root, operation.File);
        switch (operation.Type.ToLowerInvariant())
        {
            case "textreplace":
                ApplyTextReplace(path, operation);
                break;
            case "binaryreplace":
                ApplyBinaryReplace(path, operation);
                break;
            case "binaryinsert":
                ApplyBinaryInsert(path, operation);
                break;
            default:
                throw new InvalidDataException($"Unknown patch type: {operation.Type}");
        }
        _log.Info($"Applied {operation.Type} to {operation.File}");
    }

    private static void ApplyTextReplace(string path, PatchOperation operation)
    {
        var search = operation.Search ?? throw new InvalidDataException("TextReplace search text is missing.");
        var replacement = operation.Replacement ?? throw new InvalidDataException("TextReplace replacement text is missing.");
        var text = File.ReadAllText(path, Encoding.ASCII);
        var count = CountOccurrences(text, search);
        if (count != operation.ExpectedOccurrences)
            throw new InvalidDataException($"Expected {operation.ExpectedOccurrences} occurrences in {operation.File}, found {count}.");
        File.WriteAllText(path, text.Replace(search, replacement, StringComparison.Ordinal), Encoding.ASCII);
    }

    private static void ApplyBinaryReplace(string path, PatchOperation operation)
    {
        var expected = Convert.FromHexString(operation.ExpectedHex ?? throw new InvalidDataException("ExpectedHex is missing."));
        var replacement = Convert.FromHexString(operation.ReplacementHex ?? throw new InvalidDataException("ReplacementHex is missing."));
        if (expected.Length != replacement.Length) throw new InvalidDataException("BinaryReplace lengths differ.");
        using var stream = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        stream.Position = operation.Offset;
        var actual = new byte[expected.Length];
        stream.ReadExactly(actual);
        if (!actual.SequenceEqual(expected))
            throw new InvalidDataException($"Binary precondition failed at 0x{operation.Offset:X} in {operation.File}.");
        stream.Position = operation.Offset;
        stream.Write(replacement);
    }

    private static void ApplyBinaryInsert(string path, PatchOperation operation)
    {
        var insert = Convert.FromHexString(operation.DataHex ?? throw new InvalidDataException("DataHex is missing."));
        var original = File.ReadAllBytes(path);
        if (operation.Offset < 0 || operation.Offset > original.LongLength) throw new InvalidDataException("BinaryInsert offset is outside the file.");
        var result = new byte[original.Length + insert.Length];
        Buffer.BlockCopy(original, 0, result, 0, checked((int)operation.Offset));
        Buffer.BlockCopy(insert, 0, result, checked((int)operation.Offset), insert.Length);
        Buffer.BlockCopy(original, checked((int)operation.Offset), result,
            checked((int)operation.Offset) + insert.Length, original.Length - checked((int)operation.Offset));
        foreach (var update in operation.Int32Updates)
        {
            var actual = BitConverter.ToInt32(result, checked((int)update.Offset));
            if (actual != update.ExpectedValue)
                throw new InvalidDataException($"Int32 precondition failed at 0x{update.Offset:X} in {operation.File}.");
            BitConverter.GetBytes(update.Value).CopyTo(result, checked((int)update.Offset));
        }
        File.WriteAllBytes(path, result);
    }

    private static int CountOccurrences(string text, string value)
    {
        var count = 0;
        for (var index = 0; (index = text.IndexOf(value, index, StringComparison.Ordinal)) >= 0; index += value.Length) count++;
        return count;
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1024 * 1024, true);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash);
    }

    private static string GetUniqueDestination(string requested)
    {
        var full = Path.GetFullPath(requested);
        if (!Directory.Exists(full)) return full;
        return $"{full}-{DateTime.Now:yyyyMMdd-HHmmss}";
    }

    private static async Task CopyDirectoryAsync(
        string source,
        string destination,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        var files = Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories).ToList();
        Directory.CreateDirectory(destination);
        for (var index = 0; index < files.Count; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var relative = Path.GetRelativePath(source, files[index]);
            var target = Path.Combine(destination, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            await using var input = new FileStream(files[index], FileMode.Open, FileAccess.Read, FileShare.Read, 1024 * 1024, true);
            await using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1024 * 1024, true);
            await input.CopyToAsync(output, 1024 * 1024, cancellationToken);
            progress?.Report((index + 1d) / Math.Max(1, files.Count) * 0.70);
        }
    }
}
