# NET-COCKPIT-Modul-OS.ps1
<#
.SYNOPSIS
    Modul OS-Updates für das NET-COCKPIT (Menü Module > OS)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und wirkt auf die markierten, grünen Geräte der Tabelle.
    - Status prüfen: Windows-Version, letzter Neustart, Neustart ausstehend, geplanter Neustart, Modul PSWindowsUpdate, verfügbare Windows-Updates, Update-Verlauf
    - Updates installieren (ohne Neustart) oder Updates installieren und bei Bedarf neu starten (nach 30 Sekunden)
    - Update-Modul (PSWindowsUpdate) nachinstallieren; danach läuft automatisch Status prüfen
    - Details je Gerät: verfügbare Updates, Update-Verlauf und Log
    Verbindung, Konten, Warteschlange, Neustart, Neustart planen, OU-Import und Liste kommen aus dem NET-COCKPIT.
    Log je Gerät: C:\Temp\NET-COCKPIT_data\Modul-OS\yyyyMMdd_Gerät_os-log.txt
#>

# Einstellungen
## Ordner und Zustand
$script:OsLogOrdner = Join-Path $script:DatenOrdner 'Modul-OS'
$script:OsSync = [System.Collections.Generic.Dictionary[object, object]]::new()
$script:OsFenster = $null

## Spalten (nur sichtbar, wenn im Modulfenster der Haken "Spalten des Moduls in der Tabelle anzeigen" gesetzt ist); Windows, Neustart ausstehend und Letzter Neustart teilen sich alle Update-Module
New-WolSpalte -Key 'Windows' -Titel 'Windows' -Eig '[Windows]' -Breite 270 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'NeustartAusstehend' -Titel 'Neustart ausstehend' -Eig '[NeustartAusstehend]' -Breite 125 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'LetzterNeustart' -Titel 'Letzter Neustart' -Eig '[LetzterNeustart]' -Breite 125 -Sichtbar $false -Modul 'Updates'
New-WolSpalte -Key 'OsModul' -Titel 'Update-Modul' -Eig '[OsModul]' -Breite 90 -Sichtbar $false -Modul 'OS'
New-WolSpalte -Key 'OsUpdates' -Titel 'OS-Updates' -Eig '[OsUpdates]' -Breite 90 -Sichtbar $false -Modul 'OS'
New-WolSpalte -Key 'OsLetzte' -Titel 'Letzte Updates' -Eig '[OsLetzte]' -Breite 105 -Sichtbar $false -Modul 'OS'

# Skripte, die auf dem Zielgerät als geplante Aufgabe laufen (Windows PowerShell 5.1, als SYSTEM)
## Installation ohne Neustart
$script:OsInstallSkript = @'
$log = 'C:\Windows\Temp\NetCockpitOsInstall.log'
try {
    Import-Module PSWindowsUpdate -ErrorAction Stop
    Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false -Verbose *>&1 | Out-File -FilePath $log -Encoding utf8 -Width 250
}
catch {
    ($_ | Out-String) | Add-Content -Path $log
    exit 1
}
'@

## Installation mit Neustart nach 30 Sekunden, nur wenn nötig
$script:OsInstallSkriptNeustart = $script:OsInstallSkript + "`r`n" + @'

$neustart = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($neustart) {
    Add-Content -Path $log -Value 'Neustart erforderlich, das Gerät startet in 30 Sekunden neu'
    shutdown.exe /r /t 30 /c "Der Rechner wird nach Windows-Updates in 30 Sekunden neu gestartet. Bitte Arbeit speichern. Abbruch durch einen Administrator mit: shutdown /a"
}
else {
    Add-Content -Path $log -Value 'Kein Neustart erforderlich'
}
'@

