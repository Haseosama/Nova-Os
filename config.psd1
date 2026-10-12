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
        'Microsoft.XboxGameOverlay'
        'Microsoft.XboxGamingOverlay'
        'Microsoft.XboxSpeechToTextOverlay'
        'Microsoft.YourPhone'                # Mobile connecte
        'Microsoft.ZuneMusic'                # Lecteur multimedia
        'Microsoft.ZuneVideo'                # Films et TV
        'MicrosoftCorporationII.MicrosoftFamily'
        'MicrosoftCorporationII.QuickAssist'
        'MicrosoftTeams'
        'MicrosoftWindows.Client.WebExperience'   # Widgets
        'MicrosoftWindows.CrossDevice'
        'MSTeams'
    )
    # Conserves volontairement : Store, Calculatrice, Photos, Bloc-notes, Terminal, Paint, Capture d'ecran,
    # Camera, et la connexion Xbox (XboxIdentityProvider, Xbox.TCUI) dont certains jeux PC ont besoin.

    # Cle d'installation generique publique de Microsoft (Windows 11 Pro) : elle evite l'ecran
    # "cle de produit" pendant l'installation mais N'ACTIVE PAS Windows. Mets '' pour la retirer,
    # ou la cle generique de ton edition si tu gardes une autre edition que Pro.
    InstallKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'

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

    # Active le mode d'alimentation "Performances optimales" au premier demarrage.
    # Sur un PC portable, cela reduit l'autonomie.
    UltimatePerformance    = $true

    # Desactive l'integrite de la memoire (VBS/HVCI) : quelques % de FPS en plus,
    # mais moins de protection contre les logiciels malveillants. Desactive par defaut.
    DisableVBS             = $false
}
