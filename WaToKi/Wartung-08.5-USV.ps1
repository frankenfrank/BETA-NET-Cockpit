#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
    [pscredential]$Anmeldedaten,
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
Write-Host "=== Wartung-08.5-USV ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
if (-not $Automatik) { Write-Host @'
BESCHREIBUNG
Fragt USV-Status per SNMP (Standard UPS-MIB, RFC 1628) ab – Batteriestatus, Restlaufzeit, Ladezustand, Ausgangsquelle, Last, Alarme – und gibt das Ergebnis in Datei/Konsole aus.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten USV (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten, das Kennwort ist die SNMP-Community; ohne Konto gilt 'public'). SNMP-Version 2. Dann entfallen Listenpflege und Abfragen. Ohne -Ziel läuft das Skript wie bisher interaktiv.

VORAUSSETZUNGEN
- PowerShell 7
- SNMP-Modul (wird bei Bedarf vom Skript installiert): Install-PSResource -Name SNMP -Scope CurrentUser -TrustRepository
- SNMP muss im Netzwerk-/Management-Modul der USV aktiviert sein (z. B. AdPoS Netman, FSP SNMP-Karte, CyberPower RMCARD)
- Geräte ohne Ethernet-Modul können so nicht abgefragt werden
'@ -ForegroundColor Yellow }
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

# - AUSGABEORDNER (aus dem NET-COCKPIT, sonst C:\Temp)
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }
$ZielModus = (@($Ziel | Where-Object { "$_".Trim() -ne "" }).Count -gt 0)
if ($Automatik -and -not $ZielModus) {
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (USV) nötig." -ForegroundColor Red
    exit 1
}


# - AUSGABEDATEI
$Datum        = Get-Date -Format "yyyyMMdd"
$Dateiname    = "Wartung_${Datum}_USV.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname
$Kunde        = $null # optional befuellen

# - ALTE DATEI LOESCHEN
Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue

# - LOGGING
function Write-Log {
    param ([string]$Text = "")
    Write-Output $Text
    Add-Content -Path $AusgabeDatei -Value $Text -Encoding utf8
}

# - SNMP-MODUL PRUEFEN
if (-not (Get-Module -ListAvailable -Name SNMP)) {
    Write-Log "SNMP-Modul ist nicht installiert."
    $installAntwort = if ($Automatik) { 'j' } else { Read-Host "SNMP-Modul jetzt installieren? (j/n)" }
    if ($installAntwort -ne "j") {
        Write-Log "Installation abgelehnt - Skript wird beendet."
        return
    }
    try {
        if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
            Install-PSResource -Name SNMP -Scope CurrentUser -TrustRepository -ErrorAction Stop
        }
        else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Install-Module -Name SNMP -Scope CurrentUser -Force -ErrorAction Stop
        }
        Write-Log "SNMP-Modul erfolgreich installiert."
    }
    catch {
        Write-Log "Installation fehlgeschlagen: $($_.Exception.Message)"
        Write-Log "Skript wird beendet."
        return
    }
}

try {
    Import-Module SNMP -ErrorAction Stop
}
catch {
    Write-Log "SNMP-Modul konnte nicht geladen werden: $($_.Exception.Message)"
    Write-Log "Skript wird beendet."
    return
}