## Suche: verfügbare Updates und Update-Verlauf aus der Windows-Update-Historie
$script:OsSuchSkript = @'
$out = 'C:\Windows\Temp\NetCockpitOsSuche.json'
try {
    Import-Module PSWindowsUpdate -ErrorAction Stop

    ### Verfügbare Updates (Sammelobjekte werden in Einzelupdates aufgeteilt)
    $roh = @(Get-WindowsUpdate)
    $liste = New-Object System.Collections.Generic.List[object]
    foreach ($eintrag in $roh) {
        foreach ($x in $eintrag) {
            $titel   = @($x.Title)
            $kb      = @($x.KB)
            $groesse = @($x.Size)
            $kbPasst = ($kb.Count -eq $titel.Count)
            for ($i = 0; $i -lt $titel.Count; $i++) {
                $liste.Add([pscustomobject]@{
                    KB      = if ($kbPasst) { [string]$kb[$i] } else { '' }
                    Titel   = [string]$titel[$i]
                    Groesse = if ($i -lt $groesse.Count) { [string]$groesse[$i] } else { '' }
                })
            }
        }
    }

    ### Update-Verlauf aus der Windows-Update-Historie
    $verlauf       = New-Object System.Collections.Generic.List[object]
    $letzte        = ''
    $verlaufFehler = ''
    try {
        $suche  = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $gesamt = $suche.GetTotalHistoryCount()
        if ($gesamt -gt 0) {
            $eintraege = $suche.QueryHistory(0, [Math]::Min($gesamt, 200))
            foreach ($h in $eintraege) {
                $titel = [string]$h.Title
                $zeit  = ([datetime]$h.Date).ToLocalTime()
                $kb    = ''
                if ($titel -match 'KB\d+') { $kb = $Matches[0] }

                $aktion = switch ($h.Operation) { 1 { 'Installation' } 2 { 'Deinstallation' } default { 'Sonstiges' } }
                $ergebnis = switch ($h.ResultCode) { 1 { 'In Arbeit' } 2 { 'Erfolgreich' } 3 { 'Erfolgreich mit Fehlern' } 4 { 'Fehlgeschlagen' } 5 { 'Abgebrochen' } default { 'Unbekannt' } }

                if (-not $letzte -and ($h.Operation -eq 1) -and ($h.ResultCode -in 2, 3) -and ($titel -notmatch 'Security Intelligence|Definition|Defender')) {
                    $letzte = $zeit.ToString('dd.MM.yyyy', [cultureinfo]::InvariantCulture)
                }
                if ($verlauf.Count -lt 50) {
                    $verlauf.Add([pscustomobject]@{
                        Datum    = $zeit.ToString('dd.MM.yyyy HH:mm', [cultureinfo]::InvariantCulture)
                        KB       = $kb
                        Titel    = $titel
                        Ergebnis = "${aktion}: $ergebnis"
                    })
                }
            }
        }
    }
    catch { $verlaufFehler = ($_ | Out-String).Trim() }

    $erg = [pscustomobject]@{
        Fehler        = ''
        Updates       = @($liste.ToArray())
        Verlauf       = @($verlauf.ToArray())
        Letzte        = $letzte
        VerlaufFehler = $verlaufFehler
    }
}
catch {
    $erg = [pscustomobject]@{ Fehler = ($_ | Out-String).Trim(); Updates = @(); Verlauf = @(); Letzte = ''; VerlaufFehler = '' }
}
$erg | ConvertTo-Json -Depth 4 | Set-Content -Path $out -Encoding UTF8
'@

## Alle Skripte für den Job
$script:OsSkripte = @{
    Install         = $script:OsInstallSkript
    InstallNeustart = $script:OsInstallSkriptNeustart
    Suche           = $script:OsSuchSkript
}

