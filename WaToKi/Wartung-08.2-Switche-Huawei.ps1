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
Write-Host "=== Wartung-08.2-Switche-Huawei ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
if (-not $Automatik) { Write-Host @'
BESCHREIBUNG
Prüft per SSH Huawei-Switche (S5720, VRP) auf Konfigsicherung, Firmware-Version und VLAN-/Port-Konfiguration und erstellt zusätzlich eine Ist-Aufnahme (Interface-Status, Logauszug, Lüfter, Netzteil, Temperatur, PoE).

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Switche (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Gerät das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfällt die Listenpflege und die Kontoabfrage. Ohne -Ziel läuft das Skript wie bisher interaktiv.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Posh-SSH-Modul: Install-Module Posh-SSH -Scope CurrentUser -Force
- SSH (STelnet) aktiviert auf dem Switch, erreichbar auf Port 22
- Benutzer mit Service-Type SSH und Privilege-Level 3 oder höher (kein enable-Modus bei VRP)
- CLI-Befehle für VRP V200R0xx (S5720) - bei abweichender Version Syntax vor Produktivbetrieb prüfen
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
$LogFile = "$LogPath\Wartung_$Timestamp`_Switche_Huawei.txt"

# - VERZEICHNIS KONFIGSICHERUNG
$BackupPath = "$LogPath\configbackups"
if (-not (Test-Path $BackupPath)) {
    Write-Host "→ Verzeichnis $BackupPath wird erstellt..."
    New-Item -ItemType Directory -Path $BackupPath | Out-Null
}
$BackupDatum = (Get-Date).ToString("yyMMdd")

# - HOSTLISTE VERWALTEN
if ($ZielModus) {
    $ips = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Geräte (aus dem NET-COCKPIT):"
    $ips | ForEach-Object { Write-Host " - $_" }
}
else {
    $HostListFile = "$LogPath\liste_switche.txt"
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
## Read-SwitchStream
# Huawei-VRP-Prompts: User-View "<Switchname>", System-View "[Switchname]".
# Befehl gilt als abgeschlossen, wenn der Prompt wieder am Ende steht UND
# 500 ms keine weiteren Daten nachkommen. Pager "---- More ----" wird mit
# Leerzeichen weitergeschaltet (Fallback, normal per screen-length 0 abgeschaltet).
function Read-SwitchStream {
    param($Stream, [int]$TimeoutSeconds = 20)
    $sb = New-Object System.Text.StringBuilder
    $start = Get-Date
    $lastData = Get-Date
    $promptRegex = '(?m)^[<\[][^\r\n<>\[\]]+[>\]]\s*$'
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        if ($Stream.DataAvailable) {
            $chunk = $Stream.Read()
            if ($chunk) {
                [void]$sb.Append($chunk)
                $lastData = Get-Date
                if ($chunk -match '(?i)(---- more ----|--more--|press any key)') {
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

## Invoke-SwitchCommand
# Vor dem Senden Alt-Daten verwerfen, danach prüfen ob der komplette Befehl
# im Echo auftaucht (Schutz gegen vermischte Log-Meldungen), bis zu 3 Versuche.
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
        if ($result -match [regex]::Escape($Command)) {
            return $result
        }
        Start-Sleep -Milliseconds 300
    }
    return "$result`n[HINWEIS: Befehlsecho unvollstaendig angekommen, vermutlich durch gleichzeitige Log-Meldungen des Switches gestoert - trotz $MaxAttempts Versuchen]"
}

## Format-SwitchOutput
# Bereinigt die Rohausgabe eines Befehls: Befehlsecho, Prompt-Zeilen, Trennlinien und Leerzeilen entfernen
function Format-SwitchOutput {
    param([string]$Text, [string]$Command)
    $zeilen = @()
    foreach ($zeile in ($Text -split '\r?\n')) {
        $z = $zeile.TrimEnd()
        if ($z -eq '') { continue }
        if ($z -eq $Command) { continue }
        if ($z -match '^[<\[][^\r\n<>\[\]]+[>\]]$') { continue }
        if ($z -match '^-{5,}$') { continue }
        $zeilen += $z
    }
    return ($zeilen -join "`r`n")
}

## Get-FilteredSwitchLog
# Filtert die Ausgabe von "display logbuffer" auf Eintraege der letzten $Days Tage
# mit Schweregrad Warnung oder kritischer (VRP-Severity 0-4, z.B. "%%01SSH/4/SSH_FAIL").
# Info/Notice/Debug (5-7) werden verworfen. Haeufige Rauschmeldungen (Port up/down,
# Rate-Schwellwerte) werden ausgeblendet und nur gezaehlt.
function Get-FilteredSwitchLog {
    param(
        [string]$LogText,
        [int]$Days = 30,
        [string[]]$Ausblenden = @('IF_STATE', 'PORTDOWNINFO', 'INT_OUTBRDR', 'INT_INBRDR')
    )
    $grenze = (Get-Date).AddDays(-$Days)
    $kultur = [System.Globalization.CultureInfo]::InvariantCulture
    $gesamt = 0
    $ausgeblendet = 0
    $treffer = @()
    foreach ($zeile in ($LogText -split '\r?\n')) {
        if ($zeile -notmatch '^(?<m>[A-Za-z]{3})\s+(?<d>\d{1,2})\s+(?<y>\d{4})\s+(?<t>\d{2}:\d{2}:\d{2})') { continue }
        $gesamt++
        $datumText = "$($Matches['m']) $($Matches['d']) $($Matches['y']) $($Matches['t'])"
        try {
            $zeit = [datetime]::ParseExact($datumText, "MMM d yyyy HH:mm:ss", $kultur)
        } catch {
            continue
        }
        if ($zeit -lt $grenze) { continue }
        if ($zeile -notmatch '%%\d+[^/\s]+/(?<sev>[0-7])/(?<mn>[A-Za-z0-9_]+)') { continue }
        $sev = [int]$Matches['sev']
        $mn = $Matches['mn']
        if ($sev -gt 4) { continue }
        if ($Ausblenden -contains $mn) {
            $ausgeblendet++
            continue
        }
        $treffer += $zeile.TrimEnd()
    }
    if ($gesamt -eq 0) {
        return "[HINWEIS: Keine auswertbaren Logeintraege gefunden - Rohausgabe:]`r`n$LogText"
    }
    $kopf = "Buffer: $gesamt Eintraege - Warnung/kritisch in den letzten $Days Tagen: $($treffer.Count + $ausgeblendet) - davon ausgeblendet (Port up/down, Rate-Schwellwerte): $ausgeblendet - angezeigt: $($treffer.Count)"
    if ($treffer.Count -eq 0) {
        return "$kopf`r`nKeine weiteren Warnungen oder kritischen Eintraege im Zeitraum."
    }
    return "$kopf`r`n" + ($treffer -join "`r`n")
}

## Get-InterfaceSummary
# Verdichtet "display interface brief": Anzahl Ports up/down, Eth-Trunks die nicht up sind,
# Ports mit Fehlerzaehlern
function Get-InterfaceSummary {
    param([string]$Text)
    $rx = '^\s*(?<if>\S+)\s+(?<phy>\S+)\s+(?<proto>\S+)\s+(?<inu>\S+)\s+(?<outu>\S+)\s+(?<ine>\d+)\s+(?<oute>\d+)\s*$'
    $gesamt = 0
    $up = 0
    $trunkProbleme = @()
    $fehler = @()
    foreach ($zeile in ($Text -split '\r?\n')) {
        if ($zeile -notmatch $rx) { continue }
        $name = $Matches['if']
        $phy = $Matches['phy']
        $ine = [long]$Matches['ine']
        $oute = [long]$Matches['oute']
        $physisch = $name -match '^X?GigabitEthernet'
        if ($physisch) {
            $gesamt++
            if ($phy -eq 'up') { $up++ }
        }
        if (($name -match '^Eth-Trunk') -and ($phy -ne 'up')) {
            $trunkProbleme += "$name ($phy)"
        }
        if ((($ine -gt 0) -or ($oute -gt 0)) -and (($physisch) -or ($name -match '^Eth-Trunk'))) {
            $fehler += "$name (inErrors: $ine, outErrors: $oute)"
        }
    }
    if ($gesamt -eq 0) {
        return (Format-SwitchOutput -Text $Text -Command "display interface brief")
    }
    $zeilen = @()
    $zeilen += "Physische Ports: $gesamt gesamt, $up up, $($gesamt - $up) down"
    if ($trunkProbleme.Count -eq 0) {
        $zeilen += "Eth-Trunks nicht up: keine"
    } else {
        $zeilen += "Eth-Trunks nicht up: " + ($trunkProbleme -join ", ")
    }
    if ($fehler.Count -eq 0) {
        $zeilen += "Ports mit Fehlerzaehlern: keine"
    } else {
        $zeilen += "Ports mit Fehlerzaehlern: " + ($fehler -join ", ")
    }
    return ($zeilen -join "`r`n")
}

## Get-PoeSummary
# Verdichtet "display poe power": nur Ports mit aktuellem Verbrauch. Gibt $null zurueck,
# wenn keine Port-Zeilen erkannt werden (z.B. Switch ohne PoE).
function Get-PoeSummary {
    param([string]$Text)
    $rx = '^\s*(?<p>\S*GigabitEthernet\S+)\s+(?<cls>\S+)\s+(?<ref>\S+)\s+(?<usm>\d+)\s+(?<cur>\d+)\s+(?<pk>\d+)\s+(?<avg>\d+)\s*$'
    $gefunden = 0
    $summe = 0
    $aktiv = @()
    foreach ($zeile in ($Text -split '\r?\n')) {
        if ($zeile -notmatch $rx) { continue }
        $gefunden++
        $cur = [long]$Matches['cur']
        if ($cur -gt 0) {
            $summe += $cur
            $aktiv += "$($Matches['p']): $cur mW (Klasse $($Matches['cls']))"
        }
    }
    if ($gefunden -eq 0) { return $null }
    $zeilen = @()
    $zeilen += "PoE-Ports: $gefunden gesamt, $($aktiv.Count) mit Verbrauch, Summe aktuell: $summe mW"
    $zeilen += $aktiv
    return ($zeilen -join "`r`n")
}

## Get-VlanSummary
# Verdichtet "display vlan": nur die VLAN-Liste (ID, Status, Name), ohne Port-Zuordnung
function Get-VlanSummary {
    param([string]$Text)
    $rx = '^(?<id>\d+)\s+(?<st>enable|disable)\s+\S+\s+\S+\s+\S+\s*(?<desc>.*?)\s*$'
    $zeilen = @()
    foreach ($zeile in ($Text -split '\r?\n')) {
        if ($zeile -notmatch $rx) { continue }
        $zeilen += "VLAN $($Matches['id']) ($($Matches['st'])): $($Matches['desc'])"
    }
    if ($zeilen.Count -eq 0) {
        return (Format-SwitchOutput -Text $Text -Command "display vlan")
    }
    return ($zeilen -join "`r`n")
}

## Join-PortRanges
# Fasst Portnummern zu Bereichen zusammen, z.B. 1,3,4,5 -> "1,3-5"
function Join-PortRanges {
    param([int[]]$Numbers)
    $sortiert = @($Numbers | Sort-Object -Unique)
    $teile = @()
    $start = $null
    $prev = $null
    foreach ($n in $sortiert) {
        if ($null -eq $start) {
            $start = $n
            $prev = $n
            continue
        }
        if ($n -eq ($prev + 1)) {
            $prev = $n
            continue
        }
        if ($start -eq $prev) { $teile += "$start" } else { $teile += "$start-$prev" }
        $start = $n
        $prev = $n
    }
    if ($null -ne $start) {
        if ($start -eq $prev) { $teile += "$start" } else { $teile += "$start-$prev" }
    }
    return ($teile -join ",")
}

## Get-PortVlanSummary
# Verdichtet "display port vlan": Ports mit gleicher Konfiguration (Typ, PVID, VLAN-Liste)
# werden zu einer Zeile zusammengefasst
function Get-PortVlanSummary {
    param([string]$Text)
    $rx = '^(?<p>[A-Za-z\-]+(?:\d+/\d+/)?)(?<n>\d+)\s+(?<type>\S+)\s+(?<pvid>\d+)\s*(?<list>.*?)\s*$'
    $gruppen = [ordered]@{}
    foreach ($zeile in ($Text -split '\r?\n')) {
        if ($zeile -notmatch $rx) { continue }
        $prefix = $Matches['p']
        $nummer = [int]$Matches['n']
        $key = "PVID $($Matches['pvid']), Typ $($Matches['type']), VLANs $($Matches['list'])"
        if (-not $gruppen.Contains($key)) {
            $gruppen[$key] = [ordered]@{}
        }
        if (-not $gruppen[$key].Contains($prefix)) {
            $gruppen[$key][$prefix] = [System.Collections.Generic.List[int]]::new()
        }
        $gruppen[$key][$prefix].Add($nummer)
    }
    if ($gruppen.Count -eq 0) {
        return (Format-SwitchOutput -Text $Text -Command "display port vlan")
    }
    $zeilen = @()
    foreach ($key in $gruppen.Keys) {
        $ports = @()
        foreach ($prefix in $gruppen[$key].Keys) {
            $kurz = $prefix -replace '^XGigabitEthernet', 'XGE' -replace '^GigabitEthernet', 'GE'
            $ports += ($kurz + (Join-PortRanges -Numbers $gruppen[$key][$prefix].ToArray()))
        }
        $zeilen += "$key : " + ($ports -join " ")
    }
    return ($zeilen -join "`r`n")
}

# - HAUPTAUSFÜHRUNG
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

    ## Vorab-Check: Ping
    if (-not (Test-Connection -ComputerName $ip -Count 1 -Quiet)) {
        Write-Host "STATUS          : Nicht erreichbar (Ping fehlgeschlagen)" -ForegroundColor Red
        $details += "HOST: $ip - FEHLER: Nicht erreichbar (Ping fehlgeschlagen)"
        Add-SwFehler -Ziel $ip -Notiz 'Nicht erreichbar (Ping fehlgeschlagen)'
        continue
    }

    ## Vorab-Check: SSH-Port
    $portCheck = Test-NetConnection -ComputerName $ip -Port $SSHPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $portCheck) {
        Write-Host "STATUS          : Ping OK, SSH-Port $SSHPort nicht erreichbar" -ForegroundColor Red
        $details += "HOST: $ip - FEHLER: Ping OK, SSH-Port $SSHPort nicht erreichbar"
        Add-SwFehler -Ziel $ip -Notiz "SSH-Port $SSHPort nicht erreichbar"
        continue
    }

    ## SSH-Session (bis zu 3 Anmeldeversuche)
    $session = $null
    $loginFehler = ""
    for ($versuch = 1; $versuch -le 3; $versuch++) {
        $cred = Get-ZielAnmeldung -Name $ip -Meldung "Zugangsdaten für Switch $ip (Versuch $versuch von 3)" -Versuch $versuch
        if (-not $cred) {
            $loginFehler = "Eingabe der Zugangsdaten abgebrochen"
            break
        }
        try {
            $session = New-SSHSession -ComputerName $ip -Credential $cred -AcceptKey -ErrorAction Stop
            break
        } catch {
            $loginFehler = $_.Exception.Message
            Write-Host "→ Anmeldung fehlgeschlagen (Versuch $versuch von 3)" -ForegroundColor Yellow
        }
    }
    if (-not $session) {
        Write-Host "STATUS          : SSH-Verbindung fehlgeschlagen (Login/Auth)" -ForegroundColor Red
        $details += "HOST: $ip - FEHLER: SSH-Login fehlgeschlagen: $loginFehler"
        Add-SwFehler -Ziel $ip -Notiz 'SSH-Anmeldung fehlgeschlagen'
        continue
    }

    try {
        $stream = New-SSHShellStream -SSHSession $session
    } catch {
        Write-Host "STATUS          : Shell-Stream konnte nicht geoeffnet werden" -ForegroundColor Red
        $details += "HOST: $ip - FEHLER: Shell-Stream fehlgeschlagen: $($_.Exception.Message)"
        Add-SwFehler -Ziel $ip -Notiz 'Shell-Stream konnte nicht geöffnet werden'
        Remove-SSHSession -SSHSession $session | Out-Null
        continue
    }
    # Login-Banner/Prompt abholen, bevor Befehle gesendet werden
    Read-SwitchStream -Stream $stream -TimeoutSeconds 5 | Out-Null

    ## Session vorbereiten
    # Pager abschalten und Log-Ausgabe auf dem Terminal unterdruecken (nur für diese Session)
    Invoke-SwitchCommand -Stream $stream -Command "screen-length 0 temporary" -TimeoutSeconds 5 | Out-Null
    Invoke-SwitchCommand -Stream $stream -Command "undo terminal monitor" -TimeoutSeconds 5 | Out-Null

    ## Abfragen
    # 1. Systeminfo / Firmware
    $verText = Invoke-SwitchCommand -Stream $stream -Command "display version"

    # 2. Konfigurationssicherung
    $runningConfig = Invoke-SwitchCommand -Stream $stream -Command "display current-configuration" -TimeoutSeconds 60

    # 3. VLAN- / Portkonfiguration
    $vlanText = Invoke-SwitchCommand -Stream $stream -Command "display vlan"
    $switchportText = Invoke-SwitchCommand -Stream $stream -Command "display port vlan"

    # 4. Interface-Status (Ist-Aufnahme)
    $ifStatusText = Invoke-SwitchCommand -Stream $stream -Command "display interface brief"

    # 5. Logauszug (Rohdaten, Zeitraum manuell pruefen)
    $logText = Invoke-SwitchCommand -Stream $stream -Command "display logbuffer" -TimeoutSeconds 40

    # 6. Environment (Temperatur/Luefter/Netzteil)
    $tempText = Invoke-SwitchCommand -Stream $stream -Command "display temperature all"
    $fanText = Invoke-SwitchCommand -Stream $stream -Command "display fan"
    $powerText = Invoke-SwitchCommand -Stream $stream -Command "display power"
    $envText = "TEMPERATUR:`r`n$tempText`r`nLUEFTER:`r`n$fanText`r`nNETZTEIL:`r`n$powerText"

    # 7. PoE-Status (nur PoE-Modelle, sonst Fehlermeldung des Switches im Rohtext)
    $poeText = Invoke-SwitchCommand -Stream $stream -Command "display poe power"

    Remove-SSHSession -SSHSession $session | Out-Null

    ## Konfigurationssicherung in eigene Datei
    # Dateiname: <Switchname>_yyMMdd_Backup.txt - Switchname aus "sysname" der Konfiguration,
    # ist keiner vorhanden, wird die IP-Adresse verwendet
    $switchName = $null
    if ($runningConfig -match '(?m)^\s*sysname\s+(\S+)') {
        $switchName = $Matches[1]
    }
    if ([string]::IsNullOrWhiteSpace($switchName)) {
        $switchName = $ip
    }
    $switchName = $switchName -replace '[\\/:*?"<>|]', '_'
    $BackupFile = "$BackupPath\$switchName`_$BackupDatum`_Backup.txt"

    # Konfiguration gilt als vollstaendig, wenn sie mit "return" endet
    $backupOk = $runningConfig -match '(?m)^return\s*$'
    $runningConfig | Out-File -FilePath $BackupFile -Encoding utf8
    if ($backupOk) {
        Write-Host "→ Konfigurationssicherung gespeichert: $BackupFile" -ForegroundColor Green
    } else {
        Write-Host "→ Konfigurationssicherung gespeichert, aber moeglicherweise unvollstaendig: $BackupFile" -ForegroundColor Yellow
    }

    ## Detaildaten
    $details += "============================================================="
    $details += "HOST: $ip ($switchName)"
    if (-not $backupOk) {
        $details += "WARNUNG: Konfigurationssicherung moeglicherweise unvollstaendig (Ende 'return' nicht gefunden): $BackupFile"
    }
    $details += "-------------------------------------------------------------"
    $details += "VERSION:"
    $details += Format-SwitchOutput -Text $verText -Command "display version"
    $details += "-------------------------------------------------------------"
    $details += "INTERFACES:"
    $details += Get-InterfaceSummary -Text $ifStatusText
    $details += "-------------------------------------------------------------"
    $details += "ENVIRONMENT:"
    $details += "Temperatur:"
    $details += Format-SwitchOutput -Text $tempText -Command "display temperature all"
    $details += "Luefter:"
    $details += Format-SwitchOutput -Text $fanText -Command "display fan"
    $details += "Netzteil:"
    $details += Format-SwitchOutput -Text $powerText -Command "display power"
    $details += "-------------------------------------------------------------"
    $details += "POE:"
    $poeKurz = Get-PoeSummary -Text $poeText
    if ($null -eq $poeKurz) {
        $poeKurz = Format-SwitchOutput -Text $poeText -Command "display poe power"
    }
    $details += $poeKurz
    $details += "-------------------------------------------------------------"
    $details += "VLANS:"
    $details += Get-VlanSummary -Text $vlanText
    $details += "-------------------------------------------------------------"
    $details += "PORT-VLAN-ZUORDNUNG:"
    $details += Get-PortVlanSummary -Text $switchportText
    $details += "-------------------------------------------------------------"
    $details += "LOGAUSZUG (nur Warnung und kritisch, letzte 30 Tage):"
    $details += Get-FilteredSwitchLog -LogText $logText -Days 30

    ## Ergebnis für die Checkliste: Haken nur für die Konfigurationssicherung (Konfiguration vollständig gesichert); Firmware-Aktualität und VLAN sind per CLI nicht belegbar
    $pr = [ordered]@{ KonfigSicherung = [bool]$backupOk }
    $vrp = if ($verText -match '(?m)^\s*VRP.*?Version\s+(?<v>.+?)\s*$') { $Matches['v'] } else { $null }
    $ifKurz = (Get-InterfaceSummary -Text $ifStatusText -split '\r?\n' | Select-Object -First 1)
    $werte = [ordered]@{
        Switchname   = $switchName
        Version      = $vrp
        Ports        = $ifKurz
        TemperaturRoh = @((Format-SwitchOutput -Text $tempText -Command "display temperature all") -split '\r?\n')
    }
    $notizSw = $(if ($backupOk) { 'Konfigsicherung erstellt' } else { 'Konfigsicherung evtl. unvollständig' })
    if ($ifKurz) { $notizSw += "; $ifKurz" }
    $ergebnisListe.Add([pscustomobject]@{ Ziel = $ip; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = $notizSw })
}

# - LOGDATEI SCHREIBEN
Write-Host "`nLogdatei gespeichert unter: $LogFile" -ForegroundColor Cyan

$details | Out-File -FilePath $LogFile -Encoding utf8

# - DATEI ÖFFNEN
if ($Automatik) {
    $details | Write-Host
    Write-WtErgebnis -Skript '08.2-Switche-Huawei' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}
Invoke-Item $LogFile
Write-Host "`nFertig."