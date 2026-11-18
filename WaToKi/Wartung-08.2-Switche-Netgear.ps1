#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
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
Write-Host "=== Wartung-08.2-Switche-Netgear ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
if (-not $Automatik) { Write-Host @'
BESCHREIBUNG
Prüft per SSH Netgear-Switche (Konfigsicherung, Firmware-Version, VLAN-/Port-Konfiguration) und erstellt zusätzlich eine Ist-Aufnahme (Interface-Status, Logauszug, Environment, PoE).

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Switche (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Gerät das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfällt die Listenpflege und die Kontoabfrage. Ohne -Ziel läuft das Skript wie bisher interaktiv.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Posh-SSH-Modul: Install-Module Posh-SSH -Scope CurrentUser -Force
- SSH aktiviert auf dem Switch, erreichbar auf Port 22
- Zugangsdaten mit Rechten für den "enable"-Modus; Skript geht davon aus, dass kein separates Enable-Passwort konfiguriert ist (nutzt sonst das SSH-Passwort erneut)
- CLI-Befehle sind Standard-FastPath (Netgear M/S-Serie) – Syntax je nach Modell/Firmware ggf. abweichend, vor Produktivbetrieb prüfen
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
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (Switche) nötig." -ForegroundColor Red
    exit 1
}

# - KONTEN JE ZIEL (aus dem NET-COCKPIT, Spalte "Konto")
$script:AnmeldedatenHost = @{}
if ($AnmeldedatenJeZiel) {
    foreach ($k in $AnmeldedatenJeZiel.Keys) { $script:AnmeldedatenHost["$k"] = $AnmeldedatenJeZiel[$k] }
}

function Get-ZielKonto {
    param([string]$Name)
    if ($script:AnmeldedatenHost.ContainsKey($Name)) { return $script:AnmeldedatenHost[$Name] }
    return $null
}

## Konto aus dem NET-COCKPIT; ohne Konto oder ab dem 2. Versuch wird abgefragt
function Get-ZielAnmeldung {
    param([string]$Name, [string]$Meldung, [int]$Versuch = 1)
    if ($Versuch -eq 1) {
        $c = Get-ZielKonto -Name $Name
        if ($c) { return $c }
    }
    if ($Automatik) { return $null }
    return (Get-Credential -Message $Meldung)
}


# - VERZEICHNIS UND DATEINAME
$LogPath = $Ausgabepfad
$Timestamp = (Get-Date).ToString("yyyyMMdd")
$LogFile = "$LogPath\Wartung_$Timestamp`_Switche.txt"

# - HOSTLISTE VERWALTEN
if ($ZielModus) {
    $ips = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Geräte (aus dem NET-COCKPIT):"
    $ips | ForEach-Object { Write-Host " - $_" }
}
else {
    $HostListFile = "$LogPath\liste-switche.txt"
    if (-not (Test-Path $HostListFile)) {
        Write-Host "→ Hostliste existiert nicht und wird erstellt..."
        Write-Host "IP-Adresse der Switche" -ForegroundColor Yellow
        $ersteHosts = Read-Host "Gib die ersten IPs der Switche ein (durch Komma getrennt)"
        $hosts_init = $ersteHosts -split ",\s*"
        $hosts_init | Out-File $HostListFile -Encoding utf8
        Write-Host "→ Hostliste wurde erstellt unter $HostListFile"
    }

    Write-Host "`nZu pruefende Switche:"
    Get-Content $HostListFile | ForEach-Object { Write-Host " - $_" }
    $antwort = Read-Host "`nWillst du weitere Switche hinzufügen? (j/n)"
    if ($antwort -eq "j") {
        $neue = Read-Host "Neue Switch-IPs (durch Komma getrennt)"
        $ips = $neue -split ",\s*"
        Add-Content -Path $HostListFile -Value $ips
        Write-Host "→ Neue Switche wurden hinzugefügt."
    }
    $ips = Get-Content $HostListFile | Where-Object { $_.Trim() -ne "" }
}
if ($ips.Count -eq 0) {
    Write-Host "→ Keine Switch-IP-Adressen hinterlegt – Abschnitt wird übersprungen."
    if ($Automatik) { exit 1 }
    return
}

# - SSH-MODUL
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Posh-SSH Modul wird installiert ..." -ForegroundColor Yellow
    Install-Module -Name Posh-SSH -Scope CurrentUser -Force
}
Import-Module Posh-SSH

