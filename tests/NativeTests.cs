using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

internal sealed class UpdateFixture : HttpMessageHandler
{
    internal byte[] Bytes = Encoding.UTF8.GetBytes("native test installer");
    internal bool Offline, InvalidOrigin, Prerelease, Incomplete, TooLarge;
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        if (Offline) throw new HttpRequestException("offline");
        if (request.RequestUri.Host == "api.github.com") {
            string hash; using (var sha = SHA256.Create()) hash = BitConverter.ToString(sha.ComputeHash(Bytes)).Replace("-", "").ToLowerInvariant();
            string url = InvalidOrigin ? "https://example.com/app.exe" : "https://github.com/" + MouseScrollInfo.Repository + "/releases/download/v1.1.0/" + MouseScrollInfo.Installer;
            string json = "{\"tag_name\":\"v1.1.0\",\"prerelease\":" + (Prerelease ? "true" : "false") + ",\"assets\":[{\"name\":\"" + MouseScrollInfo.Installer + "\",\"size\":" + (TooLarge ? 10000001 : Bytes.Length) + ",\"digest\":\"sha256:" + hash + "\",\"browser_download_url\":\"" + url + "\"}]}";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json) });
        }
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Incomplete ? new byte[] { 1 } : Bytes) });
    }
}
internal static class NativeTests
{
    private static int count;
    private static void Expect(bool condition, string name) { if (!condition) throw new Exception("FAILED: " + name); count++; Console.WriteLine("OK " + name); }
    private static void Wait(MouseScrollUpdates updates, string status)
    {
        for (int i = 0; i < 500; i++) { if (updates.State.Status == status) return; Thread.Sleep(10); }
        throw new Exception("Expected " + status + "; got " + updates.State.Status + ": " + updates.State.Message);
    }
    private static int Main(string[] args)
    {
        try {
            string root = Path.GetFullPath(args[0]); Directory.CreateDirectory(root);
            string preferences = Path.Combine(root, "perfil João com espaços", "preferences.json");
            MouseScrollPreferences.Save(preferences, "{\"theme\":\"dark\"}");
            MouseScrollPreferences.Save(preferences, "{\"theme\":\"light\"}");
            MouseScrollPreferences.Save(preferences, "{\"theme\":\"dark\"}");
            Expect(File.ReadAllText(preferences) == "{\"theme\":\"dark\"}", "repeated theme saves replace an existing file with Unicode/spaces");
            Expect(MouseScrollUpdates.IsNewer("v1.1.0", "1.1.0-preview.2"), "stable supersedes same-base preview");
            Expect(!MouseScrollUpdates.IsNewer("v1.1.0", "1.1.0"), "same stable is not an update");
            Expect(!MouseScrollUpdates.IsNewer("v1.0.9", "1.1.0-preview.2"), "older stable is not an update");
            Expect(!MouseScrollUpdates.IsNewer("v9999999999999.1.0", "1.1.0"), "invalid version is rejected");
            bool launched = false;
            using (var updates = new MouseScrollUpdates(Path.Combine(root, "valid"), "1.1.0-preview.2", new UpdateFixture(), delegate { launched = true; })) {
                updates.Check(); Wait(updates, "available"); updates.Download(); Wait(updates, "ready");
                Expect(updates.Install() && launched, "verified update launches installer");
            }
            launched = false;
            using (var updates = new MouseScrollUpdates(Path.Combine(root, "tampered"), "1.1.0-preview.2", new UpdateFixture(), delegate { launched = true; })) {
                updates.Check(); Wait(updates, "available"); updates.Download(); Wait(updates, "ready");
                File.WriteAllText(Path.Combine(root, "tampered", "1.1.0", MouseScrollInfo.Installer), "tampered");
                Expect(!updates.Install() && !launched && updates.State.Status == "error", "altered installer is blocked");
            }
            using (var updates = new MouseScrollUpdates(Path.Combine(root, "origin"), "1.1.0-preview.2", new UpdateFixture { InvalidOrigin = true }, delegate {})) {
                updates.Check(); Wait(updates, "error"); Expect(true, "foreign download origin is blocked");
            }
            using (var updates = new MouseScrollUpdates(Path.Combine(root, "large"), "1.1.0-preview.2", new UpdateFixture { TooLarge = true }, delegate {})) {
                updates.Check(); Wait(updates, "error"); Expect(true, "installer over 10 MB is blocked");
            }
            using (var updates = new MouseScrollUpdates(Path.Combine(root, "preview"), "1.1.0-preview.2", new UpdateFixture { Prerelease = true }, delegate {})) {
                updates.Check(); Wait(updates, "current"); Expect(true, "prereleases stay outside stable channel");
            }
            using (var updates = new MouseScrollUpdates(Path.Combine(root, "partial"), "1.1.0-preview.2", new UpdateFixture { Incomplete = true }, delegate {})) {
                updates.Check(); Wait(updates, "available"); updates.Download(); Wait(updates, "error"); Expect(true, "incomplete download is blocked");
            }
            using (var updates = new MouseScrollUpdates(Path.Combine(root, "offline"), "1.1.0-preview.2", new UpdateFixture { Offline = true }, delegate {})) {
                updates.Check(); Wait(updates, "error"); Expect(true, "offline check reports recoverable error");
            }
            Console.WriteLine(count + " native checks passed. No mouse settings changed."); return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
