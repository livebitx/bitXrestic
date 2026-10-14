$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class BitXTaskbar { [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id); }'
[void][BitXTaskbar]::SetCurrentProcessExplicitAppUserModelID('bitX.bitXrestic')
[Windows.Forms.Application]::EnableVisualStyles()
$script:cancel=$false;$script:selected=@();$script:passwords=@{};$script:busy=$false;$script:selectionContext=$null
function Log($s){
 $log.SelectionStart=$log.TextLength;$log.SelectionLength=0
 $log.SelectionColor=if(([string]$s).StartsWith('ERROR:')){[Drawing.Color]::Firebrick}elseif(([string]$s).StartsWith('DONE:')){[Drawing.Color]::ForestGreen}else{[Drawing.Color]::Black}
 $extra=if(([string]$s) -match '^(Repositories:|SELECTED:|Exporting temporary ZIP:|Reusing verified temporary ZIP:|Merging files:|DONE:|ERROR:|No snapshots)'){"`r`n"}else{''}
 $log.AppendText([string]$s+"`r`n"+$extra);$log.ScrollToCaret();[Windows.Forms.Application]::DoEvents()
}
function Busy($b){$script:busy=$b;foreach($c in @($export,$root,$day,$dest,$reuse,$browseRoot,$browseDest)){$c.Enabled=-not $b};$stop.Enabled=$b}
function Quote($s){if($s.Contains('"')){throw 'Quotation marks are not allowed in paths.'};return '"'+($s -replace '(\\+)$','$1$1')+'"'}
function RunRestic($repo,$password,$arguments){
 $p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=$env:BITXRESTIC_BINARY
 $p.Arguments='-r '+(Quote $repo)+' '+$arguments;$p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
 foreach($key in @('RESTIC_PASSWORD_FILE','RESTIC_PASSWORD_COMMAND','RESTIC_REPOSITORY','RESTIC_REPOSITORY_FILE')){$p.EnvironmentVariables.Remove($key)}
 $p.EnvironmentVariables['RESTIC_PASSWORD']=$password
 $proc=New-Object Diagnostics.Process;$proc.StartInfo=$p
 try{
  [void]$proc.Start();$stdout=$proc.StandardOutput.ReadToEndAsync();$stderr=$proc.StandardError.ReadToEndAsync()
  while(-not $proc.WaitForExit(100)){[Windows.Forms.Application]::DoEvents();if($script:cancel){$proc.Kill();$proc.WaitForExit();throw 'Operation stopped.'}}
  $result=@{code=$proc.ExitCode;out=$stdout.Result;err=$stderr.Result};return $result
 }finally{$p.EnvironmentVariables.Remove('RESTIC_PASSWORD');$proc.Dispose()}
}
function Password($repo){
 $d=New-Object Windows.Forms.Form;$d.Text='Repository password';$d.Size=New-Object Drawing.Size(520,170);$d.StartPosition='CenterParent';$d.Icon=$form.Icon;$d.ShowInTaskbar=$false;$d.FormBorderStyle='FixedDialog';$d.MaximizeBox=$false;$d.MinimizeBox=$false
 $l=New-Object Windows.Forms.Label;$l.Text=$repo;$l.Location=New-Object Drawing.Point(10,10);$l.Size=New-Object Drawing.Size(485,35);$d.Controls.Add($l)
 $t=New-Object Windows.Forms.TextBox;$t.UseSystemPasswordChar=$true;$t.Location=New-Object Drawing.Point(10,50);$t.Size=New-Object Drawing.Size(485,25);$d.Controls.Add($t)
 $b=New-Object Windows.Forms.Button;$b.Text='Unlock';$b.Location=New-Object Drawing.Point(390,85);$b.DialogResult='OK';$d.Controls.Add($b);$d.AcceptButton=$b
 try{if($d.ShowDialog($form) -ne 'OK'){throw 'Password entry cancelled.'};return $t.Text}finally{$t.Clear();$d.Dispose()}
}
function RepoList($start){
 $queue=New-Object Collections.Generic.Queue[object];$queue.Enqueue(@{path=$start;depth=0});$repos=New-Object Collections.Generic.List[string]
 while($queue.Count){if($script:cancel){throw 'Search stopped.'};$node=$queue.Dequeue();$p=$node.path
  if((Test-Path -LiteralPath (Join-Path $p 'config') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $p 'keys') -PathType Container) -and (Test-Path -LiteralPath (Join-Path $p 'data') -PathType Container)){$repos.Add($p);continue}
  foreach($dir in @(Get-ChildItem -LiteralPath $p -Directory -Force -ErrorAction Stop)){if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){$queue.Enqueue(@{path=$dir.FullName;depth=$node.depth+1})}}
  [Windows.Forms.Application]::DoEvents()
 };return @($repos.ToArray())
}
function Slug($s){$s=([string]$s -replace '[^a-zA-Z0-9_.-]','_');if(-not $s){$s='unknown'};return $s.Substring(0,[Math]::Min(60,$s.Length))}
function TextHash($s){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function FileHash($path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function WriteJson($object,$path){[IO.File]::WriteAllText($path,($object|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
function SnapshotTime($value){
 if($value -is [DateTimeOffset]){return $value}
 if($value -is [DateTime]){return [DateTimeOffset]$value}
 # Restic can use nanoseconds; .NET DateTime supports at most seven fractional digits.
 $text=([string]$value).Trim() -replace '(\.\d{7})\d+(?=Z|[+-]\d{2}:\d{2}$)','$1'
 $parsed=[DateTimeOffset]::MinValue
 if(-not [DateTimeOffset]::TryParse($text,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)){throw ('Invalid snapshot timestamp: '+[string]$value)}
 return $parsed
}
function ReadSnapshots($json){
 # Assignment avoids wrapping ConvertFrom-Json's array as one item in Windows PowerShell 5.1.
 $decoded=ConvertFrom-Json -InputObject $json
 foreach($snapshot in $decoded){
  if($null -eq $snapshot.id -or $null -eq $snapshot.time -or $snapshot.time -is [Array]){throw 'Invalid snapshot JSON structure.'}
  Write-Output $snapshot
 }
}
function ClearStage($stage,$out,$date){
 $expected=[IO.Path]::GetFullPath((Join-Path $out ('.bitXrestic_files_'+$date))).TrimEnd('\')
 $actual=[IO.Path]::GetFullPath($stage).TrimEnd('\')
 if(-not $actual.Equals($expected,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected temporary folder; cleanup refused.'}
 if(-not (Test-Path -LiteralPath $stage)){return}
 $items=@(Get-Item -LiteralPath $stage -Force)+@(Get-ChildItem -LiteralPath $stage -Recurse -Force)
 foreach($item in $items){if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Link detected in temporary folder; cleanup refused.'}}
 Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop
 if(Test-Path -LiteralPath $stage){throw 'Temporary folder was not removed.'}
}
function GroupKey($snapshot){
 $scope=@($snapshot.tags|Where-Object {$_ -like 'scope:*'}|Sort-Object) -join ';'
 $project=@($snapshot.tags|Where-Object {$_ -like 'project:*'}|Sort-Object) -join ';'
 if($scope){return $snapshot.hostname+'|'+$scope+'|'+$project}
 return $snapshot.hostname+'|'+(@($snapshot.paths|Sort-Object) -join '|')
}
$form=New-Object Windows.Forms.Form;$form.Text='bitXrestic 0.3.9 - Daily export / ZIP with files';$form.Size=New-Object Drawing.Size(960,740);$form.StartPosition='CenterScreen';$form.MinimumSize=$form.Size;$form.MaximumSize=$form.Size;$form.FormBorderStyle='FixedSingle';$form.MaximizeBox=$false;$form.ShowInTaskbar=$true
if($env:BITXRESTIC_ICON){$form.Icon=New-Object Drawing.Icon($env:BITXRESTIC_ICON)}
function Field($label,$y,$value){$l=New-Object Windows.Forms.Label;$l.Text=$label;$l.Location=New-Object Drawing.Point(15,$y);$l.Size=New-Object Drawing.Size(210,22);$form.Controls.Add($l);$t=New-Object Windows.Forms.TextBox;$t.Text=$value;$t.Location=New-Object Drawing.Point(230,$y);$t.Size=New-Object Drawing.Size(580,25);$form.Controls.Add($t);return $t}
$root=Field 'Repository folder (SMB)' 20 ''
$dest=Field 'Export folder' 55 ''
function BrowseButton($target,$y,$file){
 $b=New-Object Windows.Forms.Button;$b.Text='Browse...';$b.Location=New-Object Drawing.Point(825,$y);$b.Size=New-Object Drawing.Size(95,25);$form.Controls.Add($b)
 $action={
  if($file){$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='restic.exe (*.exe)|*.exe';$dialog.Title='Select restic.exe'}
  else{$dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description='Select a folder';if(Test-Path -LiteralPath $target.Text -PathType Container){$dialog.SelectedPath=$target.Text}}
  try{if($dialog.ShowDialog($form) -eq 'OK'){if($file){$target.Text=$dialog.FileName}else{$target.Text=$dialog.SelectedPath}}}finally{$dialog.Dispose()}
 }.GetNewClosure()
 $b.Add_Click($action);return $b
}
$browseRoot=BrowseButton $root 20 $false
$browseDest=BrowseButton $dest 55 $false
$l=New-Object Windows.Forms.Label;$l.Text='Date (Windows time zone):';$l.Location=New-Object Drawing.Point(15,130);$l.AutoSize=$true;$form.Controls.Add($l)
$day=New-Object Windows.Forms.DateTimePicker;$day.Format='Custom';$day.CustomFormat='yyyy-MM-dd';$day.Location=New-Object Drawing.Point(230,125);$form.Controls.Add($day)
$reuse=New-Object Windows.Forms.CheckBox;$reuse.Text='Try the same password for other repositories';$reuse.Location=New-Object Drawing.Point(440,130);$reuse.AutoSize=$true;$reuse.Checked=$true;$form.Controls.Add($reuse)
function Button($text,$x){$b=New-Object Windows.Forms.Button;$b.Text=$text;$b.Location=New-Object Drawing.Point($x,165);$b.Size=New-Object Drawing.Size(210,32);$form.Controls.Add($b);return $b}
$export=Button 'Export to ZIP' 15;$stop=Button 'Stop' 240;$stop.Enabled=$false;$about=Button 'About' 465
$log=New-Object Windows.Forms.RichTextBox;$log.Location=New-Object Drawing.Point(15,210);$log.Size=New-Object Drawing.Size(905,475);$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Vertical';$log.WordWrap=$true;$log.Font=New-Object Drawing.Font('Consolas',9);$form.Controls.Add($log)
$log.DetectUrls=$true
$log.Add_LinkClicked({param($sender,$event)
 try{
  $uri=New-Object Uri($event.LinkText)
  if(-not $uri.IsFile){return}
  $folder=$uri.LocalPath
  if(-not (Test-Path -LiteralPath $folder -PathType Container)){throw 'Destination folder is unavailable.'}
  $launch=New-Object Diagnostics.ProcessStartInfo;$launch.FileName='explorer.exe';$launch.Arguments=Quote $folder;$launch.UseShellExecute=$true
  [void][Diagnostics.Process]::Start($launch)
 }catch{Log ('ERROR: '+$_.Exception.Message)}
})
$about.Add_Click({
 $dialog=New-Object Windows.Forms.Form;$dialog.Text='About bitXrestic';$dialog.ClientSize=New-Object Drawing.Size(490,305);$dialog.StartPosition='CenterParent';$dialog.FormBorderStyle='FixedDialog';$dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false;$dialog.ShowInTaskbar=$false;$dialog.Icon=$form.Icon
 $info=New-Object Windows.Forms.Label;$info.Location=New-Object Drawing.Point(20,20);$info.Size=New-Object Drawing.Size(450,125)
 $info.Text="bitXrestic 0.3.9`r`nBy livebitx`r`n`r`nExport restic backups from a selected date into one ZIP.`r`nFiles keep their original paths under each host.`r`nPowered by restic (BSD-2-Clause).";$dialog.Controls.Add($info)
 $link=New-Object Windows.Forms.LinkLabel;$link.Text='github.com/livebitx/bitXrestic';$link.Location=New-Object Drawing.Point(20,150);$link.AutoSize=$true;$dialog.Controls.Add($link)
 $link.Add_LinkClicked({[void][Diagnostics.Process]::Start('https://github.com/livebitx/bitXrestic')})
 $site=New-Object Windows.Forms.LinkLabel;$site.Text='bitx.ro';$site.Location=New-Object Drawing.Point(20,180);$site.AutoSize=$true;$dialog.Controls.Add($site)
 $site.Add_LinkClicked({[void][Diagnostics.Process]::Start('https://bitx.ro')})
 $support=New-Object Windows.Forms.LinkLabel;$support.Text='Support via Revolut';$support.Location=New-Object Drawing.Point(20,210);$support.AutoSize=$true;$dialog.Controls.Add($support)
 $support.Add_LinkClicked({[void][Diagnostics.Process]::Start('https://revolut.me/bin')})
 $close=New-Object Windows.Forms.Button;$close.Text='Close';$close.Location=New-Object Drawing.Point(370,255);$close.DialogResult='OK';$dialog.Controls.Add($close);$dialog.AcceptButton=$close;$dialog.CancelButton=$close
 try{[void]$dialog.ShowDialog($form)}finally{$dialog.Dispose()}
})
$stop.Add_Click({$script:cancel=$true})
$form.Add_FormClosing({param($s,$e)if($script:busy){$script:cancel=$true;$e.Cancel=$true}else{$script:passwords.Clear()}})
$script:scanAction={
 if($log.TextLength){Log ''}
 Busy $true;$script:cancel=$false;$script:selected=@();$script:selectionContext=$null
 try{
  if(-not $root.Text -or -not (Test-Path -LiteralPath $root.Text -PathType Container)){throw 'Enter a repository folder accessible in File Explorer.'}
  $repos=@(RepoList $root.Text);if(-not $repos.Count){throw 'No repositories found in the selected folder.'}
  Log ('Repositories: '+$repos.Count);$lastPassword=$null
  foreach($repo in $repos){
   if($script:cancel){throw 'Stopped.'}
   $pw=$null;if($script:passwords.ContainsKey($repo)){$pw=$script:passwords[$repo]}elseif($reuse.Checked){$pw=$lastPassword}
   $result=$null;if($null -ne $pw){$result=RunRestic $repo $pw 'snapshots --json'}
   if(-not $result -or $result.code -ne 0){$pw=Password $repo;$result=RunRestic $repo $pw 'snapshots --json'}
   if($result.code -ne 0){throw ('Cannot read repository '+$repo+': '+$result.err)}
   $script:passwords[$repo]=$pw;$lastPassword=$pw
   $snapshots=@(ReadSnapshots $result.out);$chosen=@{}
   foreach($snap in $snapshots){$time=(SnapshotTime $snap.time);if($time.LocalDateTime.Date -ne $day.Value.Date){continue};$key=GroupKey $snap;if(-not $chosen.ContainsKey($key) -or $time -gt (SnapshotTime $chosen[$key].time)){$chosen[$key]=$snap}}
   foreach($snap in @($chosen.Values | Sort-Object hostname,time,id)){
    $script:selected+=@{repo=$repo;snapshot=$snap}
    Log ('Repository: '+$repo)
    Log ('Snapshot:   '+$snap.id.Substring(0,8))
    Log ('Host:       '+$snap.hostname)
    Log ('Date:       '+$snap.time)
    Log ('Tags:       '+($snap.tags -join ', '))
    Log ''
   }
   if(-not $chosen.Count){Log ('No snapshots for the selected date: '+$repo)}
  }
  $script:selectionContext=$root.Text+'|'+$day.Value.ToString('yyyy-MM-dd')+'|'+$env:BITXRESTIC_BINARY
  Log ('SELECTED: '+$script:selected.Count+'. Latest snapshot per host + scope/project; otherwise host + paths. Exporting automatically.')
 }catch{$script:selectionContext=$null;Log ('ERROR: '+$_.Exception.Message)}finally{Busy $false}
}
$script:exportAction={
 if($log.TextLength){Log ''}
 Busy $true;$script:cancel=$false
 try{
  if(-not $script:selectionContext -or $script:selectionContext -ne ($root.Text+'|'+$day.Value.ToString('yyyy-MM-dd')+'|'+$env:BITXRESTIC_BINARY)){throw 'Run preview again for the current settings.'}
  if(-not $script:selected.Count){throw 'No snapshots selected.'}
  if(-not $dest.Text -or -not [IO.Path]::IsPathRooted($dest.Text)){throw 'Enter an absolute destination, for example D:\RESTORE.'}
  $out=[IO.Path]::GetFullPath($dest.Text);$source=[IO.Path]::GetFullPath($root.Text).TrimEnd('\')
  if($out.TrimEnd('\').Equals($source,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'The destination cannot be inside the source folder.'}
  [void][IO.Directory]::CreateDirectory($out);$date=$day.Value.ToString('yyyy-MM-dd');$final=Join-Path $out ('backup_'+$date+'.zip')
  if(Test-Path -LiteralPath $final){Log ('Destination: '+([Uri]$out).AbsoluteUri);throw 'The final ZIP already exists. Open the destination link above or choose another folder; files are not overwritten.'}
  $stage=Join-Path $out ('.bitXrestic_files_'+$date);[void][IO.Directory]::CreateDirectory($stage)
  $records=New-Object Collections.Generic.List[object]
  foreach($item in $script:selected){
   if($script:cancel){throw 'Export stopped.'};$snap=$item.snapshot;$repo=$item.repo
   $repoHash=TextHash ($repo.ToLowerInvariant())
   $repoFolder=(Slug ([IO.Path]::GetFileName($repo.TrimEnd('\'))))+'_'+$repoHash.Substring(0,12)
   $hostFolder=Slug $snap.hostname;$project=@($snap.tags|Where-Object {$_ -like 'project:*'}|Select-Object -First 1)
   $service=if($project.Count){Slug ($project[0].Substring(8))}else{Slug (@($snap.tags|Where-Object {$_ -like 'scope:*'}|Select-Object -First 1) -join '')}
   $relative=$repoFolder+'/'+$hostFolder+'/'+$service+'_'+$snap.id.Substring(0,12)+'.zip';$tar=Join-Path $stage ($relative.Replace('/','\'));[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($tar));$meta=$tar+'.verified.json'
   $valid=$false;if((Test-Path -LiteralPath $tar) -and (Test-Path -LiteralPath $meta)){try{$old=Get-Content -LiteralPath $meta -Raw|ConvertFrom-Json;$valid=$old.snapshot_id -eq $snap.id -and $old.repo -eq $repo -and $old.size -eq (Get-Item -LiteralPath $tar).Length -and $old.sha256 -eq (FileHash $tar)}catch{$valid=$false}}
   if(-not $valid){
    $partial=$tar+'.partial';if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force}
    if(Test-Path -LiteralPath $tar){throw ('Existing temporary ZIP is not verified: '+$tar+'. Choose a new export folder.')}
    Log ('Exporting temporary ZIP: '+$relative)
    $result=RunRestic $repo $script:passwords[$repo] ('dump '+$snap.id+' / --archive zip --target '+(Quote $partial))
    if($result.code -ne 0){throw ('Export failed; final ZIP was not published: '+$result.err)}
    if(-not (Test-Path -LiteralPath $partial) -or (Get-Item -LiteralPath $partial).Length -lt 22){throw 'Temporary ZIP is missing or incomplete.'}
    $hash=FileHash $partial;Move-Item -LiteralPath $partial -Destination $tar
    $record=@{repo=$repo;snapshot_id=$snap.id;time=$snap.time;host=$snap.hostname;tags=$snap.tags;paths=$snap.paths;tar=$relative;size=(Get-Item -LiteralPath $tar).Length;sha256=$hash};WriteJson $record $meta
   }else{Log ('Reusing verified temporary ZIP: '+$relative);$record=$old}
   $records.Add($record)
  }
  $zipPath=$final+'.partial';if(Test-Path -LiteralPath $zipPath){Remove-Item -LiteralPath $zipPath -Force}
  $zipFile=[IO.File]::Open($zipPath,'CreateNew','ReadWrite','None');$zip=$null
  try{
   $zip=New-Object IO.Compression.ZipArchive($zipFile,[IO.Compression.ZipArchiveMode]::Create,$true)
   $buffer=New-Object byte[] 1048576
   $seen=New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
   $hosts=New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
   foreach($record in $records){
    if($script:cancel){throw 'ZIP creation stopped.'}
    $inputPath=Join-Path $stage ($record.tar.Replace('/','\'))
    $inputFile=[IO.File]::OpenRead($inputPath);$inputZip=$null
    try{
     $inputZip=New-Object IO.Compression.ZipArchive($inputFile,[IO.Compression.ZipArchiveMode]::Read,$true)
     $hostName=Slug $record.host
     if($hosts.ContainsKey($hostName) -and $hosts[$hostName] -cne $record.host){throw ('Ambiguous host name: '+$record.host)}
     $hosts[$hostName]=[string]$record.host
     $prefix=$hostName+'/'
     Log ('Merging files: '+$prefix)
     foreach($sourceEntry in $inputZip.Entries){
      if($script:cancel){throw 'ZIP creation stopped.'}
      $name=$sourceEntry.FullName.TrimStart('/')
      if(-not $name){continue}
      if(($name -split '/') -contains '..'){throw 'Unsafe path in source archive.'}
      $fullName=$prefix+$name
      if($name.EndsWith('/')){$signature='directory'}else{
       $hashStream=$sourceEntry.Open();$hasher=[Security.Cryptography.SHA256]::Create()
       try{$signature=([BitConverter]::ToString($hasher.ComputeHash($hashStream)))+'|'+$sourceEntry.ExternalAttributes}finally{$hasher.Dispose();$hashStream.Dispose()}
      }
      if($seen.ContainsKey($fullName)){
       if($seen[$fullName] -ne $signature){throw ('Conflict: different versions at '+$fullName+'. The final ZIP was not published.')}
       continue
      }
      $seen[$fullName]=$signature
      $entry=$zip.CreateEntry($fullName,[IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime=$sourceEntry.LastWriteTime
      $entry.ExternalAttributes=$sourceEntry.ExternalAttributes
      $src=$sourceEntry.Open();$dst=$entry.Open()
      try{while(($n=$src.Read($buffer,0,$buffer.Length)) -gt 0){$dst.Write($buffer,0,$n);[Windows.Forms.Application]::DoEvents();if($script:cancel){throw 'ZIP creation stopped.'}}}finally{$dst.Dispose();$src.Dispose()}
     }
    }finally{if($inputZip){$inputZip.Dispose()};$inputFile.Dispose()}
   }
  }finally{if($zip){$zip.Dispose()};$zipFile.Dispose()}
  Move-Item -LiteralPath $zipPath -Destination $final
  try{
   ClearStage $stage $out $date
  }catch{Log ('ERROR: Archive is complete, but temporary file cleanup failed: '+$_.Exception.Message)}
  Log ('DONE: '+$final)
  Log ('Destination: '+([Uri]$out).AbsoluteUri)
 }catch{Log ('ERROR: '+$_.Exception.Message)}finally{Busy $false}
}
$export.Add_Click({
 & $script:scanAction
 if($script:selectionContext -and -not $script:cancel){if($script:selected.Count){& $script:exportAction}else{Log 'ERROR: No snapshots found for the selected date.'}}
})
[void]$form.ShowDialog()
