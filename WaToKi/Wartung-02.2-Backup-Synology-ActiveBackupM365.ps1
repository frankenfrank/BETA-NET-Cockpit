#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
    [hashtable]$AnmeldedatenJeZiel,
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
Write-Host "=== Wartung-02.2-Backup-Synology-ActiveBackupM365 ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Fragt Active Backup for Microsoft 365 auf Synology-NAS über die DSM Web API ab (SYNO.ActiveBackupOffice365). Bewertet das Backup mit OK/WARNUNG/FEHLER (Alter der letzten Ausführung, Fehler/Warnungen je Dienst, Protokoll-Auffälligkeiten), gibt Task-Details, Speicherverbrauch und das Tagesprotokoll der letzten 30 Tage in Datei/Konsole aus.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten NAS (-Ziel), den Ausgabeordner (-Ausgabeordner) und je NAS das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Hat ein NAS kein Konto oder schlägt die Anmeldung fehl, fragt das Skript per Anmeldefenster nach. Ohne -Ziel wird wie bisher eine NAS-Liste (C:\Temp\liste-backup-nas.txt) verwendet und interaktiv gepflegt.

HINWEIS
Diese API ist nicht offiziell von Synology dokumentiert. Ist auf dem NAS 2-Faktor-Authentifizierung eingerichtet, wird bei jedem Lauf nach dem OTP-Code gefragt.

VORAUSSETZUNGEN
- PowerShell 7 (winget install --id Microsoft.PowerShell -e)
- HTTPS-Zugriff auf die DSM-Weboberfläche des NAS (Standardport 5001)
- DSM-Benutzerkonto mit Zugriff auf Active Backup for Microsoft 365 (Konto aus dem NET-COCKPIT oder Abfrage)
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

# - PARAMETER
$Port            = 5001
$TageZurueck     = 30
$BewertungTage   = 7
$MaxAlterStunden = 26

# - AUSGABEORDNER
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }

# - ZIELE BESTIMMEN
$NASListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })

if ($Automatik -and $NASListe.Count -eq 0) {
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (NAS) nötig." -ForegroundColor Red
    exit 1
}

if ($NASListe.Count -gt 0) {
    Write-Host "`nZu prüfende NAS (aus dem NET-COCKPIT):"
    $NASListe | ForEach-Object { Write-Host " - $_" }
}
else {
    ## NAS-Liste verwalten (nur ohne -Ziel)
    $ServerListFile = Join-Path $Ausgabepfad "liste-backup-nas.txt"

    if (-not (Test-Path -LiteralPath $ServerListFile)) {
        (Read-Host "NAS Hostname/IP (Komma getrennt)") -split ",\s*" |
            Out-File -LiteralPath $ServerListFile -Encoding utf8
    }

    Write-Host "`nZu prüfende NAS:"
    Get-Content -LiteralPath $ServerListFile | ForEach-Object { Write-Host " - $_" }

    if ((Read-Host "`nWeitere NAS hinzufügen? (j/n)") -eq "j") {
        (Read-Host "Neue NAS (Komma getrennt)") -split ",\s*" |
            Add-Content -LiteralPath $ServerListFile
    }

    $NASListe = @(Get-Content -LiteralPath $ServerListFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
}

if ($NASListe.Count -eq 0) {
    Write-Host "→ Keine NAS vorhanden – Skript wird beendet."
    return
}

# - AUSGABEDATEI
$Datum        = Get-Date -Format "yyyyMMdd"
$Dateiname    = "Wartung_${Datum}_Backup-SYNO-ActiveBackupM365.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname

# - ALTE DATEI LÖSCHEN
Remove-Item -LiteralPath $AusgabeDatei -ErrorAction SilentlyContinue

# - LOG-FUNKTION
function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $AusgabeDatei -Value $Message
}

# - HILFSFUNKTIONEN
function ConvertFrom-UnixTime {
    param([int64]$Seconds)
    if ($Seconds -le 0) { return "-" }
    return [DateTimeOffset]::FromUnixTimeSeconds($Seconds).LocalDateTime.ToString("dd.MM.yyyy HH:mm")
}

function Format-Groesse {
    param([int64]$Bytes)
    if ($Bytes -ge 1GB) { return "{0} GB" -f [math]::Round($Bytes / 1GB, 2) }
    return "{0} MB" -f [math]::Round($Bytes / 1MB, 1)
}

