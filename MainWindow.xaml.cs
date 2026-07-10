using System.Globalization;
using AMD.BootCamp.WinUI.Models;
using AMD.BootCamp.WinUI.Services;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WinRT.Interop;

namespace AMD.BootCamp.WinUI;

public sealed partial class MainWindow : Window
{
    private readonly AppLogger _log = new();
    private readonly ProfileCatalog _profiles;
    private readonly HardwareService _hardware = new();
    private readonly PowerShellBridge _bridge;
    private readonly PackageService _packages;
    private readonly SystemOperationsService _system;
    private readonly DriverDownloadService _downloads;
    private readonly AppSettingsService _settingsService = new();
    private readonly LocalizationService _localization = new();
    private readonly CancellationTokenSource _shutdown = new();
    private PackageAuditResult? _audit;
    private string? _preparedRoot;
    private string? _lastDownloadedInstaller;
    private AppSettings _settings = new();
    private IReadOnlyList<DriverProfile> _loadedProfiles = [];
    private bool _syncingLanguage;
    private bool _syncingProfileSelection;

    private DriverProfile? SelectedProfile => ProfilePicker.SelectedItem as DriverProfile;

    private static bool ShowHiddenProfiles =>
        string.Equals(Environment.GetEnvironmentVariable("AMD_BOOTCAMP_SHOW_LEGACY_PROFILES"), "1", StringComparison.Ordinal);

    private IEnumerable<DriverProfile> GetUserFacingProfiles() =>
        _loadedProfiles.Where(x => x.IsUserVisible || ShowHiddenProfiles);

    private DriverProfile? ResolveSelectableProfile(DriverProfile? preferred) =>
        preferred is { IsUserVisible: true } || (preferred is not null && ShowHiddenProfiles)
            ? preferred
            : GetUserFacingProfiles().FirstOrDefault();

    public MainWindow()
    {
        InitializeComponent();
        _profiles = new ProfileCatalog(_log);
        _bridge = new PowerShellBridge(_log);
        _packages = new PackageService(_log, _bridge);
        _system = new SystemOperationsService(_log, _bridge);
        _downloads = new DriverDownloadService(_log);
        ConfigureWindow();
        _log.LineAdded += Log_LineAdded;
        var recentLog = _log.ReadRecentLines();
        if (recentLog.Count > 0)
            LogTextBox.Text = string.Join(Environment.NewLine, recentLog) + Environment.NewLine;
        Closed += (_, _) => _shutdown.Cancel();
        Activated += MainWindow_Activated;
    }

