using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            var root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            var logDir = Path.Combine(root, "logs");
            Directory.CreateDirectory(logDir);
            var launcherLog = Path.Combine(logDir, "launcher.log");
            var script = Path.Combine(root, "tools", "start-codex-switcher.ps1");
            if (!File.Exists(script))
            {
                MessageBox.Show(
                    "找不到启动脚本：\n" + script + "\n\n请确认整个 Codex 便捷启动器文件夹完整解压后再运行。",
                    "Codex 便捷启动器",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 2;
            }

            var pwsh = ResolvePowerShell();
            AppendLog(launcherLog, "Root: " + root);
            AppendLog(launcherLog, "PowerShell: " + pwsh);
            AppendLog(launcherLog, "Script: " + script);

            var stdoutLog = Path.Combine(logDir, "last-run.out.log");
            var stderrLog = Path.Combine(logDir, "last-run.err.log");
            TryDelete(stdoutLog);
            TryDelete(stderrLog);

            var arguments = new StringBuilder();
            arguments.Append("-Sta -NoProfile -ExecutionPolicy Bypass -File ");
            arguments.Append(Quote(script));
            foreach (var arg in args)
            {
                arguments.Append(' ');
                arguments.Append(Quote(arg));
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = pwsh,
                Arguments = arguments.ToString(),
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            startInfo.Environment["CODEX_SWITCHER_HOME"] = root;

            var process = Process.Start(startInfo);
            if (process == null)
            {
                throw new InvalidOperationException("未能创建 PowerShell 进程。");
            }

            AppendLog(launcherLog, "Started process: " + process.Id);
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) AppendLog(stdoutLog, e.Data);
            };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data != null) AppendLog(stderrLog, e.Data);
            };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            if (process.WaitForExit(2500))
            {
                AppendLog(launcherLog, "Process exited quickly. ExitCode: " + process.ExitCode);
                if (process.ExitCode != 0)
                {
                    process.WaitForExit();
                    var errorText = ReadShort(stderrLog);
                    if (string.IsNullOrWhiteSpace(errorText))
                    {
                        errorText = ReadShort(stdoutLog);
                    }

                    MessageBox.Show(
                        "Codex 切换器启动脚本退出过快，窗口没有打开。\n\n" +
                        "错误摘要：\n" + (string.IsNullOrWhiteSpace(errorText) ? "无输出。" : errorText) +
                        "\n\n日志目录：\n" + logDir,
                        "Codex 切换器",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return process.ExitCode;
                }
            }

            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Codex 切换器启动失败。\n\n请确认已安装 PowerShell 7、Windows Terminal 和 Codex CLI。\n\n" + ex.Message,
                "Codex 切换器",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static string ResolvePowerShell()
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(Path.PathSeparator))
        {
            if (string.IsNullOrWhiteSpace(dir))
            {
                continue;
            }

            var candidate = Path.Combine(dir.Trim(), "pwsh.exe");
            if (IsWindowsAppsAlias(candidate))
            {
                continue;
            }

            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        var windowsPowerShell = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        if (File.Exists(windowsPowerShell))
        {
            return windowsPowerShell;
        }

        return "pwsh.exe";
    }

    private static bool IsWindowsAppsAlias(string path)
    {
        return path.IndexOf(
            Path.Combine("AppData", "Local", "Microsoft", "WindowsApps"),
            StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static void AppendLog(string path, string message)
    {
        File.AppendAllText(
            path,
            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine,
            Encoding.UTF8);
    }

    private static string ReadShort(string path)
    {
        if (!File.Exists(path))
        {
            return "";
        }

        var text = File.ReadAllText(path, Encoding.UTF8).Trim();
        if (text.Length <= 1200)
        {
            return text;
        }

        return text.Substring(0, 1200) + Environment.NewLine + "...";
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }
}