# - ANMELDEDATEN (je NAS aus dem NET-COCKPIT, sonst Abfrage beim ersten NAS ohne Konto)
$cred = $null

# - GRENZDATEN
$Grenzdatum     = (Get-Date).AddDays(-$TageZurueck)
$Bewertungsgrenze = (Get-Date).AddDays(-$BewertungTage)

# - ANMELDEFUNKTION (MIT OTP-ABFRAGE BEI 2FA)
function Invoke-DsmLogin {
    param($BaseUrl, $Cred, $DeviceName, $NAS)

    $params = @{
        api         = "SYNO.API.Auth"
        version     = 6
        method      = "login"
        account     = $Cred.UserName
        passwd      = $Cred.GetNetworkCredential().Password
        session     = "ActiveBackupOffice365"
        format      = "sid"
        device_name = $DeviceName
    }

    $resp = Invoke-RestMethod -Uri $BaseUrl -Method Get -Body $params -SkipCertificateCheck -ErrorAction Stop

    # -- 2FA erforderlich -> OTP-Code abfragen
    if (-not $resp.success -and $resp.error.code -eq 403) {
        if ($Automatik) { Write-Host "2-Faktor-Authentifizierung auf $NAS aktiv, im Automatikmodus ist keine OTP-Eingabe möglich." -ForegroundColor Yellow; return $resp }
        $params["otp_code"] = Read-Host "OTP-Code für $NAS (2-Faktor)"
        $resp = Invoke-RestMethod -Uri $BaseUrl -Method Get -Body $params -SkipCertificateCheck -ErrorAction Stop
    }

    return $resp
}

# - DIENSTE
$dienste = [ordered]@{
    drive        = "OneDrive"
    mail         = "Exchange-Postfach"
    archive_mail = "Archiv-Postfach"
    contact      = "Kontakte"
    calendar     = "Kalender"
    site         = "SharePoint-Sites"
}

# - BEKANNTE INFO-CODES IM PROTOKOLL
$bekannteInfoCodes = @(0, -84, -85, -86, -87)

