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
Write-Host "=== Wartung-06.2-EntraSync ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Prüft den Entra Connect/ADSync-Synchronisierungsstatus (letzter Lauf, Version, Konfigurationssicherung) und das Alter des Seamless-SSO-Kerberos-Schlüssels (Konto AZUREADSSOACC). Läuft direkt auf dem Entra-Connect-Server oder von einem anderen Rechner aus per PowerShell Remoting. Es wird nur geprüft, kein Rollover durchgeführt. Konsole, Log-Datei und Konfigurationssicherung liegen immer auf dem Rechner, auf dem das Script gestartet wird.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript den Entra-Connect-Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten). Dann entfällt die Abfrage des Servernamens. Wird das Konto abgelehnt, fragt das Skript nach.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Lokal: Ausführung auf dem Server mit Microsoft Entra Connect (Azure AD Connect)
- Remote: WinRM (PowerShell Remoting) mit PowerShell-7-Endpunkt (PowerShell.7) auf dem Entra-Connect-Server aktiv, Ausführung mit dem Konto aus dem NET-COCKPIT bzw. dem aktuellen Konto
- Lokale Admin-Rechte auf dem Entra-Connect-Server (Application-Eventlog, Konfigurationssicherung)
- ADSync-PowerShell-Modul auf dem Entra-Connect-Server vorhanden
- Lesezugriff auf das Active Directory vom ausführenden Server aus (Prüfung des Kontos AZUREADSSOACC)
- Schreibrechte auf C:\Temp des ausführenden Servers
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# - KONFIGURATION
$thresholdDays = 180
$accName = "AZUREADSSOACC"
$logFolder = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
$datum = Get-Date -Format 'yyyyMMdd'
$syncDetailsPath = Join-Path $logFolder "Wartung-$datum-EntraSync.txt"

if (-not (Test-Path $logFolder)) { New-Item -ItemType Directory -Path $logFolder | Out-Null }

# - ZIELSERVER ABFRAGEN
$serverInput = if ([string]::IsNullOrWhiteSpace($Ziel)) { if ($Automatik) { '' } else { (Read-Host "Name des Entra-Connect-Servers (leer = dieser Server)").Trim() } } else { $Ziel.Trim() }
$localNames = @('', '.', 'localhost', $env:COMPUTERNAME)
$isRemote = -not ($localNames -contains $serverInput)
$targetName = if ($isRemote) { $serverInput } else { $env:COMPUTERNAME }

Write-Host "`nAbfrage wird ausgeführt ($targetName) ..." -ForegroundColor Cyan

# - REMOTING PRÜFEN
$session = $null
if ($isRemote) {
  Write-Host "`nPrüfe WinRM-Verbindung zu $targetName ..." -ForegroundColor Cyan
  try {
    Test-WSMan -ComputerName $targetName -ErrorAction Stop | Out-Null
    $sitzungParam = @{ ComputerName = $targetName; ConfigurationName = 'PowerShell.7'; ErrorAction = 'Stop' }
    if ($Anmeldedaten) { $sitzungParam.Credential = $Anmeldedaten }
    try {
      $session = New-PSSession @sitzungParam
    } catch {
      if (-not $Anmeldedaten -or $Automatik) { throw }
      Write-Host "Anmeldung mit dem Konto aus dem NET-COCKPIT fehlgeschlagen - Zugangsdaten abfragen" -ForegroundColor Yellow
      $sitzungParam.Credential = Get-Credential -Message "Zugangsdaten für $targetName"
      $session = New-PSSession @sitzungParam
    }
    Write-Host "WinRM: OK" -ForegroundColor Green
  } catch {
    Write-Host "WinRM-Verbindung zu $targetName nicht möglich: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Prüfen: WinRM auf dem Zielserver aktiv, Firewall (TCP 5985), Namensauflösung, Konto mit lokalen Adminrechten auf dem Zielserver." -ForegroundColor Yellow
    if ($Automatik) {
      Write-WtErgebnis -Skript '06.2-EntraSync' -Ordner $logFolder -Ergebnisse @([pscustomobject]@{ Ziel = $targetName; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'WinRM-Verbindung nicht möglich' })
      exit 1
    }
    return
  }
}

