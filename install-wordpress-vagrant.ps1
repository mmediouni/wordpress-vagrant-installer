# ============================================================
#  install-wordpress-vagrant.ps1
#  Assistant interactif (demo) : detection systeme, questions,
#  recapitulatif et export TXT.
# ============================================================

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Assistant WordPress + Vagrant (demo)"

# Valeurs fixes
$HostPort = "8080"
$GuestIP  = "192.168.56.18"

# ---------- Helpers d'affichage -----------------------------
function Write-Title ($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
}
function Write-Question ($text) { Write-Host "`n$text" -ForegroundColor Yellow }
function Write-Hint     ($text) { Write-Host "  ($text)" -ForegroundColor DarkGray }
function Write-Ok       ($text) { Write-Host "  [OK] $text" -ForegroundColor Green }
function Write-Err      ($text) { Write-Host "  [X]  $text" -ForegroundColor Red }
function Write-Warn     ($text) { Write-Host "  [!]  $text" -ForegroundColor Yellow }

function Ask {
    param(
        [string]$Prompt, [string]$Default = "",
        [scriptblock]$Validate = $null, [switch]$Secret
    )
    while ($true) {
        Write-Question $Prompt
        if ($Default) { Write-Hint "Entree = $Default" }
        if ($Secret) {
            $secure = Read-Host -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            $answer = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        } else { $answer = Read-Host "  >" }
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        if ([string]::IsNullOrWhiteSpace($answer)) { Write-Err "Valeur obligatoire."; continue }
        if ($Validate) {
            $res = & $Validate $answer
            if ($res -ne $true) { Write-Err $res; continue }
        }
        return $answer
    }
}

function Ask-Choice {
    param([string]$Prompt, [string[]]$Options, [int]$DefaultIndex = 0)
    Write-Question $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $DefaultIndex) { " (defaut)" } else { "" }
        Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $Options[$i], $marker)
    }
    while ($true) {
        $raw = Read-Host "  >"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Options[$DefaultIndex] }
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $Options.Count) {
            return $Options[[int]$raw - 1]
        }
        Write-Err "Entrez un numero entre 1 et $($Options.Count)."
    }
}

function Ask-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $suffix = if ($Default) { "[O/n]" } else { "[o/N]" }
    while ($true) {
        $r = Read-Host "`n$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($r)) { return $Default }
        switch ($r.ToLower()) {
            "o" { return $true }; "oui" { return $true }; "y" { return $true }; "yes" { return $true }
            "n" { return $false }; "non" { return $false }; "no" { return $false }
            default { Write-Err "Repondez par o (oui) ou n (non)." }
        }
    }
}

# ---------- Détection système ------------------------------
function Get-SystemInfo {
    $info = [PSCustomObject]@{
        OS       = "Inconnu"
        Version  = "Inconnue"
        RAM_GB   = 0
        CPU      = "Inconnu"
        CPU_Cores = 0
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $info.OS = $os.Caption
            $info.Version = $os.Version
            $info.RAM_GB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        }
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) {
            $info.CPU = $cpu.Name.Trim()
            $info.CPU_Cores = $cpu.NumberOfCores
        }
    } catch { }
    return $info
}

# ---------- Vérification Vagrant / VirtualBox --------------
function Test-CommandExists ($name) {
    return ($null -ne (Get-Command $name -ErrorAction SilentlyContinue))
}

function Test-WingetExists {
    return (Test-CommandExists "winget")
}

function Install-WithWinget ($packageId, $displayName) {
    if (-not (Test-WingetExists)) {
        Write-Err "winget n'est pas disponible. Installez $displayName manuellement."
        return $false
    }
    Write-Host "`n  Installation de $displayName via winget..." -ForegroundColor Yellow
    Write-Host "  Package : $packageId" -ForegroundColor DarkGray
    try {
        $proc = Start-Process -FilePath "winget" -ArgumentList "install", "-e", "--id", $packageId, "--accept-package-agreements", "--accept-source-agreements" -Wait -NoNewWindow -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-Ok "$displayName installe avec succes."
            return $true
        } else {
            Write-Err "L'installation a retourne le code $($proc.ExitCode)."
            return $false
        }
    } catch {
        Write-Err "Echec de l'installation : $_"
        return $false
    }
}