# Job je Gerät
## Läuft als Thread-Job (Warteschlange des NET-COCKPIT); meldet Fortschritt und Ergebnis über das Sync-Objekt $S, die Oberfläche wird vom Timer des Moduls aktualisiert
$script:OsBlock = {
    param([string]$Ziel, [string]$Aktion, $Anmeldedaten, $S, [string]$LogDatei, [string]$TaskCode, $Skripte)

    . ([scriptblock]::Create($TaskCode))
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

    ### Modul PSWindowsUpdate auf dem Gerät prüfen
    function Test-Modul {
        $hat = Invoke-Command @ic -ScriptBlock { [bool](Get-Module -ListAvailable -Name PSWindowsUpdate) }
        $S.Modul = if ($hat) { 'Ja' } else { 'Nein' }
        return [bool]$hat
    }

    ### Letzten Neustart lesen, dazu die Dauer seitdem (nach der Uhr dieses Rechners)
    function Get-LetzterNeustartText {
        $text = Get-WolZielLetzterNeustart -Ic $ic
        $start = [datetime]::ParseExact($text, 'dd.MM.yyyy HH:mm', [cultureinfo]::InvariantCulture)
        $dauer = (Get-Date) - $start
        $seit = if ($dauer.TotalDays -ge 1) { "vor $([int][math]::Floor($dauer.TotalDays)) Tagen" } elseif ($dauer.TotalHours -ge 1) { "vor $([int][math]::Floor($dauer.TotalHours)) Std." } else { 'vor weniger als 1 Std.' }
        return "$text ($seit)"
    }

    ### Suche als Aufgabe auf dem Gerät ausführen und das JSON-Ergebnis lesen; liefert $null, wenn etwas schiefging (Status ist dann gesetzt)
    function Invoke-Abfrage {
        param([string]$Name, [string]$Skript, [string]$Wort)
        $aufraeumen = $true
        try {
            $S.Status = "$Wort läuft..."
            $null = Remove-WolZielTask -Ic $ic -Name $Name
            $null = Start-WolZielTask -Ic $ic -Name $Name -Skript $Skript
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
                $S.Status = "$Wort fehlgeschlagen"
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

        switch ($Aktion) {

            ## Status prüfen: Windows-Version, Neustart, Modul, Updates suchen, Verlauf
            'Status' {
                $S.Status = 'Lese Windows-Version...'
                try {
                    $S.Windows = Get-WolZielWindows -Ic $ic
                    Write-Log "Windows: $($S.Windows)"
                }
                catch { Write-Log "Windows-Version nicht lesbar: $($_.Exception.Message)" }

                try {
                    $S.LetzterNeustart = Get-LetzterNeustartText
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

                if (-not (Test-Modul)) {
                    $S.Status = "Modul fehlt, Suche nicht möglich$zusatz"
                    Write-Log 'PSWindowsUpdate fehlt, Updates können nicht gesucht werden'
                    return
                }
                Write-Log 'PSWindowsUpdate ist vorhanden'

                $fremd = @(Get-WolZielAnderesTool -Ic $ic -Eigene 'NetCockpitOs*')
                if ($fremd.Count -gt 0) {
                    $S.Status = "Anderes NET-COCKPIT-Tool läuft auf dem Gerät$zusatz"
                    Write-Log "Anderes NET-COCKPIT-Tool läuft auf dem Gerät: $($fremd -join ', ')"
                    return
                }

                $inst = Get-WolZielTaskStatus -Ic $ic -Name 'NetCockpitOsInstall'
                if ($inst.Vorhanden -and $inst.State -in 'Running', 'Queued') {
                    $S.Status = "Installation läuft bereits auf dem Gerät$zusatz"
                    Write-Log 'Installation läuft bereits auf dem Gerät'
                    return
                }

                $res = Invoke-Abfrage -Name 'NetCockpitOsSuche' -Skript $Skripte.Suche -Wort 'Suche'
                if (-not $res) { return }

                ### Verfügbare Updates
                $liste = @($res.Updates | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ KB = [string]$_.KB; Titel = [string]$_.Titel; Groesse = [string]$_.Groesse } })
                $S.Details = $liste
                $S.Updates = [string]$liste.Count
                foreach ($u in $liste) { Write-Log ("{0} | {1} | {2}" -f $u.KB, $u.Titel, $u.Groesse) }

                ### Update-Verlauf
                $S.Verlauf = @(@($res.Verlauf) | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ Datum = [string]$_.Datum; KB = [string]$_.KB; Titel = [string]$_.Titel; Ergebnis = [string]$_.Ergebnis } })
                if ($res.VerlaufFehler) {
                    $S.Letzte = '-'
                    Write-Log "Update-Verlauf nicht lesbar: $($res.VerlaufFehler)"
                }
                else {
                    $S.Letzte = if ($res.Letzte) { [string]$res.Letzte } else { 'keine' }
                    Write-Log "Update-Verlauf: $(@($S.Verlauf).Count) Einträge gelesen, letzte Installation: $($S.Letzte)"
                }

                if ($liste.Count -eq 1) { $S.Status = "1 Update verfügbar$zusatz" }
                elseif ($liste.Count -gt 1) { $S.Status = "$($liste.Count) Updates verfügbar$zusatz" }
                else { $S.Status = "Keine Updates verfügbar$zusatz" }
                Write-Log $S.Status
            }

            ## Modul nachinstallieren
            'Modul' {
                $S.Status = 'Installiere PSWindowsUpdate...'
                Write-Log 'Installiere Modul PSWindowsUpdate aus der PSGallery'
                Invoke-Command @ic -ScriptBlock {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                    $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                    Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force -Confirm:$false
                }
                if (Test-Modul) { $S.Status = 'Modul installiert' } else { $S.Status = 'Modul-Installation fehlgeschlagen' }
                Write-Log $S.Status
            }

            ## Updates installieren (lokale Aufgabe auf dem Gerät), optional mit Neustart
            { $_ -in 'Installieren', 'InstallierenNeustart' } {
                if (-not (Test-Modul)) { $S.Status = 'Modul fehlt'; Write-Log 'PSWindowsUpdate fehlt'; return }

                $mitNeustart = ($Aktion -eq 'InstallierenNeustart')
                $skript = if ($mitNeustart) { $Skripte.InstallNeustart } else { $Skripte.Install }
                $fremd = @(Get-WolZielAnderesTool -Ic $ic -Eigene 'NetCockpitOs*')
                if ($fremd.Count -gt 0) {
                    $S.Status = 'Anderes NET-COCKPIT-Tool läuft auf dem Gerät'
                    Write-Log "Anderes NET-COCKPIT-Tool läuft auf dem Gerät: $($fremd -join ', ')"
                    return
                }

                $name = 'NetCockpitOsInstall'
                $aufraeumen = $true
                $zeile = { param($t) if ($t.Trim()) { Write-Log $t.TrimEnd() } }
                try {
                    ### Läuft schon eine Installation? Dann anhängen, sonst neu starten
                    $vorhanden = Get-WolZielTaskStatus -Ic $ic -Name $name
                    if ($vorhanden.Vorhanden -and $vorhanden.State -in 'Running', 'Queued') {
                        Write-Log 'Installation läuft bereits auf dem Gerät, hänge mich an die laufende Installation an'
                    }
                    else {
                        $S.Status = 'Bereite Installation vor...'
                        $null = Remove-WolZielTask -Ic $ic -Name $name
                        $null = Start-WolZielTask -Ic $ic -Name $name -Skript $skript
                        if ($mitNeustart) { Write-Log 'Installation gestartet (-AcceptAll -IgnoreReboot), danach Neustart nach 30 Sekunden, falls nötig' }
                        else { Write-Log 'Installation gestartet (-AcceptAll -IgnoreReboot)' }
                        Start-Sleep -Seconds 5
                    }
                    $S.Status = 'Installation läuft...'

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

                    $S.Updates = '-'
                    $S.Details = @()

                    if ($null -eq $ergebnis) { $S.Status = 'Installation beendet, Ergebnis unbekannt' }
                    elseif ($ergebnis -ne 0) { $S.Status = "Installation beendet, Aufgaben-Code $ergebnis" }
                    elseif ($mitNeustart -and ($nz -or $null -eq $nz)) { $S.Status = 'Installation abgeschlossen, Neustart wird ausgeführt' }
                    elseif ($nz) { $S.Status = 'Installation abgeschlossen, Neustart nötig (Aktionen > Neustart planen)' }
                    else { $S.Status = 'Installation abgeschlossen' }
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
function script:Get-WolOsSync {
    param($Zeile)
    if (-not $script:OsSync.ContainsKey($Zeile)) {
        $script:OsSync[$Zeile] = [hashtable]::Synchronized(@{
            Status = ''; Fehlertext = ''; Verbunden = $false
            Windows = ''; Modul = ''; Updates = ''; Letzte = ''; Neustart = ''; LetzterNeustart = ''
            GeplantBis = ''; GeplantBisGelesen = $false
            Details = @(); Verlauf = @()
            Log = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        })
    }
    return $script:OsSync[$Zeile]
}

## Werte aus dem Sync-Objekt in die Zeile übernehmen (nur Werte, die das Modul gelesen hat)
function script:Update-WolOsZeile {
    param($Zeile, $S)
    $werte = [ordered]@{
        Windows = $S.Windows; NeustartAusstehend = $S.Neustart; LetzterNeustart = $S.LetzterNeustart
        OsModul = $S.Modul; OsUpdates = $S.Updates; OsLetzte = $S.Letzte
    }
    foreach ($schluessel in $werte.Keys) {
        $wert = [string]$werte[$schluessel]
        if ($wert -and $Zeile[$schluessel] -ne $wert) { $Zeile[$schluessel] = $wert }
    }
    if ($S.GeplantBisGelesen -and $Zeile['GeplantBis'] -ne [string]$S.GeplantBis) { $Zeile['GeplantBis'] = [string]$S.GeplantBis }
}

## Timer des Moduls: zeigt den Fortschritt laufender Aufträge, solange welche laufen
$script:OsTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:OsTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:OsTimer.Add_Tick({
    try {
        foreach ($eintrag in @($script:OsSync.GetEnumerator())) {
            $z = $eintrag.Key
            $S = $eintrag.Value
            if ((Get-WolGruppeOffen -Gruppe 'OS' -Zeile $z) -eq 0) { continue }
            Update-WolOsZeile -Zeile $z -S $S
            if ($S.Status) { $z.Status = [string]$S.Status }
        }
        if ((Get-WolGruppeOffen -Gruppe 'OS') -eq 0) { $script:OsTimer.Stop() }
    }
    catch { Write-WolLog "Fehler im Timer des Moduls OS: $($_.Exception.Message)" }
})

# Aufträge
## Auswertung eines Auftrags (läuft im Poll-Takt des NET-COCKPIT)
$script:OsFertig = {
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
    Update-WolOsZeile -Zeile $z -S $S
    Save-WolWerteZeile -Zeile $z -Neu:($a.Daten.Aktion -eq 'Status' -and -not $S.Fehlertext)
    $z.Status = [string]$S.Status
    Write-WolLog ("OS {0}: {1}" -f $a.Daten.Name, $S.Status)

    ### Nach erfolgreicher Modul-Installation gleich den Status prüfen
    if ($a.Daten.Aktion -eq 'Modul' -and $S.Status -eq 'Modul installiert') {
        Start-WolOsAktion -Aktion 'Status' -Ziele @($z)
    }
}

## Aktion für Geräte in die Warteschlange des NET-COCKPIT legen (nur grüne Geräte)
function script:Start-WolOsAktion {
    param([string]$Aktion, $Ziele)
    $Ziele = @($Ziele)
    $gruen = @($Ziele | Where-Object { $_.Ampel -eq 'Gruen' })
    foreach ($z in @($Ziele | Where-Object { $_.Ampel -ne 'Gruen' })) { $z.Status = 'WinRM nicht erreichbar - übersprungen' }
    if ($gruen.Count -eq 0) { Show-WolMeldung 'Keines der Geräte ist grün (WinRM erreichbar).'; return }
    if (-not (Resolve-WolKonten -Zeilen $gruen)) { return }
    if (-not (Test-Path -LiteralPath $script:OsLogOrdner)) { New-Item -Path $script:OsLogOrdner -ItemType Directory -Force | Out-Null }

    $gestartet = 0
    foreach ($z in $gruen) {
        if ((Get-WolGruppeOffen -Gruppe 'OS' -Zeile $z) -gt 0) { continue }
        try { $konto = Get-WolAnmeldung -Zeile $z }
        catch { $z.Status = $_.Exception.Message; continue }

        $S = Get-WolOsSync -Zeile $z
        $S.Status = ''
        $S.Fehlertext = ''
        $S.Verbunden = $false
        $S.GeplantBisGelesen = $false

        $name = $(if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { [string]$z.IP })
        $logDatei = Join-Path $script:OsLogOrdner ('{0:yyyyMMdd}_{1}_os-log.txt' -f (Get-Date), ($name -replace '[^\w\.\-]', '_'))
        Add-WolAuftrag -Zeile $z -Block $script:OsBlock -Argumente @((Get-WolZielName -Zeile $z), $Aktion, $konto, $S, $logDatei, $script:ZielTaskCode, $script:OsSkripte) -Fertig $script:OsFertig -Gruppe 'OS' -Daten @{ Aktion = $Aktion; S = $S; Name = $name } -Starttext 'OS: Verbinde...'
        $gestartet++
    }
    if ($gestartet -eq 0) { Write-WolLog 'OS: Auf den Geräten läuft schon eine Aktion des Moduls'; return }
    Write-WolLog "OS $Aktion : $gestartet Gerät(e)"
    if (-not $script:OsTimer.IsEnabled) { $script:OsTimer.Start() }
}

# Dialoge
## Markierte Geräte holen (mit Hinweis, wenn keins markiert ist); -Genau 1 verlangt genau ein Gerät
function script:Get-WolOsZiele {
    param([int]$Genau = 0)
    $ziele = @(Get-WolMarkierte)
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return $null }
    if ($Genau -gt 0 -and $ziele.Count -ne $Genau) { Show-WolMeldung 'Bitte genau ein Gerät markieren.'; return $null }
    return , $ziele
}

## Namen der Geräte für Texte (Hostname, sonst IP)
function script:Get-WolOsNamen {
    param($Zeilen)
    return (@($Zeilen | ForEach-Object { if ($_.Hostname) { ([string]$_.Hostname).Split('.')[0] } else { [string]$_.IP } }) -join ', ')
}

## Details eines Geräts: verfügbare Updates, Update-Verlauf und Log
function script:Show-WolOsDetails {
    param($Zeile)
    $S = Get-WolOsSync -Zeile $Zeile
    $name = Get-WolOsNamen -Zeilen @($Zeile)
    $verfuegbar = @(@($S.Details) | Where-Object { $_ })
    $verlauf = @(@($S.Verlauf) | Where-Object { $_ })
    $log = @($S.Log.ToArray())
    if ($verfuegbar.Count -eq 0 -and $verlauf.Count -eq 0 -and $log.Count -eq 0) {
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
            <DataGridTextColumn Header="KB"    Binding="{Binding KB, Mode=OneWay}"      Width="110"/>
            <DataGridTextColumn Header="Titel" Binding="{Binding Titel, Mode=OneWay}"   Width="*"/>
            <DataGridTextColumn Header="Größe" Binding="{Binding Groesse, Mode=OneWay}" Width="90"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
      <TabItem x:Name="TabVerlauf">
        <DataGrid x:Name="TabelleVerlauf" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Datum"    Binding="{Binding Datum, Mode=OneWay}"    Width="130"/>
            <DataGridTextColumn Header="KB"       Binding="{Binding KB, Mode=OneWay}"       Width="100"/>
            <DataGridTextColumn Header="Ergebnis" Binding="{Binding Ergebnis, Mode=OneWay}" Width="230"/>
            <DataGridTextColumn Header="Titel"    Binding="{Binding Titel, Mode=OneWay}"    Width="*"/>
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
    $f.Title = "Updates auf $name"
    $f.Owner = $script:Fenster
    $f.FindName('TabelleVerfuegbar').ItemsSource = $verfuegbar
    $f.FindName('TabelleVerlauf').ItemsSource = $verlauf
    $f.FindName('TabVerfuegbar').Header = "Verfügbare Updates ($($verfuegbar.Count))"
    $f.FindName('TabVerlauf').Header = "Verlauf ($($verlauf.Count))"
    $f.FindName('TabLog').Header = "Log ($($log.Count))"
    $f.FindName('TxtLog').Text = ($log -join "`r`n")
    if ($verfuegbar.Count -eq 0) {
        $f.FindName('Reiter').SelectedIndex = $(if ($verlauf.Count -gt 0) { 1 } else { 2 })
    }
    [void]$f.ShowDialog()
}

# Aktionen des Moduls
## Status prüfen
function script:Start-WolOsStatus {
    $ziele = Get-WolOsZiele
    if ($ziele) { Start-WolOsAktion -Aktion 'Status' -Ziele $ziele }
}

## Updates installieren (ohne Neustart)
function script:Start-WolOsInstallieren {
    $ziele = Get-WolOsZiele
    if ($ziele) { Start-WolOsAktion -Aktion 'Installieren' -Ziele $ziele }
}

## Updates installieren und bei Bedarf neu starten (Rückfrage)
function script:Start-WolOsInstallierenNeustart {
    $ziele = Get-WolOsZiele
    if (-not $ziele) { return }
    $frage = "Updates installieren und danach neu starten (nach 30 Sekunden, nur wenn ein Neustart nötig ist) auf:`r`n`r`n$((Get-WolOsNamen -Zeilen $ziele) -replace ', ', "`r`n")"
    if ([System.Windows.MessageBox]::Show($frage, 'Installieren und neu starten', 'YesNo', 'Warning') -eq 'Yes') {
        Start-WolOsAktion -Aktion 'InstallierenNeustart' -Ziele $ziele
    }
}

## Update-Modul nachinstallieren (Geräte, bei denen es schon da ist, werden übersprungen)
function script:Start-WolOsModul {
    $ziele = Get-WolOsZiele
    if (-not $ziele) { return }
    $schon = @($ziele | Where-Object { $_['OsModul'] -eq 'Ja' })
    $offen = @($ziele | Where-Object { $_['OsModul'] -ne 'Ja' })
    if ($schon.Count -gt 0) {
        Show-WolMeldung ("PSWindowsUpdate ist auf diesen Geräten bereits vorhanden:`r`n`r`n" + ((Get-WolOsNamen -Zeilen $schon) -replace ', ', "`r`n"))
    }
    if ($offen.Count -eq 0) { return }
    $frage = "Das Modul PSWindowsUpdate auf diesen Geräten installieren?`r`n`r`n$((Get-WolOsNamen -Zeilen $offen) -replace ', ', "`r`n")`r`n`r`nDie Geräte brauchen dafür Internetzugang zur PSGallery."
    if ([System.Windows.MessageBox]::Show($frage, 'Update-Modul nachinstallieren', 'YesNo', 'Question') -eq 'Yes') {
        Start-WolOsAktion -Aktion 'Modul' -Ziele $offen
    }
}

## Details des markierten Geräts
function script:Start-WolOsDetails {
    $ziele = Get-WolOsZiele -Genau 1
    if ($ziele) { Show-WolOsDetails -Zeile $ziele[0] }
}

# Fenster des Moduls
## Wird vom Menü Module > OS aufgerufen: kleines Fenster neben der Tabelle (bleibt offen, die Tabelle bleibt bedienbar)
function script:Show-WolModulOS {
    if ($script:OsFenster) {
        $script:OsFenster.Activate()
        Set-WolModulOffen -Key 'OS' -Offen $true
        return
    }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OS-Updates" Width="400" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Wirkt auf die markierten Geräte der Tabelle (nur grüne, WinRM erreichbar). Aufträge laufen über die Warteschlange des NET-COCKPIT." TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,12"/>
    <CheckBox x:Name="ChkSpalten" Content="Spalten des Moduls in der Tabelle anzeigen" Margin="0,0,0,10"
              ToolTip="Blendet die Spalten dieses Moduls in der Tabelle ein (Standard: aus). Beim Schließen des Fensters werden sie wieder ausgeblendet"/>
    <Button x:Name="BtnStatus" Content="Status prüfen" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Prüft Windows-Version, letzten Neustart, ausstehenden und geplanten Neustart und das Modul PSWindowsUpdate, sucht Updates und liest den Update-Verlauf"/>
    <Button x:Name="BtnInstall" Content="Updates installieren" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Installiert alle gefundenen Updates mit -AcceptAll -IgnoreReboot (kein automatischer Neustart)"/>
    <Button x:Name="BtnInstallNeu" Content="Updates installieren und bei Bedarf neu starten" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Wie Updates installieren, danach Neustart nach 30 Sekunden, aber nur wenn ein Neustart nötig ist"/>
    <Button x:Name="BtnModul" Content="Update-Modul nachinstallieren" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Installiert das PowerShell-Modul PSWindowsUpdate auf markierten Geräten, auf denen es fehlt"/>
    <Button x:Name="BtnDetails" Content="Details des markierten Geräts..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Verfügbare Updates, Update-Verlauf und Log eines markierten Geräts"/>
    <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,5" Margin="0,8,0,0"/>
  </StackPanel>
</Window>
'@
    $f.Owner = $script:Fenster
    Connect-WolModulSpaltenHaken -Fenster $f -Key 'OS'
    $f.FindName('BtnStatus').Add_Click({ Start-WolOsStatus })
    $f.FindName('BtnInstall').Add_Click({ Start-WolOsInstallieren })
    $f.FindName('BtnInstallNeu').Add_Click({ Start-WolOsInstallierenNeustart })
    $f.FindName('BtnModul').Add_Click({ Start-WolOsModul })
    $f.FindName('BtnDetails').Add_Click({ Start-WolOsDetails })
    $f.FindName('BtnSchliessen').Add_Click({ $script:OsFenster.Close() })
    $f.Add_Closed({ Set-WolModulOffen -Key 'OS' -Offen $false; $script:OsFenster = $null })
    $script:OsFenster = $f
    $f.Show()
    Set-WolModulOffen -Key 'OS' -Offen $true
}
