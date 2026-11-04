using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Mouse Scroll")]
[assembly: AssemblyDescription("Ajusta a direção da rolagem dos mouses no Windows")]
[assembly: AssemblyProduct("Mouse Scroll")]
[assembly: AssemblyVersion("1.0.0.0")]

internal static class MouseScrollLauncher
{
    private static readonly string[] Resources =
        { "MouseScroll.ps1", "MouseScroll.ico", "MouseScroll.png" };

    [STAThread]
    private static int Main()
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
                engine.AddCommand(Path.Combine(sessionDirectory, "MouseScroll.ps1")).Invoke();
                if (engine.HadErrors)
                    throw new InvalidOperationException(engine.Streams.Error[0].ToString());
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