function Check-Vagrant {
    if (Test-CommandExists "vagrant") {
        $v = (vagrant --version) -join ""
        Write-Ok "Vagrant detecte : $v"
        return $true
    }
    Write-Warn "Vagrant n'est pas installe (ou pas dans le PATH)."
    if (Test-WingetExists) {
        $install = Ask-YesNo "Voulez-vous installer Vagrant maintenant via winget ?" $true
        if ($install) {
            $ok = Install-WithWinget "Hashicorp.Vagrant" "Vagrant"
            if ($ok) {
                # Rafraichir le PATH dans la session courante
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                if (Test-CommandExists "vagrant") { Write-Ok "Vagrant est maintenant disponible."; return $true }
                else { Write-Warn "Vagrant installe mais pas encore dans le PATH. Redemarrez PowerShell." }
            }
        }
    } else {
        Write-Warn "winget indisponible. Telechargez Vagrant manuellement : https://developer.hashicorp.com/vagrant/downloads"
    }
    return $false
}

function Check-VirtualBox {
    if (Test-CommandExists "VBoxManage") {
        Write-Ok "VirtualBox detecte (VBoxManage dans le PATH)."
        return $true
    }
    # Fallback : verifier le dossier d'installation classique
    $vboxPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    if (Test-Path $vboxPath) {
        Write-Ok "VirtualBox detecte (installation classique)."
        return $true
    }
    Write-Warn "VirtualBox n'est pas installe (ou pas dans le PATH)."
    if (Test-WingetExists) {
        $install = Ask-YesNo "Voulez-vous installer VirtualBox maintenant via winget ?" $true
        if ($install) {
            $ok = Install-WithWinget "Oracle.VirtualBox" "VirtualBox"
            if ($ok) {
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                if (Test-CommandExists "VBoxManage") { Write-Ok "VirtualBox est maintenant disponible."; return $true }
                else { Write-Warn "VirtualBox installe mais pas encore dans le PATH. Redemarrez PowerShell." }
            }
        }
    } else {
        Write-Warn "winget indisponible. Telechargez VirtualBox manuellement : https://www.virtualbox.org/wiki/Downloads"
    }
    return $false
}

# ---------- Détection des disques disponibles --------------
function Get-AvailableDrives {
    $drives = @()
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
        if ($null -ne $_.Used -and $null -ne $_.Free) {
            $path = "$($_.Name):\"
            if (Test-Path $path) {
                $freeGB  = [math]::Round($_.Free / 1GB, 1)
                $totalGB = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
                $drives += [PSCustomObject]@{
                    Letter  = "$($_.Name):\"
                    FreeGB  = $freeGB
                    TotalGB = $totalGB
                    Label   = "$($_.Name):\ - $freeGB Go libres / $totalGB Go"
                }
            }
        }
    }
    return $drives
}

$vPath     = { param($v) if ($v -match '^[A-Za-z]:\\') { return $true } return "Le chemin doit commencer par une lettre de lecteur, ex : D:\wordpress-vagrant" }
$vEmail    = { param($v) if ($v -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $true } return "Adresse email invalide." }
$vNonEmpty = { param($v) $true }

# ---------- EN-TÊTE ----------------------------------------
Clear-Host
Write-Host ""
Write-Host "  ======================================================" -ForegroundColor Magenta
Write-Host "    ASSISTANT D'INSTALLATION WORDPRESS + VAGRANT" -ForegroundColor Magenta
Write-Host "    (mode demonstration - rien ne sera execute)" -ForegroundColor Magenta
Write-Host "  ======================================================" -ForegroundColor Magenta

# ---------- 0. DÉTECTION SYSTÈME ---------------------------
Write-Title "0/8 - Detection de votre systeme"
$sys = Get-SystemInfo
Write-Host "  Systeme d'exploitation : " -NoNewline; Write-Host $sys.OS -ForegroundColor Cyan
Write-Host "  Version                : " -NoNewline; Write-Host $sys.Version -ForegroundColor Cyan
Write-Host "  Memoire RAM totale     : " -NoNewline; Write-Host "$($sys.RAM_GB) Go" -ForegroundColor Cyan
Write-Host "  Processeur             : " -NoNewline; Write-Host $sys.CPU -ForegroundColor Cyan
Write-Host "  Coeurs CPU             : " -NoNewline; Write-Host $sys.CPU_Cores -ForegroundColor Cyan
Write-Host ""
Write-Ok "Informations systeme collectees."

# ---------- 0b. VÉRIFICATION VAGRANT / VIRTUALBOX ----------
Write-Title "0b/8 - Verification des outils requis"
$vagrantOk = Check-Vagrant
$vboxOk    = Check-VirtualBox

