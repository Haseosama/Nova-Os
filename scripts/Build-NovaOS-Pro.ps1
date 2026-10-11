#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Builds a local Windows 11 Pro ISO from the source media mounted on the PC.
.DESCRIPTION
    Keeps only source install.wim index 6 (Windows 11 Professional), removes a
    conservative set of provisioned apps, applies privacy/dark-mode defaults in
    Windows specialize under SYSTEM, and adds a dark WinPE welcome launcher.

    The source media is read-only from this script's point of view. The script
    writes a separate working folder and output ISO. It does not automate disk
    partitioning, create user accounts, bypass activation, or bypass hardware
    requirements. The native Windows Setup wizard still handles installation.

    Requires Windows PowerShell 5.1, an elevated session, Windows ADK Deployment
    Tools (oscdimg.exe), and the matching Windows PE add-on with WinPE-HTA.
    Test the result in a virtual machine before using it on a physical PC.
.EXAMPLE
    .\Build-NovaOS-Pro.ps1 -SourceMedia 'F:\' `
        -OutputIso "$env:USERPROFILE\Desktop\NovaOS-Windows11-Pro.iso"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceMedia,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputIso = (Join-Path $env:USERPROFILE 'Desktop\NovaOS-Windows11-Pro.iso'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkDir = (Join-Path $env:SystemDrive 'NovaOS-Work'),

    [Parameter()]
    [string]$WinPEOCsPath,

    [Parameter()]
    [ValidateSet('fr-FR', 'en-US', 'de-DE', 'es-ES')]
    [string]$UILanguage = 'fr-FR',

    [Parameter()]
    [ValidateRange(20, 500)]
    [int]$MinimumFreeSpaceGB = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Exécutez ce script dans Windows PowerShell 5.1 (pas PowerShell 7).'
}

$sourceResolved = Resolve-Path -LiteralPath $SourceMedia -ErrorAction Stop
$sourceRoot = $sourceResolved.Path.TrimEnd('\') + '\'
$sourceInstallWim = Join-Path $sourceRoot 'sources\install.wim'
$sourceBootWim = Join-Path $sourceRoot 'sources\boot.wim'

if (-not (Test-Path -LiteralPath $sourceInstallWim -PathType Leaf)) {
    throw "Le fichier sources\install.wim est introuvable dans $sourceRoot. Montez l'ISO et indiquez sa lettre de lecteur, par exemple F:\."
}
if (-not (Test-Path -LiteralPath $sourceBootWim -PathType Leaf)) {
    throw "Le fichier sources\boot.wim est introuvable dans $sourceRoot."
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'setup.exe') -PathType Leaf)) {
    throw "setup.exe est introuvable à la racine de $sourceRoot. Ce script attend un média d'installation Windows standard monté."
}

$sourceBootSectorBios = Join-Path $sourceRoot 'boot\etfsboot.com'
$sourceBootSectorUefi = Join-Path $sourceRoot 'efi\microsoft\boot\efisys.bin'
if (-not (Test-Path -LiteralPath $sourceBootSectorBios -PathType Leaf)) {
    throw 'Le secteur de démarrage BIOS boot\etfsboot.com est introuvable dans le média source.'
}
if (-not (Test-Path -LiteralPath $sourceBootSectorUefi -PathType Leaf)) {
    throw 'Le secteur de démarrage UEFI efi\microsoft\boot\efisys.bin est introuvable dans le média source.'
}

try {
    Import-Module Dism -ErrorAction Stop
} catch {
    throw 'Le module Windows DISM est introuvable. Lancez le script depuis Windows PowerShell 5.1 sur Windows 10/11.'
}

$dismExe = Join-Path $env:WINDIR 'System32\dism.exe'
$robocopyExe = Join-Path $env:WINDIR 'System32\robocopy.exe'
if (-not (Test-Path -LiteralPath $dismExe -PathType Leaf)) { throw 'dism.exe est introuvable.' }
if (-not (Test-Path -LiteralPath $robocopyExe -PathType Leaf)) { throw 'robocopy.exe est introuvable.' }

