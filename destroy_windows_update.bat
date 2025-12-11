@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

:: --------------------------------------------------------------------
:: destroy_windows_update.bat
:: 激进版：彻底破坏 Windows Update（不可逆）。以管理员权限运行。
:: 最后确认
:: --------------------------------------------------------------------
echo *****************************************************************
echo WARNING: THIS SCRIPT WILL IRREVERSIBLY DISABLE AND REMOVE WINDOWS UPDATE
echo - No security updates, no feature updates, no Defender updates.
echo - Recovery typically requires OS reinstall.
echo *****************************************************************
echo.
choice /M "Type Y to proceed and execute the destructive actions (N to abort)"
if errorlevel 2 goto abort
if errorlevel 1 goto proceed

:abort
echo Aborted by user.
pause
exit /b 1

:proceed
echo Running destructive Windows Update teardown...
echo Ensure you ran this as Administrator (or SYSTEM). Continuing in 3 seconds...
timeout /t 3 /nobreak >nul

:: ---------------------------
:: 1) Stop and disable update-related services
:: ---------------------------
echo Stopping update services...
sc stop wuauserv >nul 2>&1
sc stop bits >nul 2>&1
sc stop cryptsvc >nul 2>&1
sc stop trustedinstaller >nul 2>&1
sc stop UsoSvc >nul 2>&1
sc stop WaaSMedicSvc >nul 2>&1
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
net stop cryptsvc >nul 2>&1

echo Disabling update services...
sc config wuauserv start= disabled >nul 2>&1
sc config bits start= disabled >nul 2>&1
sc config cryptsvc start= disabled >nul 2>&1
sc config TrustedInstaller start= disabled >nul 2>&1
sc config UsoSvc start= disabled >nul 2>&1
sc config WaaSMedicSvc start= disabled >nul 2>&1

:: Attempt delete service entries (may fail silently)
sc delete WaaSMedicSvc >nul 2>&1
sc delete UsoSvc >nul 2>&1

:: ---------------------------
:: 2) Kill related processes
:: ---------------------------
echo Killing update processes...
taskkill /F /IM wuauclt.exe >nul 2>&1
taskkill /F /IM TiWorker.exe >nul 2>&1
taskkill /F /IM usoClient.exe >nul 2>&1
taskkill /F /IM MoUsoCoreWorker.exe >nul 2>&1
taskkill /F /IM TrustedInstaller.exe >nul 2>&1

:: ---------------------------
:: 3) Take ownership and remove scheduled tasks (UpdateOrchestrator & WindowsUpdate)
:: ---------------------------
echo Taking ownership of scheduled tasks and removing them...
takeown /F "%windir%\System32\Tasks\Microsoft\Windows\UpdateOrchestrator" /A /R >nul 2>&1
icacls "%windir%\System32\Tasks\Microsoft\Windows\UpdateOrchestrator" /grant Administrators:F /T >nul 2>&1
takeown /F "%windir%\System32\Tasks\Microsoft\Windows\WindowsUpdate" /A /R >nul 2>&1
icacls "%windir%\System32\Tasks\Microsoft\Windows\WindowsUpdate" /grant Administrators:F /T >nul 2>&1

echo Deleting scheduled task files...
del /F /Q "%windir%\System32\Tasks\Microsoft\Windows\UpdateOrchestrator\*" >nul 2>&1
rmdir /S /Q "%windir%\System32\Tasks\Microsoft\Windows\UpdateOrchestrator" >nul 2>&1
del /F /Q "%windir%\System32\Tasks\Microsoft\Windows\WindowsUpdate\*" >nul 2>&1
rmdir /S /Q "%windir%\System32\Tasks\Microsoft\Windows\WindowsUpdate" >nul 2>&1

:: Also try to unregister via schtasks
schtasks /Delete /TN "\Microsoft\Windows\UpdateOrchestrator\Reboot" /F >nul 2>&1
schtasks /Delete /TN "\Microsoft\Windows\WindowsUpdate\Scheduled Start" /F >nul 2>&1

:: ---------------------------
:: 4) Remove update executables (rename to .bak first where possible)
:: ---------------------------
echo Taking ownership of update executables and removing them...
for %%F in (
    "%windir%\System32\usoclient.exe"
    "%windir%\System32\UsoClient.exe"
    "%windir%\System32\musgeneration.dll"
    "%windir%\System32\MoUsoCoreWorker.exe"
    "%windir%\System32\WaaSMedicSvc.dll"
    "%windir%\System32\WaaSMedic.exe"
    "%windir%\System32\wuauclt.exe"
    "%windir%\System32\wuaueng.dll"
    "%windir%\System32\wuapi.dll"
    "%windir%\System32\wuaueng1.dll"
    "%windir%\System32\wups2.dll"
    "%windir%\System32\wups.dll"
) do (
    if exist "%%~F" (
        takeown /F "%%~F" /A >nul 2>&1
        icacls "%%~F" /grant Administrators:F >nul 2>&1
        attrib -s -h "%%~F" 2>nul
        echo Deleting: %%~F
        del /F /Q "%%~F" >nul 2>&1
        if exist "%%~F" (
            ren "%%~F" "%%~nxF.bak" >nul 2>&1
        )
    )
)