if (-not $vagrantOk -or -not $vboxOk) {
    Write-Host ""
    Write-Warn "Un ou plusieurs outils sont manquants."
    $continueAnyway = Ask-YesNo "Voulez-vous continuer la demonstration malgre tout ?" $false
    if (-not $continueAnyway) {
        Write-Host "`n  Demonstration interrompue." -ForegroundColor Yellow
        return
    }
}
Write-Host ""
Write-Ok "Outils verifies (Vagrant : $(if ($vagrantOk) {'OK'} else {'manquant'}) / VirtualBox : $(if ($vboxOk) {'OK'} else {'manquant'}))"

Start-Sleep -Milliseconds 500

# ---------- 1. Emplacement du projet -----------------------
Write-Title "1/8 - Emplacement du projet"

$drives = Get-AvailableDrives
if ($drives.Count -eq 0) {
    Write-Err "Aucun disque fixe detecte. Impossible de continuer."
    return
}

$driveOptions = $drives | ForEach-Object { $_.Label }
$driveOptions += "Autre... (saisir un chemin)"
$defaultIdx = 0
for ($i = 0; $i -lt $drives.Count; $i++) {
    if ($drives[$i].Letter -eq "D:\") { $defaultIdx = $i }
}

$chosenDrive = Ask-Choice "Sur quel disque voulez-vous installer le projet ?" $driveOptions $defaultIdx

if ($chosenDrive -like "Autre...*") {
    $Drive = Ask "Indiquez le chemin racine complet" -Default "D:\" -Validate $vPath
} else {
    $Drive = ($chosenDrive -split ' ')[0]
    if ($Drive -notmatch '\\$') { $Drive += "\" }
}
$FolderName = Ask "Nom du dossier du projet" -Default "wordpress-vagrant" -Validate $vNonEmpty
$ProjectPath = Join-Path $Drive $FolderName
Write-Ok "Projet sera cree dans : $ProjectPath"

# ---------- 2. Informations du site ------------------------
Write-Title "2/8 - Informations du site WordPress"
$SiteTitle     = Ask "Titre du site" -Default "Mon Site WordPress" -Validate $vNonEmpty
$AdminUser     = Ask "Nom d'utilisateur administrateur WordPress" -Default "admin" -Validate $vNonEmpty
$AdminEmail    = Ask "Email administrateur" -Default "admin@example.com" -Validate $vEmail
$AdminPassword = Ask "Mot de passe administrateur (min. 8 caracteres)" -Secret -Validate {
    param($v) if ($v.Length -ge 8) { return $true } return "Au moins 8 caracteres."
}
Write-Ok "Compte admin : $AdminUser ($AdminEmail)"

# ---------- 3. Réseau (valeurs fixes) ----------------------
Write-Title "3/8 - Reseau et acces"
Write-Host "  Port HTTP    : " -NoNewline; Write-Host $HostPort -ForegroundColor Cyan
Write-Host "  IP privee VM : " -NoNewline; Write-Host $GuestIP -ForegroundColor Cyan
Write-Ok "Site accessible sur http://localhost:$HostPort"

# ---------- 4. Ressources VM -------------------------------
Write-Title "4/8 - Ressources de la machine virtuelle"
$Memory = Ask-Choice "Memoire RAM allouee a la VM" @("1024 Mo (leger)", "2048 Mo (recommande)", "4096 Mo (confortable)") 1
$CPUs = Ask "Nombre de vCPU" -Default "2" -Validate {
    param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 8) { return $true } return "Entre 1 et 8."
}
Write-Ok "VM : $Memory RAM, $CPUs vCPU"

# ---------- 5. Base de données -----------------------------
Write-Title "5/8 - Base de donnees MySQL"
$DBName     = Ask "Nom de la base de donnees" -Default "wordpress" -Validate $vNonEmpty
$DBUser     = Ask "Utilisateur MySQL" -Default "wordpress" -Validate $vNonEmpty
$DBPassword = Ask "Mot de passe MySQL" -Secret -Validate {
    param($v) if ($v.Length -ge 6) { return $true } return "Au moins 6 caracteres."
}
Write-Ok "BDD : $DBName / utilisateur $DBUser"

# ---------- 6. Options -------------------------------------
Write-Title "6/8 - Options supplementaires"
$EnableSync   = Ask-YesNo "Synchroniser le dossier WordPress avec Windows (pour edition locale)" $true
$OpenBrowser  = Ask-YesNo "Ouvrir automatiquement le navigateur a la fin de l'installation" $true
$KeepExisting = Ask-YesNo "Conserver les fichiers existants si le dossier est deja present" $true

# ---------- 7. Récapitulatif -------------------------------
Write-Title "7/8 - Recapitulatif de la configuration"
Write-Host ""
Write-Host "  --- SYSTEME HOTE ---" -ForegroundColor DarkGray
Write-Host "  OS                    : " -NoNewline; Write-Host $sys.OS -ForegroundColor Cyan
Write-Host "  RAM totale            : " -NoNewline; Write-Host "$($sys.RAM_GB) Go" -ForegroundColor Cyan
Write-Host "  CPU                   : " -NoNewline; Write-Host "$($sys.CPU) ($($sys.CPU_Cores) coeurs)" -ForegroundColor Cyan
Write-Host "  Vagrant               : " -NoNewline; Write-Host $(if ($vagrantOk) {"Disponible"} else {"Manquant"}) -ForegroundColor $(if ($vagrantOk) {"Green"} else {"Red"})
Write-Host "  VirtualBox            : " -NoNewline; Write-Host $(if ($vboxOk) {"Disponible"} else {"Manquant"}) -ForegroundColor $(if ($vboxOk) {"Green"} else {"Red"})
Write-Host ""
Write-Host "  --- PROJET ---" -ForegroundColor DarkGray
Write-Host "  Emplacement           : " -NoNewline; Write-Host $ProjectPath -ForegroundColor Cyan
Write-Host "  URL du site           : " -NoNewline; Write-Host "http://localhost:$HostPort" -ForegroundColor Cyan
Write-Host "  Titre du site         : " -NoNewline; Write-Host $SiteTitle -ForegroundColor Cyan
Write-Host "  Admin WordPress       : " -NoNewline; Write-Host "$AdminUser ($AdminEmail)" -ForegroundColor Cyan
Write-Host "  Mot de passe admin    : " -NoNewline; Write-Host ("*" * $AdminPassword.Length) -ForegroundColor Cyan
Write-Host ""
Write-Host "  --- VM ---" -ForegroundColor DarkGray
Write-Host "  Ressources            : " -NoNewline; Write-Host "$Memory, $CPUs vCPU, IP $GuestIP" -ForegroundColor Cyan
Write-Host "  Base de donnees       : " -NoNewline; Write-Host "$DBName / $DBUser" -ForegroundColor Cyan
Write-Host "  Mot de passe MySQL    : " -NoNewline; Write-Host ("*" * $DBPassword.Length) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Synchronisation       : $(if ($EnableSync) {'Oui'} else {'Non'})" -ForegroundColor $(if ($EnableSync) {"Green"} else {"DarkGray"})
Write-Host "  Ouvrir le navigateur  : $(if ($OpenBrowser) {'Oui'} else {'Non'})" -ForegroundColor $(if ($OpenBrowser) {"Green"} else {"DarkGray"})
Write-Host "  Conserver l'existant  : $(if ($KeepExisting) {'Oui'} else {'Non'})" -ForegroundColor $(if ($KeepExisting) {"Green"} else {"DarkGray"})
Write-Host ""

# ---------- 8. Confirmation + TXT --------------------------
Write-Title "8/8 - Confirmation et export"
$go = Ask-YesNo "Confirmez-vous ces parametres et souhaitez-vous lancer l'installation ?" $true

$txtPath = $null
try {
    if ($go) {
    if (-not (Test-Path $ProjectPath)) {
        New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
    }
    $txtPath = Join-Path $ProjectPath "infos-wordpress.txt"
    $dateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $lines = @(
        "============================================================",
        "  INFORMATIONS D'INSTALLATION WORDPRESS + VAGRANT",
        "  Genere le : $dateStr",
        "  Statut    : INSTALLATION VALIDEE (demo)",
        "============================================================",
        "",
        "--- SYSTEME HOTE ---",
        "OS                    : $($sys.OS)",
        "Version               : $($sys.Version)",
        "RAM totale            : $($sys.RAM_GB) Go",
        "Processeur            : $($sys.CPU)",
        "Coeurs CPU            : $($sys.CPU_Cores)",
        "Vagrant               : $(if ($vagrantOk) { 'Disponible' } else { 'Manquant' })",
        "VirtualBox            : $(if ($vboxOk) { 'Disponible' } else { 'Manquant' })",
        "",
        "--- EMPLACEMENT DU PROJET ---",
        "Chemin du projet      : $ProjectPath",
        "Fichier Vagrantfile   : $(Join-Path $ProjectPath 'Vagrantfile')",
        "Dossier synchronise   : $(Join-Path $ProjectPath 'wordpress')",
        "",
        "--- SITE WORDPRESS ---",
        "Titre du site         : $SiteTitle",
        "URL du site           : http://localhost:$HostPort",
        "URL administration    : http://localhost:$HostPort/wp-admin/",
        "",
        "--- COMPTE ADMINISTRATEUR WORDPRESS ---",
        "Nom d'utilisateur     : $AdminUser",
        "Email                 : $AdminEmail",
        "Mot de passe          : $AdminPassword",
        "",
        "--- BASE DE DONNEES MYSQL ---",
        "Nom de la base        : $DBName",
        "Utilisateur           : $DBUser",
        "Mot de passe          : $DBPassword",
        "Hote                  : localhost (dans la VM)",
        "",
        "--- RESEAU ---",
        "Port HTTP (hote)      : $HostPort",
        "IP privee de la VM    : $GuestIP",
        "",
        "--- MACHINE VIRTUELLE ---",
        "Memoire RAM           : $Memory",
        "vCPU                  : $CPUs",
        "Box                   : ubuntu/focal64",
        "",
        "--- OPTIONS ---",
        "Synchronisation       : $(if ($EnableSync)   { 'Oui' } else { 'Non' })",
        "Ouvrir le navigateur  : $(if ($OpenBrowser)  { 'Oui' } else { 'Non' })",
        "Conserver l'existant  : $(if ($KeepExisting) { 'Oui' } else { 'Non' })",
        "",
        "--- COMMANDES UTILES ---",
        "Demarrer la VM        : vagrant up",
        "Se connecter en SSH   : vagrant ssh",
        "Eteindre la VM        : vagrant halt",
        "Redemarrer la VM      : vagrant reload",
        "Etat Apache           : sudo systemctl status apache2",
        "Acceder au site       : ouvrir http://localhost:$HostPort",
        "",
        "============================================================",
        "  CONSERVEZ CE FICHIER EN LIEU SUR - IL CONTIENT VOS MOTS DE PASSE",
        "============================================================"
    )
    $lines | Out-File -FilePath $txtPath -Encoding UTF8
    Write-Host ""
    Write-Ok "Fichier d'informations ecrit : $txtPath"
    }
} catch {
    Write-Err "Impossible d'ecrire le fichier TXT : $_"
}

# ---------- Fin --------------------------------------------
if ($go) {
    Write-Host ""
    Write-Host "  [OK] Configuration validee." -ForegroundColor Green
    Write-Host "  (Mode demonstration : aucune action reelle n'a ete effectuee.)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Voici ce que ferait le script reel :" -ForegroundColor Cyan
    Write-Host "    1. Creer le dossier : $ProjectPath" -ForegroundColor Gray
    Write-Host "    2. Ecrire le Vagrantfile (port $HostPort, IP $GuestIP, $Memory RAM)" -ForegroundColor Gray
    Write-Host "    3. Lancer vagrant up et installer Apache + MySQL + PHP" -ForegroundColor Gray
    Write-Host "    4. Telecharger WordPress et creer la base '$DBName'" -ForegroundColor Gray
    Write-Host "    5. Configurer wp-config.php avec les identifiants fournis" -ForegroundColor Gray
    if ($EnableSync)  { Write-Host "    6. Monter le dossier synchronise pour edition locale" -ForegroundColor Gray }
    if ($OpenBrowser) { Write-Host "    7. Ouvrir http://localhost:$HostPort/wp-admin/install.php" -ForegroundColor Gray }
} else {
    Write-Host ""
    Write-Host "  Installation annulee par l'utilisateur." -ForegroundColor Yellow
}

if ($txtPath -and (Test-Path $txtPath)) {
    Write-Host ""
    Write-Host "  Recapitulatif ecrit dans :" -ForegroundColor Cyan
    Write-Host "    $txtPath" -ForegroundColor Cyan
    Write-Host "  Il contient toutes vos informations, y compris les mots de passe." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkCyan
Write-Host "  Fin de la demonstration." -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor DarkCyan
Write-Host ""