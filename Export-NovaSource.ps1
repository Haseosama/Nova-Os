#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Decompresse un ISO Windows 11 dans un dossier de travail modifiable, "comme du code source".

.DESCRIPTION
    Rien n'est envoye sur GitHub : tout reste sur ton PC. Le dossier produit contient :
      media\    le contenu de l'ISO, sans les images boot.wim et install.wim
      winpe\    boot.wim image 1 (Windows PE)
      setup\    boot.wim image 2 (le programme d'installation)
      windows\  install.wim, l'edition choisie (le Windows qui sera installe)
      README.md la carte du dossier
    Modifie ce que tu veux dedans, puis reconstruis l'ISO avec Build-FromSource.ps1.

.PARAMETER IsoPath
    Chemin de l'ISO Windows 11 d'origine.

.PARAMETER SourceDir
    A la place de -IsoPath : dossier ou le contenu de l'ISO a deja ete decompresse.

.PARAMETER Destination
    Dossier de travail a creer. Par defaut : D:\NovaOS\source

.PARAMETER Edition
    Edition a extraire de install.wim : son nom (ex. "Windows 11 Professionnel") ou son identifiant
    (Professional, Core...). Par defaut : Professional, quelle que soit la langue de l'ISO.

.EXAMPLE
    .\Export-NovaSource.ps1 -SourceDir "C:\Users\moi\Desktop\Nova\Win11" -Destination D:\NovaOS\source
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'Iso')]    [string] $IsoPath,
    [Parameter(Mandatory, ParameterSetName = 'Folder')] [string] $SourceDir,
    [string] $Destination = 'D:\NovaOS\source',
    [string] $Edition = 'Professional'
)

$ErrorActionPreference = 'Stop'

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

if (Test-Path $Destination) {
    throw "$Destination existe deja. Supprime-le ou choisis un autre -Destination : le script ne remplace jamais un dossier de travail."
}

$isoMounted = $false
try {
    if ($IsoPath) {
        $IsoPath = (Resolve-Path $IsoPath).Path
        Write-Step "Montage de $IsoPath"
        $disk = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $isoMounted = $true
        $SourceDir = ($disk | Get-Volume).DriveLetter + ':\'
    }
    $SourceDir = (Resolve-Path $SourceDir).Path
    $sources = Join-Path $SourceDir 'sources'
    $installImage = @('install.wim', 'install.esd') | ForEach-Object { Join-Path $sources $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $installImage) { throw "Pas de sources\install.wim ni install.esd dans $SourceDir." }

    $media   = Join-Path $Destination 'media'
    $winpe   = Join-Path $Destination 'winpe'
    $setup   = Join-Path $Destination 'setup'
    $windows = Join-Path $Destination 'windows'
    foreach ($dir in $media, $winpe, $setup, $windows) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    Write-Step 'Copie du contenu de l''ISO (media)'
    robocopy $SourceDir $media /E /XF install.wim install.esd boot.wim /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy a echoue (code $LASTEXITCODE)." }
    Get-ChildItem $media -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }

    $bootWim = Join-Path $sources 'boot.wim'
    Write-Step 'Extraction de boot.wim image 1 (winpe)'
    Expand-WindowsImage -ImagePath $bootWim -Index 1 -ApplyPath $winpe | Out-Null
    Write-Step 'Extraction de boot.wim image 2 (setup)'
    Expand-WindowsImage -ImagePath $bootWim -Index 2 -ApplyPath $setup | Out-Null

    $images = Get-WindowsImage -ImagePath $installImage
    $image = $images | Where-Object {
        $_.ImageName -eq $Edition -or (Get-WindowsImage -ImagePath $installImage -Index $_.ImageIndex).EditionId -eq $Edition
    } | Select-Object -First 1
    if (-not $image) {
        Write-Host 'Editions disponibles :'
        $images | ForEach-Object { Write-Host "  $($_.ImageIndex) : $($_.ImageName)" }
        throw "Edition '$Edition' introuvable. Relance avec -Edition et un des noms ci-dessus."
    }
    Write-Step "Extraction de $($image.ImageName) (windows) : c'est la plus longue etape"
    Expand-WindowsImage -ImagePath $installImage -Index $image.ImageIndex -ApplyPath $windows | Out-Null

    $info = [ordered]@{
        Source      = if ($IsoPath) { $IsoPath } else { $SourceDir }
        Edition     = $image.ImageName
        EditionId   = (Get-WindowsImage -ImagePath $installImage -Index $image.ImageIndex).EditionId
        Description = $image.ImageDescription
        Exported    = (Get-Date).ToString('s')
    }
    $info | ConvertTo-Json | Set-Content (Join-Path $Destination 'source.json') -Encoding UTF8

    @"
# Windows 11 decompresse ($($image.ImageName))

Source : $($info.Source)

| Dossier | Ce que c'est | Quand c'est utilise |
|---|---|---|
| ``media\`` | Contenu de l'ISO : fichiers de demarrage (``boot\``, ``efi\``), ``setup.exe``, ``sources\`` sans les images | Au demarrage sur la cle USB ou le DVD |
| ``winpe\`` | boot.wim image 1 : Windows PE de base | Outils de reparation |
| ``setup\`` | boot.wim image 2 : Windows PE + programme d'installation | Tout l'ecran d'installation |
| ``windows\`` | install.wim : le Windows qui sera installe (= le futur ``C:\``) | Apres l'installation |

## Reperes utiles

- Programme d'installation : ``setup\sources\`` (fonds ``background*.bmp``), ``setup\Windows\System32\winpe.jpg``.
- Fonds d'ecran de Windows : ``windows\Windows\Web\Wallpaper\``, ecran de verrouillage : ``windows\Windows\Web\Screen\``.
- Themes : ``windows\Windows\Resources\Themes\``.
- Images de compte : ``windows\ProgramData\Microsoft\User Account Pictures\``.
- Profil par defaut des nouveaux comptes : ``windows\Users\Default\`` (son registre : ``NTUSER.DAT``).
- Registre machine : ``windows\Windows\System32\config\`` (SOFTWARE, SYSTEM...).
- Applis preinstallees : ``windows\Program Files\WindowsApps\``.

## Modifier

Les fichiers systeme appartiennent a TrustedInstaller. Avant d'en remplacer un :
``takeown /f <fichier> /a`` puis ``icacls <fichier> /grant *S-1-5-32-544:F``.
Les fichiers signes par Microsoft (``.dll``, ``.exe``, ``.sys``) ne doivent pas etre modifies :
Windows ou le Secure Boot peuvent refuser de les charger.

## Reconstruire l'ISO

``````powershell
.\Build-FromSource.ps1 -Source "$Destination" -OutputIso D:\NovaOS\Nova-Os-source.iso
``````

Ajoute ``-NovaOS`` pour appliquer en plus les reglages Nova-Os de ``config.psd1``.
"@ | Set-Content (Join-Path $Destination 'README.md') -Encoding UTF8

    Write-Host "`nTermine : $Destination" -ForegroundColor Green
    Write-Host 'La carte du dossier est dans README.md.'
}
finally {
    if ($isoMounted) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
}
