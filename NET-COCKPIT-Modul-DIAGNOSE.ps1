# NET-COCKPIT-Modul-DIAGNOSE.ps1
<#
.SYNOPSIS
    Modul Diagnose für das NET-COCKPIT (Menü Module > Diagnose)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und wirkt auf ein markiertes, grünes Gerät der Tabelle.
    - Ereignislog: Liste mit Auswahl von Log (System, Application, Security, Setup), Stufe und Zeitraum, Filterfeld und Detailanzeige der Meldung
    - Dienste: Liste mit Filterfeld, Dienste starten, stoppen und neu starten
    - Prozesse: Liste mit CPU, RAM und Benutzer als Task-Manager-Ersatz, Prozess beenden
    Alles läuft per WinRM; Verbindung, Konten, Warteschlange und Fehlerbehandlung kommen aus dem NET-COCKPIT.
    Pro Gerät und Art öffnet sich ein eigenes Fenster, das neben der Tabelle offen bleiben kann.
#>

# Einstellungen
## Zustand: offene Anzeigefenster (Schlüssel Art|IP)
$script:DiagViewer = [System.Collections.Generic.Dictionary[string, object]]::new()
$script:DiagFenster = $null

# Skripte, die auf dem Zielgerät laufen (Windows PowerShell 5.1) und einen JSON-Text zurückgeben
## Ereignislog: Log, Stufen (leer = alle), Stunden, Höchstzahl
$script:DiagSkriptEreignisse = @'
param($Log, $Stufen, $Stunden, $Max)
$ErrorActionPreference = 'Stop'
$filter = @{ LogName = [string]$Log; StartTime = (Get-Date).AddHours(-[double]$Stunden) }
if ($Stufen -and @($Stufen).Count -gt 0) { $filter.Level = [int[]]@($Stufen) }
try { $ereignisse = @(Get-WinEvent -FilterHashtable $filter -MaxEvents ([int]$Max)) }
catch {
    if ($_.FullyQualifiedErrorId -like '*NoMatchingEventsFound*') { $ereignisse = @() } else { throw }
}
$liste = foreach ($e in $ereignisse) {
    $meldung = [string]$e.Message
    if ($meldung.Length -gt 1500) { $meldung = $meldung.Substring(0, 1500) + ' ...' }
    [pscustomobject]@{
        Zeit    = $e.TimeCreated.ToString('yyyy-MM-ddTHH:mm:ss')
        Stufe   = [string]$e.LevelDisplayName
        Quelle  = [string]$e.ProviderName
        Id      = [int]$e.Id
        Meldung = $meldung
    }
}
ConvertTo-Json -InputObject @($liste) -Compress
'@

## Dienste
$script:DiagSkriptDienste = @'
$ErrorActionPreference = 'Stop'
$liste = foreach ($s in Get-CimInstance -ClassName Win32_Service) {
    [pscustomobject]@{ Name = [string]$s.Name; Anzeige = [string]$s.DisplayName; Status = [string]$s.State; Start = [string]$s.StartMode; Konto = [string]$s.StartName }
}
ConvertTo-Json -InputObject @($liste) -Compress
'@

## Dienst starten, stoppen oder neu starten (Name, Aktion)
$script:DiagSkriptDienstAktion = @'
param($Name, $Aktion)
$ErrorActionPreference = 'Stop'
switch ($Aktion) {
    'Start'    { Start-Service -Name $Name }
    'Stopp'    { Stop-Service -Name $Name -Force }
    'Neustart' { Restart-Service -Name $Name -Force }
    default    { throw "Unbekannte Aktion: $Aktion" }
}
[string](Get-Service -Name $Name).Status
'@

