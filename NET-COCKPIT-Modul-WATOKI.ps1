# NET-COCKPIT-Modul-WATOKI.ps1
<#
.SYNOPSIS
    Modul WaToKi für das NET-COCKPIT (Menü Module > WaToKi)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und startet die Wartungsskripte aus dem Unterordner WaToKi neben dem Modul.
    - Skriptliste: alle .ps1-Dateien im Unterordner WaToKi (die .sig-Dateien sind ausgeblendet), rechts die Beschreibung aus dem Skriptkopf
    - Das gewählte Skript läuft in einem eigenen PowerShell-7-Fenster; es läuft immer nur ein Skript gleichzeitig
    - Parameter werden nur übergeben, wenn das Skript sie im param-Block kennt: -Ziel (die markierten Geräte der Tabelle), -Ausgabeordner (Unterordner Modul-WaToKi im Datenordner), -Anmeldedaten (ein Konto aus der Spalte "Konto") und -AnmeldedatenJeZiel (Zuordnung Ziel > Konto, wenn die markierten Geräte unterschiedliche Konten haben)
    - Die Anmeldedaten gehen über eine verschlüsselte Temp-Datei (nur für das angemeldete Windows-Konto lesbar), die der Startbefehl sofort nach dem Einlesen löscht
    - Das Modul fragt keine Kennwörter ab: fehlt bei einem markierten Gerät mit Konto das Kennwort der Sitzung, startet nichts und die Geräte werden genannt (Konto im Cockpit pro Gerät setzen)
    - Skripte ohne diese Parameter starten unverändert und fragen wie bisher selbst nach
    - Spalte "Wartungsreihenfolge": bearbeitbar, sichtbar nur, wenn im Fenster der Haken "Spalte Wartungsreihenfolge in der Tabelle anzeigen" gesetzt ist; der Wert wird mit der Geräteliste gespeichert
    Beim Start über start.ps1 fehlt der Unterordner anfangs; das Modul holt die Skripte dann beim ersten Öffnen mit Ladefenster vom Server (Signaturprüfung) in den Ordner neben dem Modul.
    Automatik (Knopf "Automatik starten"): arbeitet alle Geräte ab, die in der Spalte "Wartungsreihenfolge" Skriptnamen haben (Name ohne "Wartung-" und ohne .ps1, mehrere durch Komma, Semikolon oder Zeilenumbruch getrennt)
    - Je Skript ein Lauf mit allen zugehörigen Geräten (Skripte, die nur ein Gerät nehmen, laufen je Gerät), die Skripte laufen nacheinander nach Skriptname sortiert, jedes in einem eigenen unsichtbaren PowerShell-7-Prozess mit -Automatik
    - Voraussetzungen: Skript kennt -Automatik, keine Syntaxfehler, Kennwörter der Konten sind in der Sitzung vorhanden; sonst Status "übersprungen" mit Grund
    - Vor dem Start fragt das Cockpit fehlende Kennwörter der Konten ab (einmal pro Benutzername)
    - Knopf "Automatik stoppen": beendet das laufende Skript, startet die übrigen nicht mehr (Status abgebrochen) und speichert die bisherigen Ergebnisse
    - Status je Lauf: OK, übersprungen, abgebrochen oder Fehler (auch bei Zeitlimit von 10 Minuten oder Exitcode ungleich 0; bei Fehler steht die Notiz aus der Ergebnisdatei in der Meldung, sonst die letzte Konsolenzeile)
    - Ergebnis im Ordner Autowartung_<yyyyMMdd_HHmmss> im Ausgabeordner: Autowartung-Gesamtdatei.json (maschinenlesbar für den Wartinator) und Detail.txt (gegliedert für den Techniker, enthält die Konsolenausgabe jedes Skripts) und Techniker-Uebersicht.html (wie die Wartungscheckliste gegliedert, Fehler und Auffälligkeiten oben, als PDF druckbar) und Lieferschein.txt (knapper Entwurf nach Themen der Wartungscheckliste: nur Auffälligkeiten aus den Skripten, ohne Bewertung)
    - Knopf Automatik prüfen: testet vorab je Gerät Name, Ping, WinRM-/SSH-Anmeldung und nötige Module (nur lesend) und zeigt einen Bericht (wird auch als Automatik-Pruefung_<Datum>.txt gespeichert)
    - Vertrag für die Skripte: ein Skript mit -Automatik fragt nichts ab, öffnet nichts und schreibt seine Werte für die Checkliste als Ergebnis_<Skriptname ohne Wartung- und .ps1>.json in -Ausgabeordner (wird unverändert in die Gesamtdatei übernommen); alles Ausführliche gibt es auf der Konsole aus (landet in Detail.txt)
    Sonst speichert das Modul nichts.
#>

# Einstellungen
## Namen und Muster des Moduls
$script:WtUnterordner = 'WaToKi'
$script:WtDateiMuster = '*.ps1'
$script:WtAusgabeName = 'Modul-WaToKi'
$script:WtParamZiel = 'Ziel'
$script:WtParamAusgabe = 'Ausgabeordner'
$script:WtParamAnmeldung = 'Anmeldedaten'
$script:WtParamAnmeldungJeZiel = 'AnmeldedatenJeZiel'
$script:WtParamAutomatik = 'Automatik'
$script:WtLimitMinuten = 10

## Zustand: Fenster, Steuerelemente und das laufende Skript (bleibt auch bei geschlossenem Fenster erhalten)
$script:WtFenster = $null
$script:WtC = @{}
$script:WtProzess = $null
$script:WtProzessName = ''
$script:WtStart = $null
$script:WtTimer = $null
$script:WtAnmeldeDatei = ''
$script:WtLauf = $null
$script:WtAutoTimer = $null
$script:WtPruefJob = $null
$script:WtPruefTimer = $null

## Spalte in der Tabelle (bearbeitbar; der Kern speichert den Wert mit der Geräteliste)
New-WolSpalte -Key 'Wartungsreihenfolge' -Titel 'Wartungsreihenfolge' -Eig '[Wartungsreihenfolge]' -Breite 120 -NurLesen $false -Sichtbar $false -Modul 'WATOKI'

# Hilfsfunktionen
## Ordner der Skripte (Unterordner neben dem Modul)
function script:Get-WolWtSkriptOrdner {
    return (Join-Path $script:ModulOrdner $script:WtUnterordner)
}

## Ausgabeordner im Datenordner (wird bei Bedarf angelegt)
function script:Get-WolWtAusgabeOrdner {
    $ordner = Join-Path $script:DatenOrdner $script:WtAusgabeName
    if (-not (Test-Path -LiteralPath $ordner)) { [void](New-Item -Path $ordner -ItemType Directory -Force) }
    return $ordner
}

## Text für die Einbettung in einfache Anführungszeichen
function script:ConvertTo-WolWtText {
    param([string]$Text)
    return $Text.Replace("'", "''")
}

## Temp-Datei mit den Anmeldedaten löschen (der Startbefehl löscht sie selbst; das ist die Absicherung nach Skriptende oder bei einem Startfehler)
function script:Remove-WolWtAnmeldeDatei {
    if ($script:WtAnmeldeDatei -and (Test-Path -LiteralPath $script:WtAnmeldeDatei)) {
        try { Remove-Item -LiteralPath $script:WtAnmeldeDatei -Force -ErrorAction Stop } catch { }
    }
    $script:WtAnmeldeDatei = ''
}

## Läuft gerade ein Skript?
function script:Test-WolWtLaeuft {
    if (-not $script:WtProzess) { return $false }
    try { if ($script:WtProzess.HasExited) { return $false } } catch { return $false }
    return $true
}

## Skript lesen, ohne es auszuführen (Parser): Beschreibung aus dem Skriptkopf und die Parameter aus dem param-Block
function script:Get-WolWtSkriptInfo {
    param([string]$Pfad)
    $info = [pscustomobject]@{ Beschreibung = ''; HatZiel = $false; ZielMehrere = $false; HatAusgabe = $false; HatAnmeldung = $false; HatAnmeldungJeZiel = $false; HatAutomatik = $false; Fehler = '' }
    try {
        $tokens = $null
        $fehler = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Pfad, [ref]$tokens, [ref]$fehler)
        if ($fehler -and $fehler.Count -gt 0) { $info.Fehler = 'Syntaxfehler im Skript: ' + $fehler[0].Message }
        if ($ast.ParamBlock) {
            foreach ($p in $ast.ParamBlock.Parameters) {
                $name = [string]$p.Name.VariablePath.UserPath
                if ($name -eq $script:WtParamZiel) {
                    $info.HatZiel = $true
                    $typ = $p.StaticType
                    $info.ZielMehrere = ($typ.IsArray -or $typ -eq [object])
                }
                elseif ($name -eq $script:WtParamAusgabe) { $info.HatAusgabe = $true }
                elseif ($name -eq $script:WtParamAnmeldung) { $info.HatAnmeldung = $true }
                elseif ($name -eq $script:WtParamAnmeldungJeZiel) { $info.HatAnmeldungJeZiel = $true }
                elseif ($name -eq $script:WtParamAutomatik) { $info.HatAutomatik = $true }
            }
        }
        $text = Get-Content -LiteralPath $Pfad -Raw -Encoding utf8
        $treffer = [regex]::Match($text, '(?s)BESCHREIBUNG[ \t]*\r?\n(.+?)\r?\n[ \t]*\r?\n')
        if ($treffer.Success) { $info.Beschreibung = $treffer.Groups[1].Value.Trim() }
    }
    catch { $info.Fehler = 'Das Skript konnte nicht gelesen werden: ' + $_.Exception.Message }
    return $info
}

## Alle Skripte des Unterordners mit ihren Angaben
function script:Get-WolWtSkripte {
    $ordner = Get-WolWtSkriptOrdner
    if (-not (Test-Path -LiteralPath $ordner)) { return @() }
    $liste = foreach ($datei in @(Get-ChildItem -LiteralPath $ordner -File -Filter $script:WtDateiMuster | Where-Object { $_.Extension -eq '.ps1' } | Sort-Object Name)) {
        $info = Get-WolWtSkriptInfo -Pfad $datei.FullName
        [pscustomobject]@{
            Name         = $datei.Name
            Pfad         = $datei.FullName
            Beschreibung = $info.Beschreibung
            HatZiel      = $info.HatZiel
            ZielMehrere  = $info.ZielMehrere
            HatAusgabe   = $info.HatAusgabe
            HatAnmeldung = $info.HatAnmeldung
            HatAnmeldungJeZiel = $info.HatAnmeldungJeZiel
            HatAutomatik = $info.HatAutomatik
            Fehler       = $info.Fehler
        }
    }
    return @($liste)
}

# Anzeige
## Skriptliste im Fenster neu aufbauen
function script:Update-WolWtListe {
    $c = $script:WtC
    $auswahl = $null
    if ($c.Liste.SelectedItem) { $auswahl = [string]$c.Liste.SelectedItem.Tag.Name }
    $c.Liste.Items.Clear()
    $skripte = @(Get-WolWtSkripte)
    foreach ($s in $skripte) {
        $eintrag = [System.Windows.Controls.ListBoxItem]::new()
        $eintrag.Content = [System.IO.Path]::GetFileNameWithoutExtension($s.Name)
        $eintrag.Tag = $s
        [void]$c.Liste.Items.Add($eintrag)
        if ($s.Name -eq $auswahl) { $eintrag.IsSelected = $true }
    }
    if ($skripte.Count -eq 0) {
        $c.TxtInfo.Text = "Im Ordner $(Get-WolWtSkriptOrdner) wurden keine Skripte gefunden."
    }
    elseif (-not $c.Liste.SelectedItem) {
        $c.Liste.SelectedIndex = 0
    }
    Update-WolWtStatus
}

## Beschreibung und Parameter des gewählten Skripts anzeigen
function script:Show-WolWtBeschreibung {
    $c = $script:WtC
    if (-not $c.Liste.SelectedItem) { return }
    $s = $c.Liste.SelectedItem.Tag
    $zeilen = [System.Collections.Generic.List[string]]::new()
    $zeilen.Add($s.Name)
    $zeilen.Add('')
    if ($s.Beschreibung) { $zeilen.Add($s.Beschreibung); $zeilen.Add('') }
    if ($s.HatZiel) {
        $zeilen.Add($(if ($s.ZielMehrere) { "Gerät: nimmt die markierten Geräte der Tabelle über -$($script:WtParamZiel)." } else { "Gerät: nimmt genau ein markiertes Gerät der Tabelle über -$($script:WtParamZiel)." }))
    }
    else { $zeilen.Add("Gerät: das Skript fragt selbst danach (kein Parameter -$($script:WtParamZiel))." ) }
    $zeilen.Add($(if ($s.HatAnmeldungJeZiel) { "Konto: das Konto jedes markierten Geräts aus der Spalte 'Konto' über -$($script:WtParamAnmeldungJeZiel) (ohne Eintrag fragt das Skript selbst oder nimmt das Windows-Konto)." } elseif ($s.HatAnmeldung) { "Konto: das Konto aus der Spalte 'Konto' über -$($script:WtParamAnmeldung) (ohne Eintrag das angemeldete Windows-Konto)." } else { "Konto: das Skript nutzt das angemeldete Windows-Konto (kein Parameter -$($script:WtParamAnmeldung))." }))
    $zeilen.Add($(if ($s.HatAusgabe) { "Ausgabe: -$($script:WtParamAusgabe) = $(Join-Path $script:DatenOrdner $script:WtAusgabeName)" } else { "Ausgabe: das Skript bestimmt den Ordner selbst (kein Parameter -$($script:WtParamAusgabe))." }))
    $zeilen.Add($(if ($s.HatAutomatik) { "Automatik: kennt -$($script:WtParamAutomatik), läuft im Automatiklauf." } else { "Automatik: kennt -$($script:WtParamAutomatik) noch nicht, wird im Automatiklauf übersprungen." }))
    if ($s.Fehler) { $zeilen.Add(''); $zeilen.Add($s.Fehler) }
    $c.TxtInfo.Text = ($zeilen -join "`r`n")
}

