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
Write-Host "=== Wartung-05.1-Virtualisierung_ESXi ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Prüft zentrale VMware-Komponenten (Hosts, Cluster, VMs, Datastores, Snapshots) über eine vCenter-Verbindung oder direkt verbundene ESXi-Hosts und schreibt eine standardisierte Wartungsdatei. Die Ausgabe ist für eine technische Auswertung vorbereitet.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten vCenter bzw. ESXi-Hosts (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Gerät das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfällt die Listenpflege und die Kontoabfrage. Ohne -Ziel läuft das Skript wie bisher interaktiv. Ob vCenter oder ESXi vorliegt, wird nach der Verbindung automatisch erkannt.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Netzwerkzugriff (HTTPS) vom ausführenden Rechner zum vCenter bzw. zu den ESXi-Hosts
- Gültige Zugangsdaten (aus dem NET-COCKPIT je Gerät, sonst interaktiv abgefragt)
- Internetzugriff zur PowerShell Gallery, falls das Modul VCF.PowerCLI noch nicht installiert ist (wird sonst automatisch installiert)
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
$ZielModus = (@($Ziel | Where-Object { "$_".Trim() -ne "" }).Count -gt 0)
if ($Automatik -and -not $ZielModus) {
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (vCenter bzw. ESXi-Hosts) nötig." -ForegroundColor Red
    exit 1
}

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


# - VERBINDUNGSTYP
$Datum = Get-Date -Format "yyyyMMdd"
$Kunde = $null # optional befüllen
if ($ZielModus) {
    ## aus dem NET-COCKPIT: vCenter oder ESXi wird nach der Verbindung erkannt
    $Modus = $null
    $VerbindungsTyp = "vCenter/ESXi"
    $DefaultUser = ""
}
else {
    # - VERBINDUNGSTYP AUSWÄHLEN
    Write-Host ""
    Write-Host "Verbindungstyp wählen:" -ForegroundColor Yellow
    Write-Host "  1 = vCenter"
    Write-Host "  2 = Einzelne ESXi-Hosts (ohne vCenter)"
    $Modus = $null
    while ($Modus -notin @("1", "2")) {
        $Modus = Read-Host "Auswahl (1/2)"
    }
    $VerbindungsTyp = if ($Modus -eq "1") { "vCenter" } else { "ESXi" }
    $DefaultUser = if ($Modus -eq "1") { "administrator@vsphere.local" } else { "root" }
}

# - ZIELSERVER
if ($ZielModus) {
    $VCServer = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Server (aus dem NET-COCKPIT):"
    $VCServer | ForEach-Object { Write-Host " - $_" }
}
else {
    # - ZIELSERVER ABFRAGEN (HOSTLISTE VERWALTEN)
    $HostListFile = "C:\Temp\liste-$VerbindungsTyp.txt"
    if (-not (Test-Path "C:\Temp")) { New-Item -Path "C:\Temp" -ItemType Directory | Out-Null }

    if (-not (Test-Path $HostListFile)) {
        Write-Host "→ Hostliste existiert nicht und wird erstellt..."
        $ersteServer = Read-Host "Gib die ersten Server-Adressen ein ($VerbindungsTyp, durch Komma getrennt)"
        $server_init = $ersteServer -split ",\s*" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $server_init | Out-File $HostListFile -Encoding utf8
        Write-Host "→ Hostliste wurde erstellt unter $HostListFile"
    }

    Write-Host "`nZu prüfende Server ($VerbindungsTyp):"
    Get-Content $HostListFile | ForEach-Object { Write-Host " - $_" }
    $antwort = Read-Host "`nWillst du weitere Server hinzufügen? (j/n)"
    if ($antwort -eq "j") {
        $neue = Read-Host "Neue Server-Adressen (durch Komma getrennt)"
        $server_neu = $neue -split ",\s*" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        Add-Content -Path $HostListFile -Value $server_neu
        Write-Host "→ Neue Server wurden hinzugefügt."
    }

    $VCServer = Get-Content $HostListFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if (-not $VCServer -or $VCServer.Count -eq 0) {
        Write-Host "Keine Server in der Hostliste ($HostListFile)." -ForegroundColor Red
        Read-Host "Mit Enter beenden"
        exit
    }
}

