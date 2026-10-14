# Nova-Os

Nova-Os est une version allégée de Windows 11, avec un thème futuriste et des réglages pour le jeu, construite à partir de ton propre ISO officiel.
Le dépôt ne contient pas l'ISO lui-même, mais le script qui le fabrique : tu lances le script
sur ton PC Windows, il applique les modifications et produit `out\Nova-Os.iso`.

![Fond d'écran Nova-Os](assets/wallpaper.jpg)

## Pourquoi pas directement l'ISO sur GitHub ?

- GitHub refuse les fichiers de plus de 100 Mo dans un dépôt, et 2 Go par fichier dans une Release.
  Un ISO de Windows 11 fait 5 à 7 Go.
- Windows appartient à Microsoft : publier un ISO modifié en téléchargement public enfreint sa licence.
  Le script, lui, peut être partagé sans problème : chacun l'applique à son propre ISO.

## Ce que fait le script

Tout est réglable dans [`config.psd1`](config.psd1) (mets `$false` pour désactiver une option).

| Option | Par défaut | Effet |
|---|---|---|
| `RemoveApps` | liste fournie | Supprime Clipchamp, Bing Actu/Météo, Xbox, Teams, Outlook, Solitaire, Mobile connecté, Cortana, Copilot… Le Store, la Calculatrice, Photos, le Bloc-notes, le Terminal et Paint sont gardés. |
| `BypassHardwareChecks` | oui | S'installe sans TPM 2.0, sans Secure Boot, avec moins de 4 Go de RAM ou un CPU non supporté. |
| `AllowLocalAccount` | oui | Permet de créer un compte local, sans compte Microsoft ni connexion Internet. |
| `DisableTelemetry` | oui | Coupe la télémétrie, l'identifiant publicitaire et les services de collecte. |
| `DisableConsumerFeatures` | oui | Empêche l'installation automatique d'applis « suggérées ». |
| `DisableCopilot` | oui | Désactive Copilot. |
| `DisableReservedStorage` | oui | Libère environ 7 Go réservés aux mises à jour. |
| `RemoveOneDrive` | oui | OneDrive ne s'installe plus à la première connexion. |
| `Theme` | oui | Mode sombre, transparence, accent cyan néon (`AccentColor`), fond d'écran Nova-Os sur le bureau et l'écran de verrouillage, « Windows à la une » désactivé. |
| `Theme.SetupBackground` | `assets/setup.jpg` | Fond néon « NOVA OS » dans le programme d'installation et sur l'écran de chargement qui le précède. |
| `Theme.LegacySetup` | oui | Lance l'ancien programme d'installation : le nouveau (depuis 24H2) ignore les fonds personnalisés. |
| `Theme.GlassEffects` | oui | Style « liquid glass » natif : barre des tâches plus transparente. Aucune appli tierce. |
| `Branding` | oui | Logo et nom Nova OS dans Paramètres > Système > Informations, nom du PC `NOVA-PC`, logo Nova comme image de compte par défaut. |
| `GamingTweaks` | oui | Mode Jeu actif, enregistrement Game DVR coupé, planification GPU matérielle, priorité CPU/GPU aux jeux, souris sans accélération. |
| `UltimatePerformance` | oui | Active le mode d'alimentation « Performances optimales » (moins d'autonomie sur portable). |
| `DisableVBS` | non | Coupe l'intégrité de la mémoire : quelques FPS en plus, mais moins de protection. À activer en connaissance de cause. |

### Comment c'est appliqué

L'image Windows (`install.wim`) n'est pas modifiée et aucune application tierce n'est installée.
Le script ajoute à l'ISO un dossier `sources\$OEM$\$$\NovaOS`, que l'installation de Windows copie
elle-même dans `C:\Windows\NovaOS`, et un `autounattend.xml` qui lance `Specialize.ps1` pendant
l'installation, avant la création du compte. Ce script supprime les applis, écrit le registre (machine
et profil par défaut) et installe les images de compte. Tout est noté dans `C:\Windows\NovaOS\Specialize.log`.

### Ce qui reste aux couleurs de Windows

Le logo Windows au démarrage (au-dessus des points qui tournent) est dans `bootres.dll`, un fichier signé
vérifié par le Secure Boot : le modifier empêcherait le PC de démarrer. Les logos « Windows » dans les
fenêtres de l'installeur et le bouton Démarrer sont aussi dans des fichiers signés par Microsoft ; le script
n'y touche pas.

## Prérequis

- Un PC sous Windows 10 ou 11, avec environ 20 Go d'espace libre.
- Un ISO officiel de Windows 11 ([téléchargement Microsoft](https://www.microsoft.com/fr-fr/software-download/windows11)).
- Le [Windows ADK](https://learn.microsoft.com/fr-fr/windows-hardware/get-started/adk-install),
  composant « Outils de déploiement » uniquement (il fournit `oscdimg.exe`).

## Utilisation

Ouvre PowerShell **en administrateur** dans le dossier du dépôt, puis :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Build-NovaOS.ps1 -IsoPath "C:\Chemin\vers\Win11.iso"
```

L'édition installée est choisie par la clé générique `InstallKey` (Pro par défaut).

À la fin, l'ISO se trouve dans `out\Nova-Os.iso`. Tu peux le copier sur une clé USB avec
[Rufus](https://rufus.ie) ou le tester dans une machine virtuelle.

Options utiles :

- `-SourceDir D:\Win11` à la place de `-IsoPath` : partir d'un ISO déjà décompressé (le dossier n'est pas modifié).
- `-OutputIso D:\Nova-Os.iso` : choisir où écrire l'ISO.
- `-WorkDir D:\nova-work` : dossier de travail sur un autre disque.
- `-OscdimgPath C:\outils\oscdimg.exe` : si l'ADK est installé ailleurs.
- `-ConfigPath .\ma-config.psd1` : utiliser une autre configuration.

## Décompresser Windows pour le modifier à la main

Pour explorer et modifier Windows fichier par fichier, comme un dossier de code source, sur ton PC uniquement :

```powershell
.\Export-NovaSource.ps1 -IsoPath "C:\Chemin\vers\Win11.iso" -Destination D:\NovaOS\source
```

Le dossier contient `media\` (l'ISO), `winpe\` et `setup\` (boot.wim), `windows\` (install.wim, le futur `C:\`)
et un `README.md` qui indique où trouver les fonds, thèmes, images de compte et registres. Prévois environ 40 Go.
Pour refaire l'ISO après tes modifications :

```powershell
.\Build-FromSource.ps1 -Source D:\NovaOS\source -OutputIso D:\NovaOS\Nova-Os-source.iso -NovaOS
```

`-NovaOS` applique en plus les réglages de `config.psd1`.

## Fichiers

- `Build-NovaOS.ps1` : le script de construction.
- `Export-NovaSource.ps1` et `Build-FromSource.ps1` : décompresser Windows dans un dossier modifiable, puis refaire l'ISO.
- `config.psd1` : la liste des modifications.
- `assets/wallpaper.jpg` : le fond d'écran futuriste (3840×2160).
- `assets/setup.jpg` : le fond du programme d'installation.
- `assets/logo.png` : le logo Nova OS.
