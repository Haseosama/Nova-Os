#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Construit l'ISO Nova-Os a partir d'un ISO officiel de Windows 11.

.DESCRIPTION
    Monte l'ISO d'origine, applique les modifications decrites dans config.psd1
    (suppression d'applis, contournement TPM/Secure Boot, telemetrie, compte local...)
    puis genere un nouvel ISO amorcable avec oscdimg.

.PARAMETER IsoPath
    Chemin de l'ISO Windows 11 d'origine.

.PARAMETER OutputIso
    Chemin de l'ISO a produire. Par defaut : .\out\Nova-Os.iso

.PARAMETER ImageIndex
    Index de l'edition a garder (ex. Famille, Pro). Si absent, la liste est affichee et demandee.

.PARAMETER ConfigPath
    Fichier de configuration. Par defaut : config.psd1 a cote du script.

.PARAMETER WorkDir
    Dossier de travail temporaire (prevoir ~15 Go libres). Par defaut : .\work

.PARAMETER OscdimgPath
    Chemin de oscdimg.exe si le Windows ADK n'est pas installe a l'emplacement standard.

.EXAMPLE
    .\Build-NovaOS.ps1 -IsoPath D:\ISO\Win11_24H2_French_x64.iso
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $IsoPath,
    [string] $OutputIso = (Join-Path $PSScriptRoot 'out\Nova-Os.iso'),
    [int]    $ImageIndex,
    [string] $ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),
    [string] $WorkDir = (Join-Path $PSScriptRoot 'work'),
    [string] $OscdimgPath
)

$ErrorActionPreference = 'Stop'

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Registre hors ligne
# ---------------------------------------------------------------------------

function Mount-OfflineHives([string] $ImageRoot) {
    reg load HKLM\NOVA_SOFTWARE "$ImageRoot\Windows\System32\config\SOFTWARE" | Out-Null
    reg load HKLM\NOVA_SYSTEM   "$ImageRoot\Windows\System32\config\SYSTEM"   | Out-Null
    if (Test-Path "$ImageRoot\Users\Default\NTUSER.DAT") {
        reg load HKLM\NOVA_DEFAULT "$ImageRoot\Users\Default\NTUSER.DAT" | Out-Null
    }
}

function Dismount-OfflineHives {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    foreach ($hive in 'NOVA_SOFTWARE', 'NOVA_SYSTEM', 'NOVA_DEFAULT') {
        if (Test-Path "Registry::HKEY_LOCAL_MACHINE\$hive") {
            reg unload "HKLM\$hive" | Out-Null
        }
    }
}

function Set-Reg([string] $Key, [string] $Name, [uint32] $Value) {
    reg add "HKLM\$Key" /v $Name /t REG_DWORD /d ('0x{0:X}' -f $Value) /f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Echec de l'ecriture de HKLM\$Key\$Name" }
}

function Set-RegString([string] $Key, [string] $Name, [string] $Value) {
    reg add "HKLM\$Key" /v $Name /t REG_SZ /d $Value /f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Echec de l'ecriture de HKLM\$Key\$Name" }
}

function Set-HardwareBypass {
    foreach ($name in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassCPUCheck', 'BypassStorageCheck') {
        Set-Reg 'NOVA_SYSTEM\Setup\LabConfig' $name 1
    }
    Set-Reg 'NOVA_SYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 1
}

