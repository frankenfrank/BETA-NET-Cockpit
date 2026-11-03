# NET-COCKPIT-Modul-TREIBER.ps1
<#
.SYNOPSIS
    Modul TREIBER-Updates für das NET-COCKPIT (Menü Module > TREIBER)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und wirkt auf die markierten, grünen Geräte der Tabelle.
    Erkennt den PC-Hersteller je Gerät und nutzt dessen Tool: Dell Command | Update, HP Image Assistant, Lenovo LSUClient. Andere Hersteller: "nicht unterstützt".
    - Status prüfen: PC-Hersteller und Modell, Windows-Version, Neustart, Akku, Treiber-Tool, verfügbare Treiber-Updates, Verlauf
    - Treiber-Updates installieren (still, nie automatischer Neustart), optional mit BIOS/Firmware
    - Treiber-Tool nachinstallieren (Dell: WinGet, HP: HPCMSL, Lenovo: LSUClient); danach läuft automatisch Status prüfen
    - Details je Gerät: verfügbare Treiber, Verlauf, Tool-Log und Log
    Verbindung, Konten, Warteschlange, Neustart, Neustart planen, OU-Import, Liste und KuDo-Info kommen aus dem NET-COCKPIT.
    Log je Gerät: C:\Temp\NET-COCKPIT_data\Modul-TREIBER\yyyyMMdd_Gerät_treiber-log.txt
#>

# Einstellungen
## Ordner und Zustand
$script:TrLogOrdner = Join-Path $script:DatenOrdner 'Modul-TREIBER'
$script:TrSync = [System.Collections.Generic.Dictionary[object, object]]::new()
$script:TrFenster = $null
$script:TrChkBios = $null

## Spalten (nur sichtbar, wenn im Modulfenster der Haken "Spalten des Moduls in der Tabelle anzeigen" gesetzt ist); Windows, Neustart ausstehend und Letzter Neustart teilen sich alle Update-Module
New-WolSpalte -Key 'Windows' -Titel 'Windows' -Eig '[Windows]' -Breite 270 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'NeustartAusstehend' -Titel 'Neustart ausstehend' -Eig '[NeustartAusstehend]' -Breite 125 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'LetzterNeustart' -Titel 'Letzter Neustart' -Eig '[LetzterNeustart]' -Breite 125 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'TrHersteller' -Titel 'PC-Hersteller' -Eig '[TrHersteller]' -Breite 90 -Sichtbar $false -Modul 'TREIBER'
New-WolSpalte -Key 'TrModell' -Titel 'Modell' -Eig '[TrModell]' -Breite 170 -Sichtbar $false -Modul 'TREIBER'
New-WolSpalte -Key 'TrTool' -Titel 'Treiber-Tool' -Eig '[TrTool]' -Breite 90 -Sichtbar $false -Modul 'TREIBER'
New-WolSpalte -Key 'TrUpdates' -Titel 'Treiber-Updates' -Eig '[TrUpdates]' -Breite 100 -Sichtbar $false -Modul 'TREIBER'

# Skripte, die auf dem Zielgerät als geplante Aufgabe laufen (Windows PowerShell 5.1, als SYSTEM)
## Platzhalter: __MITBIOS__ ($true/$false, setzt der Job) und __ERSETZEN__ (Tool-Skript, immer $true)
## Gemeinsame Bibliothek (Herstellererkennung, Suche und Installation je Hersteller)
$script:TrLib = @'
$mitBios       = __MITBIOS__
if (-not (Test-Path -Path 'C:\ProgramData\NET-COCKPIT') -and (Test-Path -Path 'C:\ProgramData\WaToKi')) { Rename-Item -Path 'C:\ProgramData\WaToKi' -NewName 'NET-COCKPIT' -ErrorAction SilentlyContinue }
$ordnerDaten   = 'C:\ProgramData\NET-COCKPIT'
$verlaufDatei  = 'C:\ProgramData\NET-COCKPIT\TreiberVerlauf.csv'
$toolLogDatei  = 'C:\ProgramData\NET-COCKPIT\TreiberToolLog.txt'
$hpiaOrdner    = 'C:\ProgramData\NET-COCKPIT\HPIA'

if (-not (Test-Path -Path $ordnerDaten)) { New-Item -ItemType Directory -Path $ordnerDaten -Force | Out-Null }
if ((Test-Path -Path $toolLogDatei) -and ((Get-Item -Path $toolLogDatei).Length -gt 1MB)) {
    $alt = @(Get-Content -Path $toolLogDatei -Tail 2000 -Encoding UTF8)
    Set-Content -Path $toolLogDatei -Value $alt -Encoding UTF8
}

### Zeile ins Live-Log (falls gesetzt) und ins dauerhafte Tool-Log schreiben
function Write-Zeile {
    param([string]$Text)
    if ($log) { Add-Content -Path $log -Encoding utf8 -Value $Text -ErrorAction SilentlyContinue }
    Add-Content -Path $toolLogDatei -Encoding utf8 -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) -ErrorAction SilentlyContinue
}

### Eine Zeile in den Verlauf schreiben (Datum;Hersteller;Name;Id;Version;Ergebnis)
function Add-Verlauf {
    param($Hersteller, $Name, $Id, $Version, $Ergebnis)
    try {
        $zeile = '{0};{1};{2};{3};{4};{5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ([string]$Hersteller -replace '[;\r\n]', ' '), ([string]$Name -replace '[;\r\n]', ' '), ([string]$Id -replace '[;\r\n]', ' '), ([string]$Version -replace '[;\r\n]', ' '), ([string]$Ergebnis -replace '[;\r\n]', ' ')
        Add-Content -Path $verlaufDatei -Encoding utf8 -Value $zeile
    }
    catch { }
}

### Wert aus einem Objekt lesen (erster vorhandener Name aus der Liste)
function Get-Wert {
    param($Objekt, [string[]]$Namen)
    foreach ($n in $Namen) {
        $v = $Objekt.$n
        if ($null -ne $v -and ([string]$v) -ne '') { return [string]$v }
    }
    return ''
}

### Hersteller und Modell ermitteln
function Get-HerstellerInfo {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $m = [string]$cs.Manufacturer
    $h = 'Andere'
    if ($m -match 'Dell')                                { $h = 'Dell' }
    elseif ($m -match '^(HP|HP Inc\.?|Hewlett-Packard)$') { $h = 'HP' }
    elseif ($m -match 'LENOVO')                          { $h = 'Lenovo' }
    $modell = [string]$cs.Model
    if ($h -eq 'Lenovo') {
        $v = [string](Get-CimInstance -ClassName Win32_ComputerSystemProduct).Version
        if ($v) { $modell = $v }
    }
    [pscustomobject]@{ Hersteller = $h; HerstellerRoh = $m; Modell = $modell }
}

