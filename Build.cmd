@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -Command "$t=$null;$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Get-Location) 'Export.ps1'),[ref]$t,[ref]$e);if($e.Count){$e | Format-List;exit 1}"
if errorlevel 1 goto fail
powershell.exe -NoProfile -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path (Get-Location) 'TestCore.ps1'))))"
if errorlevel 1 goto fail
set "EXPORT_CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%EXPORT_CSC%" set "EXPORT_CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%EXPORT_CSC%" goto fail
"%EXPORT_CSC%" /nologo /target:winexe /reference:System.Windows.Forms.dll /win32icon:bitXrestic.ico /resource:bitXrestic.ico,bitXrestic.ico /resource:restic.exe,restic.exe /resource:Export.ps1,Export.ps1 /out:bitXrestic.exe Launcher.cs
if errorlevel 1 goto fail
start "" "%~dp0bitXrestic.exe"
exit /b 0
:fail
echo Build failed. Please share the error shown above.
pause
exit /b 1