function Set-ImageTweaks($Config) {
    $hasDefaultUser = Test-Path 'Registry::HKEY_LOCAL_MACHINE\NOVA_DEFAULT'

    if ($Config.BypassHardwareChecks) {
        Write-Host '  - Contournement TPM / Secure Boot / RAM / CPU'
        Set-HardwareBypass
        if ($hasDefaultUser) {
            Set-Reg 'NOVA_DEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 0
            Set-Reg 'NOVA_DEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 0
        }
    }

    if ($Config.AllowLocalAccount) {
        Write-Host '  - Compte local autorise (BypassNRO)'
        Set-Reg 'NOVA_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 1
    }

    if ($Config.DisableTelemetry) {
        Write-Host '  - Telemetrie desactivee'
        Set-Reg 'NOVA_SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
        Set-Reg 'NOVA_SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
        Set-Reg 'NOVA_SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
        Set-Reg 'NOVA_SYSTEM\ControlSet001\Services\DiagTrack' 'Start' 4
        Set-Reg 'NOVA_SYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 4
        if ($hasDefaultUser) {
            Set-Reg 'NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
            Set-Reg 'NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        }
    }

    if ($Config.DisableConsumerFeatures) {
        Write-Host '  - Applis suggerees desactivees'
        Set-Reg 'NOVA_SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
        if ($hasDefaultUser) {
            $cdm = 'NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            foreach ($name in 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'OemPreInstalledAppsEnabled',
                              'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled') {
                Set-Reg $cdm $name 0
            }
        }
    }

    if ($Config.DisableCopilot) {
        Write-Host '  - Copilot desactive'
        Set-Reg 'NOVA_SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        if ($hasDefaultUser) {
            Set-Reg 'NOVA_DEFAULT\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        }
    }

    if ($Config.Theme.Enabled) {
        Write-Host '  - Theme futuriste (mode sombre, accent neon, fond d''ecran)'
        Set-ThemeRegistry $Config.Theme $hasDefaultUser
    }

    if ($Config.GamingTweaks) {
        Write-Host '  - Optimisations jeux'
        Set-GamingTweaks $hasDefaultUser
    }

    if ($Config.DisableVBS) {
        Write-Host '  - Integrite de la memoire (VBS) desactivee'
        Set-Reg 'NOVA_SYSTEM\ControlSet001\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
        Set-Reg 'NOVA_SYSTEM\ControlSet001\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
    }

    if ($Config.DisableReservedStorage) {
        Write-Host '  - Stockage reserve desactive'
        Set-Reg 'NOVA_SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 0
    }
}

# ---------------------------------------------------------------------------
# Theme futuriste
# ---------------------------------------------------------------------------

# Dossier ou Nova-Os depose ses fichiers dans l'image (fond d'ecran, theme, scripts).
$NovaDirInImage = 'Windows\NovaOS'

function ConvertFrom-HexColor([string] $Hex) {
    $h = $Hex.TrimStart('#')
    if ($h -notmatch '^[0-9A-Fa-f]{6}$') { throw "Couleur invalide : $Hex (format attendu : #RRGGBB)" }
    [pscustomobject]@{
        R = [Convert]::ToByte($h.Substring(0, 2), 16)
        G = [Convert]::ToByte($h.Substring(2, 2), 16)
        B = [Convert]::ToByte($h.Substring(4, 2), 16)
    }
}

function Install-ThemeFiles([string] $ImageRoot, $Theme) {
    $dir = Join-Path $ImageRoot $NovaDirInImage
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $wallpaper = $Theme.Wallpaper
    if (-not [IO.Path]::IsPathRooted($wallpaper)) { $wallpaper = Join-Path $PSScriptRoot $wallpaper }
    Copy-Item $wallpaper (Join-Path $dir 'wallpaper.jpg') -Force

    $c = ConvertFrom-HexColor $Theme.AccentColor
    $colorization = '0XC4{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
    @"
[Theme]
DisplayName=Nova-Os

[Control Panel\Desktop]
Wallpaper=%SystemRoot%\NovaOS\wallpaper.jpg
TileWallpaper=0
WallpaperStyle=10
Pattern=

[VisualStyles]
Path=%SystemRoot%\resources\Themes\Aero\Aero.msstyles
ColorStyle=NormalColor
Size=NormalSize
AutoColorization=0
ColorizationColor=$colorization
SystemMode=Dark
AppMode=Dark
VisualStyleVersion=10

[MasterThemeSelector]
MTSM=RJSPBS
"@ | Set-Content (Join-Path $dir 'NovaOS.theme') -Encoding Unicode
}

