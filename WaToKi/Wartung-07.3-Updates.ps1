#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
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
Write-Host "=== Wartung-07.3-Updates ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Fragt von einer Liste virtueller Server per CIM die aktuelle Windows-Version/Build und die letzten 5 installierten Updates ab und schreibt eine formatierte Datei für die Wartungsauswertung.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Server (-Ziel) und den Ausgabeordner (-Ausgabeordner). Dann entfällt die Serverliste. Die Abfrage läuft mit dem angemeldeten Windows-Konto. Geprüft werden nur die Server-Updates (installierte Windows-Updates), nicht die Clients.

VORAUSSETZUNGEN
- Auf jedem Zielserver einmalig ausführen:
  New-NetFirewallRule -DisplayName "Allow Remote EventLog RPC" -Direction Inbound -Protocol TCP -LocalPort 135 -Action Allow
  New-NetFirewallRule -DisplayName "Allow Remote EventLog RPC Dynamic" -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow
- Ausführendes Konto benötigt Admin-Rechte auf allen Zielservern (CIM/WMI)
- Alternativ ohne Firewall-Öffnung: Skript direkt auf dem jeweiligen Server selbst ausführen: irm script.frankenserver.net/Wartung-07.3-Updates.ps1 | iex
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
if (-not $Automatik) {
    Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}

# START
$Datum = Get-Date -Format "yyyyMMdd"
$Dateiname = "Wartung_${Datum}_UpdatesVirtuelleServer.txt"
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname
$ZielModus = (@($Ziel | Where-Object { "$_".Trim() -ne "" }).Count -gt 0)
if ($Automatik -and -not $ZielModus) {
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (Server) nötig." -ForegroundColor Red
    exit 1
}
$ergebnisListe = [System.Collections.Generic.List[object]]::new()
$ServerListFile = "C:\Temp\liste-virtuelle_server.txt"

# - SERVERLISTE VERWALTEN
if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }
if ($ZielModus) {
    $Serverliste = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Server (aus dem NET-COCKPIT):"
    $Serverliste | ForEach-Object { Write-Host " - $_" }
}
else {
    if (-not (Test-Path $ServerListFile)) {
        Write-Host "→ Serverliste existiert nicht und wird erstellt..."
        $ersteServer = Read-Host "Gib die ersten Servernamen ein (durch Komma getrennt)"
        $server_init = $ersteServer -split ",\s*"
        $server_init | Out-File $ServerListFile -Encoding utf8
        Write-Host "→ Serverliste wurde erstellt unter $ServerListFile"
    }
    Write-Host "`nZu prüfende Server nach ${ServerListFile} :"
    Get-Content $ServerListFile | ForEach-Object { Write-Host " - $_" }
    $antwort = Read-Host "`nWillst du weitere Server hinzufügen? (j/n)"
    if ($antwort -eq "j") {
        $neue = Read-Host "Neue Servernamen (durch Komma getrennt)"
        $server_neu = $neue -split ",\s*"
        Add-Content -Path $ServerListFile -Value $server_neu
        Write-Host "→ Neue Server wurden hinzugefügt."
    }

    $Serverliste = Get-Content $ServerListFile
}

# Alte Datei löschen, falls vorhanden
Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue

# Kopfbereich
Add-Content $AusgabeDatei "#WARTUNG_UPDATES_START"
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "#INFO:"
Add-Content $AusgabeDatei "# Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
Add-Content $AusgabeDatei "# Diese Datei wurde automatisch im Rahmen einer proaktiven IT-Wartung erstellt."
Add-Content $AusgabeDatei "# Regeln für die Auswertung:"
Add-Content $AusgabeDatei "# 1. Je Server bewerten, ob die Updates aktuell sind (deutlich älter als 30-60 Tage = auffällig)."
Add-Content $AusgabeDatei "# 2. Windows-Version/Build vermerken und auffällige Abweichungen (z.B. veraltete Version) benennen."
Add-Content $AusgabeDatei "# 3. Ausgabe ausschließlich im Codeblock, exakt im Format für das Feld 'Server-Notizen':"
Add-Content $AusgabeDatei "#    - SERVERNAME:"
Add-Content $AusgabeDatei "#    -- OS: <Version/Build> - <Bewertung>"
Add-Content $AusgabeDatei "#    -- Letzte Updates: <KB, Datum, ...> - <Bewertung>"
Add-Content $AusgabeDatei "# 4. Keine Kommentare, keine Platzhalter, keine Übergänge."
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "=== BEGINN DER UPDATE-DATEN ==="
Add-Content $AusgabeDatei ""