## Statuszeile und Starten-Knopf (zeigt auch, wenn ein Skript noch läuft)
function script:Update-WolWtStatus {
    $c = $script:WtC
    if (-not $c.TxtStatus) { return }
    if ($c.BtnStop) { $c.BtnStop.IsEnabled = [bool]$script:WtLauf }
    if ($c.BtnPruef) { $c.BtnPruef.IsEnabled = -not ($script:WtLauf -or $script:WtPruefJob -or (Test-WolWtLaeuft)) }
    if ($script:WtPruefJob) {
        $c.BtnStart.IsEnabled = $false
        if ($c.BtnAuto) { $c.BtnAuto.IsEnabled = $false }
        return
    }
    if ($script:WtLauf) {
        $c.BtnStart.IsEnabled = $false
        if ($c.BtnAuto) { $c.BtnAuto.IsEnabled = $false }
        $l = $script:WtLauf
        $c.TxtStatus.Text = 'Automatik: Skript {0} von {1}: {2} (seit {3:HH:mm:ss}, Zeitlimit {4} Minuten).' -f ([math]::Min($l.Index + 1, $l.Plan.Count)), $l.Plan.Count, $script:WtProzessName, $script:WtStart, $script:WtLimitMinuten
    }
    elseif (Test-WolWtLaeuft) {
        $c.BtnStart.IsEnabled = $false
        if ($c.BtnAuto) { $c.BtnAuto.IsEnabled = $false }
        $c.TxtStatus.Text = 'Läuft: {0} (seit {1:HH:mm:ss}). Es läuft immer nur ein Skript gleichzeitig.' -f $script:WtProzessName, $script:WtStart
    }
    else {
        $c.BtnStart.IsEnabled = $true
        if ($c.BtnAuto) { $c.BtnAuto.IsEnabled = $true }
        if (-not $c.TxtStatus.Text -or $c.TxtStatus.Text.StartsWith('Läuft:')) { $c.TxtStatus.Text = 'Bereit.' }
    }
}

# Starten
## Prüfung des laufenden Skripts (Timer): beim Ende Sperre lösen und im Log vermerken
function script:Watch-WolWtProzess {
    if (Test-WolWtLaeuft) { Update-WolWtStatus; return }
    $script:WtTimer.Stop()
    $code = ''
    try { $code = [string]$script:WtProzess.ExitCode } catch { }
    $name = $script:WtProzessName
    $script:WtProzess = $null
    Remove-WolWtAnmeldeDatei
    Write-WolLog "WaToKi: $name beendet (Exitcode $code)"
    if ($script:WtC.TxtStatus) { $script:WtC.TxtStatus.Text = "Beendet: $name (Exitcode $code)" }
    Update-WolWtStatus
}

## Gewähltes Skript in einem eigenen PowerShell-7-Fenster starten
function script:Start-WolWtSkript {
    if ($script:WtLauf -or (Test-WolWtLaeuft)) { Update-WolWtStatus; return }
    $c = $script:WtC
    if (-not $c.Liste.SelectedItem) { $c.TxtStatus.Text = 'Bitte zuerst ein Skript wählen.'; return }
    $s = $c.Liste.SelectedItem.Tag

    ### Ziele: nur, wenn das Skript den Parameter kennt
    $ziele = @()
    if ($s.HatZiel) {
        $markiert = @(Get-WolMarkierte)
        if ($markiert.Count -eq 0) {
            Show-WolMeldung "Das Skript $($s.Name) arbeitet mit einem Gerät der Tabelle.`r`nBitte zuerst ein Gerät markieren." 'Information'
            return
        }
        if ($markiert.Count -gt 1 -and -not $s.ZielMehrere) {
            Show-WolMeldung "Das Skript $($s.Name) nimmt nur ein Gerät.`r`nBitte genau ein Gerät markieren." 'Information'
            return
        }
        $ziele = @($markiert | ForEach-Object { Get-WolZielName -Zeile $_ })
    }

    ### Konto: aus der Spalte "Konto" (nur, wenn das Skript -Anmeldedaten oder -AnmeldedatenJeZiel kennt); das Modul fragt nichts ab, fehlende Kennwörter werden gemeldet
    $anmeldeDatei = ''
    $anmeldeParam = ''
    if ($s.HatZiel -and ($s.HatAnmeldung -or $s.HatAnmeldungJeZiel)) {
        $veraltet = @($markiert | Where-Object { $_.Konto -and -not $_.Kennwort })
        if ($veraltet.Count -gt 0) {
            $namen = @($veraltet | ForEach-Object { if ($_.Hostname) { ([string]$_.Hostname).Split('.')[0] } else { [string]$_.IP } })
            Show-WolMeldung "Anmeldedaten für folgende Geräte sind nicht aktuell:`r`n`r`n$($namen -join "`r`n")`r`n`r`nBitte das Gerät markieren und über Optionen > Konto für markierte Geräte das Kennwort setzen (jedes Gerät einzeln), danach das Skript erneut starten." 'Information'
            return
        }
        $konto = $null
        try {
            if ($s.HatAnmeldungJeZiel) {
                $anmeldeParam = $script:WtParamAnmeldungJeZiel
                $konto = @{}
                foreach ($z in $markiert) {
                    $k = Get-WolAnmeldung -Zeile $z
                    if ($k) { $konto[(Get-WolZielName -Zeile $z)] = $k }
                }
                if ($konto.Count -eq 0) { $konto = $null }
            }
            else {
                $anmeldeParam = $script:WtParamAnmeldung
                $konten = @($markiert | ForEach-Object { ([string]$_.Konto).ToLower() } | Select-Object -Unique)
                if ($konten.Count -gt 1) {
                    Show-WolMeldung "Das Skript $($s.Name) nimmt nur ein Konto für alle Geräte.`r`nDie markierten Geräte haben unterschiedliche Konten (oder nur ein Teil hat eins).`r`nBitte nur Geräte mit demselben Konto markieren." 'Information'
                    return
                }
                $konto = Get-WolAnmeldung -Zeile $markiert[0]
            }
        }
        catch { $c.TxtStatus.Text = $_.Exception.Message; return }
        if ($konto) {
            $anmeldeDatei = Join-Path ([System.IO.Path]::GetTempPath()) ('BETA-NET-COCKPIT_Anmeldung_' + [guid]::NewGuid().ToString('N') + '.xml')
            try { $konto | Export-Clixml -LiteralPath $anmeldeDatei -ErrorAction Stop }
            catch { $c.TxtStatus.Text = "Die Anmeldedaten konnten nicht übergeben werden: $($_.Exception.Message)"; return }
            $script:WtAnmeldeDatei = $anmeldeDatei
        }
    }

    ### Befehl aufbauen: Fehler im Skript lassen das Fenster offen, wie im bisherigen Starter
    $befehl = "& '" + (ConvertTo-WolWtText $s.Pfad) + "'"
    if ($s.HatZiel) {
        $liste = ($ziele | ForEach-Object { "'" + (ConvertTo-WolWtText $_) + "'" }) -join ','
        $befehl += " -$($script:WtParamZiel) " + $(if ($s.ZielMehrere) { "@($liste)" } else { $liste })
    }
    if ($anmeldeDatei) { $befehl += " -$anmeldeParam `$wtKonto" }
    if ($s.HatAusgabe) {
        try { $ausgabe = Get-WolWtAusgabeOrdner }
        catch { Remove-WolWtAnmeldeDatei; $c.TxtStatus.Text = "Der Ausgabeordner konnte nicht angelegt werden: $($_.Exception.Message)"; return }
        $befehl += " -$($script:WtParamAusgabe) '" + (ConvertTo-WolWtText $ausgabe) + "'"
    }
    $kontoBefehl = $(if ($anmeldeDatei) { "`$wtKonto = Import-Clixml -LiteralPath '" + (ConvertTo-WolWtText $anmeldeDatei) + "'; Remove-Item -LiteralPath '" + (ConvertTo-WolWtText $anmeldeDatei) + "' -Force; " } else { '' })
    $gesamt = "try { $kontoBefehl$befehl; Write-Host ''; [void](Read-Host 'Skript beendet. Zum Schließen Enter drücken') } catch { Write-Host (`$_ | Out-String) -ForegroundColor Red; [void](Read-Host 'Fehler im Skript. Zum Schließen Enter drücken') }"
    $kodiert = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($gesamt))

    ### Prozess starten
    try {
        $pwsh = (Get-Process -Id $PID).Path
        $script:WtProzess = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $kodiert -WindowStyle Normal -PassThru -ErrorAction Stop
    }
    catch {
        $script:WtProzess = $null
        Remove-WolWtAnmeldeDatei
        $c.TxtStatus.Text = "Das Skript konnte nicht gestartet werden: $($_.Exception.Message)"
        Write-WolLog "WaToKi: $($s.Name) konnte nicht gestartet werden: $($_.Exception.Message)"
        return
    }
    $script:WtProzessName = $s.Name
    $script:WtStart = Get-Date
    $zielText = $(if ($ziele.Count -gt 0) { ' für ' + ($ziele -join ', ') } else { '' })
    Write-WolLog "WaToKi: $($s.Name) gestartet$zielText"
    if (-not $script:WtTimer) {
        $script:WtTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:WtTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:WtTimer.Add_Tick({ Watch-WolWtProzess })
    }
    $script:WtTimer.Start()
    Update-WolWtStatus
}

# Automatik
## Skriptnamen aus dem Text der Spalte Wartungsreihenfolge (Komma, Semikolon, senkrechter Strich oder Zeilenumbruch getrennt; "Wartung-" und ".ps1" werden toleriert)
function script:Get-WolWtReihenfolgeNamen {
    param([string]$Text)
    return @(([string]$Text) -split '[,;|\r\n]+' | ForEach-Object { ($_.Trim() -replace '^Wartung-', '' -replace '\.ps1$', '') } | Where-Object { $_ })
}

## Plan: je Skript die zugehörigen Geräte (Skripte ohne Mehrfach-Ziel laufen je Gerät), sortiert nach Skriptname
function script:New-WolWtPlan {
    $skripte = @(Get-WolWtSkripte)
    $nachName = @{}
    foreach ($s in $skripte) { $nachName[([System.IO.Path]::GetFileNameWithoutExtension($s.Name) -replace '^Wartung-', '').ToLowerInvariant()] = $s }
    $gruppen = @{}
    $unbekannt = [System.Collections.Generic.List[string]]::new()
    foreach ($z in @($script:Zeilen)) {
        foreach ($name in (Get-WolWtReihenfolgeNamen -Text ([string]$z['Wartungsreihenfolge']))) {
            $key = $name.ToLowerInvariant()
            if ($nachName.ContainsKey($key)) {
                if (-not $gruppen.ContainsKey($key)) { $gruppen[$key] = [System.Collections.Generic.List[object]]::new() }
                $gruppen[$key].Add($z)
            }
            else { $unbekannt.Add("$name ($(Get-WolZielName -Zeile $z))") }
        }
    }
    $plan = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($gruppen.Keys | Sort-Object)) {
        $s = $nachName[$key]
        $zeilen = @($gruppen[$key])
        if ($s.HatZiel -and -not $s.ZielMehrere) {
            foreach ($z in $zeilen) { $plan.Add([pscustomobject]@{ Skript = $s; Zeilen = @($z) }) }
        }
        else { $plan.Add([pscustomobject]@{ Skript = $s; Zeilen = $zeilen }) }
    }
    return [pscustomobject]@{ Plan = @($plan); Unbekannt = @($unbekannt) }
}

