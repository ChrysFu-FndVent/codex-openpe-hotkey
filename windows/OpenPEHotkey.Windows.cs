using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using System.Windows.Forms;
using System.Web.Script.Serialization;

namespace CodexOpenPEHotkey.Windows
{
    public sealed class RuntimeConfiguration
    {
        public string Endpoint { get; set; }
        public int RequestTimeoutSeconds { get; set; }
        public string AllowedProcessNames { get; set; }
        public string ProgressLanguage { get; set; }
        public string OpenPEServerPath { get; set; }
        public string ListenAddress { get; set; }
        public string BaseUrl { get; set; }
        public string Model { get; set; }
        public string Language { get; set; }
        public string OpenPETimeout { get; set; }
        public string SystemPrompt { get; set; }
        public string HotKey { get; set; }

        public static RuntimeConfiguration Load(string path)
        {
            if (!File.Exists(path))
            {
                throw new FileNotFoundException("Windows configuration is missing", path);
            }

            RuntimeConfiguration configuration = new JavaScriptSerializer()
                .Deserialize<RuntimeConfiguration>(File.ReadAllText(path, Encoding.UTF8));
            if (String.IsNullOrWhiteSpace(configuration.HotKey))
            {
                configuration.HotKey = "Alt+Q";
            }
            configuration.Validate();
            return configuration;
        }

        public void Validate()
        {
            Uri endpoint;
            if (!Uri.TryCreate(Endpoint, UriKind.Absolute, out endpoint) ||
                (endpoint.Scheme != Uri.UriSchemeHttp && endpoint.Scheme != Uri.UriSchemeHttps) ||
                !endpoint.IsLoopback)
            {
                throw new InvalidOperationException("Endpoint must be an absolute loopback HTTP URL");
            }
            if (RequestTimeoutSeconds <= 0)
            {
                throw new InvalidOperationException("RequestTimeoutSeconds must be positive");
            }
            if (GetAllowedProcessNames().Count == 0)
            {
                throw new InvalidOperationException("AllowedProcessNames must not be empty");
            }
            if (String.IsNullOrWhiteSpace(OpenPEServerPath) || !File.Exists(OpenPEServerPath))
            {
                throw new FileNotFoundException("openpe-server.exe was not found", OpenPEServerPath);
            }
            if (String.IsNullOrWhiteSpace(ListenAddress) || ListenAddress.IndexOfAny(new[] { '\r', '\n' }) >= 0)
            {
                throw new InvalidOperationException("ListenAddress is invalid");
            }
            RequireSingleLine(BaseUrl, "BaseUrl");
            RequireSingleLine(Model, "Model");
            RequireSingleLine(Language, "Language");
            RequireSingleLine(OpenPETimeout, "OpenPETimeout");
            RequireSingleLine(SystemPrompt, "SystemPrompt");
            HotKeyBinding.Parse(HotKey);
            Uri baseUri;
            if (!Uri.TryCreate(BaseUrl, UriKind.Absolute, out baseUri) ||
                (baseUri.Scheme != Uri.UriSchemeHttp && baseUri.Scheme != Uri.UriSchemeHttps))
            {
                throw new InvalidOperationException("BaseUrl must be an absolute HTTP or HTTPS URL");
            }
        }

        public HashSet<string> GetAllowedProcessNames()
        {
            HashSet<string> result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string item in (AllowedProcessNames ?? String.Empty).Split(','))
            {
                string value = item.Trim();
                if (value.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                {
                    value = value.Substring(0, value.Length - 4);
                }
                if (value.Length > 0)
                {
                    result.Add(value);
                }
            }
            return result;
        }

        public HotKeyBinding GetHotKeyBinding()
        {
            return HotKeyBinding.Parse(String.IsNullOrWhiteSpace(HotKey) ? "Alt+Q" : HotKey);
        }

        private static void RequireSingleLine(string value, string name)
        {
            if (String.IsNullOrWhiteSpace(value) || value.IndexOfAny(new[] { '\r', '\n' }) >= 0)
            {
                throw new InvalidOperationException(name + " must be a non-empty single-line value");
            }
        }
    }

    public sealed class HotKeyBinding
    {
        private const uint ModAlt = 0x0001;
        private const uint ModControl = 0x0002;
        private const uint ModShift = 0x0004;
        private const uint ModWin = 0x0008;

        public uint Modifiers { get; private set; }
        public uint VirtualKey { get; private set; }
        public string DisplayName { get; private set; }

