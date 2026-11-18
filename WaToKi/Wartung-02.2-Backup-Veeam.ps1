#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string]$Ziel,
    [string]$Ausgabeordner,
    [System.Management.Automation.PSCredential]$Anmeldedaten,
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
Write-Host "=== Wartung-02.2-BackupVeeam ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
if (-not $Automatik) { Write-Host @'
BESCHREIBUNG
Exportiert die Veeam-Backup-Sitzungen der letzten 30 Tage als Textdatei (Veeam B&R v12+, PowerShell-Modul statt Snapin). Das Skript kann auf dem Veeam-Server selbst oder auf einem beliebigen anderen Server gestartet werden. Die Veeam-Abfrage läuft immer auf dem Veeam-Server (lokal bzw. als lokale geplante Aufgabe, die per Invoke-Command angelegt wird), die Textdatei wird auf dem Rechner gespeichert, auf dem das Skript gestartet wurde.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript den Veeam-Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten) übergeben. Ohne Parameter fragt es den Servernamen selbst ab, speichert in C:\Temp und nutzt das angemeldete Windows-Konto.

VORAUSSETZUNGEN
- Auf dem Veeam-Server ist die Veeam Backup & Replication Console installiert (bringt das Modul Veeam.Backup.PowerShell mit)
- PowerShell 7 auf dem ausführenden Rechner. Die Abfrage läuft auf dem Veeam-Server zuerst in PowerShell 7 (Veeam 13) und sonst in Windows PowerShell 5.1 (Veeam 12). Bei einem anderen Server startet das Skript dafür kurzzeitig eine geplante Aufgabe auf dem Veeam-Server (pwsh.exe lokal), weil das Veeam-13-Modul in einer WinRM-Sitzung nicht lädt. Die Aufgabe und ihre Dateien in C:\Windows\Temp werden danach wieder gelöscht
- Bei Start von einem anderen Server: WinRM zum Veeam-Server erreichbar und Anmeldung mit einem Konto, das dort Administrator und in Veeam berechtigt ist; die Aufgabe läuft unter diesem Konto (ohne übergebenes Konto unter dem angemeldeten Konto)
- PowerShell 7 (C:\Program Files\PowerShell\7\pwsh.exe) auf dem Veeam-Server, sonst läuft nur der Weg über Windows PowerShell 5.1
'@ -ForegroundColor Yellow }
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

# - EINGABE VEEAM-SERVER
if (-not $Automatik) { Clear-Host }
Write-Host ""
$veeamServer = "$Ziel".Trim()
if ($Automatik -and [string]::IsNullOrWhiteSpace($veeamServer)) {
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (Veeam-Server) nötig." -ForegroundColor Red
    exit 1
}
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
        if ($Automatik) {
            Write-WtErgebnis -Skript '02.2-Backup-Veeam' -Ordner $targetFolder -Ergebnisse @([pscustomobject]@{ Ziel = $veeamServer; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'per WinRM nicht erreichbar' })
            exit 1
        }
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
        Sitzungen = 0
        NichtErfolgreich = 0
        Auffaellig = @()
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

    # -- KENNZAHLEN FÜR DIE CHECKLISTE
    $ergebnis.Sitzungen = @($sessions).Count
    $nichtErfolgreich = @($sessions | Where-Object { [string]$_.Result -ne 'Success' })
    $ergebnis.NichtErfolgreich = $nichtErfolgreich.Count
    $ergebnis.Auffaellig = @($nichtErfolgreich | ForEach-Object { [string]$_.JobName } | Sort-Object -Unique | Select-Object -First 5)

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