## Aufruf eines Skripts im Automatiklauf aufbauen (ohne Rückfragen); Fehler kommen als Text zurück
function script:Get-WolWtAutoAufruf {
    param($Skript, $Zeilen, [string]$Ausgabe)
    $r = [pscustomobject]@{ Befehl = ''; AnmeldeDatei = ''; Ziele = @(); Fehler = '' }
    if (-not $Skript.HatAutomatik) { $r.Fehler = "Das Skript kennt den Parameter -$($script:WtParamAutomatik) noch nicht."; return $r }
    if ($Skript.Fehler) { $r.Fehler = $Skript.Fehler; return $r }
    $ziele = @()
    if ($Skript.HatZiel) { $ziele = @($Zeilen | ForEach-Object { Get-WolZielName -Zeile $_ }) }
    $r.Ziele = $ziele
    $konto = $null
    $anmeldeParam = ''
    if ($Skript.HatZiel -and ($Skript.HatAnmeldung -or $Skript.HatAnmeldungJeZiel)) {
        $ohne = @($Zeilen | Where-Object { $_.Konto -and -not $_.Kennwort })
        if ($ohne.Count -gt 0) {
            $r.Fehler = 'Kennwort der Sitzung fehlt für: ' + ((@($ohne | ForEach-Object { Get-WolZielName -Zeile $_ })) -join ', ')
            return $r
        }
        try {
            if ($Skript.HatAnmeldungJeZiel) {
                $anmeldeParam = $script:WtParamAnmeldungJeZiel
                $konto = @{}
                foreach ($z in $Zeilen) {
                    $k = Get-WolAnmeldung -Zeile $z
                    if ($k) { $konto[(Get-WolZielName -Zeile $z)] = $k }
                }
                if ($konto.Count -eq 0) { $konto = $null }
            }
            else {
                $anmeldeParam = $script:WtParamAnmeldung
                $konten = @($Zeilen | ForEach-Object { ([string]$_.Konto).ToLower() } | Select-Object -Unique)
                if ($konten.Count -gt 1) { $r.Fehler = 'Die Geräte haben unterschiedliche Konten, das Skript nimmt nur eins.'; return $r }
                $konto = Get-WolAnmeldung -Zeile $Zeilen[0]
            }
        }
        catch { $r.Fehler = $_.Exception.Message; return $r }
        if ($konto) {
            $datei = Join-Path ([System.IO.Path]::GetTempPath()) ('BETA-NET-COCKPIT_Anmeldung_' + [guid]::NewGuid().ToString('N') + '.xml')
            try { $konto | Export-Clixml -LiteralPath $datei -ErrorAction Stop }
            catch { $r.Fehler = "Die Anmeldedaten konnten nicht übergeben werden: $($_.Exception.Message)"; return $r }
            $r.AnmeldeDatei = $datei
        }
    }
    $befehl = "& '" + (ConvertTo-WolWtText $Skript.Pfad) + "'"
    if ($Skript.HatZiel) {
        $liste = ($ziele | ForEach-Object { "'" + (ConvertTo-WolWtText $_) + "'" }) -join ','
        $befehl += " -$($script:WtParamZiel) " + $(if ($Skript.ZielMehrere) { "@($liste)" } else { $liste })
    }
    if ($r.AnmeldeDatei) { $befehl += " -$anmeldeParam `$wtKonto" }
    if ($Skript.HatAusgabe) { $befehl += " -$($script:WtParamAusgabe) '" + (ConvertTo-WolWtText $Ausgabe) + "'" }
    $befehl += " -$($script:WtParamAutomatik)"
    $kontoBefehl = $(if ($r.AnmeldeDatei) { "`$wtKonto = Import-Clixml -LiteralPath '" + (ConvertTo-WolWtText $r.AnmeldeDatei) + "'; Remove-Item -LiteralPath '" + (ConvertTo-WolWtText $r.AnmeldeDatei) + "' -Force; " } else { '' })
    $r.Befehl = "try { $kontoBefehl$befehl; if (`$LASTEXITCODE) { exit `$LASTEXITCODE }; exit 0 } catch { Write-Output (`$_ | Out-String); exit 1 }"
    return $r
}

## Ergebnis eines Skripts in die Liste des Laufs eintragen
function script:Add-WolWtErgebnis {
    param($Item, [string]$Status, [string]$Meldung, $Start, $Ende, [string]$Konsole, [string]$Ergebnisdatei)
    $l = $script:WtLauf
    $ergebnis = $null
    if ($Ergebnisdatei -and (Test-Path -LiteralPath $Ergebnisdatei)) {
        try { $ergebnis = Get-Content -LiteralPath $Ergebnisdatei -Raw -Encoding utf8 | ConvertFrom-Json -Depth 50 }
        catch { if ($Status -eq 'OK') { $Status = 'Fehler'; $Meldung = "Ergebnisdatei nicht lesbar: $($_.Exception.Message)" } }
    }
    elseif ($Status -eq 'OK') { $Status = 'Fehler'; $Meldung = 'Das Skript hat keine Ergebnisdatei geschrieben.' }
    $kurzName = ([System.IO.Path]::GetFileNameWithoutExtension($Item.Skript.Name) -replace '^Wartung-', '')
    $dauer = $(if ($Start -and $Ende) { [math]::Round(($Ende - $Start).TotalSeconds) } else { 0 })
    $l.Ergebnisse.Add([pscustomobject]@{
        Skript   = $kurzName
        Ziele    = @($Item.Zeilen | ForEach-Object { Get-WolZielName -Zeile $_ })
        Status   = $Status
        Meldung  = $Meldung
        Start    = $(if ($Start) { $Start.ToString('s') } else { '' })
        Ende     = $(if ($Ende) { $Ende.ToString('s') } else { '' })
        Sekunden = $dauer
        Konsole  = $Konsole
        Ergebnis = $ergebnis
    })
    Write-WolLog "WaToKi-Automatik: $($Item.Skript.Name) $Status$(if ($Meldung) { ' (' + $Meldung + ')' })"
}

## Techniker-Übersicht: HTML-Datei (als PDF druckbar), gegliedert wie die Wartungscheckliste
function script:ConvertTo-WolWtWertHtml {
    param($Wert)
    $e = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $istObjekt = { param($o) $null -ne $o -and $o.GetType().FullName -eq 'System.Management.Automation.PSCustomObject' }
    if ($null -eq $Wert) { return '' }
    if ($Wert -is [bool]) { return $(if ($Wert) { 'Ja' } else { 'Nein' }) }
    if ($Wert -is [datetime]) { return $Wert.ToString('dd.MM.yyyy HH:mm:ss') }
    if ($Wert -is [string] -or $Wert.GetType().IsPrimitive -or $Wert -is [decimal]) { return ((& $e $Wert) -replace "`r?`n", '<br>') }
    if ($Wert -is [System.Collections.IEnumerable]) {
        $liste = @($Wert)
        if ($liste.Count -eq 0) { return '–' }
        if (-not @($liste | Where-Object { -not (& $istObjekt $_) }).Count) {
            $spalten = @($liste | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique)
            $gew = @(foreach ($sp in $spalten) { $max = 0; foreach ($z in $liste) { $l = ([string]$z.$sp).Length; if ($l -gt $max) { $max = $l } }; [math]::Min([math]::Max([math]::Max($max, $sp.Length), 11), 70) })
            $summe = ($gew | Measure-Object -Sum).Sum
            $cols = '<colgroup>' + (($gew | ForEach-Object { '<col style="width:' + [math]::Round(100 * $_ / $summe, 1).ToString([cultureinfo]::InvariantCulture) + '%">' }) -join '') + '</colgroup>'
            $kopf = ($spalten | ForEach-Object { '<th>' + (& $e $_) + '</th>' }) -join ''
            $zeilen = foreach ($z in $liste) {
                $zellen = foreach ($sp in $spalten) { $zelle = $z.$sp; '<td>' + (ConvertTo-WolWtWertHtml -Wert $zelle) + '</td>' }
                '<tr>' + ($zellen -join '') + '</tr>'
            }
            return "<table class='w'>$cols<tr>$kopf</tr>$($zeilen -join '')</table>"
        }
        return '<ul>' + (($liste | ForEach-Object { '<li>' + (ConvertTo-WolWtWertHtml -Wert $_) + '</li>' }) -join '') + '</ul>'
    }
    if (& $istObjekt $Wert) {
        $zeilen = foreach ($p in $Wert.PSObject.Properties) { $wp = $p.Value; '<tr><th>' + (& $e $p.Name) + '</th><td>' + (ConvertTo-WolWtWertHtml -Wert $wp) + '</td></tr>' }
        return "<table class='w'><colgroup><col style='width:35%'><col></colgroup>$($zeilen -join '')</table>"
    }
    return (& $e $Wert)
}

