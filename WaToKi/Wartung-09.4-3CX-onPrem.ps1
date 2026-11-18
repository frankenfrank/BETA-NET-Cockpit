#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
    [System.Management.Automation.PSCredential]$Anmeldedaten,
    [hashtable]$AnmeldedatenJeZiel,
    [switch]$Automatik
)

# - ERGEBNIS FÜR DIE CHECKLISTE (nur mit -Automatik; alles Ausführliche steht auf der Konsole und kommt so in die Technikerinfo)
function Write-WtErgebnis {
    param([string]$Skript, [object[]]$Ergebnisse, [string]$Ordner)
    if ([string]::IsNullOrWhiteSpace($Ordner)) { $Ordner = 'C:\Temp' }
    if (-not (Test-Path -LiteralPath $Ordner)) { [void](New-Item -Path $Ordner -ItemType Directory -Force) }
    [pscustomobject]@{ Skript = $Skript; Version = 1; Ergebnisse = @($Ergebnisse) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Ordner "Ergebnis_$Skript.json") -Encoding utf8
}

if (-not $Automatik) { Clear-Host }
Write-Host ""
Write-Host "=== Wartung-09.4-3CX-onPrem ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
if (-not $Automatik) { Write-Host @'
BESCHREIBUNG
Prüft 3CX-on-Premise-Server per SSH (Windows oder Debian, OS wird automatisch per uname erkannt): installiertes 3CX-Paket, Status der 3CX-Dienste, Alter des letzten Backups. Bietet bei nicht erreichbarem SSH auf Windows-Zielen einen automatischen Fix per WinRM an (OpenSSH-Server installieren + Firewall-Regel setzen). Deckt nicht ab: SIP-Trunk-Status, Endgeräte-Firmware, verfügbare 3CX-Updates (dafür 3CX Management Console/XAPI). Kein Zugriff auf die interne 3CX-Datenbank.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten 3CX-Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Server das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Hat ein Server kein Konto oder schlägt die SSH-Anmeldung fehl, fragt das Skript nach (3 Versuche pro Server). Ohne -Ziel wird wie bisher eine Liste (C:\Temp\liste-3cx.txt) verwendet und interaktiv gepflegt.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Posh-SSH-Modul (wird bei Bedarf interaktiv zur Installation angeboten: Install-Module -Name Posh-SSH -Scope CurrentUser -Force)
- SSH-Zugriff (Port 22) auf jeden 3CX-Server
- Bei Windows-Zielen: OpenSSH-Server-Feature installiert, Dienst "sshd" gestartet, Firewall-Regel "OpenSSH-Server-In-TCP" für Profil "Any" freigegeben, Login mit Windows-Admin-Benutzer (kein root)
- Für den eingebauten Auto-Fix bei nicht erreichbarem SSH auf Windows-Zielen: WinRM auf dem Zielserver erreichbar, Zugangsdaten mit Admin-Rechten
- Backup-Pfad Debian: Standardpfad für Instance1 (/var/lib/3cxpbx/Instance1/Data/Backups), bei abweichender Instanz in $BackupPfadLinux anpassen; Backup-Pfad Windows wird automatisch unter C:\ProgramData\3CX gesucht
'@ -ForegroundColor Yellow }
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

# - VORAUSSETZUNG: MODUL POSH-SSH ---
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    $antwort = if ($Automatik) { "j" } else { Read-Host "Modul 'Posh-SSH' ist nicht installiert. Jetzt installieren? (j/n)" }
    if ($antwort -eq "j") {
        try {
            Install-Module -Name Posh-SSH -Scope CurrentUser -Force -ErrorAction Stop
        }
        catch {
            Write-Host "FEHLER: Installation von Posh-SSH fehlgeschlagen - $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }
    else {
        Write-Host "FEHLER: Modul 'Posh-SSH' wird benoetigt. Script wird beendet." -ForegroundColor Red
        return
    }
}
try {
    Import-Module Posh-SSH -ErrorAction Stop
}
catch {
    Write-Host "FEHLER: Posh-SSH konnte nicht geladen werden - $($_.Exception.Message)" -ForegroundColor Red
    return
}

# - AUSGABEORDNER (aus dem NET-COCKPIT, sonst C:\Temp)
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }

# - SERVERLISTE
$ServerListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
if ($Automatik -and $ServerListe.Count -eq 0) {
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (3CX-Server) nötig." -ForegroundColor Red
    exit 1
}
if ($ServerListe.Count -gt 0) {
    Write-Host "`nZu pruefende 3CX-Server (aus dem NET-COCKPIT):"
    $ServerListe | ForEach-Object { Write-Host " - $_" }
}
else {
    $ServerListFile = Join-Path $Ausgabepfad "liste-3cx.txt"
    if (-not (Test-Path -LiteralPath $ServerListFile)) {
        (Read-Host "3CX Hostname/IP (Komma getrennt)") -split ",\s*" |
            Out-File -LiteralPath $ServerListFile -Encoding utf8
    }
    Write-Host "`nZu pruefende 3CX-Server:"
    Get-Content -LiteralPath $ServerListFile | ForEach-Object { Write-Host " - $_" }
    if ((Read-Host "`nWeitere Server hinzufuegen? (j/n)") -eq "j") {
        (Read-Host "Neue Server (Komma getrennt)") -split ",\s*" |
            Add-Content -LiteralPath $ServerListFile
    }
    $ServerListe = @(Get-Content -LiteralPath $ServerListFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}
$SSHPort        = 22
$BackupPfadLinux = "/var/lib/3cxpbx/Instance1/Data/Backups"

# - AUSGABEDATEI
$Datum        = Get-Date -Format "yyyyMMdd"
$Dateiname    = "Wartung_${Datum}_3CX.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname
$Kunde        = $null # optional befuellen

# - ALTE DATEI LOESCHEN
Remove-Item -LiteralPath $AusgabeDatei -ErrorAction SilentlyContinue

function Write-Log {
    # Schreibt gleichzeitig auf die Konsole und ins Log-File (Add-Content).
    # Ersetzt Start-Transcript, das in der PowerShell ISE beim Anzeigen des
    # Get-Credential-Dialogs abbricht.
    param(
        [Parameter(ValueFromPipeline)] [AllowEmptyString()] [string[]] $Text = "",
        [string] $ForegroundColor
    )
    process {
        foreach ($Line in $Text) {
            if ($ForegroundColor) {
                Write-Host $Line -ForegroundColor $ForegroundColor
            } else {
                Write-Host $Line
            }
            Add-Content -LiteralPath $AusgabeDatei -Value $Line
        }
    }
}

function ConvertTo-Lines {
    # Posh-SSH liefert Output je nach Laenge mal als String-Array, mal als
    # einzelner mehrzeiliger String -> hier robust auf Zeilen-Array normalisieren
    param ($Output)
    return (($Output -join "`n") -split "`r?`n")
}

function Get-EncodedCommand {
    # Wandelt ein PowerShell-Script in Base64 um, damit es per
    # "powershell -EncodedCommand" ohne Escaping-Probleme via SSH
    # auf einem Windows-Ziel ausgefuehrt werden kann
    param ($ScriptText)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($ScriptText)
    return [Convert]::ToBase64String($bytes)
}

function Read-CredentialConsole {
    # Fragt Zugangsdaten ueber die Konsole ab (Read-Host) statt ueber den
    # WinForms-Dialog von Get-Credential. Grund: In der PowerShell ISE bricht
    # ein laufendes Start-Transcript ab, sobald der Get-Credential-Dialog
    # erscheint - das Skript laeuft danach normal weiter, aber im Log-File
    # fehlt ab dem Zeitpunkt alles.
    param (
        [Parameter(Mandatory)] [string] $Message,
        [switch] $AllowSkip
    )
    Write-Host $Message
    $Hinweis = if ($AllowSkip) { " (leer lassen zum Ueberspringen)" } else { "" }
    $Benutzername = Read-Host "Benutzername$Hinweis"
    if ($AllowSkip -and [string]::IsNullOrWhiteSpace($Benutzername)) {
        return $null
    }
    $Passwort = Read-Host "Passwort" -AsSecureString
    return New-Object System.Management.Automation.PSCredential($Benutzername, $Passwort)
}

function Test-Or-Repair-WindowsOpenSSH {
    # Wird aufgerufen, wenn SSH-Port 22 auf einem Ziel nicht erreichbar ist.
    # Prueft per WinRM, ob OpenSSH-Server installiert/aktiv ist, und bietet
    # bei Bedarf Installation + Firewall-Freigabe (Profil "Any") an.
    # Voraussetzung: WinRM auf dem Ziel erreichbar und uebergebene Zugangsdaten
    # haben Admin-Rechte auf der Zielmaschine.
    param (
        [Parameter(Mandatory)] $ComputerName,
        [Parameter(Mandatory)] $Credential
    )

    if (-not (Test-WSMan -ComputerName $ComputerName -ErrorAction SilentlyContinue)) {
        Write-Host "WinRM auf $ComputerName nicht erreichbar - kein automatischer Fix moeglich."
        return $false
    }

    if ($Automatik) {
        Write-Host "Automatikmodus: kein automatischer Fix (OpenSSH-Installation) auf $ComputerName."
        return $false
    }
    $antwort = Read-Host "SSH-Port auf $ComputerName nicht erreichbar. Per WinRM pruefen und OpenSSH ggf. installieren/Firewall setzen? (j/n)"
    if ($antwort -ne "j") { return $false }

    try {
        Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
            if ($cap.State -ne 'Installed') {
                Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
            }
            Start-Service sshd -ErrorAction SilentlyContinue
            Set-Service -Name sshd -StartupType 'Automatic'

            $rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
            if ($rule -and $rule.Profile -ne 'Any') {
                Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any
            }
        }
        Write-Host "OpenSSH auf $ComputerName installiert/konfiguriert."
        return $true
    }
    catch {
        Write-Host "FEHLER bei WinRM-Remediation auf $ComputerName - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Remote-Script, das auf einem Windows-Ziel per "powershell -EncodedCommand"
# ausgefuehrt wird und alle 3CX-Infos als JSON zurueckgibt
$WindowsRemoteScript = @'
$result = [ordered]@{
    Betriebssystem = ""
    Paket3CX       = @()
    Services       = @()
    LetztesBackup  = ""
}
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$result.Betriebssystem = "$($os.Caption) (Build $($os.BuildNumber))"
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$pakete = Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "3CX" } |
    ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }
$result.Paket3CX = if ($pakete) { @($pakete) } else { @("kein 3CX-Paket in Registry gefunden") }
$services = Get-Service -Name "3CX*" -ErrorAction SilentlyContinue |
    ForEach-Object { "$($_.Name): $($_.Status)" }
$result.Services = if ($services) { @($services) } else { @("keine 3CX-Dienste gefunden") }
$backupOrdner = Get-ChildItem -Path "C:\ProgramData\3CX" -Recurse -Directory -Filter "Backups" -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($backupOrdner) {
    $letzteDatei = Get-ChildItem -Path $backupOrdner.FullName -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $result.LetztesBackup = if ($letzteDatei) {
        "$($letzteDatei.Name) ($($letzteDatei.LastWriteTime))"
    } else {
        "Backup-Ordner gefunden, aber leer: $($backupOrdner.FullName)"
    }
} else {
    $result.LetztesBackup = "kein Backup-Ordner unter C:\ProgramData\3CX gefunden"
}
$result | ConvertTo-Json -Compress
'@

$Zusammenfassung = @()

foreach ($Server in $ServerListe) {
    Write-Log "`n===== 3CX-Server: $Server ====="
    $summary = [ordered]@{
        Server         = $Server
        Status         = "OK"
        System         = ""
        Betriebssystem = ""
        Paket3CX       = ""
        Services       = ""
        LetztesBackup  = ""
    }

    # --- Vorab-Check: Ping ---
    if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet)) {
        Write-Log "STATUS          : Nicht erreichbar (Ping fehlgeschlagen)"
        $summary.Status = "Ping fehlgeschlagen"
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }

    # --- Vorab-Check: SSH-Port (mit optionalem WinRM-Fix bei Windows-Zielen) ---
    $portCheck = Test-NetConnection -ComputerName $Server -Port $SSHPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $portCheck) {
        Write-Log "STATUS          : Ping OK, SSH-Port $SSHPort nicht erreichbar"

        $fixCred = $Anmeldedaten
        if ($AnmeldedatenJeZiel -and $AnmeldedatenJeZiel.ContainsKey($Server)) { $fixCred = $AnmeldedatenJeZiel[$Server] }
        if (-not $fixCred -and -not $Automatik) { $fixCred = Read-CredentialConsole -Message "Admin-Zugangsdaten fuer den $Server (nicht 3CX-Zugangsdaten)" -AllowSkip }
        if ($fixCred -and (Test-Or-Repair-WindowsOpenSSH -ComputerName $Server -Credential $fixCred)) {
            Start-Sleep -Seconds 3
            $portCheck = Test-NetConnection -ComputerName $Server -Port $SSHPort -InformationLevel Quiet -WarningAction SilentlyContinue
        }

        if (-not $portCheck) {
            $summary.Status = "SSH-Port nicht erreichbar"
            $Zusammenfassung += [PSCustomObject]$summary
            continue
        }
    }

    # --- Zugangsdaten (pro Server): zuerst das Konto dieses Geräts aus dem NET-COCKPIT, sonst Abfrage ---
    $cred = $Anmeldedaten
    if ($AnmeldedatenJeZiel -and $AnmeldedatenJeZiel.ContainsKey($Server)) { $cred = $AnmeldedatenJeZiel[$Server] }
    if (-not $cred -and $Automatik) {
        Write-Log "STATUS          : Keine Zugangsdaten"
        $summary.Status = "Keine Zugangsdaten"
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }
    if (-not $cred) { $cred = Read-CredentialConsole -Message "Zugangsdaten fuer 3CX-Server: $Server" }

    # --- SSH-Session (mit Login-Retry, max. 3 Versuche) ---
    $MaxLoginVersuche = 3
    $session = $null
    for ($LoginVersuch = 1; $LoginVersuch -le $MaxLoginVersuche; $LoginVersuch++) {
        if ($LoginVersuch -gt 1 -and $Automatik) { break }
        if ($LoginVersuch -gt 1) {
            Write-Log "STATUS          : SSH-Login fehlgeschlagen (Versuch $($LoginVersuch - 1)/$MaxLoginVersuche) - erneuter Versuch..." -ForegroundColor Yellow
            $cred = Read-CredentialConsole -Message "Zugangsdaten fuer 3CX-Server: $Server (Versuch $LoginVersuch/$MaxLoginVersuche)"
        }
        $session = New-SSHSession -ComputerName $Server -Port $SSHPort -Credential $cred -AcceptKey -ErrorAction SilentlyContinue
        if ($session) {
            $sid = $session.SessionId
            break
        }
    }
    if (-not $session) {
        Write-Log "STATUS          : SSH-Verbindung fehlgeschlagen (Login/Auth) nach $MaxLoginVersuche Versuchen"
        $summary.Status = "SSH-Login fehlgeschlagen ($MaxLoginVersuche Versuche)"
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }

    try {
        # --- Betriebssystem automatisch erkennen ---
        $unameResult = Invoke-SSHCommand -SessionId $sid -Command "uname -s" -ErrorAction SilentlyContinue
        $unameText   = if ($unameResult) { ($unameResult.Output -join "") } else { "" }

        if ($unameResult -and $unameResult.ExitStatus -eq 0 -and $unameText -match "Linux") {
            # ===== DEBIAN-ZWEIG =====
            $summary.System = "Debian/Linux"

            Write-Log "`n--- BETRIEBSSYSTEM (RAW /etc/os-release) ---"
            $osRelease = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "cat /etc/os-release").Output
            $osRelease | Write-Log
            $osText = $osRelease -join "`n"
            if ($osText -match '(?m)^PRETTY_NAME="(?<name>[^"]+)"') {
                $summary.Betriebssystem = $matches['name']
            } else {
                $summary.Betriebssystem = "nicht auslesbar"
            }

            Write-Log "`n--- 3CX PAKET (RAW dpkg -l | grep -i 3cx) ---"
            $dpkgRaw = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "dpkg -l | grep -i 3cx").Output
            $dpkgRaw | Write-Log
            $paketListe = $dpkgRaw | Where-Object { $_ -match '^\S+\s+\S+' } | ForEach-Object {
                $f = ($_ -split '\s+')
                if ($f.Count -ge 3) { "$($f[1])=$($f[2])" }
            }
            $summary.Paket3CX = if ($paketListe) { $paketListe } else { @("kein Paket gefunden") }

            Write-Log "`n--- 3CX SERVICES (RAW systemctl list-units | grep -i 3cx) ---"
            $svcRaw = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "systemctl list-units --type=service --all --no-pager | grep -i 3cx").Output
            $svcRaw | Write-Log
            $serviceListe = $svcRaw | Where-Object { $_ -match '3cx\S*\.service' } | ForEach-Object {
                $f = ($_.Trim() -split '\s+')
                if ($f.Count -ge 4) { "$($f[0]): $($f[2]) ($($f[3]))" }
            }
            $summary.Services = if ($serviceListe) { $serviceListe } else { @("keine Services gefunden") }

            Write-Log "`n--- BACKUP-ORDNER (RAW ls -lt $BackupPfadLinux) ---"
            $backupRaw = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "ls -lt $BackupPfadLinux 2>&1 | head -6").Output
            $backupRaw | Write-Log
            $ersteDatei = $backupRaw | Where-Object { $_ -match '^-' } | Select-Object -First 1
            $summary.LetztesBackup = if ($ersteDatei) { $ersteDatei.Trim() } else { "kein Backup gefunden (Pfad pruefen: $BackupPfadLinux)" }
        }
        else {
            # ===== WINDOWS-ZWEIG =====
            $summary.System = "Windows"
            $encoded = Get-EncodedCommand -ScriptText $WindowsRemoteScript
            $winRaw  = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "powershell -NoProfile -EncodedCommand $encoded").Output
            $winJson = $winRaw -join "`n"
            try {
                $winResult = $winJson | ConvertFrom-Json -ErrorAction Stop
                $summary.Betriebssystem = $winResult.Betriebssystem
                $summary.Paket3CX       = $winResult.Paket3CX
                $summary.Services       = $winResult.Services
                $summary.LetztesBackup  = $winResult.LetztesBackup
            }
            catch {
                Write-Log "STATUS          : Windows-Antwort konnte nicht ausgewertet werden (kein gueltiges JSON)"
                Write-Log "`n--- WINDOWS-ZIEL (RAW JSON) ---"
                Write-Log $winJson
                $summary.Status = "Fehler beim Abfragen (Windows-Auswertung)"
            }
        }
    }
    catch {
        Write-Log "STATUS          : Fehler beim Abfragen des Servers"
        $summary.Status = "Fehler beim Abfragen"
    }
    finally {
        Remove-SSHSession -SessionId $sid | Out-Null
        $Zusammenfassung += [PSCustomObject]$summary
    }
}