# - DATENSAMMLUNG (läuft auf dem Entra-Connect-Server)
$collect = {
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  $r = [ordered]@{
    ComputerName        = $env:COMPUTERNAME
    DomainName          = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
    AdSyncModuleOk      = $false
    SchedulerError      = $null
    SchedulerEnabled    = $null
    SchedulerInProgress = $null
    SchedulerNextUtc    = $null
    NoRunFound          = $false
    IsLastRunOk         = $false
    LastSuccessTime     = $null
    LastErrorTime       = $null
    EventsChecked       = 0
    IssueCount          = 0
    LogText             = ''
    Version             = $null
    BackupPath          = $null
  }

  ## ADSync-Modul
  try { Import-Module ADSync -UseWindowsPowerShell -ErrorAction Stop; $r.AdSyncModuleOk = $true } catch {}
  if (-not $r.AdSyncModuleOk) { return [pscustomobject]$r }

  ## Scheduler
  try {
    $s = Get-ADSyncScheduler -ErrorAction Stop
    $r.SchedulerEnabled    = $s.SyncCycleEnabled
    $r.SchedulerInProgress = $s.SyncCycleInProgress
    $r.SchedulerNextUtc    = $s.NextSyncCycleStartTimeInUTC
  } catch {
    $r.SchedulerError = $_.Exception.Message
  }

  ## Eventlog
  $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'ADSync' } -MaxEvents 500 -ErrorAction SilentlyContinue)
  $lastErrorRun = $events | Where-Object { $_.Id -in 6100, 6941 } | Select-Object -First 1
  $lastInfoRun  = $events | Where-Object { $_.Level -eq 4 -and $_.Id -in 6946, 6952 } | Select-Object -First 1

  if (-not $lastInfoRun) {
    $r.NoRunFound = $true
    $r.LogText = "Kein ADSync-Lauf im Eventlog gefunden (Application/ADSync)."
  } else {
    $isOk = $true
    if ($lastErrorRun -and ($lastErrorRun.TimeCreated -gt $lastInfoRun.TimeCreated)) { $isOk = $false }
    $anchor = if ($isOk) { $lastInfoRun.TimeCreated } else { $lastErrorRun.TimeCreated }

    $runEvents = @(Get-WinEvent -FilterHashtable @{
        LogName      = 'Application'
        ProviderName = 'ADSync'
        StartTime    = $anchor.AddMinutes(-10)
        EndTime      = $anchor.AddMinutes(1)
      } -ErrorAction SilentlyContinue | Sort-Object TimeCreated)

    $r.IsLastRunOk     = $isOk
    $r.LastSuccessTime = $lastInfoRun.TimeCreated
    if ($lastErrorRun) { $r.LastErrorTime = $lastErrorRun.TimeCreated }
    $r.EventsChecked   = $runEvents.Count
    $r.IssueCount      = @($runEvents | Where-Object { $_.Level -in 1, 2, 3 }).Count

    $lines = foreach ($e in $runEvents) {
      "==== EVENT ===="
      "TimeCreated: $($e.TimeCreated)"
      "Level:       $($e.LevelDisplayName)"
      "EventID:     $($e.Id)"
      "Source:      $($e.ProviderName)"
      "Category:    $($e.TaskDisplayName)"
      "MachineName: $($e.MachineName)"
      "UserName:    $(if ($e.UserId) { $e.UserId.Value })"
      ""
      "Message:"
      "$($e.Message)"
      ""
    }
    $r.LogText = $lines -join "`r`n"
  }

  ## Version
  $exe = "C:\Program Files\Microsoft Azure AD Sync\Bin\miiserver.exe"
  if (Test-Path $exe) { $r.Version = (Get-Item $exe).VersionInfo.FileVersion }

  ## Konfigurationssicherung
  $backupFile = Get-ChildItem 'C:\ProgramData\AADConnect' -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($backupFile) { $r.BackupPath = $backupFile.FullName }

  [pscustomobject]$r
}

