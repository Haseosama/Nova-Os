#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Construit l'ISO Nova-Os a partir d'un ISO officiel de Windows 11.

.DESCRIPTION
    L'image Windows (install.wim) n'est pas modifiee. Les applications de config.psd1 (Apps) sont
    telechargees a la construction et installees en silence pendant l'installation de Windows.
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

        # Journal de diagnostic au demarrage, saisie vocale en ligne, cartes, recherche de l'appareil.
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener' 'Start' 0
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\SQMLogger' 'Start' 0
        Set-Reg "$DefaultUser\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" 'HasAccepted' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AutoDownloadAndUpdateMapData' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowClipboardHistory' 1
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
        # Telemetrie NVIDIA, prete pour quand le pilote sera installe.
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Services\NvTelemetryContainer' 'Start' 4
        Set-Reg 'HKLM\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client' 'OptInOrOutPreference' 0

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
                          '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
                          '\Microsoft\Windows\Device Information\Device',
                          '\Microsoft\Windows\Device Information\Device User',
                          '\Microsoft\Windows\Maps\MapsUpdateTask',
                          '\Microsoft\Windows\Maps\MapsToastTask') {
            Disable-Task $task
        }
    }

    if ($Config.DisableConsumerFeatures) {
        Write-Host '  - Applis suggerees desactivees'
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
        # Pas de raccourci Edge sur le bureau.
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0
        # Widgets, recherche Bing dans Demarrer et recommandations.
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        Set-Reg "$DefaultUser\Software\Policies\Microsoft\Windows\Explorer" 'DisableSearchBoxSuggestions' 1
        Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'Start_IrisRecommendations' 0
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

    if ($Config.Browser.Brave) {
        Write-Host '  - Brave navigateur par defaut'
        Set-RegString 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'DefaultAssociationsConfiguration' "$NovaDir\DefaultApps.xml"
    }
    if ($Config.Browser.RemoveEdge) {
        Write-Host '  - Edge supprime et bloque (WebView2 garde pour les applis qui en ont besoin)'
        Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0
        Set-Reg 'HKLM\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1
        Set-Reg 'HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev' 'AllowUninstall' 1
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

    if ($Config.DisableSearchIndexing) {
        Write-Host '  - Indexation de recherche desactivee'
        Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Services\WSearch' 'Start' 4
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
function Update-SetupBackgrounds([string] $Dir, [string] $Image, [string] $Pattern = 'background*') {
    Add-Type -AssemblyName System.Drawing
    $files = Get-ChildItem $Dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $Pattern -and $_.Extension -in '.bmp', '.png' }
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
    # Fond affiche par certaines versions de WinPE, s'il existe.
    Update-SetupBackgrounds (Join-Path $Mount 'Windows\System32') $Image -Pattern 'setup*'
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
    Set-Reg $personalize 'ColorPrevalence' 0            # Demarrer et barre des taches noirs (accent sur les details)
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\DWM" 'AccentColor' $abgr
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\DWM" 'ColorPrevalence' 1   # accent sur les barres de titre
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" 'AccentColorMenu' $abgr
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" 'StartColorMenu' $abgr
    Set-RegString "$DefaultUser\Control Panel\Desktop" 'WallPaper' $wallpaper
    Set-RegString "$DefaultUser\Control Panel\Desktop" 'WallpaperStyle' '10'
    # Theme Nova-Os par defaut pour chaque nouveau compte (en plus de autounattend.xml).
    Set-RegString 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes' 'InstallTheme' "$NovaDir\NovaOS.theme"
    Set-RegString "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Themes" 'CurrentTheme' "$NovaDir\NovaOS.theme"

    # Barre des taches epuree : loupe de recherche seule, sans bouton Vue des taches.
    # Pas d'icone de recherche dans la barre des taches : SearchHost et ses processus WebView2
    # ne restent plus en memoire (la recherche marche toujours en tapant dans Demarrer).
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Search" 'SearchboxTaskbarMode' 0
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'ShowTaskViewButton' 0

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

function Set-PerformanceTweaks {
    # Applis en arriere-plan coupees (elles s'ouvrent normalement quand on les lance).
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
    # Pas de partage des mises a jour avec d'autres PC (Windows Update reste actif).
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    # Edge ne reste plus en memoire une fois ferme, ni pre-lance au demarrage.
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
    # Brave non plus ne reste pas en memoire une fois ferme.
    Set-Reg 'HKLM\SOFTWARE\Policies\BraveSoftware\Brave' 'BackgroundModeEnabled' 0
    # Services Windows regroupes dans moins de processus svchost (moins de RAM au repos).
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' 67108864
    # Pas de bridage des processus en arriere-plan (Power Throttling).
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
    # NTFS n'ecrit plus la date du dernier acces a chaque lecture de fichier.
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate' 2147483649
    # Services inutiles sur un PC personnel : fax, demo en magasin, cartes hors ligne, registre a distance.
    foreach ($service in 'Fax', 'RetailDemo', 'MapsBroker', 'RemoteRegistry') {
        Set-Reg "HKLM\SYSTEM\CurrentControlSet\Services\$service" 'Start' 4
    }
    # Session : applis de demarrage lancees sans delai, menus instantanes.
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" 'StartupDelayInMSec' 0
    Set-RegString "$DefaultUser\Control Panel\Desktop" 'MenuShowDelay' '0'
    # Plus d'astuces, de suggestions ni d'ecran "Terminons la configuration".
    $cdm = "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($name in 'SoftLandingEnabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-353694Enabled',
                      'SubscribedContent-353696Enabled', 'SubscribedContent-338393Enabled') {
        Set-Reg $cdm $name 0
    }
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" 'ScoobeSystemSettingEnabled' 0

    # Recherche locale seulement : plus de resultats Bing ni de "points forts" dans Demarrer.
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'EnableDynamicContentInWSB' 0
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Search" 'BingSearchEnabled' 0
    # Plus de publicites OneDrive/Office dans l'Explorateur.
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'ShowSyncProviderNotifications' 0
    # NTFS ne cree plus les noms courts 8.3 (heritage MS-DOS) : creation de fichiers plus rapide.
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisable8dot3NameCreation' 1
    # Autres services inutiles : suivi des liens, controle parental, collecteur de diagnostic.
    foreach ($service in 'TrkWks', 'WpcMonSvc', 'diagnosticshub.standardcollector.service') {
        Set-Reg "HKLM\SYSTEM\CurrentControlSet\Services\$service" 'Start' 4
    }
    # Encore d'autres services sans usage sur un PC de bureau : rapports d'erreurs, assistant de
    # compatibilite, paiement NFC et portefeuille, telephonie, point d'acces mobile, partage
    # Windows Media Player, partage de ports .NET, AllJoyn, cartes a puce, capteurs, services Xbox.
    foreach ($service in 'WerSvc', 'PcaSvc', 'WalletService', 'SEMgrSvc', 'PhoneSvc', 'icssvc',
                         'WMPNetworkSvc', 'NetTcpPortSharing', 'AJRouter', 'SCardSvr', 'ScDeviceEnum',
                         'SensorDataService', 'SensrSvc', 'SensorService',
                         'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc') {
        Set-Reg "HKLM\SYSTEM\CurrentControlSet\Services\$service" 'Start' 4
    }
    # Impression et Bluetooth : seulement si demande dans config.psd1.
    if ($Config.DisablePrinting) { Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Services\Spooler' 'Start' 4 }
    if ($Config.DisableBluetooth) {
        foreach ($service in 'bthserv', 'BTAGService', 'BthAvctpSvc') {
            Set-Reg "HKLM\SYSTEM\CurrentControlSet\Services\$service" 'Start' 4
        }
    }
    # Assistance a distance coupee.
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
    # Pas de telemetrie PowerShell ni .NET.
    Set-RegString 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'POWERSHELL_TELEMETRY_OPTOUT' '1'
    Set-RegString 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'DOTNET_CLI_TELEMETRY_OPTOUT' '1'
    # Fenetres sans animation d'agrandissement/reduction (la transparence reste) et clavier plus reactif.
    Set-RegString "$DefaultUser\Control Panel\Desktop\WindowMetrics" 'MinAnimate' '0'
    Set-RegString "$DefaultUser\Control Panel\Keyboard" 'KeyboardDelay' '0'
    # Jeux en fenetre / plein ecran fenetre : moins de latence (optimisations de Windows 11).
    Set-RegString "$DefaultUser\Software\Microsoft\DirectX\UserGpuPreferences" 'DirectXUserGlobalSettings' 'SwapEffectUpgradeEnable=1;'
    # Explorateur : extensions de fichiers visibles, ouverture sur "Ce PC".
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'HideFileExt' 0
    Set-Reg "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'LaunchTo' 1
    # Edge : pas d'ecran de bienvenue ni d'assistant au premier lancement.
    Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1
}

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

    # Priorite au programme au premier plan (le jeu) dans le partage du processeur.
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38
    # Minuterie systeme precise pour les jeux qui la demandent, meme quand une autre appli la change.
    Set-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1

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

# Installeurs acceptes : programmes d'installation, paquets d'applis (MSIX) et applis portables (zip).
$script:InstallerTypes = '.exe', '.msi', '.msix', '.msixbundle', '.appx', '.appxbundle', '.zip'

function Get-GitHubRelease([string] $Repo, [string] $Target) {
    # Repli quand winget ne fournit pas l'appli : derniere version publiee sur GitHub.
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
        $asset = foreach ($ext in '.msixbundle', '.msix', '.zip', '.exe') {
            $release.assets | Where-Object name -like "*$ext" | Select-Object -First 1
        }
        $asset = $asset | Select-Object -First 1
        if (-not $asset) { return $null }
        $path = Join-Path $Target $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $path -UseBasicParsing
        return Get-Item $path
    }
    catch { Write-Warning "$Repo : telechargement GitHub impossible ($($_.Exception.Message))."; return $null }
}

function Get-SilentArguments([string] $File, [string] $Manifest) {
    if ($File -match '\.(msix|msixbundle|appx|appxbundle)$') { return 'APPX' }
    if ($File -like '*.zip') { return 'ZIP' }
    # Options d'installation silencieuse : celles du manifeste winget, sinon selon le type d'installeur.
    if ($Manifest) {
        $silent = Select-String -Path $Manifest -Pattern '^\s*Silent:\s*(.+)$' | Select-Object -First 1
        if ($silent) { return $silent.Matches[0].Groups[1].Value.Trim().Trim("'").Trim('"') }
    }
    if ($File -like '*.msi') { return '/qn /norestart' }
    $stream = [IO.File]::OpenRead($File)
    try {
        $buffer = New-Object byte[] ([Math]::Min($stream.Length, 16MB))
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $text = [Text.Encoding]::GetEncoding(28591).GetString($buffer, 0, $read)
    }
    finally { $stream.Dispose() }
    if ($text.Contains('Inno Setup')) { return '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS' }
    if ($text.Contains('Nullsoft')) { return '/S' }
    if ($text.Contains('install4j')) { return '-q' }
    return $null
}

function Add-Apps([string] $Dir, $Apps) {
    # Telecharge (winget) ou copie les installeurs dans la charge utile ; Specialize.ps1 les installe
    # en silence pendant l'installation de Windows, sans Internet.
    $appsDir = Join-Path $Dir 'Apps'
    New-Item -ItemType Directory -Force -Path $appsDir | Out-Null
    $list = @()
    foreach ($id in $Apps.Winget) {
        $target = Join-Path $appsDir $id
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        # Version "pour tous les comptes" si elle existe, sinon celle par defaut.
        & winget download --id $id -e --source winget --scope machine -d $target --accept-package-agreements --accept-source-agreements | Out-Null
        if (-not (Get-ChildItem $target -File | Where-Object Extension -in $script:InstallerTypes)) {
            & winget download --id $id -e --source winget -d $target --accept-package-agreements --accept-source-agreements | Out-Null
        }
        # Dependances fournies par winget (Visual C++...) : installees avant l'appli.
        foreach ($dep in Get-ChildItem $target -Recurse -File | Where-Object { $_.DirectoryName -ne $target -and $_.Extension -in $script:InstallerTypes }) {
            $depArgs = if ($dep.Name -like '*vc_redist*' -or $dep.Name -like '*Visual C++*') { '/install /quiet /norestart' } else { Get-SilentArguments $dep.FullName $null }
            if ($null -eq $depArgs) { Write-Warning "$($dep.Name) : type d'installeur inconnu, ignore."; continue }
            if ($list.File -notcontains $dep.Name -and -not ($list | Where-Object Name -eq $dep.Name)) {
                Move-Item $dep.FullName (Join-Path $appsDir $dep.Name) -Force
                $list += [pscustomobject]@{ Name = $dep.Name; File = $dep.Name; Arguments = $depArgs; Logon = '' }
                Write-Host "  - $($dep.Name) (dependance de $id)"
            }
        }
        Get-ChildItem $target -Directory | Remove-Item -Recurse -Force
        $file = Get-ChildItem $target -File | Where-Object Extension -in $script:InstallerTypes | Select-Object -First 1
        if (-not $file -and $id -eq 'TorchGM.RoundedTB') { $file = Get-GitHubRelease 'RoundedTB/RoundedTB' $target }
        if (-not $file) { Write-Warning "$id : telechargement winget impossible (code $LASTEXITCODE), ignore."; Remove-Item $target -Recurse -Force; continue }
        $manifest = Get-ChildItem $target -Filter *.yaml | Select-Object -First 1
        $arguments = Get-SilentArguments $file.FullName $(if ($manifest) { $manifest.FullName })
        # Installeur install4j (JDownloader) : sans dossier impose, il s'installerait dans le profil
        # du compte Systeme qui le lance pendant l'installation de Windows.
        if ($arguments -match '(^|\s)-q(\s|$)' -and $arguments -notmatch '-dir') {
            $arguments += " -dir `"C:\Program Files\$($id.Split('.')[-1])`""
        }
        # Fichier de reponses Inno Setup (/LOADINF) : choix de l'installeur, ex. K-Lite en mode complet.
        $inf = if ($Apps.LoadInf) { $Apps.LoadInf[$id] }
        if ($inf -and -not [IO.Path]::IsPathRooted($inf)) { $inf = Join-Path $PSScriptRoot $inf }
        # Nom different (klcp.ini...) : premier fichier .ini du meme dossier qui commence pareil.
        if ($inf -and -not (Test-Path $inf) -and (Test-Path (Split-Path $inf))) {
            $prefix = (Split-Path $inf -Leaf).Split('_.')[0]
            $found = Get-ChildItem (Split-Path $inf) -Filter "$prefix*.ini" | Select-Object -First 1
            if ($found) { $inf = $found.FullName }
        }
        if ($inf -and (Test-Path $inf)) {
            Copy-Item $inf (Join-Path $target 'setup.inf') -Force
            $arguments += " /LOADINF=`"$NovaDir\Apps\$id\setup.inf`""
        }
        elseif ($inf) { Write-Warning "$id : $inf introuvable, installation avec les choix par defaut." }
        # Brave (installeur Omaha, version "machine") : seules options acceptees, sinon code 0x80040C01.
        if ($id -eq 'Brave.Brave') { $arguments = '/silent /install' }
        Get-ChildItem $target -Filter *.yaml | Remove-Item -Force
        # Installeurs qui echouent sous le compte Systeme pendant l'installation (Brave, base sur
        # Omaha comme Chrome) : installes a la premiere connexion, en administrateur.
        $logon = if ($id -in @($Apps.AtFirstLogon) + 'Brave.Brave') { '1' } else { '' }
        $list += [pscustomobject]@{ Name = $id; File = "$id\$($file.Name)"; Arguments = $arguments; Logon = $logon }
        Write-Host "  - $id ($($file.Name))"
    }
    if ($Apps.Folder -and (Test-Path $Apps.Folder)) {
        foreach ($file in Get-ChildItem $Apps.Folder -File | Where-Object Extension -in '.exe', '.msi') {
            $arguments = Get-SilentArguments $file.FullName $null
            if ($null -eq $arguments) { Write-Warning "$($file.Name) : type d'installeur inconnu, ignore."; continue }
            Copy-Item $file.FullName (Join-Path $appsDir $file.Name) -Force
            $list += [pscustomobject]@{ Name = $file.BaseName; File = $file.Name; Arguments = $arguments; Logon = '' }
            Write-Host "  - $($file.Name)"
        }
    }
    $list | Export-Csv (Join-Path $appsDir 'Apps.csv') -NoTypeInformation -Encoding UTF8
}

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

    # Menu Demarrer des nouveaux comptes : aucune epingle, donc aucun raccourci "suggere"
    # (WhatsApp, Xbox...) que Windows telecharge sinon a la premiere connexion.
    $pins = @()
    ConvertTo-Json @{ pinnedList = $pins } -Depth 3 | Set-Content (Join-Path $Dir 'LayoutModification.json') -Encoding UTF8

    # Barre des taches : Explorateur, navigateur et Store, sans l'epingle Outlook ajoutee par Windows.
    $browserLink = if ($Config.Browser.Brave) { 'Brave.lnk' } else { 'Microsoft Edge.lnk' }
    @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\File Explorer.lnk" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\BROWSER_LINK" />
        <taskbar:UWA AppUserModelID="Microsoft.WindowsStore_8wekyb3d8bbwe!App" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
'@.Replace('BROWSER_LINK', $browserLink) | Set-Content (Join-Path $Dir 'LayoutModification.xml') -Encoding UTF8

    if ($Config.Browser.Brave) {
        # Brave navigateur par defaut des nouveaux comptes (strategie "associations par defaut").
        $associations = '.htm', '.html', '.shtml', '.xht', '.xhtml', '.pdf', '.svg', '.webp', 'http', 'https', 'ftp' |
            ForEach-Object { "  <Association Identifier=`"$_`" ProgId=`"BraveHTML`" ApplicationName=`"Brave`" />" }
        (@('<?xml version="1.0" encoding="UTF-8"?>', '<DefaultAssociations>') + $associations + '</DefaultAssociations>') |
            Set-Content (Join-Path $Dir 'DefaultApps.xml') -Encoding UTF8
    }

    # Cleanup.ps1 : a chaque connexion, retire les applis de la liste deja installees pour le compte
    # (celles que le Store installe tout seul apres l'installation, comme WhatsApp ou Xbox).
    $patterns = ($Config.RemoveApps | ForEach-Object { "'$_'" }) -join ', '
    @"
# Nova-Os : retire les applis indesirables du compte. Journal : %LOCALAPPDATA%\NovaOS-Cleanup.log
`$patterns = @($patterns)
`$log = Join-Path `$env:LOCALAPPDATA 'NovaOS-Cleanup.log'
foreach (`$pattern in `$patterns) {
    Get-AppxPackage -Name "*`$pattern*" | ForEach-Object {
        try {
            Remove-AppxPackage -Package `$_.PackageFullName -ErrorAction Stop
            Add-Content `$log "`$(Get-Date -Format s) supprime : `$(`$_.Name)"
        }
        catch { Add-Content `$log "`$(Get-Date -Format s) ECHEC `$(`$_.Name) : `$(`$_.Exception.Message)" }
    }
}

