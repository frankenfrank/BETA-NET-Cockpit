#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string]$Ziel,
    [string]$Ausgabeordner,
    [pscredential]$Anmeldedaten
)

Clear-Host
Write-Host ""
Write-Host "=== Wartung-05.1-Virtualisierung_vCenter ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Prüft zentrale VMware-Komponenten (Hosts, Cluster, VMs, Datastores, Snapshots) über eine vCenter-Verbindung und schreibt eine standardisierte Wartungsdatei. Die Ausgabe ist für eine technische Auswertung vorbereitet.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript das vCenter (-Ziel), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten). Dann entfallen die Abfragen von Adresse und Zugangsdaten. Wird das Konto abgelehnt, fragt das Skript (bis zu 3 Versuche) nach.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Netzwerkzugriff (HTTPS) vom ausführenden Rechner zum vCenter
- Gültige vCenter-Zugangsdaten (aus dem NET-COCKPIT, sonst interaktiv abgefragt)
- Internetzugriff zur PowerShell Gallery, falls das Modul VMware.PowerCLI noch nicht installiert ist (wird sonst automatisch installiert)
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - AUSGABEORDNER (aus dem NET-COCKPIT, sonst C:\Temp)
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }


# - INITIALISIERUNG
$Server = "vCenter"
$Datum = Get-Date -Format "yyyyMMdd"
$Dateiname = "Wartung_${Datum}_ESXi_${Server}.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname
$Kunde = $null # optional befüllen

# - ALTE DATEI LÖSCHEN
Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue

# - POWERCLI LADEN / INSTALLIEREN
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Host "VMware PowerCLI wird installiert..." -ForegroundColor Yellow
    Install-Module -Name VMware.PowerCLI -Force -AllowClobber
}
Import-Module VMware.PowerCLI
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# - ANMELDUNG AN VCENTER
$DefaultUser = "administrator@vsphere.local"
$VCServer = if ([string]::IsNullOrWhiteSpace($Ziel)) { Read-Host "vCenter-Adresse eingeben (z. B. 192.168.30.250)" } else { $Ziel.Trim() }
if ([string]::IsNullOrWhiteSpace($VCServer)) { $VCServer = "192.168.30.250" }

$Cred = $Anmeldedaten
$verbunden = $false
for ($versuch = 1; $versuch -le 3 -and -not $verbunden; $versuch++) {
    if ($versuch -gt 1 -or -not $Cred) {
        $Cred = Get-Credential -UserName $DefaultUser -Message "Anmeldung am vCenter $VCServer (Versuch $versuch von 3)"
    }
    if (-not $Cred) { break }
    try {
        Connect-VIServer -Server $VCServer -Credential $Cred -ErrorAction Stop | Out-Null
        $verbunden = $true
    } catch {
        Write-Host "Fehler beim Verbinden mit dem vCenter: $($_.Exception.Message)" -ForegroundColor Red
    }
}
if (-not $verbunden) { exit }

# - DATEIKOPF
Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_START"
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "#INFO:"
Add-Content $AusgabeDatei "# Kunde: $Kunde"
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

# - 3. VIRTUELLE MASCHINEN
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "===== 3. Virtuelle Maschinen ====="
try {
    $vms = Get-VM | Select-Object Name, PowerState, VMHost, @{Name="ToolsStatus";Expression={$_.ExtensionData.Guest.ToolsStatus}}, @{Name="ToolsVersion";Expression={$_.ExtensionData.Guest.ToolsVersionStatus2}}
    if ($vms) {
        $vms | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
    } else {
        Add-Content $AusgabeDatei "Keine VMs gefunden."
    }
} catch {
    Add-Content $AusgabeDatei "Fehler beim Abruf der VM-Daten: $($_.Exception.Message)"
}

# - 4. DATASTORES
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "===== 4. Datastores ====="
try {
    $datastores = Get-Datastore | Select-Object Name, @{Name="Kapazität(GB)";Expression={[math]::Round($_.CapacityGB,2)}}, @{Name="Frei(GB)";Expression={[math]::Round($_.FreeSpaceGB,2)}}, @{Name="Frei(%)";Expression={[math]::Round(($_.FreeSpaceGB / $_.CapacityGB) * 100,2)}}
    if ($datastores) {
        $datastores | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
    } else {
        Add-Content $AusgabeDatei "Keine Datastores gefunden."
    }
} catch {
    Add-Content $AusgabeDatei "Fehler beim Abruf der Datastore-Informationen: $($_.Exception.Message)"
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

# - TRENNUNG UND ABSCHLUSS
Disconnect-VIServer * -Confirm:$false | Out-Null
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "=== ENDE DER ESXI-WARTUNGSDATEN ==="
Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_ENDE"

Write-Host ""
Write-Host "Die Datei wurde gespeichert in $AusgabeDatei" -ForegroundColor Green
Write-Host ""
Start-Process notepad.exe $AusgabeDatei