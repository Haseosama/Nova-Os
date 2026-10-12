#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Construit l'ISO Nova-Os a partir d'un ISO officiel de Windows 11.

.DESCRIPTION
    L'image Windows (install.wim) n'est pas modifiee et aucune application tierce n'est installee.
    Le script ajoute a l'ISO :
      - sources\$OEM$\$$\NovaOS : fond d'ecran, theme, logo et scripts, que l'installation de
        Windows copie elle-meme dans C:\Windows\NovaOS ;
      - autounattend.xml : il lance ces scripts pendant l'installation (passe specialize), avant
        la creation du compte, puis applique le theme Nova-Os par defaut ;
      - l'habillage Nova-Os du programme d'installation (boot.wim).
    Tout est applique par Windows lui-meme, et journalise dans C:\Windows\NovaOS\Specialize.log.

.PARAMETER IsoPath
    Chemin de l'ISO Windows 11 d'origine.

.PARAMETER SourceDir
    A la place de -IsoPath : dossier ou le contenu de l'ISO a deja ete decompresse.
    Il est copie dans le dossier de travail et n'est jamais modifie.

.PARAMETER OutputIso
    Chemin de l'ISO a produire. Par defaut : .\out\Nova-Os.iso

.PARAMETER ConfigPath
    Fichier de configuration. Par defaut : config.psd1 a cote du script.

.PARAMETER WorkDir
    Dossier de travail temporaire (prevoir la taille de l'ISO). Par defaut : .\work

.PARAMETER OscdimgPath
    Chemin de oscdimg.exe si le Windows ADK n'est pas installe a l'emplacement standard.

.EXAMPLE
    .\Build-NovaOS.ps1 -IsoPath D:\ISO\Win11_24H2_French_x64.iso

.EXAMPLE
    .\Build-NovaOS.ps1 -SourceDir D:\ISO\Win11_decompresse
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ParameterSetName = 'Iso')]    [string] $IsoPath,
    [Parameter(Mandatory, ParameterSetName = 'Folder')] [string] $SourceDir,
    [string] $OutputIso = (Join-Path $PSScriptRoot 'out\Nova-Os.iso'),
    [string] $ConfigPath = (Join-Path $PSScriptRoot 'config.psd1'),
    [string] $WorkDir = (Join-Path $PSScriptRoot 'work'),
    [string] $OscdimgPath
)

$ErrorActionPreference = 'Stop'

# Dossier Nova-Os sur le PC installe, et son equivalent dans l'ISO ($OEM$\$$ = %WINDIR%).
$NovaDir = 'C:\Windows\NovaOS'
$OemNovaDir = 'sources\$OEM$\$$\NovaOS'

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Registre : les reglages sont ecrits dans Registry.cmd, execute pendant l'installation.
#   HKLM\...        : machine
#   HKU\NovaDefault : profil par defaut (copie pour chaque nouveau compte)
# ---------------------------------------------------------------------------

$script:RegLines = New-Object System.Collections.Generic.List[string]
$DefaultUser = 'HKU\NovaDefault'