# - POWERCLI LADEN / INSTALLIEREN
if (-not (Get-Module -ListAvailable -Name VCF.PowerCLI)) {
    Write-Host "VCF.PowerCLI wird installiert..." -ForegroundColor Yellow
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    Install-Module -Name VCF.PowerCLI -Force -AllowClobber -SkipPublisherCheck -Scope CurrentUser
}
Import-Module VCF.PowerCLI
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Multiple -Scope Session -Confirm:$false | Out-Null

# - ANMELDUNG (JE SERVER, MAX. 3 VERSUCHE)
$MaxVersuche = 3
$VerbundeneServer = @()

foreach ($ZielServer in $VCServer) {
    $Versuch = 0
    $Verbunden = $false
    while (-not $Verbunden -and $Versuch -lt $MaxVersuche) {
        $Versuch++
        $Cred = $null
        if ($Versuch -eq 1) { $Cred = Get-ZielKonto -Name $ZielServer }
        if (-not $Cred -and $Automatik) { break }
        if (-not $Cred) {
            $userParam = if ($DefaultUser) { @{ UserName = $DefaultUser } } else { @{} }
            $Cred = Get-Credential @userParam -Message "Anmeldung an $ZielServer (Versuch $Versuch von $MaxVersuche)"
        }
        if (-not $Cred) { break }
        try {
            Connect-VIServer -Server $ZielServer -Credential $Cred -ErrorAction Stop | Out-Null
            $Verbunden = $true
            $VerbundeneServer += $ZielServer
        } catch {
            Write-Host "Anmeldung an $ZielServer fehlgeschlagen (Versuch $Versuch von $MaxVersuche): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if (-not $Verbunden) {
        Write-Host "Verbindung zu $ZielServer nach $MaxVersuche Versuchen übersprungen." -ForegroundColor Yellow
    }
}

if ($VerbundeneServer.Count -eq 0) {
    Write-Host ""
    Write-Host "Keine Verbindung zu einem Server möglich. Script wird beendet." -ForegroundColor Red
    if ($Automatik) {
        Write-WtErgebnis -Skript '05.1-Virtualisierung_ESXi' -Ordner $Ausgabepfad -Ergebnisse @($VCServer | ForEach-Object { [pscustomobject]@{ Ziel = $_; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Verbindung oder Anmeldung fehlgeschlagen' } })
        exit 1
    }
    Read-Host "Mit Enter beenden"
    exit
}

# vCenter oder ESXi erkennen (nur aus dem NET-COCKPIT; sonst hat der Benutzer gewählt)
if ($ZielModus) {
    $istVCenter = @($global:DefaultVIServers | Where-Object { $_.ProductLine -eq 'vpx' }).Count -gt 0
    $VerbindungsTyp = if ($istVCenter) { "vCenter" } else { "ESXi" }
}

$Server = $VerbundeneServer -join "_"
$Dateiname = "Wartung_${Datum}_ESXi.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname

# - HOSTNAMEN JE SERVER ERMITTELN
$HostNamen = @{}
foreach ($srv in $VerbundeneServer) {
    try {
        $vmhost = Get-VMHost -Server $srv | Select-Object -First 1
        $dns = $vmhost.ExtensionData.Config.Network.DnsConfig
        if ($dns -and $dns.HostName) {
            $HostNamen[$srv] = if ($dns.DomainName) { "$($dns.HostName).$($dns.DomainName)" } else { $dns.HostName }
        } elseif ($vmhost) {
            $HostNamen[$srv] = $vmhost.Name
        } else {
            $HostNamen[$srv] = $srv
        }
    } catch {
        $HostNamen[$srv] = $srv
    }
}

# - ALTE DATEI LÖSCHEN
Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue

# - DATEIKOPF
Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_START"
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "#INFO:"
Add-Content $AusgabeDatei "# Kunde: $Kunde"
Add-Content $AusgabeDatei "# Verbindungstyp: $VerbindungsTyp"
Add-Content $AusgabeDatei "# Server: $Server"
Add-Content $AusgabeDatei "# Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
Add-Content $AusgabeDatei "# Diese Datei wurde automatisch im Rahmen einer proaktiven IT-Wartung erstellt."
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "=== BEGINN DER ESXI-WARTUNGSDATEN ==="
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "# ERKLÄRUNG:"
Add-Content $AusgabeDatei "# Die folgenden Abschnitte enthalten Rohdaten einzelner Prüfungen."
Add-Content $AusgabeDatei "# eine technische Bewertung ('einwandfrei', 'Fehler erkannt', 'nicht zutreffend')"
Add-Content $AusgabeDatei "# als zusammenfassende Wartungsnotiz erzeugen."
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "# ZIEL DER AUSWERTUNG:"
Add-Content $AusgabeDatei "# Die Ausgabe muss exakt im folgenden Format erfolgen:"
Add-Content $AusgabeDatei "# - <Servername>:"
Add-Content $AusgabeDatei "# -- <Kurzbeschreibung der Prüfung + Bewertung>"
Add-Content $AusgabeDatei "# Beispiel:"
Add-Content $AusgabeDatei "# - ESX01:"
Add-Content $AusgabeDatei "# -- Alle Hosts verbunden - einwandfrei."
Add-Content $AusgabeDatei "# -- Alle VMs im normalen Betrieb -einwandfrei."
Add-Content $AusgabeDatei "# -- Datastores mit ausreichend freiem Speicher -unkritisch."
Add-Content $AusgabeDatei "# -- Keine Snapshots vorhanden -unkritisch."
Add-Content $AusgabeDatei "# -- VMware Tools in allen VMs aktuell -einwandfrei."
Add-Content $AusgabeDatei "# WICHTIG: Die oberste Kategorie 'Virtualisierungsumgebung' darf NICHT erscheinen."
Add-Content $AusgabeDatei "# Nur der Servername mit den untergeordneten Bewertungspunkten ist auszugeben."
Add-Content $AusgabeDatei ""

# - 1. HOSTSTATUS
Add-Content $AusgabeDatei "===== 1. ESXi-Hosts ====="
try {
    $hosts = Get-VMHost | Select-Object Name, ConnectionState, PowerState, Version, Build, @{Name="CPU";Expression={$_.CpuUsageMhz}}, @{Name="MemoryGB";Expression={[math]::Round($_.MemoryUsageGB,2)}}
    if ($hosts) {
        $hosts | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
    } else {
        Add-Content $AusgabeDatei "Keine Hosts gefunden."
    }
} catch {
    Add-Content $AusgabeDatei "Fehler beim Abruf der Hostdaten: $($_.Exception.Message)"
}

# - 2. CLUSTERSTATUS
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "===== 2. Clusterstatus ====="
if ($VerbindungsTyp -eq "ESXi") {
    Add-Content $AusgabeDatei "Nicht zutreffend (Einzel-ESXi ohne vCenter)."
} else {
    try {
        $clusters = Get-Cluster | Select-Object Name, HAEnabled, DrsEnabled, @{Name="TotalHosts";Expression={($_ | Get-VMHost).Count}}
        if ($clusters) {
            $clusters | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
        } else {
            Add-Content $AusgabeDatei "Kein Cluster erkannt oder Cmdlet nicht verfügbar."
        }
    } catch {
        Add-Content $AusgabeDatei "Fehler beim Abruf des Clusterstatus: $($_.Exception.Message)"
    }
}

# - 3. VIRTUELLE MASCHINEN
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "===== 3. Virtuelle Maschinen ====="
foreach ($srv in $VerbundeneServer) {
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "--- $($HostNamen[$srv]) - $srv ---"
    try {
        $vms = Get-VM -Server $srv | Select-Object Name, PowerState, @{Name="ToolsStatus";Expression={$_.ExtensionData.Guest.ToolsStatus}}, @{Name="ToolsVersion";Expression={$_.ExtensionData.Guest.ToolsVersionStatus2}}
        if ($vms) {
            $vms | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
        } else {
            Add-Content $AusgabeDatei "Keine VMs gefunden."
        }
    } catch {
        Add-Content $AusgabeDatei "Fehler beim Abruf der VM-Daten: $($_.Exception.Message)"
    }
}

# - 4. DATASTORES
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "===== 4. Datastores ====="
foreach ($srv in $VerbundeneServer) {
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "--- $($HostNamen[$srv]) - $srv ---"
    try {
        $datastores = Get-Datastore -Server $srv | Select-Object Name, @{Name="Kapazität(GB)";Expression={[math]::Round($_.CapacityGB,2)}}, @{Name="Frei(GB)";Expression={[math]::Round($_.FreeSpaceGB,2)}}, @{Name="Frei(%)";Expression={[math]::Round(($_.FreeSpaceGB / $_.CapacityGB) * 100,2)}}
        if ($datastores) {
            $datastores | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
        } else {
            Add-Content $AusgabeDatei "Keine Datastores gefunden."
        }
    } catch {
        Add-Content $AusgabeDatei "Fehler beim Abruf der Datastore-Informationen: $($_.Exception.Message)"
    }
}

# - 5. SNAPSHOTS
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "===== 5. Snapshots ====="
try {
    $snapshots = Get-VM | Get-Snapshot -ErrorAction SilentlyContinue | Select-Object VM, Name, Created
    if ($snapshots) {
        $snapshots | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
    } else {
        Add-Content $AusgabeDatei "Keine Snapshots vorhanden."
    }
} catch {
    Add-Content $AusgabeDatei "Fehler beim Abruf der Snapshot-Informationen: $($_.Exception.Message)"
}

# - ERGEBNIS FÜR DIE CHECKLISTE (je verbundenem Server; Haken = geprüft und in Ordnung; nur was ermittelt wurde, steht drin)
$ergebnisListe = [System.Collections.Generic.List[object]]::new()
foreach ($srv in $VCServer) {
    if ($srv -notin $VerbundeneServer) {
        $ergebnisListe.Add([pscustomobject]@{ Ziel = $srv; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Verbindung oder Anmeldung fehlgeschlagen' })
        continue
    }
    $pr = [ordered]@{}
    $probleme = @()
    $werte = [ordered]@{ Hostname = [string]$HostNamen[$srv] }
    try {
        $hostsSrv = @(Get-VMHost -Server $srv -ErrorAction Stop)
        $pr['HostsVerbunden'] = (@($hostsSrv | Where-Object { [string]$_.ConnectionState -ne 'Connected' }).Count -eq 0)
        if (-not $pr['HostsVerbunden']) { $probleme += 'Host nicht verbunden' }
    } catch { }
    try {
        $vmsSrv = @(Get-VM -Server $srv -ErrorAction Stop)
        $nichtAn = @($vmsSrv | Where-Object { [string]$_.PowerState -ne 'PoweredOn' } | ForEach-Object { [string]$_.Name })
        $pr['VmsLaufen'] = ($nichtAn.Count -eq 0)
        if ($nichtAn.Count -gt 0) { $probleme += "VMs nicht eingeschaltet: $($nichtAn -join ', ')" }
        $toolsFehler = @($vmsSrv | Where-Object { [string]$_.PowerState -eq 'PoweredOn' -and [string]$_.ExtensionData.Guest.ToolsStatus -ne 'toolsOk' } | ForEach-Object { [string]$_.Name })
        $pr['VmwareToolsOk'] = ($toolsFehler.Count -eq 0)
        if ($toolsFehler.Count -gt 0) { $probleme += "VMware Tools auffällig: $($toolsFehler -join ', ')" }
        $werte['VmsGesamt'] = $vmsSrv.Count
        $snapSrv = @($vmsSrv | Get-Snapshot -ErrorAction SilentlyContinue)
        $pr['KeineSnapshots'] = ($snapSrv.Count -eq 0)
        if ($snapSrv.Count -gt 0) { $probleme += "Snapshots vorhanden: $(@($snapSrv | ForEach-Object { "$($_.VM): $($_.Name)" }) -join ', ')" }
    } catch { }
    try {
        $dsSrv = @(Get-Datastore -Server $srv -ErrorAction Stop)
        $werte['Speicherplatz'] = @($dsSrv | ForEach-Object { [pscustomobject]@{ Laufwerk = [string]$_.Name; FreiGB = [math]::Round($_.FreeSpaceGB, 1); GroesseGB = [math]::Round($_.CapacityGB, 1); FreiProzent = $(if ($_.CapacityGB -gt 0) { [math]::Round($_.FreeSpaceGB / $_.CapacityGB * 100, 1) } else { 0 }) } })
        $pr['SpeicherplatzOk'] = (@($werte['Speicherplatz'] | Where-Object { $_.FreiProzent -lt 10 }).Count -eq 0)
        if (-not $pr['SpeicherplatzOk']) { $probleme += 'Datastore unter 10 % frei' }
    } catch { }
    $ergebnisListe.Add([pscustomobject]@{ Ziel = $srv; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = ($probleme -join '; ') })
}

# - TRENNUNG UND ABSCHLUSS
Disconnect-VIServer * -Confirm:$false | Out-Null
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "=== ENDE DER ESXI-WARTUNGSDATEN ==="
Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_ENDE"

Write-Host ""
Write-Host "Die Datei wurde gespeichert in $AusgabeDatei" -ForegroundColor Green
Write-Host ""

if ($Automatik) {
    Write-WtErgebnis -Skript '05.1-Virtualisierung_ESXi' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    exit 0
}

Start-Process notepad.exe $AusgabeDatei