function Set-ThemeRegistry($Theme, [bool] $HasDefaultUser) {
    $wallpaper = "C:\$NovaDirInImage\wallpaper.jpg"

    # Ecran de verrouillage (fonctionne aussi sur Famille et Pro via PersonalizationCSP).
    $csp = 'NOVA_SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
    Set-RegString $csp 'LockScreenImagePath' $wallpaper
    Set-RegString $csp 'LockScreenImageUrl' $wallpaper
    Set-Reg $csp 'LockScreenImageStatus' 1

    if (-not $HasDefaultUser) { return }
    $c = ConvertFrom-HexColor $Theme.AccentColor
    $abgr = [uint32](([uint32]255 -shl 24) -bor ([uint32]$c.B -shl 16) -bor ([uint32]$c.G -shl 8) -bor $c.R)

    $personalize = 'NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-Reg $personalize 'AppsUseLightTheme' 0
    Set-Reg $personalize 'SystemUsesLightTheme' 0
    Set-Reg $personalize 'EnableTransparency' 1
    Set-Reg $personalize 'ColorPrevalence' 1            # accent sur la barre des taches et Demarrer
    Set-Reg 'NOVA_DEFAULT\Software\Microsoft\Windows\DWM' 'AccentColor' $abgr
    Set-Reg 'NOVA_DEFAULT\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 1   # accent sur les barres de titre
    Set-Reg 'NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'AccentColorMenu' $abgr
    Set-Reg 'NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' 'StartColorMenu' $abgr
    Set-RegString 'NOVA_DEFAULT\Control Panel\Desktop' 'WallPaper' $wallpaper
    Set-RegString 'NOVA_DEFAULT\Control Panel\Desktop' 'WallpaperStyle' '10'
}

# ---------------------------------------------------------------------------
# Optimisations jeux
# ---------------------------------------------------------------------------

function Set-GamingTweaks([bool] $HasDefaultUser) {
    # Planification GPU acceleree par le materiel (necessite un pilote compatible).
    Set-Reg 'NOVA_SYSTEM\ControlSet001\Control\GraphicsDrivers' 'HwSchMode' 2

    # Priorite aux jeux dans le planificateur multimedia.
    $mm = 'NOVA_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-Reg $mm 'SystemResponsiveness' 10
    Set-Reg $mm 'NetworkThrottlingIndex' ([uint32]::MaxValue)
    Set-Reg "$mm\Tasks\Games" 'GPU Priority' 8
    Set-Reg "$mm\Tasks\Games" 'Priority' 6
    Set-RegString "$mm\Tasks\Games" 'Scheduling Category' 'High'
    Set-RegString "$mm\Tasks\Games" 'SFIO Priority' 'High'

    # Pas d'enregistrement video en arriere-plan (Game DVR).
    Set-Reg 'NOVA_SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0

    if (-not $HasDefaultUser) { return }
    Set-Reg 'NOVA_DEFAULT\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    # Mode Jeu actif.
    Set-Reg 'NOVA_DEFAULT\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-Reg 'NOVA_DEFAULT\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
    # Souris sans acceleration (visee plus precise).
    Set-RegString 'NOVA_DEFAULT\Control Panel\Mouse' 'MouseSpeed' '0'
    Set-RegString 'NOVA_DEFAULT\Control Panel\Mouse' 'MouseThreshold1' '0'
    Set-RegString 'NOVA_DEFAULT\Control Panel\Mouse' 'MouseThreshold2' '0'
}

function Install-FirstBootScript([string] $ImageRoot, $Config) {
    if (-not $Config.UltimatePerformance) { return }
    $dir = Join-Path $ImageRoot 'Windows\Setup\Scripts'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # Execute par Windows a la fin de l'installation, avant la premiere connexion.
    # Duplique le mode "Performances optimales" avec un GUID fixe puis l'active ;
    # repli sur "Performances elevees" si la duplication est refusee (Modern Standby).
    @'
@echo off
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 4e0a7a8c-6f1b-4d4e-9c6a-6e6f76616f73 >nul 2>&1
powercfg -setactive 4e0a7a8c-6f1b-4d4e-9c6a-6e6f76616f73 >nul 2>&1 || powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
exit /b 0
'@ | Set-Content (Join-Path $dir 'SetupComplete.cmd') -Encoding Ascii
}

