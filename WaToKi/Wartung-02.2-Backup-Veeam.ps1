#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string]$Ziel,
    [string]$Ausgabeordner,
    [System.Management.Automation.PSCredential]$Anmeldedaten
)

Clear-Host
Write-Host ""
Write-Host "=== Wartung-02.2-BackupVeeam ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Exportiert die Veeam-Backup-Sitzungen der letzten 30 Tage als Textdatei (Veeam B&R v12+, PowerShell-Modul statt Snapin). Das Skript kann auf dem Veeam-Server selbst oder auf einem beliebigen anderen Server gestartet werden. Die Veeam-Abfrage läuft immer auf dem Veeam-Server (lokal bzw. per Invoke-Command), die Textdatei wird auf dem Rechner gespeichert, auf dem das Skript gestartet wurde.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript den Veeam-Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten) übergeben. Ohne Parameter fragt es den Servernamen selbst ab, speichert in C:\Temp und nutzt das angemeldete Windows-Konto.

VORAUSSETZUNGEN
- Auf dem Veeam-Server ist die Veeam Backup & Replication Console installiert (bringt das Modul Veeam.Backup.PowerShell mit)
- PowerShell 7 auf dem ausführenden Rechner. Die Abfrage läuft auf dem Veeam-Server zuerst in PowerShell 7 (Veeam 13, Remoting-Endpunkt PowerShell.7 per Enable-PSRemoting in pwsh) und sonst in Windows PowerShell 5.1 (Veeam 12)
- Bei Start von einem anderen Server: WinRM zum Veeam-Server erreichbar und Anmeldung mit einem Konto, das dort Administrator ist
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - EINGABE VEEAM-SERVER
Clear-Host
Write-Host ""
$veeamServer = "$Ziel".Trim()
if ([string]::IsNullOrWhiteSpace($veeamServer)) {
    do {
        $veeamServer = (Read-Host "Auf welchem Server läuft Veeam Backup & Replication? Bitte den Servernamen eingeben").Trim()
    } while ([string]::IsNullOrWhiteSpace($veeamServer))
}
else {
    Write-Host "Veeam-Server (aus dem NET-COCKPIT): $veeamServer" -ForegroundColor Cyan
}

# - PARAMETER
$timestamp = (Get-Date).ToString("yyyyMMdd")
$targetFolder = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner }
$targetFile = "${targetFolder}\Wartung_${timestamp}-Backup-${veeamServer}.txt"
$lokaleNamen = @($env:COMPUTERNAME, "localhost", "127.0.0.1", "$env:COMPUTERNAME.$env:USERDNSDOMAIN")
$istLokal = $veeamServer -in $lokaleNamen

# - ERREICHBARKEIT PRÜFEN
if (-not $istLokal) {
    Write-Host ""
    Write-Host "Prüfe WinRM-Verbindung zu $veeamServer ..." -ForegroundColor Yellow
    try {
        $wsmanParameter = @{ ComputerName = $veeamServer; ErrorAction = 'Stop' }
        if ($Anmeldedaten) {
            $wsmanParameter.Credential = $Anmeldedaten
            $wsmanParameter.Authentication = 'Default'
        }
        Test-WSMan @wsmanParameter | Out-Null
        Write-Host "WinRM erreichbar." -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "Abbruch: $veeamServer ist per WinRM nicht erreichbar (Servername falsch, Server aus, Firewall oder WinRM nicht aktiv)." -ForegroundColor Red
        Write-Host ""
        Read-Host "Mit [Enter] beenden" | Out-Null
        return
    }
}

# - ORDNER ERSTELLEN
if (!(Test-Path $targetFolder)) {
    New-Item -Path $targetFolder -ItemType Directory | Out-Null
}

# - STATUS MELDUNG
Write-Host ""
Write-Host "Log wird gelesen, das dauert einen Moment ..." -ForegroundColor Yellow
Write-Host ""

