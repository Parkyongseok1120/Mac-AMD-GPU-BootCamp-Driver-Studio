using System.Text.Json;

namespace AMD.BootCamp.WinUI.Services;

public sealed class LocalizationService
{
    private Dictionary<string, string> _strings = new(StringComparer.OrdinalIgnoreCase);
    public string Language { get; private set; } = "en-US";

    public async Task LoadAsync(string language, CancellationToken cancellationToken = default)
    {
        var file = Path.Combine(AppContext.BaseDirectory, "Resources", "Localization", $"{language}.json");
        if (!File.Exists(file)) file = Path.Combine(AppContext.BaseDirectory, "Resources", "Localization", "en-US.json");
        await using var stream = File.OpenRead(file);
        _strings = await JsonSerializer.DeserializeAsync<Dictionary<string, string>>(stream,
            cancellationToken: cancellationToken) ?? new Dictionary<string, string>();
        Language = Path.GetFileNameWithoutExtension(file);
    }

    public string this[string key] => _strings.TryGetValue(key, out var value) ? value : key;
}