function script:New-WolWtTechnikerHtml {
    param($Gesamt, [string]$Pfad, $Konsolen = @())
    $e = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $kurzZiel = { param($z) $s = ([string]$z).Trim(); if ($s -match '^\d+(\.\d+){3}$') { $s } else { ($s -split '\.')[0] } }
    $eig = { param($o, $n) if ($null -ne $o -and $o.PSObject.Properties[$n]) { $o.PSObject.Properties[$n].Value } else { $null } }
    $pruefText = @{
        Anwendung = 'Ereignisprotokoll Anwendung geprüft'; System = 'Ereignisprotokoll System geprüft'; Sicherheit = 'Ereignisprotokoll Sicherheit geprüft'
        ActiveDirectory = 'Ereignisprotokoll Active Directory geprüft'; DNS = 'Ereignisprotokoll DNS geprüft'; DHCP = 'Ereignisprotokoll DHCP geprüft'
        Dateiserver = 'Ereignisprotokoll Dateiserver geprüft'; DiensteGestartet = 'Alle automatisch startenden Dienste gestartet'
        Speicherplatz = 'Freier Speicherplatz (mindestens 10 % je Laufwerk)'; SpeicherplatzOk = 'Speicherplatz ausreichend'
        RaidHdd = 'RAID / HDDs in Ordnung'; Firmware = 'Firmware'; Bios = 'BIOS'; Netzteile = 'Netzteile'; BackupErfolgreich = 'Datensicherung erfolgreich'
        BatterieOk = 'Status der Batterie in Ordnung'; UsvErreichbar = 'USV erreichbar'; CentralBerichteGeprueft = 'Sophos-Central-Berichte geprüft'
        ClusterOk = 'Cluster läuft'; HostsVerbunden = 'Hosts verbunden'; DagOk = 'DAG-Konsistenzprüfung'; FirmwareAktuell = 'Firmware aktuell'
        IntegrationsdiensteOk = 'Integrationsdienste aktuell'; InternetOnline = 'Internetverbindung online'; KeineSnapshots = 'Keine veralteten Snapshots'
        KonfigSicherung = 'Konfigurationssicherung vorhanden'; LogGeprueft = 'Log auf erfolgreiche Angriffe geprüft'; RelayOk = 'E-Mail-Relay funktioniert'
        ReplikationOk = 'Hyper-V-Replikation funktioniert'; SeamlessKeyOk = 'Seamless-SSO-Key aktuell'; SqlSicherungenAktuell = 'SQL-Sicherungen aktuell'
        SyncOk = 'Entra-Synchronisierung fehlerfrei'; VmsLaufen = 'VMs laufen'; VmwareToolsOk = 'VMware Tools aktuell'
        WindowsUpdates = 'Windows-Updates aktuell (letztes Update höchstens 60 Tage alt)'; ZertifikateGueltig = 'Zertifikate gültig'
        DcdiagOk = 'dcdiag fehlerfrei'; RootHintsOk = 'Root-Hints entsprechen der offiziellen Liste'
    }
    $bereichText = @{
        '02.2' = 'Datensicherung'; '03.1' = 'Hardware physische Server'; '03.2' = 'Protokolle Server / NAS'; '04.1' = 'Protokolle virtuelle Server'
        '05.1' = 'Virtualisierung'; '05.2' = 'Exchange'; '05.3' = 'Active Directory'; '05.4' = 'MailStore'; '05.5' = 'SQL-Server'
        '06.2' = 'Entra Connect'; '06.5' = 'E-Mail-Security'; '07.1' = 'Firewall'; '07.3' = 'Updates'
        '08.1' = 'Router'; '08.2' = 'Switche'; '08.4' = 'NAS'; '08.5' = 'USV'; '09.4' = 'Telefonanlage'
    }
    $pText = { param($k) if ($pruefText.ContainsKey($k)) { $pruefText[$k] } else { ($k -creplace '([a-z])([A-Z])', '$1 $2') } }
    $dienstListe = { param($w) @($w) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and $_ -notmatch '^Status\s+StartType' -and $_ -notmatch '^-+(\s|$)' } | ForEach-Object { $_ -replace '^Stopped\s+Automatic\s+', '' } }
    $datum = { param($t) if ($t -is [datetime]) { $t.ToString('dd.MM.yyyy HH:mm:ss') } else { $d = [datetime]::MinValue; if ([datetime]::TryParse([string]$t, [ref]$d)) { $d.ToString('dd.MM.yyyy HH:mm:ss') } else { [string]$t } } }
    $skripte = @($Gesamt.Skripte)

    # Fehler und Auffälligkeiten einsammeln
    $fehler = [System.Collections.Generic.List[string]]::new()
    $auff = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $skripte) {
        if ($s.Status -ne 'OK') { $fehler.Add('<b>' + (& $e $s.Skript) + '</b>: ' + (& $e $s.Status) + $(if ($s.Meldung) { ' – ' + (& $e $s.Meldung) } else { '' })) }
        $erg = & $eig $s.Ergebnis 'Ergebnisse'
        foreach ($r in @($erg)) {
            if ($null -eq $r) { continue }
            $ziel = & $kurzZiel $r.Ziel
            if (-not $r.Erreicht) {
                $fehler.Add('<b>' + (& $e $s.Skript) + '</b>, ' + (& $e $ziel) + ': nicht erreicht' + $(if ($r.Notiz) { ' – ' + (& $e $r.Notiz) } else { '' }))
                continue
            }
            $w = & $eig $r 'Werte'
            foreach ($p in @($r.Pruefungen.PSObject.Properties | Where-Object { $_.Value -eq $false })) {
                $det = ''
                if ($p.Name -eq 'DiensteGestartet') { $d = @(& $dienstListe (& $eig $w 'DiensteGestoppt')); if ($d.Count) { $det = ': ' + (($d | ForEach-Object { & $e $_ }) -join ', ') } }
                if ($p.Name -eq 'Speicherplatz') { $d = @(@(& $eig $w 'Speicherplatz') | Where-Object { $_ -and $_.FreiProzent -lt 10 } | ForEach-Object { (& $e $_.Laufwerk) + ' ' + $_.FreiProzent + ' % frei (' + $_.FreiGB + ' GB)' }); if ($d.Count) { $det = ': ' + ($d -join ', ') } }
                $txt = switch ($p.Name) { 'DiensteGestartet' { 'Automatisch startende Dienste gestoppt' } 'Speicherplatz' { 'Freier Speicherplatz unter 10 %' } default { (& $pText $p.Name) + ': nicht in Ordnung' } }
                $auff.Add('<b>' + (& $e $ziel) + '</b>, ' + (& $e $s.Skript) + ': ' + (& $e $txt) + $det)
            }
            if ($r.Notiz -and @($r.Pruefungen.PSObject.Properties | Where-Object { $_.Value -eq $false }).Count) { $auff.Add('<b>' + (& $e $ziel) + '</b>, ' + (& $e $s.Skript) + ': Hinweis des Skripts – ' + (& $e $r.Notiz)) }
        }
    }
    foreach ($u in @($Gesamt.Unbekannt)) { if ($u) { $fehler.Add('Unbekannter Skriptname in der Wartungsreihenfolge: ' + (& $e $u)) } }

    $h = [System.Text.StringBuilder]::new()
    [void]$h.AppendLine('<!DOCTYPE html><html lang="de"><head><meta charset="utf-8"><title>Techniker-Übersicht Autowartung</title><style>')
    [void]$h.AppendLine('@page{size:A4;margin:12mm}body{font:10pt/1.35 Segoe UI,Arial,sans-serif;color:#111;margin:0 auto;max-width:190mm}h1{font-size:18pt;margin:0 0 4px}h2{font-size:14pt;border-bottom:2px solid #333;padding-bottom:2px;margin:22px 0 8px;break-after:avoid}h3{font-size:11.5pt;margin:14px 0 4px;break-after:avoid}h4{font-size:10pt;margin:8px 0 3px}')
    [void]$h.AppendLine('table{border-collapse:collapse;width:100%;margin:4px 0;table-layout:fixed}th,td{border:1px solid #bbb;padding:2px 5px;vertical-align:top;text-align:left;overflow-wrap:anywhere}table.m td:first-child,table.m th:first-child{width:46%}th{background:#eee}table.w{font-size:8.5pt;margin:0}table.w th,table.w td{overflow-wrap:anywhere}table.w th{background:#f5f5f5;font-weight:600}tr{break-inside:avoid}ul{margin:0;padding-left:16px}')
    [void]$h.AppendLine('.ok{color:#0a6b2d;font-weight:600}.bad{color:#b00020;font-weight:600}.na{color:#777}.box{border:2px solid #b00020;background:#fdecee;padding:6px 10px;margin:10px 0;break-inside:avoid}.box.gut{border-color:#0a6b2d;background:#e9f6ee}.box.gelb{border-color:#b26a00;background:#fff4e0}.meta{color:#444;font-size:9pt}')
    [void]$h.AppendLine('.badge{font-size:8.5pt;padding:1px 6px;border-radius:8px;border:1px solid #999;margin-left:6px;font-weight:600}.seite{break-before:page}pre{white-space:pre-wrap;font:8pt/1.3 Consolas,monospace;border:1px solid #ccc;padding:6px;background:#fafafa}.notiz{margin:3px 0}')
    [void]$h.AppendLine('</style></head><body>')
    [void]$h.AppendLine('<h1>Techniker-Übersicht Autowartung</h1>')
    $z = $Gesamt.Zusammenfassung
    [void]$h.AppendLine('<div class="meta">Lauf: ' + (& $e (& $datum $Gesamt.Start)) + ' bis ' + (& $e (& $datum $Gesamt.Ende)) + ' &middot; Rechner: ' + (& $e $Gesamt.Rechner) + ' &middot; ' + (& $e $z.OK) + ' OK, ' + (& $e $z.Uebersprungen) + ' übersprungen, ' + (& $e $z.Fehler) + ' Fehler' + $(if ($z.Abgebrochen -gt 0) { ', ' + $z.Abgebrochen + ' abgebrochen' } else { '' }) + '</div>')
    if ($fehler.Count) { [void]$h.AppendLine('<div class="box"><b>Fehler beim Auslesen (' + $fehler.Count + ')</b><ul>' + (($fehler | ForEach-Object { '<li>' + $_ + '</li>' }) -join '') + '</ul></div>') }
    else { [void]$h.AppendLine('<div class="box gut"><b>Keine Fehler beim Auslesen.</b> Alle Skripte liefen durch, alle Ziele wurden erreicht.</div>') }
    if ($auff.Count) { [void]$h.AppendLine('<div class="box gelb"><b>Auffälligkeiten (' + $auff.Count + ')</b><ul>' + (($auff | ForEach-Object { '<li>' + $_ + '</li>' }) -join '') + '</ul></div>') }
    else { [void]$h.AppendLine('<div class="box gut"><b>Keine Auffälligkeiten</b> in den ausgelesenen Prüfungen.</div>') }

    # Gliederung wie die Checkliste: je Seite (erste zwei Ziffern des Skripts), darin je Skript
    $gruppen = $skripte | Group-Object { ([string]$_.Skript).Substring(0, 2) } | Sort-Object Name
    foreach ($g in $gruppen) {
        [void]$h.AppendLine('<h2 class="seite">Checkliste Seite ' + [int]$g.Name + '</h2>')
        foreach ($s in ($g.Group | Sort-Object Skript)) {
            $nr = ([string]$s.Skript).Substring(0, 4)
            $titel = $(if ($bereichText.ContainsKey($nr)) { & $e $bereichText[$nr] } else { & $e $s.Skript })
            $cls = $(if ($s.Status -eq 'OK') { 'ok' } else { 'bad' })
            [void]$h.AppendLine('<h3>' + $nr + ' ' + $titel + '<span class="badge ' + $cls + '">' + (& $e $s.Status) + '</span></h3>')
            [void]$h.AppendLine('<div class="meta">Skript: ' + (& $e $s.Skript) + ' &middot; Ziele: ' + $(if (@($s.Ziele).Count) { (@($s.Ziele) | ForEach-Object { & $e (& $kurzZiel $_) }) -join ', ' } else { '-' }) + ' &middot; Dauer: ' + (& $e $s.Sekunden) + ' s' + $(if ($s.Meldung) { ' &middot; Meldung: ' + (& $e $s.Meldung) } else { '' }) + '</div>')
            $erg = @(& $eig $s.Ergebnis 'Ergebnisse') | Where-Object { $null -ne $_ }
            if (-not $erg.Count) { [void]$h.AppendLine('<p class="bad">Kein Ergebnis vom Skript.</p>'); continue }
            # Matrix: Prüfung x Ziel
            $schluessel = @($erg | ForEach-Object { if ($_.Pruefungen) { $_.Pruefungen.PSObject.Properties.Name } } | Select-Object -Unique)
            if ($schluessel.Count) {
                $kopf = '<tr><th>Prüfung</th>' + (($erg | ForEach-Object { '<th>' + (& $e (& $kurzZiel $_.Ziel)) + '</th>' }) -join '') + '</tr>'
                $zeilen = foreach ($k in $schluessel) {
                    $zellen = foreach ($r in $erg) {
                        $v = $(if ($r.Erreicht -and $r.Pruefungen) { & $eig $r.Pruefungen $k } else { $null })
                        if ($v -eq $true) { '<td class="ok">&#10004; OK</td>' } elseif ($v -eq $false) { '<td class="bad">&#10006; Auffällig</td>' } elseif (-not $r.Erreicht) { '<td class="na">nicht erreicht</td>' } else { '<td class="na">keine Angabe</td>' }
                    }
                    '<tr><td>' + (& $e (& $pText $k)) + '</td>' + ($zellen -join '') + '</tr>'
                }
                [void]$h.AppendLine('<table class="m">' + $kopf + ($zeilen -join '') + '</table>')
            }
            # Notizen und alle Werte je Ziel
            foreach ($r in $erg) {
                $zn = & $e (& $kurzZiel $r.Ziel)
                [void]$h.AppendLine('<h4>' + $zn + $(if ($r.Erreicht) { '' } else { ' <span class="bad">&ndash; nicht erreicht</span>' }) + '</h4>')
                if ($r.Notiz) { [void]$h.AppendLine('<div class="notiz"><b>Notiz:</b> ' + (& $e $r.Notiz) + '</div>') }
                $w = & $eig $r 'Werte'
                if ($w -and @($w.PSObject.Properties).Count) {
                    $zw = foreach ($p in $w.PSObject.Properties) {
                        $wert = $p.Value
                        if ($p.Name -eq 'DiensteGestoppt') { $wert = @(& $dienstListe $wert) }
                        '<tr><th style="width:30%">' + (& $e $p.Name) + '</th><td>' + (ConvertTo-WolWtWertHtml -Wert $wert) + '</td></tr>'
                    }
                    [void]$h.AppendLine('<table>' + ($zw -join '') + '</table>')
                }
            }
        }
    }
    # Anhang: Konsolenausgabe der Skripte
    [void]$h.AppendLine('<h2 class="seite">Anhang: Konsolenausgabe der Skripte</h2>')
    for ($i = 0; $i -lt $skripte.Count; $i++) {
        $s = $skripte[$i]
        $k = $(if ($i -lt @($Konsolen).Count) { [string]@($Konsolen)[$i] } else { '' }) -replace '\x1B\[[0-9;]*[A-Za-z]', ''
        [void]$h.AppendLine('<h3>' + (& $e $s.Skript) + '</h3>' + $(if ($k.Trim()) { '<pre>' + (& $e $k.TrimEnd()) + '</pre>' } else { '<p class="na">Keine Ausgabe.</p>' }))
    }
    [void]$h.AppendLine('</body></html>')
    $h.ToString() | Set-Content -LiteralPath $Pfad -Encoding utf8BOM
}

