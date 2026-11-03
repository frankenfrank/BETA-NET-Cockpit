#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
    [hashtable]$AnmeldedatenJeZiel
)

Clear-Host
Write-Host ""
Write-Host "=== Wartung-05.1-Virtualisierung_Hyper-V ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Prüft zentrale Hyper-V-Komponenten (Replikation, Clusterstatus, VMs, Speicherplatz, Integrationsdienste, Snapshots) remote auf einer Liste von Hyper-V-Hosts per Invoke-Command und schreibt eine standardisierte Wartungsdatei. Hostliste wird bei Bedarf interaktiv angelegt/erweitert.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Hosts (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Gerät das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfällt die Listenpflege und die Kontoabfrage. Ohne -Ziel läuft das Skript wie bisher interaktiv.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner und der PowerShell-7-Endpunkt (PowerShell.7) auf den Zielhosts
- PowerShell Remoting (WinRM) auf allen Zielhosts aktiviert
- Ausführendes Konto (bzw. das Konto aus dem NET-COCKPIT) benötigt Admin-Rechte auf allen Zielhosts
- Hyper-V-PowerShell-Modul auf allen Zielhosts installiert
- FailoverClusters-PowerShell-Modul auf den Zielhosts installiert, falls Teil eines Clusters
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - AUSGABEORDNER (aus dem NET-COCKPIT, sonst C:\Temp)
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }
$ZielModus = (@($Ziel | Where-Object { "$_".Trim() -ne "" }).Count -gt 0)

# - KONTEN JE ZIEL (aus dem NET-COCKPIT, Spalte "Konto")
$script:AnmeldedatenHost = @{}
if ($AnmeldedatenJeZiel) {
    foreach ($k in $AnmeldedatenJeZiel.Keys) { $script:AnmeldedatenHost["$k"] = $AnmeldedatenJeZiel[$k] }
}

function Get-ZielKonto {
    param([string]$Name)
    if ($script:AnmeldedatenHost.ContainsKey($Name)) { return $script:AnmeldedatenHost[$Name] }
    return $null
}

## Konto aus dem NET-COCKPIT; ohne Konto oder ab dem 2. Versuch wird abgefragt
function Get-ZielAnmeldung {
    param([string]$Name, [string]$Meldung, [int]$Versuch = 1)
    if ($Versuch -eq 1) {
        $c = Get-ZielKonto -Name $Name
        if ($c) { return $c }
    }
    return (Get-Credential -Message $Meldung)
}


# - LOGPFAD UND DATEIEN
$Datum = Get-Date -Format "yyyyMMdd"
$LogPath = $Ausgabepfad
$Dateiname = "Wartung_${Datum}_Virtualisierung.txt"
$AusgabeDatei = "$LogPath\$Dateiname"
$HostListFile = "$LogPath\liste-Hypervisors.txt"

# - HOSTLISTE
if ($ZielModus) {
    $Serverliste = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Hosts (aus dem NET-COCKPIT):"
    $Serverliste | ForEach-Object { Write-Host " - $_" }
}
else {
    # - HOSTLISTE VERWALTEN
    if (-not (Test-Path $HostListFile)) {
        Write-Host "→ Hostliste existiert nicht und wird erstellt..."
        $ersteServer = Read-Host "Gib die ersten Servernamen ein (durch Komma getrennt)"
        $server_init = $ersteServer -split ",\s*"
        $server_init | Out-File $HostListFile -Encoding utf8
        Write-Host "→ Hostliste wurde erstellt unter $HostListFile"
    }

    Write-Host "`nZu prüfende Server:"
    Get-Content $HostListFile | ForEach-Object { Write-Host " - $_" }
    $antwort = Read-Host "`nWillst du weitere Server hinzufügen? (j/n)"
    if ($antwort -eq "j") {
        $neue = Read-Host "Neue Servernamen (durch Komma getrennt)"
        $server_neu = $neue -split ",\s*"
        Add-Content -Path $HostListFile -Value $server_neu
        Write-Host "→ Neue Server wurden hinzugefügt."
    }

    $Serverliste = Get-Content $HostListFile
}

# - AUSGABEDATEI INITIALISIEREN
Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue
"Hyper-V Wartungsprüfung – Remote-Auswertung $Datum" | Out-File $AusgabeDatei

