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

## Zustand: Fenster, Steuerelemente und das laufende Skript (bleibt auch bei geschlossenem Fenster erhalten)
$script:WtFenster = $null
$script:WtC = @{}
$script:WtProzess = $null
$script:WtProzessName = ''
$script:WtStart = $null
$script:WtTimer = $null
$script:WtAnmeldeDatei = ''

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
    $info = [pscustomobject]@{ Beschreibung = ''; HatZiel = $false; ZielMehrere = $false; HatAusgabe = $false; HatAnmeldung = $false; HatAnmeldungJeZiel = $false; Fehler = '' }
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
    if ($s.Fehler) { $zeilen.Add(''); $zeilen.Add($s.Fehler) }
    $c.TxtInfo.Text = ($zeilen -join "`r`n")
}

## Statuszeile und Starten-Knopf (zeigt auch, wenn ein Skript noch läuft)
function script:Update-WolWtStatus {
    $c = $script:WtC
    if (-not $c.TxtStatus) { return }
    if (Test-WolWtLaeuft) {
        $c.BtnStart.IsEnabled = $false
        $c.TxtStatus.Text = 'Läuft: {0} (seit {1:HH:mm:ss}). Es läuft immer nur ein Skript gleichzeitig.' -f $script:WtProzessName, $script:WtStart
    }
    else {
        $c.BtnStart.IsEnabled = $true
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
    if (Test-WolWtLaeuft) { Update-WolWtStatus; return }
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
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
      <Button x:Name="BtnStart" Content="&#9654; Starten" Padding="16,6" Margin="0,0,8,0" FontWeight="Bold"/>
      <Button x:Name="BtnAusgabe" Content="Ausgabeordner öffnen" Padding="10,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnNeu" Content="Liste aktualisieren" Padding="10,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,6" Margin="0,0,16,0"/>
      <CheckBox x:Name="ChkSpalten" Content="Spalte Wartungsreihenfolge in der Tabelle anzeigen" VerticalAlignment="Center"
                ToolTip="Blendet die Spalte Wartungsreihenfolge in der Tabelle ein (Standard: aus). Beim Schließen des Fensters wird sie wieder ausgeblendet"/>
    </StackPanel>
    <TextBlock x:Name="TxtStatus" Grid.Row="3" TextWrapping="Wrap" Foreground="DimGray" Margin="0,8,0,0"/>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $script:WtC = @{}
    foreach ($name in 'Liste', 'TxtInfo', 'BtnStart', 'BtnAusgabe', 'BtnNeu', 'BtnSchliessen', 'TxtStatus') { $script:WtC[$name] = $f.FindName($name) }
    Connect-WolModulSpaltenHaken -Fenster $f -Key 'WATOKI'
    $script:WtC.Liste.Add_SelectionChanged({ Show-WolWtBeschreibung })
    $script:WtC.Liste.Add_MouseDoubleClick({ Start-WolWtSkript })
    $script:WtC.BtnStart.Add_Click({ Start-WolWtSkript })
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