# - FUNKTIONEN
# Netgear-Switche liefern ueber den SSH-Exec-Kanal (Invoke-SSHCommand) oft nur
# Timeouts/Fehler - sie erwarten eine interaktive Shell. Daher Ausfuehrung ueber
# einen Shell-Stream: Befehl schreiben, Ausgabe lesen, Pager-Prompts abfangen.
# Prompt-Muster: erkennt Zeilen wie "(M4300-28G-PoE+) #" oder "Switch>" am Ende
# der bisher gelesenen Ausgabe. Erst wenn der Prompt wieder da ist UND keine
# weiteren Daten mehr nachkommen, gilt der Befehl als abgeschlossen - das
# verhindert, dass der naechste Befehl zu frueh gesendet wird und mit
# asynchronen Log-/Trap-Meldungen des Switches vermischt/abgeschnitten wird
# (genau das ist beim ersten Testlauf bei "show environment" passiert).
function Read-SwitchStream {
    param($Stream, [int]$TimeoutSeconds = 20)
    $sb = New-Object System.Text.StringBuilder
    $start = Get-Date
    $lastData = Get-Date
    $promptRegex = '(?m)\)\s*[#>]\s*$|^\S+[#>]\s*$'
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        if ($Stream.DataAvailable) {
            $chunk = $Stream.Read()
            if ($chunk) {
                [void]$sb.Append($chunk)
                $lastData = Get-Date
                if ($chunk -match '(?i)(--more--|press any key|\(q\)uit|<space>)') {
                    $Stream.Write(" ")
                }
            }
        } else {
            if (($sb.Length -gt 0) -and ($sb.ToString().TrimEnd() -match $promptRegex) -and (((Get-Date) - $lastData).TotalMilliseconds -gt 500)) {
                break
            }
            Start-Sleep -Milliseconds 100
        }
    }
    return $sb.ToString()
}

# Dieser Switch pusht laufend asynchrone Trap-/Log-Meldungen (z.B. Link-Flap
# auf einem Port) ungefragt in die gleiche Session. Das kann sich mit dem
# gerade gesendeten Befehl vermischen, so dass der Befehlstext abgeschnitten
# ankommt ("show environment" -> nur "ironment"). Daher: vor dem Senden alle
# bereits gepufferten Alt-Daten verwerfen, und nach dem Senden grob pruefen,
# ob der Befehl ueberhaupt unbeschaedigt angekommen ist (taucht er in der
# Ausgabe auf?) - wenn nicht, bis zu 2x erneut senden.
function Invoke-SwitchCommand {
    param($Stream, [string]$Command, [int]$TimeoutSeconds = 20, [int]$MaxAttempts = 3)
    $result = ""
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            while ($Stream.DataAvailable) { [void]$Stream.Read() }
            $Stream.WriteLine($Command)
            $result = Read-SwitchStream -Stream $Stream -TimeoutSeconds $TimeoutSeconds
        } catch {
            return "FEHLER beim Ausfuehren von '$Command': $($_.Exception.Message)"
        }
        $firstWord = ($Command -split '\s+')[0]
        if ($result -match [regex]::Escape($firstWord)) {
            return $result
        }
        Start-Sleep -Milliseconds 300
    }
    return "$result`n[HINWEIS: Befehlsecho unvollstaendig angekommen, vermutlich durch gleichzeitige Trap-/Log-Meldungen des Switches gestoert - trotz $MaxAttempts Versuchen]"
}

# - HAUPTAUSFÜHRUNG
$summary = @()
$details = @()
$ergebnisListe = [System.Collections.Generic.List[object]]::new()

## Gerät nicht erreichbar bzw. Abfrage fehlgeschlagen: Ergebnis ohne Haken
function Add-SwFehler {
    param([string]$Ziel, [string]$Notiz)
    $ergebnisListe.Add([pscustomobject]@{ Ziel = $Ziel; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = $Notiz })
}

$SSHPort = 22

