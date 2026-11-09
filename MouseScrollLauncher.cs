using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Mouse Scroll")]
[assembly: AssemblyDescription("Ajusta a direção da rolagem dos mouses no Windows")]
[assembly: AssemblyProduct("Mouse Scroll")]
[assembly: AssemblyVersion("1.1.0.4")]
[assembly: AssemblyInformationalVersion(MouseScrollInfo.Version)]

internal static class MouseScrollLauncher
{
    private static readonly string[] Resources =
        { "MouseScroll.ps1", "MouseScroll.ico", "MouseScroll.png", "MouseScroll.Native.cs",
          "sun-dark.png", "sun-light.png", "moon-dark.png", "moon-light.png", "settings-dark.png", "settings-light.png" };

    [STAThread]
    private static int Main(string[] args)
    {
        string sessionDirectory = Path.Combine(Path.GetTempPath(), "MouseScroll-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(sessionDirectory);
            foreach (string name in Resources)
            {
                using (Stream source = typeof(MouseScrollLauncher).Assembly.GetManifestResourceStream(name))
                using (Stream target = File.Create(Path.Combine(sessionDirectory, name)))
                    source.CopyTo(target);
            }

            var settings = InitialSessionState.CreateDefault();
            settings.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            settings.ThreadOptions = PSThreadOptions.UseCurrentThread;
            using (Runspace runspace = RunspaceFactory.CreateRunspace(settings))
            using (PowerShell engine = PowerShell.Create())
            {
                runspace.Open();
                engine.Runspace = runspace;
                engine.AddCommand(Path.Combine(sessionDirectory, "MouseScroll.ps1"));
                // An isolated profile lets QA check themes without changing personal preferences.
                if (args.Length == 2 && args[0] == "--profile") engine.AddParameter("ProfileDirectory", Path.GetFullPath(args[1]));
                if (args.Length == 2 && args[0] == "--capture") {
                    string directory = Path.GetFullPath(args[1]);
                    engine.AddParameter("ProfileDirectory", Path.Combine(directory, "profile"));
                    engine.AddParameter("CaptureDirectory", directory);
                }
                engine.Invoke();
                // The script stops on real failures. Registry probes intentionally use
                // SilentlyContinue for missing optional properties; those are not startup errors.
                if (engine.InvocationStateInfo.State == PSInvocationState.Failed)
                    throw new InvalidOperationException("Não foi possível iniciar o Mouse Scroll.", engine.InvocationStateInfo.Reason);
            }
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.GetBaseException().Message, "Mouse Scroll", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try
            {
                foreach (string name in Resources)
                    File.Delete(Path.Combine(sessionDirectory, name));
                if (Directory.Exists(sessionDirectory))
                    Directory.Delete(sessionDirectory);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}