function New-Autounattend([string] $Path, [string] $Arch, $Config) {
    $component = "processorArchitecture=`"$Arch`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`""
    $specialize = ''
    $oobe = ''
    $themes = ''
    if ($Config.AllowLocalAccount) {
        $specialize = @"
  <settings pass="specialize">
    <component name="Microsoft-Windows-Deployment" $component>
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
"@ + "`n"
        $oobe = @"
      <OOBE>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
"@ + "`n"
    }
    if ($Config.Theme.Enabled) {
        $themes = @"
      <Themes>
        <CustomDefaultThemeFile>%WINDIR%\NovaOS\NovaOS.theme</CustomDefaultThemeFile>
      </Themes>
"@ + "`n"
    }
    @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
$specialize  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" $component>
$oobe$themes    </component>
  </settings>
</unattend>
"@ | Set-Content $Path -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Fichiers
# ---------------------------------------------------------------------------

function Remove-ProtectedPath([string] $Path) {
    if (-not (Test-Path $Path)) { return }
    takeown /f $Path /r /d Y | Out-Null
    icacls $Path /grant '*S-1-5-32-544:F' /t /c /q | Out-Null
    Remove-Item $Path -Recurse -Force
}

function Find-Oscdimg([string] $Explicit) {
    if ($Explicit) {
        if (Test-Path $Explicit) { return $Explicit }
        throw "oscdimg.exe introuvable : $Explicit"
    }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $adk = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe"
    if (Test-Path $adk) { return $adk }
    $inPath = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    throw @"
oscdimg.exe introuvable. Installe le Windows ADK (composant "Deployment Tools") :
  https://learn.microsoft.com/windows-hardware/get-started/adk-install
ou passe son chemin avec -OscdimgPath.
"@
}

# ---------------------------------------------------------------------------
# Programme principal
# ---------------------------------------------------------------------------

$config     = Import-PowerShellDataFile $ConfigPath
$IsoPath    = (Resolve-Path $IsoPath).Path
$oscdimg    = Find-Oscdimg $OscdimgPath
$isoDir     = Join-Path $WorkDir 'iso'
$mountDir   = Join-Path $WorkDir 'mount'
$isoMounted = $false
$wimMounted = $false

try {
    Write-Step 'Preparation du dossier de travail'
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $isoDir, $mountDir, (Split-Path $OutputIso) | Out-Null

    Write-Step "Montage de $IsoPath"
    $disk = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $isoMounted = $true
    $drive = ($disk | Get-Volume).DriveLetter + ':'

    Write-Step 'Copie du contenu de l''ISO'
    Copy-Item "$drive\*" $isoDir -Recurse -Force
    Get-ChildItem $isoDir -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    $isoMounted = $false

    $sources = Join-Path $isoDir 'sources'
    $wim     = Join-Path $sources 'install.wim'
    $esd     = Join-Path $sources 'install.esd'
    $source  = if (Test-Path $wim) { $wim } elseif (Test-Path $esd) { $esd } else { throw 'Ni install.wim ni install.esd dans l''ISO.' }

    $images = Get-WindowsImage -ImagePath $source
    if (-not $ImageIndex) {
        Write-Host "`nEditions disponibles :"
        $images | ForEach-Object { Write-Host ("  [{0}] {1}" -f $_.ImageIndex, $_.ImageName) }
        $ImageIndex = [int](Read-Host 'Index de l''edition a garder')
    }
    $chosen = $images | Where-Object ImageIndex -eq $ImageIndex
    if (-not $chosen) { throw "Index $ImageIndex introuvable." }

    Write-Step "Extraction de l'edition : $($chosen.ImageName)"
    $single = Join-Path $WorkDir 'install.wim'
    Export-WindowsImage -SourceImagePath $source -SourceIndex $ImageIndex -DestinationImagePath $single -CompressionType Max | Out-Null
    Remove-Item $source -Force

    Write-Step 'Montage de install.wim'
    Mount-WindowsImage -ImagePath $single -Index 1 -Path $mountDir | Out-Null
    $wimMounted = $true
    $arch = switch ((Get-WindowsImage -ImagePath $single -Index 1).Architecture) { 12 { 'arm64' } default { 'amd64' } }

    if ($config.RemoveApps.Count -gt 0) {
        Write-Step 'Suppression des applications preinstallees'
        $provisioned = Get-AppxProvisionedPackage -Path $mountDir
        foreach ($pattern in $config.RemoveApps) {
            $provisioned | Where-Object PackageName -like "*$pattern*" | ForEach-Object {
                Write-Host "  - $($_.DisplayName)"
                Remove-AppxProvisionedPackage -Path $mountDir -PackageName $_.PackageName | Out-Null
            }
        }
    }

    if ($config.RemoveOneDrive) {
        Write-Step 'Suppression de l''installateur OneDrive'
        foreach ($p in "$mountDir\Windows\System32\OneDriveSetup.exe", "$mountDir\Windows\SysWOW64\OneDriveSetup.exe") {
            Remove-ProtectedPath $p
        }
    }

    if ($config.RemoveEdge) {
        Write-Step 'Suppression de Microsoft Edge'
        foreach ($p in "$mountDir\Program Files (x86)\Microsoft\Edge",
                       "$mountDir\Program Files (x86)\Microsoft\EdgeUpdate",
                       "$mountDir\Program Files (x86)\Microsoft\EdgeCore") {
            Remove-ProtectedPath $p
        }
    }

    if ($config.Theme.Enabled) {
        Write-Step 'Copie du theme Nova-Os'
        Install-ThemeFiles $mountDir $config.Theme
    }
    Install-FirstBootScript $mountDir $config

    Write-Step 'Modifications du registre'
    Mount-OfflineHives $mountDir
    try {
        Set-ImageTweaks $config
        if ($config.RemoveOneDrive -and (Test-Path 'Registry::HKEY_LOCAL_MACHINE\NOVA_DEFAULT')) {
            reg delete 'HKLM\NOVA_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Run' /v OneDriveSetup /f 2>$null | Out-Null
        }
    }
    finally {
        Dismount-OfflineHives
    }

    if ($config.CleanupComponentStore) {
        Write-Step 'Nettoyage du magasin de composants (long)'
        dism /English "/Image:$mountDir" /Cleanup-Image /StartComponentCleanup /ResetBase
        if ($LASTEXITCODE -ne 0) { Write-Warning "Nettoyage DISM termine avec le code $LASTEXITCODE, on continue." }
    }

    Write-Step 'Enregistrement de install.wim'
    Dismount-WindowsImage -Path $mountDir -Save | Out-Null
    $wimMounted = $false
    Export-WindowsImage -SourceImagePath $single -SourceIndex 1 -DestinationImagePath $wim -CompressionType Max | Out-Null
    Remove-Item $single -Force

    if ($config.BypassHardwareChecks) {
        Write-Step 'Contournement des verifications dans le programme d''installation (boot.wim)'
        $boot = Join-Path $sources 'boot.wim'
        Mount-WindowsImage -ImagePath $boot -Index 2 -Path $mountDir | Out-Null
        $wimMounted = $true
        Mount-OfflineHives $mountDir
        try { Set-HardwareBypass } finally { Dismount-OfflineHives }
        Dismount-WindowsImage -Path $mountDir -Save | Out-Null
        $wimMounted = $false
    }

    if ($config.AllowLocalAccount -or $config.Theme.Enabled) {
        Write-Step 'Ajout de autounattend.xml'
        New-Autounattend (Join-Path $isoDir 'autounattend.xml') $arch $config
    }

    Write-Step "Creation de $OutputIso"
    $bios = Join-Path $isoDir 'boot\etfsboot.com'
    $uefi = Join-Path $isoDir 'efi\microsoft\boot\efisys.bin'
    $bootData = if (Test-Path $bios) { "2#p0,e,b$bios#pEF,e,b$uefi" } else { "1#pEF,e,b$uefi" }
    & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" -lNOVA_OS $isoDir $OutputIso
    if ($LASTEXITCODE -ne 0) { throw "oscdimg a echoue (code $LASTEXITCODE)." }

    Write-Host "`nTermine : $OutputIso" -ForegroundColor Green
}
finally {
    if ($wimMounted) { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null }
    if ($isoMounted) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
}
