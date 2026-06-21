using Microsoft.UI.Xaml;

namespace AMD.BootCamp.WinUI;

public partial class App : Application
{
    public static Window? MainWindowInstance { get; private set; }
    private static readonly string StartupLogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AMD BootCamp Driver Studio", "startup-error.log");

    public App()
    {
        UnhandledException += (_, e) => WriteStartupError("Application.UnhandledException", e.Exception);
        try
        {
            InitializeComponent();
        }
        catch (Exception ex)
        {
            WriteStartupError("App.InitializeComponent", ex);
            throw;
        }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            MainWindowInstance = new MainWindow();
            MainWindowInstance.Activate();
        }
        catch (Exception ex)
        {
            WriteStartupError("App.OnLaunched", ex);
            throw;
        }
    }

    private static void WriteStartupError(string stage, Exception exception)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StartupLogPath)!);
            var properties = string.Join(Environment.NewLine,
                exception.GetType().GetProperties()
                    .Where(property => property.GetIndexParameters().Length == 0)
                    .Select(property =>
                    {
                        try { return $"{property.Name}={property.GetValue(exception)}"; }
                        catch { return $"{property.Name}=<unavailable>"; }
                    }));
            File.AppendAllText(StartupLogPath,
                $"[{DateTimeOffset.Now:O}] {stage}{Environment.NewLine}" +
                $"HResult=0x{exception.HResult:X8}{Environment.NewLine}{properties}{Environment.NewLine}" +
                $"{exception}{Environment.NewLine}{Environment.NewLine}");
        }
        catch
        {
            // Never hide the original startup failure because diagnostic logging failed.
        }
    }
}
