@echo off
rem Pulsar for Windows: builds with the csc.exe Windows already has (.NET Framework 4.8). Nothing to install.
setlocal
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
if not exist "%FW%\csc.exe" set FW=%WINDIR%\Microsoft.NET\Framework\v4.0.30319
set CSC=%FW%\csc.exe
set WPF=%FW%\WPF
set OUT=%USERPROFILE%\Desktop\Pulsar
if not exist "%OUT%" mkdir "%OUT%"
xcopy /y /q "%~dp0src\*" "%OUT%\src\" >nul
cd /d "%OUT%\src"

set REFS=/r:"%WPF%\PresentationCore.dll" /r:"%WPF%\PresentationFramework.dll" /r:"%WPF%\WindowsBase.dll" /r:"%FW%\System.Xaml.dll" /r:"%FW%\System.Windows.Forms.dll" /r:"%FW%\System.Drawing.dll" /r:"%FW%\System.Web.Extensions.dll" /r:"%FW%\System.Core.dll"
set WMD=%WINDIR%\System32\WinMetadata
set WINRT=/r:"%WMD%\Windows.Media.winmd" /r:"%WMD%\Windows.Foundation.winmd" /r:"%FW%\System.Runtime.dll" /r:"%FW%\System.Threading.Tasks.dll"
set FLAGS=/nologo /target:winexe /platform:anycpu /optimize+ /win32icon:pulsar.ico /out:"%OUT%\Pulsar.exe"

echo Building Pulsar, this can take a minute...
"%CSC%" %FLAGS% /define:MEDIA %REFS% %WINRT% *.cs > "%OUT%\build-media.log" 2>&1
if %errorlevel%==0 (
  echo   ok: music from the Windows media session
  set MODE=media
) else (
  echo   The media build failed. First lines of build-media.log:
  more +0 "%OUT%\build-media.log" | findstr /n "error" | findstr /b "[1-8]:"
  echo   Building without it.
  "%CSC%" %FLAGS% %REFS% *.cs > "%OUT%\build.log" 2>&1
  if errorlevel 1 (
    echo BUILD ERROR:
    type "%OUT%\build.log"
    pause
    exit /b 1
  )
  set MODE=fallback
)
echo.
echo Done. Open %OUT%\Pulsar.exe
pause
exit /b 0