# - API-ABFRAGE JE NAS
$ergebnisListe = [System.Collections.Generic.List[object]]::new()
foreach ($NAS in $NASListe) {
    $erg = @{ Erreicht = $false; Tasks = 0; AlleOk = $true; Pruefbar = $true; Notizen = [System.Collections.Generic.List[string]]::new() }
    Write-Log "`n===== Backuplogs: Synology Active Backup for M365 ====="
    Write-Log "===== NAS: $NAS ====="

    $baseUrl    = "https://${NAS}:${Port}/webapi/entry.cgi"
    $DeviceName = "MahrEDV-WartungsSkript"

    try {
        # -- ANMELDEDATEN DIESES NAS: Konto aus dem NET-COCKPIT, sonst Abfrage
        $nasCred = $null
        if ($AnmeldedatenJeZiel -and $AnmeldedatenJeZiel.ContainsKey($NAS)) {
            $nasCred = $AnmeldedatenJeZiel[$NAS]
            Write-Host "→ Anmeldung mit Konto $($nasCred.UserName)..."
        }
        elseif ($cred) { $nasCred = $cred }
        elseif ($Automatik) { $nasCred = $null }
        else {
            $cred    = Get-Credential -Message "DSM-Zugangsdaten für $NAS (Active Backup for Microsoft 365)"
            $nasCred = $cred
        }
        if (-not $nasCred) {
            Write-Log "STATUS          : Keine Zugangsdaten, NAS wird übersprungen"
            continue
        }

        # -- ANMELDUNG (BIS ZU 3 VERSUCHE)
        $maxVersuche = 3
        $login       = $null
        for ($versuch = 1; $versuch -le $maxVersuche; $versuch++) {
            $login = Invoke-DsmLogin -BaseUrl $baseUrl -Cred $nasCred -DeviceName $DeviceName -NAS $NAS
            if ($login.success) { break }

            Write-Log "STATUS          : Anmeldung fehlgeschlagen (Fehlercode $($login.error.code), Versuch $versuch von $maxVersuche)"
            if ($Automatik) { break }
            if ($versuch -lt $maxVersuche) {
                $nasCred = Get-Credential -Message "DSM-Zugangsdaten für $NAS erneut eingeben"
                if (-not $nasCred) { break }
            }
        }

        if (-not $login -or -not $login.success) {
            Write-Log "STATUS          : Anmeldung endgültig fehlgeschlagen, NAS wird übersprungen"
            continue
        }

        $sid = $login.data.sid
        $erg.Erreicht = $true

        # -- AUFGABEN ABRUFEN
        $tasksParams = @{ api = "SYNO.ActiveBackupOffice365"; version = 1; method = "list_tasks"; _sid = $sid }
        $tasks = Invoke-RestMethod -Uri $baseUrl -Method Get -Body $tasksParams -SkipCertificateCheck -ErrorAction Stop

        if (-not $tasks.success) {
            Write-Log "STATUS          : Aufgabenliste konnte nicht abgerufen werden (Fehlercode $($tasks.error.code))"
            continue
        }

        $data = $tasks.data

        foreach ($task in $data.tasks) {

            # --- PROTOKOLL ABRUFEN (mit Pagination)
            $logLimit  = 1000
            $logOffset = 0
            $maxSeiten = 50
            $seite     = 0
            $alleLogs  = @()
            $logFehler = $false

            do {
                $logParams = @{
                    api      = "SYNO.ActiveBackupOffice365"
                    version  = 1
                    method   = "get_all_log"
                    task_id  = $task.task_id
                    offset   = $logOffset
                    limit    = $logLimit
                    key_word = ""
                    _sid     = $sid
                }
                $log = Invoke-RestMethod -Uri $baseUrl -Method Get -Body $logParams -SkipCertificateCheck -ErrorAction Stop

                if (-not $log.success) {
                    $logFehler = $true
                    $logFehlerCode = $log.error.code
                    break
                }

                $batch      = @($log.data.logs)
                $alleLogs  += $batch
                $logOffset += $batch.Count
                $seite++
            } while ($batch.Count -eq $logLimit -and $seite -lt $maxSeiten)

            # --- PROTOKOLL AUSWERTEN
            $geparst = @()
            foreach ($e in ($alleLogs | Where-Object { [DateTimeOffset]::FromUnixTimeSeconds($_.timestamp).LocalDateTime -ge $Grenzdatum })) {
                $zeit = [DateTimeOffset]::FromUnixTimeSeconds($e.timestamp).LocalDateTime
                $o = [PSCustomObject]@{
                    Zeit         = $zeit
                    Tag          = $zeit.ToString("yyyy-MM-dd")
                    Erfolg       = 0
                    Warnung      = 0
                    Fehler       = 0
                    Auffaellig   = $false
                    Beschreibung = $e.description
                    ErrorCode    = $e.error_code
                }
                if ($e.description -match 'success:\s*(\d+);\s*warning:\s*(\d+);\s*error:\s*(\d+)') {
                    $o.Erfolg  = [int]$matches[1]
                    $o.Warnung = [int]$matches[2]
                    $o.Fehler  = [int]$matches[3]
                    if ($o.Warnung -gt 0 -or $o.Fehler -gt 0) { $o.Auffaellig = $true }
                }
                elseif ($e.error_code -notin $bekannteInfoCodes) {
                    $o.Auffaellig = $true
                }
                $geparst += $o
            }

            # --- BACKUP-BEWERTUNG
            $letzteAusfuehrung = [DateTimeOffset]::FromUnixTimeSeconds([int64]$task.last_execution_time).LocalDateTime
            $alterStunden      = [math]::Round(((Get-Date) - $letzteAusfuehrung).TotalHours, 1)
            $summeFehler       = 0
            $summeWarnung      = 0
            foreach ($key in $dienste.Keys) {
                $summeFehler  += [int]$task."error_$key"
                $summeWarnung += [int]$task."warning_$key"
            }

            $auffRecent = @($geparst | Where-Object { $_.Auffaellig -and $_.Zeit -ge $Bewertungsgrenze })
            $auffTage   = @($auffRecent | Select-Object -ExpandProperty Tag -Unique | Sort-Object -Descending)

            $fehlerBefunde  = @()
            $warnungBefunde = @()
            if ([int64]$task.last_execution_time -le 0)  { $fehlerBefunde += "Keine Ausführung vorhanden" }
            elseif ($alterStunden -gt $MaxAlterStunden)  { $fehlerBefunde += "Letzte Ausführung vor $alterStunden h (Schwelle $MaxAlterStunden h)" }
            if ($summeFehler -gt 0)                      { $fehlerBefunde += "$summeFehler Fehler in den Diensten" }
            if ([int]$task.task_status_error_code -ne 0) { $fehlerBefunde += "Task-Fehlercode $($task.task_status_error_code)" }
            if ($summeWarnung -gt 0)                     { $warnungBefunde += "$summeWarnung Warnungen in den Diensten" }
            if ([int]$task.attention_count -gt 0)        { $warnungBefunde += "$($task.attention_count) Einträge mit Aufmerksamkeit nötig" }
            if ($logFehler)                              { $warnungBefunde += "Protokoll nicht abrufbar (Fehlercode $logFehlerCode)" }
            if ($auffRecent.Count -gt 0)                 { $warnungBefunde += "$($auffRecent.Count) Protokoll-Auffälligkeiten in den letzten $BewertungTage Tagen (Tage: $($auffTage -join ', '))" }

            if ($fehlerBefunde.Count -gt 0)      { $bewertung = "FEHLER";  $farbe = "Red" }
            elseif ($warnungBefunde.Count -gt 0) { $bewertung = "WARNUNG"; $farbe = "Yellow" }
            else                                 { $bewertung = "OK";      $farbe = "Green" }

            # --- KENNZAHLEN FÜR DIE CHECKLISTE (strikt: Haken nur, wenn die Bewertung OK ist und das Protokoll der letzten $TageZurueck Tage keine Auffälligkeit enthält)
            $erg.Tasks++
            if ($logFehler) { $erg.Pruefbar = $false; $erg.Notizen.Add("$($task.task_name): Protokoll nicht abrufbar") }
            if ($bewertung -ne 'OK') { $erg.AlleOk = $false; $erg.Notizen.Add("$($task.task_name): $bewertung") }
            $auff30 = @($geparst | Where-Object { $_.Auffaellig })
            if ($auff30.Count -gt 0) { $erg.AlleOk = $false; $erg.Notizen.Add("$($task.task_name): $($auff30.Count) Auffälligkeiten in $TageZurueck Tagen") }

            $bewertungText = "BACKUP-BEWERTUNG : $bewertung (letzte Ausführung vor $alterStunden h)"
            Write-Host "`n$bewertungText" -ForegroundColor $farbe
            Add-Content -Path $AusgabeDatei -Value "`n$bewertungText"
            foreach ($b in ($fehlerBefunde + $warnungBefunde)) { Write-Log " - $b" }

            # --- TASK-DETAILS
            Write-Log "`n--- TASK: $($task.task_name) ---"
            Write-Log ("Letzte Ausführung      : {0}" -f (ConvertFrom-UnixTime $task.last_execution_time))
            Write-Log ("Zeitplan aktiv         : {0}" -f $task.enable_schedule)
            Write-Log ("Zeitplan               : täglich {0:00}:{1:00} Uhr" -f $task.schedule.hour, $task.schedule.minute)
            Write-Log ("Task-Fehlercode        : {0}" -f $task.task_status_error_code)
            Write-Log ("Erfolgreich (Anzahl)   : {0}" -f $task.success_count)
            Write-Log ("Aufmerksamkeit nötig   : {0}" -f $task.attention_count)

            Write-Log "`n--- DIENSTE (VERARBEITET / WARNUNGEN / FEHLER / BELEGT) ---"
            foreach ($key in $dienste.Keys) {
                $processed = $task."processed_$key"
                $warning   = $task."warning_$key"
                $errorCnt  = $task."error_$key"
                $used      = Format-Groesse ([int64]$task."${key}_used_storage")
                Write-Log ("{0,-18}: {1} / {2} / {3} / {4}" -f $dienste[$key], $processed, $warning, $errorCnt, $used)
            }

            $usedGesamt = Format-Groesse ([int64]($data.service_usage | Measure-Object -Property storage_usage -Sum).Sum)
            Write-Log ("`nSpeicherverbrauch gesamt: {0}" -f $usedGesamt)

            # --- TAGESPROTOKOLL
            Write-Log "`n--- TAGESPROTOKOLL (LETZTE $TageZurueck TAGE) ---"

            if ($logFehler) {
                Write-Log "  Protokoll konnte nicht abgerufen werden (Fehlercode $logFehlerCode)"
                continue
            }

            if (-not $geparst) {
                Write-Log "  Keine Einträge in den letzten $TageZurueck Tagen."
                continue
            }

            foreach ($tag in ($geparst | Group-Object Tag | Sort-Object Name -Descending)) {

                $erfolgSumme  = ($tag.Group | Measure-Object -Property Erfolg  -Sum).Sum
                $warnungSumme = ($tag.Group | Measure-Object -Property Warnung -Sum).Sum
                $fehlerSumme  = ($tag.Group | Measure-Object -Property Fehler  -Sum).Sum
                $auffTag      = @($tag.Group | Where-Object { $_.Auffaellig })

                Write-Log "  $($tag.Name): Erfolg $erfolgSumme, Warnung $warnungSumme, Fehler $fehlerSumme, Auffälligkeiten $($auffTag.Count) ($($tag.Count) Einträge gesamt)"

                if ($auffTag.Count -gt 0) {
                    # -- GLEICHARTIGE AUFFÄLLIGKEITEN (gleicher Fehlercode/Vorlage) ZUSAMMENFASSEN
                    $gruppen = $auffTag | Group-Object {
                        $vorlage = $_.Beschreibung -replace '\[[^\]]+\]', '[...]'
                        "$($_.ErrorCode)|$vorlage"
                    }

                    foreach ($gruppe in $gruppen) {
                        $erster = $gruppe.Group | Sort-Object Zeit | Select-Object -First 1
                        $zeitText = $erster.Zeit.ToString("dd.MM.yyyy HH:mm:ss")

                        if ($gruppe.Count -eq 1) {
                            Write-Log "    [$zeitText] $($erster.Beschreibung) (error_code=$($erster.ErrorCode))"
                        }
                        else {
                            $benutzer = $gruppe.Group | ForEach-Object {
                                if ($_.Beschreibung -match '\[([^\]]+)\]') { $matches[1] }
                            } | Select-Object -Unique
                            $anzeige = ($benutzer | Select-Object -First 3) -join ', '
                            $rest    = @($benutzer).Count - 3
                            $zusatz  = if ($rest -gt 0) { " (+$rest weitere)" } else { "" }
                            Write-Log "    [$zeitText] $($gruppe.Count)x: $($erster.Beschreibung) (error_code=$($erster.ErrorCode)) - Betroffen: $anzeige$zusatz"
                        }
                    }
                }
            }
        }

        # -- ABMELDUNG
        $logoutParams = @{ api = "SYNO.API.Auth"; version = 6; method = "logout"; session = "ActiveBackupOffice365"; _sid = $sid }
        Invoke-RestMethod -Uri $baseUrl -Method Get -Body $logoutParams -SkipCertificateCheck -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Log "STATUS          : Verbindung fehlgeschlagen - $($_.Exception.Message)"
        $erg.Notizen.Add('Verbindung fehlgeschlagen')
    }
    finally {
        $backupOk = $null
        if ($erg.Erreicht -and $erg.Pruefbar -and $erg.Tasks -gt 0) { $backupOk = [bool]$erg.AlleOk }
        if ($erg.Erreicht -and $erg.Tasks -eq 0) { $erg.Notizen.Add('keine Backup-Tasks gefunden') }
        if (-not $erg.Erreicht -and $erg.Notizen.Count -eq 0) { $erg.Notizen.Add('nicht erreicht oder Anmeldung fehlgeschlagen') }
        $ergebnisListe.Add([pscustomobject]@{
            Ziel = $NAS; Erreicht = [bool]$erg.Erreicht
            Pruefungen = $(if ($erg.Erreicht) { [pscustomobject]@{ BackupErfolgreich = $backupOk } } else { [pscustomobject]@{} })
            Werte = [pscustomobject]@{ Tasks = $erg.Tasks }
            Notiz = ($erg.Notizen -join '; ')
        })
    }
}

Write-Log "`n`nErgebnisdatei: $AusgabeDatei"

if ($Automatik) {
    Write-WtErgebnis -Skript '02.2-Backup-Synology-ActiveBackupM365' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    exit $(if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -gt 0) { 0 } else { 1 })
}

Invoke-Item -LiteralPath $AusgabeDatei