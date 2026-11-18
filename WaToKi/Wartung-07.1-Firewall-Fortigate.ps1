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
Write-Host "=== Wartung-07.1-Firewall-Fortigate ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Prüft per SSH auf einer FortiGate: Firmware-Aktualität, IPS-Log auf erfolgreiche Angriffe (letzte 30 Tage) und offene Ports von extern (DNAT/VIP), und schreibt Report + Zusammenfassung.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die FortiGate (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten). Dann entfallen die Abfragen von IP-Adresse und Zugangsdaten. Wird das Konto abgelehnt, fragt das Skript (bis zu 3 Versuche) nach.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Posh-SSH-Modul (wird bei Bedarf automatisch installiert: Install-Module -Name Posh-SSH -Scope CurrentUser -Force)
- SSH-Zugriff (Port 22) vom ausführenden Rechner zur FortiGate
- Admin-Zugangsdaten für die FortiGate
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   FortiGate Security-Check" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# - AUSGABEORDNER (aus dem NET-COCKPIT, sonst C:\Temp)
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }
$ReportPath = Join-Path $Ausgabepfad ("Wartung_{0}_FortiGate.txt" -f (Get-Date -Format "yyyyMMdd"))

if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Posh-SSH Modul wird installiert ..." -ForegroundColor Yellow
    Install-Module -Name Posh-SSH -Scope CurrentUser -Force
}
Import-Module Posh-SSH

if ($Automatik -and [string]::IsNullOrWhiteSpace($Ziel)) {
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (FortiGate) nötig." -ForegroundColor Red
    exit 1
}
$FortiGateIP = if ([string]::IsNullOrWhiteSpace($Ziel)) { Read-Host "IP-Adresse der Firewall" } else { $Ziel.Trim() }

Write-Host ""
Write-Host "Verbinde mit $FortiGateIP ..." -ForegroundColor Yellow
$cred = $Anmeldedaten
$session = $null
for ($versuch = 1; $versuch -le 3 -and -not $session; $versuch++) {
    if (($versuch -gt 1 -or -not $cred) -and $Automatik) { break }
    if ($versuch -gt 1 -or -not $cred) {
        $cred = Get-Credential -Message "FortiGate SSH-Zugangsdaten ($FortiGateIP) (Versuch $versuch von 3)"
    }
    if (-not $cred) { break }
    try {
        $session = New-SSHSession -ComputerName $FortiGateIP -Credential $cred -AcceptKey -ErrorAction Stop
    } catch {
        Write-Host "Anmeldung fehlgeschlagen (Versuch $versuch von 3): $($_.Exception.Message)" -ForegroundColor Red
    }
}
if (-not $session) {
    Write-Host "Keine Verbindung zur FortiGate möglich. Skript wird beendet." -ForegroundColor Red
    if ($Automatik) {
        Write-WtErgebnis -Skript '07.1-Firewall-Fortigate' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $FortiGateIP; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'SSH-Verbindung oder Anmeldung fehlgeschlagen' })
        exit 1
    }
    return
}
Write-Host "Verbunden." -ForegroundColor Green
Write-Host ""

$report  = [System.Collections.Generic.List[string]]::new()
$summary = [System.Collections.Generic.List[string]]::new()