## Prozesse: CPU in Prozent über eine Messung von einer Sekunde
$script:DiagSkriptProzesse = @'
$ErrorActionPreference = 'Stop'
$kerne = [Environment]::ProcessorCount
$vorher = @{}
foreach ($p in Get-Process) { try { $vorher[$p.Id] = $p.TotalProcessorTime.TotalSeconds } catch { } }
Start-Sleep -Milliseconds 1000
$benutzer = @{}
try { foreach ($p in Get-Process -IncludeUserName) { $benutzer[$p.Id] = [string]$p.UserName } } catch { }
$liste = foreach ($p in Get-Process) {
    $cpu = 0.0
    try { if ($vorher.ContainsKey($p.Id)) { $cpu = [math]::Round((($p.TotalProcessorTime.TotalSeconds - $vorher[$p.Id]) / $kerne) * 100, 1) } } catch { }
    [pscustomobject]@{
        Name     = [string]$p.ProcessName
        Id       = [int]$p.Id
        Cpu      = [double]$cpu
        Ram      = [math]::Round($p.WorkingSet64 / 1MB, 1)
        Threads  = [int]$p.Threads.Count
        Benutzer = [string]$benutzer[$p.Id]
    }
}
ConvertTo-Json -InputObject @($liste) -Compress
'@

## Prozess beenden (Id, Name); der Name wird geprüft, damit keine wiederverwendete Id getroffen wird
$script:DiagSkriptProzessAktion = @'
param($ProzessId, $Name)
$ErrorActionPreference = 'Stop'
$p = Get-Process -Id ([int]$ProzessId)
if ($p.ProcessName -ne [string]$Name) { throw 'Der Prozess hat sich geändert, bitte die Liste aktualisieren.' }
Stop-Process -Id ([int]$ProzessId) -Force
'beendet'
'@