# Fond d'ecran Nova-Os si Windows ne l'a pas applique (une seule fois par compte).
`$wallpaper = '$NovaDir\wallpaper.jpg'
`$done = 'HKCU:\Software\NovaOS'
if ((Test-Path `$wallpaper) -and -not (Get-ItemProperty `$done -Name ThemeApplied -ErrorAction SilentlyContinue)) {
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
    Add-Type -Namespace NovaOS -Name Desktop -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfo(int action, int param, string value, int flags);'
    [NovaOS.Desktop]::SystemParametersInfo(20, 0, `$wallpaper, 3) | Out-Null   # SPI_SETDESKWALLPAPER
    New-Item `$done -Force | Out-Null
    Set-ItemProperty `$done -Name ThemeApplied -Value 1
    Add-Content `$log "`$(Get-Date -Format s) fond d'ecran Nova-Os applique"
}

# Menu clic droit classique (sans "Afficher plus d'options"), une fois par compte.
`$classic = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
if (-not (Test-Path `$classic)) {
    New-Item `$classic -Force | Set-ItemProperty -Name '(default)' -Value ''
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Add-Content `$log "`$(Get-Date -Format s) menu clic droit classique"
}

"@ | Set-Content (Join-Path $Dir 'Cleanup.ps1') -Encoding UTF8

    if ($Config.Theme.RoundedTaskbar) {
        # RoundedTB (open source) : installe depuis l'ISO avec les autres applis (Apps), lance ici
        # a chaque connexion s'il s'agit du paquet MSIX (la version portable a sa cle Run).
        @"

# Barre des taches arrondie : RoundedTB.
`$installed = Get-AppxPackage -Name '*RoundedTB*'
if (`$installed -and -not (Get-Process RoundedTB -ErrorAction SilentlyContinue)) {
    Start-Process "shell:AppsFolder\`$(`$installed[0].PackageFamilyName)!App" -ErrorAction SilentlyContinue
}
"@ | Add-Content (Join-Path $Dir 'Cleanup.ps1') -Encoding UTF8
    }
    $removeEdge = if ($Config.Browser.RemoveEdge) { '$true' } else { '$false' }
    $needBrave = if ($Config.Browser.Brave) { '$true' } else { '$false' }
    # UserApps.ps1 : premiere connexion (FirstLogonCommands, en administrateur sous le compte cree) :
    # installe les applis "par utilisateur" que le compte Systeme n'a pas pu installer.
    @"
