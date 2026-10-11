# NovaOS Studio

Interface sombre de préparation d’un kit de personnalisation Windows, avec un script local pour Windows 11 Professionnel (index 6).

## Lancer l’interface

Aucune dépendance ni compilation n’est nécessaire. Depuis ce dossier :

```bash
python3 -m http.server 4173 --bind 0.0.0.0
```

Puis ouvrez `http://localhost:4173` (ou le lien de prévisualisation fourni par l’environnement).

## Construire l’ISO localement (Windows 11 Pro, index 6)

Le fichier `scripts/Build-NovaOS-Pro.ps1` est destiné à être lancé sur le PC Windows où l’ISO est monté. L’ISO n’a pas besoin d’être téléversé.

Prérequis :

- Windows 10/11 x64 et **Windows PowerShell 5.1** lancé en tant qu’administrateur ;
- Windows ADK avec **Deployment Tools** (`oscdimg.exe`) et l’extension Windows PE, incluant `WinPE-HTA.cab` ; idéalement une version correspondant au média ;
- au moins 30 Go d’espace libre dans le dossier de travail ;
- une sauvegarde et une machine virtuelle pour tester l’ISO avant toute installation réelle.

Monte l’ISO dans l’Explorateur Windows (dans cet exemple, il apparaît sur `F:`), place-toi dans le dossier qui contient le script et lance :

```powershell
.\Build-NovaOS-Pro.ps1 -SourceMedia 'F:\' -OutputIso "$env:USERPROFILE\Desktop\NovaOS-Windows11-Pro.iso"
```

Le script demande de saisir `BUILD` avant de continuer. Il copie le média vers un espace de travail séparé, laisse la source intacte, exporte uniquement l’index 6, retire une sélection limitée d’applications grand public, applique quelques stratégies de confidentialité et le thème sombre par défaut, ajoute un écran d’accueil NovaOS sombre dans WinPE, puis reconstruit une image ISO amorçable BIOS/UEFI. Le dossier de travail et les journaux sont conservés pour diagnostic.

L’écran NovaOS personnalisé est un **lanceur avant l’installation**. Après le clic, c’est le programme Windows Setup de Microsoft qui gère les étapes d’installation. Le script ne formate aucun disque, ne crée aucun compte, ne contourne pas l’activation ni les exigences matérielles. Windows peut encore transmettre des diagnostics requis ; le script fixe le niveau minimal généralement pris en charge par Windows 11 Pro, sans promettre « zéro télémétrie ». Une licence Pro valide reste nécessaire pour l’activation.

**Le script n’a pas pu être exécuté ou testé sur Windows dans l’environnement de développement Linux.** Relis-le avant usage, vérifie que l’ADK correspond à ton média, puis teste l’ISO dans une VM (UEFI et, si besoin, BIOS) avant de l’utiliser sur une machine réelle. Si le composant WinPE ou une étape DISM échoue, le script s’arrête et laisse le dossier de travail et son journal ; le média source n’est pas modifié.

## Kit exporté depuis l’interface

L’interface permet aussi de sélectionner une image et d’exporter un ZIP de configuration : profil JSON, script PowerShell de préférences, fichier de réponse langue/clavier et guide. Ce ZIP est distinct du résultat ISO produit par le script local.
