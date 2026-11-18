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
Write-Host "=== Wartung-03.1-physServerIPMI ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Fragt Health-Status, Sensorwerte und System Event Log (SEL, letzte 30 Tage) des BMC eines physischen Servers per ipmiutil ab und schreibt einen Bericht in eine Logdatei. Die Abfrage läuft immer auf dem physischen Server selbst (In-Band-Schnittstelle, nicht remote zum BMC), die Logdatei wird auf dem Rechner gespeichert, auf dem das Skript gestartet wurde.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Server das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Die Abfrage läuft dann per Invoke-Command (Endpunkt PowerShell.7) auf jedem Server. Ohne -Ziel läuft das Skript wie bisher lokal auf dem Server, auf dem es gestartet wurde.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner, bei Abfrage per Cockpit auch auf dem Server (Remoting-Endpunkt PowerShell.7 per Enable-PSRemoting in pwsh)
- ipmiutil installiert: Download von https://ipmiutil.sourceforge.net/FILES/ (Datei ipmiutil-3.2.1-win64.zip), entpackt nach C:\tools\ipmitool\ (auf jedem abgefragten Server)
- Bei Abfrage per Cockpit: WinRM zum Server erreichbar und Anmeldung mit einem Konto, das dort Administrator ist
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

# - VERZEICHNIS UND DATEINAME
$LogPath = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}
$Timestamp = (Get-Date -Format "yyyyMMdd")
$LogFile   = Join-Path $LogPath ("Wartung_{0}_physServer-IPMI.txt" -f $Timestamp)

# - ZIELE BESTIMMEN
## Ohne -Ziel wird lokal abgefragt
$ServerListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
$lokaleNamen = @($env:COMPUTERNAME, "localhost", "127.0.0.1", "$env:COMPUTERNAME.$env:USERDNSDOMAIN")
if ($ServerListe.Count -gt 0) {
    Write-Host "`nZu prüfende Server (aus dem NET-COCKPIT):"
    $ServerListe | ForEach-Object { Write-Host " - $_" }
}
else {
    $ServerListe = @($env:COMPUTERNAME)
    Write-Host "`nKein Ziel übergeben - Abfrage lokal auf $env:COMPUTERNAME."
}

