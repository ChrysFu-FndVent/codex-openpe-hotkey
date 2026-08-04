using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using CodexOpenPEHotkey.Windows;

namespace CodexOpenPEHotkey.Setup
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }
    }

    internal sealed class SetupForm : Form
    {
        private const string MarketplaceName = "codex-openpe-hotkey";
        private const string PluginSelector = "codex-openpe-hotkey@codex-openpe-hotkey";
        private readonly TextBox apiKey = new TextBox();
        private readonly TextBox baseUrl = new TextBox();
        private readonly TextBox model = new TextBox();
        private readonly TextBox hotKey = new TextBox();
        private readonly ComboBox outputLanguage = new ComboBox();
        private readonly ComboBox progressLanguage = new ComboBox();
        private readonly Label status = new Label();
        private readonly ProgressBar progress = new ProgressBar();
        private readonly Button installButton = new Button();
        private readonly Button cancelButton = new Button();
        private bool installing;
        private bool installed;

        public SetupForm()
        {
            Text = "Set Up Codex OpenPE Hotkey";
            ClientSize = new Size(650, 500);
            MinimumSize = new Size(650, 500);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            BuildInterface();
            FormClosing += OnFormClosing;
        }

        private void BuildInterface()
        {
            Label title = new Label {
                Text = "Codex OpenPE Hotkey",
                AutoSize = true,
                Font = new Font(Font.FontFamily, 18, FontStyle.Bold),
                Margin = new Padding(0, 0, 0, 6)
            };
            Label subtitle = new Label {
                Text = "Configure prompt enhancement once. The helper then runs in the background.",
                AutoSize = true,
                ForeColor = SystemColors.GrayText,
                Margin = new Padding(0, 0, 0, 18)
            };

            apiKey.UseSystemPasswordChar = true;
            baseUrl.Text = "https://api.openai.com/v1";
            model.Text = "gpt-5.4-mini";
            hotKey.Text = "Alt+Q";
            outputLanguage.DropDownStyle = ComboBoxStyle.DropDownList;
            outputLanguage.Items.AddRange(new object[] { "Chinese", "English" });
            outputLanguage.SelectedIndex = 0;
            progressLanguage.DropDownStyle = ComboBoxStyle.DropDownList;
            progressLanguage.Items.AddRange(new object[] { "Chinese", "English" });
            progressLanguage.SelectedIndex = 0;

            TableLayoutPanel form = new TableLayoutPanel {
                AutoSize = true,
                ColumnCount = 2,
                RowCount = 6,
                Dock = DockStyle.Top,
                Margin = new Padding(0)
            };
            form.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
            form.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            AddRow(form, 0, "API key", apiKey);
            AddRow(form, 1, "API base URL", baseUrl);
            AddRow(form, 2, "Model", model);
            AddRow(form, 3, "Hotkey", hotKey);
            AddRow(form, 4, "Output language", outputLanguage);
            AddRow(form, 5, "Progress language", progressLanguage);

            progress.Style = ProgressBarStyle.Marquee;
            progress.MarqueeAnimationSpeed = 30;
            progress.Visible = false;
            progress.Width = 580;
            progress.Height = 8;
            progress.Margin = new Padding(0, 20, 0, 8);
            status.Text = "Ready to configure this PC.";
            status.AutoSize = true;
            status.Margin = new Padding(0, 0, 0, 16);

            installButton.Text = "Install";
            installButton.AutoSize = true;
            installButton.Click += Install;
            cancelButton.Text = "Cancel";
            cancelButton.AutoSize = true;
            cancelButton.Click += CancelSetup;
            FlowLayoutPanel buttons = new FlowLayoutPanel {
                AutoSize = true,
                FlowDirection = FlowDirection.RightToLeft,
                Dock = DockStyle.Top,
                Margin = new Padding(0)
            };
            buttons.Controls.Add(installButton);
            buttons.Controls.Add(cancelButton);

            TableLayoutPanel root = new TableLayoutPanel {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 6,
                Padding = new Padding(28, 24, 28, 20)
            };
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.Controls.Add(title, 0, 0);
            root.Controls.Add(subtitle, 0, 1);
            root.Controls.Add(form, 0, 2);
            root.Controls.Add(progress, 0, 3);
            root.Controls.Add(status, 0, 4);
            root.Controls.Add(buttons, 0, 5);
            Controls.Add(root);
            AcceptButton = installButton;
            CancelButton = cancelButton;
        }

        private static void AddRow(TableLayoutPanel panel, int row, string label, Control control)
        {
            control.Dock = DockStyle.Fill;
            control.Margin = new Padding(6, 5, 0, 5);
            panel.Controls.Add(new Label {
                Text = label,
                AutoSize = true,
                TextAlign = ContentAlignment.MiddleRight,
                Dock = DockStyle.Fill,
                Margin = new Padding(0, 8, 8, 5)
            }, 0, row);
            panel.Controls.Add(control, 1, row);
        }

        private async void Install(object sender, EventArgs eventArgs)
        {
            string normalizedHotKey;
            Uri parsedBaseUrl;
            try
            {
                if (String.IsNullOrWhiteSpace(apiKey.Text) || String.IsNullOrWhiteSpace(model.Text))
                {
                    throw new InvalidOperationException("API key and model are required.");
                }
                if (!Uri.TryCreate(baseUrl.Text.Trim(), UriKind.Absolute, out parsedBaseUrl) ||
                    (parsedBaseUrl.Scheme != Uri.UriSchemeHttp && parsedBaseUrl.Scheme != Uri.UriSchemeHttps))
                {
                    throw new InvalidOperationException("API base URL must be an absolute HTTP or HTTPS URL.");
                }
                normalizedHotKey = HotKeyBinding.Parse(hotKey.Text.Trim()).DisplayName;
            }
            catch (Exception error)
            {
                MessageBox.Show(this, error.Message, "Invalid configuration", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            SetupValues values = new SetupValues {
                ApiKey = apiKey.Text,
                BaseUrl = parsedBaseUrl.AbsoluteUri.TrimEnd('/'),
                Model = model.Text.Trim(),
                HotKey = normalizedHotKey,
                Language = outputLanguage.SelectedIndex == 0 ? "zh" : "en",
                ProgressLanguage = progressLanguage.SelectedIndex == 0 ? "zh" : "en"
            };
            SetInstalling(true);
            try
            {
                await Task.Run(delegate { Configure(values); });
                apiKey.Clear();
                installed = true;
                status.Text = "Installed and healthy. Select prompt text in Codex and press " + values.HotKey + ".";
                installButton.Text = "Finish";
                installButton.Click -= Install;
                installButton.Click += delegate { Close(); };
                cancelButton.Text = "Open Codex";
                cancelButton.Click -= CancelSetup;
                cancelButton.Click += OpenCodex;
            }
            catch (Exception error)
            {
                status.Text = "Installation did not complete.";
                MessageBox.Show(this, error.Message, "Setup failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                values.ApiKey = null;
                SetInstalling(false);
            }
        }

        private void Configure(SetupValues values)
        {
            Report("Saving credentials in Windows Credential Manager...");
            CredentialStore.Write(CredentialStore.ApiKeyTarget, values.ApiKey);
            string serverToken = CredentialStore.GenerateServerToken();
            try
            {
                CredentialStore.Write(CredentialStore.ServerTokenTarget, serverToken);
            }
            finally
            {
                serverToken = null;
            }

            Report("Writing local configuration...");
            string installDirectory = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
            string server = Path.Combine(installDirectory, "openpe-server.exe");
            if (!File.Exists(server))
            {
                throw new FileNotFoundException("The installer does not contain openpe-server.exe.", server);
            }
            Directory.CreateDirectory(AppPaths.DataDirectory);
            RuntimeConfiguration configuration = new RuntimeConfiguration {
                Endpoint = "http://127.0.0.1:18980/v1/prompt-enhance",
                RequestTimeoutSeconds = 75,
                AllowedProcessNames = "Codex,ChatGPT",
                ProgressLanguage = values.ProgressLanguage,
                OpenPEServerPath = server,
                ListenAddress = "127.0.0.1:18980",
                BaseUrl = values.BaseUrl,
                Model = values.Model,
                Language = values.Language,
                OpenPETimeout = "60s",
                SystemPrompt = "Rewrite the user request as a concise, actionable instruction for a coding agent. Preserve intent, facts, constraints, and language. Do not invent requirements. Output only the rewritten instruction.",
                HotKey = values.HotKey
            };
            configuration.Validate();
            string json = new JavaScriptSerializer().Serialize(configuration);
            File.WriteAllText(AppPaths.ConfigFile, json, new UTF8Encoding(false));

            Report("Installing the bundled Codex Plugin and Skill...");
            InstallCodexPlugin(installDirectory);

            Report("Starting background services...");
            StartHelper(installDirectory);
            WaitForHealth();
        }

        private static void InstallCodexPlugin(string installDirectory)
        {
            string codex = LocateCodexCli();
            if (codex == null)
            {
                throw new FileNotFoundException("Codex desktop is required. Install or update Codex, then run setup again.");
            }
            string marketplace = Path.Combine(installDirectory, "CodexPlugin");
            if (!File.Exists(Path.Combine(marketplace, ".agents", "plugins", "marketplace.json")))
            {
                throw new FileNotFoundException("The bundled Codex Plugin is missing.", marketplace);
            }
            CommandResult marketplaces = Run(codex, "plugin marketplace list --json");
            if (marketplaces.Output.IndexOf("\"name\": \"" + MarketplaceName + "\"", StringComparison.Ordinal) >= 0 ||
                marketplaces.Output.IndexOf("\"name\":\"" + MarketplaceName + "\"", StringComparison.Ordinal) >= 0)
            {
                TryRun(codex, "plugin marketplace remove " + MarketplaceName + " --json");
            }
            Run(codex, "plugin marketplace add " + Quote(marketplace) + " --json");
            CommandResult add = TryRun(codex, "plugin add " + PluginSelector + " --json");
            if (add.ExitCode != 0)
            {
                CommandResult installedPlugins = Run(codex, "plugin list --json");
                if (installedPlugins.Output.IndexOf("\"pluginId\": \"" + PluginSelector + "\"", StringComparison.Ordinal) < 0 &&
                    installedPlugins.Output.IndexOf("\"pluginId\":\"" + PluginSelector + "\"", StringComparison.Ordinal) < 0)
                {
                    throw new InvalidOperationException("The Codex Plugin could not be installed: " + add.Error);
                }
            }
        }

        private static string LocateCodexCli()
        {
            List<string> candidates = new List<string>();
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string programs = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            candidates.Add(Path.Combine(local, "Programs", "Codex", "resources", "codex.exe"));
            candidates.Add(Path.Combine(local, "Programs", "Codex", "Resources", "codex.exe"));
            candidates.Add(Path.Combine(local, "Programs", "ChatGPT", "resources", "codex.exe"));
            candidates.Add(Path.Combine(programs, "Codex", "resources", "codex.exe"));
            string path = Environment.GetEnvironmentVariable("PATH") ?? String.Empty;
            foreach (string entry in path.Split(Path.PathSeparator))
            {
                if (!String.IsNullOrWhiteSpace(entry)) candidates.Add(Path.Combine(entry.Trim(), "codex.exe"));
            }
            foreach (string candidate in candidates)
            {
                if (File.Exists(candidate)) return candidate;
            }
            return null;
        }

        private static void StartHelper(string installDirectory)
        {
            ProcessStartInfo start = new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "WindowsPowerShell", "v1.0", "powershell.exe"),
                Arguments = "-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File " +
                    Quote(Path.Combine(installDirectory, "start.ps1")),
                WorkingDirectory = installDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            Process.Start(start);
        }

        private static void WaitForHealth()
        {
            using (HttpClientHandler handler = new HttpClientHandler { UseProxy = false })
            using (HttpClient client = new HttpClient(handler))
            {
                client.Timeout = TimeSpan.FromSeconds(2);
                for (int attempt = 0; attempt < 30; attempt++)
                {
                    try
                    {
                        if (client.GetAsync("http://127.0.0.1:18980/healthz").GetAwaiter()
                            .GetResult().IsSuccessStatusCode) return;
                    }
                    catch
                    {
                    }
                    Thread.Sleep(300);
                }
            }
            throw new TimeoutException("The bundled openPE server did not pass its health check.");
        }

        private static CommandResult Run(string executable, string arguments)
        {
            CommandResult result = TryRun(executable, arguments);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException(Path.GetFileName(executable) + " failed: " + result.Error);
            }
            return result;
        }

        private static CommandResult TryRun(string executable, string arguments)
        {
            ProcessStartInfo start = new ProcessStartInfo {
                FileName = executable,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (Process process = Process.Start(start))
            {
                string output = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();
                return new CommandResult { ExitCode = process.ExitCode, Output = output, Error = error.Trim() };
            }
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private void Report(string message)
        {
            BeginInvoke(new Action(delegate { status.Text = message; }));
        }

        private void SetInstalling(bool value)
        {
            installing = value;
            progress.Visible = value;
            apiKey.Enabled = !value;
            baseUrl.Enabled = !value;
            model.Enabled = !value;
            hotKey.Enabled = !value;
            outputLanguage.Enabled = !value;
            progressLanguage.Enabled = !value;
            installButton.Enabled = !value;
            cancelButton.Enabled = !value || installed;
            ControlBox = !value;
        }

        private void OpenCodex(object sender, EventArgs eventArgs)
        {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string app = Path.Combine(local, "Programs", "Codex", "Codex.exe");
            if (File.Exists(app)) Process.Start(app);
        }

        private void OnFormClosing(object sender, FormClosingEventArgs eventArgs)
        {
            if (installing) eventArgs.Cancel = true;
        }

        private void CancelSetup(object sender, EventArgs eventArgs)
        {
            Close();
        }

        private sealed class SetupValues
        {
            public string ApiKey;
            public string BaseUrl;
            public string Model;
            public string HotKey;
            public string Language;
            public string ProgressLanguage;
        }

        private sealed class CommandResult
        {
            public int ExitCode;
            public string Output;
            public string Error;
        }
    }
}
