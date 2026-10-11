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

function Set-Reg([string] $Key, [string] $Name, [int] $Value) {
    reg add "HKLM\$Key" /v $Name /t REG_DWORD /d $Value /f | Out-Null
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

    if ($Config.DisableReservedStorage) {
        Write-Host '  - Stockage reserve desactive'
        Set-Reg 'NOVA_SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 0
    }
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

    if ($config.AllowLocalAccount) {
        Write-Step 'Ajout de autounattend.xml'
        (Get-Content (Join-Path $PSScriptRoot 'autounattend.xml') -Raw).Replace('{{ARCH}}', $arch) |
            Set-Content (Join-Path $isoDir 'autounattend.xml') -Encoding UTF8
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
