using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Shell;

namespace NoteIt;

public partial class App : Application
{
    /// <summary>Single shared store across all windows (parity with macOS shared app store).</summary>
    public static DocumentStore Store { get; } = new();

    // Track if this is the first window being created
    private static int _windowCount;
    private WindowsIntegration? _integration;

    private void OnStartup(object sender, StartupEventArgs e)
    {
        // Single-instance check: if already running, activate and exit
        if (!WindowsIntegration.EnsureSingleInstance())
        {
            Shutdown();
            return;
        }

        // Set up tray icon and jump list
        _integration = new WindowsIntegration();
        _integration.Initialize();

        // Set up the main window manually (not via StartupUri)
        var window = new MainWindow();
        _windowCount++;

        Store.Settings.PropertyChanged += (_, _) => ApplyTheme(Store.Settings.Appearance);
        Store.RecentFiles.CollectionChanged += (_, _) => _integration?.RefreshJumpList();

        // Open files passed on the command line (e.g. Open With...)
        foreach (string arg in e.Args)
        {
            try
            {
                if (System.IO.File.Exists(arg)) Store.OpenPath(System.IO.Path.GetFullPath(arg));
            }
            catch { }
        }

        ApplyTheme(Store.Settings.Appearance);
        window.Show();
    }

    public static void RegisterWindow()
    {
        _windowCount++;
    }

    public static void UnregisterWindow()
    {
        _windowCount--;
        if (_windowCount <= 0)
        {
            // Last window closing — quit the app (Windows convention)
            Application.Current?.Shutdown();
        }
    }

    public static void ApplyTheme(AppSettings.AppearanceMode appearance)
    {
        bool dark = appearance switch
        {
            AppSettings.AppearanceMode.Dark => true,
            AppSettings.AppearanceMode.Light => false,
            _ => IsSystemDark(),
        };
        Current?.Dispatcher.Invoke(() =>
        {
            // Editor
            SetBrush("NoteItEditorBackground", dark ? "#1E1E1E" : "#FFFFFF");
            SetBrush("NoteItEditorForeground", dark ? "#D4D4D4" : "#000000");

            // Chrome (menu, toolbar)
            SetBrush("NoteItChromeBackground", dark ? "#2B2B2B" : "#F6F6F6");
            SetBrush("NoteItChromeForeground", dark ? "#E0E0E0" : "#1A1A1A");

            // Gutter
            SetBrush("NoteItGutterBackground", dark ? "#252526" : "#F7F7F7");
            SetBrush("NoteItGutterForeground", dark ? "#858585" : "#808080");

            // Tab bar / title bar
            SetBrush("NoteItTabBackground", dark ? "#333333" : "#E0E0E0");
            SetBrush("NoteItTabForeground", dark ? "#CCCCCC" : "#3B3B3B");
            SetBrush("NoteItTabSelectedBackground", dark ? "#1E1E1E" : "#FFFFFF");
            SetBrush("NoteItTabSelectedForeground", dark ? "#FFFFFF" : "#1A1A1A");
            SetBrush("NoteItTabHoverBackground", dark ? "#3D3D3D" : "#D0D0D0");
            SetBrush("NoteItTitleBarBackground", dark ? "#202020" : "#E0E0E0");
            SetBrush("NoteItTitleBarForeground", dark ? "#FFFFFF" : "#1A1A1A");
            SetBrush("NoteItAccent", dark ? "#4DA3E8" : "#0078D7");

            // Separator
            SetBrush("NoteItSeparator", dark ? "#3F3F3F" : "#CFCFCF");

            // Status bar
            SetBrush("NoteItStatusBarBackground", dark ? "#2B2B2B" : "#F0F0F0");
            SetBrush("NoteItStatusBarForeground", dark ? "#999999" : "#5A5A5A");
            SetBrush("NoteItDisabledForeground", dark ? "#A1A1A1" : "#6D6D6D");

            // Apply Mica backdrop to all windows
            foreach (Window w in Current.Windows)
            {
                ApplyMicaBackdrop(w, dark);
            }
        });
    }

    private static void SetBrush(string key, string hex)
    {
        var app = Current;
        if (app is null) return;
        var color = (Color)ColorConverter.ConvertFromString(hex);
        app.Resources[key] = new SolidColorBrush(color);
    }

    // --- Mica / Acrylic backdrop via DWM ---
    // On Windows 11 (build 22000+), extends the desktop wallpaper tinting
    // behind the window for a truly native feel.

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int pvAttribute, int cbAttribute);

    private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    private const int DWMWA_SYSTEMBACKDROP_TYPE = 38;

    // Backdrop types for DWMWA_SYSTEMBACKDROP_TYPE
    private const int DWMSBT_AUTO = 0;    // Let Windows decide
    private const int DWMSBT_MAINWINDOW = 2; // Mica
    private const int DWMSBT_TRANSIENTWINDOW = 3; // Acrylic
    private const int DWMSBT_NONE = 1;

    public static void ApplyMicaBackdrop(Window window, bool dark)
    {
        try
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return;

            // Dark title bar
            int darkFlag = dark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkFlag, sizeof(int));

            // Mica backdrop
            int backdrop = DWMSBT_MAINWINDOW;
            DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ref backdrop, sizeof(int));
        }
        catch { }
    }

    /// <summary>Called by MainWindow on SourceInitialized to apply Mica + dark mode.</summary>
    public static void OnWindowSourceInitialized(Window window)
    {
        bool dark = Store.Settings.Appearance switch
        {
            AppSettings.AppearanceMode.Dark => true,
            AppSettings.AppearanceMode.Light => false,
            _ => IsSystemDark(),
        };
        ApplyMicaBackdrop(window, dark);
    }

    private static bool IsSystemDark()
    {
        try
        {
            using var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var v = k?.GetValue("AppsUseLightTheme");
            return v is int i && i == 0;
        }
        catch { return false; }
    }
}