# - REMOTE BLOCK DEFINIEREN
$RemoteBlock = {
    param($Kunde)

    $Server = $env:COMPUTERNAME
    $Datum = Get-Date -Format "yyyyMMdd"
    if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' | Out-Null }
    $TempFile = "C:\Temp\Wartungslog_HyperV_${Server}_$Datum.txt"
    Remove-Item $TempFile -ErrorAction SilentlyContinue

    Add-Content $TempFile "#WARTUNG_EVENTLOG_START"
    Add-Content $TempFile ""
    Add-Content $TempFile "#INFO:"
    Add-Content $TempFile "# Server: $Server"
Add-Content $TempFile "# Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
Add-Content $TempFile "# Diese Datei wurde automatisch im Rahmen einer proaktiven IT-Wartung erstellt."
Add-Content $TempFile "# Regeln für die Auswertung:"
Add-Content $TempFile "# 1. Alle enthaltenen Ereignisse technisch bewerten."
Add-Content $TempFile "# 2. Kritische Ereignisse zuerst, unkritische danach."
Add-Content $TempFile "# 3. Ausgabe ausschließlich im Codeblock, exakt im Format für das Feld 'Server-Notizen':"
Add-Content $TempFile "# 4. Keine Kommentare, keine Platzhalter, keine Übergänge."
Add-Content $TempFile ""
    Add-Content $TempFile "=== BEGINN DER HYPER-V-WARTUNGSDATEN ==="
    Add-Content $TempFile ""

    Add-Content $TempFile "===== 1. Hyper-V Replikation ====="
    try {
        $replications = Get-VMReplication | Select-Object VMName, State, Health, LastReplicationTime, ReplicationMode
        if ($replications) { $replications | Format-Table -AutoSize | Out-String | Add-Content $TempFile }
        else { Add-Content $TempFile "Keine Replikationen konfiguriert." }
    } catch { Add-Content $TempFile "Fehler beim Abruf der Replikationsdaten: $($_.Exception.Message)" }

    Add-Content $TempFile ""
    Add-Content $TempFile "===== 2. Clusterstatus ====="
    try {
        if (Get-Command Get-Cluster -ErrorAction SilentlyContinue) {
            $cluster = Get-Cluster
            $groups = Get-ClusterGroup | Select-Object Name, State, OwnerNode
            Add-Content $TempFile "Clustername: $($cluster.Name)"
            $groups | Format-Table -AutoSize | Out-String | Add-Content $TempFile
        } else {
            Add-Content $TempFile "Kein Cluster erkannt oder Cmdlet nicht verfügbar."
        }
    } catch { Add-Content $TempFile "Fehler beim Abruf des Clusterstatus: $($_.Exception.Message)" }

    Add-Content $TempFile ""
    Add-Content $TempFile "===== 3. Virtuelle Maschinen ====="
    try {
        $vms = Get-VM | Select-Object Name, State, Uptime, Status
        if ($vms) { $vms | Format-Table -AutoSize | Out-String | Add-Content $TempFile }
        else { Add-Content $TempFile "Keine VMs gefunden." }
    } catch { Add-Content $TempFile "Fehler beim Abruf der VM-Daten: $($_.Exception.Message)" }

    Add-Content $TempFile ""
    Add-Content $TempFile "===== 4. Speicherplatz ====="
    try {
        $volumes = Get-Volume | Where-Object { $_.DriveLetter } | Select-Object DriveLetter, FileSystemLabel, SizeRemaining, Size, @{Name="FreePercent";Expression={[math]::Round(($_.SizeRemaining / $_.Size) * 100,2)}}
        $volumes | Format-Table -AutoSize | Out-String | Add-Content $TempFile
    } catch { Add-Content $TempFile "Fehler beim Abruf der Speicherinformationen: $($_.Exception.Message)" }

    Add-Content $TempFile ""
    Add-Content $TempFile "===== 5. Integrationsdienste ====="
    try {
        $integrations = Get-VM | ForEach-Object {
            $vm = $_.Name
            Get-VMIntegrationService -VMName $vm | Select-Object VMName, Name, PrimaryStatusDescription
        }
        if ($integrations) { $integrations | Format-Table -AutoSize | Out-String | Add-Content $TempFile }
        else { Add-Content $TempFile "Keine Integrationsdienste gefunden." }
    } catch { Add-Content $TempFile "Fehler beim Abruf der Integrationsdienste: $($_.Exception.Message)" }

    Add-Content $TempFile ""
    Add-Content $TempFile "===== 6. Snapshots / Prüfpunkte ====="
    try {
        $snapshots = Get-VM | ForEach-Object {
            $vm = $_.Name
            Get-VMSnapshot -VMName $vm -ErrorAction SilentlyContinue | Select-Object VMName, Name, CreationTime
        }
        if ($snapshots) { $snapshots | Format-Table -AutoSize | Out-String | Add-Content $TempFile }
        else { Add-Content $TempFile "Keine Snapshots vorhanden." }
    } catch { Add-Content $TempFile "Fehler beim Abruf der Snapshot-Informationen: $($_.Exception.Message)" }

    Add-Content $TempFile ""
    Add-Content $TempFile "=== ENDE DER HYPER-V-WARTUNGSDATEN ==="
    Add-Content $TempFile "#WARTUNG_EVENTLOG_ENDE"

    Get-Content $TempFile
}

# - REMOTE AUSFÜHRUNG AUF ALLEN HOSTS
foreach ($srv in $Serverliste) {
    Write-Host "`n→ Bearbeite $srv ..." -ForegroundColor Cyan
    try {
        $result = $null
        for ($versuch = 1; $versuch -le 2 -and -not $result; $versuch++) {
            $cp = @{}
            $c = Get-ZielKonto -Name $srv
            if ($c) { $cp.Credential = $c }
            try {
                $result = Invoke-Command -ComputerName $srv @cp -ConfigurationName 'PowerShell.7' -ScriptBlock $RemoteBlock -ArgumentList $null -ErrorAction Stop
            }
            catch {
                $anmeldung = $_.Exception.Message -match "Zugriff verweigert|Access is denied|0x80070005|Anmeldefehler|logon failure|Benutzername oder Kennwort|user name or password"
                if ($versuch -eq 1 -and $anmeldung) {
                    Write-Host "   Anmeldung an $srv fehlgeschlagen - Zugangsdaten abfragen" -ForegroundColor Yellow
                    $neu = Get-Credential -Message "Zugangsdaten für $srv"
                    if ($neu) { $script:AnmeldedatenHost[$srv] = $neu; continue }
                }
                throw
            }
        }
        Add-Content $AusgabeDatei "`n===== $srv =====`n"
        Add-Content $AusgabeDatei $result
        Write-Host "   ✓ Erfolgreich abgefragt" -ForegroundColor Green
    } catch {
        Write-Host "Fehler bei ${srv}: $($_.Exception.Message)" -ForegroundColor Red
        Add-Content $AusgabeDatei "`n===== $srv =====`nFehler bei der Remote-Abfrage: $($_.Exception.Message)`n"
    }
}

Write-Host "`nFertig. Ergebnisse in $AusgabeDatei" -ForegroundColor Green
Start-Process notepad.exe $AusgabeDatei