        public static HotKeyBinding Parse(string value)
        {
            if (String.IsNullOrWhiteSpace(value) || value.IndexOfAny(new[] { '\r', '\n' }) >= 0)
            {
                throw new InvalidOperationException("HotKey must not be empty");
            }
            string[] parts = value.Split('+');
            if (parts.Length < 2)
            {
                throw Invalid(value);
            }

            uint modifiers = 0;
            uint virtualKey = 0;
            string keyName = null;
            foreach (string rawPart in parts)
            {
                string part = rawPart.Trim().ToLowerInvariant();
                uint modifier = ParseModifier(part);
                if (modifier != 0)
                {
                    if ((modifiers & modifier) != 0)
                    {
                        throw Invalid(value);
                    }
                    modifiers |= modifier;
                    continue;
                }
                if (keyName != null || !TryParseKey(part, out virtualKey, out keyName))
                {
                    throw Invalid(value);
                }
            }
            if (modifiers == 0 || keyName == null)
            {
                throw Invalid(value);
            }

            List<string> displayParts = new List<string>();
            if ((modifiers & ModControl) != 0) displayParts.Add("Ctrl");
            if ((modifiers & ModAlt) != 0) displayParts.Add("Alt");
            if ((modifiers & ModShift) != 0) displayParts.Add("Shift");
            if ((modifiers & ModWin) != 0) displayParts.Add("Win");
            displayParts.Add(keyName);
            return new HotKeyBinding {
                Modifiers = modifiers,
                VirtualKey = virtualKey,
                DisplayName = String.Join("+", displayParts)
            };
        }

        private static uint ParseModifier(string value)
        {
            switch (value)
            {
                case "alt":
                case "option": return ModAlt;
                case "ctrl":
                case "control": return ModControl;
                case "shift": return ModShift;
                case "win":
                case "windows": return ModWin;
                default: return 0;
            }
        }

        private static bool TryParseKey(string value, out uint virtualKey, out string keyName)
        {
            virtualKey = 0;
            keyName = null;
            if (value.Length == 1)
            {
                char key = Char.ToUpperInvariant(value[0]);
                if ((key >= 'A' && key <= 'Z') || (key >= '0' && key <= '9'))
                {
                    virtualKey = key;
                    keyName = key.ToString();
                    return true;
                }
            }
            if (value.StartsWith("f", StringComparison.Ordinal) && value.Length <= 3)
            {
                int functionNumber;
                if (Int32.TryParse(value.Substring(1), out functionNumber) &&
                    functionNumber >= 1 && functionNumber <= 12)
                {
                    virtualKey = (uint)(0x70 + functionNumber - 1);
                    keyName = "F" + functionNumber;
                    return true;
                }
            }
            return false;
        }

        private static InvalidOperationException Invalid(string value)
        {
            return new InvalidOperationException(
                "Invalid HotKey '" + value +
                "'. Use at least one modifier plus A-Z, 0-9, or F1-F12.");
        }
    }

    public static class AppPaths
    {
        public static readonly string DataDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexOpenPEHotkey");
        public static readonly string ConfigFile = Path.Combine(DataDirectory, "config.json");
        public static readonly string HotkeyPidFile = Path.Combine(DataDirectory, "hotkey.pid");
        public static readonly string ServerPidFile = Path.Combine(DataDirectory, "server.pid");
        public static readonly string HotkeyLogFile = Path.Combine(DataDirectory, "hotkey-error.log");
        public static readonly string ServerLogFile = Path.Combine(DataDirectory, "openpe-server.log");
    }

    public static class ProgressText
    {
        private static readonly string[] Frames = {
            "\u280b", "\u2819", "\u2839", "\u2838", "\u283c",
            "\u2834", "\u2826", "\u2827", "\u2807", "\u280f"
        };

        public static string Build(int elapsedSeconds, int frameIndex, string language)
        {
            int elapsed = Math.Max(0, elapsedSeconds);
            int frame = Math.Max(0, frameIndex) % Frames.Length;
            bool chinese = (language ?? String.Empty).StartsWith("zh", StringComparison.OrdinalIgnoreCase);
            string message;
            if (chinese)
            {
                message = elapsed < 15 ? "\u6b63\u5728\u4f18\u5316" :
                    (elapsed < 45 ? "\u4ecd\u5728\u751f\u6210" : "\u7f51\u7edc\u8f83\u6162");
            }
            else
            {
                message = elapsed < 15 ? "Optimizing" :
                    (elapsed < 45 ? "Still generating" : "Network is slow");
            }
            return "[OpenPE " + Frames[frame] + "] " + message + " " + elapsed + "s";
        }
    }

    public static class TextReplacement
    {
        public static string Apply(string fullText, int start, int length, string replacement)
        {
            if (fullText == null || replacement == null || start < 0 || length < 0 ||
                start > fullText.Length || start + length > fullText.Length)
            {
                throw new ArgumentOutOfRangeException("Selected text range is invalid");
            }
            return fullText.Substring(0, start) + replacement + fullText.Substring(start + length);
        }
    }

    public static class CredentialStore
    {
        public const string ApiKeyTarget = "com.openpe.promptenhancer.api-key";
        public const string ServerTokenTarget = "com.openpe.promptenhancer.server-token";
        private const uint CredentialTypeGeneric = 1;
        private const uint PersistLocalMachine = 2;
        private const int ErrorNotFound = 1168;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NativeCredential
        {
            public uint Flags;
            public uint Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(ref NativeCredential credential, uint flags);

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(string target, uint type, uint flags);

        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);

