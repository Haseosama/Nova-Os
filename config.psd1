# Configuration de Nova-Os.
# Mets une option a $false pour la desactiver. Ce fichier est lu par Build-NovaOS.ps1.
@{
    # Applications preinstallees a supprimer de l'image (correspondance partielle sur le nom du paquet).
    # Retire une ligne pour garder l'application correspondante.
    RemoveApps = @(
        '7EE7776C.LinkedInforWindows'        # LinkedIn
        'Clipchamp.Clipchamp'
        'Microsoft.549981C3F5F10'            # Cortana
        'Microsoft.BingFinance'
        'Microsoft.BingNews'
        'Microsoft.BingSearch'
        'Microsoft.BingSports'
        'Microsoft.BingTranslator'
        'Microsoft.BingWeather'
        'Microsoft.Copilot'
        'Microsoft.Edge.GameAssist'
        'Microsoft.GamingApp'
        'Microsoft.GetHelp'
        'Microsoft.Getstarted'               # Astuces
        'Microsoft.Messaging'
        'Microsoft.Microsoft3DViewer'
        'Microsoft.MicrosoftJournal'
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.MicrosoftSolitaireCollection'
        'Microsoft.MicrosoftStickyNotes'     # Pense-betes
        'Microsoft.MixedReality.Portal'
        'Microsoft.MSPaint'                  # Paint 3D (Paint classique garde)
        'Microsoft.Office.OneNote'
        'Microsoft.OneConnect'
        'Microsoft.OutlookForWindows'
        'Microsoft.People'
        'Microsoft.PowerAutomateDesktop'
        'Microsoft.Print3D'
        'Microsoft.SkypeApp'
        'Microsoft.Todos'
        'Microsoft.Wallet'
        'Microsoft.Windows.Ai.Copilot.Provider'
        'Microsoft.Windows.DevHome'
        'Microsoft.WindowsAlarms'            # Horloge
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.WindowsMaps'
        'Microsoft.WindowsSoundRecorder'
        'Microsoft.Xbox.TCUI'
        'Microsoft.XboxGameOverlay'
        'Microsoft.XboxGamingOverlay'
        'Microsoft.XboxSpeechToTextOverlay'
        'Microsoft.XboxIdentityProvider'
        'Microsoft.YourPhone'                # Mobile connecte
        'Microsoft.ZuneMusic'                # Lecteur multimedia
        'Microsoft.ZuneVideo'                # Films et TV
        'MicrosoftCorporationII.MicrosoftFamily'
        'MicrosoftCorporationII.QuickAssist'
        'MicrosoftTeams'
        'MicrosoftWindows.Client.WebExperience'   # Widgets
        'MicrosoftWindows.CrossDevice'
        'MSTeams'
        # Applis "suggerees" que le Store installe a la premiere connexion.
        '5319275A.WhatsAppDesktop'
        'AmazonVideo.PrimeVideo'
        'BytedancePte.Ltd.TikTok'
        'Disney.37853FC22B2CE'               # Disney+
        'Facebook.Facebook'
        'Facebook.Instagram'
        'king.com.'                          # Candy Crush...
        '4DF9E0F8.Netflix'
        'Microsoft.MicrosoftPCManager'
        'SpotifyAB.SpotifyMusic'
        # Ajouts : Courrier et Calendrier, Sway, publicites des applis, page d'accueil du menu Demarrer.
        'microsoft.windowscommunicationsapps'
        'Microsoft.Office.Sway'
        'Microsoft.Advertising.Xaml'
        'Microsoft.StartExperiencesApp'
        'Microsoft.WindowsTerminal.Preview'
    )

    # Composants Windows desactives pendant l'installation : Recall, Dossiers de travail,
    # imprimante XPS, ancien PowerShell 2.0 (faille de securite connue).
    RemoveFeatures = @('Recall', 'WorkFolders-Client', 'Printing-XPSServices-Features',
                       'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2')

    # Fonctionnalites facultatives supprimees : Enregistreur d'actions, reconnaissance d'ecriture
    # mathematique, ancien Lecteur Windows Media, WordPad, Internet Explorer, Assistance rapide,
    # reconnaissance faciale Windows Hello (retire cette ligne si ton PC a une camera Hello).
    RemoveCapabilities = @('App.StepsRecorder', 'MathRecognizer', 'Media.WindowsMediaPlayer',
                           'Microsoft.Windows.WordPad', 'Browser.InternetExplorer',
                           'App.Support.QuickAssist', 'Hello.Face')
    # Conserves volontairement : Store, Calculatrice, Photos, Bloc-notes, Terminal, Paint, Capture d'ecran,
    # Camera. Xbox retire entierement a la demande (2026-10-14).

    # Cle d'installation generique publique de Microsoft (Windows 11 Pro) : elle evite l'ecran
    # "cle de produit" pendant l'installation mais N'ACTIVE PAS Windows. Mets '' pour la retirer,
    # ou la cle generique de ton edition si tu gardes une autre edition que Pro.
    InstallKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'
    # Ta propre cle (une ligne XXXXX-XXXXX-XXXXX-XXXXX-XXXXX) : si ce fichier existe, elle remplace
    # la cle generique et active Windows a l'installation. Le fichier reste sur ton PC, hors du depot.
    InstallKeyFile = 'D:\NovaOS\installers\productkey.txt'

    # Installation sur PC sans TPM 2.0 / Secure Boot / 4 Go de RAM / CPU supporte.
    BypassHardwareChecks   = $true

    # Permet de creer un compte local pendant l'installation (sans compte Microsoft ni Internet).
    AllowLocalAccount      = $true

    # Coupe la telemetrie, l'ID publicitaire et les services de collecte.
    DisableTelemetry       = $true

    # Empeche Windows d'installer tout seul des applis "suggerees" (Candy Crush, TikTok...).
    DisableConsumerFeatures = $true

    # Desactive Copilot par strategie.
    DisableCopilot         = $true

    # Libere les ~7 Go de "stockage reserve" pour les mises a jour.
    DisableReservedStorage = $true

    # OneDrive ne s'installe plus a la premiere connexion.
    RemoveOneDrive         = $true

    # --- Theme futuriste --------------------------------------------------
    # Mode sombre, couleur d'accent neon, transparence et fond d'ecran Nova-Os
    # (ecran de bureau et ecran de verrouillage).
    Theme = @{
        Enabled     = $true
        AccentColor = '#00D4FF'                  # cyan neon ; essaie '#FF2BD6' pour du rose
        Wallpaper   = 'assets\wallpaper.jpg'    # remplace par ton image (JPG) si tu veux

        # Fond d'ecran du programme d'installation de Windows (avec le titre NOVA OS).
        SetupBackground = 'assets\setup.jpg'

        # Style "liquid glass" : barre des taches plus transparente et effets de verre natifs.
        # Aucune application tierce n'est installee.
        GlassEffects = $true

        # Lance l'ancien programme d'installation, le seul qui affiche le fond Nova-Os
        # (le nouveau, depuis 24H2, garde son fond violet).
        LegacySetup = $true

        # Barre des taches arrondie et retrecie avec RoundedTB (seule appli tierce, open source,
        # tres legere). Ajoutee a l'ISO avec les autres applis, sans Internet. $false pour la retirer.
        RoundedTaskbar = $true
    }

    # --- Navigateur ---------------------------------------------------------
    # Brave installe (pour tous les comptes), navigateur par defaut et epingle dans la barre des
    # taches. Edge est desinstalle et bloque ; WebView2, dont certaines applis ont besoin, reste.
    # Internet Explorer est retire avec RemoveCapabilities (Browser.InternetExplorer).
    Browser = @{
        Brave      = $true
        RemoveEdge = $true
    }

    # --- Applications ------------------------------------------------------
    # Telechargees avec winget pendant la construction de l'ISO, puis installees en silence
    # pendant l'installation de Windows (pas besoin d'Internet sur le PC installe).
    Apps = @{
        Enabled = $true
        Winget  = @(
            'CodecGuide.K-LiteCodecPack.Mega'   # K-Lite Mega Codec Pack
            'AppWork.JDownloader'               # JDownloader 2
            'MoritzBunkus.MKVToolNix'           # MKVToolNix
            'XMediaRecode.XMediaRecode'         # XMedia Recode
        )
        # Fichiers de reponses Inno Setup (/LOADINF) pour installer avec des choix precis.
        # K-Lite en mode complet (profil "Lots of stuff") : fichier cree avec l'option /unattended
        # de son installeur. Chemin relatif = dans le depot.
        LoadInf = @{
            'CodecGuide.K-LiteCodecPack.Mega' = 'assets\klcp_mega_unattended.ini'
        }
        # Tes propres installeurs (.exe Inno Setup / NSIS, ou .msi) : depose-les dans ce dossier.
        Folder  = 'D:\NovaOS\installers'
    }

    # --- Identite Nova-Os -------------------------------------------------
    # Logo et nom Nova-Os dans Parametres > Systeme > Informations, nom du PC,
    # logo Nova-Os comme image de compte par defaut.
    Branding = @{
        Enabled         = $true
        Logo            = 'assets\logo.png'
        Manufacturer    = 'Nova OS'
        Model           = 'Nova OS Gaming Edition'
        SupportURL      = 'https://github.com/Haseosama/Nova-Os'
        ComputerName    = 'NOVA-PC'          # 15 caracteres maximum
        AccountPictures = $true
    }

    # --- Optimisations jeux ----------------------------------------------
    # Mode Jeu actif, enregistrement Game DVR coupe, planification GPU materielle,
    # priorite CPU/GPU aux jeux, acceleration de la souris desactivee.
    GamingTweaks           = $true

    # Performances : applis en arriere-plan coupees, Edge ne reste plus en memoire, pas de partage
    # des mises a jour en P2P, services inutiles coupes (fax, demo magasin, cartes, registre a
    # distance), demarrage sans delai, plus d'astuces ni de suggestions.
    PerformanceTweaks      = $true
    # Coupe le service d'impression (mets $true si tu n'imprimes jamais, meme en PDF via une imprimante).
    DisablePrinting        = $false
    # Coupe le Bluetooth (mets $true si tu n'utilises ni manette, ni casque, ni souris Bluetooth).
    DisableBluetooth       = $false

    # Coupe la veille prolongee et le demarrage rapide : libere la taille de la RAM sur C:
    # (hiberfil.sys). A mettre a $false sur un PC portable qui s'en sert.
    DisableHibernation     = $true

    # Rend les ~7 Go que Windows reserve sur C: pour ses mises a jour (Windows Update reste actif ;
    # il faut juste un peu de place libre sur C: au moment des grosses mises a jour).
    DisableReservedStorage = $true

    # Nettoie le magasin de composants (WinSxS) a la fin de l'installation : 1 a 2 Go gagnes,
    # mais l'installation de Windows dure 5 a 10 minutes de plus.
    CleanupComponents      = $true

    # Active le mode d'alimentation "Performances optimales" au premier demarrage.
    # Sur un PC portable, cela reduit l'autonomie.
    UltimatePerformance    = $true

    # Desactive l'integrite de la memoire (VBS/HVCI) : quelques % de FPS en plus,
    # mais moins de protection contre les logiciels malveillants. Desactive par defaut.
    DisableVBS             = $true

    # Coupe l'indexation de recherche (service WSearch) : moins d'activite disque en fond, mais la
    # recherche de fichiers dans Demarrer et l'Explorateur devient plus lente.
    DisableSearchIndexing  = $true
}