function Add-RegLine([string[]] $Arguments) {
    $quoted = $Arguments | ForEach-Object { if ($_ -match '[\s&|<>^]' -or $_ -eq '') { "`"$_`"" } else { $_ } }
    $line = "reg $($quoted -join ' ')"
    # En cas d'echec, la commande est notee dans le journal.
    $script:RegLines.Add("$line >nul 2>&1 || echo ECHEC : $($line -replace '[&|<>^%"]', '')")
}

function Set-Reg([string] $Key, [string] $Name, [uint32] $Value) {
    Add-RegLine @('add', $Key, '/v', $Name, '/t', 'REG_DWORD', '/d', ('0x{0:X}' -f $Value), '/f')
}

function Set-RegString([string] $Key, [string] $Name, [string] $Value) {
    Add-RegLine @('add', $Key, '/v', $Name, '/t', 'REG_SZ', '/d', $Value, '/f')
}

function Remove-RegValue([string] $Key, [string] $Name) {
    $script:RegLines.Add("reg delete `"$Key`" /v `"$Name`" /f >nul 2>&1")
}

# Desactive une tache planifiee (sans erreur si elle n'existe pas dans cette version de Windows).
function Disable-Task([string] $Task) {
    $script:RegLines.Add("schtasks /Change /TN `"$Task`" /Disable >nul 2>&1")
}

function Set-SystemTweaks($Config) {
    if ($Config.BypassHardwareChecks) {
        Write-Host '  - Contournement TPM / Secure Boot / RAM / CPU (mises a jour futures)'
        Set-Reg 'HKLM\SYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 1
        Set-Reg "$DefaultUser\Control Panel\UnsupportedHardwareNotificationCache" 'SV1' 0
        Set-Reg "$DefaultUser\Control Panel\UnsupportedHardwareNotificationCache" 'SV2' 0
    }

    if ($Config.DisableTelemetry) {
        Write-Host '  - Telemetrie desactivee'
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack' 'Start' 4
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Services\dmwappushservice' 'Start' 4
        Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" 'Enabled' 0
        Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Privacy" 'TailoredExperiencesWithDiagnosticDataEnabled' 0

        # Pas de rapport d'erreurs, de programme d'amelioration, ni de demandes d'avis.
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDiagnosticLogCollection' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DisableOneSettingsDownloads' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0
        Set-Reg "$DefaultUser\Software\Microsoft\Siuf\Rules" 'NumberOfSIUFInPeriod' 0
        Set-Reg "$DefaultUser\Software\Microsoft\Input\TIPC" 'Enabled' 0
        Set-Reg "$DefaultUser\Software\Microsoft\InputPersonalization" 'RestrictImplicitTextCollection' 1
        Set-Reg "$DefaultUser\Software\Microsoft\InputPersonalization" 'RestrictImplicitInkCollection' 1
        Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'Start_TrackProgs' 0

        # Taches planifiees qui envoient des donnees de diagnostic.
        foreach ($task in '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
                          '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
                          '\Microsoft\Windows\Application Experience\StartupAppTask',
                          '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
                          '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
                          '\Microsoft\Windows\Autochk\Proxy',
                          '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
                          '\Microsoft\Windows\Feedback\Siuf\DmClient',
                          '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
                          '\Microsoft\Windows\Windows Error Reporting\QueueReporting') {
            Disable-Task $task
        }
    }

    if ($Config.DisableConsumerFeatures) {
        Write-Host '  - Applis suggerees desactivees'
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
        # Widgets, recherche Bing dans Demarrer et recommandations.
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        Set-Reg "$DefaultUser\Software\Policies\Microsoft\Windows\Explorer" 'DisableSearchBoxSuggestions' 1
        Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'Start_IrisRecommendations' 0
        Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'TaskbarDa' 0
        $cdm = "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        foreach ($name in 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'OemPreInstalledAppsEnabled',
                          'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled') {
            Set-Reg $cdm $name 0
        }
    }

    if ($Config.DisableCopilot) {
        Write-Host '  - Copilot desactive'
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-Reg "$DefaultUser\Software\Policies\Microsoft\Windows\WindowsCopilot" 'TurnOffWindowsCopilot' 1
        # Recall (captures d'ecran analysees par l'IA).
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    }

    if ($Config.RemoveOneDrive) {
        Write-Host '  - OneDrive non installe a la premiere connexion'
        # C'est cette entree du profil par defaut qui installe OneDrive pour chaque nouveau compte.
        Remove-RegValue "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run" 'OneDriveSetup'
    }

    if ($Config.DisableVBS) {
        Write-Host '  - Integrite de la memoire (VBS) desactivee'
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
    }

    if ($Config.DisableReservedStorage) {
        Write-Host '  - Stockage reserve desactive'
        Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 0
    }
}

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

function ConvertFrom-HexColor([string] $Hex) {
    $h = $Hex.TrimStart('#')
    if ($h -notmatch '^[0-9A-Fa-f]{6}$') { throw "Couleur invalide : $Hex (format attendu : #RRGGBB)" }
    [pscustomobject]@{
        R = [Convert]::ToByte($h.Substring(0, 2), 16)
        G = [Convert]::ToByte($h.Substring(2, 2), 16)
        B = [Convert]::ToByte($h.Substring(4, 2), 16)
    }
}

function Resolve-Asset([string] $Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    Join-Path $PSScriptRoot $Path
}

# Enregistre $Image a la taille $Width x $Height (remplissage sans deformation, recadre au centre).
# Les formats sans transparence (bmp, jpg) recoivent un fond sombre.
function Save-Image([string] $Image, [string] $Destination, [int] $Width, [int] $Height) {
    Add-Type -AssemblyName System.Drawing
    $ext = [IO.Path]::GetExtension($Destination).ToLower()
    $src = [System.Drawing.Image]::FromFile($Image)
    $bmp = New-Object System.Drawing.Bitmap $Width, $Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    if ($ext -ne '.png') { $g.Clear([System.Drawing.Color]::FromArgb(255, 10, 8, 30)) }
    $scale = [Math]::Max($Width / $src.Width, $Height / $src.Height)
    $dw = $src.Width * $scale; $dh = $src.Height * $scale
    $g.DrawImage($src, ($Width - $dw) / 2, ($Height - $dh) / 2, $dw, $dh)
    $g.Dispose(); $src.Dispose()

    if (Test-Path $Destination) {
        # Fichiers systeme (boot.wim) : proprietaire TrustedInstaller.
        takeown /f $Destination /a | Out-Null
        icacls $Destination /grant '*S-1-5-32-544:F' /q | Out-Null
        (Get-Item $Destination).IsReadOnly = $false
    }
    $format = switch ($ext) {
        '.png' { [System.Drawing.Imaging.ImageFormat]::Png }
        '.bmp' { [System.Drawing.Imaging.ImageFormat]::Bmp }
        default { [System.Drawing.Imaging.ImageFormat]::Jpeg }
    }
    $bmp.Save($Destination, $format)
    $bmp.Dispose()
}

# Remplace les fonds du programme d'installation (background*.bmp / .png) par l'image Nova-Os,
# a la meme taille et dans le meme format que les originaux.
function Update-SetupBackgrounds([string] $Dir, [string] $Image) {
    Add-Type -AssemblyName System.Drawing
    $files = Get-ChildItem $Dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'background*' -and $_.Extension -in '.bmp', '.png' }
    foreach ($file in $files) {
        $orig = [System.Drawing.Image]::FromFile($file.FullName)
        $w = $orig.Width; $h = $orig.Height
        $orig.Dispose()
        Save-Image $Image $file.FullName $w $h
        Write-Host "  - $($file.Name) ($w x $h)"
    }
}

# Habille l'environnement d'installation monte (boot.wim, image 2).
function Update-SetupImage([string] $Mount, [string] $Image, [bool] $LegacySetup) {
    # Fonds de l'ancien programme d'installation.
    Update-SetupBackgrounds (Join-Path $Mount 'sources') $Image
    # Ecran de chargement affiche avant le programme d'installation.
    Save-Image $Image (Join-Path $Mount 'Windows\System32\winpe.jpg') 1920 1080
    Write-Host '  - winpe.jpg (1920 x 1080)'
    if ($LegacySetup) {
        # Le nouveau programme d'installation (24H2+) ignore les fonds personnalises :
        # on lance directement l'ancien, qui affiche le fond Nova-Os et lit autounattend.xml.
        "[LaunchApps]`r`nX:\sources\setup.exe" |
            Set-Content (Join-Path $Mount 'Windows\System32\winpeshl.ini') -Encoding Ascii
        Write-Host '  - winpeshl.ini (programme d''installation classique)'
    }
}

# ---------------------------------------------------------------------------
# Theme futuriste
# ---------------------------------------------------------------------------

function New-ThemeFile([string] $Path, $Theme) {
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
"@ | Set-Content $Path -Encoding Unicode
}

function Set-ThemeTweaks($Theme) {
    $wallpaper = "$NovaDir\wallpaper.jpg"

    # Ecran de verrouillage (fonctionne aussi sur Famille et Pro via PersonalizationCSP).
    $csp = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
    Set-RegString $csp 'LockScreenImagePath' $wallpaper
    Set-RegString $csp 'LockScreenImageUrl' $wallpaper
    Set-Reg $csp 'LockScreenImageStatus' 1

    # Windows a la une (Spotlight) remplace sinon le fond d'ecran et l'ecran de verrouillage.
    foreach ($root in 'HKLM\SOFTWARE', "$DefaultUser\Software") {
        Set-Reg "$root\Policies\Microsoft\Windows\CloudContent" 'DisableWindowsSpotlightFeatures' 1
        Set-Reg "$root\Policies\Microsoft\Windows\CloudContent" 'DisableSpotlightCollectionOnDesktop' 1
    }
    $cdm = "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Set-Reg $cdm 'RotatingLockScreenEnabled' 0
    Set-Reg $cdm 'RotatingLockScreenOverlayEnabled' 0

    $c = ConvertFrom-HexColor $Theme.AccentColor
    $abgr = [uint32](([uint32]255 -shl 24) -bor ([uint32]$c.B -shl 16) -bor ([uint32]$c.G -shl 8) -bor $c.R)

    $personalize = "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-Reg $personalize 'AppsUseLightTheme' 0
    Set-Reg $personalize 'SystemUsesLightTheme' 0
    Set-Reg $personalize 'EnableTransparency' 1
    Set-Reg $personalize 'ColorPrevalence' 1            # accent sur la barre des taches et Demarrer
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\DWM" 'AccentColor' $abgr
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\DWM" 'ColorPrevalence' 1   # accent sur les barres de titre
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" 'AccentColorMenu' $abgr
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" 'StartColorMenu' $abgr
    Set-RegString "$DefaultUser\Control Panel\Desktop" 'WallPaper' $wallpaper
    Set-RegString "$DefaultUser\Control Panel\Desktop" 'WallpaperStyle' '10'

    if ($Theme.GlassEffects) {
        # Barre des taches plus transparente (effet verre natif de Windows).
        Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'UseOLEDTaskbarTransparency' 1
        Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'UseOLEDTaskbarTransparency' 1
    }
}

# Nom et logo Nova-Os dans Parametres > Systeme > Informations (OEMInformation, prevu par Windows).
function Set-BrandingTweaks($Branding) {
    $oem = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
    Set-RegString $oem 'Manufacturer' $Branding.Manufacturer
    Set-RegString $oem 'Model' $Branding.Model
    if ($Branding.SupportURL) { Set-RegString $oem 'SupportURL' $Branding.SupportURL }
    if ($Branding.Logo) { Set-RegString $oem 'Logo' "$NovaDir\oemlogo.bmp" }
    Set-RegString 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'RegisteredOrganization' $Branding.Manufacturer
}

# ---------------------------------------------------------------------------
# Optimisations jeux
# ---------------------------------------------------------------------------

function Set-GamingTweaks {
    # Planification GPU acceleree par le materiel (necessite un pilote compatible).
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2

    # Priorite aux jeux dans le planificateur multimedia.
    $mm = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-Reg $mm 'SystemResponsiveness' 10
    Set-Reg $mm 'NetworkThrottlingIndex' ([uint32]::MaxValue)
    Set-Reg "$mm\Tasks\Games" 'GPU Priority' 8
    Set-Reg "$mm\Tasks\Games" 'Priority' 6
    Set-RegString "$mm\Tasks\Games" 'Scheduling Category' 'High'
    Set-RegString "$mm\Tasks\Games" 'SFIO Priority' 'High'

    # Pas d'enregistrement video en arriere-plan (Game DVR).
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    Set-Reg "$DefaultUser\System\GameConfigStore" 'GameDVR_Enabled' 0
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\GameDVR" 'AppCaptureEnabled' 0
    # Mode Jeu actif.
    Set-Reg "$DefaultUser\Software\Microsoft\GameBar" 'AutoGameModeEnabled' 1
    Set-Reg "$DefaultUser\Software\Microsoft\GameBar" 'AllowAutoGameMode' 1
    # Souris sans acceleration (visee plus precise).
    Set-RegString "$DefaultUser\Control Panel\Mouse" 'MouseSpeed' '0'
    Set-RegString "$DefaultUser\Control Panel\Mouse" 'MouseThreshold1' '0'
    Set-RegString "$DefaultUser\Control Panel\Mouse" 'MouseThreshold2' '0'
}

# ---------------------------------------------------------------------------
# Charge utile copiee dans C:\Windows\NovaOS par l'installation
# ---------------------------------------------------------------------------

function New-Payload([string] $Dir, $Config) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null

    if ($Config.Theme.Enabled) {
        Copy-Item (Resolve-Asset $Config.Theme.Wallpaper) (Join-Path $Dir 'wallpaper.jpg') -Force
        New-ThemeFile (Join-Path $Dir 'NovaOS.theme') $Config.Theme
    }

    $logo = if ($Config.Branding.Enabled -and $Config.Branding.Logo) { Resolve-Asset $Config.Branding.Logo }
    if ($logo) {
        Save-Image $logo (Join-Path $Dir 'oemlogo.bmp') 120 120
        if ($Config.Branding.AccountPictures) {
            # Memes noms et tailles que C:\ProgramData\Microsoft\User Account Pictures.
            $pictures = Join-Path $Dir 'AccountPictures'
            New-Item -ItemType Directory -Force -Path $pictures | Out-Null
            $sizes = @{ 'user.png' = 448; 'user.bmp' = 448; 'guest.png' = 448; 'guest.bmp' = 448
                        'user-32.png' = 32; 'user-40.png' = 40; 'user-48.png' = 48; 'user-192.png' = 192 }
            foreach ($name in $sizes.Keys) { Save-Image $logo (Join-Path $pictures $name) $sizes[$name] $sizes[$name] }
        }
    }

    # Registry.cmd : tous les reglages du registre, profil par defaut charge dans HKU\NovaDefault.
    $lines = @('@echo off',
               "reg load $DefaultUser C:\Users\Default\NTUSER.DAT >nul 2>&1 || echo ECHEC : chargement du profil par defaut") +
             $script:RegLines +
             @("reg unload $DefaultUser >nul 2>&1", 'exit /b 0')
    $lines | Set-Content (Join-Path $Dir 'Registry.cmd') -Encoding Ascii

    # Specialize.ps1 : lance par autounattend.xml pendant l'installation, avant la creation du compte.
    $patterns = ($Config.RemoveApps | ForEach-Object { "'$_'" }) -join ', '
    $power = if ($Config.UltimatePerformance) { '$true' } else { '$false' }
    @"
# Nova-Os : applique pendant l'installation de Windows (passe specialize). Journal : Specialize.log
`$ErrorActionPreference = 'Continue'
Start-Transcript -Path '$NovaDir\Specialize.log' -Append | Out-Null

Write-Output '== Suppression des applications preinstallees'
`$patterns = @($patterns)
`$provisioned = Get-AppxProvisionedPackage -Online
foreach (`$pattern in `$patterns) {
    `$provisioned | Where-Object PackageName -like "*`$pattern*" | ForEach-Object {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName `$_.PackageName -ErrorAction Stop | Out-Null
            Write-Output "  supprime : `$(`$_.DisplayName)"
        }
        catch { Write-Output "  ECHEC `$(`$_.DisplayName) : `$(`$_.Exception.Message)" }
    }
}

Write-Output '== Registre'
& cmd.exe /c '$NovaDir\Registry.cmd' 2>&1 | ForEach-Object { Write-Output "  `$_" }
Write-Output '  termine'

`$pictures = '$NovaDir\AccountPictures'
if (Test-Path `$pictures) {
    Write-Output '== Images de compte Nova-Os'
    `$target = "`$env:ProgramData\Microsoft\User Account Pictures"
    foreach (`$file in Get-ChildItem `$pictures -File) {
        `$dest = Join-Path `$target `$file.Name
        if (Test-Path `$dest) {
            takeown /f `$dest /a | Out-Null
            icacls `$dest /grant '*S-1-5-32-544:F' /q | Out-Null
        }
        Copy-Item `$file.FullName `$dest -Force
        Write-Output "  `$(`$file.Name)"
    }
}

