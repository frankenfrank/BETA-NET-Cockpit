#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string]$Ziel,
    [string]$Ausgabeordner,
    [pscredential]$Anmeldedaten,
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
Write-Host "=== Wartung-06.5-E-Mail-Security-NoSpamProxy ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Prüft NoSpamProxy Email-Relay-Status, E-Mail-Quarantäne, Zertifikatsablauf und NSP-Eventlogs (letzte 30 Tage) und schreibt Report + Zusammenfassung.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript den NoSpamProxy-Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten); die Abfragen laufen dann per PowerShell Remoting auf diesem Server. Ohne -Ziel läuft das Skript lokal auf dem NoSpamProxy-Server.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Remote: WinRM mit PowerShell-7-Endpunkt (PowerShell.7) auf dem NoSpamProxy-Server
- NoSpamProxy-PowerShell-Modul auf dem NoSpamProxy-Server (wird mit NSP mitinstalliert)
- Ausführendes Konto Mitglied von "NoSpamProxy Monitoring Administrators" (bzw. "...Configuration Administrators")
'@ -ForegroundColor Yellow
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

# - KONFIGURATION
$Days = 30
$nspServer = if ([string]::IsNullOrWhiteSpace($Ziel)) { $env:COMPUTERNAME } else { $Ziel.Trim() }
$ReportPath = Join-Path $Ausgabepfad ("Wartung_{0}_NoSpamProxy.txt" -f (Get-Date -Format "yyyyMMdd"))

## Im Automatikmodus: Ergebnis mit Erreicht=false schreiben und beenden
function Stop-NspAutomatik {
    param([string]$Notiz)
    if ($Automatik) {
        Write-WtErgebnis -Skript '06.5-E-Mail-Security-NoSpamProxy' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $nspServer; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = $Notiz })
        exit 1
    }
}