foreach ($ip in $ips) {
    Write-Host "`n→ Frage $ip ab..."

    # --- Vorab-Check: Ping ---
    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        Write-Host "STATUS          : Nicht erreichbar (Ping fehlgeschlagen)" -ForegroundColor Red
        $summary += "$ip`r`nNicht erreichbar (Ping fehlgeschlagen)`r`n"
        Add-SwFehler -Ziel $ip -Notiz 'Nicht erreichbar (Ping fehlgeschlagen)'
        continue
    }

    # --- Vorab-Check: SSH-Port ---
    $portCheck = Test-NetConnection -ComputerName $ip -Port $SSHPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $portCheck) {
        Write-Host "STATUS          : Ping OK, SSH-Port $SSHPort nicht erreichbar" -ForegroundColor Red
        $summary += "$ip`r`nPing OK, SSH-Port $SSHPort nicht erreichbar`r`n"
        Add-SwFehler -Ziel $ip -Notiz "SSH-Port $SSHPort nicht erreichbar"
        continue
    }

    # SSH-Session (bis zu 3 Anmeldeversuche, der 1. mit dem Konto aus dem NET-COCKPIT)
    $session = $null
    $loginFehler = ""
    for ($versuch = 1; $versuch -le 3 -and -not $session; $versuch++) {
        $cred = Get-ZielAnmeldung -Name $ip -Meldung "Zugangsdaten für Switch $ip (Versuch $versuch von 3)" -Versuch $versuch
        if (-not $cred) { $loginFehler = "Eingabe der Zugangsdaten abgebrochen"; break }
        try {
            $session = New-SSHSession -ComputerName $ip -Credential $cred -AcceptKey -ErrorAction Stop
        } catch {
            $loginFehler = $_.Exception.Message
            Write-Host "→ Anmeldung fehlgeschlagen (Versuch $versuch von 3)" -ForegroundColor Yellow
        }
    }
    if (-not $session) {
        Write-Host "STATUS          : SSH-Verbindung fehlgeschlagen (Login/Auth)" -ForegroundColor Red
        $summary += "$ip`r`nSSH-Login fehlgeschlagen: $loginFehler`r`n"
        Add-SwFehler -Ziel $ip -Notiz 'SSH-Anmeldung fehlgeschlagen'
        continue
    }

    try {
        $stream = New-SSHShellStream -SSHSession $session
    } catch {
        Write-Host "STATUS          : Shell-Stream konnte nicht geoeffnet werden" -ForegroundColor Red
        $summary += "$ip`r`nShell-Stream fehlgeschlagen: $($_.Exception.Message)`r`n"
        Add-SwFehler -Ziel $ip -Notiz 'Shell-Stream konnte nicht geöffnet werden'
        Remove-SSHSession -SSHSession $session | Out-Null
        continue
    }
    # Login-Banner/Prompt abholen, bevor Befehle gesendet werden
    Read-SwitchStream -Stream $stream -TimeoutSeconds 5 | Out-Null

    # In privilegierten Modus wechseln: am ">"-Prompt sind viele "show"-Befehle
    # gesperrt ("Invalid input"), erst im "#"-Modus verfuegbar.
    # ANNAHME: kein eigenes Enable-Passwort konfiguriert, es wird das SSH-Login-
    # Passwort erneut gesendet falls eines abgefragt wird - bei Bedarf anpassen.
    $enableOutput = Invoke-SwitchCommand -Stream $stream -Command "enable" -TimeoutSeconds 5
    if ($enableOutput -match '(?i)password') {
        $stream.WriteLine($cred.GetNetworkCredential().Password)
        Start-Sleep -Milliseconds 400
        Read-SwitchStream -Stream $stream -TimeoutSeconds 5 | Out-Null
    }

    # 1. Systeminfo / Firmware
    $verText = Invoke-SwitchCommand -Stream $stream -Command "show version"

    # 2. Konfigurationssicherung (Export running-config)
    $runningConfig = Invoke-SwitchCommand -Stream $stream -Command "show running-config"

    # 3. VLAN- / Portkonfiguration
    $vlanText = Invoke-SwitchCommand -Stream $stream -Command "show vlan"
    $switchportText = Invoke-SwitchCommand -Stream $stream -Command "show interfaces switchport"

    # 4. Interface-Status (Ist-Aufnahme)
    # "show port status" allein war "Incomplete command" - laut "show port ?"
    # braucht es ein Scope-Argument wie "all".
    $ifStatusText = Invoke-SwitchCommand -Stream $stream -Command "show port status all"

    # 5. Logauszug (Rohdaten, Zeitraum manuell pruefen - Format je nach Firmware unterschiedlich)
    $logText = Invoke-SwitchCommand -Stream $stream -Command "show logging buffered"

    # 6. Environment (Temperatur/Luefter/Netzteil)
    $envText = Invoke-SwitchCommand -Stream $stream -Command "show environment"

    # 7. PoE-Status (falls unterstuetzt, sonst Fehlermeldung des Switches im Rohtext)
    $poeText = Invoke-SwitchCommand -Stream $stream -Command "show poe"

    Remove-SSHSession -SSHSession $session | Out-Null

    # - Zusammenfassung (die 3 Kernfragen)
    $summary += "$ip"
    $summary += "1. Konfigurationssicherung erstellt: JA - running-config exportiert (siehe Detaildaten)"
    $summary += "2. Firmware-Update pruefen (aktuell?): aktuelle Version siehe Detaildaten - manueller Abgleich mit Netgear-Downloads erforderlich (keine automatisierte Versionspruefung moeglich)"
    $summary += "3. VLAN Portkonfiguration dokumentiert und aktuell?: VLAN-/Port-Config exportiert (siehe Detaildaten) - Abgleich mit vorhandener Dokumentation durch dich`r`n"

    # - Detaildaten
    $details += "============================================================="
    $details += "HOST: $ip"
    $details += "-------------------------------------------------------------"
    $details += "SHOW VERSION:"
    $details += $verText
    $details += "-------------------------------------------------------------"
    $details += "INTERFACE STATUS:"
    $details += $ifStatusText
    $details += "-------------------------------------------------------------"
    $details += "ENVIRONMENT (Temperatur/Luefter/Netzteil):"
    $details += $envText
    $details += "-------------------------------------------------------------"
    $details += "POE STATUS:"
    $details += $poeText
    $details += "-------------------------------------------------------------"
    $details += "VLAN-UEBERSICHT:"
    $details += $vlanText
    $details += "-------------------------------------------------------------"
    $details += "SWITCHPORT / PORT-VLAN-ZUORDNUNG:"
    $details += $switchportText
    $details += "-------------------------------------------------------------"
    $details += "LOGAUSZUG (Rohdaten, manuelle Pruefung auf Ereignisse der letzten 30 Tage):"
    $details += $logText
    $details += "-------------------------------------------------------------"
    $details += "RUNNING-CONFIG (Konfigurationssicherung):"
    $details += $runningConfig
    $details += "============================================================="

    ## Ergebnis für die Checkliste: Haken nur für die Konfigurationssicherung (running-config vollständig und ohne Fehlermeldung des Switches); Firmware-Aktualität und VLAN sind per CLI nicht belegbar
    if ($Automatik) {
        $sicherOrdner = Join-Path $LogPath 'configbackups'
        if (-not (Test-Path -LiteralPath $sicherOrdner)) { New-Item -ItemType Directory -Path $sicherOrdner -Force | Out-Null }
        $sicherDatei = Join-Path $sicherOrdner ("{0}_{1}_Backup.txt" -f ($ip -replace '[\\/:*?"<>|]', '_'), (Get-Date).ToString('yyMMdd'))
        $runningConfig | Out-File -FilePath $sicherDatei -Encoding utf8
        $backupOk = ($runningConfig -match '(?m)^!Current Configuration') -and ($runningConfig -notmatch '(?i)Invalid input|Incomplete command|FEHLER beim Ausfuehren|Befehlsecho unvollstaendig')
        $pr = [ordered]@{ KonfigSicherung = [bool]$backupOk }
        $vers = if ($verText -match '(?mi)^\s*(Software|Firmware|Machine)\S*\s*(Version)?[ .]*\s*(?<v>[0-9][^\r\n]*)$') { $Matches['v'].Trim() } else { $null }
        $werte = [ordered]@{
            Version       = $vers
            TemperaturRoh = @($envText -split '\r?\n' | Where-Object { $_ -match '(?i)temp' } | ForEach-Object { $_.Trim() })
        }
        $notizSw = $(if ($backupOk) { 'Konfigsicherung erstellt' } else { 'Konfigsicherung nicht eindeutig (Details prüfen)' })
        $ergebnisListe.Add([pscustomobject]@{ Ziel = $ip; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = $notizSw })
    }
}

# - LOGDATEI SCHREIBEN
Write-Host "`nLogdatei gespeichert unter: $LogFile" -ForegroundColor Cyan

@($summary; "============================================================="; $details) | Out-File -FilePath $LogFile -Encoding utf8

# - DATEI ÖFFNEN
if ($Automatik) {
    ## Konsole = Detail für den Techniker; die running-config liegt in configbackups\ und bleibt hier draußen
    $details | ForEach-Object { $_ } | Where-Object { $_ -ne $null } | Write-Host
    Write-WtErgebnis -Skript '08.2-Switche-Netgear' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}
Invoke-Item $LogFile
Write-Host "`nFertig."