        public static void Write(string target, string secret)
        {
            if (String.IsNullOrWhiteSpace(target) || String.IsNullOrEmpty(secret))
            {
                throw new ArgumentException("Credential target and secret are required");
            }
            byte[] secretBytes = Encoding.Unicode.GetBytes(secret);
            if (secretBytes.Length > 2560)
            {
                throw new ArgumentException("Credential is too large for Windows Credential Manager");
            }

            IntPtr blob = Marshal.AllocCoTaskMem(secretBytes.Length);
            try
            {
                Marshal.Copy(secretBytes, 0, blob, secretBytes.Length);
                NativeCredential credential = new NativeCredential();
                credential.Type = CredentialTypeGeneric;
                credential.TargetName = target;
                credential.CredentialBlobSize = (uint)secretBytes.Length;
                credential.CredentialBlob = blob;
                credential.Persist = PersistLocalMachine;
                credential.UserName = Environment.UserName;
                if (!CredWrite(ref credential, 0))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not write Windows credential");
                }
            }
            finally
            {
                for (int index = 0; index < secretBytes.Length; index++)
                {
                    Marshal.WriteByte(blob, index, 0);
                    secretBytes[index] = 0;
                }
                Marshal.FreeCoTaskMem(blob);
            }
        }

        public static string Read(string target)
        {
            IntPtr pointer;
            if (!CredRead(target, CredentialTypeGeneric, 0, out pointer))
            {
                int error = Marshal.GetLastWin32Error();
                if (error == ErrorNotFound)
                {
                    return null;
                }
                throw new Win32Exception(error, "Could not read Windows credential");
            }
            try
            {
                NativeCredential credential = (NativeCredential)Marshal.PtrToStructure(
                    pointer,
                    typeof(NativeCredential));
                return Marshal.PtrToStringUni(
                    credential.CredentialBlob,
                    (int)credential.CredentialBlobSize / 2);
            }
            finally
            {
                CredFree(pointer);
            }
        }

        public static void Delete(string target)
        {
            if (!CredDelete(target, CredentialTypeGeneric, 0))
            {
                int error = Marshal.GetLastWin32Error();
                if (error != ErrorNotFound)
                {
                    throw new Win32Exception(error, "Could not delete Windows credential");
                }
            }
        }

