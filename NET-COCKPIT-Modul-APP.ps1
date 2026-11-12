# NET-COCKPIT-Modul-APP.ps1
<#
.SYNOPSIS
    Modul APP-Updates für das NET-COCKPIT (Menü Module > APP)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und wirkt auf die markierten, grünen Geräte der Tabelle.
    - Status prüfen: Windows-Version, letzter Neustart, Neustart ausstehend, geplanter Neustart, WinGet-Modul, WinGet-Version, WAU (Ja, Intune, Nein), verfügbare Programm-Updates
    - App-Updates installieren (still, nie automatischer Neustart), Programm installieren, installierte Programme anzeigen (gemeinsame Liste mit Suche und CSV-Export), Programm deinstallieren
    - WinGet-Modul nachinstallieren (PowerShell 7 und Microsoft.WinGet.Client auf dem Zielgerät); danach läuft automatisch Status prüfen
    - WAU installieren (Winget-AutoUpdate mit Ausschlussliste; Geräte mit WAU, auch der Intune-Variante, werden übersprungen) und WAU-Ausschlüsse bearbeiten (excluded_apps.txt der normalen Installation; die Intune-Variante wird nur erkannt)
    - Details je Gerät: verfügbare Updates, Cockpit-Verlauf, WAU-Verlauf und Log
    Verbindung, Konten, Warteschlange, Neustart, Neustart planen, OU-Import und Liste kommen aus dem NET-COCKPIT.
    Log je Gerät: C:\Temp\NET-COCKPIT_data\Modul-APP\yyyyMMdd_Gerät_app-log.txt
#>

# Einstellungen
## Ordner und Zustand
$script:AppLogOrdner = Join-Path $script:DatenOrdner 'Modul-APP'
$script:AppSync = [System.Collections.Generic.Dictionary[object, object]]::new()
$script:AppFenster = $null
$script:AppDeinstallWarten = [System.Collections.Generic.List[object]]::new()
$script:AppWauWarten = [System.Collections.Generic.List[object]]::new()
$script:AppWauLauf = $null
$script:AppListeWarten = [System.Collections.Generic.List[object]]::new()
$script:AppListeLauf = $null
## Vorschlag für die WAU-Ausschlussliste (eine WinGet-Id je Zeile, Platzhalter * erlaubt)
$script:AppWauStandard = @(
    'Brave.Brave*', 'Google.Chrome*', 'Microsoft.Edge*', 'Microsoft.Office', 'Microsoft.OneDrive', 'Microsoft.RemoteDesktopClient',
    'Microsoft.Teams*', 'Mozilla.Firefox*', 'Opera.Opera*', 'TeamViewer.TeamViewer*', 'Romanitho.Winget-AutoUpdate', 'KnifMelti.WAU-Settings-GUI'
)

## Spalten (nur sichtbar, wenn im Modulfenster der Haken "Spalten des Moduls in der Tabelle anzeigen" gesetzt ist); Windows, Neustart ausstehend und Letzter Neustart teilen sich alle Update-Module
New-WolSpalte -Key 'Windows' -Titel 'Windows' -Eig '[Windows]' -Breite 270 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'NeustartAusstehend' -Titel 'Neustart ausstehend' -Eig '[NeustartAusstehend]' -Breite 125 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'LetzterNeustart' -Titel 'Letzter Neustart' -Eig '[LetzterNeustart]' -Breite 125 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'AppModul' -Titel 'WinGet-Modul' -Eig '[AppModul]' -Breite 90 -Sichtbar $false -Modul 'APP'
New-WolSpalte -Key 'AppUpdates' -Titel 'App-Updates' -Eig '[AppUpdates]' -Breite 90 -Sichtbar $false -Modul 'APP'
New-WolSpalte -Key 'AppWinget' -Titel 'WinGet-Version' -Eig '[AppWinget]' -Breite 110 -Sichtbar $false -Modul 'APP'
New-WolSpalte -Key 'WauStatus' -Titel 'WAU' -Eig '[WauStatus]' -Breite 70 -Sichtbar $false -Modul 'APP'

# Skripte, die auf dem Zielgerät als geplante Aufgabe laufen (PowerShell 7, als SYSTEM)
## Gemeinsamer Kopf: Logdatei, Fehlerzähler und Verlauf (Datum;Name;Id;Von;Nach;Ergebnis)
$script:AppKopf = @'
$log = 'C:\Windows\Temp\NetCockpitAppInstall.log'
$fehlerAnzahl = 0
if (-not (Test-Path -Path 'C:\ProgramData\NET-COCKPIT') -and (Test-Path -Path 'C:\ProgramData\WaToKi')) { Rename-Item -Path 'C:\ProgramData\WaToKi' -NewName 'NET-COCKPIT' -ErrorAction SilentlyContinue }
$verlaufDatei = 'C:\ProgramData\NET-COCKPIT\WingetVerlauf.csv'

### Eine Zeile in den Verlauf schreiben
function Add-Verlauf {
    param($Name, $Id, $Von, $Nach, $Ergebnis)
    try {
        $ordner = Split-Path -Path $verlaufDatei -Parent
        if (-not (Test-Path -Path $ordner)) { New-Item -ItemType Directory -Path $ordner -Force | Out-Null }
        $zeile = '{0};{1};{2};{3};{4};{5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ([string]$Name -replace '[;\r\n]', ' '), ([string]$Id -replace '[;\r\n]', ' '), ([string]$Von -replace '[;\r\n]', ' '), ([string]$Nach -replace '[;\r\n]', ' '), ([string]$Ergebnis -replace '[;\r\n]', ' ')
        Add-Content -Path $verlaufDatei -Encoding utf8 -Value $zeile
    }
    catch { }
}

'@

## Gewählte Programme mit Update installieren (Quelle winget); __IDS__ wird durch die Liste der gewählten WinGet-Ids ersetzt
$script:AppInstallRumpf = @'
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    $erlaubt = @(__IDS__)
    $pakete = @(Get-WinGetPackage -Source winget | Where-Object { $_.IsUpdateAvailable -and $erlaubt -contains $_.Id })
    Add-Content -Path $log -Encoding utf8 -Value ("{0} gewählte Programm-Updates gefunden" -f $pakete.Count)

    foreach ($p in $pakete) {
        $neu = @($p.AvailableVersions)
        $neueVersion = if ($neu.Count -gt 0) { [string]$neu[0] } else { '?' }
        Add-Content -Path $log -Encoding utf8 -Value ("Aktualisiere {0} ({1}): {2} -> {3}" -f $p.Name, $p.Id, $p.InstalledVersion, $neueVersion)
        try {
            $r = @(Update-WinGetPackage -Id $p.Id -Source winget -Mode Silent -ErrorAction Stop)[0]
            Add-Content -Path $log -Encoding utf8 -Value ("  Ergebnis: {0}, Neustart nötig: {1}, Installer-Code: {2}" -f $r.Status, $r.RebootRequired, $r.InstallerErrorCode)
            if ($r.Status -ne 'Ok') { $fehlerAnzahl++ }
            Add-Verlauf $p.Name $p.Id $p.InstalledVersion $neueVersion ('{0}{1}' -f $r.Status, $(if ($r.RebootRequired) { ', Neustart nötig' } else { '' }))
        }
        catch {
            $fehlerAnzahl++
            Add-Content -Path $log -Encoding utf8 -Value ("  Fehler: {0}" -f $_.Exception.Message)
            Add-Verlauf $p.Name $p.Id $p.InstalledVersion $neueVersion ('Fehler: ' + $_.Exception.Message)
        }
    }
    Add-Content -Path $log -Encoding utf8 -Value ("Fertig: {0} von {1} Programmen mit Fehler" -f $fehlerAnzahl, $pakete.Count)
}
catch {
    ($_ | Out-String) | Add-Content -Path $log -Encoding utf8
    exit 1
}
if ($fehlerAnzahl -gt 0) { exit 1 }
'@

## Ein einzelnes Programm installieren (__ID__ wird vor dem Start eingesetzt)
$script:AppProgrammRumpf = @'
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    Add-Content -Path $log -Encoding utf8 -Value 'Installiere Programm __ID__'
    $r = @(Install-WinGetPackage -Id '__ID__' -Source winget -Mode Silent -ErrorAction Stop)[0]
    Add-Content -Path $log -Encoding utf8 -Value ("  Ergebnis: {0}, Neustart nötig: {1}, Installer-Code: {2}" -f $r.Status, $r.RebootRequired, $r.InstallerErrorCode)
    if ($r.Status -ne 'Ok') { $fehlerAnzahl++ }
    Add-Verlauf '' '__ID__' '-' '-' ('Neu installiert: {0}{1}' -f $r.Status, $(if ($r.RebootRequired) { ', Neustart nötig' } else { '' }))
}
catch {
    $fehlerAnzahl++
    Add-Content -Path $log -Encoding utf8 -Value ("  Fehler: {0}" -f $_.Exception.Message)
    Add-Verlauf '' '__ID__' '-' '-' ('Neu installiert, Fehler: ' + $_.Exception.Message)
}
if ($fehlerAnzahl -gt 0) { exit 1 }
'@

## Ein einzelnes Programm deinstallieren (__ID__ wird vor dem Start eingesetzt)
$script:AppDeinstallRumpf = @'
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    Add-Content -Path $log -Encoding utf8 -Value 'Deinstalliere Programm __ID__'
    $r = @(Uninstall-WinGetPackage -Id '__ID__' -Mode Silent -ErrorAction Stop)[0]
    Add-Content -Path $log -Encoding utf8 -Value ("  Ergebnis: {0}, Neustart nötig: {1}, Deinstaller-Code: {2}" -f $r.Status, $r.RebootRequired, $r.UninstallerErrorCode)
    if ($r.Status -ne 'Ok') { $fehlerAnzahl++ }
    Add-Verlauf '' '__ID__' '-' '-' ('Deinstalliert: {0}{1}' -f $r.Status, $(if ($r.RebootRequired) { ', Neustart nötig' } else { '' }))
}
catch {
    $fehlerAnzahl++
    Add-Content -Path $log -Encoding utf8 -Value ("  Fehler: {0}" -f $_.Exception.Message)
    Add-Verlauf '' '__ID__' '-' '-' ('Deinstalliert, Fehler: ' + $_.Exception.Message)
}
if ($fehlerAnzahl -gt 0) { exit 1 }
'@