## Lieferschein-Entwurf: knapp, nach Themen der Wartungscheckliste gegliedert, nur Auffälligkeiten aus den Skriptergebnissen, ohne Bewertung
function script:New-WolWtLieferschein {
    param($Gesamt, [string]$Pfad)
    $eig = { param($o, $n) if ($null -ne $o -and $o.PSObject.Properties[$n]) { $o.PSObject.Properties[$n].Value } else { $null } }
    $kurzZiel = { param($z) $s = ([string]$z).Trim(); if ($s -match '^\d+(\.\d+){3}$') { $s } else { ($s -split '\.')[0] } }
    $dezimal = { param($x) ([double]$x).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ',') }
    $themaVon = { param($n)
        switch -Regex ($n) {
            '^02\.' { 'Backup'; break }
            '^03\.1' { 'Hardware'; break }
            '^(03\.2|04\.)' { 'Server'; break }
            '^05\.1' { 'Virtualisierung'; break }
            '^05\.2' { 'Exchange'; break }
            '^05\.3' { 'Active Directory'; break }
            '^05\.4' { 'Mailstore'; break }
            '^05\.5' { 'SQL'; break }
            '^06\.2' { 'Microsoft 365'; break }
            '^06\.5' { 'Mailsecurity'; break }
            '^07\.1' { 'Firewall'; break }
            '^07\.3' { 'Updates'; break }
            '^08\.1' { 'Router'; break }
            '^08\.2' { 'Switche'; break }
            '^08\.4' { 'NAS'; break }
            '^08\.5' { 'USV'; break }
            '^09\.4' { 'TK-Anlage'; break }
            default { $n }
        }
    }
    # Texte für nicht bestandene Prüfungen, wenn das Skript keine Notiz dazu liefert
    $keyText = @{
        DcdiagOk = 'dcdiag nicht fehlerfrei'; RootHintsOk = 'Root-Hints weichen ab'; SeamlessKeyOk = 'Seamless-SSO-Key nicht aktuell'
        SyncOk = 'Entra-Synchronisierung nicht fehlerfrei'; KonfigSicherung = 'Konfigurationssicherung fehlt'; WindowsUpdates = 'Updates nicht aktuell'
        BackupErfolgreich = 'Sicherung nicht erfolgreich'; RelayOk = 'E-Mail-Relay nicht in Ordnung'; KeineSnapshots = 'veraltete Snapshots vorhanden'
        ReplikationOk = 'Replikation nicht in Ordnung'; ClusterOk = 'Cluster nicht in Ordnung'; HostsVerbunden = 'Hosts nicht verbunden'
        VmsLaufen = 'VMs laufen nicht alle'; SpeicherplatzOk = 'Speicherplatz knapp'; IntegrationsdiensteOk = 'Integrationsdienste nicht aktuell'
        VmwareToolsOk = 'VMware Tools nicht aktuell'; DagOk = 'DAG-Konsistenzprüfung fehlgeschlagen'; ZertifikateGueltig = 'Zertifikat läuft ab oder ist abgelaufen'
        SqlSicherungenAktuell = 'SQL-Sicherungen nicht aktuell'; FirmwareAktuell = 'Firmware nicht aktuell'; LogGeprueft = 'Log nicht geprüft'
        InternetOnline = 'Internetverbindung nicht online'; BatterieOk = 'Batterie nicht in Ordnung'; UsvErreichbar = 'USV nicht erreichbar'
    }
    $themen = [ordered]@{}
    $dienste = [ordered]@{}
    $platz = [System.Collections.Generic.List[string]]::new()
    foreach ($s in @($Gesamt.Skripte)) {
        $skriptName = [string](& $eig $s 'Skript')
        $thema = & $themaVon $skriptName
        $erg = & $eig $s 'Ergebnis'
        foreach ($e in @(& $eig $erg 'Ergebnisse')) {
            if (-not $e) { continue }
            $name = & $kurzZiel $e.Ziel
            if (-not $themen.Contains($thema)) { $themen[$thema] = [ordered]@{} }
            if (-not $themen[$thema].Contains($name)) { $themen[$thema][$name] = [System.Collections.Generic.List[string]]::new() }
            $z = $themen[$thema][$name]
            $notiz = [string](& $eig $e 'Notiz')
            if (-not $e.Erreicht) { $z.Add('von der Wartungsautomatik nicht erreicht'); continue }
            $pr = & $eig $e 'Pruefungen'
            $w = & $eig $e 'Werte'
            $falsch = @()
            if ($pr) { $falsch = @($pr.PSObject.Properties | Where-Object { $_.Value -eq $false } | ForEach-Object { $_.Name }) }
            $istServer = ($thema -eq 'Server')
            $anzDienste = @(@(& $eig $w 'DiensteGestoppt') | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and $_ -notmatch '^Status\s+StartType' -and $_ -notmatch '^-{3,}' }).Count
            if ($istServer) {
                $ids = @(@(& $eig $w 'Ereignisse') | Where-Object { $_ } | ForEach-Object { [string]$_.Id } | Select-Object -Unique)
                if ($ids.Count -gt 0) { $z.Add('Ereignis-IDs ' + ($ids -join ', ')) }
            }
            if ($falsch -contains 'DiensteGestartet') {
                if ($istServer) { $dienste[$name] = $anzDienste }
                elseif (-not $dienste.Contains($name)) { $z.Add('Dienste gestoppt') }
            }
            if ($istServer -and ($falsch -contains 'Speicherplatz')) {
                $d = @(@(& $eig $w 'Speicherplatz') | Where-Object { $_ -and $null -ne $_.FreiProzent -and [double]$_.FreiProzent -lt 10 } | ForEach-Object { '{0} {1} {2} GB' -f $name, $_.Laufwerk, (& $dezimal $_.FreiGB) })
                if ($d.Count -gt 0) { foreach ($x in $d) { $platz.Add($x) } } else { $platz.Add("$name zu knapp") }
            }
            $rest = @($falsch | Where-Object { $_ -ne 'DiensteGestartet' -and -not ($istServer -and $_ -eq 'Speicherplatz') })
            if ($rest.Count -gt 0) {
                $teile = @($notiz -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^Automatische Dienste' -and $_ -notmatch '^Speicherplatz' -and $_ -notmatch '^Version\s' })
                if ($teile.Count -gt 0) { foreach ($t in $teile) { $z.Add($t) } }
                else { foreach ($k in $rest) { $z.Add($(if ($keyText.ContainsKey($k)) { $keyText[$k] } else { "Prüfung $k nicht bestanden" })) } }
            }
            elseif ($istServer -and $notiz) { $z.Add($notiz) }
            if ($thema -eq 'Active Directory') {
                $b = & $eig $w 'InaktiveBenutzer'; $c = & $eig $w 'InaktiveComputer'
                $teile = @()
                if ([int]$b -gt 0) { $teile += "$b inaktive Benutzer" }
                if ([int]$c -gt 0) { $teile += "$c inaktive Computer" }
                if ($teile.Count -gt 0) { $z.Add($teile -join ', ') }
            }
        }
    }
    $zeilen = [System.Collections.Generic.List[string]]::new()
    foreach ($thema in $themen.Keys) {
        $je = [ordered]@{}
        foreach ($n in $themen[$thema].Keys) { $l = @($themen[$thema][$n] | Select-Object -Unique); if ($l.Count -gt 0) { $je[$n] = $l } }
        $extra = [System.Collections.Generic.List[string]]::new()
        if ($thema -eq 'Server') {
            if ($dienste.Count -gt 0) { $extra.Add('Dienste gestoppt: ' + (($dienste.Keys) -join ', ')) }
            if ($platz.Count -gt 0) { $extra.Add('Speicherplatz niedrig: ' + ($platz -join ', ')) }
        }
        if ($je.Count -eq 0 -and $extra.Count -eq 0) { continue }
        if ($thema -in 'Server', 'Backup') {
            $zeilen.Add("- ${thema}:")
            foreach ($n in $je.Keys) { $zeilen.Add("-- ${n}: " + ($je[$n] -join ', ')) }
            foreach ($x in $extra) { $zeilen.Add("-- $x") }
        }
        elseif ($je.Count -eq 1) { $zeilen.Add("- ${thema}: " + ($je[@($je.Keys)[0]] -join ', ')) }
        else { $zeilen.Add("- ${thema}: " + ((@($je.Keys) | ForEach-Object { "${_}: " + ($je[$_] -join ', ') }) -join '; ')) }
    }
    $kopf = $(if ($zeilen.Count -gt 0) { '- proaktive IT-Wartung gem. Wartungscheckliste ausgeführt, folgende Auffälligkeiten festgestellt:' } else { '- proaktive IT-Wartung gem. Wartungscheckliste ausgeführt, keine Auffälligkeiten' })
    (@($kopf) + $zeilen) -join "`r`n" | Set-Content -LiteralPath $Pfad -Encoding utf8BOM
}

## Lauf abschließen: Autowartung-Gesamtdatei.json und Detail.txt schreiben
function script:Complete-WolWtAutomatik {
    $l = $script:WtLauf
    $script:WtAutoTimer.Stop()
    $ende = Get-Date
    $zaehl = @{ OK = 0; 'übersprungen' = 0; Fehler = 0; 'abgebrochen' = 0 }
    foreach ($e in $l.Ergebnisse) { $zaehl[$e.Status] = 1 + [int]$zaehl[$e.Status] }
    try {
        $gesamt = [pscustomobject]@{
            Version      = 1
            Start        = $l.Start.ToString('s')
            Ende         = $ende.ToString('s')
            Rechner      = $env:COMPUTERNAME
            Unbekannt    = @($l.Unbekannt)
            Zusammenfassung = [pscustomobject]@{ OK = [int]$zaehl['OK']; Uebersprungen = [int]$zaehl['übersprungen']; Fehler = [int]$zaehl['Fehler']; Abgebrochen = [int]$zaehl['abgebrochen'] }
            Skripte      = @($l.Ergebnisse | ForEach-Object { [pscustomobject]@{ Skript = $_.Skript; Ziele = $_.Ziele; Status = $_.Status; Meldung = $_.Meldung; Start = $_.Start; Ende = $_.Ende; Sekunden = $_.Sekunden; Konsole = $_.Konsole; Ergebnis = $_.Ergebnis } })
        }
        $gesamt | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $l.Ordner 'Autowartung-Gesamtdatei.json') -Encoding utf8
        $text = [System.Collections.Generic.List[string]]::new()
        $text.Add('WaToKi Automatiklauf')
        $text.Add("Start : $($l.Start.ToString('dd.MM.yyyy HH:mm:ss'))")
        $text.Add("Ende  : $($ende.ToString('dd.MM.yyyy HH:mm:ss'))")
        $text.Add("Ergebnis: $($zaehl['OK']) OK, $($zaehl['übersprungen']) übersprungen, $($zaehl['Fehler']) Fehler$(if ($zaehl['abgebrochen'] -gt 0) { ', ' + $zaehl['abgebrochen'] + ' abgebrochen' })")
        if ($l.Unbekannt.Count -gt 0) { $text.Add('Unbekannte Skriptnamen in der Wartungsreihenfolge: ' + ($l.Unbekannt -join '; ')) }
        foreach ($e in $l.Ergebnisse) {
            $text.Add('')
            $text.Add('=' * 70)
            $text.Add("$($e.Skript)  [$($e.Status)]  $($e.Sekunden) s")
            $text.Add("Ziele: $(if ($e.Ziele.Count -gt 0) { $e.Ziele -join ', ' } else { '-' })")
            if ($e.Meldung) { $text.Add("Hinweis: $($e.Meldung)") }
            $text.Add('=' * 70)
            if ($e.Konsole) { $text.Add($e.Konsole.TrimEnd()) }
        }
        ($text -join "`r`n") | Set-Content -LiteralPath (Join-Path $l.Ordner 'Detail.txt') -Encoding utf8BOM
        try { New-WolWtTechnikerHtml -Gesamt $gesamt -Pfad (Join-Path $l.Ordner 'Techniker-Uebersicht.html') -Konsolen @($l.Ergebnisse | ForEach-Object { [string]$_.Konsole }) }
        catch { Write-WolLog "WaToKi-Automatik: Techniker-Übersicht nicht geschrieben: $($_.Exception.Message)" }
        try { New-WolWtLieferschein -Gesamt $gesamt -Pfad (Join-Path $l.Ordner 'Lieferschein.txt') }
        catch { Write-WolLog "WaToKi-Automatik: Lieferschein nicht geschrieben: $($_.Exception.Message)" }
        Write-WolLog "WaToKi-Automatik beendet: $($zaehl['OK']) OK, $($zaehl['übersprungen']) übersprungen, $($zaehl['Fehler']) Fehler$(if ($zaehl['abgebrochen'] -gt 0) { ', ' + $zaehl['abgebrochen'] + ' abgebrochen' }) ($($l.Ordner))"
        $meldung = "Automatik beendet: $($zaehl['OK']) OK, $($zaehl['übersprungen']) übersprungen, $($zaehl['Fehler']) Fehler$(if ($zaehl['abgebrochen'] -gt 0) { ', ' + $zaehl['abgebrochen'] + ' abgebrochen' }). Ordner: $($l.Ordner)"
    }
    catch { $meldung = "Automatik beendet, aber die Ergebnisdateien konnten nicht geschrieben werden: $($_.Exception.Message)"; Write-WolLog "WaToKi-Automatik: $meldung" }
    $script:WtLauf = $null
    $script:WtProzess = $null
    if ($script:WtC.TxtStatus) { $script:WtC.TxtStatus.Text = $meldung }
    Update-WolWtStatus
}

## Nächstes Skript des Plans starten (übersprungene Skripte werden sofort eingetragen)
function script:Start-WolWtAutoNaechstes {
    $l = $script:WtLauf
    while ($l.Index -lt $l.Plan.Count) {
        $item = $l.Plan[$l.Index]
        $kurz = [System.IO.Path]::GetFileNameWithoutExtension($item.Skript.Name) -replace '^Wartung-', ''
        $aufruf = Get-WolWtAutoAufruf -Skript $item.Skript -Zeilen $item.Zeilen -Ausgabe $l.Ordner
        if ($aufruf.Fehler) {
            Add-WolWtErgebnis -Item $item -Status 'übersprungen' -Meldung $aufruf.Fehler -Start $null -Ende $null -Konsole '' -Ergebnisdatei ''
            $l.Index++
            continue
        }
        $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
        $l.AktuellKonsole = Join-Path $l.Ordner "Konsole_${kurz}_$suffix.txt"
        $l.AktuellFehler = Join-Path $l.Ordner "Fehler_${kurz}_$suffix.txt"
        $l.AktuellErgebnis = Join-Path $l.Ordner "Ergebnis_$kurz.json"
        $kodiert = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($aufruf.Befehl))
        try {
            $pwsh = (Get-Process -Id $PID).Path
            $script:WtProzess = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-OutputFormat', 'Text', '-EncodedCommand', $kodiert -WindowStyle Hidden -PassThru -RedirectStandardOutput $l.AktuellKonsole -RedirectStandardError $l.AktuellFehler -ErrorAction Stop
        }
        catch {
            $script:WtProzess = $null
            if ($aufruf.AnmeldeDatei -and (Test-Path -LiteralPath $aufruf.AnmeldeDatei)) { try { Remove-Item -LiteralPath $aufruf.AnmeldeDatei -Force -ErrorAction Stop } catch { } }
            Add-WolWtErgebnis -Item $item -Status 'Fehler' -Meldung "Start nicht möglich: $($_.Exception.Message)" -Start $null -Ende $null -Konsole '' -Ergebnisdatei ''
            $l.Index++
            continue
        }
        $l.AktuellItem = $item
        $l.AktuellAnmeldeDatei = $aufruf.AnmeldeDatei
        $script:WtAnmeldeDatei = $aufruf.AnmeldeDatei
        $script:WtProzessName = $item.Skript.Name
        $script:WtStart = Get-Date
        $zielText = $(if ($aufruf.Ziele.Count -gt 0) { ' für ' + ($aufruf.Ziele -join ', ') } else { '' })
        Write-WolLog "WaToKi-Automatik: $($item.Skript.Name) gestartet$zielText"
        Update-WolWtStatus
        return
    }
    Complete-WolWtAutomatik
}