if ($power) {
    Write-Output '== Mode Performances optimales'
    # GUID fixe pour pouvoir l'activer ; repli sur Performances elevees (PC en Modern Standby).
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 4e0a7a8c-6f1b-4d4e-9c6a-6e6f76616f73 | Out-Null
    powercfg -setactive 4e0a7a8c-6f1b-4d4e-9c6a-6e6f76616f73
    if (`$LASTEXITCODE -ne 0) { powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c }
    Write-Output "  code `$LASTEXITCODE"
}

Write-Output '== Fin'
Stop-Transcript | Out-Null
"@ | Set-Content (Join-Path $Dir 'Specialize.ps1') -Encoding UTF8
}

# ---------------------------------------------------------------------------
# autounattend.xml
# ---------------------------------------------------------------------------

function New-RunSynchronous([string[]] $Commands) {
    $i = 0
    $items = foreach ($cmd in $Commands) {
        $i++
        $escaped = [Security.SecurityElement]::Escape($cmd)
        @"
        <RunSynchronousCommand wcm:action="add">
          <Order>$i</Order>
          <Path>$escaped</Path>
        </RunSynchronousCommand>
"@
    }
    "      <RunSynchronous>`n$($items -join "`n")`n      </RunSynchronous>`n"
}

function New-Autounattend([string] $Path, [string] $Arch, $Config) {
    $component = "processorArchitecture=`"$Arch`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`""

    # windowsPE : contournement materiel du programme d'installation, cle generique.
    $peBody = ''
    if ($Config.BypassHardwareChecks) {
        $peBody += New-RunSynchronous @(
            foreach ($name in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassCPUCheck', 'BypassStorageCheck') {
                "reg add HKLM\SYSTEM\Setup\LabConfig /v $name /t REG_DWORD /d 1 /f"
            })
    }
    if ($Config.InstallKey) {
        # Cle generique : passe l'ecran "cle de produit" et choisit l'edition, sans activer Windows.
        $peBody += @"
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey>
          <Key>$($Config.InstallKey)</Key>
          <WillShowUI>OnError</WillShowUI>
        </ProductKey>
      </UserData>
"@ + "`n"
    }

    # specialize : nom du PC, compte local possible, puis tous les reglages Nova-Os.
    $spCommands = @()
    if ($Config.AllowLocalAccount) {
        $spCommands += 'reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f'
    }
    $spCommands += "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $NovaDir\Specialize.ps1"
    $computerName = ''
    if ($Config.Branding.Enabled -and $Config.Branding.ComputerName) {
        $computerName = @"
    <component name="Microsoft-Windows-Shell-Setup" $component>
      <ComputerName>$([Security.SecurityElement]::Escape($Config.Branding.ComputerName))</ComputerName>
    </component>
"@ + "`n"
    }

    $oobe = ''
    if ($Config.AllowLocalAccount) {
        $oobe = @"
      <OOBE>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
"@ + "`n"
    }
    $themes = ''
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
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" $component>
$peBody    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Deployment" $component>
$(New-RunSynchronous $spCommands)    </component>
$computerName  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" $component>
$oobe$themes    </component>
  </settings>
</unattend>
"@ | Set-Content $Path -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

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
if ($IsoPath) { $IsoPath = (Resolve-Path $IsoPath).Path }
$oscdimg    = Find-Oscdimg $OscdimgPath
$isoDir     = Join-Path $WorkDir 'iso'
$mountDir   = Join-Path $WorkDir 'mount'
$isoMounted = $false
$wimMounted = $false

try {
    Write-Step 'Preparation du dossier de travail'
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
    # Ne cree que les dossiers absents : New-Item sur la racine d'un disque (D:\) echoue sous PowerShell 5.1.
    foreach ($dir in $isoDir, $mountDir, (Split-Path $OutputIso)) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    }

    if ($SourceDir) {
        $SourceDir = (Resolve-Path $SourceDir).Path
        if (-not (Test-Path (Join-Path $SourceDir 'sources'))) { throw "Pas de dossier 'sources' dans $SourceDir : ce n'est pas le contenu d'un ISO Windows." }
        Write-Step "Copie du dossier decompresse $SourceDir"
        Copy-Item "$SourceDir\*" $isoDir -Recurse -Force
    }
    else {
        Write-Step "Montage de $IsoPath"
        $disk = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $isoMounted = $true
        $drive = ($disk | Get-Volume).DriveLetter + ':'

        Write-Step 'Copie du contenu de l''ISO'
        Copy-Item "$drive\*" $isoDir -Recurse -Force
        Dismount-DiskImage -ImagePath $IsoPath | Out-Null
        $isoMounted = $false
    }
    Get-ChildItem $isoDir -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }

    $sources = Join-Path $isoDir 'sources'
    $arch = if (Test-Path (Join-Path $isoDir 'efi\boot\bootaa64.efi')) { 'arm64' } else { 'amd64' }

    Write-Step 'Preparation des reglages'
    Set-SystemTweaks $config
    if ($config.Theme.Enabled) {
        Write-Host '  - Theme futuriste (mode sombre, accent neon, fond d''ecran, effet verre)'
        Set-ThemeTweaks $config.Theme
    }
    if ($config.Branding.Enabled) {
        Write-Host '  - Identite Nova-Os (logo, fabricant, nom du PC, images de compte)'
        Set-BrandingTweaks $config.Branding
    }
    if ($config.GamingTweaks) {
        Write-Host '  - Optimisations jeux'
        Set-GamingTweaks
    }

    Write-Step "Ajout de la charge utile Nova-Os ($OemNovaDir)"
    New-Payload (Join-Path $isoDir $OemNovaDir) $config

    $setupBackground = if ($config.Theme.Enabled -and $config.Theme.SetupBackground) { Resolve-Asset $config.Theme.SetupBackground }
    if ($setupBackground) {
        Write-Step 'Habillage Nova-Os du programme d''installation'
        # Fonds utilises quand l'installation est lancee depuis Windows (setup.exe).
        Update-SetupBackgrounds $sources $setupBackground
        # Environnement de demarrage sur la cle USB / le DVD (boot.wim, image 2).
        try {
            Mount-WindowsImage -ImagePath (Join-Path $sources 'boot.wim') -Index 2 -Path $mountDir | Out-Null
            $wimMounted = $true
            Update-SetupImage $mountDir $setupBackground ([bool]$config.Theme.LegacySetup)
            Dismount-WindowsImage -Path $mountDir -Save | Out-Null
            $wimMounted = $false
        }
        catch {
            Write-Warning "boot.wim non modifie ($($_.Exception.Message)), on continue."
            if ($wimMounted) { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null; $wimMounted = $false }
        }
    }

    Write-Step 'Ajout de autounattend.xml'
    New-Autounattend (Join-Path $isoDir 'autounattend.xml') $arch $config

    Write-Step "Creation de $OutputIso"
    $bios = Join-Path $isoDir 'boot\etfsboot.com'
    $uefi = Join-Path $isoDir 'efi\microsoft\boot\efisys.bin'
    $bootData = if (Test-Path $bios) { "2#p0,e,b$bios#pEF,e,b$uefi" } else { "1#pEF,e,b$uefi" }
    & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" -lNOVA_OS $isoDir $OutputIso
    if ($LASTEXITCODE -ne 0) { throw "oscdimg a echoue (code $LASTEXITCODE)." }

    Write-Host "`nTermine : $OutputIso" -ForegroundColor Green
    Write-Host "Apres l'installation, le journal se trouve dans $NovaDir\Specialize.log"
}
finally {
    if ($wimMounted) { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null }
    if ($isoMounted) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
}