# Verbindung
## Läuft als Thread-Job: führt eines der Skripte auf dem Zielgerät aus und gibt den Text zurück
$script:DiagBlock = {
    param([string]$Ziel, $Anmeldedaten, [string]$Skript, [object[]]$Parameter)
    $ProgressPreference = 'SilentlyContinue'
    try {
        $p = @{ ComputerName = $Ziel; ErrorAction = 'Stop' }
        if ($Anmeldedaten) { $p.Credential = $Anmeldedaten }
        $sb = [scriptblock]::Create($Skript)
        $roh = @(Invoke-Command @p -ScriptBlock $sb -ArgumentList $Parameter)
        $text = [string]($roh | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        [pscustomobject]@{ Erfolg = $true; Text = $text; Fehler = '' }
    }
    catch {
        [pscustomobject]@{ Erfolg = $false; Text = ''; Fehler = $_.Exception.Message }
    }
}

# Hilfsfunktionen
## Zustand des Anzeigefensters (hängt am Tag des Fensters)
function script:Get-WolDiagS {
    param($Quelle)
    $w = [System.Windows.Window]::GetWindow($Quelle)
    if ($w) { return $w.Tag }
    return $null
}

## Name des Geräts für Texte (Hostname, sonst IP)
function script:Get-WolDiagName {
    param($Zeile)
    if ($Zeile.Hostname) { return ([string]$Zeile.Hostname).Split('.')[0] }
    return [string]$Zeile.IP
}

## Filtertext für die Tabelle (DataView.RowFilter): Teiltext in irgendeiner Spalte, Sonderzeichen werden maskiert
function script:New-WolDiagFilter {
    param([string]$Text, [string[]]$Spalten)
    if (-not $Text) { return '' }
    $e = $Text -replace '([\[\]%*])', '[$1]'
    $e = $e.Replace("'", "''")
    return (@($Spalten | ForEach-Object { "Convert([$_], 'System.String') LIKE '%$e%'" }) -join ' OR ')
}

## Spalten der Tabelle je Art anlegen
function script:Initialize-WolDiagSpalten {
    param($S)
    $def = switch ($S.Art) {
        'Ereignisse' { @(@('Zeit', 'Zeit', 150, 'dd.MM.yyyy HH:mm:ss'), @('Stufe', 'Stufe', 100, ''), @('Quelle', 'Quelle', 220, ''), @('Id', 'ID', 60, ''), @('Meldung', 'Meldung', 0, '')) }
        'Dienste'    { @(@('Name', 'Name', 200, ''), @('Anzeige', 'Anzeigename', 320, ''), @('Status', 'Status', 90, ''), @('Start', 'Starttyp', 110, ''), @('Konto', 'Konto', 0, '')) }
        'Prozesse'   { @(@('Name', 'Name', 240, ''), @('Id', 'PID', 70, ''), @('Cpu', 'CPU %', 70, 'N1'), @('Ram', 'RAM (MB)', 90, 'N1'), @('Threads', 'Threads', 70, ''), @('Benutzer', 'Benutzer', 0, '')) }
    }
    foreach ($d in $def) {
        $spalte = [System.Windows.Controls.DataGridTextColumn]::new()
        $spalte.Header = $d[1]
        $bindung = [System.Windows.Data.Binding]::new([string]$d[0])
        $bindung.Mode = [System.Windows.Data.BindingMode]::OneWay
        if ($d[3]) { $bindung.StringFormat = [string]$d[3] }
        $spalte.Binding = $bindung
        $spalte.Width = $(if ($d[2] -gt 0) { [System.Windows.Controls.DataGridLength]::new([double]$d[2]) } else { [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star) })
        [void]$S.Tabelle.Columns.Add($spalte)
    }
}

## Antwort des Geräts (JSON) in die Tabelle übernehmen
function script:Set-WolDiagDaten {
    param($S, [string]$Json)
    $zeilen = @()
    if ($Json) { $zeilen = @($Json | ConvertFrom-Json) }
    $t = [System.Data.DataTable]::new()
    switch ($S.Art) {
        'Ereignisse' {
            [void]$t.Columns.Add('Zeit', [datetime]); [void]$t.Columns.Add('Stufe', [string]); [void]$t.Columns.Add('Quelle', [string])
            [void]$t.Columns.Add('Id', [int]); [void]$t.Columns.Add('Meldung', [string]); [void]$t.Columns.Add('Voll', [string])
            foreach ($z in $zeilen) {
                $r = $t.NewRow()
                $r['Zeit'] = [datetime]::Parse([string]$z.Zeit, [cultureinfo]::InvariantCulture)
                $r['Stufe'] = [string]$z.Stufe; $r['Quelle'] = [string]$z.Quelle; $r['Id'] = [int]$z.Id
                $voll = [string]$z.Meldung
                $erste = ($voll -split "\r?\n")[0]
                if ($erste.Length -gt 250) { $erste = $erste.Substring(0, 247) + '...' }
                $r['Meldung'] = $erste; $r['Voll'] = $voll
                $t.Rows.Add($r)
            }
            $S.Filterspalten = @('Zeit', 'Stufe', 'Quelle', 'Id', 'Meldung', 'Voll')
            $sortierung = 'Zeit DESC'
        }
        'Dienste' {
            $status = @{ 'Running' = 'Läuft'; 'Stopped' = 'Beendet'; 'Paused' = 'Angehalten'; 'Start Pending' = 'Startet'; 'Stop Pending' = 'Stoppt' }
            $start = @{ 'Auto' = 'Automatisch'; 'Manual' = 'Manuell'; 'Disabled' = 'Deaktiviert'; 'Boot' = 'System'; 'System' = 'System' }
            foreach ($n in 'Name', 'Anzeige', 'Status', 'Start', 'Konto') { [void]$t.Columns.Add($n, [string]) }
            foreach ($z in $zeilen) {
                $r = $t.NewRow()
                $r['Name'] = [string]$z.Name; $r['Anzeige'] = [string]$z.Anzeige; $r['Konto'] = [string]$z.Konto
                $r['Status'] = $(if ($status.ContainsKey([string]$z.Status)) { $status[[string]$z.Status] } else { [string]$z.Status })
                $r['Start'] = $(if ($start.ContainsKey([string]$z.Start)) { $start[[string]$z.Start] } else { [string]$z.Start })
                $t.Rows.Add($r)
            }
            $S.Filterspalten = @('Name', 'Anzeige', 'Status', 'Start', 'Konto')
            $sortierung = 'Anzeige ASC'
        }
        'Prozesse' {
            [void]$t.Columns.Add('Name', [string]); [void]$t.Columns.Add('Id', [int]); [void]$t.Columns.Add('Cpu', [double])
            [void]$t.Columns.Add('Ram', [double]); [void]$t.Columns.Add('Threads', [int]); [void]$t.Columns.Add('Benutzer', [string])
            foreach ($z in $zeilen) {
                $r = $t.NewRow()
                $r['Name'] = [string]$z.Name; $r['Id'] = [int]$z.Id; $r['Cpu'] = [double]$z.Cpu
                $r['Ram'] = [double]$z.Ram; $r['Threads'] = [int]$z.Threads; $r['Benutzer'] = [string]$z.Benutzer
                $t.Rows.Add($r)
            }
            $S.Filterspalten = @('Name', 'Id', 'Benutzer')
            $sortierung = 'Cpu DESC'
        }
    }
    $S.Ansicht = $t.DefaultView
    $S.Ansicht.Sort = $sortierung
    $S.Ansicht.RowFilter = New-WolDiagFilter -Text $S.TxtFilter.Text -Spalten $S.Filterspalten
    $S.Tabelle.ItemsSource = $S.Ansicht
    $S.TxtStatus.Text = '{0} Einträge (Stand {1:HH:mm:ss}), angezeigt: {2}' -f $zeilen.Count, (Get-Date), $S.Ansicht.Count
}

# Abfragen
## Auswertung eines Auftrags (läuft im Poll-Timer): Liste laden oder Aktion abgeschlossen
$script:DiagFertig = {
    param($a)
    $S = $a.Daten.S
    $S.Laeuft = $false
    $name = Get-WolDiagName -Zeile $S.Zeile
    try {
        $erg = @(Receive-Job -Job $a.Job -ErrorAction Stop) | Select-Object -Last 1
        if (-not $erg) { throw 'keine Rückmeldung vom Zielgerät' }
        if (-not $erg.Erfolg) { throw $erg.Fehler }
        if ($S.Geschlossen) { return }
        if ($a.Daten.Modus -eq 'Laden') { Set-WolDiagDaten -S $S -Json ([string]$erg.Text) }
        else {
            Write-WolLog "Diagnose $name : $($a.Daten.Text) - $([string]$erg.Text)"
            Start-WolDiagLaden -S $S
            $S.TxtStatus.Text = "$($a.Daten.Text): fertig, Liste wird aktualisiert..."
        }
    }
    catch {
        $kurz = Register-WolVerbindungsfehler -Zeile $S.Zeile -Text $_.Exception.Message
        if (-not $S.Geschlossen) { $S.TxtStatus.Text = "Fehler: $kurz" }
        Write-WolLog "Diagnose $name ($($S.Art)) fehlgeschlagen: $kurz"
        Write-WolLog "Diagnose-Fehlertext ${name}: $($_.Exception.Message)" -NurDatei
    }
}

## Auftrag für ein Gerät in die Warteschlange stellen
function script:Add-WolDiagAuftrag {
    param($S, [string]$Skript, [object[]]$Parameter, [string]$Modus, [string]$Text = '')
    try { $konto = Get-WolAnmeldung -Zeile $S.Zeile }
    catch { $S.TxtStatus.Text = $_.Exception.Message; return $false }
    $S.Laeuft = $true
    Add-WolAuftrag -Zeile $null -Block $script:DiagBlock -Argumente @((Get-WolZielName -Zeile $S.Zeile), $konto, $Skript, $Parameter) -Fertig $script:DiagFertig -Gruppe 'DIAG' -Daten @{ S = $S; Modus = $Modus; Text = $Text }
    return $true
}

## Liste neu laden (Einstellungen der Auswahlfelder werden gelesen)
function script:Start-WolDiagLaden {
    param($S)
    if ($S.Laeuft) { return }
    switch ($S.Art) {
        'Ereignisse' {
            $stufen = switch ($S.CmbStufe.SelectedIndex) { 0 { [int[]]@(1, 2) } 1 { [int[]]@(1, 2, 3) } default { [int[]]@() } }
            $stunden = switch ($S.CmbZeit.SelectedIndex) { 0 { 1 } 1 { 24 } 2 { 168 } default { 720 } }
            $skript = $script:DiagSkriptEreignisse
            $param = @([string]$S.CmbLog.Text, $stufen, $stunden, 500)
        }
        'Dienste' { $skript = $script:DiagSkriptDienste; $param = @() }
        'Prozesse' { $skript = $script:DiagSkriptProzesse; $param = @() }
    }
    if (Add-WolDiagAuftrag -S $S -Skript $skript -Parameter $param -Modus 'Laden') { $S.TxtStatus.Text = 'Wird vom Gerät abgefragt...' }
}

## Dienst starten, stoppen oder neu starten (markierte Zeile, mit Rückfrage)
function script:Start-WolDiagDienst {
    param($S, [string]$Aktion)
    $zeile = $S.Tabelle.SelectedItem
    if (-not $zeile) { $S.TxtStatus.Text = 'Bitte zuerst einen Dienst in der Liste auswählen.'; return }
    $dienst = [string]$zeile['Name']
    $anzeige = [string]$zeile['Anzeige']
    $wort = switch ($Aktion) { 'Start' { 'starten' } 'Stopp' { 'stoppen' } default { 'neu starten' } }
    $name = Get-WolDiagName -Zeile $S.Zeile
    if ([System.Windows.MessageBox]::Show("Dienst $wort?`r`n`r`n$anzeige ($dienst)`r`nGerät: $name", 'NET-COCKPIT', 'YesNo', 'Question', 'No') -ne 'Yes') { return }
    if ($S.Laeuft) { $S.TxtStatus.Text = 'Es läuft noch eine Abfrage, bitte kurz warten.'; return }
    if (Add-WolDiagAuftrag -S $S -Skript $script:DiagSkriptDienstAktion -Parameter @($dienst, $Aktion) -Modus 'Aktion' -Text "$anzeige $wort") { $S.TxtStatus.Text = "$anzeige wird $wort..." }
}

## Prozess beenden (markierte Zeile, mit Rückfrage)
function script:Start-WolDiagProzessBeenden {
    param($S)
    $zeile = $S.Tabelle.SelectedItem
    if (-not $zeile) { $S.TxtStatus.Text = 'Bitte zuerst einen Prozess in der Liste auswählen.'; return }
    $prozess = [string]$zeile['Name']
    $id = [int]$zeile['Id']
    $name = Get-WolDiagName -Zeile $S.Zeile
    if ([System.Windows.MessageBox]::Show("Prozess beenden?`r`n`r`n$prozess (PID $id)`r`nGerät: $name`r`n`r`nNicht gespeicherte Daten des Prozesses gehen verloren.", 'NET-COCKPIT', 'YesNo', 'Warning', 'No') -ne 'Yes') { return }
    if ($S.Laeuft) { $S.TxtStatus.Text = 'Es läuft noch eine Abfrage, bitte kurz warten.'; return }
    if (Add-WolDiagAuftrag -S $S -Skript $script:DiagSkriptProzessAktion -Parameter @($id, $prozess) -Modus 'Aktion' -Text "$prozess (PID $id) beenden") { $S.TxtStatus.Text = "$prozess wird beendet..." }
}

# Fenster
## Anzeigefenster einer Art für ein Gerät (ein Fenster je Art und Gerät)
function script:Show-WolDiagFenster {
    param([string]$Art, $Zeile)
    $schluessel = "$Art|$($Zeile.IP)"
    if ($script:DiagViewer.ContainsKey($schluessel)) { [void]$script:DiagViewer[$schluessel].Fenster.Activate(); return }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="1150" Height="660" WindowStartupLocation="CenterOwner">
  <Grid Margin="8">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <WrapPanel Grid.Row="0" Margin="0,0,0,6">
      <TextBlock Text="Filter:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="TxtFilter" Width="220" Margin="0,0,14,0" ToolTip="Teiltext in einer beliebigen Spalte (Groß-/Kleinschreibung egal)"/>
      <TextBlock x:Name="LblLog" Text="Log:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <ComboBox x:Name="CmbLog" Width="110" Margin="0,0,14,0" SelectedIndex="0">
        <ComboBoxItem Content="System"/><ComboBoxItem Content="Application"/><ComboBoxItem Content="Security"/><ComboBoxItem Content="Setup"/>
      </ComboBox>
      <TextBlock x:Name="LblStufe" Text="Stufe:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <ComboBox x:Name="CmbStufe" Width="160" Margin="0,0,14,0" SelectedIndex="1">
        <ComboBoxItem Content="Kritisch und Fehler"/><ComboBoxItem Content="Fehler und Warnungen"/><ComboBoxItem Content="Alle"/>
      </ComboBox>
      <TextBlock x:Name="LblZeit" Text="Zeitraum:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <ComboBox x:Name="CmbZeit" Width="150" Margin="0,0,14,0" SelectedIndex="1">
        <ComboBoxItem Content="Letzte Stunde"/><ComboBoxItem Content="Letzte 24 Stunden"/><ComboBoxItem Content="Letzte 7 Tage"/><ComboBoxItem Content="Letzte 30 Tage"/>
      </ComboBox>
      <Button x:Name="BtnAktualisieren" Content="Aktualisieren" Padding="12,3" Margin="0,0,14,0"/>
      <Button x:Name="BtnStart" Content="Starten" Padding="12,3" Margin="0,0,6,0"/>
      <Button x:Name="BtnStopp" Content="Stoppen" Padding="12,3" Margin="0,0,6,0"/>
      <Button x:Name="BtnNeustart" Content="Neu starten" Padding="12,3" Margin="0,0,6,0"/>
      <Button x:Name="BtnBeenden" Content="Task beenden" Padding="12,3" Margin="0,0,6,0"/>
    </WrapPanel>
    <DataGrid x:Name="Tabelle" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" SelectionMode="Single"/>
    <TextBox x:Name="TxtDetail" Grid.Row="2" Height="130" Margin="0,6,0,0" IsReadOnly="True" FontFamily="Consolas" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
    <TextBlock x:Name="TxtStatus" Grid.Row="3" Margin="0,6,0,0" Foreground="DimGray"/>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $S = @{ Art = $Art; Zeile = $Zeile; Schluessel = $schluessel; Fenster = $f; Laeuft = $false; Geschlossen = $false; Ansicht = $null; Filterspalten = @() }
    foreach ($n in 'TxtFilter', 'CmbLog', 'LblLog', 'CmbStufe', 'LblStufe', 'CmbZeit', 'LblZeit', 'BtnAktualisieren', 'BtnStart', 'BtnStopp', 'BtnNeustart', 'BtnBeenden', 'Tabelle', 'TxtDetail', 'TxtStatus') { $S[$n] = $f.FindName($n) }
    $f.Tag = $S
    $name = Get-WolDiagName -Zeile $Zeile
    $titel = switch ($Art) { 'Ereignisse' { 'Ereignislog' } 'Dienste' { 'Dienste' } default { 'Prozesse' } }
    $f.Title = "$titel auf $name"

    ### Nur die Bedienelemente der jeweiligen Art zeigen
    $aus = [System.Windows.Visibility]::Collapsed
    if ($Art -ne 'Ereignisse') { foreach ($n in 'CmbLog', 'LblLog', 'CmbStufe', 'LblStufe', 'CmbZeit', 'LblZeit', 'TxtDetail') { $S[$n].Visibility = $aus } }
    if ($Art -ne 'Dienste') { foreach ($n in 'BtnStart', 'BtnStopp', 'BtnNeustart') { $S[$n].Visibility = $aus } }
    if ($Art -ne 'Prozesse') { $S.BtnBeenden.Visibility = $aus }
    Initialize-WolDiagSpalten -S $S

    $S.BtnAktualisieren.Add_Click({ $ds = Get-WolDiagS -Quelle $this; if ($ds) { Start-WolDiagLaden -S $ds } })
    $S.BtnStart.Add_Click({ $ds = Get-WolDiagS -Quelle $this; if ($ds) { Start-WolDiagDienst -S $ds -Aktion 'Start' } })
    $S.BtnStopp.Add_Click({ $ds = Get-WolDiagS -Quelle $this; if ($ds) { Start-WolDiagDienst -S $ds -Aktion 'Stopp' } })
    $S.BtnNeustart.Add_Click({ $ds = Get-WolDiagS -Quelle $this; if ($ds) { Start-WolDiagDienst -S $ds -Aktion 'Neustart' } })
    $S.BtnBeenden.Add_Click({ $ds = Get-WolDiagS -Quelle $this; if ($ds) { Start-WolDiagProzessBeenden -S $ds } })
    $S.TxtFilter.Add_TextChanged({
        $ds = Get-WolDiagS -Quelle $this
        if ($ds -and $ds.Ansicht) {
            $ds.Ansicht.RowFilter = New-WolDiagFilter -Text $ds.TxtFilter.Text -Spalten $ds.Filterspalten
            $ds.TxtStatus.Text = 'angezeigt: {0}' -f $ds.Ansicht.Count
        }
    })
    $S.Tabelle.Add_SelectionChanged({
        $ds = Get-WolDiagS -Quelle $this
        if ($ds -and $ds.Art -eq 'Ereignisse') {
            $zeile = $ds.Tabelle.SelectedItem
            $ds.TxtDetail.Text = $(if ($zeile) { [string]$zeile['Voll'] } else { '' })
        }
    })
    $f.Add_Closed({
        $ds = $this.Tag
        $ds.Geschlossen = $true
        [void]$script:DiagViewer.Remove([string]$ds.Schluessel)
    })
    $script:DiagViewer[$schluessel] = $S
    $f.Show()
    Start-WolDiagLaden -S $S
}

## Gerät für ein Anzeigefenster bestimmen: genau ein markiertes, grünes Gerät
function script:Open-WolDiagFenster {
    param([string]$Art)
    $ziele = @(Get-WolMarkierte)
    if ($ziele.Count -ne 1) { Show-WolMeldung 'Bitte genau ein Gerät markieren.'; return }
    $z = $ziele[0]
    if ($z.Ampel -ne 'Gruen') { Show-WolMeldung 'Das Gerät ist nicht grün (WinRM nicht erreichbar).'; return }
    if (-not (Resolve-WolKonten -Zeilen @($z))) { return }
    Show-WolDiagFenster -Art $Art -Zeile $z
}

## Wird vom Menü Module > Diagnose aufgerufen: kleines Fenster neben der Tabelle (bleibt offen, die Tabelle bleibt bedienbar)
function script:Show-WolModulDIAGNOSE {
    if ($script:DiagFenster) { [void]$script:DiagFenster.Activate(); return }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Diagnose" Width="400" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Wirkt auf das markierte Gerät der Tabelle (genau eins, grün, WinRM erreichbar). Jede Anzeige öffnet ein eigenes Fenster." TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,10"/>
    <Button x:Name="BtnEreignisse" Content="Ereignislog..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Zeigt Einträge aus System, Application, Security oder Setup mit Filter nach Stufe und Zeitraum"/>
    <Button x:Name="BtnDienste" Content="Dienste..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Zeigt alle Dienste; Starten, Stoppen und Neu starten"/>
    <Button x:Name="BtnProzesse" Content="Prozesse..." Padding="10,5" Margin="0,0,0,6"
            ToolTip="Zeigt alle Prozesse mit CPU, RAM und Benutzer; Task beenden"/>
    <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,5" Margin="0,8,0,0"/>
  </StackPanel>
</Window>
'@
    $f.Owner = $script:Fenster
    $f.FindName('BtnEreignisse').Add_Click({ Open-WolDiagFenster -Art 'Ereignisse' })
    $f.FindName('BtnDienste').Add_Click({ Open-WolDiagFenster -Art 'Dienste' })
    $f.FindName('BtnProzesse').Add_Click({ Open-WolDiagFenster -Art 'Prozesse' })
    $f.FindName('BtnSchliessen').Add_Click({ $script:DiagFenster.Close() })
    $f.Add_Closed({ $script:DiagFenster = $null })
    $script:DiagFenster = $f
    $f.Show()
}