    private bool _activationHandled;
    private async void MainWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        if (_activationHandled) return;
        _activationHandled = true;
        await InitializeAsync();
    }

    private void ConfigureWindow()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var id = Win32Interop.GetWindowIdFromWindow(hwnd);
        var window = AppWindow.GetFromWindowId(id);
        window.Resize(new Windows.Graphics.SizeInt32(1180, 900));
        MainNavigation.SelectedItem = OverviewNav;
    }

    private async Task InitializeAsync()
    {
        await RunBusyAsync(async ct =>
        {
            _settings = await _settingsService.LoadAsync(ct);
            var language = _settings.Language is "ko-KR" or "en-US"
                ? _settings.Language
                : CultureInfo.CurrentUICulture.Name.StartsWith("ko", StringComparison.OrdinalIgnoreCase) ? "ko-KR" : "en-US";
            _syncingLanguage = true;
            SetLanguagePicker(LanguagePicker, language);
            SetLanguagePicker(SettingsLanguagePicker, language);
            _syncingLanguage = false;
            await _localization.LoadAsync(language, ct);
            ApplyLanguage();

            _loadedProfiles = await _profiles.LoadAsync(ct);
            ApplyLanguage();
            ProfilePicker.ItemsSource = GetUserFacingProfiles().ToList();
            DriverVersionList.ItemsSource = GetDownloadProfiles();
            var pendingInstallResult = await _system.LoadInstallResultAsync(ct);
            var initialProfile = Directory.Exists(_settings.PreparedFolder)
                ? _loadedProfiles.FirstOrDefault(x => x.Id.Equals(_settings.PreparedProfileId, StringComparison.OrdinalIgnoreCase))
                : null;
            initialProfile = ResolveSelectableProfile(initialProfile) ?? GetUserFacingProfiles().FirstOrDefault();
            SelectProfile(initialProfile);
            if (pendingInstallResult is { ProfileId.Length: > 0 })
            {
                var installProfile = ResolveSelectableProfile(_loadedProfiles.FirstOrDefault(x =>
                    x.Id.Equals(pendingInstallResult.ProfileId, StringComparison.OrdinalIgnoreCase)));
                if (installProfile is not null) SelectProfile(installProfile);
            }
            DownloadFolderBox.Text = _settings.DownloadFolder;
            SourcePathBox.Text = string.IsNullOrWhiteSpace(_settings.SourceFolder) ? @"C:\AMD" : _settings.SourceFolder;
            if (SelectedProfile is { } selected &&
                _settings.PreparedProfileId.Equals(selected.Id, StringComparison.OrdinalIgnoreCase) &&
                Directory.Exists(_settings.PreparedFolder))
            {
                _preparedRoot = _settings.PreparedFolder;
                OutputPathBox.Text = _preparedRoot;
                PreparedRootText.Text = _preparedRoot;
            }
            if (File.Exists(_settings.LastDownloadedInstaller))
            {
                _lastDownloadedInstaller = _settings.LastDownloadedInstaller;
                LastDownloadedText.Text = _lastDownloadedInstaller;
            }
            BlockWindowsUpdateToggle.IsOn = _settings.BlockWindowsUpdateDrivers;
            SuppressAdrenalinToggle.IsOn = _settings.SuppressAdrenalinUpdates;
            SettingsBlockWindowsUpdateToggle.IsOn = _settings.BlockWindowsUpdateDrivers;
            SettingsSuppressAdrenalinToggle.IsOn = _settings.SuppressAdrenalinUpdates;
            RefreshBackups();
            await RefreshStatusAsync(ct);
            if (pendingInstallResult is not null)
                await ShowPendingInstallResultAsync(pendingInstallResult, ct);
            _log.Info("AMD Boot Camp Driver Studio 1.1.0 started.");
        }, showProgress: false);
    }

    private async Task RunBusyAsync(Func<CancellationToken, Task> action, bool showProgress = true)
    {
        BusyRing.IsActive = true;
        OperationProgress.Visibility = showProgress ? Visibility.Visible : Visibility.Collapsed;
        OperationProgress.Value = 0;
        MainNavigation.IsEnabled = false;
        try
        {
            await action(_shutdown.Token);
        }
        catch (OperationCanceledException) when (_shutdown.IsCancellationRequested) { }
        catch (Exception ex)
        {
            _log.Error(ex.Message);
            ShowStatus(ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            MainNavigation.IsEnabled = true;
            BusyRing.IsActive = false;
            OperationProgress.Visibility = Visibility.Collapsed;
        }
    }

    private async Task ShowPendingInstallResultAsync(InstallResultSnapshot result, CancellationToken cancellationToken)
    {
        try
        {
            var profile = _loadedProfiles.FirstOrDefault(x =>
                              x.Id.Equals(result.ProfileId, StringComparison.OrdinalIgnoreCase))
                          ?? SelectedProfile;
            if (profile is null) return;

            var status = await _system.GetStatusAsync(profile, cancellationToken);
            var details = new List<string>();
            if (!string.IsNullOrWhiteSpace(result.Message)) details.Add(result.Message);
            details.Add(string.Format(_localization["dialog.installResultPackageRoot"], result.PackageRoot));
            if (!string.IsNullOrWhiteSpace(result.BackupFolder))
                details.Add(string.Format(_localization["dialog.installResultBackup"], result.BackupFolder));
            details.Add(string.Format(_localization["dialog.installResultExpectedVersion"], profile.DriverVersion));
            details.Add(string.Format(_localization["dialog.installResultActualVersion"],
                string.IsNullOrWhiteSpace(status.DriverVersion) ? "—" : status.DriverVersion));
            details.Add(string.Format(_localization["dialog.installResultDriverInf"],
                string.IsNullOrWhiteSpace(status.DriverInf) ? "—" : status.DriverInf));

            string title;
            if (!result.Success)
            {
                title = _localization["dialog.installResultFailureTitle"];
                details.Insert(0, _localization["dialog.installResultFailureIntro"]);
                if (!string.IsNullOrWhiteSpace(result.Error))
                    details.Add(string.Format(_localization["dialog.installResultError"], result.Error));
                ShowStatus(result.Error.Length > 0 ? result.Error : result.Message, InfoBarSeverity.Error);
            }
            else
            {
                var issues = new List<string>();
                if (!status.HardwarePresent)
                    issues.Add(_localization["dialog.installResultHardwareMissing"]);
                if (!string.Equals(status.DriverVersion, profile.DriverVersion, StringComparison.OrdinalIgnoreCase))
                    issues.Add(string.Format(_localization["dialog.installResultVersionMismatch"], profile.DriverVersion,
                        string.IsNullOrWhiteSpace(status.DriverVersion) ? "—" : status.DriverVersion));
                if (status.ProblemCode != 0)
                    issues.Add(string.Format(_localization["dialog.installResultProblemCode"], status.ProblemCode));
                if (profile.KernelDriverModified && !status.TestSigningActive)
                    issues.Add(_localization["dialog.installResultTestModeOff"]);

                if (issues.Count == 0)
                {
                    title = _localization["dialog.installResultSuccessTitle"];
                    details.Insert(0, _localization["dialog.installResultSuccessIntro"]);
                    ShowStatus(_localization["message.installResultApplied"], InfoBarSeverity.Success);
                }
                else
                {
                    title = _localization["dialog.installResultWarningTitle"];
                    details.Insert(0, _localization["dialog.installResultWarningIntro"]);
                    details.Add(string.Empty);
                    details.Add(_localization["dialog.installResultDetectedIssues"]);
                    details.AddRange(issues.Select(x => $"• {x}"));
                    ShowStatus(_localization["message.installResultNeedsReview"], InfoBarSeverity.Warning);
                }
            }

            if (!string.IsNullOrWhiteSpace(result.LogPath))
                details.Add(string.Format(_localization["dialog.installResultLog"], result.LogPath));

            var dialog = new ContentDialog
            {
                XamlRoot = MainNavigation.XamlRoot,
                Title = title,
                Content = new TextBlock
                {
                    Text = string.Join(Environment.NewLine, details),
                    TextWrapping = TextWrapping.Wrap,
                    MaxWidth = 640
                },
                CloseButtonText = _localization["action.close"],
                DefaultButton = ContentDialogButton.Close
            };
            await dialog.ShowAsync();
        }
        finally
        {
            _system.ClearInstallResult();
        }
    }

    private async Task RefreshStatusAsync(CancellationToken cancellationToken)
    {
        var profile = SelectedProfile;
        if (profile is null)
        {
            ProfileStatusText.Text = _localization["profile.none"];
            return;
        }
        ProfileStatusText.Text = profile.DisplayName;
        var status = await _system.GetStatusAsync(profile, cancellationToken);
        GpuNameText.Text = status.HardwarePresent ? status.GpuName : _localization["status.notDetected"];
        GpuCodeText.Text = status.HardwarePresent ? $"{status.HardwareId}\nCode {status.ProblemCode}" : profile.SupportedHardwareIds[0];
        DriverVersionText.Text = string.IsNullOrWhiteSpace(status.DriverVersion) ? "—" : status.DriverVersion;
        DriverInfText.Text = string.IsNullOrWhiteSpace(status.DriverInf) ? "—" : status.DriverInf;
        SecureBootText.Text = status.SecureBootEnabled ? _localization["status.secureBootOn"] : _localization["status.secureBootOff"];
        if (profile.KernelDriverModified)
        {
            TestModeText.Text = status.TestSigningActive
                ? _localization["status.testModeOn"]
                : status.TestSigningConfigured
                    ? _localization["status.testModePending"]
                    : _localization["status.testModeOff"];
        }
        else
        {
            TestModeText.Text = status.CertificateImported
                ? _localization["status.certImported"]
                : _localization["status.certNotImported"];
        }
    }

    private void MainNavigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag) return;
        OverviewView.Visibility = tag == "overview" ? Visibility.Visible : Visibility.Collapsed;
        PackageView.Visibility = tag == "package" ? Visibility.Visible : Visibility.Collapsed;
        DownloadsView.Visibility = tag == "downloads" ? Visibility.Visible : Visibility.Collapsed;
        PrepareView.Visibility = tag == "prepare" ? Visibility.Visible : Visibility.Collapsed;
        InstallView.Visibility = tag == "install" ? Visibility.Visible : Visibility.Collapsed;
        BackupsView.Visibility = tag == "backups" ? Visibility.Visible : Visibility.Collapsed;
        SettingsView.Visibility = tag == "settings" ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void LanguagePicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_activationHandled || _syncingLanguage ||
            LanguagePicker.SelectedItem is not ComboBoxItem item || item.Tag is not string language) return;
        await ChangeLanguageAsync(language);
    }

    private async void SettingsLanguagePicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_activationHandled || _syncingLanguage ||
            SettingsLanguagePicker.SelectedItem is not ComboBoxItem item || item.Tag is not string language) return;
        await ChangeLanguageAsync(language);
    }

    private async Task ChangeLanguageAsync(string language)
    {
        _syncingLanguage = true;
        SetLanguagePicker(LanguagePicker, language);
        SetLanguagePicker(SettingsLanguagePicker, language);
        _syncingLanguage = false;
        await _localization.LoadAsync(language, _shutdown.Token);
        _settings.Language = language;
        await _settingsService.SaveAsync(_settings, _shutdown.Token);
        ApplyLanguage();
    }

    private static void SetLanguagePicker(ComboBox picker, string language) =>
        picker.SelectedIndex = language == "ko-KR" ? 0 : 1;

    private void ApplyLanguage()
    {
        AppTitleText.Text = _localization["app.title"];
        AppSubtitleText.Text = _localization["app.subtitle"];
        OverviewNav.Content = _localization["nav.overview"];
        PackageNav.Content = _localization["nav.package"];
        DownloadsNav.Content = _localization["nav.downloads"];
        PrepareNav.Content = _localization["nav.prepare"];
        InstallNav.Content = _localization["nav.install"];
        BackupsNav.Content = _localization["nav.backups"];
        SettingsNav.Content = _localization["nav.settings"];
        OverviewHeading.Text = _localization["overview.heading"];
        GpuCardLabel.Text = _localization["overview.gpu"];
        DriverCardLabel.Text = _localization["overview.driver"];
        SecurityCardLabel.Text = _localization["overview.security"];
        ProfileStatusLabel.Text = _localization["overview.profile"];
        ProfileStatusDetail.Text = _localization["overview.profileDetail"];
        RefreshStatusButton.Content = _localization["action.refresh"];
        PackageHeading.Text = _localization["package.heading"];
        PackageDescription.Text = _localization["package.description"];
        ProfilePickerLabel.Text = _localization["package.profile"];
        SourceFolderLabel.Text = _localization["package.source"];
        SourcePathBox.PlaceholderText = _localization["package.placeholder"];
        BrowseSourceButton.Content = _localization["action.browse"];
        AuditButton.Content = _localization["action.audit"];
        AuditResultLabel.Text = _localization["package.result"];
        if (_audit is null) AuditResultText.Text = _localization["package.notVerified"];
        PrepareHeading.Text = _localization["prepare.heading"];
        PrepareDescription.Text = _localization["prepare.description"];
        OutputFolderLabel.Text = _localization["prepare.output"];
        SecurityConsentText.Text = _localization["prepare.consent"];
        PrepareButton.Content = _localization["action.prepare"];
        PreparedPackageLabel.Text = _localization["prepare.result"];
        if (_preparedRoot is null) PreparedRootText.Text = _localization["prepare.notPrepared"];
        InstallHeading.Text = _localization["install.heading"];
        InstallDescription.Text = _localization["install.description"];
        InstallProfilePickerLabel.Text = _localization["install.profileChoice"];
        BlockWindowsUpdateToggle.Header = _localization["install.blockWu"];
        SuppressAdrenalinToggle.Header = _localization["install.blockAdrenalin"];
        EnableTestModeButton.Content = _localization["action.testMode"];
        DisableTestModeButton.Content = _localization["action.disableTestMode"];
        InstallButton.Content = _localization["action.install"];
        RestartButton.Content = _localization["action.restart"];
        BackupsHeading.Text = _localization["backups.heading"];
        BackupsDescription.Text = _localization["backups.description"];
        RefreshBackupsButton.Content = _localization["action.refreshBackups"];
        OpenBackupFolderButton.Content = _localization["action.openBackupFolder"];
        RestoreBackupButton.Content = _localization["action.restore"];
        LogsHeading.Text = _localization["logs.heading"];
        LogsDescription.Text = _localization["logs.description"];
        ClearLogButton.Content = _localization["action.clearLog"];
        DriverBasisNoticeText.Text = _localization["overview.driverBasis"];
        CreatorLink.Content = _localization["action.creatorLink"];
        DownloadsHeading.Text = _localization["downloads.heading"];
        DownloadsDescription.Text = _localization["downloads.description"];
        DetectedWindowsText.Text = string.Format(_localization["downloads.detectedWindows"], DriverProfile.CurrentWindowsDisplayName);
        UnifiedPackageNoticeText.Text = _localization["downloads.unifiedPackage"];
        DownloadBasisNoticeText.Text = _localization["downloads.driverBasis"];
        DownloadFolderLabel.Text = _localization["downloads.folder"];
        BrowseDownloadFolderButton.Content = _localization["action.browse"];
        DownloadResultLabel.Text = _localization["downloads.result"];
        if (_lastDownloadedInstaller is null)
        {
            LastDownloadedText.Text = _localization["downloads.notDownloaded"];
            DownloadProgressText.Text = _localization["downloads.progressIdle"];
        }
        RunDownloadedInstallerButton.Content = _localization["action.runInstaller"];
        BrowseDownloadedInstallerButton.Content = _localization["action.chooseInstaller"];
        DetectPackageButton.Content = _localization["action.detectPackage"];
        SettingsHeading.Text = _localization["settings.heading"];
        SettingsDescription.Text = _localization["settings.description"];
        SettingsLanguageLabel.Text = _localization["settings.language"];
        SettingsBlockWindowsUpdateToggle.Header = _localization["install.blockWu"];
        SettingsSuppressAdrenalinToggle.Header = _localization["install.blockAdrenalin"];
        SaveSettingsButton.Content = _localization["action.saveSettings"];
        ApplyDefaultsButton.Content = _localization["action.applyDefaults"];
        SetupGuideLabel.Text = _localization["settings.setup"];
        SetupGuideText.Text = _localization["settings.setupGuide"];
        foreach (var profile in _loadedProfiles)
        {
            UpdateProfileCardText(profile);
            profile.DownloadActionText = string.Format(_localization["action.downloadFor"], DriverProfile.CurrentWindowsDisplayName);
            profile.OfficialPageActionText = _localization["action.officialPage"];
            profile.WindowsCompatibilityText = _localization["downloads.compatibility"];
        }
        if (SelectedProfile is { } selectedProfile)
        {
            _syncingProfileSelection = true;
            try
            {
                InstallProfilePicker.ItemsSource = GetInstallProfilesFor(selectedProfile);
                InstallProfilePicker.SelectedItem = selectedProfile;
            }
            finally
            {
                _syncingProfileSelection = false;
            }
        }
        UpdateProfileModeUi();
        if (_loadedProfiles.Count > 0)
        {
            DriverVersionList.ItemsSource = null;
            DriverVersionList.ItemsSource = GetDownloadProfiles();
        }
    }

    private List<DriverProfile> GetDownloadProfiles() =>
        GetUserFacingProfiles()
            .Where(x => x.HasInstallerForCurrentWindows)
            .GroupBy(x => $"{x.InstallerFileName}|{x.InstallerSha256}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group
                .OrderBy(ProfileSelectionPriority)
                .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                .First())
            .OrderByDescending(x => x.MarketingVersion, StringComparer.OrdinalIgnoreCase)
            .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToList();

    private void BrowseSourceButton_Click(object sender, RoutedEventArgs e)
    {
        var folder = SelectFolder(SourcePathBox.Text, _localization["package.source"]);
        if (folder is not null) SourcePathBox.Text = folder;
    }

    private void BrowseAdditionalSourceButton_Click(object sender, RoutedEventArgs e)
    {
        var folder = SelectFolder(AdditionalSourcePathBox.Text, AdditionalSourceLabel.Text);
        if (folder is not null) AdditionalSourcePathBox.Text = folder;
    }

    private void BrowseDownloadFolderButton_Click(object sender, RoutedEventArgs e)
    {
        var folder = SelectFolder(DownloadFolderBox.Text, _localization["downloads.folder"]);
        if (folder is not null) DownloadFolderBox.Text = folder;
    }

    private string? SelectFolder(string currentPath, string description)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = description,
            UseDescriptionForTitle = true,
            ShowNewFolderButton = true,
            InitialDirectory = Directory.Exists(currentPath) ? currentPath : string.Empty
        };
        var owner = new WinFormsWindow(WindowNative.GetWindowHandle(this));
        return dialog.ShowDialog(owner) == System.Windows.Forms.DialogResult.OK
            ? dialog.SelectedPath
            : null;
    }

    private string? SelectInstallerFile(string currentPath)
    {
        using var dialog = new System.Windows.Forms.OpenFileDialog
        {
            Title = _localization["downloads.chooseInstallerTitle"],
            Filter = _localization["downloads.installerFilter"],
            CheckFileExists = true,
            Multiselect = false,
            InitialDirectory = Directory.Exists(currentPath)
                ? currentPath
                : Directory.Exists(DownloadFolderBox.Text.Trim())
                    ? DownloadFolderBox.Text.Trim()
                    : string.Empty
        };
        var owner = new WinFormsWindow(WindowNative.GetWindowHandle(this));
        return dialog.ShowDialog(owner) == System.Windows.Forms.DialogResult.OK
            ? dialog.FileName
            : null;
    }

    private async void BrowseDownloadedInstallerButton_Click(object sender, RoutedEventArgs e)
    {
        var selectedPath = SelectInstallerFile(_lastDownloadedInstaller ?? DownloadFolderBox.Text.Trim());
        if (selectedPath is null) return;
        await RunBusyAsync(async ct =>
        {
            var (profile, result) = await _downloads.IdentifyInstallerAsync(selectedPath, _loadedProfiles, ct);
            SelectInstallProfileForDownloadedPackage(profile);
            _lastDownloadedInstaller = result.Path;
            _settings.LastDownloadedInstaller = result.Path;
            _settings.DownloadFolder = Path.GetDirectoryName(result.Path) ?? _settings.DownloadFolder;
            DownloadFolderBox.Text = _settings.DownloadFolder;
            await _settingsService.SaveAsync(_settings, ct);
            LastDownloadedText.Text = result.Path;
            DownloadProgressBar.Value = 100;
            DownloadProgressText.Text = string.Format(_localization["downloads.progressComplete"], FormatBytes(result.Bytes));
            ShowStatus(_localization["message.selectedInstallerVerified"], InfoBarSeverity.Success);
        });
    }

    private async void DownloadVersionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: DriverProfile profile }) return;
        SelectInstallProfileForDownloadedPackage(profile);
        await RunBusyAsync(async ct =>
        {
            await SaveSettingsFromControlsAsync(ct);
            var result = await EnsureInstallerAsync(profile, ct);
            ShowStatus(_localization[result.ReusedExisting
                ? "message.reusedInstaller"
                : "message.downloadSuccess"], InfoBarSeverity.Success);
        });
    }

    private async Task<DriverDownloadResult> EnsureInstallerAsync(
        DriverProfile profile,
        CancellationToken cancellationToken)
    {
        DownloadProgressBar.Value = 0;
        DownloadProgressText.Text = _localization["downloads.progressStarting"];
        var progress = new Progress<DownloadProgress>(UpdateDownloadProgress);
        var result = await _downloads.DownloadAsync(profile,
            DownloadFolderBox.Text.Trim(), progress, cancellationToken);
        _lastDownloadedInstaller = result.Path;
        _settings.LastDownloadedInstaller = result.Path;
        await _settingsService.SaveAsync(_settings, cancellationToken);
        LastDownloadedText.Text = result.Path;
        DownloadProgressBar.Value = 100;
        DownloadProgressText.Text = string.Format(_localization["downloads.progressComplete"],
            FormatBytes(result.Bytes));
        return result;
    }

    private void UpdateDownloadProgress(DownloadProgress progress)
    {
        DownloadProgressBar.Value = progress.Percent;
        OperationProgress.Value = progress.Percent;
        if (progress.IsVerifying)
        {
            DownloadProgressText.Text = _localization["downloads.progressVerifying"];
            return;
        }

        var total = progress.TotalBytes is > 0 ? FormatBytes(progress.TotalBytes.Value) : _localization["downloads.unknownSize"];
        var eta = progress.EstimatedRemaining is { } remaining
            ? remaining.ToString(remaining.TotalHours >= 1 ? @"hh\:mm\:ss" : @"mm\:ss")
            : "--:--";
        DownloadProgressText.Text = string.Format(_localization["downloads.progress"],
            progress.Percent,
            FormatBytes(progress.BytesReceived),
            total,
            FormatBytes(progress.BytesPerSecond),
            eta);
    }

    private void OfficialPageButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: DriverProfile profile }) DriverDownloadService.OpenOfficialPage(profile);
    }

    private async void RunDownloadedInstallerButton_Click(object sender, RoutedEventArgs e)
    {
        var profile = RequireProfile();
        await RunBusyAsync(async ct =>
        {
            await SaveSettingsFromControlsAsync(ct);
            var installer = await EnsureInstallerAsync(profile, ct);
            DriverDownloadService.LaunchInstaller(installer.Path);
            ShowStatus(_localization["message.extractorStarted"], InfoBarSeverity.Informational);
        });
    }

    private async void DetectPackageButton_Click(object sender, RoutedEventArgs e)
    {
        var profile = RequireProfile();
        await RunBusyAsync(async ct =>
        {
            var searchRoots = new List<string> { @"C:\AMD" };
            if (Directory.Exists(SourcePathBox.Text.Trim())) searchRoots.Insert(0, SourcePathBox.Text.Trim());
            var candidates = _packages.DiscoverPackageRoots(profile, searchRoots);
            if (candidates.Count == 0)
            {
                ShowStatus(_localization["message.packageNotFound"], InfoBarSeverity.Warning);
                return;
            }

            foreach (var candidate in candidates)
            {
                try
                {
                    _audit = await _packages.AuditAsync(profile, candidate, cancellationToken: ct,
                        supplementalSourcePaths: GetSupplementalSourcePaths(profile));
                    SourcePathBox.Text = _audit.PackageRoot;
                    _settings.SourceFolder = _audit.PackageRoot;
                    await _settingsService.SaveAsync(_settings, ct);
                    AuditResultText.Text = _localization["package.verified"];
                    AuditDetailText.Text = $"{_audit.PackageRoot}\n{_audit.Files.Count} files · SHA-256 OK";
                    MainNavigation.SelectedItem = PackageNav;
                    ShowStatus(_localization["message.packageDetected"], InfoBarSeverity.Success);
                    return;
                }
                catch (Exception ex) when (ex is InvalidDataException or FileNotFoundException or DirectoryNotFoundException)
                {
                    _log.Warning($"Skipped non-matching package candidate {candidate}: {ex.Message}");
                }
            }
            ShowStatus(_localization["message.packageNotValid"], InfoBarSeverity.Warning);
        });
    }

    private async void SaveSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        await RunBusyAsync(async ct =>
        {
            await SaveSettingsFromControlsAsync(ct);
            ShowStatus(_localization["message.settingsSaved"], InfoBarSeverity.Success);
        }, false);
    }

    private async void ApplyDefaultsButton_Click(object sender, RoutedEventArgs e)
    {
        await RunBusyAsync(async ct =>
        {
            await SaveSettingsFromControlsAsync(ct);
            await _system.ConfigureDefaultsAsync(RequireProfile(),
                _settings.BlockWindowsUpdateDrivers, _settings.SuppressAdrenalinUpdates, ct);
            ShowStatus(_localization["message.defaultsApplied"], InfoBarSeverity.Success);
        }, false);
    }

    private async Task SaveSettingsFromControlsAsync(CancellationToken cancellationToken)
    {
        _settings.DownloadFolder = DownloadFolderBox.Text.Trim();
        _settings.BlockWindowsUpdateDrivers = SettingsBlockWindowsUpdateToggle.IsOn;
        _settings.SuppressAdrenalinUpdates = SettingsSuppressAdrenalinToggle.IsOn;
        _settings.SourceFolder = string.IsNullOrWhiteSpace(SourcePathBox.Text) ? @"C:\AMD" : SourcePathBox.Text.Trim();
        _settings.PreparedFolder = _preparedRoot ?? _settings.PreparedFolder;
        _settings.PreparedProfileId = _preparedRoot is null ? _settings.PreparedProfileId : SelectedProfile?.Id ?? string.Empty;
        _settings.LastDownloadedInstaller = _lastDownloadedInstaller ?? _settings.LastDownloadedInstaller;
        if (SelectedProfile is { } profile)
        {
            foreach (var source in profile.AdditionalSources)
            {
                if (!string.IsNullOrWhiteSpace(AdditionalSourcePathBox.Text))
                    _settings.AdditionalSourceFolders[source.Id] = AdditionalSourcePathBox.Text.Trim();
            }
        }
        BlockWindowsUpdateToggle.IsOn = _settings.BlockWindowsUpdateDrivers;
        SuppressAdrenalinToggle.IsOn = _settings.SuppressAdrenalinUpdates;
        await _settingsService.SaveAsync(_settings, cancellationToken);
    }

    private async void AuditButton_Click(object sender, RoutedEventArgs e)
    {
        await RunBusyAsync(async ct =>
        {
            var profile = RequireProfile();
            var gpus = await _hardware.DetectGpusAsync(ct);
            var gpu = HardwareService.RequireSupported(gpus, profile);
            var progress = new Progress<double>(v => OperationProgress.Value = v * 100);
            _audit = await _packages.AuditAsync(profile, SourcePathBox.Text.Trim(), progress, ct,
                GetSupplementalSourcePaths(profile));
            AuditResultText.Text = _localization["package.verified"];
            var additionalFileCount = _audit.AdditionalSources?.Values.Sum(x => x.Files.Count) ?? 0;
            AuditDetailText.Text = $"{gpu.Name}\n{_audit.PackageRoot}\n{_audit.Files.Count} base files + {additionalFileCount} additional files · SHA-256 OK";
            ShowStatus(_localization["message.auditSuccess"], InfoBarSeverity.Success);
            MainNavigation.SelectedItem = PrepareNav;
        });
    }

    private async void PrepareButton_Click(object sender, RoutedEventArgs e)
    {
        if (!SecurityConsentCheck.IsChecked.GetValueOrDefault())
        {
            ShowStatus(_localization["message.consentRequired"], InfoBarSeverity.Warning);
            return;
        }
        await RunBusyAsync(async ct =>
        {
            var profile = RequireProfile();
            var progress = new Progress<double>(v => OperationProgress.Value = v * 100);
            _audit = await _packages.AuditAsync(profile, SourcePathBox.Text.Trim(), progress, ct,
                GetSupplementalSourcePaths(profile));
            var result = await _packages.PrepareAsync(_audit, OutputPathBox.Text.Trim(), progress, ct);
            _preparedRoot = result.OutputRoot;
            PreparedRootText.Text = result.OutputRoot;
            _settings.PreparedFolder = result.OutputRoot;
            _settings.PreparedProfileId = profile.Id;
            _settings.SourceFolder = _audit.PackageRoot;
            await _settingsService.SaveAsync(_settings, ct);
            ShowStatus(_localization["message.prepareSuccess"], InfoBarSeverity.Success);
            MainNavigation.SelectedItem = InstallNav;
        });
    }

    private async void EnableTestModeButton_Click(object sender, RoutedEventArgs e)
    {
        if (!RequireConsent()) return;
        var profile = RequireProfile();
        if (!profile.KernelDriverModified)
        {
            ShowStatus(_localization["message.certModeNotRequired"], InfoBarSeverity.Informational);
            return;
        }
        await RunBusyAsync(async ct =>
        {
            await _system.EnableTestSigningAsync(profile, ct);
            ShowStatus(_localization["message.testModeSuccess"], InfoBarSeverity.Success);
            await RefreshStatusAsync(ct);
        }, false);
    }

    private async void DisableTestModeButton_Click(object sender, RoutedEventArgs e)
    {
        var confirmed = await ConfirmAsync(_localization["dialog.disableTestModeTitle"], _localization["dialog.disableTestModeBody"]);
        if (!confirmed) return;
        await RunBusyAsync(async ct =>
        {
            await _system.DisableTestSigningAsync(RequireProfile(), ct);
            ShowStatus(_localization["message.disableTestModeSuccess"], InfoBarSeverity.Success);
            await RefreshStatusAsync(ct);
        }, false);
    }

    private async void InstallButton_Click(object sender, RoutedEventArgs e)
    {
        if (!RequireConsent()) return;
        var root = _preparedRoot ?? OutputPathBox.Text.Trim();
        var confirmed = await ConfirmAsync(_localization["dialog.installTitle"], _localization["dialog.installBody"]);
        if (!confirmed) return;
        var workerStarted = false;
        await RunBusyAsync(async ct =>
        {
            var profile = RequireProfile();
            await _packages.ValidatePreparedAsync(profile, root, ct);
            var executable = Environment.ProcessPath
                ?? throw new InvalidOperationException("The current application executable could not be resolved.");
            _log.Warning(_localization["message.detachedInstallStarting"]);
            _system.StartDetachedInstall(profile, root,
                BlockWindowsUpdateToggle.IsOn, SuppressAdrenalinToggle.IsOn, executable);
            workerStarted = true;
        }, false);
        if (workerStarted) Close();
    }

    private async void RestoreBackupButton_Click(object sender, RoutedEventArgs e)
    {
        if (!RequireConsent()) return;
        if (BackupList.SelectedItem is not string backup)
        {
            ShowStatus(_localization["message.selectBackup"], InfoBarSeverity.Warning);
            return;
        }
        if (!await ConfirmAsync(_localization["dialog.restoreTitle"], _localization["dialog.restoreBody"])) return;
        await RunBusyAsync(async ct =>
        {
            await _system.RestoreAsync(RequireProfile(), backup, ct);
            ShowStatus(_localization["message.restoreSuccess"], InfoBarSeverity.Success);
        });
    }

    private async void RefreshStatusButton_Click(object sender, RoutedEventArgs e) =>
        await RunBusyAsync(RefreshStatusAsync, false);

    private void RefreshBackupsButton_Click(object sender, RoutedEventArgs e) => RefreshBackups();
    private void OpenBackupFolderButton_Click(object sender, RoutedEventArgs e)
    {
        var folder = BackupList.SelectedItem as string ?? SystemOperationsService.BackupRoot;
        Directory.CreateDirectory(folder);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "explorer.exe",
            UseShellExecute = true,
            ArgumentList = { folder }
        });
    }
    private void RestartButton_Click(object sender, RoutedEventArgs e) => _system.RestartComputer();

    private void ClearLogButton_Click(object sender, RoutedEventArgs e)
    {
        _log.Clear();
        LogTextBox.Text = string.Empty;
        ShowStatus(_localization["message.logCleared"], InfoBarSeverity.Success);
    }

    private void ProfilePicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingProfileSelection) return;
        SelectProfile(ProfilePicker.SelectedItem as DriverProfile);
    }

    private void InstallProfilePicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingProfileSelection) return;
        SelectProfile(InstallProfilePicker.SelectedItem as DriverProfile);
    }

    private void SelectProfile(DriverProfile? profile)
    {
        profile = ResolveSelectableProfile(profile);
        if (profile is null) return;
        _syncingProfileSelection = true;
        try
        {
            ProfilePicker.SelectedItem = profile;
            InstallProfilePicker.ItemsSource = GetInstallProfilesFor(profile);
            InstallProfilePicker.SelectedItem = profile;
        }
        finally
        {
            _syncingProfileSelection = false;
        }

        OnSelectedProfileChanged();
    }

    private void SelectInstallProfileForDownloadedPackage(DriverProfile downloadProfile)
    {
        var current = SelectedProfile;
        if (current is not null &&
            current.InstallerFileName.Equals(downloadProfile.InstallerFileName, StringComparison.OrdinalIgnoreCase) &&
            current.InstallerSha256.Equals(downloadProfile.InstallerSha256, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var installProfile = GetUserFacingProfiles()
            .Where(x => x.InstallerFileName.Equals(downloadProfile.InstallerFileName, StringComparison.OrdinalIgnoreCase) &&
                        x.InstallerSha256.Equals(downloadProfile.InstallerSha256, StringComparison.OrdinalIgnoreCase))
            .OrderBy(ProfileSelectionPriority)
            .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
        SelectProfile(installProfile ?? ResolveSelectableProfile(downloadProfile));
    }

    private List<DriverProfile> GetInstallProfilesFor(DriverProfile profile) => [profile];

    private void UpdateProfileCardText(DriverProfile profile)
    {
        profile.DownloadDisplayName = $"AMD {profile.MarketingVersion}";
        var mode = GetProfileMode(profile);
        profile.InstallModeTitle = mode.Title;
        profile.InstallModeDescription = mode.Detail;
    }

    private void OnSelectedProfileChanged()
    {
        _audit = null;
        _preparedRoot = null;
        if (SelectedProfile is { } profile)
        {
            ProfileStatusText.Text = profile.DisplayName;
            OutputPathBox.Text = $"C:\\AMD\\BootCampDriverStudio\\Prepared\\AMD-{profile.MarketingVersion}-{profile.Id.Split('-').Last()}";
            AdditionalSourcePanel.Visibility = profile.RequiresAdditionalSource ? Visibility.Visible : Visibility.Collapsed;
            if (profile.RequiresAdditionalSource)
            {
                var source = profile.AdditionalSources[0];
                AdditionalSourceLabel.Text = $"Additional official AMD package: {source.DisplayName}";
                AdditionalSourcePathBox.Text = _settings.AdditionalSourceFolders.TryGetValue(source.Id, out var saved)
                    ? saved
                    : string.Empty;
            }
            else
            {
                AdditionalSourcePathBox.Text = string.Empty;
            }
        }
        UpdateProfileModeUi();
    }

    private void UpdateProfileModeUi()
    {
        var profile = SelectedProfile;
        if (profile is null)
        {
            PackageProfileModeText.Text = _localization["install.mode.selectProfile"];
            PrepareProfileModeText.Text = _localization["install.mode.selectProfile"];
            InstallProfileModeText.Text = _localization["install.mode.selectInstallProfile"];
            EnableTestModeButton.IsEnabled = false;
            return;
        }

        var mode = GetProfileMode(profile);
        EnableTestModeButton.IsEnabled = mode.RequiresTestSigning;
        PrepareButton.Content = _localization["action.prepareSign"];
        EnableTestModeButton.Content = mode.RequiresTestSigning
            ? _localization["action.testMode"]
            : _localization["install.testSigningNotRequired"];

        var text = $"{profile.DisplayName}\n{_localization["install.modeLabel"]}: {mode.Title}\n{mode.Detail}";
        if (profile.InstallationMode.Equals("legacy-binary-patch", StringComparison.OrdinalIgnoreCase))
            text += $"\n\n{_localization["install.mode.binary.deprecated"]}";
        PackageProfileModeText.Text = text;
        PrepareProfileModeText.Text = text;
        InstallProfileModeText.Text = text;
        SecurityConsentText.Text = mode.Consent;
    }

    private (string Title, string Detail, string Consent, bool RequiresTestSigning) GetProfileMode(DriverProfile profile)
    {
        if (ProfileUsesBinaryPatch(profile))
        {
            return (
                _localization["install.mode.binary.title"],
                _localization["install.mode.binary.detail"],
                _localization["install.mode.binary.consent"],
                true);
        }

        return (
            _localization["install.mode.whql.title"],
            _localization["install.mode.whql.detail"],
            _localization["install.mode.whql.consent"],
            false);
    }

    private static bool ProfileUsesBinaryPatch(DriverProfile profile) => profile.UsesBinaryPatch;

    private static int ProfileSelectionPriority(DriverProfile profile) => profile.InstallationMode switch
    {
        "whql-anchor" => 0,
        _ when profile.UsesBinaryPatch => 99,
        _ => 50
    };

    private IReadOnlyDictionary<string, string>? GetSupplementalSourcePaths(DriverProfile profile)
    {
        if (!profile.RequiresAdditionalSource) return null;
        return profile.AdditionalSources.ToDictionary(
            source => source.Id,
            _ => AdditionalSourcePathBox.Text.Trim(),
            StringComparer.OrdinalIgnoreCase);
    }

    private DriverProfile RequireProfile() => SelectedProfile ?? throw new InvalidOperationException(_localization["message.profileRequired"]);

    private bool RequireConsent()
    {
        if (SecurityConsentCheck.IsChecked.GetValueOrDefault()) return true;
        ShowStatus(_localization["message.consentRequired"], InfoBarSeverity.Warning);
        return false;
    }

    private void RefreshBackups() => BackupList.ItemsSource = _system.ListBackups();

    private void ShowStatus(string message, InfoBarSeverity severity)
    {
        StatusInfoBar.Message = message;
        StatusInfoBar.Severity = severity;
        StatusInfoBar.IsOpen = true;
    }

    private async Task<bool> ConfirmAsync(string title, string body)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = MainNavigation.XamlRoot,
            Title = title,
            Content = body,
            PrimaryButtonText = _localization["action.continue"],
            CloseButtonText = _localization["action.cancel"],
            DefaultButton = ContentDialogButton.Close
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private static string FormatBytes(double bytes)
    {
        string[] units = ["B", "KB", "MB", "GB"];
        var value = Math.Max(0, bytes);
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }
        return $"{value:0.##} {units[unit]}";
    }

    private sealed class WinFormsWindow(nint handle) : System.Windows.Forms.IWin32Window
    {
        public nint Handle { get; } = handle;
    }

    private void Log_LineAdded(object? sender, string line)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            LogTextBox.Text += line + Environment.NewLine;
            if (LogTextBox.Text.Length > 120_000)
                LogTextBox.Text = LogTextBox.Text[^80_000..];
            LogTextBox.Select(LogTextBox.Text.Length, 0);
        });
    }
}