## Laufendes Skript abschließen: Konsole einsammeln, Status bestimmen, Ergebnis eintragen (Abbruch = vom Knopf "Automatik stoppen" beendet)
function script:Complete-WolWtAktuell {
    param([bool]$Zeitlimit = $false, [bool]$Abbruch = $false)
    $l = $script:WtLauf
    $code = ''
    try { $code = [string]$script:WtProzess.ExitCode } catch { }
    $ende = Get-Date
    Remove-WolWtAnmeldeDatei
    $konsole = ''
    foreach ($d in $l.AktuellKonsole, $l.AktuellFehler) {
        if (Test-Path -LiteralPath $d) {
            $inhalt = Get-Content -LiteralPath $d -Raw -Encoding utf8
            if ($inhalt) { $konsole += $inhalt.TrimEnd() + "`r`n" }
            try { Remove-Item -LiteralPath $d -Force -ErrorAction Stop } catch { }
        }
    }
    if ($Abbruch) { $status = 'abgebrochen'; $meldung = 'Der Lauf wurde gestoppt, das Skript wurde beendet.' }
    elseif ($Zeitlimit) { $status = 'Fehler'; $meldung = "Zeitlimit von $($script:WtLimitMinuten) Minuten überschritten, das Skript wurde beendet." }
    elseif ($code -eq '0') { $status = 'OK'; $meldung = '' }
    else {
        $status = 'Fehler'; $meldung = "Exitcode $code"
        $z = ''
        try {
            if ($l.AktuellErgebnis -and (Test-Path -LiteralPath $l.AktuellErgebnis)) {
                $erg = Get-Content -LiteralPath $l.AktuellErgebnis -Raw -Encoding utf8 | ConvertFrom-Json -Depth 50
                $notizen = @($erg.Ergebnisse | Where-Object { -not $_.Erreicht -and $_.Notiz } | ForEach-Object {
                        $zk = $(if ([string]$_.Ziel -match '^\d+\.\d+\.\d+\.\d+$') { [string]$_.Ziel } else { ([string]$_.Ziel -split '\.')[0] })
                        "${zk}: $($_.Notiz)"
                    })
                if ($notizen.Count -gt 0) { $z = ($notizen | Select-Object -Unique) -join ' | ' }
            }
        } catch { }
        if (-not $z) {
            $letzte = @(($konsole -split '\r?\n') | Where-Object { $_.Trim() } | Select-Object -Last 1)
            if ($letzte.Count -gt 0) { $z = $letzte[0].Trim() }
        }
        if ($z) { if ($z.Length -gt 300) { $z = $z.Substring(0, 300) + '...' }; $meldung += ": $z" }
    }
    Add-WolWtErgebnis -Item $l.AktuellItem -Status $status -Meldung $meldung -Start $script:WtStart -Ende $ende -Konsole $konsole -Ergebnisdatei $l.AktuellErgebnis
    $script:WtProzess = $null
    $l.Index++
}

## Timer: laufendes Skript prüfen (Ende, Zeitlimit) und das nächste starten
function script:Watch-WolWtAutomatik {
    $l = $script:WtLauf
    if (-not $l) { $script:WtAutoTimer.Stop(); return }
    if ($script:WtProzess) {
        $laeuft = $true
        try { $laeuft = -not $script:WtProzess.HasExited } catch { $laeuft = $false }
        $zeitlimit = $false
        if ($laeuft) {
            if (((Get-Date) - $script:WtStart).TotalMinutes -lt $script:WtLimitMinuten) { Update-WolWtStatus; return }
            $zeitlimit = $true
            try { $script:WtProzess.Kill($true); [void]$script:WtProzess.WaitForExit(5000) } catch { }
        }
        Complete-WolWtAktuell -Zeitlimit $zeitlimit
    }
    Start-WolWtAutoNaechstes
}

## Automatik stoppen (Knopf "Automatik stoppen"): laufendes Skript beenden, übrige Skripte nicht mehr starten, bisherige Ergebnisse speichern
function script:Stop-WolWtAutomatik {
    if (-not $script:WtLauf) { return }
    $antwort = [System.Windows.MessageBox]::Show("Automatiklauf stoppen?`r`n`r`nDas laufende Skript wird beendet, die übrigen werden nicht mehr gestartet. Die bisherigen Ergebnisse werden gespeichert.", 'NET-COCKPIT', 'YesNo', 'Question')
    $l = $script:WtLauf
    if ($antwort -ne 'Yes' -or -not $l) { return }
    $script:WtAutoTimer.Stop()
    if ($script:WtProzess) {
        $beendet = $false
        try { $beendet = $script:WtProzess.HasExited } catch { $beendet = $true }
        if (-not $beendet) {
            try { $script:WtProzess.Kill($true); [void]$script:WtProzess.WaitForExit(5000) } catch { }
            Complete-WolWtAktuell -Abbruch $true
        }
        else { Complete-WolWtAktuell }
    }
    while ($l.Index -lt $l.Plan.Count) {
        Add-WolWtErgebnis -Item $l.Plan[$l.Index] -Status 'abgebrochen' -Meldung 'Der Lauf wurde gestoppt, das Skript wurde nicht gestartet.' -Start $null -Ende $null -Konsole '' -Ergebnisdatei ''
        $l.Index++
    }
    Write-WolLog 'WaToKi-Automatik: vom Benutzer gestoppt'
    Complete-WolWtAutomatik
}

## Automatiklauf starten (Knopf "Automatik starten")
function script:Start-WolWtAutomatik {
    if ($script:WtLauf -or $script:WtPruefJob -or (Test-WolWtLaeuft)) { Update-WolWtStatus; return }
    $c = $script:WtC
    $p = New-WolWtPlan
    if ($p.Plan.Count -eq 0) {
        $hinweis = "In der Spalte Wartungsreihenfolge steht bei keinem Gerät ein bekannter Skriptname (Beispiel: 05.1-VirtServer-HyperV)."
        if ($p.Unbekannt.Count -gt 0) { $hinweis += "`r`n`r`nUnbekannt: " + ($p.Unbekannt -join '; ') }
        Show-WolMeldung $hinweis 'Information'
        return
    }
    $bereit = @($p.Plan | Where-Object { $_.Skript.HatAutomatik -and -not $_.Skript.Fehler })
    $geraete = @($bereit | ForEach-Object { $_.Zeilen } | ForEach-Object { Get-WolZielName -Zeile $_ } | Select-Object -Unique).Count
    $text = "Die Automatik läuft jetzt los: $($bereit.Count) Skriptaufrufe" + $(if ($geraete -gt 0) { " für $geraete Geräte" } else { '' }) + ".`r`n`r`nDas Ergebnis liegt danach im Ausgabeordner. Mit dem Knopf 'Automatik stoppen' lässt sich der Lauf jederzeit beenden."
    $ohneAuto = @($p.Plan | Where-Object { -not ($_.Skript.HatAutomatik -and -not $_.Skript.Fehler) } | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Skript.Name) -replace '^Wartung-', '' } | Select-Object -Unique)
    if ($ohneAuto.Count -gt 0) { $text += "`r`n`r`nNicht dabei (Skript noch ohne Automatik-Modus): " + ($ohneAuto -join ', ') }
    if ($p.Unbekannt.Count -gt 0) { $text += "`r`n`r`nUnbekannte Skriptnamen (werden ignoriert): " + ($p.Unbekannt -join '; ') }
    $text += "`r`n`r`nJetzt starten?"
    $antwort = [System.Windows.MessageBox]::Show($text, 'NET-COCKPIT', 'YesNo', 'Question')
    if ($antwort -ne 'Yes') { return }
    ### Fehlende Kennwörter der Konten jetzt abfragen (einmal pro Benutzername), statt Skripte zu überspringen
    $kontoMenge = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    foreach ($item in @($bereit | Where-Object { $_.Skript.HatZiel -and ($_.Skript.HatAnmeldung -or $_.Skript.HatAnmeldungJeZiel) })) {
        foreach ($z in $item.Zeilen) { [void]$kontoMenge.Add($z) }
    }
    $kontoZeilen = @($kontoMenge)
    if ($kontoZeilen.Count -gt 0 -and -not (Resolve-WolKonten -Zeilen $kontoZeilen -Besitzer $script:WtFenster)) {
        $c.TxtStatus.Text = 'Automatik nicht gestartet: Die Kennwortabfrage wurde abgebrochen.'
        return
    }
    try {
        $ordner = Join-Path (Get-WolWtAusgabeOrdner) ('Autowartung_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        [void](New-Item -Path $ordner -ItemType Directory -Force -ErrorAction Stop)
    }
    catch { $c.TxtStatus.Text = "Der Ordner für den Lauf konnte nicht angelegt werden: $($_.Exception.Message)"; return }
    $script:WtLauf = @{
        Plan = @($p.Plan); Index = 0; Ordner = $ordner; Start = Get-Date
        Unbekannt = @($p.Unbekannt); Ergebnisse = [System.Collections.Generic.List[object]]::new()
        AktuellItem = $null; AktuellKonsole = ''; AktuellFehler = ''; AktuellErgebnis = ''; AktuellAnmeldeDatei = ''
    }
    Write-WolLog "WaToKi-Automatik gestartet: $($p.Plan.Count) Aufruf(e), Ordner $ordner"
    if (-not $script:WtAutoTimer) {
        $script:WtAutoTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:WtAutoTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:WtAutoTimer.Add_Tick({ Watch-WolWtAutomatik })
    }
    $script:WtAutoTimer.Start()
    Start-WolWtAutoNaechstes
}

## Verbindungsart eines Skripts (für die Automatik-Prüfung), aus dem Skriptnamen abgeleitet
function script:Get-WolWtTransport {
    param([string]$Name)
    $n = ($Name -replace '^Wartung-', '' -replace '\.ps1$', '')
    switch -Regex ($n) {
        '^(03\.2|04\.1)-' { return 'Windows-Ereignislog' }
        '^07\.3-' { return 'Windows-CIM' }
        '^05\.1-Virtualisierung_(ESXi|vCenter)' { return 'vSphere' }
        '^(02\.2-Backup-Veeam|05\.[1-5]-|06\.2-|06\.5-)' { return 'WinRM' }
        '^03\.1-physServerIPMI' { return 'IPMI' }
        '^(07\.1-Firewall-Fortigate|08\.2-|08\.4-NAS-QNAP)' { return 'SSH' }
        '^(07\.1-Firewall-Sophos_Central|09\.4-Starface)' { return 'Cloud' }
        '^(03\.1-physServeriDRAC|02\.2-Backup-Synology|07\.1-Firewall-Sophos|08\.1-|08\.4-NAS-Synology)' { return 'Web' }
        '^08\.5-' { return 'SNMP' }
        '^09\.4-3CX' { return 'WinRM-oder-SSH' }
        default { return 'Unbekannt' }
    }
}

## Aufgaben der Prüfung: je Gerät und Verbindungsart eine Aufgabe (mit Konto und Kennwort aus der Sitzung)
function script:New-WolWtPruefAufgaben {
    param($Plan)
    $aufgaben = @{}
    $probleme = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Plan) {
        $s = $item.Skript
        $kurz = [System.IO.Path]::GetFileNameWithoutExtension($s.Name) -replace '^Wartung-', ''
        if (-not $s.HatAutomatik) { $probleme.Add("${kurz}: kennt den Parameter -$($script:WtParamAutomatik) noch nicht (wird im Lauf übersprungen)"); continue }
        if ($s.Fehler) { $probleme.Add("${kurz}: $($s.Fehler)"); continue }
        if (-not $s.HatZiel) { $probleme.Add("${kurz}: wählt seine Geräte selbst, die Verbindung lässt sich hier nicht prüfen"); continue }
        $transport = Get-WolWtTransport -Name $s.Name
        $brauchtKonto = [bool]($s.HatAnmeldung -or $s.HatAnmeldungJeZiel)
        foreach ($z in $item.Zeilen) {
            $ziel = Get-WolZielName -Zeile $z
            $key = ("$ziel|$transport|" + [string]$z.Konto).ToLowerInvariant()
            if (-not $aufgaben.ContainsKey($key)) {
                $cred = $null
                $kwFehlt = $false
                try { $cred = Get-WolAnmeldung -Zeile $z } catch { $kwFehlt = $true }
                $aufgaben[$key] = [pscustomobject]@{ Ziel = $ziel; Transport = $transport; Skripte = [System.Collections.Generic.List[string]]::new(); Konto = [string]$z.Konto; Cred = $cred; KennwortFehlt = $kwFehlt; BrauchtKonto = $brauchtKonto }
            }
            elseif ($brauchtKonto) { $aufgaben[$key].BrauchtKonto = $true }
            if (-not $aufgaben[$key].Skripte.Contains($kurz)) { $aufgaben[$key].Skripte.Add($kurz) }
        }
    }
    $liste = @($aufgaben.Values | Sort-Object Ziel, Transport | ForEach-Object {
        $_.Skripte = @($_.Skripte)
        $_
    })
    return [pscustomobject]@{ Aufgaben = $liste; Probleme = @($probleme) }
}