# - SCRIPTBLOCK FÜR VEEAM-ABFRAGE
$scriptBlock = {
    $ergebnis = [PSCustomObject]@{
        Fehler = $null
        Zeilen = @()
    }

    # -- MODUL PRÜFEN
    if (-not (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell)) {
        $ergebnis.Fehler = "Das Modul Veeam.Backup.PowerShell ist auf diesem Server nicht vorhanden. Ist hier Veeam Backup & Replication bzw. die Konsole installiert?"
        return $ergebnis
    }

    # -- SITZUNGEN LESEN
    try {
        Import-Module Veeam.Backup.PowerShell -ErrorAction Stop

        # letzte 30 Tage
        $sessions = Get-VBRBackupSession -ErrorAction Stop | Where-Object { $_.CreationTime -ge (Get-Date).AddDays(-30) } | Sort-Object CreationTime -Descending
    }
    catch {
        $ergebnis.Fehler = $_.Exception.Message
        return $ergebnis
    }

    # -- ZEILEN AUFBAUEN
    $zeilen = [System.Collections.Generic.List[string]]::new()

    if (@($sessions).Count -eq 0) {
        $zeilen.Add("Keine Backup-Sitzungen gefunden.")
    }
    else {
        foreach ($session in $sessions) {
            $zeilen.Add("Job: $($session.JobName)")
            $zeilen.Add("Start: $($session.CreationTime)")
            $zeilen.Add("Ende: $($session.EndTime)")
            $zeilen.Add("Ergebnis: $($session.Result)")
            $zeilen.Add("")

            foreach ($task in $session.GetTaskSessions()) {
                $zeilen.Add("  Gerät: $($task.Name) - $($task.Status)")
            }

            $zeilen.Add("")
            $zeilen.Add("")
        }
    }

    $ergebnis.Zeilen = $zeilen.ToArray()
    return $ergebnis
}

# - LOGS ABRUFEN
## Veeam 13 läuft in PowerShell 7, Veeam 12 nur in Windows PowerShell 5.1. Das Skript probiert erst PS7, bei Fehler PS 5.1.
$ergebnis = $null
$fehlerListe = [System.Collections.Generic.List[string]]::new()

foreach ($endpunkt in @('PowerShell 7', 'Windows PowerShell 5.1')) {
    $antwort = $null
    try {
        if ($istLokal) {
            if ($endpunkt -eq 'PowerShell 7') {
                $antwort = Invoke-Command -ScriptBlock $scriptBlock -ErrorAction Stop
            }
            else {
                $befehl = "& { $scriptBlock } | ConvertTo-Json -Compress -Depth 4"
                $kodiert = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($befehl))
                $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $kodiert
                $antwort = ($json -join '') | ConvertFrom-Json
            }
        }
        else {
            $invokeParameter = @{ ComputerName = $veeamServer; ScriptBlock = $scriptBlock; ErrorAction = 'Stop' }
            if ($endpunkt -eq 'PowerShell 7') { $invokeParameter.ConfigurationName = 'PowerShell.7' }
            if ($Anmeldedaten) { $invokeParameter.Credential = $Anmeldedaten }
            $antwort = Invoke-Command @invokeParameter
        }
    }
    catch {
        $fehlerListe.Add("${endpunkt}: $($_.Exception.Message)")
        continue
    }

    if ($null -eq $antwort) {
        $fehlerListe.Add("${endpunkt}: keine Antwort erhalten")
        continue
    }
    if ($antwort.Fehler) {
        $fehlerListe.Add("${endpunkt}: $($antwort.Fehler)")
        continue
    }

    $ergebnis = $antwort
    Write-Host "Abfrage erfolgreich mit $endpunkt." -ForegroundColor Green
    break
}

if ($null -eq $ergebnis) {
    Write-Host ""
    Write-Host "Abbruch: Abfrage auf $veeamServer fehlgeschlagen." -ForegroundColor Red
    foreach ($eintrag in $fehlerListe) {
        Write-Host $eintrag -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Mit [Enter] beenden" | Out-Null
    return
}

# - LOGS EXPORTIEREN
$ergebnis.Zeilen | Out-File -FilePath $targetFile -Encoding utf8

# - FERTIG MELDUNG
Write-Host "Export abgeschlossen." -ForegroundColor Green
Write-Host "Datei gespeichert unter: $targetFile" -ForegroundColor Cyan
Write-Host "Logdatei wird geöffnet ..." -ForegroundColor Green

# - DATEI ÖFFNEN
if (Test-Path $targetFile) {
    Invoke-Item $targetFile
}
else {
    Write-Host "Keine Datei erstellt." -ForegroundColor Red
}