### Pfade der Hersteller-Tools
function Get-DcuPfad {
    foreach ($p in @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe")) {
        if (Test-Path -Path $p) { return $p }
    }
    return $null
}
function Get-HpiaPfad {
    $f = Get-ChildItem -Path $hpiaOrdner -Recurse -Filter 'HPImageAssistant.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

### Dell: Hilfsfunktionen für das DCU-Log (dcu-cli lehnt -report und -outputLog auf dem Testgerät mit Code 107 ab, deshalb wird das DCU-eigene Log ausgewertet)
$dcuLogPfad = 'C:\ProgramData\Dell\UpdateService\Log\Service.log'

### Zeitstempel einer DCU-Logzeile lesen, z. B. [26-10-15 15:52:51]
function ConvertTo-DcuZeit {
    param([string]$Zeile)
    if ($Zeile -match '^\[(\d\d-\d\d-\d\d \d\d:\d\d:\d\d)\]') {
        return [datetime]::ParseExact($Matches[1], 'yy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
    }
    return $null
}

### DCU-Log lesen, umgebrochene Einträge wieder zu einer Zeile zusammensetzen
function Get-DcuLogZeilen {
    param([int]$Anzahl = 4000)
    $roh = @(Get-Content -Path $dcuLogPfad -Tail $Anzahl -Encoding UTF8)
    $fertig = New-Object System.Collections.Generic.List[string]
    foreach ($z in $roh) {
        if ($z -match '^\[\d\d-\d\d-\d\d \d\d:\d\d:\d\d\]' -or $fertig.Count -eq 0) { $fertig.Add($z) }
        else { $fertig[$fertig.Count - 1] = $fertig[$fertig.Count - 1] + $z }
    }
    return @($fertig.ToArray())
}

### Dell: Treiber-Liste per dcu-cli /scan, ausgewertet aus dem DCU-Log
function Get-ListeDell {
    $dcu = Get-DcuPfad
    if (-not $dcu) { return [pscustomobject]@{ Fehler = 'Dell Command | Update fehlt'; Liste = @(); Roh = $null } }
    $typ = if ($mitBios) { 'bios,firmware,driver' } else { 'driver' }
    $argumente = "/scan -silent -updateType=$typ"
    Write-Zeile "dcu-cli $argumente"
    $start = Get-Date
    $p = Start-Process -FilePath $dcu -ArgumentList $argumente -Wait -PassThru -WindowStyle Hidden
    Write-Zeile "dcu-cli Scan beendet, Code $($p.ExitCode)"
    if ($p.ExitCode -eq 500) { return [pscustomobject]@{ Fehler = ''; Liste = @(); Roh = $null } }
    if ($p.ExitCode -ne 0) { return [pscustomobject]@{ Fehler = "Dell-Scan fehlgeschlagen, Code $($p.ExitCode)"; Liste = @(); Roh = $null } }
    if (-not (Test-Path -Path $dcuLogPfad)) { return [pscustomobject]@{ Fehler = "DCU-Log nicht gefunden ($dcuLogPfad)"; Liste = @(); Roh = $null } }
    Start-Sleep -Seconds 2

    ### Letzten Filter-Eintrag dieses Scans suchen (danach folgt die endgültige Liste)
    $zeilen = @(Get-DcuLogZeilen)
    $idx = -1
    for ($i = $zeilen.Count - 1; $i -ge 0; $i--) {
        if ($zeilen[$i] -match 'total updates after applying filter') { $idx = $i; break }
    }
    if ($idx -lt 0) { return [pscustomobject]@{ Fehler = 'Im DCU-Log wurde kein Scan-Ergebnis gefunden'; Liste = @(); Roh = $null } }
    $zeit = ConvertTo-DcuZeit $zeilen[$idx]
    if ($zeit -and $zeit -lt $start.AddSeconds(-10)) { return [pscustomobject]@{ Fehler = 'Im DCU-Log fehlt das Ergebnis dieses Scans (nur ältere Einträge vorhanden)'; Liste = @(); Roh = $null } }
    if ($zeilen[$idx] -match '(\d+) total updates after applying filter' -and [int]$Matches[1] -eq 0) { return [pscustomobject]@{ Fehler = ''; Liste = @(); Roh = $null } }

    ### Einträge nach dem Filter-Eintrag einlesen
    $muster = '\{[^}]*\}\s+\[\d+\]\s+(?<ref>\w+),\s+(?<id>\w+),\s+(?<name>.+?),\s+(?<ver>[^,\s]+),\s+Inventoried = (?<inv>\w+),\s+Inventory Version = (?<invver>.+?),\s+RequiresPowerAdapter = (?<pwr>\w+)\s*$'
    $liste = @()
    $kopfGefunden = $false
    for ($i = $idx + 1; $i -lt $zeilen.Count; $i++) {
        if ($zeilen[$i] -match 'There are \[\d+\] updates') {
            if ($kopfGefunden) { break }
            $kopfGefunden = $true
            continue
        }
        if (-not $kopfGefunden) { continue }
        if ($zeilen[$i] -match $muster) {
            $liste += [pscustomobject]@{
                Name    = $Matches['name']
                Id      = $Matches['id']
                Typ     = $(if ($Matches['inv'] -eq 'True') { 'inventarisiert' } else { 'nicht inventarisiert' })
                Version = $(if ($Matches['invver'] -eq 'empty') { $Matches['ver'] } else { "$($Matches['invver']) -> $($Matches['ver'])" })
            }
        }
        else { break }
    }
    if ($liste.Count -eq 0) { return [pscustomobject]@{ Fehler = 'Im DCU-Log wurde keine Update-Liste erkannt'; Liste = @(); Roh = $null } }

    ### Nicht inventarisierte Katalog-Einträge meldet dcu-cli selbst nicht (Konsole zeigt nur inventarisierte), deshalb werden sie nicht übernommen
    $ignoriert = @($liste | Where-Object { $_.Typ -eq 'nicht inventarisiert' }).Count
    if ($ignoriert -gt 0) {
        Write-Zeile "$ignoriert nicht inventarisierte Katalog-Einträge ignoriert (von dcu-cli nicht gemeldet)"
        $liste = @($liste | Where-Object { $_.Typ -eq 'inventarisiert' })
    }
    return [pscustomobject]@{ Fehler = ''; Liste = $liste; Roh = $null }
}

### HP: Treiber-Liste per HP Image Assistant (Analyze, Action List)
function Get-ListeHP {
    $hpia = Get-HpiaPfad
    if (-not $hpia) { return [pscustomobject]@{ Fehler = 'HP Image Assistant fehlt'; Liste = @(); Roh = $null } }
    $ordner = 'C:\Windows\Temp\NetCockpitTreiberHpiaReport'
    if (Test-Path -Path $ordner) { Remove-Item -Path $ordner -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
    $kat = if ($mitBios) { 'Drivers,Firmware,BIOS' } else { 'Drivers' }
    $argumente = "/Operation:Analyze /Category:$kat /Selection:All /Action:List /Silent /ReportFolder:$ordner"
    Write-Zeile "HPImageAssistant $argumente"
    $p = Start-Process -FilePath $hpia -ArgumentList $argumente -Wait -PassThru -WindowStyle Hidden
    Write-Zeile "HPImageAssistant Analyse beendet, Code $($p.ExitCode)"
    if ($p.ExitCode -notin 0, 256, 257) { return [pscustomobject]@{ Fehler = "HP-Analyse fehlgeschlagen, Code $($p.ExitCode)"; Liste = @(); Roh = $null } }
    $liste = @()
    $gefunden = $false
    $json = Get-ChildItem -Path $ordner -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($json) {
        $gefunden = $true
        $j = Get-Content -Path $json.FullName -Raw | ConvertFrom-Json
        foreach ($r in @($j.HPIA.Recommendations)) {
            if (-not $r) { continue }
            $liste += [pscustomobject]@{
                Name    = Get-Wert $r @('Name', 'Title')
                Id      = Get-Wert $r @('SoftpaqId', 'SoftPaqId', 'Id')
                Typ     = Get-Wert $r @('TargetType', 'Category', 'ReleaseType')
                Version = Get-Wert $r @('Version')
            }
        }
    }
    else {
        $xmlDatei = Get-ChildItem -Path $ordner -Recurse -Filter '*.xml' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($xmlDatei) {
            $gefunden = $true
            [xml]$xml = Get-Content -Path $xmlDatei.FullName -Raw
            foreach ($r in @($xml.SelectNodes('//Recommendation'))) {
                if (-not $r) { continue }
                $liste += [pscustomobject]@{
                    Name    = Get-Wert $r @('Name', 'Title')
                    Id      = Get-Wert $r @('SoftpaqId', 'Id')
                    Typ     = Get-Wert $r @('TargetType', 'Category', 'ReleaseType')
                    Version = Get-Wert $r @('Version')
                }
            }
        }
    }
    if (-not $gefunden -and $p.ExitCode -eq 0) { return [pscustomobject]@{ Fehler = 'HP-Analyse ohne Report (Datei nicht gefunden)'; Liste = @(); Roh = $null } }
    return [pscustomobject]@{ Fehler = ''; Liste = $liste; Roh = $null }
}

### Lenovo: Treiber-Liste per LSUClient (nur unbeaufsichtigt installierbare Pakete)
function Get-ListeLenovo {
    if (-not (Get-Module -ListAvailable -Name LSUClient)) { return [pscustomobject]@{ Fehler = 'LSUClient fehlt'; Liste = @(); Roh = $null } }
    Import-Module LSUClient -ErrorAction Stop
    $upd = @(Get-LSUpdate | Where-Object { $_.Installer.Unattended })
    if (-not $mitBios) {
        $upd = @($upd | Where-Object {
            ([string]$_.Type) -notmatch 'BIOS|Firmware' -and
            ([string]$_.Category) -notmatch 'BIOS|UEFI|Firmware' -and
            ([string]$_.Title) -notmatch 'BIOS|UEFI'
        })
    }
    $liste = @()
    foreach ($u in $upd) {
        $t = [string]$u.Type
        if (-not $t) { $t = [string]$u.Category }
        $liste += [pscustomobject]@{ Name = [string]$u.Title; Id = [string]$u.ID; Typ = $t; Version = [string]$u.Version }
    }
    return [pscustomobject]@{ Fehler = ''; Liste = $liste; Roh = $upd }
}

### Liste je Hersteller holen
function Get-TreiberListe {
    param([string]$Hersteller)
    switch ($Hersteller) {
        'Dell'   { return (Get-ListeDell) }
        'HP'     { return (Get-ListeHP) }
        'Lenovo' { return (Get-ListeLenovo) }
        default  { return [pscustomobject]@{ Fehler = 'Hersteller nicht unterstützt'; Liste = @(); Roh = $null } }
    }
}

### Dell: Installation per dcu-cli /applyUpdates (kein automatischer Neustart)
function Install-TreiberDell {
    $dcu = Get-DcuPfad
    $typ = if ($mitBios) { 'bios,firmware,driver' } else { 'driver' }
    $argumente = "/applyUpdates -updateType=$typ -silent -reboot=disable"
    Write-Zeile "dcu-cli $argumente"
    $start = Get-Date
    $p = Start-Process -FilePath $dcu -ArgumentList $argumente -Wait -PassThru -WindowStyle Hidden
    $code = $p.ExitCode

    ### Fehler und Warnungen dieses Laufs aus dem DCU-Log übernehmen (Format ->ERROR bzw. ->WARN angenommen)
    try {
        if (Test-Path -Path $dcuLogPfad) {
            $n = 0
            foreach ($z in @(Get-DcuLogZeilen)) {
                $t = ConvertTo-DcuZeit $z
                if ($t -and $t -ge $start.AddSeconds(-5) -and $z -match '->(ERROR|WARN|WARNING|FATAL)\}' -and $n -lt 50) {
                    Write-Zeile ('  ' + $z.Trim())
                    $n++
                }
            }
        }
    }
    catch { Write-Zeile ('  DCU-Log nicht lesbar: ' + $_.Exception.Message) }

    $neustart = ($code -in 1, 5)
    $ok = ($code -in 0, 1, 5, 500)
    $text = if ($code -eq 0) { 'Ok' } elseif ($neustart) { "Ok, Neustart nötig (Code $code)" } elseif ($code -eq 500) { 'Keine Updates' } else { "Fehler, Code $code" }
    return [pscustomobject]@{ Ok = $ok; Neustart = $neustart; Text = $text; Einzel = $null }
}

### HP: Installation per HP Image Assistant (kein automatischer Neustart durch das Cockpit)
function Install-TreiberHP {
    $hpia = Get-HpiaPfad
    $ordner = 'C:\Windows\Temp\NetCockpitTreiberHpiaReport'
    $laden  = 'C:\Windows\Temp\NetCockpitTreiberHpiaDownload'
    if (Test-Path -Path $ordner) { Remove-Item -Path $ordner -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
    New-Item -ItemType Directory -Path $laden -Force | Out-Null
    $kat = if ($mitBios) { 'Drivers,Firmware,BIOS' } else { 'Drivers' }
    $argumente = "/Operation:Analyze /Category:$kat /Selection:All /Action:Install /Silent /AutoCleanup /ReportFolder:$ordner /SoftpaqDownloadFolder:$laden"
    Write-Zeile "HPImageAssistant $argumente"
    $p = Start-Process -FilePath $hpia -ArgumentList $argumente -Wait -PassThru -WindowStyle Hidden
    $code = $p.ExitCode
    $neustart = ($code -eq 3010)
    $ok = ($code -in 0, 256, 257, 3010)
    $text = if ($code -eq 0) { 'Ok' } elseif ($neustart) { "Ok, Neustart nötig (Code $code)" } elseif ($code -in 256, 257) { 'Keine Updates' } else { "Fehler, Code $code" }
    return [pscustomobject]@{ Ok = $ok; Neustart = $neustart; Text = $text; Einzel = $null }
}

### Lenovo: Installation per LSUClient (Einzelergebnisse je Paket)
function Install-TreiberLenovo {
    param($Roh)
    Import-Module LSUClient -ErrorAction Stop
    $alles = @($Roh | Install-LSUpdate -Verbose 4>&1)
    $einzel = @()
    $fehler = 0
    $neustart = $false
    foreach ($r in $alles) {
        if ($r -is [System.Management.Automation.VerboseRecord]) { Write-Zeile ('  ' + $r.Message); continue }
        if ($null -eq $r) { continue }
        $erfolg = $true
        if ($r.PSObject.Properties['Success']) { $erfolg = [bool]$r.Success }
        $offen = [string]$r.PendingAction
        if ($offen -match 'REBOOT') { $neustart = $true }
        if (-not $erfolg) { $fehler++ }
        $grund = [string]$r.FailureReason
        $einzel += [pscustomobject]@{
            Name     = Get-Wert $r @('Title', 'Name')
            Id       = Get-Wert $r @('ID', 'Id')
            Version  = Get-Wert $r @('Version')
            Ergebnis = $(if ($erfolg) { if ($offen) { "Ok, offen: $offen" } else { 'Ok' } } else { "Fehler: $grund" })
        }
    }
    $text = if ($fehler -gt 0) { "$fehler Pakete mit Fehler" } elseif ($neustart) { 'Ok, Neustart nötig' } else { 'Ok' }
    return [pscustomobject]@{ Ok = ($fehler -eq 0); Neustart = $neustart; Text = $text; Einzel = $einzel }
}
'@

## Suche (Liste, Verlauf und Tool-Log als JSON)
$script:TrSuchHaupt = @'
$out = 'C:\Windows\Temp\NetCockpitTreiberSuche.json'
$log = 'C:\Windows\Temp\NetCockpitTreiberSuche.log'
try {
    $info = Get-HerstellerInfo
    $r = Get-TreiberListe -Hersteller $info.Hersteller

    ### Verlauf der Installationen durch das Cockpit (letzte 50 Einträge, neueste zuerst)
    $verlauf = New-Object System.Collections.Generic.List[object]
    if (Test-Path -Path $verlaufDatei) {
        foreach ($zeile in @(Get-Content -Path $verlaufDatei -Encoding UTF8 | Select-Object -Last 50)) {
            $t = @($zeile -split ';')
            if ($t.Count -ge 6) {
                $verlauf.Add([pscustomobject]@{ Datum = $t[0]; Hersteller = $t[1]; Name = $t[2]; Id = $t[3]; Version = $t[4]; Ergebnis = $t[5] })
            }
        }
    }
    $verlauf.Reverse()

    ### Tool-Log (letzte 200 Zeilen)
    $toolLog = @()
    if (Test-Path -Path $toolLogDatei) { $toolLog = @(Get-Content -Path $toolLogDatei -Tail 200 -Encoding UTF8) }

    $erg = [pscustomobject]@{
        Fehler     = [string]$r.Fehler
        Hersteller = $info.Hersteller
        Modell     = $info.Modell
        Updates    = @($r.Liste)
        Verlauf    = @($verlauf.ToArray())
        ToolLog    = @($toolLog)
    }
}
catch {
    $erg = [pscustomobject]@{ Fehler = ($_ | Out-String).Trim(); Hersteller = ''; Modell = ''; Updates = @(); Verlauf = @(); ToolLog = @() }
}
$erg | ConvertTo-Json -Depth 4 | Set-Content -Path $out -Encoding UTF8
'@

## Installation (kein automatischer Neustart)
$script:TrInstallHaupt = @'
$log = 'C:\Windows\Temp\NetCockpitTreiberInstall.log'
$fehlerAnzahl = 0
try {
    $info = Get-HerstellerInfo
    Write-Zeile ("Hersteller: {0}, Modell: {1}, BIOS/Firmware einbezogen: {2}" -f $info.Hersteller, $info.Modell, $mitBios)

    $r = Get-TreiberListe -Hersteller $info.Hersteller
    if ($r.Fehler) {
        Write-Zeile ("Fehler: {0}" -f $r.Fehler)
        exit 1
    }
    $liste = @($r.Liste)
    Write-Zeile ("{0} Treiber-Updates gefunden" -f $liste.Count)
    foreach ($u in $liste) { Write-Zeile ("  {0} | {1} | {2} | {3}" -f $u.Name, $u.Id, $u.Typ, $u.Version) }
    if ($liste.Count -eq 0) {
        Write-Zeile 'Nichts zu installieren'
        exit 0
    }

    switch ($info.Hersteller) {
        'Dell'   { $i = Install-TreiberDell }
        'HP'     { $i = Install-TreiberHP }
        'Lenovo' { $i = Install-TreiberLenovo -Roh $r.Roh }
    }

    ### Verlauf schreiben
    if ($i.Einzel) {
        foreach ($e in @($i.Einzel)) { Add-Verlauf $info.Hersteller $e.Name $e.Id $e.Version $e.Ergebnis }
    }
    else {
        foreach ($u in $liste) { Add-Verlauf $info.Hersteller $u.Name $u.Id $u.Version $i.Text }
    }

    Write-Zeile ("  Ergebnis: {0}, Neustart nötig: {1}" -f $i.Text, $i.Neustart)
    if (-not $i.Ok) { $fehlerAnzahl++ }
}
catch {
    Write-Zeile ("Fehler: {0}" -f $_.Exception.Message)
    exit 1
}
if ($fehlerAnzahl -gt 0) { exit 1 }
'@

## Nachinstallation des Treiber-Tools je Hersteller
$script:TrToolHaupt = @'
$log = 'C:\Windows\Temp\NetCockpitTreiberTool.log'
try {
    $info = Get-HerstellerInfo
    Write-Zeile ("Hersteller: {0}, Modell: {1}" -f $info.Hersteller, $info.Modell)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    switch ($info.Hersteller) {

        ### Dell: Dell Command | Update per WinGet
        'Dell' {
            $w = @(Get-Item -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending) | Select-Object -First 1
            if (-not $w) {
                Write-Zeile 'WinGet (App Installer) fehlt auf dem Rechner, Dell Command | Update kann nicht installiert werden'
                exit 1
            }
            $ersetzen = __ERSETZEN__

            ## Inkompatible Dell-Update-Produkte suchen (blockieren den MSI-Installer, Fehler 1602)
            function Get-DellAltprodukte {
                $liste = @()
                $reg = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
                foreach ($p in @(Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue)) {
                    $dn = [string]$p.DisplayName
                    if ($dn -match '^Dell Update$' -or $dn -match '^Dell Update for Windows' -or $dn -match '^Dell Command \| Update for Windows') {
                        $liste += [pscustomobject]@{ Art = 'MSI'; Name = $dn; Version = [string]$p.DisplayVersion; Kennung = [string]$p.PSChildName; Paket = $null }
                    }
                }
                foreach ($an in 'DellInc.DellUpdate', 'DellInc.DellCommandUpdate') {
                    foreach ($a in @(Get-AppxPackage -AllUsers -Name $an -ErrorAction SilentlyContinue)) {
                        $liste += [pscustomobject]@{ Art = 'Appx'; Name = $a.Name; Version = [string]$a.Version; Kennung = $a.PackageFullName; Paket = $a }
                    }
                }
                return @($liste)
            }

            $alt = @(Get-DellAltprodukte)
            if ($alt.Count -gt 0) {
                $namen = ($alt | ForEach-Object { if ($_.Version) { "$($_.Name) $($_.Version)" } else { $_.Name } }) -join '; '
                if (-not $ersetzen) {
                    Write-Zeile "INKOMPATIBEL: $namen"
                    Write-Zeile 'Dell Command | Update lässt sich neben diesem Produkt nicht installieren.'
                    exit 2
                }
                Write-Zeile "Entferne Altprodukt(e): $namen"
                foreach ($x in $alt) {
                    try {
                        if ($x.Art -eq 'MSI') {
                            if ($x.Kennung -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { Write-Zeile "  Übersprungen (keine MSI-Kennung): $($x.Name)"; continue }
                            $pr = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $($x.Kennung) /qn /norestart" -Wait -PassThru
                            Write-Zeile "  msiexec /x $($x.Kennung) ($($x.Name)): Exit-Code $($pr.ExitCode)"
                        }
                        else {
                            Remove-AppxPackage -Package $x.Kennung -AllUsers -ErrorAction Stop
                            Write-Zeile "  Appx entfernt: $($x.Kennung)"
                        }
                    }
                    catch { Write-Zeile "  Entfernen fehlgeschlagen ($($x.Name)): $($_.Exception.Message)" }
                }
                $rest = @(Get-DellAltprodukte)
                if ($rest.Count -gt 0) {
                    Write-Zeile ("Altprodukt noch vorhanden: " + (($rest | ForEach-Object { $_.Name }) -join '; '))
                    exit 1
                }
                Write-Zeile 'Altprodukt(e) entfernt'
            }

            Write-Zeile "winget install --id Dell.CommandUpdate ($($w.FullName))"
            $ausgabe = & $w.FullName install --id Dell.CommandUpdate --exact --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
            foreach ($z in @($ausgabe -split "`r?`n")) { if ($z.Trim()) { Write-Zeile ('  ' + $z.TrimEnd()) } }
            if (-not (Get-DcuPfad)) { Write-Zeile 'dcu-cli.exe ist nach der Installation nicht vorhanden'; exit 1 }
        }

        ### HP: HPCMSL aus der PSGallery installieren (bei altem PowerShellGet mit einer vorübergehend geladenen neueren Version), danach HP Image Assistant entpacken
        'HP' {
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
            ## Ältere PowerShellGet-Versionen (Windows PowerShell 5.1 liefert 1.0.0.1) können die HP-Module nicht installieren (PowerShellGetFormatVersion 2.0) und überspringen sie ohne Fehler.
            ## Neuere Versionen werden nur vorübergehend in einen temporären Ordner geladen und danach gelöscht: systemweit installiert würden sie auf Geräten mit deaktivierter Skriptausführung andere Installationen (zum Beispiel PSWindowsUpdate) blockieren.
            $pg = @(Get-Module -ListAvailable -Name PowerShellGet | Sort-Object -Property Version -Descending) | Select-Object -First 1
            $hilfOrdner = $null
            $befehl = 'Install-Module -Name HPCMSL -Scope AllUsers -Force -AcceptLicense -SkipPublisherCheck -ErrorAction Stop'
            try {
                if (-not $pg -or $pg.Version -lt [version]'2.2.5') {
                    $hilfOrdner = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('NetCockpitPsGet_' + [guid]::NewGuid().ToString('N'))
                    Write-Zeile ('PowerShellGet {0} ist zu alt, lade eine neuere Version vorübergehend nach {1}' -f $(if ($pg) { $pg.Version } else { 'fehlt' }), $hilfOrdner)
                    New-Item -ItemType Directory -Path $hilfOrdner -Force | Out-Null
                    Save-Module -Name PowerShellGet -MinimumVersion 2.2.5 -Path $hilfOrdner -Force -ErrorAction Stop
                    $befehl = ('$env:PSModulePath = ''{0};'' + $env:PSModulePath; Import-Module -Name PackageManagement -MinimumVersion 1.4.4 -Force; Import-Module -Name PowerShellGet -MinimumVersion 2.2.5 -Force; ' -f $hilfOrdner) + $befehl
                }
                ## HPCMSL in einem frischen Prozess installieren, damit die neue PowerShellGet-Version geladen wird
                Write-Zeile 'Installiere HPCMSL in einem neuen PowerShell-Prozess'
                $ausgabe = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $befehl 2>&1 | Out-String
                foreach ($z in @($ausgabe -split "`r?`n")) { if ($z.Trim()) { Write-Zeile ('  ' + $z.TrimEnd()) } }
            }
            finally {
                if ($hilfOrdner -and (Test-Path -LiteralPath $hilfOrdner)) { Remove-Item -LiteralPath $hilfOrdner -Recurse -Force -ErrorAction SilentlyContinue }
            }
            if (-not (Get-Module -ListAvailable -Name HPCMSL)) { Write-Zeile 'HPCMSL ist nach der Installation nicht vorhanden'; exit 1 }
            Import-Module -Name HPCMSL -Force -ErrorAction Stop
            Write-Zeile 'HPCMSL geladen, lade und entpacke den HP Image Assistant'
            if (-not (Test-Path -Path $hpiaOrdner)) { New-Item -ItemType Directory -Path $hpiaOrdner -Force | Out-Null }
            Install-HPImageAssistant -Extract -DestinationPath $hpiaOrdner
            if (-not (Get-HpiaPfad)) { Write-Zeile 'HPImageAssistant.exe ist nach dem Entpacken nicht vorhanden'; exit 1 }
        }

        ### Lenovo: LSUClient aus der PSGallery
        'Lenovo' {
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
            Install-Module -Name LSUClient -Scope AllUsers -Force -ErrorAction Stop
            if (-not (Get-Module -ListAvailable -Name LSUClient)) { Write-Zeile 'LSUClient ist nach der Installation nicht vorhanden'; exit 1 }
        }

        default {
            Write-Zeile ("Hersteller nicht unterstützt: {0}" -f $info.HerstellerRoh)
            exit 1
        }
    }
    Write-Zeile 'Treiber-Tool installiert'
}
catch {
    Write-Zeile ("Fehler: {0}" -f $_.Exception.Message)
    exit 1
}
'@

## Zusammengesetzte Skripte (BIOS/Firmware-Schalter setzt der Job je Lauf ein)
$script:TrSkripte = @{
    Such    = $script:TrLib + "`r`n" + $script:TrSuchHaupt
    Install = $script:TrLib + "`r`n" + $script:TrInstallHaupt
    Tool    = $script:TrLib + "`r`n" + $script:TrToolHaupt
}

# Job je Gerät
## Läuft als Thread-Job (Warteschlange des NET-COCKPIT); meldet Fortschritt und Ergebnis über das Sync-Objekt $S, die Oberfläche wird vom Timer des Moduls aktualisiert
$script:TrBlock = {
    param([string]$Ziel, [string]$Aktion, $Anmeldedaten, $S, [string]$LogDatei, [string]$TaskCode, $Skripte, [bool]$MitBios)

    . ([scriptblock]::Create($TaskCode))
    $ic = @{ ComputerName = $Ziel; ErrorAction = 'Stop' }
    if ($Anmeldedaten) { $ic.Credential = $Anmeldedaten }
    $meldung = { param($t) Write-Log $t }

    ### Schalter BIOS/Firmware in die Skripte einsetzen
    $mitText = if ($MitBios) { '$true' } else { '$false' }
    $suchSkript = $Skripte.Such.Replace('__MITBIOS__', $mitText)
    $installSkript = $Skripte.Install.Replace('__MITBIOS__', $mitText)
    $toolSkript = $Skripte.Tool.Replace('__MITBIOS__', $mitText).Replace('__ERSETZEN__', '$true')

    ### Log schreiben (Sync-Objekt für die Oberfläche und Datei)
    function Write-Log {
        param([string]$Text)
        $zeile = '{0:HH:mm:ss} {1}' -f (Get-Date), $Text
        [void]$S.Log.Add($zeile)
        try { Add-Content -Path $LogDatei -Value $zeile -Encoding utf8 } catch { }
    }

    ### Hersteller und Modell auf dem Gerät lesen
    function Get-HerstellerRemote {
        $info = Invoke-Command @ic -ScriptBlock {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem
            $m = [string]$cs.Manufacturer
            $h = 'Andere'
            if ($m -match 'Dell')                                 { $h = 'Dell' }
            elseif ($m -match '^(HP|HP Inc\.?|Hewlett-Packard)$') { $h = 'HP' }
            elseif ($m -match 'LENOVO')                           { $h = 'Lenovo' }
            $modell = [string]$cs.Model
            if ($h -eq 'Lenovo') {
                $v = [string](Get-CimInstance -ClassName Win32_ComputerSystemProduct).Version
                if ($v) { $modell = $v }
            }
            [pscustomobject]@{ Hersteller = $h; HerstellerRoh = $m; Modell = $modell }
        }
        $S.Hersteller = [string]$info.Hersteller
        $S.Modell = [string]$info.Modell
        return $info
    }

    ### Treiber-Tool auf dem Gerät prüfen
    function Test-Tool {
        param([string]$Hersteller)
        $hat = Invoke-Command @ic -ArgumentList $Hersteller -ScriptBlock {
            param($h)
            if (-not (Test-Path -Path 'C:\ProgramData\NET-COCKPIT') -and (Test-Path -Path 'C:\ProgramData\WaToKi')) { Rename-Item -Path 'C:\ProgramData\WaToKi' -NewName 'NET-COCKPIT' -ErrorAction SilentlyContinue }
            switch ($h) {
                'Dell'   { return [bool](@("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") | Where-Object { Test-Path -Path $_ }) }
                'HP'     { return [bool](Get-ChildItem -Path 'C:\ProgramData\NET-COCKPIT\HPIA' -Recurse -Filter 'HPImageAssistant.exe' -ErrorAction SilentlyContinue | Select-Object -First 1) }
                'Lenovo' { return [bool](Get-Module -ListAvailable -Name LSUClient) }
                default  { return $false }
            }
        }
        $S.Tool = if ($hat) { 'Ja' } else { 'Nein' }
        return [bool]$hat
    }

    ### Akkubetrieb prüfen
    function Test-Akku {
        $akku = Invoke-Command @ic -ScriptBlock {
            $b = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
            if ($b.Count -eq 0) { return $false }
            return [bool]($b | Where-Object { $_.BatteryStatus -eq 1 })
        }
        return [bool]$akku
    }

    ### Ergebnis-Listen aus dem JSON der Suche in Sync-Objekte übernehmen
    function Set-SuchVerlauf {
        param($Res)
        $S.Verlauf = @(@($Res.Verlauf) | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Datum = [string]$_.Datum; Hersteller = [string]$_.Hersteller; Name = [string]$_.Name; Id = [string]$_.Id; Version = [string]$_.Version; Ergebnis = [string]$_.Ergebnis } })
        $S.ToolLog = @(@($Res.ToolLog) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    }

    ### Logzeilen einer laufenden Aufgabe übernehmen und auf Marker prüfen
    $zeile = {
        param($t)
        if ($t.Trim()) { Write-Log $t.TrimEnd() }
        if ($t -match 'Neustart nötig: True') { $S.Marker = $true }
        if ($t -match '^INKOMPATIBEL: (.+)$') { $S.Inkompat = $Matches[1].Trim() }
    }

    Write-Log "===== Aktion: $Aktion (BIOS/Firmware einbezogen: $MitBios) ====="

    try {
        ## Verbindung prüfen
        $S.Status = 'Verbinde...'
        $wer = Invoke-Command @ic -ScriptBlock { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
        $S.Verbunden = $true
        Write-Log "Verbindung erfolgreich als $([string]@($wer)[0])"

        switch ($Aktion) {

            ## Status prüfen: Hersteller, Windows-Version, Neustart, Akku, Tool, Treiber suchen, Verlauf
            'Status' {
                $S.Status = 'Lese Hersteller...'
                $info = Get-HerstellerRemote
                Write-Log "Hersteller: $($info.HerstellerRoh) | Modell: $($info.Modell) | Zuordnung: $($info.Hersteller)"

                $S.Status = 'Lese Windows-Version...'
                try {
                    $S.Windows = Get-WolZielWindows -Ic $ic
                    Write-Log "Windows: $($S.Windows)"
                }
                catch { Write-Log "Windows-Version nicht lesbar: $($_.Exception.Message)" }

                $S.Status = 'Prüfe Neustart...'
                $neustart = Test-WolZielNeustartAusstehend -Ic $ic
                $S.Neustart = if ($neustart) { 'Ja' } else { 'Nein' }
                Write-Log "Ausstehender Neustart: $($S.Neustart)"

                try {
                    $S.LetzterNeustart = Get-WolZielLetzterNeustart -Ic $ic
                    Write-Log "Letzter Neustart: $($S.LetzterNeustart)"
                }
                catch { Write-Log "Letzter Neustart nicht lesbar: $($_.Exception.Message)" }

                $zusatz = ''
                $geplantText = Get-WolZielNeustart -Ic $ic
                $S.GeplantBis = [string]$geplantText
                $S.GeplantBisGelesen = $true
                if ($geplantText) {
                    $geplant = [datetime]::ParseExact([string]$geplantText, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture).ToString('dd.MM. HH:mm')
                    $zusatz = " | Neustart geplant $geplant"
                    Write-Log "Geplanter Neustart: $geplant"
                }

                try {
                    if (Test-Akku) {
                        $zusatz += ' | Akkubetrieb'
                        Write-Log 'Das Gerät läuft im Akkubetrieb'
                    }
                }
                catch { Write-Log "Akku-Prüfung nicht möglich: $($_.Exception.Message)" }

                if ($info.Hersteller -eq 'Andere') {
                    $S.Tool = '-'
                    $S.Updates = '-'
                    $S.Status = "Hersteller nicht unterstützt ($($info.HerstellerRoh))$zusatz"
                    Write-Log $S.Status
                    return
                }

                if (-not (Test-Tool -Hersteller $info.Hersteller)) {
                    $S.Updates = '-'
                    $S.Status = "Treiber-Tool fehlt, Suche nicht möglich$zusatz"
                    Write-Log "Treiber-Tool für $($info.Hersteller) fehlt, Suche nicht möglich"
                    return
                }
                Write-Log "Treiber-Tool für $($info.Hersteller) ist vorhanden"

                $fremd = @(Get-WolZielAnderesTool -Ic $ic -Eigene 'NetCockpitTreiber*')
                if ($fremd.Count -gt 0) {
                    $S.Status = 'Anderes NET-COCKPIT-Tool läuft auf dem Gerät'
                    Write-Log "Anderes NET-COCKPIT-Tool läuft auf dem Gerät: $($fremd -join ', ')"
                    return
                }

                $inst = Get-WolZielTaskStatus -Ic $ic -Name 'NetCockpitTreiberInstall'
                if ($inst.Vorhanden -and $inst.State -in 'Running', 'Queued') {
                    $S.Status = "Installation läuft bereits auf dem Gerät$zusatz"
                    Write-Log 'Installation läuft bereits auf dem Gerät'
                    return
                }

                $name = 'NetCockpitTreiberSuche'
                $aufraeumen = $true
                try {
                    $S.Status = 'Suche läuft...'
                    $null = Remove-WolZielTask -Ic $ic -Name $name
                    $null = Start-WolZielTask -Ic $ic -Name $name -Skript $suchSkript
                    Write-Log 'Suche gestartet (lokale Aufgabe auf dem Gerät)'
                    Start-Sleep -Seconds 5
                    $w = Wait-WolZielTask -Ic $ic -Name $name -PauseSek 5 -MaxMinuten 30 -Meldung $meldung
                    if ($w.Ergebnis -eq 'Verloren') { $aufraeumen = $false; $S.Status = 'Verbindung verloren'; return }
                    if ($w.Ergebnis -eq 'Zeit') { $S.Status = 'Suche: Zeitüberschreitung (30 Min)'; Write-Log $S.Status; return }

                    $json = Invoke-Command @ic -ScriptBlock {
                        $f = 'C:\Windows\Temp\NetCockpitTreiberSuche.json'
                        if (Test-Path $f) { Get-Content -Path $f -Raw -Encoding UTF8 }
                    }
                    if (-not $json) {
                        $S.Status = "Suche ohne Ergebnis, Aufgaben-Code $($w.Result)"
                        Write-Log $S.Status
                        return
                    }

                    $res = $json | ConvertFrom-Json
                    if ($res.Fehler) {
                        $S.Updates = '-'
                        $S.Status = "Suche fehlgeschlagen: $($res.Fehler)"
                        Write-Log "Fehler auf dem Gerät: $($res.Fehler)"
                        Set-SuchVerlauf -Res $res
                        return
                    }

                    ### Verfügbare Treiber-Updates
                    $liste = @($res.Updates | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Id = [string]$_.Id; Typ = [string]$_.Typ; Version = [string]$_.Version } })
                    $S.Details = $liste
                    $nichtInv = @($liste | Where-Object { $_.Typ -eq 'nicht inventarisiert' }).Count
                    $relevant = $liste.Count - $nichtInv
                    $S.Updates = if ($nichtInv -gt 0) { "$relevant (+$nichtInv)" } else { [string]$liste.Count }
                    foreach ($u in $liste) { Write-Log ('{0} | {1} | {2} | {3}' -f $u.Name, $u.Id, $u.Typ, $u.Version) }

                    ### Verlauf der Installationen durch das Cockpit und Tool-Log
                    Set-SuchVerlauf -Res $res
                    Write-Log "Verlauf: $(@($S.Verlauf).Count) Einträge gelesen"

                    if ($nichtInv -gt 0) {
                        $ni = "$nichtInv nicht inventarisiert"
                        if ($relevant -eq 0)     { $S.Status = "Keine inventarisierten Updates, $ni$zusatz" }
                        elseif ($relevant -eq 1) { $S.Status = "1 Treiber-Update verfügbar (+$ni)$zusatz" }
                        else                     { $S.Status = "$relevant Treiber-Updates verfügbar (+$ni)$zusatz" }
                    }
                    elseif ($liste.Count -eq 1) { $S.Status = "1 Treiber-Update verfügbar$zusatz" }
                    elseif ($liste.Count -gt 1) { $S.Status = "$($liste.Count) Treiber-Updates verfügbar$zusatz" }
                    else                        { $S.Status = "Keine Treiber-Updates verfügbar$zusatz" }
                    Write-Log $S.Status
                }
                finally {
                    if ($aufraeumen) {
                        try { $null = Remove-WolZielTask -Ic $ic -Name $name }
                        catch { Write-Log "Aufräumen fehlgeschlagen: $($_.Exception.Message)" }
                    }
                }
            }

            ## Treiber-Tool nachinstallieren (Dell: WinGet, HP: HPCMSL, Lenovo: LSUClient)
            'Tool' {
                $S.Inkompat = ''
                $S.Status = 'Lese Hersteller...'
                $info = Get-HerstellerRemote
                Write-Log "Hersteller: $($info.HerstellerRoh) | Modell: $($info.Modell) | Zuordnung: $($info.Hersteller)"
                if ($info.Hersteller -eq 'Andere') {
                    $S.Tool = '-'
                    $S.Status = "Hersteller nicht unterstützt ($($info.HerstellerRoh))"
                    Write-Log $S.Status
                    return
                }

                $fremd = @(Get-WolZielAnderesTool -Ic $ic -Eigene 'NetCockpitTreiber*')
                if ($fremd.Count -gt 0) {
                    $S.Status = 'Anderes NET-COCKPIT-Tool läuft auf dem Gerät'
                    Write-Log "Anderes NET-COCKPIT-Tool läuft auf dem Gerät: $($fremd -join ', ')"
                    return
                }

                $name = 'NetCockpitTreiberTool'
                $aufraeumen = $true
                try {
                    $S.Status = 'Installiere Treiber-Tool...'
                    $null = Remove-WolZielTask -Ic $ic -Name $name
                    $null = Start-WolZielTask -Ic $ic -Name $name -Skript $toolSkript
                    Write-Log "Tool-Installation gestartet für $($info.Hersteller) (lokale Aufgabe auf dem Gerät)"
                    Start-Sleep -Seconds 5

                    $w = Wait-WolZielTask -Ic $ic -Name $name -PauseSek 10 -MaxMinuten 60 -Zeile $zeile -Meldung $meldung
                    if ($w.Ergebnis -eq 'Verloren') {
                        $aufraeumen = $false
                        $S.Status = 'Verbindung verloren, Tool-Installation läuft evtl. weiter'
                        Write-Log 'Aufgabe bleibt auf dem Gerät bestehen, Aufräumen erfolgt beim nächsten Lauf'
                        return
                    }
                    if ($w.Ergebnis -eq 'Zeit') {
                        $aufraeumen = $false
                        $S.Status = 'Tool-Installation: Zeitüberschreitung (60 Min)'
                        Write-Log $S.Status
                        return
                    }
                    if ($w.Ergebnis -eq 'Weg') { Write-Log 'Aufgabe ist auf dem Gerät nicht mehr vorhanden' }

                    if (Test-Tool -Hersteller $info.Hersteller) { $S.Status = 'Treiber-Tool installiert' }
                    elseif ($S.Inkompat)                        { $S.Status = "Inkompatibles Dell-Produkt konnte nicht entfernt werden: $($S.Inkompat)" }
                    else                                        { $S.Status = 'Treiber-Tool-Installation fehlgeschlagen (siehe Log)' }
                    Write-Log $S.Status
                }
                finally {
                    if ($aufraeumen) {
                        try { $null = Remove-WolZielTask -Ic $ic -Name $name; Write-Log 'Aufgabe und Skript auf dem Gerät entfernt' }
                        catch { Write-Log "Aufräumen fehlgeschlagen: $($_.Exception.Message)" }
                    }
                }
            }

            ## Treiber-Updates installieren (lokale Aufgabe auf dem Gerät, kein automatischer Neustart)
            'Installieren' {
                $S.Status = 'Lese Hersteller...'
                $info = Get-HerstellerRemote
                Write-Log "Hersteller: $($info.HerstellerRoh) | Modell: $($info.Modell) | Zuordnung: $($info.Hersteller)"
                if ($info.Hersteller -eq 'Andere') {
                    $S.Status = "Hersteller nicht unterstützt ($($info.HerstellerRoh))"
                    Write-Log $S.Status
                    return
                }
                if (-not (Test-Tool -Hersteller $info.Hersteller)) {
                    $S.Status = 'Treiber-Tool fehlt'
                    Write-Log "Treiber-Tool für $($info.Hersteller) fehlt"
                    return
                }
                if ($MitBios -and (Test-Akku)) {
                    $S.Status = 'Abbruch: Gerät im Akkubetrieb (BIOS/Firmware einbezogen)'
                    Write-Log $S.Status
                    return
                }

                $fremd = @(Get-WolZielAnderesTool -Ic $ic -Eigene 'NetCockpitTreiber*')
                if ($fremd.Count -gt 0) {
                    $S.Status = 'Anderes NET-COCKPIT-Tool läuft auf dem Gerät'
                    Write-Log "Anderes NET-COCKPIT-Tool läuft auf dem Gerät: $($fremd -join ', ')"
                    return
                }

                $name = 'NetCockpitTreiberInstall'
                $aufraeumen = $true
                $S.Marker = $false
                try {
                    ### Läuft schon eine Installation? Dann anhängen, sonst neu starten
                    $vorhanden = Get-WolZielTaskStatus -Ic $ic -Name $name
                    if ($vorhanden.Vorhanden -and $vorhanden.State -in 'Running', 'Queued') {
                        Write-Log 'Installation läuft bereits auf dem Gerät, hänge mich an die laufende Installation an'
                    }
                    else {
                        $S.Status = 'Bereite Installation vor...'
                        $null = Remove-WolZielTask -Ic $ic -Name $name
                        $null = Start-WolZielTask -Ic $ic -Name $name -Skript $installSkript
                        Write-Log 'Installation gestartet (still, ohne automatischen Neustart)'
                        Start-Sleep -Seconds 5
                    }
                    $S.Status = 'Installation läuft...'

                    $w = Wait-WolZielTask -Ic $ic -Name $name -PauseSek 10 -MaxMinuten 240 -Zeile $zeile -Meldung $meldung
                    if ($w.Ergebnis -eq 'Verloren') {
                        $aufraeumen = $false
                        $S.Status = 'Verbindung verloren, Installation läuft evtl. weiter'
                        Write-Log 'Aufgabe bleibt auf dem Gerät bestehen, Aufräumen erfolgt beim nächsten Lauf'
                        return
                    }
                    if ($w.Ergebnis -eq 'Zeit') {
                        $aufraeumen = $false
                        $S.Status = 'Installation: Zeitüberschreitung (240 Min)'
                        Write-Log $S.Status
                        return
                    }
                    if ($w.Ergebnis -eq 'Weg') { Write-Log 'Aufgabe ist auf dem Gerät nicht mehr vorhanden' }
                    $ergebnis = if ($w.Ergebnis -eq 'Fertig') { $w.Result } else { $null }

                    ### Neustart-Bedarf prüfen (das Gerät kann bereits im Neustart sein)
                    $nz = $null
                    try { $nz = Test-WolZielNeustartAusstehend -Ic $ic }
                    catch { Write-Log 'Neustart-Prüfung nicht möglich, das Gerät startet evtl. bereits neu' }

                    $S.Updates = '-'
                    $S.Details = @()

                    if ($null -eq $ergebnis)  { $S.Status = 'Installation beendet, Ergebnis unbekannt' }
                    elseif ($ergebnis -eq 1)  { $S.Status = 'Installation beendet, mindestens ein Treiber fehlgeschlagen (siehe Log)' }
                    elseif ($ergebnis -ne 0)  { $S.Status = "Installation beendet, Aufgaben-Code $ergebnis" }
                    elseif ($nz -or $S.Marker) {
                        $S.Neustart = 'Ja'
                        $S.Status = 'Installation abgeschlossen, Neustart nötig (Aktionen > Neustart planen)'
                    }
                    else                      { $S.Status = 'Installation abgeschlossen' }
                    Write-Log $S.Status
                }
                finally {
                    if ($aufraeumen) {
                        try { $null = Remove-WolZielTask -Ic $ic -Name $name; Write-Log 'Aufgabe und Skript auf dem Gerät entfernt' }
                        catch { Write-Log "Aufräumen fehlgeschlagen: $($_.Exception.Message)" }
                    }
                }
            }
        }
    }
    catch {
        $S.Fehlertext = $_.Exception.Message
        Write-Log "Fehler: $($_.Exception.Message)"
    }
}

# Sync-Objekte und Anzeige
## Sync-Objekt eines Geräts (bleibt für die Sitzung erhalten, damit Details und Log nach dem Lauf verfügbar sind)
function script:Get-WolTrSync {
    param($Zeile)
    if (-not $script:TrSync.ContainsKey($Zeile)) {
        $script:TrSync[$Zeile] = [hashtable]::Synchronized(@{
            Status = ''; Fehlertext = ''; Verbunden = $false
            Windows = ''; Hersteller = ''; Modell = ''; Tool = ''; Updates = ''; Neustart = ''; LetzterNeustart = ''
            GeplantBis = ''; GeplantBisGelesen = $false
            Marker = $false; Inkompat = ''
            Details = @(); Verlauf = @(); ToolLog = @()
            Log = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        })
    }
    return $script:TrSync[$Zeile]
}

## Werte aus dem Sync-Objekt in die Zeile übernehmen (nur Werte, die das Modul gelesen hat)
function script:Update-WolTrZeile {
    param($Zeile, $S)
    $werte = [ordered]@{
        Windows = $S.Windows; NeustartAusstehend = $S.Neustart; LetzterNeustart = $S.LetzterNeustart
        TrHersteller = $S.Hersteller; TrModell = $S.Modell; TrTool = $S.Tool; TrUpdates = $S.Updates
    }
    foreach ($schluessel in $werte.Keys) {
        $wert = [string]$werte[$schluessel]
        if ($wert -and $Zeile[$schluessel] -ne $wert) { $Zeile[$schluessel] = $wert }
    }
    if ($S.GeplantBisGelesen -and $Zeile['GeplantBis'] -ne [string]$S.GeplantBis) { $Zeile['GeplantBis'] = [string]$S.GeplantBis }
}

## Timer des Moduls: zeigt den Fortschritt laufender Aufträge, solange welche laufen
$script:TrTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:TrTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:TrTimer.Add_Tick({
    try {
        foreach ($eintrag in @($script:TrSync.GetEnumerator())) {
            $z = $eintrag.Key
            $S = $eintrag.Value
            if ((Get-WolGruppeOffen -Gruppe 'TREIBER' -Zeile $z) -eq 0) { continue }
            Update-WolTrZeile -Zeile $z -S $S
            if ($S.Status) { $z.Status = [string]$S.Status }
        }
        if ((Get-WolGruppeOffen -Gruppe 'TREIBER') -eq 0) { $script:TrTimer.Stop() }
    }
    catch { Write-WolLog "Fehler im Timer des Moduls TREIBER: $($_.Exception.Message)" }
})

# Aufträge
## Auswertung eines Auftrags (läuft im Poll-Takt des NET-COCKPIT)
$script:TrFertig = {
    param($a)
    $z = $a.Zeile
    $S = $a.Daten.S
    try { $null = Receive-Job -Job $a.Job -ErrorAction Stop }
    catch { if (-not $S.Fehlertext) { $S.Fehlertext = $_.Exception.Message } }

    if ($S.Fehlertext) {
        $kurz = Register-WolVerbindungsfehler -Zeile $z -Text ([string]$S.Fehlertext)
        $S.Status = $(if ($S.Verbunden) { "Fehler: $kurz" } else { "Verbindung fehlgeschlagen: $kurz" })
    }
    elseif (-not $S.Status) { $S.Status = 'Beendet' }
    Update-WolTrZeile -Zeile $z -S $S
    Save-WolWerteZeile -Zeile $z -Neu:($a.Daten.Aktion -eq 'Status' -and -not $S.Fehlertext)
    $z.Status = [string]$S.Status
    Write-WolLog ('TREIBER {0}: {1}' -f $a.Daten.Name, $S.Status)

    ### Nach erfolgreicher Tool-Installation gleich den Status prüfen
    if ($a.Daten.Aktion -eq 'Tool' -and $S.Status -eq 'Treiber-Tool installiert') {
        Start-WolTrAktion -Aktion 'Status' -Ziele @($z)
    }
}

## Aktion für Geräte in die Warteschlange des NET-COCKPIT legen (nur grüne Geräte)
function script:Start-WolTrAktion {
    param([string]$Aktion, $Ziele, [bool]$MitBios = $false)
    $Ziele = @($Ziele)
    $gruen = @($Ziele | Where-Object { $_.Ampel -eq 'Gruen' })
    foreach ($z in @($Ziele | Where-Object { $_.Ampel -ne 'Gruen' })) { $z.Status = 'WinRM nicht erreichbar - übersprungen' }
    if ($gruen.Count -eq 0) { Show-WolMeldung 'Keines der Geräte ist grün (WinRM erreichbar).'; return }
    if (-not (Resolve-WolKonten -Zeilen $gruen)) { return }
    if (-not (Test-Path -LiteralPath $script:TrLogOrdner)) { New-Item -Path $script:TrLogOrdner -ItemType Directory -Force | Out-Null }

    $gestartet = 0
    foreach ($z in $gruen) {
        if ((Get-WolGruppeOffen -Gruppe 'TREIBER' -Zeile $z) -gt 0) { continue }
        try { $konto = Get-WolAnmeldung -Zeile $z }
        catch { $z.Status = $_.Exception.Message; continue }

        $S = Get-WolTrSync -Zeile $z
        $S.Status = ''
        $S.Fehlertext = ''
        $S.Verbunden = $false
        $S.GeplantBisGelesen = $false

        $name = $(if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { [string]$z.IP })
        $logDatei = Join-Path $script:TrLogOrdner ('{0:yyyyMMdd}_{1}_treiber-log.txt' -f (Get-Date), ($name -replace '[^\w\.\-]', '_'))
        Add-WolAuftrag -Zeile $z -Block $script:TrBlock -Argumente @((Get-WolZielName -Zeile $z), $Aktion, $konto, $S, $logDatei, $script:ZielTaskCode, $script:TrSkripte, $MitBios) -Fertig $script:TrFertig -Gruppe 'TREIBER' -Daten @{ Aktion = $Aktion; S = $S; Name = $name } -Starttext 'TREIBER: Verbinde...'
        $gestartet++
    }
    if ($gestartet -eq 0) { Write-WolLog 'TREIBER: Auf den Geräten läuft schon eine Aktion des Moduls'; return }
    Write-WolLog "TREIBER $Aktion : $gestartet Gerät(e)"
    if (-not $script:TrTimer.IsEnabled) { $script:TrTimer.Start() }
}

# Dialoge
## Markierte Geräte holen (mit Hinweis, wenn keins markiert ist); -Genau 1 verlangt genau ein Gerät
function script:Get-WolTrZiele {
    param([int]$Genau = 0)
    $ziele = @(Get-WolMarkierte)
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return $null }
    if ($Genau -gt 0 -and $ziele.Count -ne $Genau) { Show-WolMeldung 'Bitte genau ein Gerät markieren.'; return $null }
    return , $ziele
}

## Namen der Geräte für Texte (Hostname, sonst IP)
function script:Get-WolTrNamen {
    param($Zeilen)
    return (@($Zeilen | ForEach-Object { if ($_.Hostname) { ([string]$_.Hostname).Split('.')[0] } else { [string]$_.IP } }) -join ', ')
}

## Details eines Geräts: verfügbare Treiber, Verlauf, Tool-Log und Log
function script:Show-WolTrDetails {
    param($Zeile)
    $S = Get-WolTrSync -Zeile $Zeile
    $name = Get-WolTrNamen -Zeilen @($Zeile)
    $verfuegbar = @(@($S.Details) | Where-Object { $_ })
    $verlauf = @(@($S.Verlauf) | Where-Object { $_ })
    $toolLog = @(@($S.ToolLog) | Where-Object { $null -ne $_ })
    $log = @($S.Log.ToArray())
    if ($verfuegbar.Count -eq 0 -and $verlauf.Count -eq 0 -and $toolLog.Count -eq 0 -and $log.Count -eq 0) {
        Show-WolMeldung "Für $name liegen noch keine Daten vor. Bitte zuerst Status prüfen."
        return
    }

    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="1100" Height="520" WindowStartupLocation="CenterOwner">
  <Grid Margin="8">
    <TabControl x:Name="Reiter">
      <TabItem x:Name="TabVerfuegbar">
        <DataGrid x:Name="TabelleVerfuegbar" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Name"    Binding="{Binding Name, Mode=OneWay}"    Width="*"/>
            <DataGridTextColumn Header="Id"      Binding="{Binding Id, Mode=OneWay}"      Width="200"/>
            <DataGridTextColumn Header="Typ"     Binding="{Binding Typ, Mode=OneWay}"     Width="160"/>
            <DataGridTextColumn Header="Version" Binding="{Binding Version, Mode=OneWay}" Width="150"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
      <TabItem x:Name="TabVerlauf">
        <DataGrid x:Name="TabelleVerlauf" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Datum"      Binding="{Binding Datum, Mode=OneWay}"      Width="140"/>
            <DataGridTextColumn Header="Hersteller" Binding="{Binding Hersteller, Mode=OneWay}" Width="80"/>
            <DataGridTextColumn Header="Name"       Binding="{Binding Name, Mode=OneWay}"       Width="*"/>
            <DataGridTextColumn Header="Id"         Binding="{Binding Id, Mode=OneWay}"         Width="150"/>
            <DataGridTextColumn Header="Version"    Binding="{Binding Version, Mode=OneWay}"    Width="120"/>
            <DataGridTextColumn Header="Ergebnis"   Binding="{Binding Ergebnis, Mode=OneWay}"   Width="240"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
      <TabItem x:Name="TabToolLog">
        <TextBox x:Name="TxtToolLog" IsReadOnly="True" FontFamily="Consolas" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem x:Name="TabLog">
        <TextBox x:Name="TxtLog" IsReadOnly="True" FontFamily="Consolas" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
    </TabControl>
  </Grid>
</Window>
'@
    $f.Title = "Treiber auf $name"
    $f.Owner = $script:Fenster
    $f.FindName('TabelleVerfuegbar').ItemsSource = $verfuegbar
    $f.FindName('TabelleVerlauf').ItemsSource = $verlauf
    $f.FindName('TabVerfuegbar').Header = "Verfügbare Treiber ($($verfuegbar.Count))"
    $f.FindName('TabVerlauf').Header = "Verlauf ($($verlauf.Count))"
    $f.FindName('TabToolLog').Header = "Tool-Log ($($toolLog.Count) Zeilen)"
    $f.FindName('TabLog').Header = "Log ($($log.Count))"
    $txtToolLog = $f.FindName('TxtToolLog')
    $txtToolLog.Text = ($toolLog -join "`r`n")
    $f.FindName('TxtLog').Text = ($log -join "`r`n")
    $f.Add_ContentRendered({ $txtToolLog.ScrollToEnd() }.GetNewClosure())
    if ($verfuegbar.Count -eq 0) {
        $f.FindName('Reiter').SelectedIndex = $(if ($verlauf.Count -gt 0) { 1 } elseif ($toolLog.Count -gt 0) { 2 } else { 3 })
    }
    [void]$f.ShowDialog()
}

# Aktionen des Moduls
## Status prüfen
function script:Start-WolTrStatus {
    $ziele = Get-WolTrZiele
    if ($ziele) { Start-WolTrAktion -Aktion 'Status' -Ziele $ziele -MitBios ([bool]$script:TrChkBios.IsChecked) }
}

## Treiber-Updates installieren (Rückfrage; mit BIOS/Firmware nur bei Netzteilbetrieb)
function script:Start-WolTrInstallieren {
    $ziele = Get-WolTrZiele
    if (-not $ziele) { return }
    $mitBios = [bool]$script:TrChkBios.IsChecked
    $namen = (Get-WolTrNamen -Zeilen $ziele) -replace ', ', "`r`n"
    if ($mitBios) {
        $text = "Treiber-Updates INKLUSIVE BIOS/Firmware installieren auf:`r`n`r`n$namen`r`n`r`nAchtung: Die Geräte müssen am Netzteil hängen (bei Akkubetrieb wird abgebrochen). BitLocker und der nötige Neustart sind vorher zu bedenken.`r`n`r`nWeiter?"
    }
    else {
        $text = "Treiber-Updates (ohne BIOS/Firmware) installieren auf:`r`n`r`n$namen`r`n`r`nEs wird nicht automatisch neu gestartet.`r`n`r`nWeiter?"
    }
    $hinweis = @()
    foreach ($z in $ziele) {
        $d = @(@((Get-WolTrSync -Zeile $z).Details) | Where-Object { $_ })
        $ni = @($d | Where-Object { $_.Typ -eq 'nicht inventarisiert' }).Count
        if ($ni -gt 0) { $hinweis += "$(Get-WolTrNamen -Zeilen @($z)): $($d.Count - $ni) inventarisiert, $ni nicht inventarisiert" }
    }
    if ($hinweis.Count -gt 0) {
        $text = $text.Replace("`r`n`r`nWeiter?", "`r`n`r`nLaut letztem Status:`r`n" + ($hinweis -join "`r`n") + "`r`nDell Command | Update lässt sich nicht auf einzelne Pakete beschränken, nur auf Typen (Treiber, BIOS, Firmware).`r`n`r`nWeiter?")
    }
    if ([System.Windows.MessageBox]::Show($text, 'Treiber-Updates installieren', 'YesNo', 'Warning') -eq 'Yes') {
        Start-WolTrAktion -Aktion 'Installieren' -Ziele $ziele -MitBios $mitBios
    }
}

## Treiber-Tool nachinstallieren (Rückfrage je Gerät; Hersteller kommt aus dem letzten Status)
function script:Start-WolTrTool {
    $ziele = Get-WolTrZiele
    if (-not $ziele) { return }
    $ok = @()
    foreach ($z in $ziele) {
        $name = Get-WolTrNamen -Zeilen @($z)
        $hersteller = [string]$z['TrHersteller']
        if (-not $hersteller) { Show-WolMeldung "Der Hersteller von $name ist noch nicht bekannt. Bitte zuerst Status prüfen."; continue }
        if ($hersteller -eq 'Andere') { Show-WolMeldung "${name}: Hersteller wird nicht unterstützt (nur Dell, HP, Lenovo)."; continue }
        if ([string]$z['TrTool'] -eq 'Ja') { Show-WolMeldung "Das Treiber-Tool ist auf $name bereits vorhanden."; continue }
        $was = switch ($hersteller) {
            'Dell'   { 'Dell Command | Update per WinGet (Dell.CommandUpdate). Ein vorhandenes inkompatibles Dell-Update-Produkt wird vorher deinstalliert' }
            'HP'     { 'das Modul HPCMSL aus der PSGallery und den HP Image Assistant' }
            'Lenovo' { 'das Modul LSUClient aus der PSGallery' }
        }
        if ([System.Windows.MessageBox]::Show("Auf $name ($hersteller) installieren: $was ?`r`nDas Gerät benötigt dafür Internetzugang.", 'Treiber-Tool nachinstallieren', 'YesNo', 'Question') -eq 'Yes') { $ok += $z }
    }
    if ($ok.Count -gt 0) { Start-WolTrAktion -Aktion 'Tool' -Ziele $ok }
}

## Details des markierten Geräts
function script:Start-WolTrDetails {
    $ziele = Get-WolTrZiele -Genau 1
    if ($ziele) { Show-WolTrDetails -Zeile $ziele[0] }
}

# Fenster des Moduls
## Wird vom Menü Module > TREIBER aufgerufen: kleines Fenster neben der Tabelle (bleibt offen, die Tabelle bleibt bedienbar)
function script:Show-WolModulTREIBER {
    if ($script:TrFenster) {
        $script:TrFenster.Activate()
        Set-WolModulOffen -Key 'TREIBER' -Offen $true
        return
    }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TREIBER-Updates" Width="400" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Wirkt auf die markierten Geräte der Tabelle (nur grüne, WinRM erreichbar). Aufträge laufen über die Warteschlange des NET-COCKPIT. Unterstützt: Dell, HP, Lenovo." TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,12"/>
    <CheckBox x:Name="ChkSpalten" Content="Spalten des Moduls in der Tabelle anzeigen" Margin="0,0,0,10"
              ToolTip="Blendet die Spalten dieses Moduls in der Tabelle ein (Standard: aus). Beim Schließen des Fensters werden sie wieder ausgeblendet"/>
    <Button x:Name="BtnStatus" Content="Status prüfen" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Prüft PC-Hersteller und Modell, Windows-Version, Neustart, Akku und Treiber-Tool, sucht Treiber-Updates und liest den Verlauf"/>
    <Button x:Name="BtnInstall" Content="Treiber-Updates installieren" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Installiert die Treiber-Updates still, mit Rückfrage und nie mit automatischem Neustart"/>
    <Button x:Name="BtnTool" Content="Treiber-Tool nachinstallieren" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Dell: Dell Command | Update per WinGet, HP: HPCMSL und HP Image Assistant, Lenovo: LSUClient"/>
    <Button x:Name="BtnDetails" Content="Details des markierten Geräts..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Verfügbare Treiber, Verlauf, Tool-Log und Log eines markierten Geräts"/>
    <CheckBox x:Name="ChkBios" Content="BIOS/Firmware einbeziehen" Margin="0,6,0,0"
              ToolTip="Standardmäßig aus. Bei Akkubetrieb bricht die Installation ab"/>
    <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,5" Margin="0,12,0,0"/>
  </StackPanel>
</Window>
'@
    $f.Owner = $script:Fenster
    $script:TrChkBios = $f.FindName('ChkBios')
    Connect-WolModulSpaltenHaken -Fenster $f -Key 'TREIBER'
    $f.FindName('BtnStatus').Add_Click({ Start-WolTrStatus })
    $f.FindName('BtnInstall').Add_Click({ Start-WolTrInstallieren })
    $f.FindName('BtnTool').Add_Click({ Start-WolTrTool })
    $f.FindName('BtnDetails').Add_Click({ Start-WolTrDetails })
    $f.FindName('BtnSchliessen').Add_Click({ $script:TrFenster.Close() })
    $f.Add_Closed({ Set-WolModulOffen -Key 'TREIBER' -Offen $false; $script:TrFenster = $null; $script:TrChkBios = $null })
    $script:TrFenster = $f
    $f.Show()
    Set-WolModulOffen -Key 'TREIBER' -Offen $true
}
