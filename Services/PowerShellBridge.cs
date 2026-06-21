using System.Diagnostics;
using System.Text;
using AMD.BootCamp.WinUI.Models;

namespace AMD.BootCamp.WinUI.Services;

public sealed class PowerShellBridge
{
    private readonly AppLogger _log;
    private readonly string _powerShell = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.Windows),
        "System32", "WindowsPowerShell", "v1.0", "powershell.exe");

    public PowerShellBridge(AppLogger log) => _log = log;

    public async Task<ProcessResult> RunScriptAsync(
        string scriptName,
        IEnumerable<string> arguments,
        CancellationToken cancellationToken = default)
    {
        var script = Path.Combine(AppContext.BaseDirectory, "Scripts", scriptName);
        if (!File.Exists(script)) throw new FileNotFoundException("PowerShell bridge script is missing.", script);

        var start = new ProcessStartInfo
        {
            FileName = _powerShell,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-ExecutionPolicy");
        start.ArgumentList.Add("Bypass");
        start.ArgumentList.Add("-File");
        start.ArgumentList.Add(script);
        foreach (var argument in arguments) start.ArgumentList.Add(argument);

        using var process = new Process { StartInfo = start, EnableRaisingEvents = true };
        if (!process.Start()) throw new InvalidOperationException("Failed to start Windows PowerShell.");
        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        foreach (var line in stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)) _log.Info(line);
        foreach (var line in stderr.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)) _log.Warning(line);
        return new ProcessResult(process.ExitCode, stdout, stderr);
    }

    public int StartDetachedScript(string scriptName, IEnumerable<string> arguments)
    {
        var script = Path.Combine(AppContext.BaseDirectory, "Scripts", scriptName);
        if (!File.Exists(script)) throw new FileNotFoundException("PowerShell worker script is missing.", script);

        var start = new ProcessStartInfo
        {
            FileName = _powerShell,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = AppContext.BaseDirectory
        };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-ExecutionPolicy");
        start.ArgumentList.Add("Bypass");
        start.ArgumentList.Add("-File");
        start.ArgumentList.Add(script);
        foreach (var argument in arguments) start.ArgumentList.Add(argument);

        using var process = Process.Start(start) ?? throw new InvalidOperationException("Failed to start the detached PowerShell worker.");
        _log.Info($"Detached worker started. PID={process.Id}");
        return process.Id;
    }

    public static void EnsureSuccess(ProcessResult result, string operation)
    {
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"{operation} failed with exit code {result.ExitCode}. {result.StandardError}".Trim());
    }
}