## Läuft als Thread-Job: prüft je Aufgabe Name, Ping, Port und Anmeldung (nur lesend, je Gerät höchstens ein Anmeldeversuch)
$script:WtPruefBlock = {
    param($Aufgaben, [string]$SshText)
    $Aufgaben | ForEach-Object -ThrottleLimit 8 -Parallel {
        $a = $_
        $sshText = $using:SshText
        $ProgressPreference = 'SilentlyContinue'
        $pr = [System.Collections.Generic.List[object]]::new()
        $ok = { param($t) $pr.Add([pscustomobject]@{ Status = 'OK'; Text = $t }) }
        $hin = { param($t) $pr.Add([pscustomobject]@{ Status = 'Hinweis'; Text = $t }) }
        $feh = { param($t) $pr.Add([pscustomobject]@{ Status = 'Fehler'; Text = $t }) }
        $kurzFehler = { param($e) $m = (([string]$e.Exception.Message) -replace '\s+', ' ').Trim(); if ($m.Length -gt 260) { $m.Substring(0, 257) + '...' } else { $m } }
        $tcp = { param($h, $p) $c = [System.Net.Sockets.TcpClient]::new(); try { $t = $c.ConnectAsync($h, $p); ($t.Wait(3000) -and $c.Connected) } catch { $false } finally { $c.Dispose() } }
        $ziel = [string]$a.Ziel
        $wer = $(if ($a.Konto) { [string]$a.Konto } else { 'angemeldetes Windows-Konto' })

        $winrm = {
            $p5985 = & $tcp $ziel 5985
            $p5986 = & $tcp $ziel 5986
            if (-not $p5985 -and -not $p5986) { & $feh 'WinRM-Port 5985/5986 nicht erreichbar (Firewall oder WinRM nicht aktiviert).'; return }
            & $ok ('WinRM-Port ' + $(if ($p5985) { '5985' } else { '5986' }) + ' erreichbar')
            try {
                $so = New-PSSessionOption -OpenTimeout 20000 -OperationTimeout 30000
                $p = @{ ComputerName = $ziel; SessionOption = $so; ErrorAction = 'Stop' }
                if ($a.Cred) { $p.Credential = $a.Cred }
                if (-not $p5985) { $p.UseSSL = $true }
                $r = Invoke-Command @p -ScriptBlock { [pscustomobject]@{ Name = $env:COMPUTERNAME; Admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } }
                & $ok "WinRM-Anmeldung OK ($wer)"
                if (-not $r.Admin) { & $hin 'Das Konto hat in der Sitzung keine Administratorrechte (die meisten Skripte brauchen sie).' }
            }
            catch { & $feh ('WinRM-Anmeldung fehlgeschlagen: ' + (& $kurzFehler $_)) }
        }
        $cim = {
            $p5985 = & $tcp $ziel 5985
            $p5986 = & $tcp $ziel 5986
            if (-not $p5985 -and -not $p5986) { & $feh 'WinRM-Port 5985/5986 nicht erreichbar (Firewall oder WinRM nicht aktiviert).'; return $false }
            & $ok ('WinRM-Port ' + $(if ($p5985) { '5985' } else { '5986' }) + ' erreichbar')
            $cs = $null
            try {
                $cp = @{ ComputerName = $ziel; ErrorAction = 'Stop'; OperationTimeoutSec = 20 }
                if ($a.Cred) { $cp.Credential = $a.Cred }
                $cs = New-CimSession @cp
                [void](Get-CimInstance -CimSession $cs -ClassName Win32_OperatingSystem -OperationTimeoutSec 20 -ErrorAction Stop)
                & $ok "CIM-Abfrage OK ($wer)"
                return $true
            }
            catch { & $feh ('CIM-Abfrage fehlgeschlagen: ' + (& $kurzFehler $_)); return $false }
            finally { if ($cs) { Remove-CimSession -CimSession $cs -ErrorAction SilentlyContinue } }
        }
        $ssh = {
            if (-not (& $tcp $ziel 22)) { & $feh 'SSH-Port 22 nicht erreichbar.'; return }
            & $ok 'SSH-Port 22 erreichbar'
            if (-not (Get-Module -ListAvailable -Name Posh-SSH)) { & $feh 'PowerShell-Modul Posh-SSH ist nicht installiert.'; return }
            if (-not $a.Cred) { & $feh 'Kein Konto mit Kennwort für den SSH-Login vorhanden.'; return }
            $res = & ([scriptblock]::Create($sshText)) $ziel $a.Cred
            if ($res.Erfolg) { & $ok "SSH-Anmeldung OK ($wer)" } else { & $feh ('SSH-Anmeldung fehlgeschlagen: ' + (([string]$res.Fehler -replace '\s+', ' ').Trim())) }
        }

        try {
            $netz = $true
            $cloud = ($a.Transport -eq 'Cloud')
            if ($a.KennwortFehlt) { & $feh "Für das Konto $($a.Konto) liegt in dieser Sitzung kein Kennwort vor (Anmeldung nicht prüfbar)." }
            elseif ($a.BrauchtKonto -and -not $a.Konto -and $a.Transport -in 'SSH', 'Web', 'SNMP', 'Cloud', 'vSphere') { & $feh 'Kein Konto in der Geräteliste, das Skript braucht Anmeldedaten.' }
            if (-not $cloud) {
                if ($ziel -notmatch '^\d+(\.\d+){3}$') {
                    try { $ips = @([System.Net.Dns]::GetHostAddresses($ziel)); & $ok ('Name aufgelöst: ' + $ips[0].IPAddressToString) }
                    catch { & $feh 'Name lässt sich nicht auflösen (DNS).'; $netz = $false }
                }
                if ($netz) {
                    if (Test-Connection -TargetName $ziel -Count 1 -TimeoutSeconds 2 -Quiet -ErrorAction SilentlyContinue) { & $ok 'Ping antwortet' }
                    else { & $hin 'Ping ohne Antwort (Ping kann gesperrt sein).' }
                }
            }
            if ($netz) {
                switch ($a.Transport) {
                    'WinRM' { & $winrm }
                    'Windows-CIM' { [void](& $cim) }
                    'Windows-Ereignislog' {
                        [void](& $cim)
                        if (& $tcp $ziel 135) {
                            & $ok 'RPC-Port 135 erreichbar'
                            try {
                                $gp = @{ ComputerName = $ziel; LogName = 'System'; MaxEvents = 1; ErrorAction = 'Stop' }
                                if ($a.Cred) { $gp.Credential = $a.Cred }
                                [void](Get-WinEvent @gp)
                                & $ok 'Ereignisprotokoll lesbar'
                            }
                            catch {
                                if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { & $ok 'Ereignisprotokoll lesbar' }
                                else { & $feh ('Ereignisprotokoll nicht lesbar: ' + (& $kurzFehler $_)) }
                            }
                        }
                        else { & $feh 'RPC-Port 135 nicht erreichbar (Ereignisprotokoll aus der Ferne, Firewall-Regeln für die Remote-Ereignisprotokollverwaltung).' }
                    }
                    'SSH' { & $ssh }
                    'WinRM-oder-SSH' {
                        if ((& $tcp $ziel 5985) -or (& $tcp $ziel 5986)) { & $winrm }
                        elseif (& $tcp $ziel 22) { & $ssh }
                        else { & $feh 'Weder WinRM (5985/5986) noch SSH (22) erreichbar.' }
                    }
                    'Web' {
                        $offen = @(foreach ($port in 443, 4444, 5001, 8443, 80) { if (& $tcp $ziel $port) { $port } })
                        if ($offen.Count) { & $ok ('Webdienst erreichbar (Port ' + ($offen -join ', ') + ')'); & $hin 'Die Anmeldung an der Schnittstelle (API/Web) wird erst im Lauf geprüft.' }
                        else { & $feh 'Kein Webport (443, 4444, 5001, 8443, 80) erreichbar.' }
                    }
                    'vSphere' {
                        if (& $tcp $ziel 443) { & $ok 'Port 443 erreichbar' } else { & $feh 'Port 443 nicht erreichbar.' }
                        if (-not (Get-Module -ListAvailable -Name 'VMware.VimAutomation.Core')) { & $feh 'VMware PowerCLI ist nicht installiert.' }
                        else { & $hin 'Die Anmeldung am vCenter/ESXi wird erst im Lauf geprüft.' }
                    }
                    'SNMP' {
                        if (-not (Get-Module -ListAvailable -Name SNMP)) { & $feh 'PowerShell-Modul SNMP ist nicht installiert.' }
                        else { & $hin 'SNMP (UDP 161) lässt sich von hier nicht vorab prüfen, die Abfrage wird erst im Lauf geprüft.' }
                    }
                    'IPMI' {
                        if (-not (Test-Path -LiteralPath 'C:\tools\ipmitool\ipmiutil.exe')) { & $feh 'ipmiutil fehlt (C:\tools\ipmitool\ipmiutil.exe).' }
                        else { & $hin 'IPMI wird erst im Lauf geprüft.' }
                    }
                    'Cloud' { }
                    default { & $hin 'Verbindungsart dieses Skripts ist unbekannt, es wurden nur Name und Ping geprüft.' }
                }
            }
            if ($cloud) {
                $h = (($ziel -replace '^https?://', '') -split '[/:]')[0]
                if ($h -match '^[\w-]+(\.[\w-]+)+$') { if (& $tcp $h 443) { & $ok "Internetzugriff auf $h (Port 443) erreichbar" } else { & $feh "$h (Port 443) nicht erreichbar." } }
                else { & $hin 'Cloud-Dienst: die Verbindung lässt sich von hier nicht vorab prüfen.' }
            }
        }
        catch { & $feh ('Prüfung abgebrochen: ' + (& $kurzFehler $_)) }
        [pscustomobject]@{ Ziel = $a.Ziel; Transport = $a.Transport; Skripte = @($a.Skripte); Konto = $a.Konto; Pruefungen = @($pr.ToArray()) }
    }
}

## Bericht der Prüfung als Text
function script:New-WolWtPruefBericht {
    param($Aufgaben, $Ergebnisse, $Probleme, [bool]$Zeitlimit)
    $nach = @{}
    foreach ($e in @($Ergebnisse)) { if ($e) { $nach[("$($e.Ziel)|$($e.Transport)|$($e.Konto)").ToLowerInvariant()] = $e } }
    $liste = foreach ($a in @($Aufgaben)) {
        $key = ("$($a.Ziel)|$($a.Transport)|$($a.Konto)").ToLowerInvariant()
        if ($nach.ContainsKey($key)) { $nach[$key] }
        else { [pscustomobject]@{ Ziel = $a.Ziel; Transport = $a.Transport; Skripte = @($a.Skripte); Konto = $a.Konto; Pruefungen = @([pscustomobject]@{ Status = 'Fehler'; Text = 'Keine Antwort innerhalb des Zeitlimits.' }) } }
    }
    $liste = @($liste)
    $schlecht = @($liste | Where-Object { @($_.Pruefungen | Where-Object { $_.Status -eq 'Fehler' }).Count -gt 0 })
    $gut = @($liste | Where-Object { @($_.Pruefungen | Where-Object { $_.Status -eq 'Fehler' }).Count -eq 0 })
    $arten = @{ 'WinRM' = 'WinRM'; 'Windows-CIM' = 'Windows (CIM)'; 'Windows-Ereignislog' = 'Windows (CIM, Ereignisprotokoll)'; 'SSH' = 'SSH'; 'Web' = 'Web/API'; 'vSphere' = 'vSphere'; 'SNMP' = 'SNMP'; 'IPMI' = 'IPMI'; 'Cloud' = 'Cloud'; 'WinRM-oder-SSH' = 'WinRM oder SSH'; 'Unbekannt' = 'unbekannt' }
    $kopf = { param($e) "$($e.Ziel) · $(if ($arten.ContainsKey([string]$e.Transport)) { $arten[[string]$e.Transport] } else { $e.Transport }) · Skripte: $(@($e.Skripte) -join ', ')" }
    $t = [System.Collections.Generic.List[string]]::new()
    $t.Add('Automatik-Prüfung vom ' + (Get-Date -Format 'dd.MM.yyyy HH:mm'))
    $geraete = @($liste | ForEach-Object { $_.Ziel } | Select-Object -Unique).Count
    $t.Add("Geräte: $geraete · Verbindungen: $($liste.Count) · bereit: $($gut.Count) · nicht bereit: $($schlecht.Count)")
    if ($Zeitlimit) { $t.Add('Achtung: Die Prüfung wurde nach dem Zeitlimit beendet, nicht beantwortete Verbindungen stehen unter "nicht bereit".') }
    if ($schlecht.Count -gt 0) {
        $t.Add('')
        $t.Add('NICHT BEREIT')
        foreach ($e in $schlecht) {
            $t.Add((& $kopf $e))
            foreach ($p in @($e.Pruefungen)) {
                $marke = switch ($p.Status) { 'OK' { '[OK]     ' } 'Fehler' { '[FEHLER] ' } default { '[Hinweis]' } }
                $t.Add("  $marke $($p.Text)")
            }
        }
    }
    if ($gut.Count -gt 0) {
        $t.Add('')
        $t.Add('BEREIT')
        foreach ($e in $gut) {
            $hinweise = @($e.Pruefungen | Where-Object { $_.Status -eq 'Hinweis' } | ForEach-Object { $_.Text })
            $t.Add("[OK] $(& $kopf $e)")
            foreach ($h in $hinweise) { $t.Add("       Hinweis: $h") }
        }
    }
    if (@($Probleme).Count -gt 0) {
        $t.Add('')
        $t.Add('SKRIPTE')
        foreach ($p in @($Probleme)) { $t.Add("  $p") }
    }
    $t.Add('')
    $t.Add('Die Prüfung zeigt, ob Verbindung und Anmeldung möglich sind. Ob die Abfragen selbst ein Ergebnis liefern, zeigt erst der Lauf.')
    return [pscustomobject]@{ Text = ($t -join "`r`n"); Gut = $gut.Count; Schlecht = $schlecht.Count; Geraete = $geraete }
}