# - DATEN HOLEN
try {
  if ($isRemote) {
    $data = Invoke-Command -Session $session -ScriptBlock $collect
  } else {
    $data = & $collect
  }
} catch {
  Write-Host "Datensammlung auf $targetName fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
  if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
  if ($Automatik) {
    Write-WtErgebnis -Skript '06.2-EntraSync' -Ordner $logFolder -Ergebnisse @([pscustomobject]@{ Ziel = $targetName; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Datensammlung fehlgeschlagen' })
    exit 1
  }
  return
}

# - ENTRA CONNECT VORHANDEN?
if (-not $data.AdSyncModuleOk) {
  Write-Host "`nAbbruch: Auf $targetName ist kein Entra Connect (ADSync-Modul) vorhanden." -ForegroundColor Red
  Write-Host "Bitte den Server mit Microsoft Entra Connect angeben." -ForegroundColor Yellow
  if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
  if ($Automatik) {
    Write-WtErgebnis -Skript '06.2-EntraSync' -Ordner $logFolder -Ergebnisse @([pscustomobject]@{ Ziel = $targetName; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Kein Entra Connect (ADSync-Modul) auf dem Server' })
    exit 1
  }
  return
}

# - DATEIEN LOKAL SPEICHERN
$backupCopiedText = "Keine Sicherungsdatei gefunden"

if ($data.AdSyncModuleOk) {

  ## Log-Datei
  $data.LogText | Out-File -FilePath $syncDetailsPath -Encoding UTF8
  if ($Automatik -and $data.LogText) { Write-Host $data.LogText }

  ## Konfigurationssicherung
  if ($data.BackupPath) {
    $backupName = Split-Path $data.BackupPath -Leaf
    if ($isRemote) {
      Copy-Item -FromSession $session -Path $data.BackupPath -Destination $logFolder -Force
    } else {
      Copy-Item -Path $data.BackupPath -Destination $logFolder -Force
    }
    $backupCopiedText = "Backup kopiert nach $logFolder\$backupName"
  }
}

if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }

# - SEAMLESS-KEY PRÜFEN (nur lesend, vom ausführenden Server aus)
$ssoAvailable = $false
$keyError = $null
$keyLastSet = $null
$keyVersion = 'unbekannt'
$ageDays = 0

try {
  $searcher = New-Object System.DirectoryServices.DirectorySearcher
  $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($data.DomainName)")
  $searcher.Filter = "(&(objectClass=computer)(name=$accName))"
  [void]$searcher.PropertiesToLoad.Add('pwdlastset')
  [void]$searcher.PropertiesToLoad.Add('msds-keyversionnumber')
  $found = $searcher.FindOne()

  if ($found) {
    $ssoAvailable = $true
    $keyLastSet = [DateTime]::FromFileTime([int64]$found.Properties['pwdlastset'][0])
    if ($found.Properties['msds-keyversionnumber'].Count -gt 0) { $keyVersion = $found.Properties['msds-keyversionnumber'][0] }
    $ageDays = (New-TimeSpan -Start $keyLastSet -End (Get-Date)).Days
  }
} catch {
  $keyError = $_.Exception.Message
}

# - AUSGABE
Write-Host "`n# Entra Connect / ADSync Status ($targetName)" -ForegroundColor Cyan

if (-not $data.AdSyncModuleOk) {
  Write-Host "Status: ADSync nicht verfügbar (ADSync-Modul auf $targetName nicht gefunden, ist das der Entra-Connect-Server?)" -ForegroundColor Yellow
} else {

  ## Sync-Ergebnis
  if ($data.NoRunFound) {
    Write-Host "Status: Kein Lauf gefunden" -ForegroundColor Yellow
    Write-Host "Geprüft: Application-Eventlog (ADSync) auf $targetName, kein Sync-Lauf vorhanden"
    Write-Host ("Log-Datei: {0}" -f $syncDetailsPath)
  } elseif ($data.IsLastRunOk) {
    Write-Host "Status: Synchronisierung fehlerfrei" -ForegroundColor Green
    Write-Host ("Letzter Sync-Lauf: {0}" -f $data.LastSuccessTime)
    Write-Host ("Geprüfte Events im Zeitraum des Laufs: {0}" -f $data.EventsChecked)
    $issueColor = if ($data.IssueCount -gt 0) { "Yellow" } else { "Green" }
    Write-Host ("Gefundene Fehler/Warnungen: {0}" -f $data.IssueCount) -ForegroundColor $issueColor
    Write-Host ("Log-Datei: {0}" -f $syncDetailsPath)
  } else {
    Write-Host "Status: Fehler gefunden" -ForegroundColor Red
    Write-Host ("Letzter Lauf mit Fehlern: {0}" -f $data.LastErrorTime) -ForegroundColor Red
    Write-Host ("Geprüfte Events im Zeitraum des Laufs: {0}" -f $data.EventsChecked)
    Write-Host ("Gefundene Fehler/Warnungen: {0}" -f $data.IssueCount) -ForegroundColor Red
    Write-Host ("Log-Datei: {0}" -f $syncDetailsPath)
    if (-not $Automatik) { Start-Process notepad.exe $syncDetailsPath }
  }

  ## Scheduler
  if ($data.SchedulerError) {
    Write-Host "Hinweis: Get-ADSyncScheduler fehlgeschlagen: $($data.SchedulerError)" -ForegroundColor Yellow
  } else {
    Write-Host ("ADSync: Enabled={0} InProgress={1} NextUTC={2}" -f $data.SchedulerEnabled, $data.SchedulerInProgress, $data.SchedulerNextUtc)
  }

  ## Version
  if ($data.Version) {
    Write-Host ("Installierte Version: {0}" -f $data.Version)
  } else {
    Write-Host "Installierte Version: unbekannt" -ForegroundColor Yellow
  }

  ## Konfigurationssicherung
  Write-Host $backupCopiedText
}

Write-Host "`n## Seamless-Key" -ForegroundColor Cyan
if ($keyError) {
  Write-Host ("Key-Alter konnte nicht gelesen werden (Domäne {0}): {1}" -f $data.DomainName, $keyError) -ForegroundColor Yellow
} elseif (-not $ssoAvailable) {
  Write-Host "Nicht eingerichtet (Konto '$accName' nicht gefunden)." -ForegroundColor Yellow
} else {
  Write-Host ("SSO-Key: Zuletzt aktualisiert: {0} | Version: {1} | Alter: {2} Tage | Älter als {3} Tage: {4}" -f `
    $keyLastSet,
    $keyVersion,
    $ageDays,
    $thresholdDays,
    ($ageDays -gt $thresholdDays))

  if ($ageDays -gt $thresholdDays) {
    Write-Host "Rollover notwendig. Bitte lokal auf dem Entra-Connect-Server durchführen." -ForegroundColor Red
  } else {
    Write-Host "Rollover nicht notwendig." -ForegroundColor Green
  }
  Write-Host "Hinweis: Microsoft empfiehlt, den Key mindestens alle 30 Tage zu erneuern." -ForegroundColor Cyan
}

# - ERGEBNIS FÜR DIE CHECKLISTE (Haken = geprüft und in Ordnung; nur was ermittelt wurde, steht drin)
if ($Automatik) {
  $pr = [ordered]@{}
  $probleme = @()
  $werte = [ordered]@{ Version = [string]$data.Version }
  if (-not $data.NoRunFound) {
    $pr['SyncOk'] = [bool]$data.IsLastRunOk
    $werte['LetzterLauf'] = $(if ($data.LastSuccessTime) { ([datetime]$data.LastSuccessTime).ToString('yyyy-MM-dd HH:mm') } else { $null })
    $werte['FehlerWarnungen'] = $data.IssueCount
    if (-not $data.IsLastRunOk) { $probleme += 'Letzter Sync-Lauf mit Fehlern' }
  } else {
    $probleme += 'Kein Sync-Lauf im Eventlog gefunden'
  }
  if ($ssoAvailable) {
    $pr['SeamlessKeyOk'] = ($ageDays -le $thresholdDays)
    $werte['SeamlessKeyAlterTage'] = $ageDays
    if ($ageDays -gt $thresholdDays) { $probleme += "Seamless-SSO-Key $ageDays Tage alt (Rollover nötig)" }
  }
  if ($data.BackupPath) { $pr['KonfigSicherung'] = $true }
  $notiz = $(if ($data.Version) { "Version $($data.Version)" } else { '' })
  if ($probleme.Count -gt 0) { $notiz = (@($notiz) + $probleme | Where-Object { $_ }) -join '; ' }
  Write-WtErgebnis -Skript '06.2-EntraSync' -Ordner $logFolder -Ergebnisse @([pscustomobject]@{ Ziel = $targetName; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = $notiz })
  exit 0
}