Write-Log "`n`n===== ZUSAMMENFASSUNG =====" -ForegroundColor Green
foreach ($s in $Zusammenfassung) {
    Write-Log "`n--- $($s.Server) ---"
    Write-Log "Status           : $($s.Status)"
    if ($s.Status -eq "OK") {
        Write-Log "System           : $($s.System)"
        Write-Log "Betriebssystem   : $($s.Betriebssystem)"
        Write-Log "3CX-Pakete:"
        $s.Paket3CX | ForEach-Object { Write-Log "   - $_" }
        Write-Log "Services:"
        $s.Services | ForEach-Object { Write-Log "   - $_" }
        Write-Log "Letztes Backup   : $($s.LetztesBackup)"
    }
}

if ($Automatik) {
    # - ERGEBNIS FÜR DIE CHECKLISTE (keine Haken: Dienststatus und Backup-Alter stehen in der Notiz)
    $ergebnisListe = foreach ($s in $Zusammenfassung) {
        if ($s.Status -ne 'OK') {
            [pscustomobject]@{ Ziel = [string]$s.Server; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = [string]$s.Status }
            continue
        }
        $dienste = @($s.Services | Where-Object { $_ -and $_ -notmatch '^keine ' })
        $laufen = @($dienste | Where-Object { $_ -match '(?i)running' }).Count
        $notizTeile = @()
        $notizTeile += $(if ($dienste.Count -gt 0) { "3CX-Dienste: $laufen von $($dienste.Count) laufen" } else { '3CX-Dienste: keine gefunden' })
        $notizTeile += "Letztes Backup: $($s.LetztesBackup)"
        [pscustomobject]@{
            Ziel       = [string]$s.Server
            Erreicht   = $true
            Pruefungen = [pscustomobject]@{}
            Werte      = [pscustomobject]@{ System = [string]$s.System; Betriebssystem = [string]$s.Betriebssystem; Pakete = @($s.Paket3CX); Dienste = $dienste; LetztesBackup = [string]$s.LetztesBackup }
            Notiz      = ($notizTeile -join '; ')
        }
    }
    Write-WtErgebnis -Skript '09.4-3CX-onPrem' -Ordner $Ausgabepfad -Ergebnisse @($ergebnisListe)
    if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}

# --- Kein Log behalten, wenn kein Server erfolgreich abgefragt wurde ---
$ErfolgreicheServer = $Zusammenfassung | Where-Object { $_.Status -eq "OK" }
if (-not $ErfolgreicheServer) {
    Remove-Item -LiteralPath $AusgabeDatei -ErrorAction SilentlyContinue
    Write-Host "`n`nKein Server erfolgreich abgefragt - kein Log erstellt." -ForegroundColor Yellow
} else {
    Write-Host "`n`nErgebnisdatei: $AusgabeDatei"
    Invoke-Item -LiteralPath $AusgabeDatei
}