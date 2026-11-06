# NET-COCKPIT-Modul-SSH.ps1
<#
.SYNOPSIS
    Modul SSH für das NET-COCKPIT (Menü Module > SSH)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und öffnet für jedes markierte Gerät ein eigenes PowerShell-7-Fenster mit dem Windows-eigenen ssh.exe (OpenSSH-Client, kein Zusatztool).
    - Benutzer: aus der Spalte "Konto" des Geräts (so, wie er dort steht); ist sie leer, nimmt das Modul den Benutzer aus dem Feld "Benutzer für Geräte ohne Konto"
    - Port: einstellbar im Fenster (Vorgabe 22, gilt für alle markierten Geräte)
    - Das Kennwort speichert und übergibt das Modul nicht: ssh.exe fragt es im Fenster selbst ab (auch die Rückfrage zum Hostschlüssel)
    - Nach dem Ende der Verbindung bleibt das Fenster offen, bis Enter gedrückt wird, damit Fehlermeldungen lesbar bleiben
    Das Modul speichert nichts; Port und Benutzer bleiben nur bis zum Beenden des NET-COCKPIT im Fenster erhalten.
#>

# Einstellungen
## Vorgaben und Zustand des Moduls (bleibt bis zum Beenden des NET-COCKPIT erhalten)
$script:SshPortVorgabe = 22
$script:SshPort = '22'
$script:SshBenutzerOhneKonto = ''

# Hilfsfunktionen
## Text für die Einbettung in einfache Anführungszeichen
function script:ConvertTo-WolSshText {
    param([string]$Text)
    return $Text.Replace("'", "''")
}

## Pfad von ssh.exe (leer, wenn der OpenSSH-Client nicht installiert ist)
function script:Get-WolSshPfad {
    $befehl = Get-Command -Name 'ssh.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($befehl) { return [string]$befehl.Source }
    return ''
}

## Ein PowerShell-7-Fenster mit ssh.exe für ein Gerät starten (Benutzer und Ziel gehen als einzelne Argumente an ssh.exe)
function script:Start-WolSshFenster {
    param([string]$SshPfad, [string]$Ziel, [string]$Benutzer, [int]$Port)
    $titel = "SSH $Ziel"
    $befehl = "`$Host.UI.RawUI.WindowTitle = '" + (ConvertTo-WolSshText $titel) + "'; & '" + (ConvertTo-WolSshText $SshPfad) + "' -p $Port -l '" + (ConvertTo-WolSshText $Benutzer) + "' '" + (ConvertTo-WolSshText $Ziel) + "'"
    $gesamt = "try { $befehl; Write-Host ''; [void](Read-Host 'Verbindung beendet. Zum Schließen Enter drücken') } catch { Write-Host (`$_ | Out-String) -ForegroundColor Red; [void](Read-Host 'Fehler. Zum Schließen Enter drücken') }"
    $kodiert = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($gesamt))
    $pwsh = (Get-Process -Id $PID).Path
    [void](Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $kodiert -WindowStyle Normal -PassThru -ErrorAction Stop)
}

# Anzeige
## Wird vom Menü Module > SSH aufgerufen: kleines Fenster mit Port und Benutzer, "Verbinden" öffnet je markiertem Gerät ein Fenster
function script:Show-WolModulSSH {
    $markiert = @(Get-WolMarkierte)
    if ($markiert.Count -eq 0) {
        Show-WolMeldung 'Bitte zuerst ein oder mehrere Geräte in der Tabelle markieren.' 'Information'
        return
    }
    $sshPfad = Get-WolSshPfad
    if (-not $sshPfad) {
        Show-WolMeldung "Auf diesem Rechner ist kein ssh.exe vorhanden.`r`n`r`nDer OpenSSH-Client ist ein optionales Windows-Feature (Einstellungen > System > Optionale Features > OpenSSH-Client)." 'Warning'
        return
    }

    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SSH" Width="520" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Markierte Geräte" FontWeight="Bold" Margin="0,0,0,4"/>
    <TextBox x:Name="TxtGeraete" IsReadOnly="True" Height="120" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Consolas" Margin="0,0,0,10"/>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Text="Port" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtPort" Grid.Row="0" Grid.Column="1" Width="80" HorizontalAlignment="Left" Margin="0,0,0,6" ToolTip="Gilt für alle markierten Geräte. Vorgabe 22."/>
      <TextBlock Grid.Row="1" Text="Benutzer für Geräte ohne Konto" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtBenutzer" Grid.Row="1" Grid.Column="1" Margin="0,0,0,6" ToolTip="Wird nur für Geräte genutzt, bei denen die Spalte Konto leer ist."/>
    </Grid>
    <TextBlock Text="Das Kennwort fragt ssh.exe im jeweiligen Fenster selbst ab, das NET-COCKPIT speichert es nicht." Foreground="DimGray" TextWrapping="Wrap" Margin="0,4,0,0"/>
    <TextBlock x:Name="TxtFehler" Foreground="Firebrick" TextWrapping="Wrap" Margin="0,6,0,0"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnOk" Content="Verbinden" Padding="14,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BtnAbbruch" Content="Abbrechen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $d.Owner = $script:Fenster
    $c = @{}
    foreach ($n in 'TxtGeraete', 'TxtPort', 'TxtBenutzer', 'TxtFehler', 'BtnOk', 'BtnAbbruch') { $c[$n] = $d.FindName($n) }
    $c.TxtPort.Text = $script:SshPort
    $c.TxtBenutzer.Text = $script:SshBenutzerOhneKonto
    $c.TxtGeraete.Text = (($markiert | ForEach-Object {
        $konto = [string]$_.Konto
        '{0}   Benutzer: {1}' -f (Get-WolZielName -Zeile $_), $(if ($konto) { $konto } else { '(Spalte Konto leer)' })
    }) -join "`r`n")
    $c.BtnAbbruch.Add_Click({ $d.Close() })
    $c.BtnOk.Add_Click({
        $c.TxtFehler.Text = ''
        $port = 0
        if (-not [int]::TryParse($c.TxtPort.Text.Trim(), [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
            $c.TxtFehler.Text = 'Der Port ist ungültig. Erwartet wird eine Zahl von 1 bis 65535.'
            return
        }
        $benutzerStandard = $c.TxtBenutzer.Text.Trim()
        $ohne = @($markiert | Where-Object { -not ([string]$_.Konto).Trim() })
        if ($ohne.Count -gt 0 -and -not $benutzerStandard) {
            $namen = @($ohne | ForEach-Object { Get-WolZielName -Zeile $_ })
            $c.TxtFehler.Text = "Bei diesen Geräten ist die Spalte Konto leer: $($namen -join ', '). Bitte einen Benutzer für Geräte ohne Konto eintragen."
            return
        }
        $script:SshPort = [string]$port
        $script:SshBenutzerOhneKonto = $benutzerStandard
        foreach ($z in $markiert) {
            $ziel = Get-WolZielName -Zeile $z
            $benutzer = ([string]$z.Konto).Trim()
            if (-not $benutzer) { $benutzer = $benutzerStandard }
            try {
                Start-WolSshFenster -SshPfad $sshPfad -Ziel $ziel -Benutzer $benutzer -Port $port
                Write-WolLog "SSH: Fenster für $ziel gestartet (Benutzer $benutzer, Port $port)"
            }
            catch { Write-WolLog "SSH: Fenster für $ziel konnte nicht gestartet werden: $($_.Exception.Message)" }
        }
        $d.Close()
    })
    [void]$d.ShowDialog()
}
