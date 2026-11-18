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
Write-Host "=== Wartung-05.2-ExchangeOnPrem ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Führt eine Kurzprüfung auf einem Exchange-Server aus (per Remote-PowerShell): Speicherplatz der Datenbanken, DAG-Konsistenz, alte/inaktive Postfächer, Zertifikate, installierte CU-Version.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript den Exchange-Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten). Ohne -Ziel wird der Server abgefragt (Vorgabe: dieser Rechner). Wird das Konto abgelehnt, fragt das Skript (bis zu 3 Versuche) nach.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner (das Exchange-Snapin läuft nur in Windows PowerShell, daher Verbindung per Remote-PowerShell auf http://<Server>/PowerShell/)
- Zielserver per vollständigem Namen (FQDN) ansprechbar, da die Anmeldung per Kerberos erfolgt
- Exchange-Admin-Rechte (View-Only Organization Management reicht für die Abfragen)
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

# - EXCHANGE-SERVER
$lokalerName = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
$ExchangeServer = $Ziel
if ([string]::IsNullOrWhiteSpace($ExchangeServer) -and -not $Automatik) {
    $ExchangeServer = Read-Host "Exchange-Server (FQDN, leer = $lokalerName)"
}
if ([string]::IsNullOrWhiteSpace($ExchangeServer)) { $ExchangeServer = $lokalerName }
$ExchangeServer = $ExchangeServer.Trim()

# - VERBINDUNG ZUR EXCHANGE MANAGEMENT SHELL (REMOTE, KERBEROS; BIS ZU 3 VERSUCHE)
$sitzungParam = @{
    ConfigurationName = 'Microsoft.Exchange'
    ConnectionUri     = "http://$ExchangeServer/PowerShell/"
    Authentication    = 'Kerberos'
    ErrorAction       = 'Stop'
}
$Cred = $Anmeldedaten
$sitzung = $null
for ($versuch = 1; $versuch -le 3 -and -not $sitzung; $versuch++) {
    if ($versuch -gt 1 -and $Automatik) { break }
    if ($versuch -gt 1) {
        $Cred = Get-Credential -Message "Anmeldung an $ExchangeServer (Versuch $versuch von 3)"
        if (-not $Cred) { break }
    }
    if ($Cred) { $sitzungParam.Credential = $Cred } else { $sitzungParam.Remove('Credential') }
    try {
        $sitzung = New-PSSession @sitzungParam
    }
    catch {
        Write-Host "Verbindung zu $ExchangeServer fehlgeschlagen (Versuch $versuch von 3): $($_.Exception.Message)" -ForegroundColor Red
    }
}
if (-not $sitzung) {
    Write-Host "Keine Verbindung zur Exchange Management Shell auf $ExchangeServer möglich. Skript wird beendet." -ForegroundColor Red
    if ($Automatik) {
        Write-WtErgebnis -Skript '05.2-ExchangeOnPrem' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $ExchangeServer; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Verbindung zur Exchange Management Shell fehlgeschlagen' })
        exit 1
    }
    return
}

$Datum = Get-Date -Format "yyyyMMdd"
$Datei = Join-Path $Ausgabepfad "Wartung_${Datum}_Exchange.txt"

Add-Content $Datei "===== Exchange / Hosted Exchange Kurzcheck ====="
Add-Content $Datei "Server: $ExchangeServer"

# 1. Speicherplatz der Datenbanken
Add-Content $Datei "`n--- Datenbanken: Speicherplatz ---"
Invoke-Command -Session $sitzung -ScriptBlock {
    Get-MailboxDatabase -Status | ForEach-Object {
        "DB: $($_.Name) | Größe: $($_.DatabaseSize) | Frei: $($_.AvailableNewMailboxSpace)"
    }
} | Add-Content $Datei

# 2. DAG-Konsistenz
Add-Content $Datei "`n--- DAG-Konsistenzprüfung ---"
try {
    Invoke-Command -Session $sitzung -ErrorAction Stop -ScriptBlock {
        $dag = Get-DatabaseAvailabilityGroup -ErrorAction Stop
        Get-MailboxDatabaseCopyStatus * | ForEach-Object {
            "DB: $($_.Name) | Status: $($_.Status)"
        }
    } | Add-Content $Datei
}
catch {
    Add-Content $Datei "Keine DAG vorhanden."
}