## Winget-AutoUpdate (WAU) installieren und Ausschlussliste schreiben (__LISTE__ = Ausschlussliste als Base64 von UTF-8)
$script:AppWauRumpf = @'
$wauId = 'Romanitho.Winget-AutoUpdate'
$wauEinstellungen = 'UPDATESINTERVAL=Monthly UPDATESATLOGON=1 NOTIFICATIONLEVEL=SuccessOnly'
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    Add-Content -Path $log -Encoding utf8 -Value "Installiere Winget-AutoUpdate ($wauId) mit: $wauEinstellungen"
    if ((Get-Command -Name Install-WinGetPackage).Parameters.ContainsKey('Custom')) {
        $r = @(Install-WinGetPackage -Id $wauId -Source winget -Mode Silent -Custom $wauEinstellungen -ErrorAction Stop)[0]
        Add-Content -Path $log -Encoding utf8 -Value ("  Ergebnis: {0}, Neustart nötig: {1}, Installer-Code: {2}" -f $r.Status, $r.RebootRequired, $r.InstallerErrorCode)
        if ($r.Status -ne 'Ok') { $fehlerAnzahl++ }
        Add-Verlauf '' $wauId '-' '-' ('WAU installiert: ' + $r.Status)
    }
    else {
        $winget = @(Resolve-Path -Path 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe' -ErrorAction SilentlyContinue | Sort-Object -Property Path -Descending)[0]
        if (-not $winget) { throw 'winget.exe nicht gefunden (C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*)' }
        Add-Content -Path $log -Encoding utf8 -Value "  Das Modul kennt -Custom nicht, nutze $($winget.Path)"
        $ausgabe = (& $winget.Path install --id $wauId --exact --source winget --silent --accept-package-agreements --accept-source-agreements --custom $wauEinstellungen 2>&1 | Out-String).Trim()
        Add-Content -Path $log -Encoding utf8 -Value $ausgabe
        Add-Content -Path $log -Encoding utf8 -Value ("  winget-Exitcode: {0}" -f $LASTEXITCODE)
        if ($LASTEXITCODE -ne 0) { $fehlerAnzahl++ }
        Add-Verlauf '' $wauId '-' '-' ('WAU installiert, winget-Exitcode ' + $LASTEXITCODE)
    }

    ### Ausschlussliste schreiben
    $wauOrdner = 'C:\Program Files\Winget-AutoUpdate'
    if (Test-Path -Path $wauOrdner) {
        $eintraege = @([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__LISTE__')) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Set-Content -Path (Join-Path $wauOrdner 'excluded_apps.txt') -Value $eintraege -Encoding ascii
        Add-Content -Path $log -Encoding utf8 -Value ("Ausschlussliste geschrieben: {0} Einträge" -f $eintraege.Count)
    }
    else {
        $fehlerAnzahl++
        Add-Content -Path $log -Encoding utf8 -Value "Ordner $wauOrdner fehlt nach der Installation, Ausschlussliste nicht geschrieben"
    }

    ### Geplante Aufgabe prüfen
    if (Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue) { Add-Content -Path $log -Encoding utf8 -Value 'Geplante Aufgabe Winget-AutoUpdate vorhanden' }
    else {
        $fehlerAnzahl++
        Add-Content -Path $log -Encoding utf8 -Value 'Geplante Aufgabe Winget-AutoUpdate fehlt'
    }
}
catch {
    $fehlerAnzahl++
    Add-Content -Path $log -Encoding utf8 -Value ("  Fehler: {0}" -f $_.Exception.Message)
    Add-Verlauf '' $wauId '-' '-' ('WAU installiert, Fehler: ' + $_.Exception.Message)
}
if ($fehlerAnzahl -gt 0) { exit 1 }
'@

## Installierte Programme lesen (für die Auswahl bei der Deinstallation)
$script:AppListeSkript = @'
$out = 'C:\Windows\Temp\NetCockpitAppListe.json'
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    $liste = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Get-WinGetPackage)) {
        $liste.Add([pscustomobject]@{
            Name    = [string]$p.Name
            Id      = [string]$p.Id
            Version = [string]$p.InstalledVersion
            Quelle  = [string]$p.Source
        })
    }
    $erg = [pscustomobject]@{ Fehler = ''; Programme = @($liste.ToArray() | Sort-Object -Property Name) }
}
catch {
    $erg = [pscustomobject]@{ Fehler = ($_ | Out-String).Trim(); Programme = @() }
}
$erg | ConvertTo-Json -Depth 4 | Set-Content -Path $out -Encoding UTF8
'@

## Suche: WinGet-Version, verfügbare Updates, Cockpit-Verlauf und WAU-Verlauf
$script:AppSuchSkript = @'
$out = 'C:\Windows\Temp\NetCockpitAppSuche.json'
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop

    ### WinGet-Version (nur Information, bei Fehler bleibt der Wert leer)
    $wingetVersion = ''
    try { $wingetVersion = [string](Get-WinGetVersion) }
    catch { $wingetVersion = '' }

    ### Programme mit verfügbarem Update (nur Quelle winget)
    $pakete = @(Get-WinGetPackage -Source winget | Where-Object { $_.IsUpdateAvailable })
    $liste = New-Object System.Collections.Generic.List[object]
    foreach ($p in $pakete) {
        $neu = @($p.AvailableVersions)
        $liste.Add([pscustomobject]@{
            Name       = [string]$p.Name
            Id         = [string]$p.Id
            Version    = [string]$p.InstalledVersion
            Verfuegbar = if ($neu.Count -gt 0) { [string]$neu[0] } else { '' }
            Quelle     = [string]$p.Source
        })
    }

    ### Alle installierten Programme (für den Reiter "Installierte Programme"; schlägt das fehl, bleibt die gespeicherte Liste erhalten)
    $programmeOk = $false
    $programme = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($p in @(Get-WinGetPackage)) {
            $programme.Add([pscustomobject]@{
                Name    = [string]$p.Name
                Id      = [string]$p.Id
                Version = [string]$p.InstalledVersion
                Quelle  = [string]$p.Source
            })
        }
        $programmeOk = $true
    }
    catch { $programmeOk = $false }

    ### Verlauf der Installationen durch das Cockpit (letzte 50 Einträge, neueste zuerst)
    $verlauf = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -Path 'C:\ProgramData\NET-COCKPIT') -and (Test-Path -Path 'C:\ProgramData\WaToKi')) { Rename-Item -Path 'C:\ProgramData\WaToKi' -NewName 'NET-COCKPIT' -ErrorAction SilentlyContinue }
    $datei = 'C:\ProgramData\NET-COCKPIT\WingetVerlauf.csv'
    if (Test-Path -Path $datei) {
        foreach ($zeile in @(Get-Content -Path $datei -Encoding UTF8 | Select-Object -Last 50)) {
            $t = @($zeile -split ';')
            if ($t.Count -ge 6) {
                $verlauf.Add([pscustomobject]@{ Datum = $t[0]; Name = $t[1]; Id = $t[2]; Von = $t[3]; Nach = $t[4]; Ergebnis = $t[5] })
            }
        }
    }
    $verlauf.Reverse()

    ### Update-Verlauf aus dem Log von Winget-AutoUpdate (WAU), falls vorhanden
    $wauVerlauf = New-Object System.Collections.Generic.List[object]
    $wauPfad    = ''
    $wauDatei   = @('C:\Program Files\Winget-AutoUpdate\logs\updates.log', 'C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\logs\updates.log') |
        Where-Object { Test-Path -Path $_ } | ForEach-Object { Get-Item -Path $_ } | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    if ($wauDatei) {
        $wauPfad = [string]$wauDatei.FullName
        $datum   = ''
        $aktuell = $null
        foreach ($zeile in @(Get-Content -Path $wauDatei.FullName)) {
            ### Fehlercode des Installers (Zeile ohne Uhrzeit)
            if ($aktuell -and $zeile -match '^Installer failed with exit code: (\S+)') { $aktuell.Code = $Matches[1]; continue }
            ### Datum steht in der Kopfzeile jedes Prüflaufs
            if ($zeile -match '^#\s+(\d{2}\.\d{2}\.\d{4}) - CHECK FOR APP UPDATES') {
                ### Neuer Prüflauf: ein noch offenes Update hat im Log kein Ergebnis bekommen
                if ($aktuell) { $aktuell.Ergebnis = 'Kein Ergebnis im Log'; $wauVerlauf.Add($aktuell); $aktuell = $null }
                $datum = $Matches[1]
                continue
            }
            $treffer = [regex]::Match($zeile, '^(\d{2}:\d{2}):\d{2} - (.*)$')
            if (-not $treffer.Success) { continue }
            $zeit = $treffer.Groups[1].Value
            $text = $treffer.Groups[2].Value

            if ($text -match '^Updating (.+) from (.+) to (.+)\.\.\.$') {
                if ($aktuell) { $aktuell.Ergebnis = 'Kein Ergebnis im Log'; $wauVerlauf.Add($aktuell) }
                $aktuell = [pscustomobject]@{ Datum = "$datum $zeit"; Name = $Matches[1]; Id = ''; Von = $Matches[2]; Nach = $Matches[3]; Ergebnis = ''; Code = '' }
            }
            elseif ($aktuell -and $text -match '^#+\s+WINGET UPGRADE: (\S+)\s+#+$') { $aktuell.Id = $Matches[1] }
            elseif ($aktuell -and $text -match ' updated to ') {
                $aktuell.Ergebnis = 'Erfolgreich'
                $wauVerlauf.Add($aktuell)
                $aktuell = $null
            }
            elseif ($aktuell -and $text -match ' update failed\.$') {
                $aktuell.Ergebnis = if ($aktuell.Code) { 'Fehlgeschlagen (Installer-Code ' + $aktuell.Code + ')' } else { 'Fehlgeschlagen' }
                $wauVerlauf.Add($aktuell)
                $aktuell = $null
            }
        }
        if ($aktuell) { $aktuell.Ergebnis = 'Kein Ergebnis im Log'; $wauVerlauf.Add($aktuell) }
        $wauVerlauf.Reverse()
    }
    $wauAnzeige = @($wauVerlauf | Select-Object -First 100 -Property Datum, Name, Id, Von, Nach, Ergebnis)

    $erg = [pscustomobject]@{
        Fehler        = ''
        WingetVersion = $wingetVersion
        Updates       = @($liste.ToArray())
        Verlauf       = @($verlauf.ToArray())
        WauVerlauf    = $wauAnzeige
        WauPfad       = $wauPfad
        Programme     = @($programme.ToArray() | Sort-Object -Property Name)
        ProgrammeOk   = $programmeOk
    }
}
catch {
    $erg = [pscustomobject]@{ Fehler = ($_ | Out-String).Trim(); WingetVersion = ''; Updates = @(); Verlauf = @(); WauVerlauf = @(); WauPfad = ''; Programme = @(); ProgrammeOk = $false }
}
$erg | ConvertTo-Json -Depth 4 | Set-Content -Path $out -Encoding UTF8
'@

## Alle Skripte für den Job (Kopf plus Rumpf)
$script:AppSkripte = @{
    Install  = $script:AppKopf + $script:AppInstallRumpf
    Programm = $script:AppKopf + $script:AppProgrammRumpf
    Deinstall = $script:AppKopf + $script:AppDeinstallRumpf
    Wau      = $script:AppKopf + $script:AppWauRumpf
    Liste    = $script:AppListeSkript
    Suche    = $script:AppSuchSkript
}