# - SCRIPTBLOCK FÜR LOKALE AUFGABE AUF DEM VEEAM-SERVER
## Läuft per Invoke-Command auf dem Veeam-Server, legt dort eine einmalige geplante Aufgabe an (pwsh.exe lokal, nicht in einer WinRM-Sitzung), wartet auf das Ergebnis und räumt wieder auf
$aufgabenBlock = {
    param([string]$AbfrageText, $Konto)

    $id = [guid]::NewGuid().ToString('N')
    $skriptDatei = "C:\Windows\Temp\WaToKiVeeam_$id.ps1"
    $jsonDatei = "C:\Windows\Temp\WaToKiVeeam_$id.json"
    $aufgabenName = "WaToKiVeeam_$id"
    $ergebnis = $null

    try {
        # -- POWERSHELL 7 PRÜFEN
        $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (-not (Test-Path $pwsh)) {
            throw "PowerShell 7 ist auf diesem Server nicht installiert ($pwsh)."
        }

        # -- SKRIPT FÜR DIE AUFGABE SCHREIBEN
        $skriptZeilen = @(
            "`$ErrorActionPreference = 'Stop'",
            "`$abfrage = {",
            $AbfrageText,
            "}",
            "try { `$e = & `$abfrage } catch { `$e = [pscustomobject]@{ Fehler = `$_.Exception.Message; Zeilen = @() } }",
            "`$e | ConvertTo-Json -Compress -Depth 4 | Set-Content -Path '$jsonDatei' -Encoding UTF8"
        )
        ($skriptZeilen -join "`r`n") | Set-Content -Path $skriptDatei -Encoding UTF8

        # -- AUFGABE ANLEGEN UND STARTEN
        $aktion = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$skriptDatei`""
        if ($Konto) {
            $kennwort = $Konto.GetNetworkCredential().Password
            Register-ScheduledTask -TaskName $aufgabenName -Action $aktion -User $Konto.UserName -Password $kennwort -RunLevel Highest -Force -ErrorAction Stop | Out-Null
        }
        else {
            $prinzipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest
            Register-ScheduledTask -TaskName $aufgabenName -Action $aktion -Principal $prinzipal -Force -ErrorAction Stop | Out-Null
        }
        Start-ScheduledTask -TaskName $aufgabenName -ErrorAction Stop

        # -- AUF DAS ERGEBNIS WARTEN (höchstens 10 Minuten)
        $start = Get-Date
        while (-not (Test-Path $jsonDatei)) {
            Start-Sleep -Seconds 3
            $laufzeit = ((Get-Date) - $start).TotalSeconds
            if ($laufzeit -gt 600) { throw 'Zeitüberschreitung: Die Aufgabe hat nach 10 Minuten kein Ergebnis geliefert.' }
            if ($laufzeit -gt 30 -and (Get-ScheduledTask -TaskName $aufgabenName).State -ne 'Running') { Start-Sleep -Seconds 2; break }
        }
        if (-not (Test-Path $jsonDatei)) {
            $code = (Get-ScheduledTaskInfo -TaskName $aufgabenName).LastTaskResult
            throw "Die Aufgabe hat kein Ergebnis geschrieben (Aufgabencode $code)."
        }
        Start-Sleep -Seconds 1
        $ergebnis = Get-Content -Path $jsonDatei -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $ergebnis = [PSCustomObject]@{ Fehler = $_.Exception.Message; Zeilen = @() }
    }
    finally {
        Unregister-ScheduledTask -TaskName $aufgabenName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path $skriptDatei, $jsonDatei -Force -ErrorAction SilentlyContinue
    }

    return $ergebnis
}

# - LOGS ABRUFEN
## Veeam 13 läuft in PowerShell 7, Veeam 12 nur in Windows PowerShell 5.1. Das Skript probiert erst PS7, bei Fehler PS 5.1.
## Bei einem anderen Server läuft PS7 als lokale geplante Aufgabe auf dem Veeam-Server, weil das Veeam-13-Modul in einer WinRM-Sitzung nicht lädt (Hostpolicy-Fehler).
$ergebnis = $null
$fehlerListe = [System.Collections.Generic.List[string]]::new()

$endpunkte = if ($istLokal) { @('PowerShell 7', 'Windows PowerShell 5.1') } else { @('PowerShell 7 (lokale Aufgabe)', 'Windows PowerShell 5.1') }
foreach ($endpunkt in $endpunkte) {
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
            $invokeParameter = @{ ComputerName = $veeamServer; ErrorAction = 'Stop' }
            if ($Anmeldedaten) { $invokeParameter.Credential = $Anmeldedaten }
            if ($endpunkt -like 'PowerShell 7*') {
                $invokeParameter.ScriptBlock = $aufgabenBlock
                $invokeParameter.ArgumentList = @($scriptBlock.ToString(), $Anmeldedaten)
            }
            else { $invokeParameter.ScriptBlock = $scriptBlock }
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
    if ($Automatik) {
        Write-WtErgebnis -Skript '02.2-Backup-Veeam' -Ordner $targetFolder -Ergebnisse @([pscustomobject]@{ Ziel = $veeamServer; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Abfrage fehlgeschlagen' })
        exit 1
    }
    Read-Host "Mit [Enter] beenden" | Out-Null
    return
}

# - LOGS EXPORTIEREN
$ergebnis.Zeilen | Out-File -FilePath $targetFile -Encoding utf8

# - FERTIG MELDUNG
Write-Host "Export abgeschlossen." -ForegroundColor Green
Write-Host "Datei gespeichert unter: $targetFile" -ForegroundColor Cyan

# - ERGEBNIS FÜR DIE CHECKLISTE
if ($Automatik) {
    $sitzungen = [int]$ergebnis.Sitzungen
    $nicht = [int]$ergebnis.NichtErfolgreich
    ### Haken (geprüft) nur, wenn es Sitzungen gibt und alle der letzten 30 Tage erfolgreich waren; ohne Sitzungen ist es unbekannt
    $backupOk = $(if ($sitzungen -gt 0) { $nicht -eq 0 } else { $null })
    $notiz = $(if ($sitzungen -eq 0) { 'keine Backup-Sitzungen in den letzten 30 Tagen' } elseif ($nicht -gt 0) { "$nicht von $sitzungen Sitzungen nicht erfolgreich: $(@($ergebnis.Auffaellig) -join ', ')" } else { '' })
    Write-WtErgebnis -Skript '02.2-Backup-Veeam' -Ordner $targetFolder -Ergebnisse @([pscustomobject]@{
        Ziel = $veeamServer; Erreicht = $true
        Pruefungen = [pscustomobject]@{ BackupErfolgreich = $backupOk }
        Werte = [pscustomobject]@{ Sitzungen30Tage = $sitzungen; NichtErfolgreich = $nicht; AuffaelligeJobs = @($ergebnis.Auffaellig) }
        Notiz = $notiz
    })
    exit 0
}

Write-Host "Logdatei wird geöffnet ..." -ForegroundColor Green

# - DATEI ÖFFNEN
if (Test-Path $targetFile) {
    Invoke-Item $targetFile
}
else {
    Write-Host "Keine Datei erstellt." -ForegroundColor Red
}