using System.Windows;
using System.Windows.Shell;

namespace NoteIt;

/// <summary>
/// Native Windows integration: system tray icon, jump list for recent files,
/// and single-instance enforcement.
/// </summary>
public sealed class WindowsIntegration : IDisposable
{
    private System.Windows.Forms.NotifyIcon? _trayIcon;
    private bool _disposed;

    /// <summary>Initializes the system tray icon and jump list. Call once at app startup.</summary>
    public void Initialize()
    {
        SetupTrayIcon();
        SetupJumpList();
    }

    // --- System Tray ---

    private void SetupTrayIcon()
    {
        try
        {
            _trayIcon = new System.Windows.Forms.NotifyIcon
            {
                Icon = CreateAppIcon(),
                Visible = true,
                Text = "NoteIt",
            };
            _trayIcon.DoubleClick += (_, _) => RestoreAllWindows();
            _trayIcon.MouseClick += (_, e) =>
            {
                if (e.Button == System.Windows.Forms.MouseButtons.Right)
                    _trayIcon.ContextMenuStrip?.Show(System.Windows.Forms.Cursor.Position);
            };
            BuildTrayContextMenu();
        }
        catch { }
    }

    private void BuildTrayContextMenu()
    {
        if (_trayIcon is null) return;
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("New Tab", null, (_, _) => ActivateMainWindow());
        menu.Items.Add("Open…", null, (_, _) => ActivateMainWindow());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        // Recent files submenu
        var recentItem = new System.Windows.Forms.ToolStripMenuItem("Open Recent");
        foreach (string p in App.Store.RecentFiles.Take(10).ToList())
        {
            recentItem.DropDownItems.Add(System.IO.Path.GetFileName(p), null,
                (_, _) => { App.Store.OpenPath(p); ActivateMainWindow(); });
        }
        menu.Items.Add(recentItem);
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => Application.Current.Shutdown());
        _trayIcon.ContextMenuStrip = menu;
    }

    private void RestoreAllWindows()
    {
        foreach (Window w in Application.Current.Windows)
        {
            w.Show();
            w.WindowState = WindowState.Normal;
            w.Activate();
        }
    }

    private void ActivateMainWindow()
    {
        var w = Application.Current.Windows.OfType<MainWindow>().FirstOrDefault();
        if (w is null)
        {
            w = new MainWindow();
            w.Show();
        }
        w.Show();
        if (w.WindowState == WindowState.Minimized)
            w.WindowState = WindowState.Normal;
        w.Activate();
    }

    /// <summary>Creates a simple icon for the system tray.</summary>
    private static System.Drawing.Icon CreateAppIcon()
    {
        try
        {
            return CreateTextIcon("N");
        }
        catch
        {
            return System.Drawing.SystemIcons.Application;
        }
    }

    private static System.Drawing.Icon CreateTextIcon(string text)
    {
        try
        {
            using var bmp = new System.Drawing.Bitmap(32, 32);
            using var g = System.Drawing.Graphics.FromImage(bmp);
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using var bg = new System.Drawing.Drawing2D.LinearGradientBrush(
                new System.Drawing.Rectangle(0, 0, 32, 32),
                System.Drawing.ColorTranslator.FromHtml("#0078D7"),
                System.Drawing.ColorTranslator.FromHtml("#005A9E"),
                90f);
            g.FillRectangle(bg, 0, 0, 32, 32);
            // Draw "N" centered
            using var font = new System.Drawing.Font("Segoe UI", 16f, System.Drawing.FontStyle.Bold);
            var sf = new System.Drawing.StringFormat
            {
                Alignment = System.Drawing.StringAlignment.Center,
                LineAlignment = System.Drawing.StringAlignment.Center,
            };
            g.DrawString(text, font, System.Drawing.Brushes.White, 16, 16, sf);
            var hIcon = bmp.GetHicon();
            return System.Drawing.Icon.FromHandle(hIcon);
        }
        catch
        {
            return System.Drawing.SystemIcons.Application;
        }
    }

    // --- Jump List ---

    private void SetupJumpList()
    {
        try
        {
            var jl = JumpList.GetJumpList(Application.Current);
            if (jl is null)
            {
                jl = new JumpList();
                JumpList.SetJumpList(Application.Current, jl);
            }
            jl.JumpItems.Clear();
            // Add recent files as jump tasks
            foreach (string p in App.Store.RecentFiles.Take(10).ToList())
            {
                var task = new JumpTask
                {
                    Title = System.IO.Path.GetFileName(p),
                    Description = p,
                    ApplicationPath = Environment.ProcessPath ?? "",
                    Arguments = $"\"{p}\"",
                };
                jl.JumpItems.Add(task);
            }
            jl.Apply();
        }
        catch { }
    }

    /// <summary>Refreshes the jump list with the latest recent files.</summary>
    public void RefreshJumpList()
    {
        SetupJumpList();
    }

    // --- Single Instance ---

    private static Mutex? _singleInstanceMutex;

    /// <summary>Returns false if another instance is already running.</summary>
    public static bool EnsureSingleInstance()
    {
        _singleInstanceMutex = new Mutex(true, "NoteIt_SingleInstance_Mutex", out bool createdNew);
        if (createdNew)
            return true;

        if (ActivateExistingInstance())
            return false;

        // A stale NoteIt process can exist without a window handle (tray-only / crashed instance).
        // In that case, allow a fresh launch instead of silently exiting.
        try
        {
            _singleInstanceMutex.ReleaseMutex();
        }
        catch { }
        _singleInstanceMutex.Dispose();
        _singleInstanceMutex = new Mutex(true, "NoteIt_SingleInstance_Mutex", out createdNew);
        return createdNew;
    }

    private static bool ActivateExistingInstance()
    {
        try
        {
            var processes = System.Diagnostics.Process.GetProcessesByName("NoteIt");
            foreach (var p in processes)
            {
                if (p.MainWindowHandle != IntPtr.Zero)
                {
                    // Restore if minimized
                    ShowWindow(p.MainWindowHandle, SW_RESTORE);
                    SetForegroundWindow(p.MainWindowHandle);
                    return true;
                }
            }

            // No visible window exists; clean up stale tray-only processes.
            foreach (var p in processes)
            {
                try { p.Kill(entireProcessTree: true); }
                catch { }
            }
        }
        catch { }
        return false;
    }

    private const int SW_RESTORE = 9;

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _trayIcon?.Dispose();
        _singleInstanceMutex?.Dispose();
    }
}