# - SERVERLISTE
if ($ZielModus) {
    $USVListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Geräte (aus dem NET-COCKPIT):"
    $USVListe | ForEach-Object { Write-Host " - $_" }
}
else {
    $ServerListFile = "C:\Temp\liste-usv.txt"

    if (-not (Test-Path $ServerListFile)) {
        (Read-Host "USV Hostname/IP (Komma getrennt)") -split ",\s*" |
            Out-File $ServerListFile -Encoding utf8
    }

    Write-Host "`nZu pruefende USV:"
    Get-Content $ServerListFile | ForEach-Object { Write-Host " - $_" }

    if ((Read-Host "`nWeitere USV hinzufuegen? (j/n)") -eq "j") {
        (Read-Host "Neue USV (Komma getrennt)") -split ",\s*" |
            Add-Content $ServerListFile
    }

    $USVListe = Get-Content $ServerListFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

# - ERREICHBARKEIT PRUEFEN
Write-Log "Wartung USV - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
Write-Log "Ausgeführt auf: $env:COMPUTERNAME"
Write-Log ""
Write-Log "===== ERREICHBARKEIT ====="

## Funktionen
function Test-Ping {
    param ($Ziel, [int]$TimeoutMs = 2000)
    $pinger = [System.Net.NetworkInformation.Ping]::new()
    try   { return ($pinger.Send($Ziel, $TimeoutMs).Status -eq 'Success') }
    catch { return $false }
    finally { $pinger.Dispose() }
}

function Test-TcpPort {
    param ($Ziel, [int]$Port, [int]$TimeoutMs = 2000)
    $client = [System.Net.Sockets.TcpClient]::new()
    try   { return ($client.ConnectAsync($Ziel, $Port).Wait($TimeoutMs) -and $client.Connected) }
    catch { return $false }
    finally { $client.Dispose() }
}

$Zusammenfassung = @()
$USVErreichbar   = @()

foreach ($USV in $USVListe) {
    $ping  = Test-Ping -Ziel $USV
    $http  = $false
    $https = $false

    if (-not $ping) {
        $http  = Test-TcpPort -Ziel $USV -Port 80
        $https = Test-TcpPort -Ziel $USV -Port 443
    }

    if ($ping) {
        Write-Log "$USV : erreichbar (Ping OK)"
        $USVErreichbar += $USV
    }
    elseif ($http -or $https) {
        Write-Log "$USV : erreichbar (Ping blockiert, TCP 80: $http / TCP 443: $https)"
        $USVErreichbar += $USV
    }
    else {
        Write-Log "$USV : NICHT erreichbar (Ping, TCP 80 und TCP 443 fehlgeschlagen)"
        $Zusammenfassung += [PSCustomObject][ordered]@{
            USV            = $USV
            Status         = "Nicht erreichbar"
            Hersteller     = ""
            Modell         = ""
            Batterie       = ""
            Restlaufzeit   = ""
            Ladezustand    = ""
            Ausgangsquelle = ""
            Last           = ""
            Alarme         = ""
        }
    }
}

if ($USVErreichbar.Count -eq 0) {
    Write-Log ""
    Write-Log "Keine USV erreichbar - Skript wird beendet."
    if ($Automatik) {
        Write-WtErgebnis -Skript '08.5-USV' -Ordner $Ausgabepfad -Ergebnisse @($USVListe | ForEach-Object { [pscustomobject]@{ Ziel = [string]$_; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Nicht erreichbar (Ping, TCP 80 und 443 fehlgeschlagen)' } })
        exit 1
    }
    Invoke-Item $AusgabeDatei
    return
}

# - SNMP
# --- SNMP-Zugangsdaten (gelten fuer ALLE USV in der Liste) ---
if ($Automatik) {
    $SnmpCommunity = if ($Anmeldedaten) { $Anmeldedaten.GetNetworkCredential().Password } else { "" }
    $SnmpVersionInput = "2"
} else {
    $SnmpCommunity = Read-Host "SNMP Community (leer = 'public')"
    $SnmpVersionInput = Read-Host "SNMP Version - 1 oder 2 (leer = 2)"
}
if ([string]::IsNullOrWhiteSpace($SnmpCommunity)) { $SnmpCommunity = "public" }
$SnmpVersion = if ($SnmpVersionInput -eq "1") { "V1" } else { "V2" }

$SnmpTimeout = 3000

# --- Standard UPS-MIB OIDs (RFC 1628) ---
$OidSysDescr           = "1.3.6.1.2.1.1.1.0"          # MIB-II, Basis-Erreichbarkeitstest
$OidManufacturer       = "1.3.6.1.2.1.33.1.1.1.0"
$OidModel              = "1.3.6.1.2.1.33.1.1.2.0"
$OidBatteryStatus      = "1.3.6.1.2.1.33.1.2.1.0"
$OidSecondsOnBattery   = "1.3.6.1.2.1.33.1.2.2.0"
$OidMinutesRemaining   = "1.3.6.1.2.1.33.1.2.3.0"
$OidChargeRemaining    = "1.3.6.1.2.1.33.1.2.4.0"     # Prozent
$OidBatteryVoltage     = "1.3.6.1.2.1.33.1.2.5.0"     # 0.1 V DC
$OidOutputSource       = "1.3.6.1.2.1.33.1.4.1.0"
$OidOutputPercentLoad  = "1.3.6.1.2.1.33.1.4.4.1.5.1" # erste Output-Line
$OidAlarmsPresent      = "1.3.6.1.2.1.33.1.6.1.0"

# --- Standardisierte Klartexte laut RFC 1628 (kein Freitext, direkt aus der Norm) ---
$BatteryStatusText = @{ "1" = "unknown"; "2" = "normal"; "3" = "low"; "4" = "depleted" }
$OutputSourceText  = @{ "1" = "other"; "2" = "none"; "3" = "normal"; "4" = "bypass"; "5" = "battery"; "6" = "booster"; "7" = "reducer" }

function Get-SnmpValue {
    param ($IP, $OID)
    try {
        $result = Get-SnmpData -IP $IP -OID $OID -Community $SnmpCommunity -Version $SnmpVersion -UDPport 161 -TimeOut $SnmpTimeout -ErrorAction Stop
        if ($result) { return $result.Data } else { return $null }
    }
    catch {
        return $null
    }
}

# - ABFRAGE
foreach ($USV in $USVErreichbar) {
    Write-Log ""
    Write-Log "===== USV: $USV ====="

    $summary = [ordered]@{
        USV            = $USV
        Status         = "OK"
        Hersteller     = ""
        Modell         = ""
        Batterie       = ""
        Restlaufzeit   = ""
        Ladezustand    = ""
        Ausgangsquelle = ""
        Last           = ""
        Alarme         = ""
    }

    # --- Vorab-Check: SNMP-Basisabfrage (sysDescr, MIB-II) ---
    $sysDescr = Get-SnmpValue -IP $USV -OID $OidSysDescr
    if ($null -eq $sysDescr) {
        Write-Log "STATUS          : Erreichbar, SNMP antwortet nicht (Port 161 / Community / Version pruefen)"
        $summary.Status = "SNMP nicht erreichbar"
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }

    Write-Log ""
    Write-Log "--- SYSDESCR (RAW) ---"
    Write-Log "$sysDescr"

    Write-Log ""
    Write-Log "--- UPS-MIB (RAW, RFC 1628) ---"

    $mfr = Get-SnmpValue -IP $USV -OID $OidManufacturer
    Write-Log "Hersteller (upsIdentManufacturer)         : $mfr"
    $summary.Hersteller = $mfr

    $mdl = Get-SnmpValue -IP $USV -OID $OidModel
    Write-Log "Modell (upsIdentModel)                    : $mdl"
    $summary.Modell = $mdl

    $battStatusRaw = Get-SnmpValue -IP $USV -OID $OidBatteryStatus
    $battStatusTxt = if ($battStatusRaw -and $BatteryStatusText.ContainsKey("$battStatusRaw")) { $BatteryStatusText["$battStatusRaw"] } else { "nicht auslesbar" }
    Write-Log "Batteriestatus (upsBatteryStatus)         : $battStatusRaw ($battStatusTxt)"
    $summary.Batterie = "$battStatusRaw ($battStatusTxt)"

    $secOnBatt = Get-SnmpValue -IP $USV -OID $OidSecondsOnBattery
    Write-Log "Sekunden auf Batterie (upsSecondsOnBattery): $secOnBatt"

    $minRemain = Get-SnmpValue -IP $USV -OID $OidMinutesRemaining
    Write-Log "Restlaufzeit Minuten (upsEstimatedMinutesRemaining): $minRemain"
    $summary.Restlaufzeit = if ($null -ne $minRemain) { "$minRemain min" } else { "nicht auslesbar" }

    $chargeRemain = Get-SnmpValue -IP $USV -OID $OidChargeRemaining
    Write-Log "Ladezustand Prozent (upsEstimatedChargeRemaining): $chargeRemain"
    $summary.Ladezustand = if ($null -ne $chargeRemain) { "$chargeRemain %" } else { "nicht auslesbar" }

    $battVolt = Get-SnmpValue -IP $USV -OID $OidBatteryVoltage
    Write-Log "Batteriespannung 0.1V (upsBatteryVoltage) : $battVolt"

    $outSourceRaw = Get-SnmpValue -IP $USV -OID $OidOutputSource
    $outSourceTxt = if ($outSourceRaw -and $OutputSourceText.ContainsKey("$outSourceRaw")) { $OutputSourceText["$outSourceRaw"] } else { "nicht auslesbar" }
    Write-Log "Ausgangsquelle (upsOutputSource)           : $outSourceRaw ($outSourceTxt)"
    $summary.Ausgangsquelle = "$outSourceRaw ($outSourceTxt)"

    $outLoad = Get-SnmpValue -IP $USV -OID $OidOutputPercentLoad
    Write-Log "Last Prozent (upsOutputPercentLoad, Line 1): $outLoad"
    $summary.Last = if ($null -ne $outLoad) { "$outLoad %" } else { "nicht auslesbar" }

    $alarms = Get-SnmpValue -IP $USV -OID $OidAlarmsPresent
    Write-Log "Aktive Alarme (upsAlarmsPresent)           : $alarms"
    $summary.Alarme = if ($null -ne $alarms) { $alarms } else { "nicht auslesbar" }

    $Zusammenfassung += [PSCustomObject]$summary
}

# - ZUSAMMENFASSUNG
Write-Log ""
Write-Log ""
Write-Log "===== ZUSAMMENFASSUNG ====="

foreach ($s in $Zusammenfassung) {
    Write-Log ""
    Write-Log "--- $($s.USV) ---"
    Write-Log "Status            : $($s.Status)"
    if ($s.Status -eq "OK") {
        Write-Log "Hersteller/Modell : $($s.Hersteller) / $($s.Modell)"
        Write-Log "Batterie          : $($s.Batterie)"
        Write-Log "Restlaufzeit      : $($s.Restlaufzeit)"
        Write-Log "Ladezustand       : $($s.Ladezustand)"
        Write-Log "Ausgangsquelle    : $($s.Ausgangsquelle)"
        Write-Log "Last              : $($s.Last)"
        Write-Log "Alarme            : $($s.Alarme)"
    }
}

Write-Output ""
Write-Output "Ergebnisdatei: $AusgabeDatei"

if ($Automatik) {
    # - ERGEBNIS FÜR DIE CHECKLISTE (Haken nur bei belegter Aussage: USV per SNMP erreichbar; Batterie = Batteriestatus "normal")
    $ergebnisListe = foreach ($s in $Zusammenfassung) {
        if ($s.Status -ne 'OK') {
            [pscustomobject]@{ Ziel = [string]$s.USV; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = [string]$s.Status }
            continue
        }
        $pr = [ordered]@{ UsvErreichbar = $true }
        if ($s.Batterie -match '^\d') { $pr['BatterieOk'] = ($s.Batterie -match '^2 ') }
        $teile = @("$($s.Hersteller) $($s.Modell)".Trim(), "Batterie: $($s.Batterie)", "Ladezustand: $($s.Ladezustand)", "Restlaufzeit: $($s.Restlaufzeit)", "Last: $($s.Last)", "Alarme: $($s.Alarme)")
        [pscustomobject]@{
            Ziel       = [string]$s.USV
            Erreicht   = $true
            Pruefungen = [pscustomobject]$pr
            Werte      = [pscustomobject]@{ Hersteller = [string]$s.Hersteller; Modell = [string]$s.Modell; Batterie = [string]$s.Batterie; Restlaufzeit = [string]$s.Restlaufzeit; Ladezustand = [string]$s.Ladezustand; Ausgangsquelle = [string]$s.Ausgangsquelle; Last = [string]$s.Last; Alarme = [string]$s.Alarme }
            Notiz      = (($teile | Where-Object { $_ }) -join '; ')
        }
    }
    Write-WtErgebnis -Skript '08.5-USV' -Ordner $Ausgabepfad -Ergebnisse @($ergebnisListe)
    if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}

Invoke-Item $AusgabeDatei