$programFilesX86 = ${env:ProgramFiles(x86)}
if ([string]::IsNullOrWhiteSpace($programFilesX86)) { $programFilesX86 = $env:ProgramFiles }
$adkRoot = Join-Path $programFilesX86 'Windows Kits\10\Assessment and Deployment Kit'
$oscdimgCandidates = @(
    (Join-Path $adkRoot 'Deployment Tools\amd64\Oscdimg\oscdimg.exe'),
    (Join-Path $adkRoot 'Deployment Tools\x86\Oscdimg\oscdimg.exe')
)
$oscdimgExe = $oscdimgCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $oscdimgExe) {
    throw 'oscdimg.exe niet gevonden. Installeer Windows ADK > Deployment Tools en start dit script opnieuw.'
}

if ([string]::IsNullOrWhiteSpace($WinPEOCsPath)) {
    $WinPEOCsPath = Join-Path $adkRoot 'Windows Preinstallation Environment\amd64\WinPE_OCs'
}
if (-not (Test-Path -LiteralPath (Join-Path $WinPEOCsPath 'WinPE-HTA.cab') -PathType Leaf)) {
    throw "WinPE-HTA.cab introuvable dans $WinPEOCsPath. Installez le module complémentaire Windows PE de l'ADK correspondant à l'image, ou indiquez -WinPEOCsPath."
}

$requiredOCs = @('WinPE-WMI.cab', 'WinPE-NetFX.cab', 'WinPE-Scripting.cab', 'WinPE-HTA.cab')
foreach ($oc in $requiredOCs) {
    if (-not (Test-Path -LiteralPath (Join-Path $WinPEOCsPath $oc) -PathType Leaf)) {
        throw "Composant WinPE requis introuvable : $(Join-Path $WinPEOCsPath $oc)"
    }
}

$sourceImages = Get-WindowsImage -ImagePath $sourceInstallWim
$selectedSourceImage = $sourceImages | Where-Object { $_.ImageIndex -eq 6 } | Select-Object -First 1
if (-not $selectedSourceImage) {
    throw "L'index 6 est absent du install.wim source. Aucun média n'a été modifié."
}
$bootImages = Get-WindowsImage -ImagePath $sourceBootWim
if (-not ($bootImages | Where-Object { $_.ImageIndex -eq 2 })) {
    throw "L'index 2 du boot.wim (Windows Setup) est introuvable."
}

$OutputIso = [IO.Path]::GetFullPath($OutputIso)
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
$outputDirectory = Split-Path -Parent $OutputIso
if ([string]::IsNullOrWhiteSpace($outputDirectory)) { throw "Le chemin de sortie de l'ISO est invalide." }
if (Test-Path -LiteralPath $OutputIso) {
    throw "Le fichier de sortie existe déjà : $OutputIso. Choisissez un autre nom pour éviter de l'écraser."
}
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
if ($WorkDir -match '\s') {
    throw "Le dossier de travail ne doit pas contenir d'espace, car oscdimg utilise ce chemin pour les secteurs de démarrage : $WorkDir"
}

