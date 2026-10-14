using System; using System.IO; using System.Reflection; using System.Diagnostics; using System.Windows.Forms;
class Launcher {
 static void Extract(string name,string path){using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream(name))using(var output=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)){if(input==null)throw new Exception("Missing resource: "+name);input.CopyTo(output);}}
 [STAThread] static void Main(){string work=null;try{
  work=Path.Combine(Path.GetTempPath(),"bitXrestic_"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(work);
  string binary=Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),"restic.exe"),icon=Path.Combine(work,"bitXrestic.ico");if(!File.Exists(binary)){binary=Path.Combine(work,"restic.exe");Extract("restic.exe",binary);}Extract("bitXrestic.ico",icon);
  string script;using(var r=new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream("Export.ps1")))script=r.ReadToEnd();
  var p=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"));
  p.Arguments="-NoProfile -STA -Command \"& ([ScriptBlock]::Create([Console]::In.ReadToEnd()))\"";
  p.UseShellExecute=false;p.CreateNoWindow=true;p.RedirectStandardInput=true;p.RedirectStandardError=true;
  p.EnvironmentVariables["BITXRESTIC_BINARY"]=binary;p.EnvironmentVariables["BITXRESTIC_ICON"]=icon;
  var child=Process.Start(p);child.StandardInput.Write(script);child.StandardInput.Close();string err=child.StandardError.ReadToEnd();child.WaitForExit();
  if(child.ExitCode!=0)MessageBox.Show(err,"bitXrestic");
 }catch(Exception e){MessageBox.Show(e.Message,"bitXrestic");}finally{if(work!=null){try{Directory.Delete(work,true);}catch{}}}}
}