# - VERBINDUNG ZUM NSP-SERVER (lokal oder per PowerShell Remoting)
$nspLokal = ($nspServer -in @($env:COMPUTERNAME, "localhost", "127.0.0.1", "::1", ".")) -or ($nspServer -like "$env:COMPUTERNAME.*")
$nspSitzung = $null
if (-not $nspLokal) {
    $sitzungParam = @{ ComputerName = $nspServer; ConfigurationName = 'PowerShell.7'; ErrorAction = 'Stop' }
    if ($Anmeldedaten) { $sitzungParam.Credential = $Anmeldedaten }
    try {
        $nspSitzung = New-PSSession @sitzungParam
    } catch {
        if (-not $Anmeldedaten -or $Automatik) { Write-Host "Verbindung zu $nspServer fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red; Stop-NspAutomatik 'Verbindung fehlgeschlagen'; return }
        Write-Host "Anmeldung mit dem Konto aus dem NET-COCKPIT fehlgeschlagen - Zugangsdaten abfragen" -ForegroundColor Yellow
        $sitzungParam.Credential = Get-Credential -Message "Zugangsdaten für $nspServer"
        try { $nspSitzung = New-PSSession @sitzungParam }
        catch { Write-Host "Verbindung zu $nspServer fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red; Stop-NspAutomatik 'Verbindung fehlgeschlagen'; return }
    }
    ## $Days steht den Abfragen auf dem Server als globale Variable zur Verfügung
    Invoke-Command -Session $nspSitzung -ScriptBlock { param($tage) $global:Days = $tage } -ArgumentList $Days
}

$report  = [System.Collections.Generic.List[string]]::new()
$summary = [System.Collections.Generic.List[string]]::new()
$report.Add("NoSpamProxy Security-Check - $nspServer - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$report.Add("=" * 60)


#FUNKTIONEN
function Invoke-NspStep {
    param([scriptblock]$ScriptBlock, [string]$Title, [object[]]$ArgumentList)
    Write-Host " -> $Title" -ForegroundColor Yellow
    if ($nspSitzung) { $result = Invoke-Command -Session $nspSitzung -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList }
    else { $result = & $ScriptBlock @ArgumentList }
    Write-Host "    OK" -ForegroundColor Green
    return $result
}

Write-Host "Fuehre Checks aus:" -ForegroundColor Cyan

# 0. Verbindung zur NSP-API herstellen
try {
    Invoke-NspStep -Title "Verbindung zur NoSpamProxy-API" -ScriptBlock {
        Connect-Nsp -IgnoreServerCertificateErrors -ErrorAction Stop
    } | Out-Null
} catch {
    Write-Host "Verbindung zur NoSpamProxy-API fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    Stop-NspAutomatik 'Verbindung zur NoSpamProxy-API fehlgeschlagen'
    throw
}

$dateFrom = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')
$dateTo   = (Get-Date).ToString('yyyy-MM-dd')

# ===========================================================
# 1. Funktioniert das Email-Relay einwandfrei?
# ===========================================================
$relay = Invoke-NspStep -Title "Message-Track / Warteschlange / Issues (Relay, $Days Tage)" -ScriptBlock {
    $ts = New-TimeSpan -Days $Days
    $roles = Get-NspGatewayRole
    $perRole = foreach ($role in $roles) {
        [PSCustomObject]@{
            GatewayRole        = $role.Name
            EingehendErfolg    = (Get-NspMessageTrack -Status Success -Age $ts -Directions FromExternal -GatewayRole $role.Name).Count
            AusgehendErfolg    = (Get-NspMessageTrack -Status Success -Age $ts -Directions FromLocal -GatewayRole $role.Name).Count
            DispatcherError    = (Get-NspMessageTrack -Status DispatcherError -Age $ts -Directions All -GatewayRole $role.Name).Count
            TemporaerBlockiert = (Get-NspMessageTrack -Status TemporarilyBlocked -Age $ts -Directions All -GatewayRole $role.Name).Count
            AusgehendWartend   = (Get-NspMessageTrack -Status DeliveryPending -Age $ts -Directions FromLocal -GatewayRole $role.Name).Count
        }
    }

    $queueCount = $null
    try {
        $queueCount = (Get-NspQueue -ErrorAction Stop | Measure-Object).Count
    } catch {
        $queueCount = -1
    }

    $issues = @(Get-NspIssue)

    [PSCustomObject]@{
        PerRole    = $perRole
        QueueCount = $queueCount
        Issues     = $issues
    }
}

$relayTable = $relay.PerRole | Format-Table -AutoSize | Out-String
$report.Add("`n--- Email-Relay - Message-Track je Gateway-Rolle, letzte $Days Tage ---")
$report.Add($relayTable)

if ($relay.QueueCount -eq -1) {
    $report.Add("Warteschlange (Get-NspQueue): konnte nicht global abgefragt werden - ggf. ist -Domain erforderlich, manuell pruefen.")
} else {
    $report.Add("Aktuelle Warteschlange (Get-NspQueue): $($relay.QueueCount) Eintraege")
}

if ($relay.Issues.Count -gt 0) {
    $report.Add("`nGet-NspIssue meldet $($relay.Issues.Count) offene Probleme:")
    $report.Add(($relay.Issues | Format-Table -AutoSize | Out-String))
} else {
    $report.Add("`nGet-NspIssue: keine offenen Probleme gemeldet.")
}

$dispatcherErrorSum = ($relay.PerRole | Measure-Object -Property DispatcherError -Sum).Sum
$queueWarnLevel = 50

if ($dispatcherErrorSum -gt 0) {
    $relayDetail = "$dispatcherErrorSum DispatcherError(s) in letzten $Days Tagen, Relay pruefen"
} elseif ($relay.QueueCount -gt $queueWarnLevel) {
    $relayDetail = "Warteschlange mit $($relay.QueueCount) Eintraegen auffaellig hoch (Schwelle: $queueWarnLevel), Relay pruefen"
} elseif ($relay.Issues.Count -gt 0) {
    $relayDetail = "$($relay.Issues.Count) offene Probleme laut Get-NspIssue, Details im Report"
} else {
    $relayDetail = "Relay funktioniert einwandfrei (keine DispatcherError, Warteschlange unauffaellig, keine offenen Issues)"
}

# ===========================================================
# 2. E-Mail-Quarantaene (On-Hold) - nur Anzahl
# ===========================================================
$holdCount = Invoke-NspStep -Title "Quarantaene / On-Hold-Mails" -ScriptBlock {
    (Get-NspEmailOnHold).Count
}
$report.Add("`n--- Quarantaene (On-Hold) ---")
$report.Add("Aktuell in Quarantaene (Get-NspEmailOnHold): $holdCount Mail(s)")
$report.Add("Hinweis: Get-NspEmailOnHold liefert laut Hersteller keine Mails, die noch auf die Content-Filter-Verarbeitung warten (bekannte Einschraenkung).")
$holdDetail = "$holdCount Mail(s) aktuell in Quarantaene"

# ===========================================================
# 3. Zertifikatsablauf - alle Zertifikate im lokalen NSP-Zertifikatsspeicher,
# sortiert nach Ablaufdatum (am naechsten ablaufendes zuerst)
# ===========================================================
$certExpiries = @(
    Invoke-NspStep -Title "Zertifikatsablauf (Cert:\LocalMachine\My)" -ScriptBlock {
        Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Sort-Object NotAfter |
            ForEach-Object {
                [PSCustomObject]@{
                    GueltigBis = $_.NotAfter.ToString('dd.MM.yyyy')
                    Thumbprint = $_.Thumbprint
                    Betreff    = $_.Subject
                }
            }
    }
)

$report.Add("`n--- Zertifikatsablauf - alle Zertifikate in Cert:\LocalMachine\My, sortiert nach Ablaufdatum ---")
$report.Add(($certExpiries | Format-Table -AutoSize | Out-String))

# ===========================================================
# 4. Normales Logging - NSP-eigene Eventlog-Kanaele, Fehler/Warnungen, max. 30 Tage
# ===========================================================
$eventRaw = Invoke-NspStep -Title "NSP-Eventlog (Fehler/Warnungen, $Days Tage)" -ScriptBlock {
    $since = (Get-Date).AddDays(-$Days)
    $nspLogs = @('Net at Work Mail Gateway', 'Net at Work Mail Gateway - Connections')
    try {
        Get-WinEvent -FilterHashtable @{LogName = $nspLogs; Level = 1,2,3; StartTime = $since} -ErrorAction Stop
    } catch {
        @()
    }
}
$eventRaw = @($eventRaw)

# Uebersicht je Log/Schweregrad
$eventOverview = @($eventRaw | Group-Object LogName, LevelDisplayName | Select-Object Name, Count)

# Ausfuehrliche Aufschluesselung je Log/Schweregrad/Event-ID fuer den Report
$eventDetailTable = @(
    $eventRaw | Group-Object LogName, LevelDisplayName, Id | ForEach-Object {
        $first = $_.Group[0]
        [PSCustomObject]@{
            LogName       = $first.LogName
            Level         = $first.LevelDisplayName
            EventId       = $first.Id
            Anzahl        = $_.Count
            LetzteMeldung = ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated.ToString('dd.MM.yyyy HH:mm')
            Beispieltext  = (($first.Message -split "`r?`n")[0])
        }
    } | Sort-Object LogName, Level, EventId
)

$report.Add("`n--- NSP-Eventlog (Net at Work Mail Gateway / - Connections), Fehler/Warnungen, letzte $Days Tage - Uebersicht ---")
$report.Add(($eventOverview | Format-Table -AutoSize | Out-String))
$report.Add("--- NSP-Eventlog - Aufschluesselung nach Event-ID ---")
$report.Add(($eventDetailTable | Format-Table -AutoSize -Wrap | Out-String))

$nspWarnCount  = ($eventRaw | Where-Object { $_.LevelDisplayName -eq 'Warnung' }).Count
$nspErrorCount = ($eventRaw | Where-Object { $_.LevelDisplayName -eq 'Fehler' }).Count

# ===========================================================
# Zusammenfassung befuellen
# ===========================================================
$summary.Add("- Email-Relay:")
$summary.Add("-- $relayDetail")
$summary.Add("- Quarantaene:")
$summary.Add("-- $holdDetail")
$summary.Add("- Zertifikatablaufdatum:")
if ($certExpiries.Count -gt 0) {
    foreach ($c in $certExpiries) {
        $summary.Add("-- $($c.GueltigBis) $($c.Thumbprint)")
    }
} else {
    $summary.Add("-- keine Zertifikate in Cert:\LocalMachine\My gefunden")
}
$summary.Add("- NSP-Ereignislog:")
$summary.Add("-- Warnungen: $nspWarnCount")
$summary.Add("-- Fehler: $nspErrorCount")

if ($nspSitzung) { Remove-PSSession $nspSitzung -ErrorAction SilentlyContinue }

# ===========================================================
# Report schreiben
# ===========================================================
$finalReport = [System.Collections.Generic.List[string]]::new()
$finalReport.Add("NoSpamProxy Security-Check - $nspServer - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$finalReport.Add("Zeitraum: $dateFrom bis $dateTo")
$finalReport.Add("=" * 60)
$finalReport.Add("")
$finalReport.Add("DETAILS")
$finalReport.Add("-" * 60)
$finalReport.AddRange($report)
$finalReport.Add("")
$finalReport.Add("=" * 60)
$finalReport.Add("ZUSAMMENFASSUNG")
$finalReport.Add("-" * 60)
$finalReport.AddRange($summary)

$finalReport | Out-File -FilePath $ReportPath -Encoding UTF8

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " ZUSAMMENFASSUNG" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
foreach ($line in $summary) { Write-Host $line -ForegroundColor White }
Write-Host ""
Write-Host " Report gespeichert: $ReportPath" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan

if ($Automatik) {
    Get-Content -LiteralPath $ReportPath | Write-Host

    # - ERGEBNIS FÜR DIE CHECKLISTE (Haken = geprüft und in Ordnung; nur was ermittelt wurde, steht drin)
    $pr = [ordered]@{}
    $probleme = @()
    if ($relay.QueueCount -ne -1) {
        $pr['RelayOk'] = (($dispatcherErrorSum -eq 0) -and ($relay.QueueCount -le $queueWarnLevel) -and ($relay.Issues.Count -eq 0))
        if (-not $pr['RelayOk']) { $probleme += $relayDetail }
    }
    $werte = [ordered]@{
        RelayDetail       = $relayDetail
        QuarantaeneMails  = $holdCount
        Zertifikate       = @($certExpiries | ForEach-Object { [pscustomobject]@{ GueltigBis = $_.GueltigBis; Thumbprint = $_.Thumbprint; Betreff = $_.Betreff } })
        EventlogWarnungen = $nspWarnCount
        EventlogFehler    = $nspErrorCount
    }
    $notiz = "Quarantäne: $holdCount Mail(s)"
    if ($probleme.Count -gt 0) { $notiz += '; ' + ($probleme -join '; ') }
    Write-WtErgebnis -Skript '06.5-E-Mail-Security-NoSpamProxy' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $nspServer; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = $notiz })
    exit 0
}

Invoke-Item $ReportPath