        public static string GenerateServerToken()
        {
            byte[] bytes = new byte[32];
            using (RandomNumberGenerator generator = RandomNumberGenerator.Create())
            {
                generator.GetBytes(bytes);
            }
            StringBuilder result = new StringBuilder(bytes.Length * 2);
            foreach (byte value in bytes)
            {
                result.Append(value.ToString("x2"));
            }
            Array.Clear(bytes, 0, bytes.Length);
            return result.ToString();
        }
    }

    internal static class Diagnostics
    {
        private static readonly object Gate = new object();

        public static void Log(string message)
        {
            try
            {
                Directory.CreateDirectory(AppPaths.DataDirectory);
                lock (Gate)
                {
                    File.AppendAllText(
                        AppPaths.HotkeyLogFile,
                        DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine,
                        Encoding.UTF8);
                }
            }
            catch
            {
            }
        }
    }

    internal sealed class ServerProcess : IDisposable
    {
        private readonly RuntimeConfiguration configuration;
        private Process ownedProcess;
        private bool ownsPidFile;

        public ServerProcess(RuntimeConfiguration configuration)
        {
            this.configuration = configuration;
        }

        public void EnsureRunning()
        {
            if (IsHealthy())
            {
                Diagnostics.Log("openpe-server already healthy");
                return;
            }

            string apiKey = CredentialStore.Read(CredentialStore.ApiKeyTarget);
            string serverToken = CredentialStore.Read(CredentialStore.ServerTokenTarget);
            if (String.IsNullOrEmpty(apiKey) || String.IsNullOrEmpty(serverToken))
            {
                throw new InvalidOperationException("OpenPE credentials are missing from Windows Credential Manager");
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = configuration.OpenPEServerPath;
            startInfo.Arguments = "--listen " + QuoteArgument(configuration.ListenAddress);
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.EnvironmentVariables["OPENPE_API_KEY"] = apiKey;
            startInfo.EnvironmentVariables["OPENPE_SERVER_TOKEN"] = serverToken;
            startInfo.EnvironmentVariables["OPENPE_BASE_URL"] = configuration.BaseUrl;
            startInfo.EnvironmentVariables["OPENPE_MODEL"] = configuration.Model;
            startInfo.EnvironmentVariables["OPENPE_LANGUAGE"] = configuration.Language;
            startInfo.EnvironmentVariables["OPENPE_TIMEOUT"] = configuration.OpenPETimeout;
            startInfo.EnvironmentVariables["OPENPE_SYSTEM_PROMPT"] = configuration.SystemPrompt;

            ownedProcess = new Process();
            ownedProcess.StartInfo = startInfo;
            ownedProcess.EnableRaisingEvents = true;
            ownedProcess.OutputDataReceived += LogServerOutput;
            ownedProcess.ErrorDataReceived += LogServerOutput;
            if (!ownedProcess.Start())
            {
                throw new InvalidOperationException("openpe-server could not be started");
            }
            File.WriteAllText(AppPaths.ServerPidFile, ownedProcess.Id.ToString(), Encoding.ASCII);
            ownsPidFile = true;
            ownedProcess.BeginOutputReadLine();
            ownedProcess.BeginErrorReadLine();

            apiKey = null;
            serverToken = null;
            for (int attempt = 0; attempt < 40; attempt++)
            {
                if (ownedProcess.HasExited)
                {
                    throw new InvalidOperationException("openpe-server exited during startup");
                }
                if (IsHealthy())
                {
                    Diagnostics.Log("openpe-server started");
                    return;
                }
                Thread.Sleep(250);
            }
            throw new TimeoutException("openpe-server health check timed out");
        }

        public bool IsHealthy()
        {
            try
            {
                Uri endpoint = new Uri(configuration.Endpoint);
                Uri health = new Uri(endpoint.GetLeftPart(UriPartial.Authority) + "/healthz");
                Uri info = new Uri(endpoint.GetLeftPart(UriPartial.Authority) + "/v1/info");
                using (HttpClientHandler handler = new HttpClientHandler())
                {
                    handler.UseProxy = false;
                    using (HttpClient client = new HttpClient(handler))
                    {
                        client.Timeout = TimeSpan.FromSeconds(2);
                        HttpResponseMessage response = client.GetAsync(health).GetAwaiter().GetResult();
                        if (!response.IsSuccessStatusCode)
                        {
                            return false;
                        }
                        string healthBody = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                        Dictionary<string, object> healthResult = new JavaScriptSerializer()
                            .Deserialize<Dictionary<string, object>>(healthBody);
                        object status;
                        if (!healthResult.TryGetValue("status", out status) ||
                            !String.Equals(status == null ? null : status.ToString(), "ok", StringComparison.OrdinalIgnoreCase))
                        {
                            return false;
                        }

                        string token = CredentialStore.Read(CredentialStore.ServerTokenTarget);
                        if (String.IsNullOrEmpty(token))
                        {
                            return false;
                        }
                        client.DefaultRequestHeaders.Authorization =
                            new AuthenticationHeaderValue("Bearer", token);
                        HttpResponseMessage infoResponse = client.GetAsync(info).GetAwaiter().GetResult();
                        return infoResponse.IsSuccessStatusCode;
                    }
                }
            }
            catch
            {
                return false;
            }
        }

        public void Dispose()
        {
            if (ownedProcess != null)
            {
                try
                {
                    if (!ownedProcess.HasExited)
                    {
                        ownedProcess.Kill();
                        ownedProcess.WaitForExit(3000);
                    }
                }
                catch
                {
                }
                ownedProcess.Dispose();
                ownedProcess = null;
            }
            try
            {
                if (ownsPidFile && File.Exists(AppPaths.ServerPidFile))
                {
                    File.Delete(AppPaths.ServerPidFile);
                }
            }
            catch
            {
            }
        }

        private static string QuoteArgument(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static void LogServerOutput(object sender, DataReceivedEventArgs args)
        {
            if (String.IsNullOrEmpty(args.Data))
            {
                return;
            }
            try
            {
                File.AppendAllText(
                    AppPaths.ServerLogFile,
                    DateTimeOffset.Now.ToString("o") + " " + args.Data + Environment.NewLine,
                    Encoding.UTF8);
            }
            catch
            {
            }
        }
    }

    internal sealed class OpenPEClient
    {
        private readonly RuntimeConfiguration configuration;

        public OpenPEClient(RuntimeConfiguration configuration)
        {
            this.configuration = configuration;
        }

        public string Enhance(string prompt)
        {
            string token = CredentialStore.Read(CredentialStore.ServerTokenTarget);
            if (String.IsNullOrEmpty(token))
            {
                throw new InvalidOperationException("OpenPE server token is missing");
            }

            Dictionary<string, object> requestObject = new Dictionary<string, object>();
            requestObject["prompt"] = prompt;
            requestObject["client"] = "codex";
            requestObject["mode"] = "agent";
            string json = new JavaScriptSerializer().Serialize(requestObject);

            using (HttpClientHandler handler = new HttpClientHandler())
            {
                handler.UseProxy = false;
                using (HttpClient client = new HttpClient(handler))
                {
                    client.Timeout = TimeSpan.FromSeconds(configuration.RequestTimeoutSeconds);
                    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
                    using (StringContent content = new StringContent(json, Encoding.UTF8, "application/json"))
                    {
                        HttpResponseMessage response = client
                            .PostAsync(configuration.Endpoint, content)
                            .GetAwaiter()
                            .GetResult();
                        string body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                        if (!response.IsSuccessStatusCode)
                        {
                            throw new InvalidOperationException("OpenPE returned HTTP " + (int)response.StatusCode);
                        }
                        Dictionary<string, object> result = new JavaScriptSerializer()
                            .Deserialize<Dictionary<string, object>>(body);
                        object value;
                        if (!result.TryGetValue("enhanced_prompt", out value) || value == null ||
                            String.IsNullOrWhiteSpace(value.ToString()))
                        {
                            throw new InvalidOperationException("OpenPE returned an empty enhanced_prompt");
                        }
                        return value.ToString().Trim();
                    }
                }
            }
        }
    }

    internal sealed class InlineSelectionSlot
    {
        public int ProcessId { get; private set; }
        public string OriginalText { get; private set; }

        private readonly AutomationElement element;
        private readonly int startOffset;
        private string displayedText;
        private string expectedDocument;

        private InlineSelectionSlot(
            AutomationElement element,
            int processId,
            string originalText,
            string document,
            int startOffset)
        {
            this.element = element;
            ProcessId = processId;
            OriginalText = originalText;
            displayedText = originalText;
            expectedDocument = document;
            this.startOffset = startOffset;
        }

        public static InlineSelectionSlot Capture(string hotKeyDisplayName)
        {
            AutomationElement element = AutomationElement.FocusedElement;
            if (element == null)
            {
                throw new InvalidOperationException("Focused text control is unavailable");
            }
            object textObject;
            object valueObject;
            if (!element.TryGetCurrentPattern(TextPattern.Pattern, out textObject) ||
                !element.TryGetCurrentPattern(ValuePattern.Pattern, out valueObject))
            {
                throw new InvalidOperationException("Focused control does not support inline UI Automation replacement");
            }
            ValuePattern valuePattern = (ValuePattern)valueObject;
            if (valuePattern.Current.IsReadOnly)
            {
                throw new InvalidOperationException("Focused control is read-only");
            }
            TextPattern textPattern = (TextPattern)textObject;
            TextPatternRange[] selections = textPattern.GetSelection();
            if (selections == null || selections.Length != 1)
            {
                throw new InvalidOperationException(
                    "Select exactly one prompt range before pressing " + hotKeyDisplayName);
            }
            string selectedText = selections[0].GetText(-1);
            if (String.IsNullOrWhiteSpace(selectedText))
            {
                throw new InvalidOperationException(
                    "Select prompt text before pressing " + hotKeyDisplayName);
            }
            string document = textPattern.DocumentRange.GetText(-1);
            int offset = GetStartOffset(textPattern, selections[0]);
            if (offset < 0 || offset + selectedText.Length > document.Length ||
                !String.Equals(document.Substring(offset, selectedText.Length), selectedText, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Selected range could not be mapped to the prompt text");
            }
            return new InlineSelectionSlot(element, element.Current.ProcessId, selectedText, document, offset);
        }

        public bool ReplaceProgress(string text)
        {
            return Replace(text, true, true);
        }

        public bool ReplaceFinal(string text)
        {
            return Replace(text, false, true);
        }

        public bool RestoreOriginal(bool updateSelection)
        {
            return Replace(OriginalText, false, updateSelection);
        }

        public bool RestoreDocumentIfUnchanged()
        {
            return Replace(OriginalText, false, false);
        }

        private bool Replace(string text, bool selectReplacement, bool requireOwnedSelection)
        {
            string currentDocument;
            TextPattern currentTextPattern;
            ValuePattern currentValuePattern;
            if (!TryGetPatterns(out currentTextPattern, out currentValuePattern, out currentDocument) ||
                !String.Equals(currentDocument, expectedDocument, StringComparison.Ordinal))
            {
                return false;
            }
            if (requireOwnedSelection && !OwnsSelection(currentTextPattern))
            {
                return false;
            }

            string previousDocument = expectedDocument;
            string nextDocument = TextReplacement.Apply(
                currentDocument,
                startOffset,
                displayedText.Length,
                text);
            try
            {
                currentValuePattern.SetValue(nextDocument);
                if (selectReplacement)
                {
                    if (!SelectRange(startOffset, text.Length, false))
                    {
                        Rollback(previousDocument);
                        return false;
                    }
                }
                else if (requireOwnedSelection && !SelectRange(startOffset + text.Length, 0, true))
                {
                    Rollback(previousDocument);
                    return false;
                }

                displayedText = text;
                expectedDocument = nextDocument;
                return true;
            }
            catch
            {
                Rollback(previousDocument);
                return false;
            }
        }

        private bool OwnsSelection(TextPattern textPattern)
        {
            try
            {
                TextPatternRange[] selections = textPattern.GetSelection();
                return selections != null && selections.Length == 1 &&
                    GetStartOffset(textPattern, selections[0]) == startOffset &&
                    String.Equals(selections[0].GetText(-1), displayedText, StringComparison.Ordinal);
            }
            catch
            {
                return false;
            }
        }

        private bool TryGetPatterns(
            out TextPattern textPattern,
            out ValuePattern valuePattern,
            out string document)
        {
            textPattern = null;
            valuePattern = null;
            document = null;
            try
            {
                object textObject;
                object valueObject;
                if (!element.TryGetCurrentPattern(TextPattern.Pattern, out textObject) ||
                    !element.TryGetCurrentPattern(ValuePattern.Pattern, out valueObject))
                {
                    return false;
                }
                textPattern = (TextPattern)textObject;
                valuePattern = (ValuePattern)valueObject;
                document = textPattern.DocumentRange.GetText(-1);
                return true;
            }
            catch
            {
                return false;
            }
        }

        private bool SelectRange(int start, int length, bool collapse)
        {
            try
            {
                object textObject;
                if (!element.TryGetCurrentPattern(TextPattern.Pattern, out textObject))
                {
                    return false;
                }
                TextPattern textPattern = (TextPattern)textObject;
                TextPatternRange document = textPattern.DocumentRange;
                TextPatternRange range = document.Clone();
                range.MoveEndpointByRange(
                    TextPatternRangeEndpoint.End,
                    document,
                    TextPatternRangeEndpoint.Start);
                int endMoved = range.MoveEndpointByUnit(
                    TextPatternRangeEndpoint.End,
                    TextUnit.Character,
                    start + length);
                if (endMoved != start + length)
                {
                    return false;
                }
                if (collapse)
                {
                    range.MoveEndpointByRange(
                        TextPatternRangeEndpoint.Start,
                        range,
                        TextPatternRangeEndpoint.End);
                }
                else
                {
                    int startMoved = range.MoveEndpointByUnit(
                        TextPatternRangeEndpoint.Start,
                        TextUnit.Character,
                        start);
                    if (startMoved != start)
                    {
                        return false;
                    }
                }
                range.Select();
                return true;
            }
            catch
            {
                return false;
            }
        }

        private void Rollback(string previousDocument)
        {
            try
            {
                object valueObject;
                if (element.TryGetCurrentPattern(ValuePattern.Pattern, out valueObject))
                {
                    ((ValuePattern)valueObject).SetValue(previousDocument);
                    SelectRange(startOffset, displayedText.Length, false);
                }
            }
            catch
            {
            }
        }

        private static int GetStartOffset(TextPattern textPattern, TextPatternRange selection)
        {
            TextPatternRange prefix = textPattern.DocumentRange.Clone();
            prefix.MoveEndpointByRange(
                TextPatternRangeEndpoint.End,
                selection,
                TextPatternRangeEndpoint.Start);
            return prefix.GetText(-1).Length;
        }
    }

    internal sealed class ActiveSession
    {
        public InlineSelectionSlot Slot;
        public IntPtr ExpectedWindow;
        public int ExpectedProcessId;
        public DateTime StartedAt;
        public int FrameIndex;
        public bool InlineActive;
        public System.Windows.Forms.Timer Timer;
    }

    internal sealed class HotKeyWindow : NativeWindow, IDisposable
    {
        private const int HotKeyMessage = 0x0312;
        private const uint ModNoRepeat = 0x4000;
        private const int HotKeyIdentifier = 1;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint virtualKey);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr window, int id);

        public event EventHandler Pressed;

        public HotKeyWindow(HotKeyBinding binding)
        {
            CreateHandle(new CreateParams());
            if (!RegisterHotKey(
                Handle,
                HotKeyIdentifier,
                binding.Modifiers | ModNoRepeat,
                binding.VirtualKey))
            {
                int error = Marshal.GetLastWin32Error();
                DestroyHandle();
                throw new Win32Exception(error, "Could not register " + binding.DisplayName);
            }
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == HotKeyMessage && message.WParam.ToInt32() == HotKeyIdentifier)
            {
                EventHandler handler = Pressed;
                if (handler != null)
                {
                    handler(this, EventArgs.Empty);
                }
            }
            base.WndProc(ref message);
        }

        public void Dispose()
        {
            if (Handle != IntPtr.Zero)
            {
                UnregisterHotKey(Handle, HotKeyIdentifier);
                DestroyHandle();
            }
        }
    }

    internal sealed class HotKeyApplication : ApplicationContext
    {
        private readonly RuntimeConfiguration configuration;
        private readonly HashSet<string> allowedProcessNames;
        private readonly OpenPEClient client;
        private readonly ServerProcess server;
        private readonly HotKeyWindow hotKeyWindow;
        private readonly Control dispatcher;
        private readonly string hotKeyDisplayName;
        private ActiveSession activeSession;

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        public HotKeyApplication(RuntimeConfiguration configuration)
        {
            this.configuration = configuration;
            allowedProcessNames = configuration.GetAllowedProcessNames();
            HotKeyBinding hotKeyBinding = configuration.GetHotKeyBinding();
            hotKeyDisplayName = hotKeyBinding.DisplayName;
            client = new OpenPEClient(configuration);
            server = new ServerProcess(configuration);
            try
            {
                dispatcher = new Control();
                dispatcher.CreateControl();
                hotKeyWindow = new HotKeyWindow(hotKeyBinding);
                hotKeyWindow.Pressed += HandleHotKey;
                server.EnsureRunning();
                Diagnostics.Log("Windows hotkey helper started with " + hotKeyDisplayName);
            }
            catch
            {
                if (hotKeyWindow != null)
                {
                    hotKeyWindow.Dispose();
                }
                if (dispatcher != null)
                {
                    dispatcher.Dispose();
                }
                server.Dispose();
                throw;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                CancelActiveSession();
                hotKeyWindow.Dispose();
                dispatcher.Dispose();
                server.Dispose();
            }
            base.Dispose(disposing);
        }

        private void HandleHotKey(object sender, EventArgs eventArgs)
        {
            if (activeSession != null)
            {
                Diagnostics.Log("ignored " + hotKeyDisplayName + " while a request is active");
                System.Media.SystemSounds.Beep.Play();
                return;
            }

            IntPtr foregroundWindow;
            int processId;
            string processName;
            if (!TryGetForegroundApplication(out foregroundWindow, out processId, out processName) ||
                !allowedProcessNames.Contains(processName))
            {
                Diagnostics.Log("foreground application is not allowed");
                System.Media.SystemSounds.Beep.Play();
                return;
            }

            try
            {
                InlineSelectionSlot slot = InlineSelectionSlot.Capture(hotKeyDisplayName);
                if (slot.ProcessId != processId)
                {
                    throw new InvalidOperationException("Focused text control does not belong to the foreground application");
                }
                string prompt = slot.OriginalText.Trim();
                ActiveSession session = new ActiveSession();
                session.Slot = slot;
                session.ExpectedWindow = foregroundWindow;
                session.ExpectedProcessId = processId;
                session.StartedAt = DateTime.UtcNow;
                session.FrameIndex = 0;
                string initialProgress = ProgressText.Build(0, 0, configuration.ProgressLanguage);
                if (!slot.ReplaceProgress(initialProgress))
                {
                    throw new InvalidOperationException("Selected text could not be replaced with inline progress");
                }
                session.InlineActive = true;
                session.Timer = new System.Windows.Forms.Timer();
                session.Timer.Interval = 350;
                session.Timer.Tick += delegate { UpdateProgress(session); };
                session.Timer.Start();
                activeSession = session;

                ThreadPool.QueueUserWorkItem(delegate
                {
                    string enhanced = null;
                    Exception failure = null;
                    try
                    {
                        enhanced = client.Enhance(prompt);
                    }
                    catch (Exception error)
                    {
                        failure = error;
                    }
                    try
                    {
                        dispatcher.BeginInvoke(new Action(delegate { Finish(session, enhanced, failure); }));
                    }
                    catch (InvalidOperationException)
                    {
                    }
                });
                Diagnostics.Log("enhancement request started");
            }
            catch (Exception error)
            {
                Diagnostics.Log(hotKeyDisplayName + " failed: " + error.Message);
                System.Media.SystemSounds.Beep.Play();
            }
        }

        private void UpdateProgress(ActiveSession session)
        {
            if (activeSession != session || !session.InlineActive)
            {
                StopTimer(session);
                return;
            }
            if (!IsExpectedForeground(session))
            {
                StopTimer(session);
                session.InlineActive = false;
                bool restored = session.Slot.RestoreDocumentIfUnchanged();
                Diagnostics.Log(restored
                    ? "focus changed; original text restored"
                    : "focus changed; inline document changed before restore");
                return;
            }

            session.FrameIndex++;
            int elapsed = (int)(DateTime.UtcNow - session.StartedAt).TotalSeconds;
            string progress = ProgressText.Build(elapsed, session.FrameIndex, configuration.ProgressLanguage);
            if (!session.Slot.ReplaceProgress(progress))
            {
                StopTimer(session);
                session.InlineActive = false;
                bool restored = session.Slot.RestoreDocumentIfUnchanged();
                Diagnostics.Log(restored
                    ? "selection changed; original text restored"
                    : "selection or document changed; result will be copied only");
            }
        }

        private void Finish(ActiveSession session, string enhanced, Exception failure)
        {
            if (activeSession != session)
            {
                return;
            }
            StopTimer(session);

            if (failure == null && !String.IsNullOrWhiteSpace(enhanced))
            {
                if (session.InlineActive && IsExpectedForeground(session) && session.Slot.ReplaceFinal(enhanced))
                {
                    Diagnostics.Log("enhanced text applied inline");
                }
                else
                {
                    if (session.InlineActive)
                    {
                        session.Slot.RestoreDocumentIfUnchanged();
                    }
                    bool copied = TrySetClipboardText(enhanced);
                    Diagnostics.Log(copied
                        ? "enhanced text copied; inline replacement skipped"
                        : "inline replacement skipped and clipboard was unavailable");
                    System.Media.SystemSounds.Beep.Play();
                }
            }
            else
            {
                if (session.InlineActive)
                {
                    session.Slot.RestoreDocumentIfUnchanged();
                }
                Diagnostics.Log("enhancement request failed: " +
                    (failure == null ? "empty result" : failure.Message));
                System.Media.SystemSounds.Beep.Play();
            }

            session.InlineActive = false;
            activeSession = null;
        }

        private void CancelActiveSession()
        {
            ActiveSession session = activeSession;
            if (session == null)
            {
                return;
            }
            StopTimer(session);
            if (session.InlineActive)
            {
                session.Slot.RestoreDocumentIfUnchanged();
            }
            activeSession = null;
        }

        private static void StopTimer(ActiveSession session)
        {
            if (session.Timer != null)
            {
                session.Timer.Stop();
                session.Timer.Dispose();
                session.Timer = null;
            }
        }

        private static bool IsExpectedForeground(ActiveSession session)
        {
            IntPtr window = GetForegroundWindow();
            uint processId;
            GetWindowThreadProcessId(window, out processId);
            return window == session.ExpectedWindow && processId == (uint)session.ExpectedProcessId;
        }

        private static bool TryGetForegroundApplication(
            out IntPtr window,
            out int processId,
            out string processName)
        {
            window = GetForegroundWindow();
            processId = 0;
            processName = null;
            if (window == IntPtr.Zero)
            {
                return false;
            }
            uint nativeProcessId;
            GetWindowThreadProcessId(window, out nativeProcessId);
            if (nativeProcessId == 0)
            {
                return false;
            }
            try
            {
                using (Process process = Process.GetProcessById((int)nativeProcessId))
                {
                    processId = process.Id;
                    processName = process.ProcessName;
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }

        private static bool TrySetClipboardText(string text)
        {
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    Clipboard.SetText(text);
                    return true;
                }
                catch (ExternalException)
                {
                    Thread.Sleep(50);
                }
            }
            return false;
        }
    }

    public static class WindowsHost
    {
        private static Mutex mutex;

        [STAThread]
        public static void Run()
        {
            bool created;
            mutex = new Mutex(true, @"Local\CodexOpenPEHotkey", out created);
            if (!created)
            {
                return;
            }

            Directory.CreateDirectory(AppPaths.DataDirectory);
            File.WriteAllText(AppPaths.HotkeyPidFile, Process.GetCurrentProcess().Id.ToString(), Encoding.ASCII);
            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += delegate(object sender, ThreadExceptionEventArgs args)
                {
                    Diagnostics.Log("UI thread failure: " + args.Exception);
                };
                RuntimeConfiguration configuration = RuntimeConfiguration.Load(AppPaths.ConfigFile);
                using (HotKeyApplication application = new HotKeyApplication(configuration))
                {
                    Application.Run(application);
                }
            }
            catch (Exception error)
            {
                Diagnostics.Log("startup failed: " + error);
                System.Media.SystemSounds.Beep.Play();
            }
            finally
            {
                try
                {
                    if (File.Exists(AppPaths.HotkeyPidFile))
                    {
                        File.Delete(AppPaths.HotkeyPidFile);
                    }
                }
                catch
                {
                }
                mutex.ReleaseMutex();
                mutex.Dispose();
                mutex = null;
            }
        }
    }

    public static class SelfTests
    {
        public static void Run()
        {
            Expect(
                ProgressText.Build(3, 0, "zh") == "[OpenPE \u280b] \u6b63\u5728\u4f18\u5316 3s",
                "Chinese progress starts in optimizing state");
            Expect(
                ProgressText.Build(20, 5, "zh") == "[OpenPE \u2834] \u4ecd\u5728\u751f\u6210 20s",
                "Chinese progress exposes continued generation");
            Expect(
                ProgressText.Build(50, 7, "zh") == "[OpenPE \u2827] \u7f51\u7edc\u8f83\u6162 50s",
                "Chinese progress exposes slow network state");
            Expect(
                TextReplacement.Apply("before prompt after", 7, 6, "better") == "before better after",
                "Text replacement preserves surrounding content");
            RuntimeConfiguration configuration = new RuntimeConfiguration();
            configuration.AllowedProcessNames = "Codex, ChatGPT.exe";
            HashSet<string> names = configuration.GetAllowedProcessNames();
            Expect(names.Contains("Codex") && names.Contains("ChatGPT"), "Windows process allowlist is normalized");
            HotKeyBinding defaultBinding = HotKeyBinding.Parse("Alt+Q");
            Expect(defaultBinding.DisplayName == "Alt+Q" && defaultBinding.VirtualKey == 0x51,
                "Default Windows hotkey is Alt+Q");
            HotKeyBinding customBinding = HotKeyBinding.Parse("control+shift+f8");
            Expect(customBinding.DisplayName == "Ctrl+Shift+F8" && customBinding.VirtualKey == 0x77,
                "Custom Windows hotkey is parsed");
            ExpectThrows(delegate { HotKeyBinding.Parse("Q"); }, "Modifier-free Windows hotkey is rejected");
            ExpectThrows(delegate { HotKeyBinding.Parse("Alt+Escape"); }, "Unsupported Windows key is rejected");
            ExpectThrows(delegate { HotKeyBinding.Parse("Alt+Option+Q"); },
                "Duplicate Windows modifier alias is rejected");
            Console.WriteLine("All Windows core self-tests passed");
        }

        private static void Expect(bool condition, string message)
        {
            if (!condition)
            {
                throw new InvalidOperationException("FAIL: " + message);
            }
            Console.WriteLine("PASS: " + message);
        }

        private static void ExpectThrows(Action action, string message)
        {
            try
            {
                action();
            }
            catch
            {
                Console.WriteLine("PASS: " + message);
                return;
            }
            throw new InvalidOperationException("FAIL: " + message);
        }
    }
}
