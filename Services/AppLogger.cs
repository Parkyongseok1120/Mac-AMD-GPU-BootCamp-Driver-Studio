using System.Collections.ObjectModel;

namespace AMD.BootCamp.WinUI.Services;

public sealed class AppLogger
{
    private readonly object _gate = new();
    private readonly string _logPath;

    public string LogPath => _logPath;

    public ObservableCollection<string> Lines { get; } = [];
    public event EventHandler<string>? LineAdded;

    public AppLogger(string? logFolder = null)
    {
        var folder = logFolder ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AMD BootCamp Driver Studio", "Logs");
        Directory.CreateDirectory(folder);
        _logPath = Path.Combine(folder, $"studio-{DateTime.Now:yyyyMMdd}.log");
    }

    public void Info(string message) => Write("INFO", message);
    public void Warning(string message) => Write("WARN", message);
    public void Error(string message) => Write("ERROR", message);

    public IReadOnlyList<string> ReadRecentLines(int maximum = 250)
    {
        lock (_gate)
        {
            if (!File.Exists(_logPath)) return [];
            return File.ReadLines(_logPath).TakeLast(Math.Max(1, maximum)).ToList();
        }
    }

    public void Clear()
    {
        lock (_gate)
        {
            File.WriteAllText(_logPath, string.Empty);
            Lines.Clear();
        }
    }

    private void Write(string level, string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] [{level}] {message}";
        lock (_gate)
        {
            File.AppendAllText(_logPath, line + Environment.NewLine);
        }
        LineAdded?.Invoke(this, line);
    }
}
