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

    # Nettoie le magasin de composants (image plus petite, mais les mises a jour deja integrees
    # ne pourront plus etre desinstallees). Ajoute plusieurs minutes au build.
    CleanupComponentStore  = $true
}
