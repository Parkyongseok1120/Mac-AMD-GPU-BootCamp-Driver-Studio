using System.Management;
using AMD.BootCamp.WinUI.Models;

namespace AMD.BootCamp.WinUI.Services;

public sealed class HardwareService
{
    public Task<IReadOnlyList<DetectedGpu>> DetectGpusAsync(CancellationToken cancellationToken = default) =>
        Task.Run<IReadOnlyList<DetectedGpu>>(() =>
        {
            var results = new List<DetectedGpu>();
            using var searcher = new ManagementObjectSearcher(
                "SELECT Name,PNPDeviceID,Status,ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPClass='Display'");
            foreach (ManagementObject item in searcher.Get())
            {
                cancellationToken.ThrowIfCancellationRequested();
                results.Add(new DetectedGpu(
                    item["Name"]?.ToString() ?? "Unknown GPU",
                    item["PNPDeviceID"]?.ToString() ?? string.Empty,
                    item["Status"]?.ToString() ?? string.Empty,
                    item["ConfigManagerErrorCode"] is uint code ? code : 0));
            }
            return results;
        }, cancellationToken);

    public static DetectedGpu RequireSupported(IReadOnlyList<DetectedGpu> gpus, DriverProfile profile)
    {
        var match = gpus.FirstOrDefault(gpu => profile.SupportedHardwareIds.Any(id =>
            gpu.PnpDeviceId.StartsWith(id, StringComparison.OrdinalIgnoreCase)));
        return match ?? throw new InvalidOperationException(
            $"Supported hardware was not found. Required: {string.Join(", ", profile.SupportedHardwareIds)}");
    }
}
