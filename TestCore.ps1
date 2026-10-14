$ErrorActionPreference='Stop'
try {
 $tokens=$null;$errors=$null
 $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Get-Location) 'Export.ps1'),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors | Out-String)}
 foreach($name in @('ReadSnapshots','SnapshotTime','GroupKey','ClearStage')){
  $node=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
  if(-not $node){throw ('Functie lipsa: '+$name)}
  . ([ScriptBlock]::Create($node.Extent.Text))
 }
 $json='[{"id":"one","time":"2026-10-14T06:00:09.41270119+03:00","hostname":"cat","tags":["scope:docker","project:nginx"],"paths":["/opt/docker/nginx"]},{"id":"two","time":"2026-10-14T06:00:14.045523292+03:00","hostname":"cat","tags":["scope:system"],"paths":["/etc"]}]'
 $rows=@(ReadSnapshots $json)
 if($rows.Count -ne 2 -or $rows[0].id -ne 'one' -or $rows[1].id -ne 'two'){throw 'Lista JSON nu este parcursa separat.'}
 foreach($row in $rows){$time=SnapshotTime $row.time;if($time.Year -ne 2026 -or $time.Day -ne 14 -or $time.Offset.TotalHours -ne 3){throw 'Data citita incorect.'}}
 if((GroupKey $rows[0]) -eq (GroupKey $rows[1])){throw 'Serviciile nu sunt separate.'}
 if(@(ReadSnapshots '[]').Count -ne 0){throw 'Lista goala incorecta.'}
 if(@(ReadSnapshots ('['+($rows[0]|ConvertTo-Json -Compress)+']')).Count -ne 1){throw 'Snapshot unic incorect.'}
 $testRoot=Join-Path ([IO.Path]::GetTempPath()) ('bitXrestic_test_'+[Guid]::NewGuid().ToString('N'))
 try{
  $stage=Join-Path $testRoot '.bitXrestic_files_2026-10-14'
  [void][IO.Directory]::CreateDirectory((Join-Path $stage 'host/sub'))
  [IO.File]::WriteAllText((Join-Path $stage 'host/sub/export.zip'),'test')
  [IO.File]::WriteAllText((Join-Path $stage 'host/sub/export.zip.verified.json'),'{}')
  $final=Join-Path $testRoot 'backup_2026-10-14.zip';[IO.File]::WriteAllText($final,'keep')
  ClearStage $stage $testRoot '2026-10-14'
  if((Test-Path -LiteralPath $stage) -or -not (Test-Path -LiteralPath $final)){throw 'Curatare incorecta.'}
 }finally{if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}}
 Write-Host 'Teste JSON / date / servicii / curatare: OK'
} catch {Write-Host ('TEST ESUAT: '+$_.Exception.Message);exit 1}