# Nova-Os : applis installees a la premiere connexion. Journal : $NovaDir\UserApps.log
`$userApps = '$NovaDir\UserApps'
if (Test-Path "`$userApps\UserApps.csv") {
    foreach (`$app in Import-Csv "`$userApps\UserApps.csv") {
        `$arguments = `$app.Arguments
        if (`$arguments -match '/VERYSILENT') { `$arguments += " /LOG=``"$NovaDir\`$(`$app.Name)-user-setup.log``"" }
        `$process = Start-Process (Join-Path `$userApps `$app.File) `$arguments -PassThru
        if (-not `$process.WaitForExit(1200000)) { `$process | Stop-Process -Force }
        Add-Content '$NovaDir\UserApps.log' "`$(Get-Date -Format s) `$(`$app.Name) : code `$(`$process.ExitCode)"
    }
}

`$needBrave = $needBrave
if ($removeEdge) {
    # A la premiere connexion : la region (France = Europe) est choisie, la desinstallation est autorisee.
    Add-Content '$NovaDir\UserApps.log' "`$(Get-Date -Format s) suppression de Microsoft Edge"
    `$setup = Get-ChildItem "`${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    # Jamais sans navigateur : Edge reste si Brave n'a pas pu etre installe.
    `$brave = Test-Path "`$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"
    if (`$needBrave -and -not `$brave) { Add-Content '$NovaDir\UserApps.log' "`$(Get-Date -Format s) Brave absent : Edge garde"; `$setup = `$null }
    if (`$setup) {
        # Le desinstalleur refuse si l'ancienne appli Edge integree semble absente : on lui en montre une.
        `$stub = "`$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
        New-Item -ItemType Directory -Force -Path `$stub | Out-Null
        if (-not (Test-Path "`$stub\MicrosoftEdge.exe")) { New-Item -ItemType File -Path "`$stub\MicrosoftEdge.exe" | Out-Null; `$created = `$true }
        `$process = Start-Process `$setup.FullName '--uninstall --system-level --force-uninstall --delete-profile' -PassThru -Wait
        Add-Content '$NovaDir\UserApps.log' "`$(Get-Date -Format s) Edge : code `$(`$process.ExitCode)"
        if (`$created) { Remove-Item "`$stub\MicrosoftEdge.exe" -Force -ErrorAction SilentlyContinue }
    }
    
    Remove-Item "`$env:PUBLIC\Desktop\Microsoft Edge.lnk", "`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
}
"@ | Set-Content (Join-Path $Dir 'UserApps.ps1') -Encoding UTF8

    Set-RegString "$DefaultUser\Software\Microsoft\Windows\CurrentVersion\Run" 'NovaOSCleanup' `
        "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $NovaDir\Cleanup.ps1"

    # Registry.cmd : tous les reglages du registre, profil par defaut charge dans HKU\NovaDefault.
    $lines = @('@echo off',
               "reg load $DefaultUser C:\Users\Default\NTUSER.DAT >nul 2>&1 || echo ECHEC : chargement du profil par defaut") +
             $script:RegLines +
             @("reg unload $DefaultUser >nul 2>&1", 'exit /b 0')
    $lines | Set-Content (Join-Path $Dir 'Registry.cmd') -Encoding Ascii

    # Specialize.ps1 : lance par autounattend.xml pendant l'installation, avant la creation du compte.
    $power = if ($Config.UltimatePerformance) { '$true' } else { '$false' }
    $hibernate = if ($Config.DisableHibernation) { '$true' } else { '$false' }
    $reserved = if ($Config.DisableReservedStorage) { '$true' } else { '$false' }
    $cleanup = if ($Config.CleanupComponents) { '$true' } else { '$false' }
    $features = ($Config.RemoveFeatures | ForEach-Object { "'$_'" }) -join ', '
    $capabilities = ($Config.RemoveCapabilities | ForEach-Object { "'$_'" }) -join ', '
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

Write-Output '== Menu Demarrer'
`$shell = 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell'
New-Item -ItemType Directory -Force -Path `$shell | Out-Null
Copy-Item '$NovaDir\LayoutModification.json' (Join-Path `$shell 'LayoutModification.json') -Force
Copy-Item '$NovaDir\LayoutModification.xml' (Join-Path `$shell 'LayoutModification.xml') -Force
Remove-Item "`$env:PUBLIC\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
Write-Output '  epingles Nova-Os'

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

`$apps = '$NovaDir\Apps'
if (Test-Path "`$apps\Apps.csv") {
    Write-Output '== Applications Nova-Os'
    foreach (`$app in Import-Csv "`$apps\Apps.csv") {
        `$file = Join-Path `$apps `$app.File
        if (`$app.Logon) {
            `$userApps = '$NovaDir\UserApps'
            New-Item -ItemType Directory -Force -Path `$userApps | Out-Null
            Copy-Item `$file `$userApps -Force
            [pscustomobject]@{ Name = `$app.Name; File = (Split-Path `$file -Leaf); Arguments = `$app.Arguments } |
                Export-Csv "`$userApps\UserApps.csv" -NoTypeInformation -Encoding UTF8 -Append
            Write-Output "  `$(`$app.Name) : installe a la premiere connexion"
            continue
        }
        if (`$app.Arguments -eq 'APPX') {
            # Paquet d'appli : provisionne pour tous les comptes.
            try { Add-AppxProvisionedPackage -Online -PackagePath `$file -SkipLicense -ErrorAction Stop | Out-Null; Write-Output "  `$(`$app.Name) : provisionne" }
            catch { Write-Output "  `$(`$app.Name) : ECHEC `$(`$_.Exception.Message)" }
            continue
        }
        if (`$app.Arguments -eq 'ZIP') {
            # Appli portable : copiee dans Program Files, lancee a chaque connexion.
            `$name = (`$app.Name -split '\.')[-1]
            `$dest = Join-Path `$env:ProgramFiles `$name
            Expand-Archive `$file `$dest -Force
            `$exe = Get-ChildItem `$dest -Recurse -Filter "`$name.exe" | Select-Object -First 1
            if (-not `$exe) { `$exe = Get-ChildItem `$dest -Recurse -Filter *.exe | Select-Object -First 1 }
            if (`$exe) {
                New-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name `$name -Value "``"`$(`$exe.FullName)``"" -Force | Out-Null
                `$link = (New-Object -ComObject WScript.Shell).CreateShortcut("`$env:ProgramData\Microsoft\Windows\Start Menu\Programs\`$name.lnk")
                `$link.TargetPath = `$exe.FullName; `$link.Save()
            }
            Write-Output "  `$(`$app.Name) : copie dans `$dest"
            continue
        }
        if (`$file -like '*.msi') { `$process = Start-Process msiexec.exe "/i ``"`$file``" `$(`$app.Arguments)" -PassThru }
        else {
            `$arguments = `$app.Arguments
            if (`$arguments -match '/VERYSILENT') { `$arguments += " /LOG=``"$NovaDir\`$(`$app.Name)-setup.log``"" }
            `$process = Start-Process `$file `$arguments -PassThru
        }
        if (-not `$process.WaitForExit(1200000)) { `$process | Stop-Process -Force; Write-Output "  `$(`$app.Name) : trop long, arrete" }
        else { Write-Output "  `$(`$app.Name) : code `$(`$process.ExitCode)" }
        if (`$process.HasExited -and `$process.ExitCode -notin 0, 3010 -and `$file -notlike '*.msi') {
            # Installeur qui refuse le compte Systeme : relance a la premiere connexion, en
            # administrateur sous le compte cree (UserApps.ps1), sans les options "pour tous".
            `$userApps = '$NovaDir\UserApps'
            New-Item -ItemType Directory -Force -Path `$userApps | Out-Null
            Copy-Item `$file `$userApps -Force
            `$userArgs = (`$app.Arguments -replace '\s*/ALLUSERS', '' -replace '\s*-dir\s+"[^"]*"', '').Trim()
            [pscustomobject]@{ Name = `$app.Name; File = (Split-Path `$file -Leaf); Arguments = `$userArgs } |
                Export-Csv "`$userApps\UserApps.csv" -NoTypeInformation -Encoding UTF8 -Append
            Write-Output "  `$(`$app.Name) : sera installe a la premiere connexion"
        }
    }
    Remove-Item `$apps -Recurse -Force -ErrorAction SilentlyContinue
}

`$features = @($features)
`$capabilities = @($capabilities)
if (`$features -or `$capabilities) {
    Write-Output '== Composants Windows inutiles'
    foreach (`$name in `$features) {
        `$feature = Get-WindowsOptionalFeature -Online -FeatureName `$name -ErrorAction SilentlyContinue
        if (`$feature -and `$feature.State -eq 'Enabled') {
            try { Disable-WindowsOptionalFeature -Online -FeatureName `$name -NoRestart -ErrorAction Stop | Out-Null; Write-Output "  desactive : `$name" }
            catch { Write-Output "  ECHEC `$name : `$(`$_.Exception.Message)" }
        }
    }
    `$installed = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object State -eq 'Installed'
    foreach (`$name in `$capabilities) {
        `$installed | Where-Object Name -like "`$name~*" | ForEach-Object {
            try { Remove-WindowsCapability -Online -Name `$_.Name -ErrorAction Stop | Out-Null; Write-Output "  supprime : `$(`$_.Name)" }
            catch { Write-Output "  ECHEC `$(`$_.Name) : `$(`$_.Exception.Message)" }
        }
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

if ($hibernate) {
    Write-Output '== Veille prolongee et demarrage rapide desactives (hiberfil.sys supprime)'
    powercfg /hibernate off
    Write-Output "  code `$LASTEXITCODE"
}

if ($reserved) {
    Write-Output '== Stockage reserve desactive (environ 7 Go rendus, Windows Update reste actif)'
    Dism.exe /Online /Set-ReservedStorageState /State:Disabled /Quiet
    Write-Output "  code `$LASTEXITCODE"
}

if ($cleanup) {
    Write-Output '== Nettoyage du magasin de composants (WinSxS)'
    Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet
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
    $spCommands += "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $NovaDir\Specialize.ps1"
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
    $firstLogon = ''
    if ($Config.Apps.Enabled -or $Config.Browser.RemoveEdge) {
        $firstLogon = @"
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $NovaDir\UserApps.ps1</CommandLine>
          <Description>Nova-Os : applis par utilisateur</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
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
$firstLogon$oobe$themes    </component>
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
# Cle de licence personnelle, gardee hors du depot (jamais sur GitHub).
if ($config.InstallKeyFile -and (Test-Path $config.InstallKeyFile)) {
    $config.InstallKey = (Get-Content $config.InstallKeyFile -Raw).Trim()
    Write-Host "Cle de produit lue depuis $($config.InstallKeyFile)"
}
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
    if ($config.PerformanceTweaks) {
        Write-Host '  - Performances (arriere-plan, services inutiles, Edge, demarrage)'
        Set-PerformanceTweaks
    }
    if ($config.GamingTweaks) {
        Write-Host '  - Optimisations jeux'
        Set-GamingTweaks
    }

    Write-Step "Ajout de la charge utile Nova-Os ($OemNovaDir)"
    New-Payload (Join-Path $isoDir $OemNovaDir) $config
    if ($config.Theme.Enabled -and $config.Theme.RoundedTaskbar) {
        if (-not $config.Apps) { $config.Apps = @{ Enabled = $true; Winget = @() } }
        $config.Apps.Enabled = $true
        $config.Apps.Winget = @($config.Apps.Winget) + 'TorchGM.RoundedTB'
    }
    if ($config.Browser.Brave) {
        if (-not $config.Apps) { $config.Apps = @{ Enabled = $true; Winget = @() } }
        $config.Apps.Enabled = $true
        $config.Apps.Winget = @('Brave.Brave') + @($config.Apps.Winget)
    }
    if ($config.Apps.Enabled) {
        Write-Step 'Telechargement des applications Nova-Os'
        Add-Apps (Join-Path $isoDir $OemNovaDir) $config.Apps
    }

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
    # oscdimg ecrit sa progression sur stderr : sans ce Continue, PowerShell l'arrete des la
    # premiere ligne quand la sortie est redirigee vers un journal.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" -lNOVA_OS $isoDir $OutputIso 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = $previousPreference
    if ($LASTEXITCODE -ne 0) { throw "oscdimg a echoue (code $LASTEXITCODE)." }

    Write-Host "`nTermine : $OutputIso" -ForegroundColor Green
    Write-Host "Apres l'installation, le journal se trouve dans $NovaDir\Specialize.log"
}
finally {
    if ($wimMounted) { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null }
    if ($isoMounted) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
}