$report.Add("FortiGate Security-Check - $FortiGateIP - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$report.Add("=" * 60)

function Invoke-FGCommand {
    param([string]$Command, [string]$Title)
    Write-Host " -> $Title" -ForegroundColor Yellow
    $result = Invoke-SSHCommand -SSHSession $session -Command $Command -TimeOut 60
    $text = ($result.Output -join "`n")
    $report.Add("`n--- $Title ---")
    $report.Add($text)
    Write-Host "    OK" -ForegroundColor Green
    return $text
}

Write-Host "Fuehre Checks aus:" -ForegroundColor Cyan

# 0. Pager abschalten (persistente Konsoleneinstellung, verhindert --More--)
$cmdNoPager = @"
config system console
set output standard
end
"@
Invoke-FGCommand -Command $cmdNoPager -Title "Pager deaktivieren" | Out-Null

# Zeitraum: max. letzte 30 Tage (Format wie von FortiOS erwartet: yyyy/MM/dd)
# Hinweis: "/" im .NET-Format ist kulturabhaengig (wird auf de-DE zu "."), daher escaped als \/
$dateTo   = Get-Date -Format "yyyy\/MM\/dd"
$dateFrom = (Get-Date).AddDays(-30).ToString("yyyy\/MM\/dd")
$dateRange = "$dateFrom-$dateTo"

# ===========================================================
# 1. Firmware-Update vorhanden oder Version aktuell?
# ===========================================================
$fwText = Invoke-FGCommand -Command "get system status" -Title "Firmware-Version"

$currentVersion = $null
if ($fwText -match 'Version:\s*\S+\s+v(\d+)\.(\d+)\.(\d+),build(\d+)') {
    $currentVersion = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
    $currentBuild   = $Matches[4]
}

$imgText = Invoke-FGCommand -Command "diagnose test application forticldd 14" -Title "Verfuegbare Firmware-Images (FortiGuard-Cache)"

$newerVersions = @()
$imageLinesFound = 0
foreach ($line in ($imgText -split "`n")) {
    if ($line -match 'version:(\d+)-(\d+)-(\d+)b\d+-F') {
        $imageLinesFound++
        if ($line -match 'type=upgrade') {
            $candidate = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
            if ($currentVersion -and $candidate -gt $currentVersion) {
                $newerVersions += $candidate.ToString()
            }
        }
    }
}

if (-not $currentVersion) {
    $fwAnswer = "NICHT ERMITTELT - Version konnte aus 'get system status' nicht ausgelesen werden, manuell pruefen."
} elseif ($imageLinesFound -eq 0) {
    $fwAnswer = "NICHT ERMITTELBAR - FortiGuard-Image-Cache des Geraets ist leer/nicht erreichbar (aktuell installiert: v$currentVersion build$currentBuild). Manuell in GUI unter System > Firmware oder Fortinet-Release-Notes pruefen."
} elseif ($newerVersions.Count -gt 0) {
    $fwAnswer = "NEIN - Update verfuegbar: $($newerVersions -join ', ') (aktuell: $currentVersion build$currentBuild)"
} else {
    $fwAnswer = "JA - Firmware ist aktuell (v$currentVersion build$currentBuild, laut FortiGuard-Cache des Geraets keine neuere Upgrade-Version)"
}
$summary.Add("1. Firmware-Update vorhanden oder Version aktuell: $fwAnswer")

# ===========================================================
# 2. Log geprueft auf erfolgreiche Angriffe? (IPS, action=pass, max. 30 Tage)
# ===========================================================
$cmdIpsLog = @"
execute log filter reset
execute log filter category 4
execute log filter field action pass
execute log filter field date $dateRange
execute log filter view-lines 1000
execute log display
"@
$ipsText = Invoke-FGCommand -Command $cmdIpsLog -Title "IPS-Log - erfolgreiche Angriffe, letzte 30 Tage (action=pass)"

$ipsCount = 0
if ($ipsText -match '(\d+)\s+logs found') {
    $ipsCount = [int]$Matches[1]
}

if ($ipsCount -gt 0) {
    $ipsAnswer = "JA GEPRUEFT - $ipsCount erfolgreiche Angriffe (action=pass) in den letzten 30 Tagen gefunden, Details im Report"
} else {
    $ipsAnswer = "JA GEPRUEFT - keine erfolgreichen Angriffe (action=pass) in den letzten 30 Tagen im IPS-Log"
}
$summary.Add("2. Log geprueft auf erfolgreiche Angriffe: $ipsAnswer")

# ===========================================================
# 3. Offene Ports von extern (DNAT/VIP) - Liste zur Relevanzpruefung
# ===========================================================
$vipText = Invoke-FGCommand -Command "show full-configuration firewall vip" -Title "DNAT/VIP-Konfiguration"
Invoke-FGCommand -Command "show firewall policy" -Title "Firewall-Policies" | Out-Null

$vipList = [System.Collections.Generic.List[object]]::new()
$vipBlocks = [regex]::Matches($vipText, 'edit "(?<name>[^"]+)"(?<body>.*?)\r?\n\s*next', 'Singleline')
foreach ($block in $vipBlocks) {
    $body = $block.Groups['body'].Value
    $extip     = if ($body -match 'set extip (\S+)')     { $Matches[1] } else { "-" }
    $extport   = if ($body -match 'set extport (\S+)')   { $Matches[1] } else { "any" }
    $mappedip  = if ($body -match 'set mappedip "?([^"\r\n]+)"?') { $Matches[1] } else { "-" }
    $mappedport= if ($body -match 'set mappedport (\S+)'){ $Matches[1] } else { "-" }
    $protocol  = if ($body -match 'set protocol (\S+)')  { $Matches[1] } else { "tcp" }

    $vipList.Add([PSCustomObject]@{
        Name        = $block.Groups['name'].Value
        ExternIP    = $extip
        ExternPort  = $extport
        Protokoll   = $protocol
        ZielIP      = $mappedip
        ZielPort    = $mappedport
    })
}

$vipTable = $vipList | Format-Table -AutoSize | Out-String
$report.Add("`n--- Offene Ports von extern (DNAT/VIP) - Uebersicht ---")
$report.Add($vipTable)

$summary.Add("3. Offene Ports von extern (DNAT): $($vipList.Count) VIP-Eintraege aktiv - Liste unten, Relevanz durch dich zu bestaetigen (Skript kann Business-Relevanz nicht automatisch beurteilen)")
$summary.Add("")
$summary.Add($vipTable)

Remove-SSHSession -SSHSession $session | Out-Null

# ===========================================================
# Report schreiben
# ===========================================================
$finalReport = [System.Collections.Generic.List[string]]::new()
$finalReport.Add("FortiGate Security-Check - $FortiGateIP - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$finalReport.Add("Zeitraum Logs: $dateFrom bis $dateTo")
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

    # - ERGEBNIS FÜR DIE CHECKLISTE (Haken nur, was das Skript wirklich prüfen konnte; Ports und Konfigurationssicherung ohne Haken)
    $pr = [ordered]@{}
    $notizTeile = @()
    if ($currentVersion) {
        if ($newerVersions.Count -gt 0) {
            $pr['FirmwareAktuell'] = $false
            $notizTeile += "Firmware-Update verfügbar: $($newerVersions -join ', ')"
        } elseif ($imageLinesFound -gt 0) {
            $pr['FirmwareAktuell'] = $true
        }
    }
    if ($ipsText -match '\d+\s+logs found') {
        $pr['LogGeprueft'] = $true
        if ($ipsCount -gt 0) { $notizTeile += "IPS-Log: $ipsCount erfolgreiche Angriffe (action=pass) in 30 Tagen" }
    }
    $notizTeile += "$($vipList.Count) VIP-Eintraege (offene Ports von extern), Relevanz manuell prüfen"
    $werte = [ordered]@{
        Firmware      = $(if ($currentVersion) { "v$currentVersion build$currentBuild" } else { $null })
        FirmwareAntwort = $fwAnswer
        IpsTreffer    = $ipsCount
        Vips          = @($vipList | ForEach-Object { [pscustomobject]@{ Name = $_.Name; ExternIP = $_.ExternIP; ExternPort = $_.ExternPort; Protokoll = $_.Protokoll; ZielIP = $_.ZielIP; ZielPort = $_.ZielPort } })
    }
    Write-WtErgebnis -Skript '07.1-Firewall-Fortigate' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $FortiGateIP; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = ($notizTeile -join '; ') })
    exit 0
}

Invoke-Item $ReportPath