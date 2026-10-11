# Configuration de Nova-Os.
# Mets une option a $false pour la desactiver. Ce fichier est lu par Build-NovaOS.ps1.
@{
    # Applications preinstallees a supprimer de l'image (correspondance partielle sur le nom du paquet).
    # Retire une ligne pour garder l'application correspondante.
    RemoveApps = @(
        'Clipchamp.Clipchamp'
        'Microsoft.549981C3F5F10'            # Cortana
        'Microsoft.BingNews'
        'Microsoft.BingSearch'
        'Microsoft.BingWeather'
        'Microsoft.Copilot'
        'Microsoft.GamingApp'
        'Microsoft.GetHelp'
        'Microsoft.Getstarted'
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.MicrosoftSolitaireCollection'
        'Microsoft.OutlookForWindows'
        'Microsoft.People'
        'Microsoft.PowerAutomateDesktop'
        'Microsoft.Todos'
        'Microsoft.Windows.DevHome'
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.WindowsMaps'
        'Microsoft.WindowsSoundRecorder'
        'Microsoft.Xbox.TCUI'
        'Microsoft.XboxGameOverlay'
        'Microsoft.XboxGamingOverlay'
        'Microsoft.XboxSpeechToTextOverlay'
        'Microsoft.YourPhone'
        'Microsoft.ZuneMusic'
        'Microsoft.ZuneVideo'
        'MicrosoftCorporationII.QuickAssist'
        'MicrosoftTeams'
        'MSTeams'
    )
    # Conserves volontairement : Store, Calculatrice, Photos, Bloc-notes, Terminal, Paint, Capture d'ecran.

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

    # Supprime l'installateur OneDrive (OneDrive ne s'installe plus a la premiere connexion).
    RemoveOneDrive         = $true

    # Supprime Microsoft Edge. Desactive par defaut : certaines applis (WebView2) en dependent.
    RemoveEdge             = $false

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
        GlassEffects = $true

        # Applis installees avec winget a la premiere connexion (Internet requis) pour pousser
        # l'effet verre : TranslucentTB (barre des taches en verre) et Mica For Everyone
        # (fond flou acrylique sur les fenetres). Vide la liste pour ne rien installer.
        GlassApps = @(
            'CharlesMilette.TranslucentTB'
            'MicaForEveryone.MicaForEveryone'
        )
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

    # Nettoie le magasin de composants (image plus petite, mais les mises a jour deja integrees
    # ne pourront plus etre desinstallees). Ajoute plusieurs minutes au build.
    CleanupComponentStore  = $true
}