## Bericht im Fenster zeigen und im Ausgabeordner speichern
function script:Show-WolWtPruefBericht {
    param([string]$Text)
    $datei = ''
    try {
        $datei = Join-Path (Get-WolWtAusgabeOrdner) ('Automatik-Pruefung_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
        $Text | Set-Content -LiteralPath $datei -Encoding utf8BOM -ErrorAction Stop
    }
    catch { $datei = '' }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Automatik-Prüfung" Width="900" Height="640" MinWidth="520" MinHeight="320" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBox x:Name="TxtBericht" IsReadOnly="True" FontFamily="Consolas" FontSize="12" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,0">
      <Button x:Name="BtnKopieren" Content="Kopieren" Padding="14,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnZu" Content="Schließen" Padding="14,6" Margin="0,0,16,0"/>
      <TextBlock x:Name="TxtDatei" VerticalAlignment="Center" Foreground="DimGray"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $f.FindName('TxtBericht').Text = $Text
    $f.FindName('TxtDatei').Text = $(if ($datei) { "Gespeichert: $datei" } else { '' })
    $f.FindName('BtnKopieren').Add_Click({ try { [System.Windows.Clipboard]::SetText($Text) } catch { } }.GetNewClosure())
    $f.FindName('BtnZu').Add_Click({ $f.Close() }.GetNewClosure())
    $f.Show()
}

## Prüfung beenden: Ergebnisse einsammeln, Bericht zeigen
function script:Complete-WolWtPruefung {
    param([bool]$Zeitlimit = $false)
    $pj = $script:WtPruefJob
    if (-not $pj) { return }
    if ($script:WtPruefTimer) { $script:WtPruefTimer.Stop() }
    $erg = @()
    try { $erg = @(Receive-Job -Job $pj.Job -ErrorAction SilentlyContinue) } catch { }
    try { Stop-Job -Job $pj.Job -ErrorAction SilentlyContinue; Remove-Job -Job $pj.Job -Force -ErrorAction SilentlyContinue } catch { }
    $script:WtPruefJob = $null
    $b = New-WolWtPruefBericht -Aufgaben $pj.Aufgaben -Ergebnisse $erg -Probleme $pj.Probleme -Zeitlimit $Zeitlimit
    Write-WolLog "WaToKi-Prüfung: $($b.Gut) bereit, $($b.Schlecht) nicht bereit ($($b.Geraete) Geräte)"
    if ($script:WtC.TxtStatus) { $script:WtC.TxtStatus.Text = "Prüfung fertig: $($b.Gut) bereit, $($b.Schlecht) nicht bereit." }
    Update-WolWtStatus
    Show-WolWtPruefBericht -Text $b.Text
}

## Timer: Fortschritt der Prüfung anzeigen, bei Ende oder Zeitlimit abschließen
function script:Watch-WolWtPruefung {
    $pj = $script:WtPruefJob
    if (-not $pj) { if ($script:WtPruefTimer) { $script:WtPruefTimer.Stop() }; return }
    $laeuft = ($pj.Job.State -eq 'Running' -or $pj.Job.State -eq 'NotStarted')
    if ($laeuft -and ((Get-Date) - $pj.Start).TotalMinutes -lt 10) {
        $fertig = 0
        try { $fertig = @(Receive-Job -Job $pj.Job -Keep -ErrorAction SilentlyContinue).Count } catch { }
        if ($script:WtC.TxtStatus) { $script:WtC.TxtStatus.Text = "Prüfung läuft: $fertig von $($pj.Aufgaben.Count) Verbindungen geprüft." }
        return
    }
    Complete-WolWtPruefung -Zeitlimit $laeuft
}

## Kontrollknopf "Automatik prüfen": geht alle Geräte des Plans durch und prüft, ob die Automatik laufen würde (nur lesend)
function script:Start-WolWtPruefung {
    if ($script:WtLauf -or $script:WtPruefJob -or (Test-WolWtLaeuft)) { Update-WolWtStatus; return }
    $c = $script:WtC
    $p = New-WolWtPlan
    if ($p.Plan.Count -eq 0) {
        $hinweis = "In der Spalte Wartungsreihenfolge steht bei keinem Gerät ein bekannter Skriptname (Beispiel: 05.1-VirtServer-HyperV)."
        if ($p.Unbekannt.Count -gt 0) { $hinweis += "`r`n`r`nUnbekannt: " + ($p.Unbekannt -join '; ') }
        Show-WolMeldung $hinweis 'Information'
        return
    }
    ### Fehlende Kennwörter jetzt abfragen (einmal pro Benutzername), sonst lässt sich die Anmeldung nicht testen
    $bereit = @($p.Plan | Where-Object { $_.Skript.HatAutomatik -and -not $_.Skript.Fehler -and $_.Skript.HatZiel })
    $kontoMenge = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    foreach ($item in @($bereit | Where-Object { $_.Skript.HatAnmeldung -or $_.Skript.HatAnmeldungJeZiel })) {
        foreach ($z in $item.Zeilen) { [void]$kontoMenge.Add($z) }
    }
    $kontoZeilen = @($kontoMenge)
    if ($kontoZeilen.Count -gt 0 -and -not (Resolve-WolKonten -Zeilen $kontoZeilen -Besitzer $script:WtFenster)) {
        $c.TxtStatus.Text = 'Prüfung nicht gestartet: Die Kennwortabfrage wurde abgebrochen.'
        return
    }
    $a = New-WolWtPruefAufgaben -Plan $p.Plan
    $probleme = @($a.Probleme)
    if ($p.Unbekannt.Count -gt 0) { $probleme += ('Unbekannte Skriptnamen (werden ignoriert): ' + ($p.Unbekannt -join '; ')) }
    if ($a.Aufgaben.Count -eq 0) {
        $b = New-WolWtPruefBericht -Aufgaben @() -Ergebnisse @() -Probleme $probleme -Zeitlimit $false
        Show-WolWtPruefBericht -Text $b.Text
        return
    }
    try { $job = Start-ThreadJob -ScriptBlock $script:WtPruefBlock -ArgumentList $a.Aufgaben, $script:SshPruefBlock.ToString() }
    catch { $c.TxtStatus.Text = "Die Prüfung konnte nicht gestartet werden: $($_.Exception.Message)"; return }
    $script:WtPruefJob = [pscustomobject]@{ Job = $job; Aufgaben = @($a.Aufgaben); Probleme = $probleme; Start = Get-Date }
    Write-WolLog "WaToKi-Prüfung gestartet: $($a.Aufgaben.Count) Verbindung(en)"
    if (-not $script:WtPruefTimer) {
        $script:WtPruefTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:WtPruefTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:WtPruefTimer.Add_Tick({ Watch-WolWtPruefung })
    }
    $script:WtPruefTimer.Start()
    $c.TxtStatus.Text = "Prüfung läuft: 0 von $($a.Aufgaben.Count) Verbindungen geprüft."
    Update-WolWtStatus
}

# Fenster
## Wird vom Menü Module > WaToKi aufgerufen: Fenster neben der Tabelle (bleibt offen, die Tabelle bleibt bedienbar)
function script:Show-WolModulWATOKI {
    if ($script:WtFenster) { [void]$script:WtFenster.Activate(); return }
    ### Start über start.ps1: Die Wartungsskripte liegen noch nicht im Ordner und werden jetzt mit Ladefenster vom Server geholt
    if ($script:ServerBasis -and $script:ServerSchluessel -and -not (Test-Path -LiteralPath (Get-WolWtSkriptOrdner))) {
        [void](Install-WolNachladen -Titel 'Modul WaToKi: Wartungsskripte werden geladen' -RepoOrdner $script:WtUnterordner -ZielOrdner (Get-WolWtSkriptOrdner))
    }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WaToKi" Width="860" Height="520" MinWidth="640" MinHeight="360" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Startet ein Wartungsskript in einem eigenen PowerShell-Fenster. Skripte mit dem Parameter -Ziel arbeiten mit den markierten Geräten der Tabelle." TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,8"/>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="340"/>
        <ColumnDefinition Width="12"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <ListBox x:Name="Liste" Grid.Column="0"/>
      <TextBox x:Name="TxtInfo" Grid.Column="2" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="6"/>
    </Grid>
    <WrapPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
      <Button x:Name="BtnStart" Content="&#9654; Starten" Padding="16,6" Margin="0,0,8,0" FontWeight="Bold"/>
      <Button x:Name="BtnAuto" Content="Automatik starten" Padding="10,6" Margin="0,0,8,0"
              ToolTip="Arbeitet alle Geräte mit Eintrag in der Spalte Wartungsreihenfolge nacheinander ab (je Skript ein unsichtbarer Prozess, Zeitlimit 10 Minuten) und schreibt Autowartung-Gesamtdatei.json und Detail.txt in einen neuen Ordner"/>
      <Button x:Name="BtnPruef" Content="Automatik prüfen" Padding="10,6" Margin="0,0,8,0"
              ToolTip="Prüft vorab, ob die Automatik laufen würde: Name, Ping, WinRM- und SSH-Anmeldung, Module. Es wird nichts verändert."/>
      <Button x:Name="BtnStop" Content="Automatik stoppen" Padding="10,6" Margin="0,0,8,0" IsEnabled="False"
              ToolTip="Beendet das laufende Skript, startet die übrigen nicht mehr und speichert die bisherigen Ergebnisse"/>
      <Button x:Name="BtnAusgabe" Content="Ausgabeordner öffnen" Padding="10,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnNeu" Content="Liste aktualisieren" Padding="10,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,6" Margin="0,0,16,0"/>
      <CheckBox x:Name="ChkSpalten" Content="Spalte Wartungsreihenfolge in der Tabelle anzeigen" VerticalAlignment="Center"
                ToolTip="Blendet die Spalte Wartungsreihenfolge in der Tabelle ein (Standard: aus). Beim Schließen des Fensters wird sie wieder ausgeblendet"/>
    </WrapPanel>
    <TextBlock x:Name="TxtStatus" Grid.Row="3" TextWrapping="Wrap" Foreground="DimGray" Margin="0,8,0,0"/>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $script:WtC = @{}
    foreach ($name in 'Liste', 'TxtInfo', 'BtnStart', 'BtnAuto', 'BtnPruef', 'BtnStop', 'BtnAusgabe', 'BtnNeu', 'BtnSchliessen', 'TxtStatus') { $script:WtC[$name] = $f.FindName($name) }
    Connect-WolModulSpaltenHaken -Fenster $f -Key 'WATOKI'
    $script:WtC.Liste.Add_SelectionChanged({ Show-WolWtBeschreibung })
    $script:WtC.Liste.Add_MouseDoubleClick({ Start-WolWtSkript })
    $script:WtC.BtnStart.Add_Click({ Start-WolWtSkript })
    $script:WtC.BtnAuto.Add_Click({ Start-WolWtAutomatik })
    $script:WtC.BtnPruef.Add_Click({ Start-WolWtPruefung })
    $script:WtC.BtnStop.Add_Click({ Stop-WolWtAutomatik })
    $script:WtC.BtnAusgabe.Add_Click({
        try { Invoke-Item -LiteralPath (Get-WolWtAusgabeOrdner) }
        catch { $script:WtC.TxtStatus.Text = "Der Ausgabeordner konnte nicht geöffnet werden: $($_.Exception.Message)" }
    })
    $script:WtC.BtnNeu.Add_Click({ Update-WolWtListe })
    $script:WtC.BtnSchliessen.Add_Click({ $script:WtFenster.Close() })
    $f.Add_Closed({ Set-WolModulOffen -Key 'WATOKI' -Offen $false; $script:WtFenster = $null; $script:WtC = @{} })
    $script:WtFenster = $f
    Set-WolModulOffen -Key 'WATOKI' -Offen $true
    Update-WolWtListe
    $f.Show()
}