# 3. Alte Postfächer
Add-Content $Datei "`n--- Alte / Inaktive Postfächer ---"
$altePostfaecher = @(Invoke-Command -Session $sitzung -ScriptBlock {
    Get-Mailbox -ResultSize Unlimited | Where-Object { ($_.WhenChangedUTC -lt (Get-Date).AddMonths(-6)) -and ($_.RecipientTypeDetails -eq "UserMailbox") } | ForEach-Object {
        "Altes Postfach: $($_.PrimarySmtpAddress) | Zuletzt geändert: $($_.WhenChangedUTC)"
    }
})
if ($altePostfaecher.Count -gt 0) {
    Add-Content $Datei $altePostfaecher
} else {
    Add-Content $Datei "Keine alten oder inaktiven Postfächer gefunden."
}

# 4. Zertifikate
Add-Content $Datei "`n--- Zertifikate ---"
Invoke-Command -Session $sitzung -ScriptBlock {
    Get-ExchangeCertificate | ForEach-Object {
        "Zertifikat: $($_.FriendlyName) | Dienste: $($_.Services) | Läuft ab: $($_.NotAfter)"
    }
} | Add-Content $Datei

# 5. Aktuelles CU
Add-Content $Datei "`n--- Aktuelles CU ---"
$Version = Invoke-Command -Session $sitzung -ScriptBlock {
    (@((Get-ExchangeServer).AdminDisplayVersion) | ForEach-Object { "$_" }) -join ", "
}
Add-Content $Datei "Installierte Version: $Version"
Add-Content $Datei "Link zu aktuellen CU-Updates: https://learn.microsoft.com/en-us/exchange/new-features/build-numbers-and-release-dates"

Add-Content $Datei "`n===== Ende Exchange-Kurzcheck ====="

# - ERGEBNIS FÜR DIE CHECKLISTE (Haken = geprüft und in Ordnung; nur was ermittelt wurde, steht drin)
$pr = [ordered]@{}
$probleme = @()
$werte = [ordered]@{ Version = [string]$Version }
try {
    $kopien = @(Invoke-Command -Session $sitzung -ErrorAction Stop -ScriptBlock {
        $null = Get-DatabaseAvailabilityGroup -ErrorAction Stop
        Get-MailboxDatabaseCopyStatus * | ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; Status = [string]$_.Status } }
    })
    if ($kopien.Count -gt 0) {
        $schlecht = @($kopien | Where-Object { $_.Status -notin @('Mounted', 'Healthy') })
        $pr['DagOk'] = ($schlecht.Count -eq 0)
        if ($schlecht.Count -gt 0) { $probleme += "DAG-Kopien auffällig: $(@($schlecht | ForEach-Object { "$($_.Name) $($_.Status)" }) -join ', ')" }
    }
} catch { }
try {
    $zert = @(Invoke-Command -Session $sitzung -ErrorAction Stop -ScriptBlock {
        Get-ExchangeCertificate | ForEach-Object { [pscustomobject]@{ Name = [string]$_.FriendlyName; Dienste = [string]$_.Services; Ablauf = $_.NotAfter } }
    })
    if ($zert.Count -gt 0) {
        $werte['Zertifikate'] = @($zert | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Dienste = $_.Dienste; Ablauf = ([datetime]$_.Ablauf).ToString('yyyy-MM-dd') } })
        $abgelaufen = @($zert | Where-Object { $_.Dienste -ne 'None' -and [datetime]$_.Ablauf -lt (Get-Date) })
        $pr['ZertifikateGueltig'] = ($abgelaufen.Count -eq 0)
        if ($abgelaufen.Count -gt 0) { $probleme += "Zertifikat abgelaufen: $(@($abgelaufen | ForEach-Object { $_.Name }) -join ', ')" }
    }
} catch { }
$werte['AltePostfaecher'] = $altePostfaecher.Count

Remove-PSSession $sitzung -ErrorAction SilentlyContinue

Write-Host "Kurzcheck abgeschlossen. Datei gespeichert unter: $Datei" -ForegroundColor Yellow

if ($Automatik) {
    Get-Content -LiteralPath $Datei | Write-Host
    $notiz = "Version $Version"
    if ($probleme.Count -gt 0) { $notiz += '; ' + ($probleme -join '; ') }
    Write-WtErgebnis -Skript '05.2-ExchangeOnPrem' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $ExchangeServer; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = $notiz })
    exit 0
}
