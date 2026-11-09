using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class MouseScrollInfo
{
    public const string Version = "1.1.0-preview.4";
    public const string Repository = "leosalema213/inverter-scroll-mouse";
    public const string Installer = "MouseScroll-Instalar.exe";
    public const int MaxInstallerBytes = 10000000;
}

public static class MouseScrollPreferences
{
    public static void Save(string file, string json)
    {
        file = Path.GetFullPath(file);
        Directory.CreateDirectory(Path.GetDirectoryName(file));
        string temporary = file + ".tmp";
        File.WriteAllText(temporary, json, new System.Text.UTF8Encoding(false));
        // A genuine C# null avoids PowerShell coercing the backup path to an empty string.
        if (File.Exists(file)) File.Replace(temporary, file, null);
        else File.Move(temporary, file);
    }
}

public class MouseScrollComboBox : ComboBox
{
    public Color BorderColor = Color.Gray;
    public MouseScrollComboBox() { DrawMode = DrawMode.OwnerDrawFixed; DropDownStyle = ComboBoxStyle.DropDownList; FlatStyle = FlatStyle.Flat; ItemHeight = 28; }
    protected override void OnDrawItem(DrawItemEventArgs e)
    {
        if (e.Index < 0) return;
        using (var brush = new SolidBrush(BackColor)) e.Graphics.FillRectangle(brush, e.Bounds);
        var bounds = e.Bounds; bounds.X += 9;
        TextRenderer.DrawText(e.Graphics, GetItemText(Items[e.Index]), Font, bounds, ForeColor, TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }
    private void DrawFrame(Graphics graphics)
    {
        using (var fill = new SolidBrush(BackColor)) graphics.FillRectangle(fill, ClientRectangle);
        using (var pen = new Pen(Focused ? Color.FromArgb(115, 115, 115) : BorderColor)) graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
        TextRenderer.DrawText(graphics, GetItemText(SelectedItem), Font, new Rectangle(9, 1, Width - 34, Height - 2), ForeColor,
            TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
        graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        using (var pen = new Pen(ForeColor, 1.3f)) {
            pen.StartCap = pen.EndCap = System.Drawing.Drawing2D.LineCap.Round;
            float x = Width - 14, y = Height / 2f;
            graphics.DrawLines(pen, new[] { new PointF(x - 3, y - 1.5f), new PointF(x, y + 1.5f), new PointF(x + 3, y - 1.5f) });
        }
    }
    protected override void WndProc(ref Message message)
    {
        base.WndProc(ref message);
        if (message.Msg == 0xF) using (var graphics = Graphics.FromHwnd(Handle)) DrawFrame(graphics);
        if ((message.Msg == 0x317 || message.Msg == 0x318) && message.WParam != IntPtr.Zero)
            using (var graphics = Graphics.FromHdc(message.WParam)) DrawFrame(graphics);
    }
}

// Owner drawing keeps the original Details layout while theming the native header.
public class MouseScrollDeviceList : ListView
{
    public Color HeaderColor = Color.White;
    public Color HeaderTextColor = Color.Gray;
    public Color AlternateColor = Color.WhiteSmoke;
    public Color SelectionColor = Color.LightGray;
    public MouseScrollDeviceList() { DoubleBuffered = true; OwnerDraw = true; }
    protected override void OnDrawColumnHeader(DrawListViewColumnHeaderEventArgs e)
    {
        using (var brush = new SolidBrush(HeaderColor)) e.Graphics.FillRectangle(brush, e.Bounds);
        var bounds = e.Bounds; bounds.Inflate(-7, 0);
        TextRenderer.DrawText(e.Graphics, e.Header.Text, Font, bounds, HeaderTextColor, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
    }
    protected override void OnDrawItem(DrawListViewItemEventArgs e) { }
    protected override void OnDrawSubItem(DrawListViewSubItemEventArgs e)
    {
        Color background = e.Item.Selected ? SelectionColor : e.ItemIndex % 2 == 1 ? AlternateColor : BackColor;
        using (var brush = new SolidBrush(background)) e.Graphics.FillRectangle(brush, e.Bounds);
        var bounds = e.Bounds; bounds.Inflate(-7, 0);
        TextRenderer.DrawText(e.Graphics, e.SubItem.Text, Font, bounds, ForeColor, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }
}

public class MouseScrollUpdateState
{
    public string Status = "idle", Version, Message;
    public int Percent;
    public MouseScrollUpdateState Copy() { return (MouseScrollUpdateState)MemberwiseClone(); }
}

public sealed class MouseScrollUpdates : IDisposable
{
    private readonly object gate = new object();
    private readonly HttpClient client;
    private readonly string directory;
    private readonly Action<string> launch;
    private readonly string currentVersion;
    private MouseScrollUpdateState state = new MouseScrollUpdateState();
    private int working;
    private string candidateUrl, candidateHash, installer;
    private long candidateSize;
    private volatile bool disposed;
    public MouseScrollUpdateState State { get { lock (gate) return state.Copy(); } }
    public MouseScrollUpdates(string directory) : this(directory, MouseScrollInfo.Version, new HttpClientHandler(), null) { }
    public MouseScrollUpdates(string directory, string version, HttpMessageHandler handler, Action<string> launch)
    {
        this.directory = directory; currentVersion = version; this.launch = launch ?? LaunchInstaller;
        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
        client = new HttpClient(handler); client.Timeout = TimeSpan.FromSeconds(30);
        client.DefaultRequestHeaders.UserAgent.ParseAdd("MouseScroll/" + version);
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    }
    private void Set(string status, string message, string version, int percent)
    {
        lock (gate) state = new MouseScrollUpdateState { Status = status, Message = message, Version = version ?? state.Version, Percent = percent };
    }
    public static bool IsNewer(string remote, string current)
    {
        var a = Regex.Match(remote ?? "", @"^v?(\d+)\.(\d+)\.(\d+)$");
        var b = Regex.Match(current ?? "", @"^(\d+)\.(\d+)\.(\d+)(-preview\.\d+)?$");
        if (!a.Success || !b.Success) return false;
        for (int i = 1; i <= 3; i++) {
            int x, y;
            if (!int.TryParse(a.Groups[i].Value, out x) || !int.TryParse(b.Groups[i].Value, out y)) return false;
            if (x != y) return x > y;
        }
        return b.Groups[4].Success;
    }
    private static string Text(Dictionary<string, object> value, string key)
    { object result; return value.TryGetValue(key, out result) ? Convert.ToString(result) : ""; }
    private static string AssetUrl(Dictionary<string, object> asset, string tag)
    {
        string expected = "https://github.com/" + MouseScrollInfo.Repository + "/releases/download/" + Uri.EscapeDataString(tag) + "/" + Text(asset, "name");
        if (Text(asset, "browser_download_url") != expected) throw new InvalidDataException("Endereço de atualização inválido.");
        return expected;
    }
    private async Task<string> ReadText(string url, int limit)
    {
        using (var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false)) {
            response.EnsureSuccessStatusCode();
            using (var input = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
            using (var output = new MemoryStream()) {
                byte[] buffer = new byte[8192]; int count;
                while ((count = await input.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) > 0) {
                    if (output.Length + count > limit) throw new InvalidDataException("Resposta de atualização grande demais.");
                    output.Write(buffer, 0, count);
                }
                return System.Text.Encoding.UTF8.GetString(output.ToArray());
            }
        }
    }
    public void Check()
    {
        if (disposed || State.Status == "ready" || State.Status == "installing" || Interlocked.CompareExchange(ref working, 1, 0) != 0) return;
        Set("checking", "Verificando atualizações…", null, 0);
        Task.Run(async delegate {
            try {
                string api = "https://api.github.com/repos/" + MouseScrollInfo.Repository + "/releases/latest";
                string json;
                using (var response = await client.GetAsync(api).ConfigureAwait(false)) {
                    if (response.StatusCode == HttpStatusCode.NotFound) { Set("current", "Nenhuma atualização publicada ainda.", null, 0); return; }
                    response.EnsureSuccessStatusCode();
                    json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    if (json.Length > 1024 * 1024) throw new InvalidDataException("Resposta de atualização grande demais.");
                }
                var serializer = new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 };
                var release = serializer.Deserialize<Dictionary<string, object>>(json);
                string tag = Text(release, "tag_name");
                if (Text(release, "draft") == "True" || Text(release, "prerelease") == "True" || !IsNewer(tag, currentVersion)) {
                    Set("current", "Você está na versão mais recente.", null, 0); return;
                }
                Dictionary<string, object> asset = null, checksum = null;
                object items;
                if (release.TryGetValue("assets", out items)) foreach (Dictionary<string, object> item in (IEnumerable)items) {
                    if (Text(item, "name") == MouseScrollInfo.Installer) asset = item;
                    if (Text(item, "name") == MouseScrollInfo.Installer + ".sha256") checksum = item;
                }
                long size;
                if (asset == null || !long.TryParse(Text(asset, "size"), out size) || size < 1 || size > MouseScrollInfo.MaxInstallerBytes)
                    throw new InvalidDataException("O instalador não está disponível ou ultrapassa o limite de 10 MB.");
                string url = AssetUrl(asset, tag);
                var digest = Regex.Match(Text(asset, "digest"), @"^sha256:([a-fA-F0-9]{64})$");
                string hash = digest.Success ? digest.Groups[1].Value.ToLowerInvariant() : null;
                if (hash == null && checksum != null) {
                    var match = Regex.Match(await ReadText(AssetUrl(checksum, tag), 4096).ConfigureAwait(false), @"^([a-fA-F0-9]{64})\s+");
                    if (match.Success) hash = match.Groups[1].Value.ToLowerInvariant();
                }
                if (hash == null) throw new InvalidDataException("Esta versão não tem uma verificação SHA-256 válida.");
                candidateUrl = url; candidateHash = hash; candidateSize = size;
                Set("available", "Há uma nova versão disponível.", tag.TrimStart('v'), 0);
            } catch (Exception error) {
                if (!disposed) Set("error", error is InvalidDataException ? error.Message : "Não foi possível verificar. Confira sua conexão e tente novamente.", null, 0);
            } finally { Interlocked.Exchange(ref working, 0); }
        });
    }
    public void Download()
    {
        if (disposed || State.Status != "available" || Interlocked.CompareExchange(ref working, 1, 0) != 0) return;
        string version = State.Version;
        Set("downloading", "Baixando atualização…", version, 0);
        Task.Run(async delegate {
            string partial = null;
            try {
                string folder = Path.Combine(directory, version); Directory.CreateDirectory(folder);
                installer = Path.Combine(folder, MouseScrollInfo.Installer); partial = installer + ".partial";
                using (var response = await client.GetAsync(candidateUrl, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false)) {
                    response.EnsureSuccessStatusCode();
                    using (var input = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                    using (var output = new FileStream(partial, FileMode.Create, FileAccess.Write))
                    using (var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(5))) {
                        byte[] buffer = new byte[32768]; long total = 0; int count;
                        while ((count = await input.ReadAsync(buffer, 0, buffer.Length, timeout.Token).ConfigureAwait(false)) > 0) {
                            total += count;
                            if (total > candidateSize || total > MouseScrollInfo.MaxInstallerBytes) throw new InvalidDataException("O tamanho do instalador não confere.");
                            await output.WriteAsync(buffer, 0, count, timeout.Token).ConfigureAwait(false);
                            Set("downloading", "Baixando atualização…", version, (int)Math.Min(99, total * 100 / candidateSize));
                        }
                        if (total != candidateSize) throw new InvalidDataException("O download ficou incompleto. Tente novamente.");
                    }
                }
                if (HashFile(partial) != candidateHash) throw new InvalidDataException("A verificação do download falhou. Nada foi instalado.");
                if (File.Exists(installer)) File.Delete(installer);
                File.Move(partial, installer);
                Set("ready", "Atualização pronta para instalar.", version, 100);
            } catch (Exception error) {
                try { if (partial != null) File.Delete(partial); } catch { }
                if (!disposed) Set("error", error is InvalidDataException ? error.Message : "Não foi possível baixar. Verifique sua conexão e o espaço em disco.", version, 0);
            } finally { Interlocked.Exchange(ref working, 0); }
        });
    }
    private static string HashFile(string file)
    {
        using (var stream = File.OpenRead(file)) using (var hash = SHA256.Create())
            return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
    }
    private static void LaunchInstaller(string file)
    {
        using (var child = Process.Start(new ProcessStartInfo(file, "/S --updated --force-run") { UseShellExecute = true })) {
            if (child == null) throw new IOException("Não foi possível abrir o instalador.");
        }
    }
    public bool Install()
    {
        if (State.Status != "ready" || Interlocked.CompareExchange(ref working, 1, 0) != 0) return false;
        try {
            if (HashFile(installer) != candidateHash) throw new InvalidDataException("O instalador foi alterado. Verifique e baixe novamente.");
            launch(installer); Set("installing", "Aplicando atualização…", null, 100); return true;
        } catch (Exception error) { Set("error", error.Message, null, 0); return false; }
        finally { Interlocked.Exchange(ref working, 0); }
    }
    public void Dispose() { disposed = true; client.Dispose(); }
}