:: ---------------------------
:: 5) Rename / remove update-related folders (SoftwareDistribution, catroot2, $WINDOWS.~BT, UpdateProvider)
:: ---------------------------
echo Renaming update cache folders (SoftwareDistribution, catroot2, $WINDOWS.~BT) ...
attrib -s -h "%windir%\SoftwareDistribution" >nul 2>&1
attrib -s -h "%windir%\System32\catroot2" >nul 2>&1

ren "%windir%\SoftwareDistribution" "SoftwareDistribution.disabled" >nul 2>&1
ren "%windir%\System32\catroot2" "catroot2.disabled" >nul 2>&1

:: remove Windows upgrade temp folders if exist
if exist "%SystemDrive%\$WINDOWS.~BT" (
    rmdir /S /Q "%SystemDrive%\$WINDOWS.~BT" >nul 2>&1
)
if exist "%SystemDrive%\$WINDOWS.~WS" (
    rmdir /S /Q "%SystemDrive%\$WINDOWS.~WS" >nul 2>&1
)

:: ---------------------------
:: 6) Remove Update Medic / WaaSMedic hooks and services
:: ---------------------------
echo Removing WaaSMedic related files and service...
takeown /F "%windir%\ServiceProfiles\LocalService\AppData\Local\Microsoft\WaaSMedic" /A /R >nul 2>&1
icacls "%windir%\ServiceProfiles\LocalService\AppData\Local\Microsoft\WaaSMedic" /grant Administrators:F /T >nul 2>&1
rmdir /S /Q "%windir%\ServiceProfiles\LocalService\AppData\Local\Microsoft\WaaSMedic" >nul 2>&1

takeown /F "%windir%\system32\WaaSMedicSvc.dll" /A >nul 2>&1
icacls "%windir%\system32\WaaSMedicSvc.dll" /grant Administrators:F >nul 2>&1
del /F /Q "%windir%\system32\WaaSMedicSvc.dll" >nul 2>&1

:: ---------------------------
:: 7) Registry locks / policies to block update functionality and Windows Update UI
:: ---------------------------
echo Adding registry policies to block Windows Update and access...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWindowsUpdateAccess /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" /v ElevatedAllowed /t REG_DWORD /d 0 /f >nul 2>&1

:: Disable access to Windows Update UI
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoWindowsUpdate /t REG_DWORD /d 1 /f >nul 2>&1

:: ---------------------------
:: 8) Remove servicing stack / updates metadata (attempt - may require WinPE)
:: ---------------------------
echo Attempting to rename parts of WinSxS servicing metadata (may fail on live system)...
takeown /F "%windir%\winsxs\pending.xml" /A >nul 2>&1
del /F /Q "%windir%\winsxs\pending.xml" >nul 2>&1

ren "%windir%\winsxs\Manifests" "Manifests.disabled" >nul 2>&1 2>nul
ren "%windir%\winsxs\Backup" "Backup.disabled" >nul 2>&1 2>nul

:: ---------------------------
:: 9) Final cleanup: remove update-related scheduled tasks in Registry
:: ---------------------------
echo Cleaning scheduled tasks registry entries...
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\UpdateOrchestrator" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\WindowsUpdate" /f >nul 2>&1

:: ---------------------------
:: 10) Final disable: block common update domains via hosts (best-effort)
:: ---------------------------
echo Blocking update domains in hosts file (best-effort)...
takeown /F "%windir%\System32\drivers\etc\hosts" /A >nul 2>&1
icacls "%windir%\System32\drivers\etc\hosts" /grant Administrators:F >nul 2>&1
(
    echo 127.0.0.1 windowsupdate.microsoft.com
    echo 127.0.0.1 update.microsoft.com
    echo 127.0.0.1 download.windowsupdate.com
    echo 127.0.0.1 wustat.windows.com
    echo 127.0.0.1 wua.microsoft.com
) >> "%windir%\System32\drivers\etc\hosts"

:: ---------------------------
:: 11) Final service stop & reboot suggestion
:: ---------------------------
echo.
echo Destructive operations attempted. Some protected files may still remain because they are in-use.
echo For absolute destruction, boot into WinPE/WinRE and run this script there (or manually delete the renamed .disabled folders and remaining files).
echo *** SYSTEM MAY BE UNSTABLE. RESTART IS RECOMMENDED. ***
echo If you want to attempt an immediate reboot, press Y now.
choice /M "Reboot now?" /N
if errorlevel 2 goto end
if errorlevel 1 (shutdown /r /t 5) 

:end
echo Done. IMPORTANT: To recover, you will most likely need to reinstall Windows.
pause
ENDLOCAL
exit /b 0
