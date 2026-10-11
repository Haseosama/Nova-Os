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
| `RemoveEdge` | non | Supprime Edge. Désactivé par défaut car certaines applis dépendent de WebView2. |
| `Theme` | oui | Mode sombre, transparence, accent cyan néon (`AccentColor`), fond d'écran Nova-Os sur le bureau et l'écran de verrouillage. Mets ta propre image dans `Wallpaper` si tu veux. |
| `GamingTweaks` | oui | Mode Jeu actif, enregistrement Game DVR coupé, planification GPU matérielle, priorité CPU/GPU aux jeux, souris sans accélération. |
| `UltimatePerformance` | oui | Active le mode d'alimentation « Performances optimales » au premier démarrage (moins d'autonomie sur portable). |
| `DisableVBS` | non | Coupe l'intégrité de la mémoire : quelques FPS en plus, mais moins de protection. À activer en connaissance de cause. |
| `CleanupComponentStore` | oui | Réduit la taille de l'image (les mises à jour intégrées ne seront plus désinstallables). |

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

Le script affiche les éditions présentes (Famille, Pro…) et te demande laquelle garder.
Pour éviter la question : `-ImageIndex 6` (par exemple pour Pro).

À la fin, l'ISO se trouve dans `out\Nova-Os.iso`. Tu peux le copier sur une clé USB avec
[Rufus](https://rufus.ie) ou le tester dans une machine virtuelle.

Options utiles :

- `-OutputIso D:\Nova-Os.iso` : choisir où écrire l'ISO.
- `-WorkDir D:\nova-work` : dossier de travail sur un autre disque.
- `-OscdimgPath C:\outils\oscdimg.exe` : si l'ADK est installé ailleurs.
- `-ConfigPath .\ma-config.psd1` : utiliser une autre configuration.

## Fichiers

- `Build-NovaOS.ps1` : le script de construction.
- `config.psd1` : la liste des modifications.
- `assets/wallpaper.jpg` : le fond d'écran futuriste (3840×2160).

Le script ajoute aussi dans l'ISO un `autounattend.xml` (compte local et thème par défaut) et,
si `UltimatePerformance` est actif, un `SetupComplete.cmd` qui règle l'alimentation après l'installation.
