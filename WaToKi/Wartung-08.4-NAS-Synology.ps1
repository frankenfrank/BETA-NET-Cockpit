#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
    [System.Management.Automation.PSCredential]$Anmeldedaten,
    [hashtable]$AnmeldedatenJeZiel
)

Clear-Host
Write-Host ""
Write-Host "=== Wartung-08.4-NAS-Synology ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Fragt Systemdaten (Firmware/DSM-Version, Storage/RAID, Datenträger, Speicherplatz, CPU/RAM-Auslastung) von Synology-NAS über die DSM Web API ab und gibt das Ergebnis in Datei/Konsole aus.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten NAS (-Ziel), den Ausgabeordner (-Ausgabeordner) und je NAS das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Hat ein NAS kein Konto, fragt das Skript einmal per Anmeldefenster nach und nutzt diese Zugangsdaten für die weiteren NAS ohne Konto. Ohne -Ziel wird wie bisher eine Liste (C:\Temp\liste-nas.txt) verwendet und interaktiv gepflegt.

HINWEIS
Diese API ist nicht offiziell von Synology dokumentiert. Ist auf dem NAS 2-Faktor-Authentifizierung eingerichtet, wird bei jedem Lauf nach dem OTP-Code gefragt.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- HTTPS-Zugriff auf die DSM-Weboberfläche des NAS (Standardport 5001)
- DSM-Benutzerkonto mit Zugriff auf Storage Manager / Control Panel
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - PARAMETER
$Port = 5001

# - AUSGABEORDNER (aus dem NET-COCKPIT, sonst C:\Temp)
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }

