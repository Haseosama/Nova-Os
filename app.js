(() => {
  'use strict';

  const LANGUAGE_MAP = {
    'fr-FR': { label: 'Français (France)', short: 'FR · FR', input: '040c:0000040c' },
    'en-US': { label: 'English (United States)', short: 'EN · US', input: '0409:00000409' },
    'es-ES': { label: 'Español (España)', short: 'ES · ES', input: '0c0a:0000040a' },
    'de-DE': { label: 'Deutsch (Deutschland)', short: 'DE · DE', input: '0407:00000407' }
  };

  const ACCENTS = {
    mint: { label: 'Vert néon', hex: '#b6f17b', rgb: '182, 241, 123' },
    ice: { label: 'Bleu glacier', hex: '#74c9ef', rgb: '116, 201, 239' },
    violet: { label: 'Violet orbital', hex: '#b5a1fa', rgb: '181, 161, 250' },
    amber: { label: 'Ambre', hex: '#f0bd73', rgb: '240, 189, 115' }
  };

  const DEFAULTS = {
    widgets: true,
    copilot: true,
    consumerFeatures: true,
    suggestions: true,
    limitDiagnostics: true,
    advertisingId: true,
    tailoredExperiences: true,
    activityHistory: true,
    webSearch: false,
    removeXbox: true,
    removeTeams: true,
    removeClipchamp: true,
    removeNews: true,
    removeSolitaire: false,
    removePhoneLink: false
  };

  const PROFILES = {
    nova: { ...DEFAULTS },
    essential: {
      widgets: false,
      copilot: true,
      consumerFeatures: false,
      suggestions: false,
      limitDiagnostics: true,
      advertisingId: true,
      tailoredExperiences: true,
      activityHistory: false,
      webSearch: false,
      removeXbox: false,
      removeTeams: false,
      removeClipchamp: false,
      removeNews: false,
      removeSolitaire: false,
      removePhoneLink: false
    }
  };

  const SETTINGS = {
    system: {
      intro: 'Ajustez les fonctions visibles et les suggestions de Windows.',
      rows: [
        { id: 'widgets', title: 'Désactiver les widgets', detail: 'Masque le panneau Widgets de la barre des tâches.', icon: '#i-grid', tag: 'OPTIONNEL' },
        { id: 'copilot', title: 'Désactiver Microsoft Copilot', detail: 'Applique la stratégie Windows prévue pour cette fonctionnalité.', icon: '#i-spark', tag: 'OPTIONNEL' },
        { id: 'consumerFeatures', title: 'Réduire les applications suggérées', detail: 'Limite l’installation automatique de contenus grand public.', icon: '#i-window', tag: 'SOBRE' },
        { id: 'suggestions', title: 'Masquer les suggestions Windows', detail: 'Désactive une partie des conseils et promotions intégrés.', icon: '#i-sliders', tag: 'SOBRE' }
      ],
      note: 'Les mises à jour système, Windows Defender et Microsoft Store ne sont pas désactivés.'
    },
    privacy: {
      intro: 'Réduisez les réglages publicitaires et diagnostics facultatifs.',
      rows: [
        { id: 'limitDiagnostics', title: 'Limiter les diagnostics facultatifs', detail: 'Demande le niveau minimal pris en charge par l’édition Windows.', icon: '#i-shield', tag: 'À SAVOIR' },
        { id: 'advertisingId', title: 'Désactiver l’identifiant publicitaire', detail: 'Désactive l’identifiant utilisé pour personnaliser les annonces.', icon: '#i-lock', tag: 'CONFIDENTIALITÉ' },
        { id: 'tailoredExperiences', title: 'Désactiver les expériences personnalisées', detail: 'Empêche les conseils fondés sur les données de diagnostic.', icon: '#i-spark', tag: 'CONFIDENTIALITÉ' },
        { id: 'activityHistory', title: 'Désactiver le partage d’activité', detail: 'Désactive les stratégies Windows liées à l’historique d’activité.', icon: '#i-clock', tag: 'OPTIONNEL' },
        { id: 'webSearch', title: 'Limiter les résultats web dans la recherche', detail: 'Réduit l’intégration des résultats Internet dans la recherche Windows.', icon: '#i-grid', tag: 'OPTIONNEL' }
      ],
      note: 'Aucune promesse de « zéro télémétrie » : certains diagnostics restent requis par Windows et dépendent de l’édition.'
    },
    apps: {
      intro: 'Retirez les applications grand public que vous n’utilisez pas.',
      rows: [
        { id: 'removeXbox', title: 'Xbox et composants gaming', detail: 'Retire les packages Xbox grand public ; les jeux restent installables.', icon: '#i-cpu', tag: 'OPTIONNEL' },
        { id: 'removeTeams', title: 'Teams personnel', detail: 'Retire l’application Teams personnelle provisionnée par Windows.', icon: '#i-window', tag: 'OPTIONNEL' },
        { id: 'removeClipchamp', title: 'Clipchamp', detail: 'Retire l’application Clipchamp fournie avec certaines images.', icon: '#i-window', tag: 'OPTIONNEL' },
        { id: 'removeNews', title: 'Actualités et météo Bing', detail: 'Retire les applications d’actualités et météo provisionnées.', icon: '#i-grid', tag: 'OPTIONNEL' },
        { id: 'removeSolitaire', title: 'Microsoft Solitaire Collection', detail: 'Retire la collection de jeux préinstallée.', icon: '#i-spark', tag: 'OPTIONNEL' },
        { id: 'removePhoneLink', title: 'Mobile connecté', detail: 'Retire le lien avec le téléphone si vous ne l’utilisez pas.', icon: '#i-window', tag: 'OPTIONNEL' }
      ],
      note: 'Le kit ne supprime ni Edge, ni le Microsoft Store, ni Defender, ni les composants nécessaires au système.'
    }
  };

  const state = {
    image: null,
    profile: 'nova',
    activeTab: 'system',
    options: { ...DEFAULTS },
    language: 'fr-FR',
    theme: 'dark',
    accent: 'mint',
    history: []
  };

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const useIcon = (id) => `<svg class="icon" aria-hidden="true"><use href="#${id.replace(/^#/, '')}"></use></svg>`;

  const elements = {
    isoInput: $('#isoInput'),
    dropzone: $('#dropzone'),
    prompt: $('#dropzonePrompt'),
    fileLoaded: $('#fileLoaded'),
    settingsList: $('#settingsList'),
    settingsIntro: $('#settingsIntro'),
    settingsFootnote: $('#settingsFootnote'),
    exportButton: $('#exportButton'),
    toastRegion: $('#toastRegion'),
    historyList: $('#historyList'),
    modalBackdrop: $('#modalBackdrop')
  };

  function cloneOptions(options) {
    return Object.fromEntries(Object.entries(options).map(([key, value]) => [key, Boolean(value)]));
  }

  function formatSize(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return 'Taille inconnue';
    const units = ['octets', 'Ko', 'Mo', 'Go', 'To'];
    const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const value = bytes / (1024 ** exponent);
    const digits = exponent === 0 ? 0 : value >= 10 ? 1 : 2;
    return `${value.toFixed(digits).replace('.', ',')} ${units[exponent]}`;
  }

  function showToast(message, type = 'success', duration = 4300) {
    const toast = document.createElement('div');
    toast.className = `toast${type === 'warning' ? ' is-warning' : type === 'error' ? ' is-error' : ''}`;
    toast.innerHTML = `${useIcon(type === 'error' ? 'i-help' : type === 'warning' ? 'i-shield' : 'i-check')}<span></span>`;
    $('.toast span', toast).textContent = message;
    elements.toastRegion.appendChild(toast);
    window.setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(6px)';
      window.setTimeout(() => toast.remove(), 200);
    }, duration);
  }

  function setImage(file) {
    if (!file) return;
    if (!/\.iso$/i.test(file.name)) {
      showToast('Choisissez un fichier .iso. Le contenu ne sera pas téléversé.', 'error');
      return;
    }
    state.image = { name: file.name, size: file.size, lastModified: file.lastModified };
    elements.isoInput.value = '';
    renderImage();
    updateDerived();
    showToast(`${file.name} est sélectionné localement. Son contenu n’a pas été lu.`);
  }

  function renderImage() {
    const hasImage = Boolean(state.image);
    elements.dropzone.classList.toggle('is-loaded', hasImage);
    elements.prompt.hidden = hasImage;
    elements.fileLoaded.hidden = !hasImage;
    $('#navIsoState').textContent = hasImage ? 'OK' : '—';
    if (hasImage) {
      $('#loadedFileName').textContent = state.image.name;
      $('#loadedFileMeta').textContent = `ISO · ${formatSize(state.image.size)} · référence locale`;
      $('#metricIso').textContent = 'Sélectionnée';
      $('#metricIsoSub').textContent = formatSize(state.image.size);
    } else {
      $('#metricIso').textContent = 'En attente';
      $('#metricIsoSub').textContent = 'Aucun média chargé';
    }
  }

  function setActiveProfile(profile) {
    if (profile === 'nova' || profile === 'essential') {
      state.options = cloneOptions(PROFILES[profile]);
    }
    state.profile = profile;
    $$('.profile-card').forEach((card) => {
      const selected = card.dataset.profile === profile;
      card.classList.toggle('is-selected', selected);
      card.setAttribute('aria-pressed', String(selected));
    });
    renderSettings();
    updateDerived();
  }

  function renderSettings() {
    const group = SETTINGS[state.activeTab];
    if (!group) return;
    const activeCount = group.rows.filter((row) => state.options[row.id]).length;
    elements.settingsIntro.innerHTML = `<span>${group.intro}</span><strong>${activeCount} activée${activeCount > 1 ? 's' : ''}</strong>`;
    elements.settingsList.innerHTML = group.rows.map((row) => {
      const checked = Boolean(state.options[row.id]);
      return `<div class="setting-row">
        <span class="setting-icon">${useIcon(row.icon)}</span>
        <div class="setting-copy"><strong>${row.title}<span class="setting-tag">${row.tag}</span></strong><p>${row.detail}</p></div>
        <button class="switch" type="button" role="switch" aria-checked="${checked}" aria-label="${row.title}" data-option="${row.id}"></button>
      </div>`;
    }).join('');
    elements.settingsFootnote.innerHTML = `${useIcon('i-lock')}<span>${group.note}</span>`;

    $$('.settings-tab').forEach((tab) => {
      const selected = tab.dataset.tab === state.activeTab;
      tab.classList.toggle('is-active', selected);
      tab.setAttribute('aria-selected', String(selected));
    });
    $('#tabCountSystem').textContent = `${SETTINGS.system.rows.filter((row) => state.options[row.id]).length}/${SETTINGS.system.rows.length}`;
    $('#tabCountPrivacy').textContent = `${SETTINGS.privacy.rows.filter((row) => state.options[row.id]).length}/${SETTINGS.privacy.rows.length}`;
    $('#tabCountApps').textContent = `${SETTINGS.apps.rows.filter((row) => state.options[row.id]).length}/${SETTINGS.apps.rows.length}`;
  }

  function chooseTab(tabName) {
    if (!SETTINGS[tabName]) return;
    state.activeTab = tabName;
    renderSettings();
    setActiveNavigation('customize', tabName === 'privacy' ? 'privacy' : 'system');
  }

  function setActiveNavigation(target, tabName = '') {
    const navigationTab = tabName === 'privacy' ? 'privacy' : tabName ? 'system' : '';
    $$('.nav-item[data-target]').forEach((item) => {
      const sameTarget = item.dataset.target === target;
      const matchesTab = !item.dataset.tab || item.dataset.tab === navigationTab || !navigationTab;
      const active = sameTarget && matchesTab;
      item.classList.toggle('is-active', active);
      if (active) item.setAttribute('aria-current', 'page');
      else item.removeAttribute('aria-current');
    });
  }

  function updateTheme() {
    document.body.dataset.theme = state.theme;
    $$('.theme-option').forEach((button) => {
      const selected = button.dataset.theme === state.theme;
      button.classList.toggle('is-selected', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
    $('#summaryTheme').textContent = state.theme === 'dark' ? 'Sombre' : 'Clair';
  }

  function updateAccent() {
    const accent = ACCENTS[state.accent] || ACCENTS.mint;
    document.documentElement.style.setProperty('--accent', accent.hex);
    document.documentElement.style.setProperty('--accent-rgb', accent.rgb);
    $('#accentLabel').textContent = accent.label;
    $$('.accent-swatch').forEach((button) => {
      const selected = button.dataset.accent === state.accent;
      button.classList.toggle('is-selected', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
  }

  function updateDerived() {
    const allRows = Object.values(SETTINGS).flatMap((group) => group.rows);
    const selectedCount = allRows.filter((row) => state.options[row.id]).length;
    const selectedApps = SETTINGS.apps.rows.filter((row) => state.options[row.id]).length;
    const selectedPrivacy = SETTINGS.privacy.rows.filter((row) => state.options[row.id]).length;
    const hasImage = Boolean(state.image);

    $('#metricOptions').textContent = String(selectedCount);
    $('#metricBuildState').textContent = hasImage ? 'Prêt à exporter' : 'À configurer';
    $('#summaryOptionCount').textContent = String(selectedCount);
    $('#summaryAppsCount').textContent = String(selectedApps);
    $('#summaryLanguage').textContent = (LANGUAGE_MAP[state.language] || LANGUAGE_MAP['fr-FR']).short;
    $('#navIsoState').textContent = hasImage ? 'OK' : '—';

    const status = $('#summaryStatus');
    status.classList.toggle('is-ready', hasImage);
    if (hasImage) {
      $('strong', status).textContent = state.image.name;
      $('small', status).textContent = `${formatSize(state.image.size)} · référence locale`;
    } else {
      $('strong', status).textContent = 'Source manquante';
      $('small', status).textContent = 'Ajoutez un ISO pour continuer';
    }

    const completeness = Math.min(100, 58 + (selectedCount > 0 ? 12 : 0) + (state.language ? 5 : 0) + (state.theme ? 5 : 0) + (state.accent ? 5 : 0) + (hasImage ? 15 : 0));
    $('#completenessValue').textContent = `${completeness}%`;
    $('#completenessBar').style.width = `${completeness}%`;
    $('#metricOptions').setAttribute('aria-label', `${selectedCount} options activées, dont ${selectedPrivacy} options de confidentialité et ${selectedApps} applications à retirer`);
    renderSettings();
  }

  function collectProfile() {
    const accent = ACCENTS[state.accent];
    return {
      product: 'NovaOS Studio',
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      source: state.image ? { fileName: state.image.name, sizeBytes: state.image.size, contentsIncluded: false } : null,
      profile: state.profile,
      language: state.language,
      desktop: { theme: state.theme, accentName: accent.label, accentHex: accent.hex },
      options: { ...state.options },
      notes: [
        'Ce profil décrit des réglages proposés, pas un ISO reconstruit.',
        'Le niveau de diagnostic dépend de l’édition et des stratégies Windows. Aucun réglage ne garantit zéro télémétrie.',
        'Relisez le script PowerShell et testez les changements sur une machine de test avant tout déploiement.'
      ]
    };
  }

  function escapeXml(value) {
    return String(value).replace(/[<>&"']/g, (char) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' })[char]);
  }

  function createAnswerFile() {
    const language = LANGUAGE_MAP[state.language] || LANGUAGE_MAP['fr-FR'];
    const locale = escapeXml(state.language);
    const keyboard = escapeXml(language.input);
    return `<?xml version="1.0" encoding="utf-8"?>\n<unattend xmlns="urn:schemas-microsoft-com:unattend">\n  <!-- NovaOS Studio : préremplit uniquement la langue et le clavier. -->\n  <settings pass="windowsPE">\n    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">\n      <SetupUILanguage>\n        <UILanguage>${locale}</UILanguage>\n      </SetupUILanguage>\n      <InputLocale>${keyboard}</InputLocale>\n      <SystemLocale>${locale}</SystemLocale>\n      <UILanguage>${locale}</UILanguage>\n      <UserLocale>${locale}</UserLocale>\n    </component>\n  </settings>\n  <settings pass="oobeSystem">\n    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">\n      <InputLocale>${keyboard}</InputLocale>\n      <SystemLocale>${locale}</SystemLocale>\n      <UILanguage>${locale}</UILanguage>\n      <UserLocale>${locale}</UserLocale>\n    </component>\n  </settings>\n</unattend>\n`;
  }

  function createPowerShell(profile) {
    const appPatterns = [];
    if (profile.options.removeXbox) appPatterns.push('Microsoft.Xbox*');
    if (profile.options.removeTeams) appPatterns.push('MSTeams', 'MicrosoftTeams');
    if (profile.options.removeClipchamp) appPatterns.push('Clipchamp.Clipchamp');
    if (profile.options.removeNews) appPatterns.push('Microsoft.BingNews', 'Microsoft.BingWeather');
    if (profile.options.removeSolitaire) appPatterns.push('Microsoft.MicrosoftSolitaireCollection');
    if (profile.options.removePhoneLink) appPatterns.push('Microsoft.YourPhone');

    const appLiteral = appPatterns.length
      ? appPatterns.map((pattern) => `    '${pattern}'`).join(',\n')
      : '    # Aucune application sélectionnée';
    const themeValue = profile.desktop.theme === 'dark' ? 0 : 1;
    const hex = profile.desktop.accentHex.replace('#', '');
    const rgb = [0, 2, 4].map((offset) => parseInt(hex.slice(offset, offset + 2), 16));
    const accentValue = `${rgb[2].toString(16).padStart(2, '0')}${rgb[1].toString(16).padStart(2, '0')}${rgb[0].toString(16).padStart(2, '0')}`.toUpperCase();

    const operations = [];
    if (profile.options.limitDiagnostics) {
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection' 'AllowTelemetry' 1`);
      operations.push(`# 1 = minimum generally available on Pro/Home; Enterprise policy can differ.`);
    }
    if (profile.options.advertisingId) {
      operations.push(`Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo' 'Enabled' 0`);
    }
    if (profile.options.tailoredExperiences) {
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1`);
    }
    if (profile.options.activityHistory) {
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System' 'EnableActivityFeed' 0`);
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System' 'PublishUserActivities' 0`);
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System' 'UploadUserActivities' 0`);
    }
    if (profile.options.webSearch) {
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Search' 'DisableWebSearch' 1`);
    }
    if (profile.options.consumerFeatures) {
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent' 'DisableWindowsConsumerFeatures' 1`);
    }
    if (profile.options.copilot) {
      operations.push(`Set-NovaDword 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsCopilot' 'TurnOffWindowsCopilot' 1`);
    }
    if (profile.options.widgets) {
      operations.push(`Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced' 'TaskbarDa' 0`);
    }
    if (profile.options.suggestions) {
      operations.push(`Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0`);
      operations.push(`Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0`);
      operations.push(`Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0`);
      operations.push(`Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0`);
    }

    const operationBlock = operations.length
      ? operations.map((line) => `    ${line}`).join('\n')
      : '    Write-Host "Aucun réglage système ou confidentialité sélectionné."';

    return `# NovaOS Studio — script de configuration post-installation
# Généré le ${new Date().toISOString()}
# IMPORTANT : relisez ce fichier et testez-le dans une machine virtuelle avant usage.
# Il ne reconstruit pas l’ISO, ne désactive pas les mises à jour/Defender et ne garantit pas zéro télémétrie.

[CmdletBinding()]
param(
    [switch]$PreviewOnly
)

$ErrorActionPreference = 'Continue'
$SelectedApps = @(
${appLiteral}
)
$DesktopTheme = '${profile.desktop.theme}'
$AccentHex = '${profile.desktop.accentHex}'

function Set-NovaDword {
    param([string]$Path, [string]$Name, [int]$Value)
    if ($PreviewOnly) {
        Write-Host "[APERÇU] $Path\\$Name = $Value"
        return
    }
    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Lancez PowerShell en tant qu’administrateur, puis relisez les changements avant de continuer.'
}

Write-Host ''
Write-Host 'NovaOS Studio — aperçu des réglages choisis' -ForegroundColor Cyan
Write-Host "Thème de bureau : $DesktopTheme ; accent : $AccentHex"
Write-Host "Packages sélectionnés pour retrait : $($SelectedApps.Count)"
Write-Host 'Les paramètres utilisateur HKCU s’appliquent au compte qui exécute ce script.'
Write-Host 'Certaines données de diagnostic restent requises par Windows et varient selon l’édition.'
Write-Host ''
if (-not $PreviewOnly) {
    $confirmation = Read-Host 'Après avoir lu le script, tapez APPLY pour appliquer ces réglages'
    if ($confirmation -cne 'APPLY') {
        Write-Host 'Aucune modification appliquée.' -ForegroundColor Yellow
        exit 0
    }
}

$backupRoot = Join-Path $env:ProgramData ('NovaOS\\Backup\\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (-not $PreviewOnly) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $registryExports = @(
        @{ Key = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize'; File = 'theme.reg' },
        @{ Key = 'HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection'; File = 'diagnostics.reg' }
    )
    foreach ($entry in $registryExports) {
        & reg.exe export $entry.Key (Join-Path $backupRoot $entry.File) /y 2>$null | Out-Null
    }
    Write-Host "Sauvegarde des stratégies : $backupRoot" -ForegroundColor DarkGray
}

Write-Host 'Application des préférences...' -ForegroundColor Cyan
try {
${operationBlock}

    $personalizePath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize'
    Set-NovaDword $personalizePath 'SystemUsesLightTheme' ${themeValue}
    Set-NovaDword $personalizePath 'AppsUseLightTheme' ${themeValue}

    if ($DesktopTheme -and $AccentHex -match '^#[0-9a-fA-F]{6}$') {
        $r = [Convert]::ToInt32($AccentHex.Substring(1, 2), 16)
        $g = [Convert]::ToInt32($AccentHex.Substring(3, 2), 16)
        $b = [Convert]::ToInt32($AccentHex.Substring(5, 2), 16)
        $accentColor = [Convert]::ToUInt32(('FF{0:X2}{1:X2}{2:X2}' -f $b, $g, $r), 16)
        $accentColorSigned = [BitConverter]::ToInt32([BitConverter]::GetBytes([UInt32]$accentColor), 0)
        Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\DWM' 'ColorizationColor' $accentColorSigned
        Set-NovaDword 'HKCU:\\Software\\Microsoft\\Windows\\DWM' 'ColorPrevalence' 1
    }

    if ($SelectedApps.Count -gt 0) {
        $matchesPattern = {
            param($Name)
            foreach ($pattern in $SelectedApps) {
                if ($Name -like $pattern) { return $true }
            }
            return $false
        }

        Write-Host 'Retrait des applications provisionnées sélectionnées...' -ForegroundColor Cyan
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | ForEach-Object {
            if (& $matchesPattern $_.DisplayName) {
                Write-Host "  Provisionné : $($_.DisplayName)"
                if (-not $PreviewOnly) {
                    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Continue | Out-Null
                }
            }
        }

        Write-Host 'Retrait des applications présentes pour les utilisateurs...' -ForegroundColor Cyan
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
            if (& $matchesPattern $_.Name) {
                Write-Host "  Installé : $($_.Name)"
                if (-not $PreviewOnly) {
                    try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop }
                    catch { Write-Warning "Impossible de retirer $($_.Name) : $($_.Exception.Message)" }
                }
            }
        }
    }

    if ($PreviewOnly) {
        Write-Host 'Aucun changement écrit : mode aperçu.' -ForegroundColor Green
    } else {
        Write-Host 'Configuration terminée. Un redémarrage peut être nécessaire.' -ForegroundColor Green
    }
} catch {
    Write-Error "Le script s’est arrêté : $($_.Exception.Message)"
    throw
}
`;
  }

  function createReadme(profile) {
    const sourceLine = profile.source
      ? `Fichier de référence sélectionné : ${profile.source.fileName} (${formatSize(profile.source.sizeBytes)}).\nSon contenu n’est pas inclus dans cette archive.\n`
      : 'Aucun fichier ISO de référence n’est inclus.\n';
    return `NOVAOS STUDIO — KIT DE CONFIGURATION\n====================================\n\nCe ZIP contient un profil de personnalisation, un script PowerShell relisible et un fichier de réponse de langue/clavier.\n\nIMPORTANT\n---------\nCe kit N’EST PAS un ISO Windows modifié. Le navigateur ne monte pas, ne lit pas et ne reconstruit pas votre ISO. Il n’a conservé que les métadonnées du fichier sélectionné. Pour créer réellement un média personnalisé, il faut un poste Windows et un flux de maintenance/reconstruction adapté (DISM et outils Windows ADK).\n\n${sourceLine}\nFICHIERS\n--------\n- NovaOS-profile.json : récapitulatif des options choisies.\n- Apply-NovaOS.ps1 : script à lire avant exécution ; retire seulement les packages cochés et applique des stratégies/préférences Windows.\n- autounattend.xml : préremplit la langue et le clavier, sans ignorer l’OOBE, le compte Microsoft, l’activation ou les exigences matérielles.\n\nUTILISATION PRUDENTE\n--------------------\n1. Vérifiez que votre média Windows et votre édition prennent en charge la langue sélectionnée.\n2. Ouvrez le JSON et le script dans un éditeur de texte.\n3. Testez d’abord dans une machine virtuelle ou sur un appareil de test, avec une sauvegarde.\n4. Pour le script, lancez PowerShell en administrateur. -PreviewOnly affiche les actions sans écrire les changements.\n5. Les préférences HKCU ne concernent que le compte qui exécute le script. Les stratégies et options disponibles peuvent varier selon Windows, l’édition et les politiques de l’organisation.\n\nCONFIDENTIALITÉ ET TÉLÉMÉTRIE\n----------------------------\nLe script demande le niveau minimal de diagnostics généralement disponible sur les éditions grand public ; il ne prétend pas supprimer tous les diagnostics requis par Windows. Microsoft Defender, Windows Update, Edge et le Microsoft Store ne sont pas retirés par ce profil.\n\nGénéré localement par NovaOS Studio. Aucune donnée n’a été téléversée.\n`;
  }

  function crc32(bytes) {
    if (!crc32.table) {
      crc32.table = new Uint32Array(256);
      for (let n = 0; n < 256; n += 1) {
        let value = n;
        for (let k = 0; k < 8; k += 1) value = (value & 1) ? (0xedb88320 ^ (value >>> 1)) : (value >>> 1);
        crc32.table[n] = value >>> 0;
      }
    }
    let crc = 0xffffffff;
    for (let index = 0; index < bytes.length; index += 1) crc = crc32.table[(crc ^ bytes[index]) & 0xff] ^ (crc >>> 8);
    return (crc ^ 0xffffffff) >>> 0;
  }

  function concatBytes(parts) {
    const length = parts.reduce((total, part) => total + part.length, 0);
    const output = new Uint8Array(length);
    let offset = 0;
    parts.forEach((part) => { output.set(part, offset); offset += part.length; });
    return output;
  }

  function buildZip(files) {
    const encoder = new TextEncoder();
    const now = new Date();
    const dosTime = (now.getHours() << 11) | (now.getMinutes() << 5) | Math.floor(now.getSeconds() / 2);
    const dosDate = ((Math.max(1980, now.getFullYear()) - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
    const localParts = [];
    const centralParts = [];
    let offset = 0;

    files.forEach(({ name, contents }) => {
      const filename = encoder.encode(name);
      const data = encoder.encode(contents);
      const crc = crc32(data);
      const local = new Uint8Array(30 + filename.length);
      const lv = new DataView(local.buffer);
      lv.setUint32(0, 0x04034b50, true);
      lv.setUint16(4, 20, true);
      lv.setUint16(6, 0x0800, true);
      lv.setUint16(8, 0, true);
      lv.setUint16(10, dosTime, true);
      lv.setUint16(12, dosDate, true);
      lv.setUint32(14, crc, true);
      lv.setUint32(18, data.length, true);
      lv.setUint32(22, data.length, true);
      lv.setUint16(26, filename.length, true);
      lv.setUint16(28, 0, true);
      local.set(filename, 30);
      localParts.push(local, data);

      const central = new Uint8Array(46 + filename.length);
      const cv = new DataView(central.buffer);
      cv.setUint32(0, 0x02014b50, true);
      cv.setUint16(4, 20, true);
      cv.setUint16(6, 20, true);
      cv.setUint16(8, 0x0800, true);
      cv.setUint16(10, 0, true);
      cv.setUint16(12, dosTime, true);
      cv.setUint16(14, dosDate, true);
      cv.setUint32(16, crc, true);
      cv.setUint32(20, data.length, true);
      cv.setUint32(24, data.length, true);
      cv.setUint16(28, filename.length, true);
      cv.setUint16(30, 0, true);
      cv.setUint16(32, 0, true);
      cv.setUint16(34, 0, true);
      cv.setUint16(36, 0, true);
      cv.setUint32(38, 0, true);
      cv.setUint32(42, offset, true);
      central.set(filename, 46);
      centralParts.push(central);
      offset += local.length + data.length;
    });

    const centralDirectory = concatBytes(centralParts);
    const localRecords = concatBytes(localParts);
    const end = new Uint8Array(22);
    const ev = new DataView(end.buffer);
    ev.setUint32(0, 0x06054b50, true);
    ev.setUint16(4, 0, true);
    ev.setUint16(6, 0, true);
    ev.setUint16(8, files.length, true);
    ev.setUint16(10, files.length, true);
    ev.setUint32(12, centralDirectory.length, true);
    ev.setUint32(16, localRecords.length, true);
    ev.setUint16(20, 0, true);
    return concatBytes([localRecords, centralDirectory, end]);
  }

  function safeBaseName(name) {
    const base = String(name || 'Windows')
      .replace(/\.iso$/i, '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-zA-Z0-9_-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 48);
    return base || 'Windows';
  }

  function downloadKit() {
    if (!state.image) {
      showToast('Sélectionnez d’abord un fichier ISO .iso. Le contenu reste sur votre appareil.', 'warning', 5500);
      $('#source').scrollIntoView({ behavior: 'smooth', block: 'center' });
      elements.dropzone.focus({ preventScroll: true });
      return;
    }
    const profile = collectProfile();
    const files = [
      { name: 'README-NovaOS.txt', contents: createReadme(profile) },
      { name: 'NovaOS-profile.json', contents: `${JSON.stringify(profile, null, 2)}\n` },
      { name: 'Apply-NovaOS.ps1', contents: createPowerShell(profile) },
      { name: 'autounattend.xml', contents: createAnswerFile() }
    ];
    const zip = buildZip(files);
    const blob = new Blob([zip], { type: 'application/zip' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    const base = safeBaseName(state.image.name);
    link.href = url;
    link.download = `NovaOS-kit-${base}.zip`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 20_000);

    const record = {
      name: `NovaOS-kit-${base}.zip`,
      createdAt: new Date().toLocaleString('fr-FR', { dateStyle: 'medium', timeStyle: 'short' }),
      count: Object.values(profile.options).filter(Boolean).length
    };
    state.history.unshift(record);
    state.history = state.history.slice(0, 5);
    renderHistory();
    showToast('Kit ZIP exporté. Il ne contient pas l’image ISO.', 'success', 5500);
  }

  function renderHistory() {
    if (!state.history.length) {
      elements.historyList.innerHTML = `<div class="history-empty"><span class="history-empty-icon">${useIcon('i-clock')}</span><div><strong>Pas encore d’export</strong><span>Votre premier kit apparaîtra ici.</span></div></div>`;
      return;
    }
    elements.historyList.innerHTML = state.history.map((record) => `<div class="history-entry"><span class="history-empty-icon">${useIcon('i-file')}</span><span class="history-entry-copy"><strong>${escapeHtml(record.name)}</strong><small>${escapeHtml(record.createdAt)} · ${record.count} options activées</small></span><span class="history-entry-badge">ZIP</span></div>`).join('');
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
  }

  function resetProject() {
    state.image = null;
    state.profile = 'nova';
    state.activeTab = 'system';
    state.options = cloneOptions(DEFAULTS);
    state.language = 'fr-FR';
    state.theme = 'dark';
    state.accent = 'mint';
    elements.isoInput.value = '';
    $('#languageSelect').value = state.language;
    $$('.profile-card').forEach((card) => {
      const selected = card.dataset.profile === state.profile;
      card.classList.toggle('is-selected', selected);
      card.setAttribute('aria-pressed', String(selected));
    });
    updateTheme();
    updateAccent();
    renderImage();
    renderSettings();
    updateDerived();
    window.scrollTo({ top: 0, behavior: 'smooth' });
    showToast('Nouvelle configuration prête. Vos réglages par défaut ont été restaurés.');
  }

  function openModal() {
    elements.modalBackdrop.hidden = false;
    $('#modalDone').focus();
  }

  function closeModal() {
    elements.modalBackdrop.hidden = true;
    $('#helpButton').focus();
  }

  function initNavigation() {
    $$('.nav-item[data-target]').forEach((button) => {
      button.addEventListener('click', () => {
        const target = button.dataset.target;
        if (button.dataset.tab) chooseTab(button.dataset.tab);
        setActiveNavigation(target, button.dataset.tab || '');
        const targetElement = document.getElementById(target);
        if (targetElement) targetElement.scrollIntoView({ behavior: 'smooth', block: target === 'overview' ? 'start' : 'center' });
        $('#sidebar').classList.remove('is-open');
      });
    });
    $$('[data-scroll-to]').forEach((button) => {
      button.addEventListener('click', () => {
        const target = document.getElementById(button.dataset.scrollTo);
        if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' });
      });
    });
    const sections = ['overview', 'source', 'customize', 'installer', 'builds'].map((id) => document.getElementById(id)).filter(Boolean);
    if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver((entries) => {
        const visible = entries.filter((entry) => entry.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (!visible) return;
        const sectionId = visible.target.id;
        const tabName = sectionId === 'customize' ? state.activeTab : '';
        setActiveNavigation(sectionId, tabName);
      }, { rootMargin: '-18% 0px -66% 0px', threshold: [0, .1, .35, .6] });
      sections.forEach((section) => observer.observe(section));
    }
  }

  function initFileInput() {
    elements.isoInput.addEventListener('change', (event) => setImage(event.target.files && event.target.files[0]));
    $('#browseButton').addEventListener('click', (event) => {
      event.stopPropagation();
      elements.isoInput.click();
    });
    $('#removeFileButton').addEventListener('click', (event) => {
      event.stopPropagation();
      state.image = null;
      renderImage();
      updateDerived();
      showToast('Image source retirée.');
    });
    elements.dropzone.addEventListener('click', (event) => {
      if (event.target.closest('#removeFileButton')) return;
      if (event.target.closest('#browseButton')) return;
      elements.isoInput.click();
    });
    elements.dropzone.addEventListener('keydown', (event) => {
      if (event.target !== elements.dropzone) return;
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        elements.isoInput.click();
      }
    });
    ['dragenter', 'dragover'].forEach((name) => elements.dropzone.addEventListener(name, (event) => {
      event.preventDefault();
      elements.dropzone.classList.add('is-dragging');
    }));
    ['dragleave', 'drop'].forEach((name) => elements.dropzone.addEventListener(name, (event) => {
      event.preventDefault();
      elements.dropzone.classList.remove('is-dragging');
    }));
    elements.dropzone.addEventListener('drop', (event) => {
      const file = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0];
      if (file) setImage(file);
    });
  }

  function initControls() {
    $$('.profile-card').forEach((card) => card.addEventListener('click', () => setActiveProfile(card.dataset.profile)));
    $$('.settings-tab').forEach((tab) => tab.addEventListener('click', () => chooseTab(tab.dataset.tab)));
    elements.settingsList.addEventListener('click', (event) => {
      const toggle = event.target.closest('[data-option]');
      if (!toggle) return;
      const id = toggle.dataset.option;
      state.options[id] = !state.options[id];
      state.profile = 'custom';
      $$('.profile-card').forEach((card) => {
        const selected = card.dataset.profile === 'custom';
        card.classList.toggle('is-selected', selected);
        card.setAttribute('aria-pressed', String(selected));
      });
      renderSettings();
      updateDerived();
    });

    $('#languageSelect').addEventListener('change', (event) => {
      state.language = LANGUAGE_MAP[event.target.value] ? event.target.value : 'fr-FR';
      updateDerived();
    });
    $$('.theme-option').forEach((button) => button.addEventListener('click', () => {
      state.theme = button.dataset.theme;
      updateTheme();
      updateDerived();
    }));
    $$('.accent-swatch').forEach((button) => button.addEventListener('click', () => {
      state.accent = button.dataset.accent;
      updateAccent();
      updateDerived();
    }));

    elements.exportButton.addEventListener('click', downloadKit);
    $('#resetButton').addEventListener('click', resetProject);
    $('#newProjectButton').addEventListener('click', resetProject);
    $('#clearHistoryButton').addEventListener('click', () => {
      state.history = [];
      renderHistory();
      showToast('Historique local effacé.');
    });
    $('#helpButton').addEventListener('click', openModal);
    $('#kitDetailsButton').addEventListener('click', openModal);
    $('#modalClose').addEventListener('click', closeModal);
    $('#modalDone').addEventListener('click', closeModal);
    elements.modalBackdrop.addEventListener('click', (event) => {
      if (event.target === elements.modalBackdrop) closeModal();
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && !elements.modalBackdrop.hidden) closeModal();
    });
    $('#menuButton').addEventListener('click', () => $('#sidebar').classList.toggle('is-open'));
    document.addEventListener('click', (event) => {
      const sidebar = $('#sidebar');
      if (sidebar.classList.contains('is-open') && !sidebar.contains(event.target) && !$('#menuButton').contains(event.target)) sidebar.classList.remove('is-open');
    });
  }

  function init() {
    $('#languageSelect').value = state.language;
    renderImage();
    updateTheme();
    updateAccent();
    renderSettings();
    renderHistory();
    updateDerived();
    initNavigation();
    initFileInput();
    initControls();
  }

  init();
})();