Write-Host " "
Write-Host " "

foreach ($Server in $Serverliste) {
    Write-Host "----- $Server -----" -ForegroundColor Cyan

    Add-Content $AusgabeDatei "- ${Server}:"

    $osFehler = $null
    $qfeFehler = $null
    $os = $null
    $updates = $null

    try {
        $os = Get-CimInstance -ComputerName $Server -ClassName Win32_OperatingSystem -ErrorAction Stop
    }
    catch {
        $osFehler = "-- Fehler beim Abruf der OS-Version: $($_.Exception.Message)"
    }

    if ($os) {
        $installDatum = $os.InstallDate
        $osZeile = "-- OS: $($os.Caption), Version $($os.Version), Build $($os.BuildNumber)"
        if ($installDatum) {
            $osZeile += " (installiert: $("{0:dd.MM.yyyy}" -f $installDatum))"
        }
        Add-Content $AusgabeDatei $osZeile
        Write-Host "  $($os.Caption), Build $($os.BuildNumber)" -ForegroundColor DarkCyan
    }
    elseif ($osFehler) {
        Add-Content $AusgabeDatei $osFehler
    }

    try {
        $updates = Get-CimInstance -ComputerName $Server -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 5
    }
    catch {
        $qfeFehler = "-- Fehler beim Abruf der Updates: $($_.Exception.Message)"
    }

    if ($updates) {
        foreach ($u in $updates) {
            Add-Content $AusgabeDatei ("-- {0:dd.MM.yyyy}, {1}: {2}" -f $u.InstalledOn, $u.HotFixID, $u.Description)
        }
        Write-Host "  Letztes Update: $("{0:dd.MM.yyyy}" -f $updates[0].InstalledOn), $($updates[0].HotFixID)" -ForegroundColor DarkCyan
    }
    elseif ($qfeFehler) {
        Add-Content $AusgabeDatei $qfeFehler
    }
    else {
        Add-Content $AusgabeDatei "-- Keine installierten Updates gefunden"
    }

    Add-Content $AusgabeDatei ""

    ## Ergebnis für die Checkliste (Haken nur, wenn das neueste Update höchstens 60 Tage alt ist; sonst bzw. ohne Abruf kein Haken)
    $pr = [ordered]@{}
    $werte = [ordered]@{}
    $notiz = ''
    if ($os) {
        $werte['Betriebssystem'] = [string]$os.Caption
        $werte['Build'] = [string]$os.BuildNumber
    }
    if ($updates) {
        $letztes = ($updates | Select-Object -First 1)
        $alterTage = [int]((Get-Date) - $letztes.InstalledOn).TotalDays
        $werte['LetztesUpdate'] = ([datetime]$letztes.InstalledOn).ToString('yyyy-MM-dd')
        $werte['LetztesUpdateKB'] = [string]$letztes.HotFixID
        $werte['Updates'] = @($updates | ForEach-Object { [pscustomobject]@{ KB = [string]$_.HotFixID; Datum = ([datetime]$_.InstalledOn).ToString('yyyy-MM-dd') } })
        $pr['WindowsUpdates'] = ($alterTage -le 60)
        $notiz = $(if ($alterTage -le 60) { "Letztes Update vor $alterTage Tagen" } else { "Letztes Update vor $alterTage Tagen (auffällig)" })
    }
    $ergebnisListe.Add([pscustomobject]@{
        Ziel       = $Server
        Erreicht   = [bool]($os -or $updates)
        Pruefungen = [pscustomobject]$pr
        Werte      = [pscustomobject]$werte
        Notiz      = $(if ($os -or $updates) { $notiz } else { 'Abruf per CIM fehlgeschlagen' })
    })
}

# Fußbereich
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "=== ENDE DER UPDATE-DATEN ==="
Add-Content $AusgabeDatei "#WARTUNG_UPDATES_ENDE"

Write-Host ""
Write-Host "Die Datei wurde gespeichert in $AusgabeDatei" -ForegroundColor Green
Write-Host ""
if ($Automatik) {
    Get-Content -LiteralPath $AusgabeDatei | Write-Host
    Write-WtErgebnis -Skript '07.3-Updates' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}

Start-Process notepad.exe $AusgabeDatei