# Job je Gerät
## Läuft als Thread-Job (Warteschlange des NET-COCKPIT); meldet Fortschritt und Ergebnis über das Sync-Objekt $S, die Oberfläche wird vom Timer des Moduls aktualisiert
$script:AppBlock = {
    param([string]$Ziel, [string]$Aktion, $Anmeldedaten, $S, [string]$LogDatei, [string]$TaskCode, [string]$Wert, $Skripte)

    . ([scriptblock]::Create($TaskCode))
    $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
    $ic = @{ ComputerName = $Ziel; ErrorAction = 'Stop' }
    if ($Anmeldedaten) { $ic.Credential = $Anmeldedaten }
    $meldung = { param($t) Write-Log $t }

    ### Log schreiben (Sync-Objekt für die Oberfläche und Datei)
    function Write-Log {
        param([string]$Text)
        $zeile = '{0:HH:mm:ss} {1}' -f (Get-Date), $Text
        [void]$S.Log.Add($zeile)
        try { Add-Content -Path $LogDatei -Value $zeile -Encoding utf8 } catch { }
    }

    ### PowerShell 7 und Modul auf dem Gerät prüfen
    function Test-Modul {
        $info = Invoke-Command @ic -ScriptBlock {
            $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
            $ps7  = Test-Path -Path $pwsh
            $mod  = $false
            if ($ps7) {
                $befehl = '[bool](Get-Module -ListAvailable -Name Microsoft.WinGet.Client)'
                $enc    = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
                $mod    = ((& $pwsh -NoProfile -NonInteractive -EncodedCommand $enc 2>$null | Out-String).Trim() -eq 'True')
            }
            [pscustomobject]@{ PS7 = $ps7; Modul = $mod }
        }
        if (-not $info.PS7) { Write-Log 'PowerShell 7 fehlt auf dem Gerät (C:\Program Files\PowerShell\7\pwsh.exe)' }
        elseif (-not $info.Modul) { Write-Log 'Microsoft.WinGet.Client fehlt in PowerShell 7' }
        $hat = ($info.PS7 -and $info.Modul)
        $S.Modul = if ($hat) { 'Ja' } else { 'Nein' }
        return [bool]$hat
    }

    ### WAU auf dem Gerät erkennen: Ja = normale Installation, Intune = Intune-Variante (Winget-Autoupdate-aaS), Nein; bei Ja steht die Ausschlussliste in Liste
    function Get-WauInfo {
        $info = Invoke-Command @ic -ScriptBlock {
            $normal = Test-Path -LiteralPath 'C:\Program Files\Winget-AutoUpdate'
            $intune = Test-Path -LiteralPath 'C:\Program Files\Winget-Autoupdate-aaS'
            if (-not $normal -and -not $intune) {
                foreach ($t in @(Get-ScheduledTask -TaskName 'Winget-AutoUpdate*' -ErrorAction SilentlyContinue)) {
                    if ($t.TaskName -like '*aaS*') { $intune = $true } else { $normal = $true }
                }
            }
            $liste = ''
            $datei = 'C:\Program Files\Winget-AutoUpdate\excluded_apps.txt'
            if ($normal -and (Test-Path -LiteralPath $datei)) { $liste = [string](Get-Content -LiteralPath $datei -Raw) }
            [pscustomobject]@{ Normal = $normal; Intune = $intune; Liste = $liste }
        }
        $art = if ($info.Normal) { 'Ja' } elseif ($info.Intune) { 'Intune' } else { 'Nein' }
        $S.Wau = $art
        return [pscustomobject]@{ Art = $art; Liste = [string]$info.Liste }
    }

    ### Abfrage als Aufgabe auf dem Gerät ausführen und das JSON-Ergebnis lesen; liefert $null, wenn etwas schiefging (Status ist dann gesetzt)
    function Invoke-Abfrage {
        param([string]$Name, [string]$Skript, [string]$Wort)
        $aufraeumen = $true
        try {
            $S.Status = "$Wort läuft..."
            $null = Remove-WolZielTask -Ic $ic -Name $Name
            $null = Start-WolZielTask -Ic $ic -Name $Name -Skript $Skript -Programm $pwsh
            Write-Log "$Wort gestartet (lokale Aufgabe auf dem Gerät)"
            Start-Sleep -Seconds 5
            $w = Wait-WolZielTask -Ic $ic -Name $Name -PauseSek 5 -MaxMinuten 30 -Meldung $meldung
            if ($w.Ergebnis -eq 'Verloren') { $aufraeumen = $false; $S.Status = 'Verbindung verloren'; return $null }
            if ($w.Ergebnis -eq 'Zeit') { $S.Status = "${Wort}: Zeitüberschreitung (30 Min)"; Write-Log $S.Status; return $null }

            $json = Invoke-Command @ic -ArgumentList $Name -ScriptBlock {
                param($n)
                $f = "C:\Windows\Temp\$n.json"
                if (Test-Path $f) { Get-Content -Path $f -Raw -Encoding UTF8 }
            }
            if (-not $json) { $S.Status = "$Wort ohne Ergebnis, Aufgaben-Code $($w.Result)"; Write-Log $S.Status; return $null }

            $res = $json | ConvertFrom-Json
            if ($res.Fehler) {
                $S.Status = "$Wort fehlgeschlagen (WinGet nicht verfügbar?)"
                Write-Log "Fehler auf dem Gerät: $($res.Fehler)"
                return $null
            }
            return $res
        }
        finally {
            if ($aufraeumen) {
                try { $null = Remove-WolZielTask -Ic $ic -Name $Name }
                catch { Write-Log "Aufräumen fehlgeschlagen: $($_.Exception.Message)" }
            }
        }
    }

    Write-Log "===== Aktion: $Aktion ====="

    try {
        ## Verbindung prüfen
        $S.Status = 'Verbinde...'
        $wer = Invoke-Command @ic -ScriptBlock { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
        $S.Verbunden = $true
        Write-Log "Verbindung erfolgreich als $([string]@($wer)[0])"

        ## Läuft ein anderes NET-COCKPIT-Tool (OS oder Treiber) auf dem Gerät?
        $andere = @(Get-WolZielAnderesTool -Ic $ic -Eigene 'NetCockpitApp*')
        if ($andere.Count -gt 0) {
            $S.Status = 'Anderes NET-COCKPIT-Tool läuft auf dem Gerät'
            Write-Log ("Anderes NET-COCKPIT-Tool läuft auf dem Gerät: {0}" -f ($andere -join ', '))
            return
        }

        switch ($Aktion) {

            ## Status prüfen: Windows-Version, Neustart, Modul, Programm-Updates suchen
            'Status' {
                $S.Status = 'Lese Windows-Version...'
                try {
                    $S.Windows = Get-WolZielWindows -Ic $ic
                    Write-Log "Windows: $($S.Windows)"
                }
                catch { Write-Log "Windows-Version nicht lesbar: $($_.Exception.Message)" }

                try {
                    $S.LetzterNeustart = Get-WolZielLetzterNeustart -Ic $ic
                    Write-Log "Letzter Neustart: $($S.LetzterNeustart)"
                }
                catch { Write-Log "Letzter Neustart nicht lesbar: $($_.Exception.Message)" }

                $S.Status = 'Prüfe Neustart...'
                $neustart = Test-WolZielNeustartAusstehend -Ic $ic
                $S.Neustart = if ($neustart) { 'Ja' } else { 'Nein' }
                Write-Log "Ausstehender Neustart: $($S.Neustart)"

                $zusatz = ''
                $geplantText = Get-WolZielNeustart -Ic $ic
                $S.GeplantBis = [string]$geplantText
                $S.GeplantBisGelesen = $true
                if ($geplantText) {
                    $geplant = [datetime]::ParseExact([string]$geplantText, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture).ToString('dd.MM. HH:mm')
                    $zusatz = " | Neustart geplant $geplant"
                    Write-Log "Geplanter Neustart: $geplant"
                }

                $S.Status = 'Prüfe WAU...'
                try {
                    $wau = Get-WauInfo
                    Write-Log "WAU: $($wau.Art)"
                }
                catch { Write-Log "WAU nicht prüfbar: $($_.Exception.Message)" }

                if (-not (Test-Modul)) {
                    $S.Status = "Modul fehlt, Suche nicht möglich$zusatz"
                    Write-Log 'Microsoft.WinGet.Client fehlt, Updates können nicht gesucht werden'
                    return
                }
                Write-Log 'Microsoft.WinGet.Client ist vorhanden'

                $inst = Get-WolZielTaskStatus -Ic $ic -Name 'NetCockpitAppInstall'
                if ($inst.Vorhanden -and $inst.State -in 'Running', 'Queued') {
                    $S.Status = "Installation läuft bereits auf dem Gerät$zusatz"
                    Write-Log 'Installation läuft bereits auf dem Gerät'
                    return
                }

                $res = Invoke-Abfrage -Name 'NetCockpitAppSuche' -Skript $Skripte.Suche -Wort 'Suche'
                if (-not $res) {
                    if ($S.Status -like 'Suche fehlgeschlagen*') { $S.Winget = '-' }
                    return
                }

                ### WinGet-Version
                $S.Winget = if ($res.WingetVersion) { [string]$res.WingetVersion } else { '-' }
                Write-Log "WinGet-Version: $($S.Winget)"

                ### Verfügbare Programm-Updates
                $liste = @($res.Updates | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Id = [string]$_.Id; Version = [string]$_.Version; Verfuegbar = [string]$_.Verfuegbar; Quelle = [string]$_.Quelle } })
                $S.Details = $liste
                $S.DetailsNeu = $true
                $S.Updates = [string]$liste.Count
                foreach ($u in $liste) { Write-Log ("{0} | {1} | {2} -> {3}" -f $u.Name, $u.Id, $u.Version, $u.Verfuegbar) }

                ### Verlauf der Installationen durch das Cockpit
                $S.Verlauf = @(@($res.Verlauf) | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Datum = [string]$_.Datum; Name = [string]$_.Name; Id = [string]$_.Id; Von = [string]$_.Von; Nach = [string]$_.Nach; Ergebnis = [string]$_.Ergebnis } })
                Write-Log "Verlauf: $(@($S.Verlauf).Count) Einträge gelesen"

                ### Update-Verlauf aus dem Log von Winget-AutoUpdate (WAU)
                $S.WauVerlauf = @(@($res.WauVerlauf) | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Datum = [string]$_.Datum; Name = [string]$_.Name; Id = [string]$_.Id; Von = [string]$_.Von; Nach = [string]$_.Nach; Ergebnis = [string]$_.Ergebnis } })
                ### Alle installierten Programme (nur wenn die Abfrage auf dem Gerät geklappt hat)
                if ($res.ProgrammeOk) {
                    $S.Programme = @(@($res.Programme) | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Id = [string]$_.Id; Version = [string]$_.Version; Quelle = [string]$_.Quelle } })
                    $S.ProgrammeNeu = $true
                    Write-Log "Installierte Programme: $(@($S.Programme).Count) gelesen"
                }
                else { Write-Log 'Installierte Programme konnten nicht gelesen werden, die gespeicherte Liste bleibt erhalten' }
                if ($res.WauPfad) { Write-Log "WAU-Verlauf: $(@($S.WauVerlauf).Count) Einträge gelesen aus $($res.WauPfad)" }
                else { Write-Log 'WAU-Log nicht vorhanden (C:\Program Files\Winget-AutoUpdate\logs\updates.log oder C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\logs\updates.log)' }

                if ($liste.Count -eq 1) { $S.Status = "1 Programm-Update verfügbar$zusatz" }
                elseif ($liste.Count -gt 1) { $S.Status = "$($liste.Count) Programm-Updates verfügbar$zusatz" }
                else { $S.Status = "Keine Programm-Updates verfügbar$zusatz" }
                Write-Log $S.Status
            }

            ## Installierte Programme lesen (für die Auswahl bei der Deinstallation und für die Anzeige)
            { $_ -in 'ProgrammeLesen', 'ProgrammeAnzeigen' } {
                $S.Programme = @()
                if (-not (Test-Modul)) { $S.Status = 'Modul fehlt'; Write-Log 'Microsoft.WinGet.Client fehlt'; return }

                $inst = Get-WolZielTaskStatus -Ic $ic -Name 'NetCockpitAppInstall'
                if ($inst.Vorhanden -and $inst.State -in 'Running', 'Queued') {
                    $S.Status = 'Installation läuft bereits auf dem Gerät'
                    Write-Log $S.Status
                    return
                }

                $res = Invoke-Abfrage -Name 'NetCockpitAppListe' -Skript $Skripte.Liste -Wort 'Programmliste'
                if (-not $res) { return }

                $S.Programme = @(@($res.Programme) | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Id = [string]$_.Id; Version = [string]$_.Version; Quelle = [string]$_.Quelle } })
                $S.ProgrammeNeu = $true
                $S.Status = "{0} installierte Programme gelesen" -f @($S.Programme).Count
                Write-Log $S.Status
            }

            ## Modul nachinstallieren (und WinGet bei Bedarf bereitstellen)
            'Modul' {
                $S.Status = 'Installiere PowerShell 7 und Microsoft.WinGet.Client...'
                $res = Invoke-Command @ic -ScriptBlock {
                    $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
                    $zeilen = New-Object System.Collections.Generic.List[string]
                    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

                    ### PowerShell 7 per MSI installieren, wenn es fehlt
                    if (-not (Test-Path -Path $pwsh)) {
                        $zeilen.Add('PowerShell 7 fehlt, installiere per MSI (aka.ms/install-powershell.ps1)')
                        try {
                            $skript = Invoke-RestMethod -Uri 'https://aka.ms/install-powershell.ps1'
                            & ([scriptblock]::Create($skript)) -UseMSI -Quiet
                        }
                        catch { $zeilen.Add("PowerShell-7-Installation fehlgeschlagen: $($_.Exception.Message)") }
                    }

                    ### Modul in PowerShell 7 installieren und WinGet bereitstellen
                    if (Test-Path -Path $pwsh) {
                        $befehl = @'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force -Confirm:$false
Import-Module Microsoft.WinGet.Client
try { Repair-WinGetPackageManager -AllUsers | Out-Null } catch { Write-Output ('Repair-WinGetPackageManager meldet: ' + $_.Exception.Message) }
'@
                        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
                        $ausgabe = (& $pwsh -NoProfile -NonInteractive -EncodedCommand $enc 2>&1 | Out-String).Trim()
                        if ($ausgabe) { $zeilen.Add($ausgabe) }
                    }
                    $zeilen.ToArray()
                }
                foreach ($z in @($res)) { if ($z) { Write-Log $z } }
                if (Test-Modul) { $S.Status = 'Modul installiert' } else { $S.Status = 'Modul-Installation fehlgeschlagen' }
                Write-Log $S.Status
            }

            ## WAU-Ausschlussliste eines Geräts lesen (nur normale Installation)
            'WauAusschluesseLesen' {
                $S.Status = 'Lese WAU-Ausschlussliste...'
                $wau = Get-WauInfo
                if ($wau.Art -eq 'Intune') { $S.Status = 'Intune-Variante, Liste über Intune pflegen'; Write-Log $S.Status; return }
                if ($wau.Art -eq 'Nein') { $S.Status = 'WAU nicht vorhanden'; Write-Log $S.Status; return }
                $S.WauListe = $wau.Liste
                $S.WauGelesen = $true
                $S.Status = 'WAU-Ausschlussliste gelesen'
                Write-Log $S.Status
            }

            ## WAU-Ausschlussliste schreiben ($Wert = Liste als Base64 von UTF-8); kein Auftrag auf dem Gerät, nur eine Datei
            'WauAusschluesse' {
                $wau = Get-WauInfo
                if ($wau.Art -eq 'Intune') { $S.Status = 'Intune-Variante, Liste über Intune pflegen'; Write-Log $S.Status; return }
                if ($wau.Art -eq 'Nein') { $S.Status = 'WAU nicht vorhanden - übersprungen'; Write-Log $S.Status; return }
                $S.Status = 'Schreibe WAU-Ausschlussliste...'
                $eintraege = @([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Wert)) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                $anzahl = Invoke-Command @ic -ArgumentList (, $eintraege) -ScriptBlock {
                    param($zeilen)
                    $datei = 'C:\Program Files\Winget-AutoUpdate\excluded_apps.txt'
                    Set-Content -LiteralPath $datei -Value $zeilen -Encoding ASCII
                    @(Get-Content -LiteralPath $datei | Where-Object { $_.Trim() }).Count
                }
                if ([int]$anzahl -eq $eintraege.Count) { $S.Status = "WAU-Ausschlussliste geschrieben ($anzahl Einträge)" }
                else { $S.Status = "WAU-Ausschlussliste geschrieben, Kontrolle weicht ab ($anzahl statt $($eintraege.Count) Einträge)" }
                Write-Log $S.Status
            }

            ## Updates, Programm oder WAU installieren, Programm deinstallieren (lokale Aufgabe auf dem Gerät)
            { $_ -in 'Installieren', 'ProgrammInstallieren', 'ProgrammDeinstallieren', 'WauInstallieren' } {
                if ($Aktion -eq 'WauInstallieren') {
                    $wau = Get-WauInfo
                    if ($wau.Art -ne 'Nein') {
                        $S.Status = 'WAU schon vorhanden - übersprungen' + $(if ($wau.Art -eq 'Intune') { ' (Intune-Variante)' } else { '' })
                        Write-Log $S.Status
                        return
                    }
                }
                if (-not (Test-Modul)) { $S.Status = 'Modul fehlt'; Write-Log 'Microsoft.WinGet.Client fehlt'; return }

                ### Bei den Aktionen für ein einzelnes Programm enthält $Wert die WinGet-Id
                $skript = switch ($Aktion) {
                    'ProgrammInstallieren'   { $Skripte.Programm.Replace('__ID__', $Wert.Replace("'", "''")) }
                    'ProgrammDeinstallieren' { $Skripte.Deinstall.Replace('__ID__', $Wert.Replace("'", "''")) }
                    'WauInstallieren'        { $Skripte.Wau.Replace('__LISTE__', $Wert) }
                    default                  { $Skripte.Install.Replace('__IDS__', (@($Wert -split '\|' | Where-Object { $_ } | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ',')) }
                }
                $wort = switch ($Aktion) { 'ProgrammDeinstallieren' { 'Deinstallation' } 'WauInstallieren' { 'WAU-Installation' } default { 'Installation' } }
                $name = 'NetCockpitAppInstall'
                $aufraeumen = $true
                $zeile = {
                    param($t)
                    if ($t.Trim()) { Write-Log $t.TrimEnd() }
                    if ($t -match 'Neustart nötig: True') { $S.NeustartGemeldet = $true }
                }
                try {
                    ### Läuft schon eine Installation? Dann anhängen, sonst neu starten
                    $vorhanden = Get-WolZielTaskStatus -Ic $ic -Name $name
                    if ($vorhanden.Vorhanden -and $vorhanden.State -in 'Running', 'Queued') {
                        Write-Log 'Installation läuft bereits auf dem Gerät, hänge mich an die laufende Installation an'
                    }
                    else {
                        $S.Status = "Bereite $wort vor..."
                        $null = Remove-WolZielTask -Ic $ic -Name $name
                        $null = Start-WolZielTask -Ic $ic -Name $name -Skript $skript -Programm $pwsh
                        Write-Log "$wort gestartet (still, ohne automatischen Neustart)"
                        Start-Sleep -Seconds 5
                    }
                    $S.Status = "$wort läuft..."

                    $w = Wait-WolZielTask -Ic $ic -Name $name -PauseSek 10 -Zeile $zeile -Meldung $meldung
                    if ($w.Ergebnis -eq 'Verloren') {
                        $aufraeumen = $false
                        $S.Status = 'Verbindung verloren, Installation läuft evtl. weiter'
                        Write-Log 'Aufgabe bleibt auf dem Gerät bestehen, Aufräumen erfolgt beim nächsten Lauf'
                        return
                    }
                    if ($w.Ergebnis -eq 'Weg') { Write-Log 'Aufgabe ist auf dem Gerät nicht mehr vorhanden' }
                    $ergebnis = if ($w.Ergebnis -eq 'Fertig') { $w.Result } else { $null }

                    ### Neustart-Bedarf prüfen (das Gerät kann bereits im Neustart sein)
                    $nz = $null
                    try {
                        $nz = Test-WolZielNeustartAusstehend -Ic $ic
                        $S.Neustart = if ($nz) { 'Ja' } else { 'Nein' }
                    }
                    catch { Write-Log 'Neustart-Prüfung nicht möglich, das Gerät startet evtl. bereits neu' }

                    if ($Aktion -ne 'WauInstallieren') {
                        $S.Updates = '-'
                        $S.Details = @()
                        $S.DetailsNeu = $true
                    }

                    if ($null -eq $ergebnis) { $S.Status = "$wort beendet, Ergebnis unbekannt" }
                    elseif ($ergebnis -eq 1) { $S.Status = "$wort beendet, mindestens ein Programm fehlgeschlagen (siehe Log)" }
                    elseif ($ergebnis -ne 0) { $S.Status = "$wort beendet, Aufgaben-Code $ergebnis" }
                    elseif ($nz -or $S.NeustartGemeldet) {
                        $S.Neustart = 'Ja'
                        $S.Status = $wort + ' abgeschlossen, Neustart nötig (Aktionen > Neustart planen)'
                    }
                    else { $S.Status = "$wort abgeschlossen" }
                    if ($Aktion -eq 'WauInstallieren') {
                        try { $null = Get-WauInfo }
                        catch { Write-Log "WAU nicht prüfbar: $($_.Exception.Message)" }
                    }
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
function script:Get-WolAppSync {
    param($Zeile)
    if (-not $script:AppSync.ContainsKey($Zeile)) {
        $S = [hashtable]::Synchronized(@{
            Status = ''; Fehlertext = ''; Verbunden = $false; NeustartGemeldet = $false
            Windows = ''; Modul = ''; Updates = ''; Winget = ''; Neustart = ''; LetzterNeustart = ''
            GeplantBis = ''; GeplantBisGelesen = $false
            Wau = ''; WauListe = ''; WauGelesen = $false
            Details = @(); Verlauf = @(); WauVerlauf = @(); Programme = @()
            DetailsStand = ''; DetailsNeu = $false; ProgrammeStand = ''; ProgrammeNeu = $false
            Log = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        })
        $script:AppSync[$Zeile] = $S
        Restore-WolAppProgramme -Zeile $Zeile -S $S
        Restore-WolAppUpdates -Zeile $Zeile -S $S
    }
    return $script:AppSync[$Zeile]
}

## Gespeicherte Programmliste des Geräts laden (Ordner des Geräts, Datei APP-Programme.json; Stand = gelesen am)
function script:Restore-WolAppProgramme {
    param($Zeile, $S)
    $gespeichert = Read-WolGeraeteListe -Zeile $Zeile -Name 'APP-Programme'
    if (-not $gespeichert) { return }
    $S.Programme = @(@($gespeichert.Daten) | Where-Object { $_ })
    $S.ProgrammeStand = [string]$gespeichert.Stand
}

## Gespeicherte Listen "Verfügbare Updates", "Cockpit-Verlauf" und "WAU-Verlauf" des Geräts laden (Datei APP-Updates.json)
function script:Restore-WolAppUpdates {
    param($Zeile, $S)
    $gespeichert = Read-WolGeraeteListe -Zeile $Zeile -Name 'APP-Updates'
    if (-not $gespeichert) { return }
    $S.Details = @(@($gespeichert.Daten.Details) | Where-Object { $_ })
    $S.Verlauf = @(@($gespeichert.Daten.Verlauf) | Where-Object { $_ })
    $S.WauVerlauf = @(@($gespeichert.Daten.WauVerlauf) | Where-Object { $_ })
    $S.DetailsStand = [string]$gespeichert.Stand
    if ($S.Updates -eq '') { $S.Updates = [string]@($S.Details).Count }
}

## Werte aus dem Sync-Objekt in die Zeile übernehmen (nur Werte, die das Modul gelesen hat)
function script:Update-WolAppZeile {
    param($Zeile, $S)
    $werte = [ordered]@{
        Windows = $S.Windows; NeustartAusstehend = $S.Neustart; LetzterNeustart = $S.LetzterNeustart
        AppModul = $S.Modul; AppUpdates = $S.Updates; AppWinget = $S.Winget; WauStatus = $S.Wau
    }
    foreach ($schluessel in $werte.Keys) {
        $wert = [string]$werte[$schluessel]
        if ($wert -and $Zeile[$schluessel] -ne $wert) { $Zeile[$schluessel] = $wert }
    }
    if ($S.GeplantBisGelesen -and $Zeile['GeplantBis'] -ne [string]$S.GeplantBis) { $Zeile['GeplantBis'] = [string]$S.GeplantBis }
}

## Timer des Moduls: zeigt den Fortschritt laufender Aufträge und öffnet die Deinstallations-Auswahl (ein Dialog in einem Auswertungs-Takt des NET-COCKPIT ginge nicht)
$script:AppTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:AppTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:AppTimer.Add_Tick({
    try {
        foreach ($eintrag in @($script:AppSync.GetEnumerator())) {
            $z = $eintrag.Key
            $S = $eintrag.Value
            if ((Get-WolGruppeOffen -Gruppe 'APP' -Zeile $z) -eq 0) { continue }
            Update-WolAppZeile -Zeile $z -S $S
            if ($S.Status) { $z.Status = [string]$S.Status }
        }
        if ($script:AppDeinstallWarten.Count -gt 0) {
            $script:AppTimer.Stop()
            try {
                $z = $script:AppDeinstallWarten[0]
                $script:AppDeinstallWarten.RemoveAt(0)
                Show-WolAppDeinstallation -Zeile $z
            }
            finally { $script:AppTimer.Start() }
        }
        if ($script:AppWauWarten.Count -gt 0) {
            $script:AppTimer.Stop()
            try {
                $lauf = $script:AppWauWarten[0]
                $script:AppWauWarten.RemoveAt(0)
                Show-WolAppWauAusschluesse -Lauf $lauf
            }
            finally { $script:AppTimer.Start() }
        }
        if ($script:AppListeWarten.Count -gt 0) {
            $script:AppTimer.Stop()
            try {
                $lauf = $script:AppListeWarten[0]
                $script:AppListeWarten.RemoveAt(0)
                Show-WolAppProgrammListe -Lauf $lauf
            }
            finally { $script:AppTimer.Start() }
        }
        if ((Get-WolGruppeOffen -Gruppe 'APP') -eq 0 -and $script:AppDeinstallWarten.Count -eq 0 -and $script:AppWauWarten.Count -eq 0 -and $script:AppListeWarten.Count -eq 0) { $script:AppTimer.Stop() }
    }
    catch { Write-WolLog "Fehler im Timer des Moduls APP: $($_.Exception.Message)" }
})

# Aufträge
## Auswertung eines Auftrags (läuft im Poll-Takt des NET-COCKPIT)
$script:AppFertig = {
    param($a)
    $z = $a.Zeile
    $S = $a.Daten.S
    $aktion = $a.Daten.Aktion
    try { $null = Receive-Job -Job $a.Job -ErrorAction Stop }
    catch { if (-not $S.Fehlertext) { $S.Fehlertext = $_.Exception.Message } }

    if ($S.Fehlertext) {
        $kurz = Register-WolVerbindungsfehler -Zeile $z -Text ([string]$S.Fehlertext)
        $S.Status = $(if ($S.Verbunden) { "Fehler: $kurz" } else { "Verbindung fehlgeschlagen: $kurz" })
    }
    elseif (-not $S.Status) { $S.Status = 'Beendet' }
    Update-WolAppZeile -Zeile $z -S $S
    Save-WolWerteZeile -Zeile $z -Neu:($aktion -eq 'Status' -and -not $S.Fehlertext)

    ### Neu gelesene Listen im Ordner des Geräts speichern (mit Zeitpunkt "gelesen am")
    $programmeNeu = $false
    if ($S.DetailsNeu) {
        $S.DetailsNeu = $false
        $S.DetailsStand = Save-WolGeraeteListe -Zeile $z -Name 'APP-Updates' -Daten ([ordered]@{ Details = @($S.Details); Verlauf = @($S.Verlauf); WauVerlauf = @($S.WauVerlauf) })
    }
    if ($aktion -in 'ProgrammeLesen', 'ProgrammeAnzeigen') {
        if ($S.ProgrammeNeu) {
            $S.ProgrammeNeu = $false
            $programmeNeu = $true
            $S.ProgrammeStand = Save-WolGeraeteListe -Zeile $z -Name 'APP-Programme' -Daten @($S.Programme)
        }
        else { Restore-WolAppProgramme -Zeile $z -S $S }
    }
    elseif ($S.ProgrammeNeu) {
        $S.ProgrammeNeu = $false
        $S.ProgrammeStand = Save-WolGeraeteListe -Zeile $z -Name 'APP-Programme' -Daten @($S.Programme)
    }
    ### Nach einer Deinstallation ist die gespeicherte Programmliste überholt
    if ($aktion -eq 'ProgrammDeinstallieren' -and -not $S.Fehlertext) {
        Remove-WolGeraeteListe -Zeile $z -Name 'APP-Programme'
        $S.Programme = @()
        $S.ProgrammeStand = ''
    }
    $z.Status = [string]$S.Status
    Write-WolLog ("APP {0}: {1}" -f $a.Daten.Name, $S.Status)

    ### Nach erfolgreicher Modul-Installation gleich den Status prüfen
    if ($aktion -eq 'Modul' -and $S.Status -eq 'Modul installiert') {
        Start-WolAppAktion -Aktion 'Status' -Ziele @($z)
    }

    ### WAU-Ausschlusslisten gelesen: sobald alle gelesenen Geräte fertig sind, den Dialog anstoßen
    if ($aktion -eq 'WauAusschluesseLesen' -and $script:AppWauLauf) {
        $offen = @($script:AppWauLauf.Lesen | Where-Object { (Get-WolGruppeOffen -Gruppe 'APP' -Zeile $_) -gt 0 })
        if ($offen.Count -eq 0) {
            $script:AppWauWarten.Add($script:AppWauLauf)
            $script:AppWauLauf = $null
            if (-not $script:AppTimer.IsEnabled) { $script:AppTimer.Start() }
        }
    }

    ### Programmlisten gelesen: sobald alle gelesenen Geräte fertig sind, die gemeinsame Anzeige anstoßen
    if ($aktion -eq 'ProgrammeAnzeigen' -and $script:AppListeLauf) {
        $offen = @($script:AppListeLauf.Zeilen | Where-Object { (Get-WolGruppeOffen -Gruppe 'APP' -Zeile $_) -gt 0 })
        if ($offen.Count -eq 0) {
            $script:AppListeWarten.Add($script:AppListeLauf)
            $script:AppListeLauf = $null
            if (-not $script:AppTimer.IsEnabled) { $script:AppTimer.Start() }
        }
    }

    if ($aktion -eq 'ProgrammeLesen' -and $programmeNeu -and -not $S.Fehlertext -and @($S.Programme).Count -gt 0) {
        $script:AppDeinstallWarten.Add($z)
        if (-not $script:AppTimer.IsEnabled) { $script:AppTimer.Start() }
    }
}

## Aktion für Geräte in die Warteschlange des NET-COCKPIT legen (nur grüne Geräte; Wert = WinGet-Id bei einzelnen Programmen)
function script:Start-WolAppAktion {
    param([string]$Aktion, $Ziele, [string]$Wert = '', [hashtable]$WertJe = $null)
    $Ziele = @($Ziele)
    $gruen = @($Ziele | Where-Object { $_.Ampel -eq 'Gruen' })
    foreach ($z in @($Ziele | Where-Object { $_.Ampel -ne 'Gruen' })) { $z.Status = 'WinRM nicht erreichbar - übersprungen' }
    if ($gruen.Count -eq 0) { Show-WolMeldung 'Keines der Geräte ist grün (WinRM erreichbar).'; return }
    if (-not (Resolve-WolKonten -Zeilen $gruen)) { return }
    if (-not (Test-Path -LiteralPath $script:AppLogOrdner)) { New-Item -Path $script:AppLogOrdner -ItemType Directory -Force | Out-Null }

    $gestartet = 0
    foreach ($z in $gruen) {
        if ((Get-WolGruppeOffen -Gruppe 'APP' -Zeile $z) -gt 0) { continue }
        try { $konto = Get-WolAnmeldung -Zeile $z }
        catch { $z.Status = $_.Exception.Message; continue }

        $S = Get-WolAppSync -Zeile $z
        $S.Status = ''
        $S.Fehlertext = ''
        $S.Verbunden = $false
        $S.NeustartGemeldet = $false
        $S.GeplantBisGelesen = $false
        $S.WauGelesen = $false

        $wertGeraet = $(if ($WertJe -and $WertJe.ContainsKey($z)) { [string]$WertJe[$z] } else { $Wert })
        $name = $(if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { [string]$z.IP })
        $logDatei = Join-Path $script:AppLogOrdner ('{0:yyyyMMdd}_{1}_app-log.txt' -f (Get-Date), ($name -replace '[^\w\.\-]', '_'))
        Add-WolAuftrag -Zeile $z -Block $script:AppBlock -Argumente @((Get-WolZielName -Zeile $z), $Aktion, $konto, $S, $logDatei, $script:ZielTaskCode, $wertGeraet, $script:AppSkripte) -Fertig $script:AppFertig -Gruppe 'APP' -Daten @{ Aktion = $Aktion; S = $S; Name = $name } -Starttext 'APP: Verbinde...'
        $gestartet++
    }
    if ($gestartet -eq 0) { Write-WolLog 'APP: Auf den Geräten läuft schon eine Aktion des Moduls'; return }
    Write-WolLog "APP $Aktion : $gestartet Gerät(e)"
    if (-not $script:AppTimer.IsEnabled) { $script:AppTimer.Start() }
}

# Dialoge
## Markierte Geräte holen (mit Hinweis, wenn keins markiert ist); -Genau 1 verlangt genau ein Gerät
function script:Get-WolAppZiele {
    param([int]$Genau = 0)
    $ziele = @(Get-WolMarkierte)
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return $null }
    if ($Genau -gt 0 -and $ziele.Count -ne $Genau) { Show-WolMeldung 'Bitte genau ein Gerät markieren.'; return $null }
    return , $ziele
}

## Namen der Geräte für Texte (Hostname, sonst IP)
function script:Get-WolAppNamen {
    param($Zeilen)
    return (@($Zeilen | ForEach-Object { if ($_.Hostname) { ([string]$_.Hostname).Split('.')[0] } else { [string]$_.IP } }) -join ', ')
}

## Abfrage der WinGet-Id für die Programm-Installation; Rückgabe: Id oder $null bei Abbruch
function script:Read-WolAppProgrammId {
    param([string]$Namen)
    $vorgabe = ''
    while ($true) {
        $id = Show-WolEingabe -Titel 'Programm installieren' -Frage "WinGet-Id des Programms (zum Beispiel 7zip.7zip) für: $Namen" -Vorgabe $vorgabe -Hinweis 'Die Id muss exakt stimmen (Suche mit: winget search Programmname). Installiert wird still und maschinenweit über eine Aufgabe als SYSTEM.'
        if ($null -eq $id) { return $null }
        $id = $id.Trim()
        if ($id -match '^[A-Za-z0-9][A-Za-z0-9._+\-]*$') { return $id }
        Show-WolMeldung 'Bitte eine gültige WinGet-Id eingeben (nur Buchstaben, Ziffern und . _ + -), zum Beispiel 7zip.7zip.' 'Warning'
        $vorgabe = $id
    }
}

## Programmliste eines Geräts ist gelesen: Auswahl zeigen, bestätigen lassen und die Deinstallation starten
function script:Show-WolAppDeinstallation {
    param($Zeile)
    $liste = @((Get-WolAppSync -Zeile $Zeile).Programme)
    $name = Get-WolAppNamen -Zeilen @($Zeile)
    if ($liste.Count -eq 0) { Show-WolMeldung "Auf $name konnten keine Programme gelesen werden. Details stehen im Log des Geräts." 'Warning'; return }

    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Programm deinstallieren" Width="900" Height="620" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="LblKopf" Grid.Row="0" FontWeight="Bold" Margin="0,0,0,8"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="Suchen:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="TxtSuche" Width="300" Margin="0,0,18,0"/>
      <CheckBox x:Name="ChkWinget" Content="Nur Quelle winget" IsChecked="True" VerticalAlignment="Center"/>
    </StackPanel>
    <DataGrid x:Name="Raster" Grid.Row="2" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="True"
              SelectionMode="Single" SelectionUnit="FullRow" GridLinesVisibility="Horizontal">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Name"    Binding="{Binding Name, Mode=OneWay}"    Width="280"/>
        <DataGridTextColumn Header="Id"      Binding="{Binding Id, Mode=OneWay}"      Width="*"/>
        <DataGridTextColumn Header="Version" Binding="{Binding Version, Mode=OneWay}" Width="130"/>
        <DataGridTextColumn Header="Quelle"  Binding="{Binding Quelle, Mode=OneWay}"  Width="80"/>
      </DataGrid.Columns>
    </DataGrid>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnOk" Content="Deinstallieren" Padding="14,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BtnAbbruch" Content="Abbrechen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $raster = $f.FindName('Raster')
    $suche = $f.FindName('TxtSuche')
    $chk = $f.FindName('ChkWinget')
    $f.FindName('LblKopf').Text = "Installierte Programme auf $name ($($liste.Count))"

    $raster.ItemsSource = $liste
    $ansicht = [System.Windows.Data.CollectionViewSource]::GetDefaultView($raster.ItemsSource)
    $pruefen = {
        param($zeile)
        if ($chk.IsChecked -and $zeile.Quelle -ne 'winget') { return $false }
        $t = $suche.Text.Trim()
        if (-not $t) { return $true }
        return (($zeile.Name.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($zeile.Id.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))
    }.GetNewClosure()
    $ansicht.Filter = [System.Predicate[object]]$pruefen
    $suche.Add_TextChanged({ $ansicht.Refresh() }.GetNewClosure())
    $chk.Add_Checked({ $ansicht.Refresh() }.GetNewClosure())
    $chk.Add_Unchecked({ $ansicht.Refresh() }.GetNewClosure())
    $f.Add_Loaded({ [void]$suche.Focus() }.GetNewClosure())

    $erg = @{ Programm = $null }
    $f.FindName('BtnOk').Add_Click({
        $gewaehlt = $raster.SelectedItem
        if (-not $gewaehlt) {
            [void][System.Windows.MessageBox]::Show($f, 'Bitte ein Programm in der Liste auswählen.', 'Programm deinstallieren', 'OK', 'Warning')
            return
        }
        $erg.Programm = $gewaehlt
        $f.DialogResult = $true
    }.GetNewClosure())
    if ($f.ShowDialog() -ne $true) { return }

    $wahl = $erg.Programm
    $antwort = [System.Windows.MessageBox]::Show("Programm auf $name deinstallieren?`r`n`r`nName: $($wahl.Name)`r`nId: $($wahl.Id)`r`nVersion: $($wahl.Version)", 'Programm deinstallieren', 'YesNo', 'Warning')
    if ($antwort -eq 'Yes') { Start-WolAppAktion -Aktion 'ProgrammDeinstallieren' -Ziele @($Zeile) -Wert $wahl.Id }
}

## Programmlisten der markierten Geräte sind gelesen: eine gemeinsame Liste mit Suche, Filter und CSV-Export zeigen (nur Anzeige, nichts wird verändert)
function script:Show-WolAppProgrammListe {
    param($Lauf)
    $eintraege = [System.Collections.Generic.List[object]]::new()
    $ohneDaten = [System.Collections.Generic.List[string]]::new()
    foreach ($z in @($Lauf.Zeilen)) {
        $geraet = Get-WolAppNamen -Zeilen @($z)
        $sz = Get-WolAppSync -Zeile $z
        $programme = @($sz.Programme)
        if ($programme.Count -eq 0) { $ohneDaten.Add($geraet); continue }
        $gelesen = Format-WolStand $sz.ProgrammeStand
        foreach ($p in $programme) {
            $eintraege.Add([pscustomobject]@{ Geraet = $geraet; Name = [string]$p.Name; Id = [string]$p.Id; Version = [string]$p.Version; Quelle = [string]$p.Quelle; Gelesen = $gelesen })
        }
    }
    if ($eintraege.Count -eq 0) {
        Show-WolMeldung ("Es konnten keine Programme gelesen werden.`r`nGeräte: {0}`r`nDetails stehen im Log des jeweiligen Geräts." -f ($ohneDaten -join ', ')) 'Warning'
        return
    }

    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Installierte Programme" Width="1000" Height="640" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="LblKopf" Grid.Row="0" FontWeight="Bold" Margin="0,0,0,8"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="Suchen:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="TxtSuche" Width="300" Margin="0,0,18,0" ToolTip="Sucht in Gerät, Name und Id"/>
      <CheckBox x:Name="ChkWinget" Content="Nur Quelle winget" IsChecked="False" VerticalAlignment="Center"/>
    </StackPanel>
    <DataGrid x:Name="Raster" Grid.Row="2" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="True"
              SelectionMode="Extended" SelectionUnit="FullRow" GridLinesVisibility="Horizontal">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Gerät"   Binding="{Binding Geraet, Mode=OneWay}"  Width="160"/>
        <DataGridTextColumn Header="Name"    Binding="{Binding Name, Mode=OneWay}"    Width="280"/>
        <DataGridTextColumn Header="Id"      Binding="{Binding Id, Mode=OneWay}"      Width="*"/>
        <DataGridTextColumn Header="Version" Binding="{Binding Version, Mode=OneWay}" Width="130"/>
        <DataGridTextColumn Header="Quelle"  Binding="{Binding Quelle, Mode=OneWay}"  Width="80"/>
        <DataGridTextColumn Header="Gelesen am" Binding="{Binding Gelesen, Mode=OneWay}" Width="120"/>
      </DataGrid.Columns>
    </DataGrid>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnNeu" Content="Neu auslesen" Padding="14,4" Margin="0,0,8,0" ToolTip="Liest die Programme der Geräte in dieser Liste neu aus (nur grüne Geräte) und öffnet die Liste danach erneut"/>
      <Button x:Name="BtnExport" Content="Exportieren (CSV)..." Padding="14,4" Margin="0,0,8,0" ToolTip="Schreibt die aktuell angezeigten Zeilen in eine CSV-Datei (Semikolon, für Excel)"/>
      <Button x:Name="BtnSchliessen" Content="Schließen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $raster = $f.FindName('Raster')
    $suche = $f.FindName('TxtSuche')
    $chk = $f.FindName('ChkWinget')
    $kopf = $f.FindName('LblKopf')
    $gesamt = $eintraege.Count
    $anzahlGeraete = @($eintraege | Select-Object -ExpandProperty Geraet -Unique).Count
    $startOrdner = $(if ($script:ListenPfad) { Split-Path -Path $script:ListenPfad } else { $script:DatenOrdner })
    $geraeteZeilen = @($Lauf.Zeilen)

    $raster.ItemsSource = $eintraege
    $ansicht = [System.Windows.Data.CollectionViewSource]::GetDefaultView($raster.ItemsSource)
    $pruefen = {
        param($zeile)
        if ($chk.IsChecked -and $zeile.Quelle -ne 'winget') { return $false }
        $t = $suche.Text.Trim()
        if (-not $t) { return $true }
        return (($zeile.Name.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($zeile.Id.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($zeile.Geraet.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0))
    }.GetNewClosure()
    $ansicht.Filter = [System.Predicate[object]]$pruefen
    $aktualisieren = {
        $ansicht.Refresh()
        $kopf.Text = ('Installierte Programme auf {0} Gerät(en): {1} von {2}' -f $anzahlGeraete, @($ansicht).Count, $gesamt)
    }.GetNewClosure()
    & $aktualisieren
    $suche.Add_TextChanged({ & $aktualisieren }.GetNewClosure())
    $chk.Add_Checked({ & $aktualisieren }.GetNewClosure())
    $chk.Add_Unchecked({ & $aktualisieren }.GetNewClosure())
    $f.Add_Loaded({ [void]$suche.Focus() }.GetNewClosure())

    $f.FindName('BtnExport').Add_Click({
        $dlg = [Microsoft.Win32.SaveFileDialog]::new()
        $dlg.Title = 'Programmliste exportieren'
        $dlg.Filter = 'CSV-Datei (*.csv)|*.csv'
        $dlg.FileName = ('Installierte-Programme_{0:yyyyMMdd}.csv' -f (Get-Date))
        if ($startOrdner -and (Test-Path -LiteralPath $startOrdner)) { $dlg.InitialDirectory = $startOrdner }
        if ($dlg.ShowDialog($f) -ne $true) { return }
        try {
            $zeilen = @($ansicht)
            $zeilen | Select-Object @{ Name = 'Gerät'; Expression = { $_.Geraet } }, Name, Id, Version, Quelle, @{ Name = 'Gelesen am'; Expression = { $_.Gelesen } } | Export-Csv -Path $dlg.FileName -Delimiter ';' -NoTypeInformation -Encoding utf8BOM
            [void][System.Windows.MessageBox]::Show($f, ("{0} Zeilen exportiert:`r`n{1}" -f $zeilen.Count, $dlg.FileName), 'Programmliste exportieren', 'OK', 'Information')
        }
        catch {
            [void][System.Windows.MessageBox]::Show($f, "Der Export ist fehlgeschlagen: $($_.Exception.Message)", 'Programmliste exportieren', 'OK', 'Warning')
        }
    }.GetNewClosure())
    $f.FindName('BtnNeu').Add_Click({ $f.Close(); Start-WolAppProgrammListeNeu -Zeilen $geraeteZeilen }.GetNewClosure())
    $f.FindName('BtnSchliessen').Add_Click({ $f.Close() }.GetNewClosure())

    $f.Show()
    if ($ohneDaten.Count -gt 0) {
        Show-WolMeldung ("Für diese Geräte konnten keine Programme gelesen werden: {0}`r`nDetails stehen im Log des jeweiligen Geräts." -f ($ohneDaten -join ', ')) 'Warning'
    }
}

## Details eines Geräts: verfügbare Updates, Cockpit-Verlauf, WAU-Verlauf und Log
function script:Show-WolAppDetails {
    param($Zeile)
    $S = Get-WolAppSync -Zeile $Zeile
    $name = Get-WolAppNamen -Zeilen @($Zeile)
    $verfuegbar = @(@($S.Details) | Where-Object { $_ })
    $verlauf = @(@($S.Verlauf) | Where-Object { $_ })
    $wau = @(@($S.WauVerlauf) | Where-Object { $_ })
    $programme = @(@($S.Programme) | Where-Object { $_ })
    $log = @($S.Log.ToArray())
    if ($verfuegbar.Count -eq 0 -and $verlauf.Count -eq 0 -and $wau.Count -eq 0 -and $programme.Count -eq 0 -and $log.Count -eq 0) {
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
            <DataGridTextColumn Header="Name"        Binding="{Binding Name, Mode=OneWay}"       Width="*"/>
            <DataGridTextColumn Header="Id"          Binding="{Binding Id, Mode=OneWay}"         Width="280"/>
            <DataGridTextColumn Header="Installiert" Binding="{Binding Version, Mode=OneWay}"    Width="150"/>
            <DataGridTextColumn Header="Verfügbar"   Binding="{Binding Verfuegbar, Mode=OneWay}" Width="150"/>
            <DataGridTextColumn Header="Quelle"      Binding="{Binding Quelle, Mode=OneWay}"     Width="90"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
      <TabItem x:Name="TabProgramme">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,6,0,6">
            <TextBlock Text="Suchen:" VerticalAlignment="Center" Margin="6,0,6,0"/>
            <TextBox x:Name="TxtProgSuche" Width="300" ToolTip="Sucht in Name und Id"/>
            <TextBlock x:Name="LblProgStand" VerticalAlignment="Center" Margin="18,0,0,0" Foreground="DimGray"/>
          </StackPanel>
          <DataGrid x:Name="TabelleProgramme" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Name"    Binding="{Binding Name, Mode=OneWay}"    Width="*"/>
              <DataGridTextColumn Header="Id"      Binding="{Binding Id, Mode=OneWay}"      Width="320"/>
              <DataGridTextColumn Header="Version" Binding="{Binding Version, Mode=OneWay}" Width="170"/>
              <DataGridTextColumn Header="Quelle"  Binding="{Binding Quelle, Mode=OneWay}"  Width="90"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>
      <TabItem x:Name="TabVerlauf">
        <DataGrid x:Name="TabelleVerlauf" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Datum"    Binding="{Binding Datum, Mode=OneWay}"    Width="140"/>
            <DataGridTextColumn Header="Name"     Binding="{Binding Name, Mode=OneWay}"     Width="*"/>
            <DataGridTextColumn Header="Id"       Binding="{Binding Id, Mode=OneWay}"       Width="240"/>
            <DataGridTextColumn Header="Von"      Binding="{Binding Von, Mode=OneWay}"      Width="120"/>
            <DataGridTextColumn Header="Nach"     Binding="{Binding Nach, Mode=OneWay}"     Width="120"/>
            <DataGridTextColumn Header="Ergebnis" Binding="{Binding Ergebnis, Mode=OneWay}" Width="260"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
      <TabItem x:Name="TabWau">
        <DataGrid x:Name="TabelleWau" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Datum"    Binding="{Binding Datum, Mode=OneWay}"    Width="140"/>
            <DataGridTextColumn Header="Name"     Binding="{Binding Name, Mode=OneWay}"     Width="*"/>
            <DataGridTextColumn Header="Id"       Binding="{Binding Id, Mode=OneWay}"       Width="240"/>
            <DataGridTextColumn Header="Von"      Binding="{Binding Von, Mode=OneWay}"      Width="120"/>
            <DataGridTextColumn Header="Nach"     Binding="{Binding Nach, Mode=OneWay}"     Width="120"/>
            <DataGridTextColumn Header="Ergebnis" Binding="{Binding Ergebnis, Mode=OneWay}" Width="260"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
      <TabItem x:Name="TabLog">
        <TextBox x:Name="TxtLog" IsReadOnly="True" FontFamily="Consolas" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
    </TabControl>
  </Grid>
</Window>
'@
    $stand = Format-WolStand $S.DetailsStand
    $f.Title = "Programm-Updates auf $name" + $(if ($stand) { " (gelesen am $stand)" } else { '' })
    $f.Owner = $script:Fenster
    $f.FindName('TabelleVerfuegbar').ItemsSource = $verfuegbar
    $f.FindName('TabelleVerlauf').ItemsSource = $verlauf
    $f.FindName('TabelleWau').ItemsSource = $wau
    $f.FindName('TabVerfuegbar').Header = "Verfügbare Updates ($($verfuegbar.Count))"
    $f.FindName('TabProgramme').Header = "Installierte Programme ($($programme.Count))"
    $f.FindName('TabelleProgramme').ItemsSource = $programme
    $progStand = Format-WolStand $S.ProgrammeStand
    $f.FindName('LblProgStand').Text = $(if ($progStand) { "gelesen am $progStand" } else { 'noch nicht gelesen (Status prüfen)' })
    $progSuche = $f.FindName('TxtProgSuche')
    $progAnsicht = [System.Windows.Data.CollectionViewSource]::GetDefaultView($programme)
    $progSuche.Add_TextChanged({
        $t = $progSuche.Text.Trim()
        if ($t) {
            $pruefen = {
                param($p)
                return (([string]$p.Name).IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or (([string]$p.Id).IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            }.GetNewClosure()
            $progAnsicht.Filter = [System.Predicate[object]]$pruefen
        }
        else { $progAnsicht.Filter = $null }
    }.GetNewClosure())
    $f.FindName('TabVerlauf').Header = "Cockpit-Verlauf ($($verlauf.Count))"
    $f.FindName('TabWau').Header = "WAU-Verlauf ($($wau.Count))"
    $f.FindName('TabLog').Header = "Log ($($log.Count))"
    $f.FindName('TxtLog').Text = ($log -join "`r`n")
    if ($verfuegbar.Count -eq 0) {
        $f.FindName('Reiter').SelectedIndex = $(if ($programme.Count -gt 0) { 1 } elseif ($verlauf.Count -gt 0) { 2 } elseif ($wau.Count -gt 0) { 3 } else { 4 })
    }
    [void]$f.ShowDialog()
}

# Aktionen des Moduls
## Status prüfen
function script:Start-WolAppStatus {
    $ziele = Get-WolAppZiele
    if ($ziele) { Start-WolAppAktion -Aktion 'Status' -Ziele $ziele }
}

## App-Updates installieren: Auswahlfenster mit den Updates aller markierten Geräte (aus deren letztem "Status prüfen"), installiert wird nur das Angehakte und nur auf Geräten, die das Update haben
function script:Start-WolAppInstallieren {
    $ziele = Get-WolAppZiele
    if (-not $ziele) { return }
    $gruen = @($ziele | Where-Object { $_.Ampel -eq 'Gruen' })
    foreach ($z in @($ziele | Where-Object { $_.Ampel -ne 'Gruen' })) { $z.Status = 'WinRM nicht erreichbar - übersprungen' }
    if ($gruen.Count -eq 0) { Show-WolMeldung 'Keines der Geräte ist grün (WinRM erreichbar).'; return }

    ### Geräte mit Statusdaten (Updates ist erst nach "Status prüfen" gefüllt)
    $mitDaten = [System.Collections.Generic.List[object]]::new()
    foreach ($z in $gruen) {
        if ((Get-WolAppSync -Zeile $z).Updates -eq '') { $z.Status = 'Bitte zuerst Status prüfen' } else { $mitDaten.Add($z) }
    }
    if ($mitDaten.Count -eq 0) { Show-WolMeldung 'Bitte zuerst Status prüfen. Die Auswahl baut auf dem Ergebnis auf.'; return }

    ### Gemeinsame Liste: jedes Programm einmal, mit der Zahl der Geräte, die das Update haben
    $apps = [ordered]@{}
    foreach ($z in $mitDaten) {
        foreach ($u in @((Get-WolAppSync -Zeile $z).Details | Where-Object { $_ })) {
            if (-not $apps.Contains($u.Id)) { $apps[$u.Id] = @{ Name = $u.Name; Id = $u.Id; Geraete = [System.Collections.Generic.List[object]]::new() } }
            if (-not $apps[$u.Id].Geraete.Contains($z)) { $apps[$u.Id].Geraete.Add($z) }
        }
    }
    if ($apps.Count -eq 0) { Show-WolMeldung 'Auf den markierten Geräten sind laut Status keine Updates verfügbar.'; return }

    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="App-Updates installieren" Width="520" Height="540" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="LblKopf" Grid.Row="0" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
      <Button x:Name="BtnAlle" Content="Alle markieren" Padding="10,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnKeine" Content="Keine markieren" Padding="10,4"/>
    </StackPanel>
    <Border Grid.Row="2" BorderBrush="LightGray" BorderThickness="1">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="Liste" Margin="8"/>
      </ScrollViewer>
    </Border>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnOk" Content="Installieren" Padding="14,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BtnAbbruch" Content="Abbrechen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $staende = @($mitDaten | ForEach-Object { [string](Get-WolAppSync -Zeile $_).DetailsStand } | Where-Object { $_ } | Sort-Object)
    $standText = ''
    if ($staende.Count -gt 0) { $standText = "`r`nListe gelesen am: " + (Format-WolStand $staende[0]) + $(if ($staende[0] -ne $staende[-1]) { ' (ältester Stand)' } else { '' }) }
    $f.FindName('LblKopf').Text = "Updates auf $($mitDaten.Count) Gerät(en): $(Get-WolAppNamen -Zeilen $mitDaten)$standText"
    $liste = $f.FindName('Liste')
    $boxen = [System.Collections.Generic.List[object]]::new()
    foreach ($a in @($apps.Values | Sort-Object { $_.Name })) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = '{0} ({1} von {2})' -f $a.Name, $a.Geraete.Count, $mitDaten.Count
        $cb.ToolTip = $a.Id
        $cb.Margin = '0,0,0,4'
        $cb.Tag = $a.Id
        ### Microsoft.PowerShell ist nicht vorangehakt, alles andere schon
        $cb.IsChecked = ($a.Id -ne 'Microsoft.PowerShell')
        [void]$liste.Children.Add($cb)
        $boxen.Add($cb)
    }
    $f.FindName('BtnAlle').Add_Click({ foreach ($b in $boxen) { $b.IsChecked = $true } }.GetNewClosure())
    $f.FindName('BtnKeine').Add_Click({ foreach ($b in $boxen) { $b.IsChecked = $false } }.GetNewClosure())
    $f.FindName('BtnOk').Add_Click({
        if (-not @($boxen | Where-Object { $_.IsChecked }).Count) {
            [void][System.Windows.MessageBox]::Show($f, 'Bitte mindestens ein Update auswählen.', 'App-Updates installieren', 'OK', 'Warning')
            return
        }
        $f.DialogResult = $true
    }.GetNewClosure())
    if ($f.ShowDialog() -ne $true) { return }

    ### Je Gerät nur die gewählten Ids, die es auch hat
    $gewaehlt = @($boxen | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
    $wertJe = @{}
    $zuInstallieren = [System.Collections.Generic.List[object]]::new()
    foreach ($z in $mitDaten) {
        $ids = @($gewaehlt | Where-Object { $apps[$_].Geraete.Contains($z) })
        if ($ids.Count -eq 0) { $z.Status = 'Kein gewähltes Update - übersprungen'; continue }
        $wertJe[$z] = $ids -join '|'
        $zuInstallieren.Add($z)
    }
    if ($zuInstallieren.Count -eq 0) { Show-WolMeldung 'Auf keinem Gerät ist ein gewähltes Update verfügbar.'; return }
    Start-WolAppAktion -Aktion 'Installieren' -Ziele $zuInstallieren -WertJe $wertJe
}

## Programm installieren: Id abfragen, bestätigen lassen
function script:Start-WolAppProgramm {
    $ziele = Get-WolAppZiele
    if (-not $ziele) { return }
    $namen = Get-WolAppNamen -Zeilen $ziele
    $id = Read-WolAppProgrammId -Namen $namen
    if (-not $id) { return }
    $antwort = [System.Windows.MessageBox]::Show("Programm $id auf diesen Geräten installieren?`r`n`r`n$($namen -replace ', ', "`r`n")", 'Programm installieren', 'YesNo', 'Question')
    if ($antwort -eq 'Yes') { Start-WolAppAktion -Aktion 'ProgrammInstallieren' -Ziele $ziele -Wert $id }
}

## Programm deinstallieren: Programmliste des markierten Geräts lesen (danach öffnet der Timer die Auswahl)
function script:Start-WolAppDeinstallieren {
    $ziele = Get-WolAppZiele -Genau 1
    if ($ziele) { Start-WolAppAktion -Aktion 'ProgrammeLesen' -Ziele $ziele }
}

## Installierte Programme anzeigen: gespeicherte Listen sofort zeigen, nur Geräte ohne gespeicherte Liste werden gelesen (danach öffnet der Timer die gemeinsame Liste)
function script:Start-WolAppProgrammListe {
    $ziele = Get-WolAppZiele
    if (-not $ziele) { return }
    $ohneListe = @($ziele | Where-Object { @((Get-WolAppSync -Zeile $_).Programme).Count -eq 0 })
    $lesen = @($ohneListe | Where-Object { $_.Ampel -eq 'Gruen' -and (Get-WolGruppeOffen -Gruppe 'APP' -Zeile $_) -eq 0 })
    if ($lesen.Count -eq 0) {
        Show-WolAppProgrammListe -Lauf @{ Zeilen = @($ziele) }
        return
    }
    $script:AppListeLauf = @{ Zeilen = @($ziele) }
    Start-WolAppAktion -Aktion 'ProgrammeAnzeigen' -Ziele $lesen
}

## Programmlisten der Geräte aus der Liste-Anzeige neu lesen (Knopf "Neu auslesen"); Geräte ohne Verbindung behalten ihre gespeicherte Liste
function script:Start-WolAppProgrammListeNeu {
    param($Zeilen)
    $Zeilen = @($Zeilen)
    $lesen = @($Zeilen | Where-Object { $_.Ampel -eq 'Gruen' -and (Get-WolGruppeOffen -Gruppe 'APP' -Zeile $_) -eq 0 })
    if ($lesen.Count -eq 0) {
        Show-WolMeldung 'Keines der Geräte ist grün (WinRM erreichbar) oder frei (es läuft schon eine Aktion des Moduls). Die gespeicherten Listen bleiben erhalten.'
        Show-WolAppProgrammListe -Lauf @{ Zeilen = $Zeilen }
        return
    }
    $script:AppListeLauf = @{ Zeilen = $Zeilen }
    Start-WolAppAktion -Aktion 'ProgrammeAnzeigen' -Ziele $lesen
}

## WinGet-Modul nachinstallieren (Geräte, bei denen es schon da ist, werden übersprungen)
function script:Start-WolAppModul {
    $ziele = Get-WolAppZiele
    if (-not $ziele) { return }
    $schon = @($ziele | Where-Object { $_['AppModul'] -eq 'Ja' })
    $offen = @($ziele | Where-Object { $_['AppModul'] -ne 'Ja' })
    if ($schon.Count -gt 0) {
        Show-WolMeldung ("Microsoft.WinGet.Client ist auf diesen Geräten bereits vorhanden:`r`n`r`n" + ((Get-WolAppNamen -Zeilen $schon) -replace ', ', "`r`n"))
    }
    if ($offen.Count -eq 0) { return }
    $frage = "PowerShell 7 (falls nötig) und das Modul Microsoft.WinGet.Client auf diesen Geräten installieren?`r`n`r`n$((Get-WolAppNamen -Zeilen $offen) -replace ', ', "`r`n")`r`n`r`nDie Geräte brauchen dafür Internetzugang (PowerShell-7-Download und PSGallery)."
    if ([System.Windows.MessageBox]::Show($frage, 'WinGet-Modul nachinstallieren', 'YesNo', 'Question') -eq 'Yes') {
        Start-WolAppAktion -Aktion 'Modul' -Ziele $offen
    }
}

## Eingabefenster für die WAU-Ausschlussliste (eine WinGet-Id je Zeile); Rückgabe: bereinigter Text oder $null bei Abbruch
function script:Show-WolAppWauDialog {
    param([string]$Titel, [string]$Kopf, [string]$Hinweis, [string]$Vorgabe, [string]$OkText)
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" Height="560" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="LblKopf" Grid.Row="0" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,6"/>
    <TextBlock x:Name="LblHinweis" Grid.Row="1" TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,8"/>
    <TextBox x:Name="TxtListe" Grid.Row="2" AcceptsReturn="True" TextWrapping="NoWrap" FontFamily="Consolas" FontSize="13"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnOk" Padding="14,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnAbbruch" Content="Abbrechen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $f.Title = $Titel
    $f.FindName('LblKopf').Text = $Kopf
    $f.FindName('LblHinweis').Text = $Hinweis
    $box = $f.FindName('TxtListe')
    $box.Text = $Vorgabe
    $f.FindName('BtnOk').Content = $OkText
    $erg = @{ Text = $null }
    $f.FindName('BtnOk').Add_Click({
        $zeilen = @($box.Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
        $erg.Text = $zeilen -join "`r`n"
        $f.DialogResult = $true
    }.GetNewClosure())
    if ($f.ShowDialog() -ne $true) { return $null }
    return [string]$erg.Text
}

## Ausschlussliste für den Versand an das Gerät kodieren (Base64 von UTF-8, damit keine Sonderzeichen stören)
function script:ConvertTo-WolAppWauListe {
    param([string]$Text)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

## WAU-Listen sind gelesen: Dialog mit der Liste zeigen und auf alle markierten Geräte schreiben
function script:Show-WolAppWauAusschluesse {
    param($Lauf)
    $gelesen = @($Lauf.Lesen | Where-Object { (Get-WolAppSync -Zeile $_).WauGelesen })
    if ($gelesen.Count -eq 0) {
        Show-WolMeldung "Auf keinem der Geräte konnte eine WAU-Ausschlussliste gelesen werden (Status der Geräte beachten)." 'Warning'
        return
    }
    $listen = @{}
    foreach ($z in $gelesen) {
        $eintraege = @(([string](Get-WolAppSync -Zeile $z).WauListe) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $listen[$z] = $eintraege
    }
    $erster = @($gelesen | Where-Object { $listen[$_].Count -gt 0 })[0]
    $hinweis = 'Eine WinGet-Id je Zeile, Platzhalter * erlaubt. Beim Speichern wird die Liste auf allen markierten Geräten mit normaler WAU ersetzt. Geräte mit der Intune-Variante werden nicht geändert.'
    if ($erster) {
        $vorgabe = $listen[$erster] -join "`r`n"
        $schluessel = { param($z) (@($listen[$z] | Sort-Object { $_.ToLowerInvariant() }) -join '|').ToLowerInvariant() }
        $abweichend = @($gelesen | Where-Object { (& $schluessel $_) -ne (& $schluessel $erster) })
        if ($abweichend.Count -gt 0) {
            $hinweis += "`r`n`r`nAchtung: Die Listen sind nicht gleich. Gezeigt wird die Liste von $(Get-WolAppNamen -Zeilen @($erster)). Abweichend: $(Get-WolAppNamen -Zeilen $abweichend)."
        }
    }
    else {
        $vorgabe = $script:AppWauStandard -join "`r`n"
        $hinweis += "`r`n`r`nAuf den gelesenen Geräten gibt es noch keine Liste, vorbelegt ist der Standardvorschlag."
    }
    $kopf = 'WAU-Ausschlüsse bearbeiten für: ' + (Get-WolAppNamen -Zeilen $Lauf.Ziele)
    $text = Show-WolAppWauDialog -Titel 'WAU-Ausschlüsse bearbeiten' -Kopf $kopf -Hinweis $hinweis -Vorgabe $vorgabe -OkText 'Speichern'
    if ($null -eq $text) { return }
    Start-WolAppAktion -Aktion 'WauAusschluesse' -Ziele $Lauf.Ziele -Wert (ConvertTo-WolAppWauListe -Text $text)
}

## WAU installieren: ein Dialog mit der Ausschlussliste für alle markierten Geräte; Geräte mit WAU (auch Intune-Variante) werden auf dem Gerät übersprungen
function script:Start-WolAppWauInstallieren {
    $ziele = Get-WolAppZiele
    if (-not $ziele) { return }
    $kopf = 'Winget-AutoUpdate (WAU) installieren auf: ' + (Get-WolAppNamen -Zeilen $ziele)
    $hinweis = 'Ausschlussliste: eine WinGet-Id je Zeile, Platzhalter * erlaubt. Einstellungen: Updates monatlich und bei Anmeldung, Benachrichtigung nur bei Erfolg. Geräte, auf denen WAU schon läuft (auch die Intune-Variante), werden übersprungen. Das Gerät braucht Internetzugang und das WinGet-Modul.'
    $text = Show-WolAppWauDialog -Titel 'WAU installieren' -Kopf $kopf -Hinweis $hinweis -Vorgabe ($script:AppWauStandard -join "`r`n") -OkText 'Installieren'
    if ($null -eq $text) { return }
    Start-WolAppAktion -Aktion 'WauInstallieren' -Ziele $ziele -Wert (ConvertTo-WolAppWauListe -Text $text)
}

## WAU-Ausschlüsse bearbeiten: liest die Listen der markierten Geräte mit normaler WAU, danach öffnet sich der Dialog
function script:Start-WolAppWauAusschluesse {
    $ziele = Get-WolAppZiele
    if (-not $ziele) { return }
    $lesen = @($ziele | Where-Object { $_.Ampel -eq 'Gruen' -and [string]$_['WauStatus'] -notin 'Intune', 'Nein' })
    if ($lesen.Count -eq 0) {
        Show-WolMeldung "Auf den markierten Geräten ist keine normale WAU bekannt (oder sie sind nicht grün).`r`nBitte zuerst Status prüfen. Bei der Intune-Variante wird die Liste über Intune gepflegt."
        return
    }
    $script:AppWauLauf = @{ Ziele = $ziele; Lesen = $lesen }
    Start-WolAppAktion -Aktion 'WauAusschluesseLesen' -Ziele $lesen
}

## Details des markierten Geräts
function script:Start-WolAppDetails {
    $ziele = Get-WolAppZiele -Genau 1
    if ($ziele) { Show-WolAppDetails -Zeile $ziele[0] }
}

# Fenster des Moduls
## Wird vom Menü Module > APP aufgerufen: kleines Fenster neben der Tabelle (bleibt offen, die Tabelle bleibt bedienbar)
function script:Show-WolModulAPP {
    if ($script:AppFenster) {
        $script:AppFenster.Activate()
        Set-WolModulOffen -Key 'APP' -Offen $true
        return
    }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="APP-Updates" Width="400" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Wirkt auf die markierten Geräte der Tabelle (nur grüne, WinRM erreichbar). Aufträge laufen über die Warteschlange des NET-COCKPIT." TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,12"/>
    <CheckBox x:Name="ChkSpalten" Content="Spalten des Moduls in der Tabelle anzeigen" Margin="0,0,0,10"
              ToolTip="Blendet die Spalten dieses Moduls in der Tabelle ein (Standard: aus). Beim Schließen des Fensters werden sie wieder ausgeblendet"/>
    <Button x:Name="BtnStatus" Content="Status prüfen" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Prüft Windows-Version, letzten Neustart, ausstehenden und geplanten Neustart, WinGet-Modul, WinGet-Version und WAU und sucht Programm-Updates"/>
    <Button x:Name="BtnInstall" Content="App-Updates installieren" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Zeigt die Updates der markierten Geräte (laut letztem Status prüfen) zur Auswahl und installiert nur die angehakten still, es wird nie automatisch neu gestartet"/>
    <Button x:Name="BtnProgramm" Content="Programm installieren..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Installiert ein Programm aus WinGet (Id eingeben, zum Beispiel 7zip.7zip) auf den markierten Geräten"/>
    <Button x:Name="BtnProgListe" Content="Installierte Programme anzeigen..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Zeigt die installierten Programme (WinGet) der markierten Geräte in einer gemeinsamen Liste mit Suche, Filter und CSV-Export. Gespeicherte Listen erscheinen sofort mit Datum (gelesen am), nur Geräte ohne Liste werden gelesen; Neu auslesen in der Liste aktualisiert (nur Anzeige, es wird nichts verändert)"/>
    <Button x:Name="BtnDeinstall" Content="Programm deinstallieren..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Liest die installierten Programme (WinGet) eines markierten Geräts ein und deinstalliert das gewählte Programm still"/>
    <Button x:Name="BtnModul" Content="WinGet-Modul nachinstallieren" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Installiert bei Bedarf PowerShell 7 und das Modul Microsoft.WinGet.Client und führt Repair-WinGetPackageManager -AllUsers aus; danach läuft automatisch Status prüfen"/>
    <Button x:Name="BtnWauInstall" Content="WAU installieren..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Installiert Winget-AutoUpdate (monatlich und bei Anmeldung, Meldung nur bei Erfolg) mit einer Ausschlussliste auf den markierten Geräten. Geräte mit WAU, auch der Intune-Variante, werden übersprungen"/>
    <Button x:Name="BtnWauListe" Content="WAU-Ausschlüsse bearbeiten..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Liest die Ausschlussliste (excluded_apps.txt) der markierten Geräte mit normaler WAU, zeigt sie zum Bearbeiten und schreibt sie auf alle markierten Geräte. Die Intune-Variante wird nicht geändert"/>
    <Button x:Name="BtnDetails" Content="Details des markierten Geräts..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Verfügbare Updates, Cockpit-Verlauf, WAU-Verlauf und Log eines markierten Geräts"/>
    <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,5" Margin="0,8,0,0"/>
  </StackPanel>
</Window>
'@
    $f.Owner = $script:Fenster
    Connect-WolModulSpaltenHaken -Fenster $f -Key 'APP'
    $f.FindName('BtnStatus').Add_Click({ Start-WolAppStatus })
    $f.FindName('BtnInstall').Add_Click({ Start-WolAppInstallieren })
    $f.FindName('BtnProgramm').Add_Click({ Start-WolAppProgramm })
    $f.FindName('BtnProgListe').Add_Click({ Start-WolAppProgrammListe })
    $f.FindName('BtnDeinstall').Add_Click({ Start-WolAppDeinstallieren })
    $f.FindName('BtnModul').Add_Click({ Start-WolAppModul })
    $f.FindName('BtnWauInstall').Add_Click({ Start-WolAppWauInstallieren })
    $f.FindName('BtnWauListe').Add_Click({ Start-WolAppWauAusschluesse })
    $f.FindName('BtnDetails').Add_Click({ Start-WolAppDetails })
    $f.FindName('BtnSchliessen').Add_Click({ $script:AppFenster.Close() })
    $f.Add_Closed({ Set-WolModulOffen -Key 'APP' -Offen $false; $script:AppFenster = $null })
    $script:AppFenster = $f
    $f.Show()
    Set-WolModulOffen -Key 'APP' -Offen $true
}
