#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reconstruit un ISO Windows 11 a partir du dossier cree par Export-NovaSource.ps1.

.DESCRIPTION
    Recompresse setup\ et winpe\ en boot.wim, windows\ en install.wim, les remet dans media\
    (sur une copie) et produit l'ISO. Le dossier source n'est pas modifie.

.PARAMETER Source
    Dossier cree par Export-NovaSource.ps1. Par defaut : D:\NovaOS\source

.PARAMETER OutputIso
    ISO a produire. Par defaut : D:\NovaOS\Nova-Os-source.iso

.PARAMETER WorkDir
    Dossier de travail temporaire. Par defaut : D:\NovaOS\work-source

.PARAMETER NovaOS
    Applique en plus les reglages Nova-Os (config.psd1) avec Build-NovaOS.ps1.

.PARAMETER OriginalIso
    ISO Microsoft d'origine, pour recopier l'identite de l'edition (Pro...) dans install.wim si
    DISM ne l'a pas fait et que le dossier n'a pas de image.xml.

.PARAMETER OscdimgPath
    Chemin de oscdimg.exe si le Windows ADK n'est pas installe a l'emplacement standard.
#>
[CmdletBinding()]
param(
    [string] $Source = 'D:\NovaOS\source',
    [string] $OutputIso = 'D:\NovaOS\Nova-Os-source.iso',
    [string] $WorkDir = 'D:\NovaOS\work-source',
    [switch] $NovaOS,
    [string] $OriginalIso,
    [string] $OscdimgPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WimImageInfo.ps1')

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Find-Oscdimg([string] $Explicit) {
    if ($Explicit) {
        if (Test-Path $Explicit) { return $Explicit }
        throw "oscdimg.exe introuvable : $Explicit"
    }
    $hostArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $adk = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArch\Oscdimg\oscdimg.exe"
    if (Test-Path $adk) { return $adk }
    $inPath = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    throw 'oscdimg.exe introuvable. Installe le Windows ADK (Deployment Tools) ou passe -OscdimgPath.'
}

function Invoke-Dism([string[]] $Arguments) {
    & dism.exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "DISM a echoue (code $LASTEXITCODE) : dism $($Arguments -join ' ')" }
}

$Source = (Resolve-Path $Source).Path
foreach ($dir in 'media', 'winpe', 'setup', 'windows') {
    if (-not (Test-Path (Join-Path $Source $dir))) { throw "$Source\$dir manquant : ce n'est pas un dossier cree par Export-NovaSource.ps1." }
}
$info = Get-Content (Join-Path $Source 'source.json') -Raw | ConvertFrom-Json
$arch = if (Test-Path (Join-Path $Source 'media\efi\boot\bootaa64.efi')) { 'arm64' } else { 'amd64' }

$isoDir = Join-Path $WorkDir 'iso'
$sources = Join-Path $isoDir 'sources'
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $isoDir | Out-Null
$outDir = Split-Path $OutputIso
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

Write-Step 'Copie de media'
robocopy (Join-Path $Source 'media') $isoDir /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy a echoue (code $LASTEXITCODE)." }

Write-Step 'Compression de boot.wim (winpe + setup)'
$bootWim = Join-Path $sources 'boot.wim'
Invoke-Dism @('/Capture-Image', "/ImageFile:$bootWim", "/CaptureDir:$(Join-Path $Source 'winpe')",
              "/Name:Microsoft Windows PE ($arch)", '/Compress:max', '/Bootable')
Invoke-Dism @('/Append-Image', "/ImageFile:$bootWim", "/CaptureDir:$(Join-Path $Source 'setup')",
              "/Name:Microsoft Windows Setup ($arch)", '/Bootable')

Write-Step "Compression de install.wim ($($info.Edition)) : c'est la plus longue etape"
$capture = @('/Capture-Image', "/ImageFile:$(Join-Path $sources 'install.wim')", "/CaptureDir:$(Join-Path $Source 'windows')",
             "/Name:$($info.Edition)", "/Description:$($info.Description)", '/Compress:max')
Invoke-Dism $capture

# DISM lit l'edition (Professional...) dans le registre de l'image : le programme d'installation
# en a besoin pour associer la cle produit a l'image.
$captured = Get-WindowsImage -ImagePath (Join-Path $sources 'install.wim') -Index 1
Write-Host "  Edition : $($captured.EditionId), version $($captured.Version)"
if ($info.EditionId -and $captured.EditionId -ne $info.EditionId) {
    # DISM n'a pas pu lire le registre de l'image : on recopie la fiche de l'image d'origine.
    $originalXml = $null
    $saved = Join-Path $Source 'image.xml'
    if (Test-Path $saved) { $originalXml = Get-Content $saved -Raw -Encoding Unicode }
    elseif ($OriginalIso) {
        $iso = (Resolve-Path $OriginalIso).Path
        $drive = (Mount-DiskImage -ImagePath $iso -PassThru | Get-Volume).DriveLetter + ':'
        try {
            $wim = @("$drive\sources\install.wim", "$drive\sources\install.esd") | Where-Object { Test-Path $_ } | Select-Object -First 1
            $match = Get-WindowsImage -ImagePath $wim | Where-Object ImageName -eq $info.Edition | Select-Object -First 1
            if ($match) { $originalXml = Get-WimImageXml $wim $match.ImageIndex }
        }
        finally { Dismount-DiskImage -ImagePath $iso | Out-Null }
    }
    if ($originalXml) {
        Write-Step 'Restauration de l''identite de l''edition dans install.wim'
        Restore-WimImageIdentity (Join-Path $sources 'install.wim') 1 $originalXml
        $captured = Get-WindowsImage -ImagePath (Join-Path $sources 'install.wim') -Index 1
        Write-Host "  Edition : $($captured.EditionId), version $($captured.Version)"
    }
    if ($captured.EditionId -ne $info.EditionId) {
        throw "install.wim n'a pas d'edition ($($captured.EditionId)) : l'installation ne proposerait aucune image. Relance avec -OriginalIso <ISO Microsoft d'origine>."
    }
}

if ($NovaOS) {
    Write-Step 'Application des reglages Nova-Os'
    & (Join-Path $PSScriptRoot 'Build-NovaOS.ps1') -SourceDir $isoDir -OutputIso $OutputIso -WorkDir (Join-Path $WorkDir 'nova')
}
else {
    Write-Step "Creation de $OutputIso"
    $oscdimg = Find-Oscdimg $OscdimgPath
    $bios = Join-Path $isoDir 'boot\etfsboot.com'
    $uefi = Join-Path $isoDir 'efi\microsoft\boot\efisys.bin'
    $bootData = if (Test-Path $bios) { "2#p0,e,b$bios#pEF,e,b$uefi" } else { "1#pEF,e,b$uefi" }
    # oscdimg ecrit sa progression sur stderr : sans ce Continue, PowerShell l'arrete des la
    # premiere ligne quand la sortie est redirigee vers un journal.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" -lNOVA_OS $isoDir $OutputIso 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = $previousPreference
    if ($LASTEXITCODE -ne 0) { throw "oscdimg a echoue (code $LASTEXITCODE)." }
}

Write-Host "`nTermine : $OutputIso" -ForegroundColor Green
Write-Host "Le dossier de travail $WorkDir peut etre supprime."