$workDriveRoot = [IO.Path]::GetPathRoot($WorkDir)
$driveInfo = [IO.DriveInfo]::new($workDriveRoot)
$requiredBytes = [int64]$MinimumFreeSpaceGB * [int64]1024 * [int64]1024 * [int64]1024
if ($driveInfo.AvailableFreeSpace -lt $requiredBytes) {
    $freeGB = [math]::Round($driveInfo.AvailableFreeSpace / 1073741824.0, 1)
    throw "Espace insuffisant sur $workDriveRoot : $freeGB Go libres ; au moins $MinimumFreeSpaceGB Go sont requis."
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$buildRoot = Join-Path $WorkDir "NovaOS-Pro-$timestamp"
$stagingMedia = Join-Path $buildRoot 'Media'
$installMount = Join-Path $buildRoot 'Mount-Install'
$bootMount = Join-Path $buildRoot 'Mount-Boot'
$logPath = Join-Path $buildRoot 'Build-NovaOS.log'
$stagedInstallWim = Join-Path $stagingMedia 'sources\install.wim'
$stagedBootWim = Join-Path $stagingMedia 'sources\boot.wim'
New-Item -ItemType Directory -Path $stagingMedia, $installMount, $bootMount -Force | Out-Null

Write-Host ''
Write-Host 'NovaOS — préparation du média Windows 11 Professionnel' -ForegroundColor Cyan
Write-Host "Source monté : $sourceRoot"
Write-Host "Édition sélectionnée : index 6 — $($selectedSourceImage.ImageName)"
Write-Host "Actions : index 6 uniquement, retrait ciblé d'applications, réglages pendant specialize, lanceur WinPE sombre."
Write-Host "Le média source reste intact. Le partitionnement, l'activation et l'assistant Windows restent manuels."
Write-Host "Espace libre requis : au moins $MinimumFreeSpaceGB Go."
Write-Host "Sortie prévue : $OutputIso"
$confirmation = Read-Host 'Pour continuer après vérification, tapez BUILD'
if ($confirmation -cne 'BUILD') {
    Write-Host 'Annulé. Aucun fichier ISO de sortie créé.' -ForegroundColor Yellow
    return
}

Start-Transcript -Path $logPath -Force | Out-Null
$installMounted = $false
$bootMounted = $false
try {
    Write-Host ''
    Write-Host '1/5 — Copie des fichiers du média source...' -ForegroundColor Cyan
    & $robocopyExe $sourceRoot $stagingMedia /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XF install.wim install.esd 'install*.swm' "/LOG:$buildRoot\Robocopy.log"
    $robocopyCode = $LASTEXITCODE
    if ($robocopyCode -ge 8) { throw "Robocopy a échoué avec le code $robocopyCode. Consultez $buildRoot\Robocopy.log" }

    Write-Host "2/5 — Export de l'index 6 uniquement..." -ForegroundColor Cyan
    if (Test-Path -LiteralPath $stagedInstallWim) { Remove-Item -LiteralPath $stagedInstallWim -Force }
    try {
        Export-WindowsImage -SourceImagePath $sourceInstallWim -SourceIndex 6 -DestinationImagePath $stagedInstallWim -CompressionType Max -CheckIntegrity -ErrorAction Stop | Out-Null
    } catch {
        throw "L'export de l'image avec DISM a échoué : $($_.Exception.Message)"
    }

    foreach ($wimPath in @($stagedInstallWim, $stagedBootWim)) {
        $wimFile = Get-Item -LiteralPath $wimPath -ErrorAction Stop
        if ($wimFile.IsReadOnly) { $wimFile.IsReadOnly = $false }
    }

    Write-Host '3/5 — Maintenance de Windows 11 Pro (index de sortie 1)...' -ForegroundColor Cyan
    Mount-WindowsImage -ImagePath $stagedInstallWim -Index 1 -Path $installMount -CheckIntegrity | Out-Null
    $installMounted = $true

    $appPatterns = @(
        'Clipchamp.Clipchamp',
        'Microsoft.BingNews',
        'Microsoft.BingWeather',
        'Microsoft.GetHelp',
        'Microsoft.Getstarted',
        'Microsoft.GamingApp',
        'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.People',
        'Microsoft.PowerAutomateDesktop',
        'Microsoft.Todos',
        'Microsoft.Windows.DevHome',
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.Xbox*',
        'Microsoft.YourPhone',
        'Microsoft.ZuneMusic',
        'Microsoft.ZuneVideo',
        'MicrosoftTeams',
        'MSTeams'
    )
    $provisioned = Get-AppxProvisionedPackage -Path $installMount
    foreach ($package in $provisioned) {
        $matchedPattern = $appPatterns | Where-Object { $package.DisplayName -like $_ } | Select-Object -First 1
        if ($matchedPattern) {
            Write-Host "  Retrait du package provisionné : $($package.DisplayName)" -ForegroundColor DarkGray
            try {
                Remove-AppxProvisionedPackage -Path $installMount -PackageName $package.PackageName -ErrorAction Stop | Out-Null
            } catch {
                Write-Warning "Package conservé ($($package.DisplayName)) : $($_.Exception.Message)"
            }
        }
    }

    # Machine policies and default-user visual settings are applied later in the
    # Windows specialize pass, where Setup runs with SYSTEM privileges.

    Dismount-WindowsImage -Path $installMount -Save -CheckIntegrity | Out-Null
    $installMounted = $false

    Write-Host "4/5 — Ajout de l'écran de bienvenue NovaOS à WinPE..." -ForegroundColor Cyan
    Mount-WindowsImage -ImagePath $stagedBootWim -Index 2 -Path $bootMount -CheckIntegrity | Out-Null
    $bootMounted = $true

    $installedBootPackages = Get-WindowsPackage -Path $bootMount
    foreach ($oc in $requiredOCs) {
        $packageStem = [IO.Path]::GetFileNameWithoutExtension($oc)
        $alreadyInstalled = $installedBootPackages | Where-Object { $_.PackageName -like "$packageStem-Package*" } | Select-Object -First 1
        if (-not $alreadyInstalled) {
            $packagePath = Join-Path $WinPEOCsPath $oc
            Write-Host "  Ajout du composant $packageStem" -ForegroundColor DarkGray
            Add-WindowsPackage -Path $bootMount -PackagePath $packagePath -NoRestart | Out-Null
        }
    }

    $system32 = Join-Path $bootMount 'Windows\System32'
    $originalWinpeshl = Join-Path $system32 'winpeshl.ini'
    if (Test-Path -LiteralPath $originalWinpeshl -PathType Leaf) {
        Copy-Item -LiteralPath $originalWinpeshl -Destination (Join-Path $buildRoot 'winpeshl-original.ini') -Force
    }

    $launcherPath = Join-Path $system32 'NovaOS-Launcher.hta'
    @'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta charset="utf-8">
<title>NovaOS Setup</title>
<HTA:APPLICATION ID="NovaOSSetup" APPLICATIONNAME="NovaOS Setup" BORDER="none" CAPTION="no" SHOWINTASKBAR="no" SINGLEINSTANCE="yes" SCROLL="no" WINDOWSTATE="maximize" />
<style>
* { box-sizing: border-box; }
html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
body { color: #edf3f1; font-family: "Segoe UI", Arial, sans-serif; background: #080d12; }
.shell { position: relative; width: 100%; height: 100%; overflow: hidden; background: radial-gradient(ellipse at 79% 47%, #172a29 0, #0c151a 32%, #080d12 72%); }
.grid { position: absolute; inset: 0; opacity: .16; background-image: linear-gradient(rgba(168,215,192,.14) 1px, transparent 1px), linear-gradient(90deg, rgba(168,215,192,.14) 1px, transparent 1px); background-size: 42px 42px; }
.glow { position: absolute; top: 50%; right: 8%; width: 470px; height: 470px; border: 1px solid rgba(182,241,123,.2); border-radius: 50%; transform: translateY(-50%); box-shadow: 0 0 90px rgba(106,194,139,.08), inset 0 0 80px rgba(106,194,139,.035); }
.glow:before, .glow:after { position: absolute; content: ""; border: 1px solid rgba(182,241,123,.17); border-radius: 50%; }
.glow:before { inset: 34px; }
.glow:after { inset: 80px; border-style: dashed; }
.content { position: absolute; top: 50%; left: 10%; width: 50%; max-width: 680px; transform: translateY(-50%); }
.eyebrow { display: flex; align-items: center; gap: 10px; color: #91aa9c; font: 12px Consolas, monospace; letter-spacing: 3px; }
.mark { width: 8px; height: 8px; background: #b6f17b; transform: rotate(45deg); box-shadow: 0 0 15px rgba(182,241,123,.7); }
h1 { margin: 26px 0 16px; font-size: 64px; font-weight: 500; letter-spacing: -3px; line-height: 1.05; }
h1 span { color: #b6f17b; }
.desc { max-width: 520px; color: #a8b6b7; font-size: 18px; line-height: 1.7; }
.meta { display: flex; gap: 22px; margin-top: 26px; color: #82938e; font: 11px Consolas, monospace; letter-spacing: 1px; }
.meta b { color: #c3d3c6; font-weight: 400; }
.button { display: inline-block; margin-top: 33px; padding: 15px 21px; border: 1px solid #b6f17b; border-radius: 4px; background: #b6f17b; color: #101911; font-size: 14px; font-weight: 700; letter-spacing: .4px; cursor: pointer; }
.button:hover { background: #d0ff9e; }
.note { margin-top: 13px; color: #798984; font-size: 11px; line-height: 1.6; }
.logo { position: absolute; top: 42px; left: 10%; display: flex; align-items: center; gap: 12px; color: #eff5f1; font-size: 18px; font-weight: 700; letter-spacing: 4px; }
.logo-mark { display: grid; width: 37px; height: 37px; place-items: center; border: 1px solid rgba(182,241,123,.55); border-radius: 10px; color: #b6f17b; font-size: 22px; font-weight: 500; transform: rotate(45deg); }
.logo-mark span { transform: rotate(-45deg); }
.logo small { display: block; margin-top: 3px; color: #81938a; font: 8px Consolas, monospace; letter-spacing: 2px; }
.footer { position: absolute; right: 10%; bottom: 35px; left: 10%; display: flex; justify-content: space-between; padding-top: 14px; border-top: 1px solid rgba(163,190,180,.16); color: #70817d; font: 10px Consolas, monospace; letter-spacing: 1px; }
.footer b { color: #adc69e; font-weight: 400; }
@media screen and (max-width: 900px) { .content { left: 7%; width: 76%; } .logo { left: 7%; } h1 { font-size: 48px; } .glow { right: -30%; opacity: .6; } .footer { right: 7%; left: 7%; } }
</style>
<script language="JScript">
function findInstallMedia() {
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    for (var code = 67; code <= 90; code++) {
        var root = String.fromCharCode(code) + ":\\";
        var hasImage = fso.FileExists(root + "sources\\install.wim") || fso.FileExists(root + "sources\\install.esd");
        if (hasImage && fso.FileExists(root + "setup.exe")) return root;
    }
    return "";
}
function startSetup() {
    var root = findInstallMedia();
    if (!root) {
        document.getElementById("status").innerText = "Média Windows introuvable. Vérifiez que le support d’installation est connecté, puis réessayez.";
        return;
    }
    var shell = new ActiveXObject("WScript.Shell");
    shell.Run('"' + root + 'setup.exe"', 1, false);
    window.close();
}
</script>
</head>
<body>
<div class="shell"><div class="grid"></div><div class="glow"></div>
  <div class="logo"><div class="logo-mark"><span>N</span></div><div>NOVAOS<small>INSTALLATION ENVIRONMENT</small></div></div>
  <main class="content">
    <div class="eyebrow"><span class="mark"></span> WINDOWS 11 PRO · X64</div>
    <h1>Votre système.<br><span>Vos règles.</span></h1>
    <div class="desc">L’environnement NovaOS est prêt. Lancez l’installation de Windows 11 Professionnel et configurez votre appareil à votre rythme.</div>
    <div class="meta"><span>ÉDITION <b>PRO</b></span><span>MODE <b>LOCAL</b></span><span>SETUP <b>MICROSOFT</b></span></div>
    <button class="button" onclick="startSetup()">Démarrer l’installation <span aria-hidden="true">&nbsp; →</span></button>
    <div class="note" id="status">Le choix du disque, l’activation et les exigences matérielles restent gérés par Windows Setup.</div>
  </main>
  <div class="footer"><span>PRE-INSTALLATION · NOVAOS</span><span>UNE CONFIGURATION <b>À VOTRE IMAGE</b></span></div>
</div>
</body>
</html>
'@ | Set-Content -LiteralPath $launcherPath -Encoding Unicode

    $startScript = Join-Path $system32 'NovaOS-Start.cmd'
    @'
@echo off
wpeinit
start "" /wait "%SystemRoot%\System32\mshta.exe" "%SystemRoot%\System32\NovaOS-Launcher.hta"
echo.
echo NovaOS Setup Launcher closed. Use the Windows Setup screen or restart the computer.
'@ | Set-Content -LiteralPath $startScript -Encoding ASCII

    $winpeshl = Join-Path $system32 'winpeshl.ini'
    @'
[LaunchApp]
AppPath = %SYSTEMROOT%\System32\cmd.exe
CmdLine = /k %SYSTEMROOT%\System32\NovaOS-Start.cmd
'@ | Set-Content -LiteralPath $winpeshl -Encoding ASCII

    Dismount-WindowsImage -Path $bootMount -Save -CheckIntegrity | Out-Null
    $bootMounted = $false

    Write-Host '5/5 — Configuration de Setup et reconstruction ISO bootable...' -ForegroundColor Cyan
    $eiCfg = Join-Path $stagingMedia 'sources\ei.cfg'
    @'
[EditionID]
Professional
[Channel]
Retail
[VL]
0
'@ | Set-Content -LiteralPath $eiCfg -Encoding ASCII

    $oemScriptsDir = Join-Path $stagingMedia 'sources\$OEM$\$$\Setup\Scripts'
    New-Item -ItemType Directory -Path $oemScriptsDir -Force | Out-Null
    $configureScript = Join-Path $oemScriptsDir 'NovaOS-Configure.cmd'
    @'
@echo off
setlocal
set "LOG=%WINDIR%\Temp\NovaOS-Configure.log"
echo NovaOS specialize settings > "%LOG%"
rem AllowTelemetry=1 is the minimum generally supported on Pro, not zero telemetry.
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableTailoredExperiencesWithDiagnosticData /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableActivityFeed /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v PublishUserActivities /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v UploadUserActivities /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v DisableWebSearch /t REG_DWORD /d 1 /f >> "%LOG%" 2>&1
reg.exe load HKU\NOVAOS_DEFAULT "%SystemDrive%\Users\Default\NTUSER.DAT" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo Default user hive could not be loaded; skipping per-user defaults. >> "%LOG%"
  exit /b 0
)
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v SystemUsesLightTheme /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SystemPaneSuggestionsEnabled /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338388Enabled /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe add "HKU\NOVAOS_DEFAULT\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg.exe unload HKU\NOVAOS_DEFAULT >> "%LOG%" 2>&1
exit /b 0
'@ | Set-Content -LiteralPath $configureScript -Encoding ASCII

    $localeData = @{
        'fr-FR' = @{ Input = '040c:0000040c' }
        'en-US' = @{ Input = '0409:00000409' }
        'de-DE' = @{ Input = '0407:00000407' }
        'es-ES' = @{ Input = '0c0a:0000040a' }
    }[$UILanguage]
    $answerFile = Join-Path $stagingMedia 'autounattend.xml'
    @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <!-- NovaOS: prefill language and keyboard; no disk, activation, or account automation. -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$UILanguage</UILanguage></SetupUILanguage>
      <InputLocale>$($localeData.Input)</InputLocale>
      <SystemLocale>$UILanguage</SystemLocale>
      <UILanguage>$UILanguage</UILanguage>
      <UserLocale>$UILanguage</UserLocale>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Apply NovaOS machine policies and dark defaults</Description>
          <Path>cmd.exe /c if exist &quot;%WINDIR%\Setup\Scripts\NovaOS-Configure.cmd&quot; call &quot;%WINDIR%\Setup\Scripts\NovaOS-Configure.cmd&quot;</Path>
          <WillReboot>Never</WillReboot>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>$($localeData.Input)</InputLocale>
      <SystemLocale>$UILanguage</SystemLocale>
      <UILanguage>$UILanguage</UILanguage>
      <UserLocale>$UILanguage</UserLocale>
    </component>
  </settings>
</unattend>
"@ | Set-Content -LiteralPath $answerFile -Encoding UTF8

    $biosBootImage = Join-Path $stagingMedia 'boot\etfsboot.com'
    $uefiBootImage = Join-Path $stagingMedia 'efi\microsoft\boot\efisys.bin'
    $bootData = '-bootdata:2#p0,e,b' + $biosBootImage + '#pEF,e,b' + $uefiBootImage
    $volumeLabel = 'NOVAOS_W11_PRO'
    $volumeOption = '-l' + $volumeLabel
    $oscdimgLog = Join-Path $buildRoot 'Oscdimg.log'
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 can turn native stderr output into a terminating
        # NativeCommandError when ErrorActionPreference is Stop. Merge the streams
        # and check oscdimg's actual exit code instead of treating stderr as failure.
        $ErrorActionPreference = 'Continue'
        & $oscdimgExe '-m' '-o' '-u2' '-udfver102' $volumeOption $bootData $stagingMedia $OutputIso 2>&1 |
            Tee-Object -FilePath $oscdimgLog
        $oscdimgExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($oscdimgExitCode -ne 0) {
        throw "oscdimg.exe a échoué (code $oscdimgExitCode). Consultez $oscdimgLog. L'espace de travail est conservé dans $buildRoot"
    }
    if (-not (Test-Path -LiteralPath $OutputIso -PathType Leaf)) {
        throw "oscdimg.exe a retourné le code 0, mais l'ISO de sortie est introuvable : $OutputIso"
    }

    Write-Host ''
    Write-Host 'Build terminé.' -ForegroundColor Green
    Write-Host "ISO : $OutputIso" -ForegroundColor Green
    Write-Host "Journal : $logPath"
    Write-Host "Espace de travail conservé : $buildRoot"
    Write-Host "Testez l'ISO dans une machine virtuelle avant toute installation réelle." -ForegroundColor Yellow
} finally {
    if ($installMounted) {
        try { Dismount-WindowsImage -Path $installMount -Discard -ErrorAction Stop | Out-Null }
        catch { Write-Warning "Impossible de démonter le WIM Windows : $($_.Exception.Message)" }
    }
    if ($bootMounted) {
        try { Dismount-WindowsImage -Path $bootMount -Discard -ErrorAction Stop | Out-Null }
        catch { Write-Warning "Impossible de démonter le WIM WinPE : $($_.Exception.Message)" }
    }
    try { Stop-Transcript | Out-Null } catch { }
}