# - SCRIPTBLOCK FÜR DIE IPMIUTIL-ABFRAGE (läuft auf dem physischen Server)
$scriptBlock = {
    $ergebnis = [PSCustomObject]@{
        Fehler = $null
        Health = @()
        Sensor = @()
        Sel    = @()
    }

    # -- Tool/Parameter
    $ipmiutil = "C:\tools\ipmitool\ipmiutil.exe"
    $cutoff   = (Get-Date).AddDays(-30)

    if (-not (Test-Path -LiteralPath $ipmiutil)) {
        $ergebnis.Fehler = "ipmiutil.exe nicht gefunden unter $ipmiutil"
        return $ergebnis
    }

    try {
        # --- HEALTH (Errors von ipmiutil unterdrücken)
        $ergebnis.Health = @(& $ipmiutil health 2>$null | ForEach-Object { "$_" })

        # --- SENSORS: nur "nicht OK" und "Init" ausgeben (OEM/FRU-Zeilen raus)
        $sensorRaw = & $ipmiutil sensor 2>$null
        $ergebnis.Sensor = @($sensorRaw | Where-Object {
            ($_ -match "=\s") -and
            ($_ -match "\s(OK|Init|WARN|MIN|MAJ|CRIT)\s") -and
            ($_ -notmatch "^\s*ipmiutil\b") -and
            ($_ -notmatch "^\s*--\s*BMC\b") -and
            ($_ -notmatch "^\s*SDR\b") -and
            ($_ -notmatch "^\s*\d{4}\s") -and
            ($_ -notmatch "\sOK\s")
        } | ForEach-Object { "$_" })

        # --- SEL (LETZTE 30 TAGE): nur gültige Event-Zeilen, Datum per ParseExact filtern
        $selRaw   = & $ipmiutil sel -c 2>$null
        $selLines = $selRaw | Where-Object { $_ -match "^\s*[0-9a-fA-F]{4}\s*\|\s*\d{2}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s*\|" }

        $ergebnis.Sel = @(foreach ($line in $selLines) {
            $parts = $line -split "\|"
            if ($parts.Count -lt 3) { continue }

            $dtText = ($parts[1]).Trim()
            try {
                $dt = [DateTime]::ParseExact($dtText, "MM/dd/yy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                if ($dt -ge $cutoff) { "$line" }
            }
            catch {
                continue
            }
        })
    }
    catch {
        $ergebnis.Fehler = $_.Exception.Message
    }
    return $ergebnis
}

# - IPMI-ABFRAGE JE SERVER
Write-Host "IPMI-Abfrage laeuft..."
$Report = @()
$Report += "Wartung physische Server IPMI - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
$Report += "Ausgeführt auf: $env:COMPUTERNAME"
$Report += ""
$ergebnisListe = [System.Collections.Generic.List[object]]::new()

foreach ($Server in $ServerListe) {
    Write-Host "  -> $Server ..." -ForegroundColor Yellow
    $Report += "################ SERVER: $Server ################"
    $Report += ""

    $antwort = $null
    $fehler  = $null
    try {
        if ($Server -in $lokaleNamen) {
            $antwort = & $scriptBlock
        }
        else {
            ## Konto dieses Geräts aus dem NET-COCKPIT, sonst das gemeinsame Konto, sonst das angemeldete Windows-Konto
            $invokeParameter = @{ ComputerName = $Server; ScriptBlock = $scriptBlock; ConfigurationName = 'PowerShell.7'; ErrorAction = 'Stop' }
            $konto = $Anmeldedaten
            if ($AnmeldedatenJeZiel -and $AnmeldedatenJeZiel.ContainsKey($Server)) { $konto = $AnmeldedatenJeZiel[$Server] }
            if ($konto) { $invokeParameter.Credential = $konto }
            $antwort = Invoke-Command @invokeParameter
        }
    }
    catch {
        $fehler = $_.Exception.Message
    }

    if (-not $fehler -and $null -eq $antwort) { $fehler = "keine Antwort erhalten" }
    if (-not $fehler -and $antwort.Fehler) { $fehler = $antwort.Fehler }

    if ($fehler) {
        Write-Host "     Fehler: $fehler" -ForegroundColor Red
        $Report += "FEHLER: $fehler"
        $Report += ""
        $ergebnisListe.Add([pscustomobject]@{ Ziel = $Server; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = $fehler })
        continue
    }
    ### Checklisten-Werte: IPMI liefert keine eindeutige Zuordnung zu RAID/Firmware/BIOS/Netzteile, daher keine Haken, nur Kennzahlen
    $ergebnisListe.Add([pscustomobject]@{
        Ziel = $Server; Erreicht = $true; Pruefungen = [pscustomobject]@{}
        Werte = [pscustomobject]@{ SensorAbweichungen = @($antwort.Sensor).Count; SelEintraege30Tage = @($antwort.Sel).Count }
        Notiz = $(if (@($antwort.Sensor).Count -gt 0 -or @($antwort.Sel).Count -gt 0) { "IPMI: $(@($antwort.Sensor).Count) Sensor-Abweichungen, $(@($antwort.Sel).Count) SEL-Einträge (30 Tage), Details siehe Technikerinfo" } else { '' })
    })

    $Report += "===== IPMIUTIL HEALTH ====="
    $Report += $antwort.Health
    $Report += ""
    $Report += "===== IPMIUTIL SENSOR (NUR ABWEICHUNGEN) ====="
    if ($antwort.Sensor -and @($antwort.Sensor).Count -gt 0) { $Report += $antwort.Sensor } else { $Report += "Keine Abweichungen (alles OK / keine Init-Werte erkannt)." }
    $Report += ""
    $Report += "===== IPMIUTIL SEL (LETZTE 30 TAGE, -c) ====="
    if ($antwort.Sel -and @($antwort.Sel).Count -gt 0) { $Report += $antwort.Sel } else { $Report += "Keine SEL-Einträge innerhalb der letzten 30 Tage." }
    $Report += ""
}

# - AUSGABE (KONSOLE + DATEI)
if (-not $Automatik) { Clear-Host }
Write-Host ""
$Report | Out-Host
$Report | Out-File -LiteralPath $LogFile -Encoding utf8

Write-Host "`nDatei gespeichert unter: $LogFile `n" -ForegroundColor Cyan

if ($Automatik) {
    Write-WtErgebnis -Skript '03.1-physServerIPMI' -Ordner $LogPath -Ergebnisse $ergebnisListe.ToArray()
    exit $(if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -gt 0) { 0 } else { 1 })
}