# - SERVERLISTE
$NASListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
if ($NASListe.Count -gt 0) {
    Write-Host "`nZu prüfende NAS (aus dem NET-COCKPIT):"
    $NASListe | ForEach-Object { Write-Host " - $_" }
}
else {
    $ServerListFile = Join-Path $Ausgabepfad "liste-nas.txt"

    if (-not (Test-Path -LiteralPath $ServerListFile)) {
        (Read-Host "NAS Hostname/IP (Komma getrennt)") -split ",\s*" |
            Out-File -LiteralPath $ServerListFile -Encoding utf8
    }

    Write-Host "`nZu prüfende NAS:"
    Get-Content -LiteralPath $ServerListFile | ForEach-Object { Write-Host " - $_" }

    if ((Read-Host "`nWeitere NAS hinzufügen? (j/n)") -eq "j") {
        (Read-Host "Neue NAS (Komma getrennt)") -split ",\s*" |
            Add-Content -LiteralPath $ServerListFile
    }

    $NASListe = @(Get-Content -LiteralPath $ServerListFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

# - AUSGABEDATEI
$Datum        = Get-Date -Format "yyyyMMdd"
$Dateiname    = "Wartung_${Datum}_NAS-Synology.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname

# - ALTE DATEI LÖSCHEN
Remove-Item -LiteralPath $AusgabeDatei -ErrorAction SilentlyContinue

# - LOG-FUNKTION
function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -LiteralPath $AusgabeDatei -Value $Message
}

# - ANMELDEDATEN
## Je NAS das Konto aus dem NET-COCKPIT; fehlt es, einmal abfragen und für die weiteren NAS ohne Konto weiterverwenden
$gemeinsamesKonto = $Anmeldedaten
function Get-NasKonto {
    param([string]$NAS)
    if ($AnmeldedatenJeZiel -and $AnmeldedatenJeZiel.ContainsKey($NAS)) { return $AnmeldedatenJeZiel[$NAS] }
    if (-not $script:gemeinsamesKonto) { $script:gemeinsamesKonto = Get-Credential -Message "DSM-Zugangsdaten (für $NAS)" }
    return $script:gemeinsamesKonto
}

# - ANMELDEFUNKTION (MIT OTP-ABFRAGE BEI 2FA)
function Invoke-DsmLogin {
    param($BaseUrl, $Cred, $DeviceName, $NAS)

    $params = @{
        api         = "SYNO.API.Auth"
        version     = 6
        method      = "login"
        account     = $Cred.UserName
        passwd      = $Cred.GetNetworkCredential().Password
        session     = "SystemStatus"
        format      = "sid"
        device_name = $DeviceName
    }

    $resp = Invoke-RestMethod -Uri $BaseUrl -Method Get -Body $params -SkipCertificateCheck -ErrorAction Stop

    # -- 2FA erforderlich -> OTP-Code abfragen
    if (-not $resp.success -and $resp.error.code -eq 403) {
        $params["otp_code"] = Read-Host "OTP-Code für $NAS (2-Faktor)"
        $resp = Invoke-RestMethod -Uri $BaseUrl -Method Get -Body $params -SkipCertificateCheck -ErrorAction Stop
    }

    return $resp
}

# - API-ABFRAGE JE NAS
foreach ($NAS in $NASListe) {
    Write-Log "`n===== NAS: $NAS ====="

    $baseUrl    = "https://${NAS}:${Port}/webapi/entry.cgi"
    $DeviceName = "MahrEDV-WartungsSkript"

    try {
        # -- ANMELDUNG
        $cred = Get-NasKonto -NAS $NAS
        if (-not $cred) { Write-Log "STATUS          : Keine Zugangsdaten - übersprungen"; continue }
        $login = Invoke-DsmLogin -BaseUrl $baseUrl -Cred $cred -DeviceName $DeviceName -NAS $NAS

        if (-not $login.success) {
            Write-Log "STATUS          : Anmeldung fehlgeschlagen (Fehlercode $($login.error.code))"
            continue
        }

        $sid = $login.data.sid

        # -- SYSTEMINFO ABRUFEN
        $sysParams = @{ api = "SYNO.Core.System"; version = 1; method = "info"; _sid = $sid }
        $sysInfo   = Invoke-RestMethod -Uri $baseUrl -Method Get -Body $sysParams -SkipCertificateCheck -ErrorAction Stop
        $sys       = $sysInfo.data

        Write-Log "`n--- SYSTEMINFO ---"
        Write-Log ("Modell           : {0}" -f $sys.model)
        Write-Log ("Firmware         : {0} (Stand {1})" -f $sys.firmware_ver, $sys.firmware_date)
        Write-Log ("Seriennummer     : {0}" -f $sys.serial)
        Write-Log ("RAM              : {0} MB" -f $sys.ram_size)
        Write-Log ("Temperatur       : {0} °C" -f $sys.sys_temp)
        Write-Log ("Uptime           : {0}" -f $sys.up_time)
        Write-Log ("Systemzeit       : {0}" -f $sys.time)

        # -- STORAGE / RAID / DATENTRAEGER ABRUFEN
        $storageParams = @{ api = "SYNO.Storage.CGI.Storage"; version = 1; method = "load_info"; _sid = $sid }
        $storageInfo   = Invoke-RestMethod -Uri $baseUrl -Method Get -Body $storageParams -SkipCertificateCheck -ErrorAction Stop
        $storage       = $storageInfo.data

        Write-Log "`n--- RAID / STORAGE POOLS ---"
        foreach ($pool in $storage.storagePools) {
            Write-Log ("{0} ({1}) - Status: {2}" -f $pool.desc, $pool.device_type, $pool.status)
            foreach ($raid in $pool.raids) {
                Write-Log ("  RAID {0}: {1}/{2} Laufwerke normal" -f $raid.raidPath, $raid.normalDevCount, $raid.designedDiskCount)
            }
        }

        Write-Log "`n--- DATENTRAEGER ---"
        foreach ($disk in ($storage.disks | Sort-Object slot_id)) {
            $sizeTB = [math]::Round([int64]$disk.size_total / 1TB, 1)
            Write-Log ("{0} ({1}) - Modell {2} - Status: {3} - SMART: {4} - Temp: {5} °C - Größe: {6} TB" -f `
                $disk.longName, $disk.device, $disk.model, $disk.status, $disk.smart_status, $disk.temp, $sizeTB)
        }

        Write-Log "`n--- SPEICHERPLATZ (VOLUMES) ---"
        foreach ($vol in $storage.volumes) {
            $totalTB = [math]::Round([int64]$vol.size.total / 1TB, 2)
            $usedTB  = [math]::Round([int64]$vol.size.used / 1TB, 2)
            $freeTB  = [math]::Round(([int64]$vol.size.total - [int64]$vol.size.used) / 1TB, 2)
            $pctUsed = [math]::Round(([int64]$vol.size.used / [int64]$vol.size.total) * 100, 0)
            Write-Log ("{0} ({1}) - Status: {2} - Belegt: {3} TB von {4} TB ({5}%) - Frei: {6} TB" -f `
                $vol.vol_desc, $vol.fs_type, $vol.status, $usedTB, $totalTB, $pctUsed, $freeTB)
        }

        # -- CPU/RAM AUSLASTUNG ABRUFEN
        $utilParams = @{ api = "SYNO.Core.System.Utilization"; version = 1; method = "get"; _sid = $sid }
        $utilInfo   = Invoke-RestMethod -Uri $baseUrl -Method Get -Body $utilParams -SkipCertificateCheck -ErrorAction Stop
        $util       = $utilInfo.data

        Write-Log "`n--- CPU / RAM AUSLASTUNG ---"
        $load1  = [math]::Round($util.cpu.'1min_load' / 100, 2)
        $load5  = [math]::Round($util.cpu.'5min_load' / 100, 2)
        $load15 = [math]::Round($util.cpu.'15min_load' / 100, 2)
        Write-Log ("CPU Load (1/5/15 min) : {0} / {1} / {2}" -f $load1, $load5, $load15)

        $ramTotalMB = [math]::Round($util.memory.total_real / 1024, 0)
        $ramAvailMB = [math]::Round($util.memory.avail_real / 1024, 0)
        Write-Log ("RAM genutzt            : {0}% (verfügbar: {1} MB von {2} MB)" -f $util.memory.real_usage, $ramAvailMB, $ramTotalMB)

        $swapTotalMB = [math]::Round($util.memory.total_swap / 1024, 0)
        Write-Log ("Swap genutzt            : {0}% (gesamt: {1} MB)" -f $util.memory.swap_usage, $swapTotalMB)

        # -- ABMELDUNG
        $logoutParams = @{ api = "SYNO.API.Auth"; version = 6; method = "logout"; session = "SystemStatus" }
        Invoke-RestMethod -Uri $baseUrl -Method Get -Body $logoutParams -SkipCertificateCheck -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Log "STATUS          : Verbindung fehlgeschlagen - $($_.Exception.Message)"
    }
}

Write-Log "`n`nErgebnisdatei: $AusgabeDatei"
Invoke-Item -LiteralPath $AusgabeDatei