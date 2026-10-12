# Lecture et ecriture de la fiche d'une image WIM (edition, langue, nom...) avec wimgapi.dll,
# l'API de Windows pour les fichiers WIM. Utilise par Export-NovaSource.ps1 et Build-FromSource.ps1.
#
# Sur certains PC, DISM ne peut pas lire le registre de l'image qu'il capture : install.wim perd
# alors son edition et le programme d'installation ne propose plus aucune image. On recopie donc
# la fiche de l'image Microsoft d'origine dans l'image capturee.

Add-Type -Namespace NovaOS -Name Wim -MemberDefinition @'
[DllImport("wimgapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr WIMCreateFile(string path, uint access, uint disposition, uint flags, uint compression, out uint result);
[DllImport("wimgapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool WIMSetTemporaryPath(IntPtr wim, string path);
[DllImport("wimgapi.dll", SetLastError = true)]
public static extern IntPtr WIMLoadImage(IntPtr wim, uint index);
[DllImport("wimgapi.dll", SetLastError = true)]
public static extern bool WIMGetImageInformation(IntPtr handle, out IntPtr info, out uint size);
[DllImport("wimgapi.dll", SetLastError = true)]
public static extern bool WIMSetImageInformation(IntPtr image, IntPtr info, uint size);
[DllImport("wimgapi.dll", SetLastError = true)]
public static extern bool WIMCloseHandle(IntPtr handle);
[DllImport("kernel32.dll")]
public static extern IntPtr LocalFree(IntPtr mem);
'@ -ErrorAction SilentlyContinue

function Invoke-WimImage([string] $Path, [int] $Index, [bool] $Write, [scriptblock] $Action) {
    $access = if ($Write) { [uint32]0xC0000000 } else { [uint32]0x80000000 }   # lecture (+ ecriture)
    $created = [uint32]0
    $wim = [NovaOS.Wim]::WIMCreateFile($Path, $access, 3, 0, 0, [ref]$created)   # 3 = ouvrir l'existant
    if ($wim -eq [IntPtr]::Zero) { throw "Impossible d'ouvrir $Path (erreur $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." }
    try {
        [NovaOS.Wim]::WIMSetTemporaryPath($wim, $env:TEMP) | Out-Null
        $image = [NovaOS.Wim]::WIMLoadImage($wim, $Index)
        if ($image -eq [IntPtr]::Zero) { throw "Image $Index introuvable dans $Path (erreur $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." }
        try { & $Action $image }
        finally { [NovaOS.Wim]::WIMCloseHandle($image) | Out-Null }
    }
    finally { [NovaOS.Wim]::WIMCloseHandle($wim) | Out-Null }
}

# Fiche XML de l'image $Index de $Path.
function Get-WimImageXml([string] $Path, [int] $Index) {
    $script:wimXml = $null
    Invoke-WimImage $Path $Index $false {
        param($image)
        $info = [IntPtr]::Zero; $size = [uint32]0
        if (-not [NovaOS.Wim]::WIMGetImageInformation($image, [ref]$info, [ref]$size)) {
            throw "Lecture de la fiche impossible (erreur $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
        }
        try { $script:wimXml = [Runtime.InteropServices.Marshal]::PtrToStringUni($info, [int]($size / 2)).TrimStart([char]0xFEFF) }
        finally { [NovaOS.Wim]::LocalFree($info) | Out-Null }
    }
    $script:wimXml
}

# Remplace l'identite de l'image $Index de $Path (WINDOWS, NAME, FLAGS...) par celle de $OriginalXml,
# en gardant les tailles et dates de la nouvelle capture.
function Restore-WimImageIdentity([string] $Path, [int] $Index, [string] $OriginalXml) {
    $current = [xml](Get-WimImageXml $Path $Index)
    $original = [xml]$OriginalXml
    foreach ($name in 'WINDOWS', 'NAME', 'DESCRIPTION', 'FLAGS', 'DISPLAYNAME', 'DISPLAYDESCRIPTION') {
        $source = $original.IMAGE.SelectSingleNode($name)
        if (-not $source) { continue }
        $existing = $current.IMAGE.SelectSingleNode($name)
        $copy = $current.ImportNode($source, $true)
        if ($existing) { $current.IMAGE.ReplaceChild($copy, $existing) | Out-Null } else { $current.IMAGE.AppendChild($copy) | Out-Null }
    }
    $text = [char]0xFEFF + $current.OuterXml
    $bytes = [Text.Encoding]::Unicode.GetBytes($text)
    $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
    try {
        [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $buffer, $bytes.Length)
        Invoke-WimImage $Path $Index $true {
            param($image)
            if (-not [NovaOS.Wim]::WIMSetImageInformation($image, $buffer, [uint32]$bytes.Length)) {
                throw "Ecriture de la fiche impossible (erreur $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
            }
        }
    }
    finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
}
