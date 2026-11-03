#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
    [hashtable]$AnmeldedatenJeZiel
)

Clear-Host
Write-Host ""
Write-Host "=== Wartung-03.2-ServerNASProtokolle ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Liest Application-/System-Eventlogs (plus rollenspezifische Zusatzlogs wie Hyper-V, AD, DNS, DHCP, RDS, Druck, Zertifikatsdienste, Dateiserver) der letzten 30 Tage von einer Liste von Hyper-V-Hosts aus, fasst wiederkehrende Ereignisse zusammen und schreibt eine formatierte Datei für die Wartungsauswertung. Zusätzlich werden je Host Speicherplatz (lokale Partitionen), Betriebssystemversion/-BuildNumber und nicht gestartete Autostart-Dienste ausgegeben. Alle Daten je Host (Speicherplatz, OS, Dienste, Rollen) werden über eine einzige CIM-Session pro Host abgerufen. Hostliste wird bei Bedarf interaktiv angelegt/erweitert.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Hosts (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Host das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfallen Hostliste und Kontoabfrage. Ohne -Ziel wird wie bisher eine Hostliste (C:\Temp\liste-Hypervisors.txt) verwendet und interaktiv gepflegt.

ANMELDEDATEN
- Aus dem NET-COCKPIT bekommt jeder Host sein eigenes Konto; Hosts ohne Konto nutzen das aktuelle Konto
- Ohne NET-COCKPIT kann optional ein anderes Konto als das aktuelle abgefragt werden (z. B. wenn das Script von einer VM ausgeführt wird, die nicht in der Domäne des Kunden ist)
- Vor der Auswertung wird jeder Host vorab geprüft (Port 135 + CIM-Anmeldung)
- Bei fehlgeschlagener Anmeldung stoppt die Prüfung für dieses Konto sofort, es wird kein weiterer Host mit den falschen Anmeldedaten angefragt (Schutz vor Kontosperrung); Hosts mit anderen Konten werden weiter geprüft. Danach können die Anmeldedaten neu eingegeben werden
- Nicht erreichbare Hosts oder Hosts ohne Zugriff werden in der Logdatei vermerkt und übersprungen
- Für den lokalen Rechner (Computername, localhost) werden die Anmeldedaten nicht verwendet

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Auf jedem Zielhost einmalig VORHER ausführen:

New-NetFirewallRule -DisplayName "Allow Remote EventLog RPC" -Direction Inbound -Protocol TCP -LocalPort 135 -Action Allow
New-NetFirewallRule -DisplayName "Allow Remote EventLog RPC Dynamic" -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow

- Ausführendes Konto (oder das abgefragte Konto) benötigt Admin-Rechte auf allen Zielhosts (Eventlog-Zugriff + CIM/DCOM für Rollenerkennung, Speicherplatz- und OS-Abfrage)
- Alternativ ohne Firewall-Öffnung: Skript direkt auf dem jeweiligen Host selbst ausführen

WICHTIG:
1. Die Rollennamen aus Win32_ServerFeature.Name sind für AD DS, DNS, DHCP, Remotedesktop, Druck, Hyper-V und Dateiserver gegen eine echte Umgebung verifiziert (deutsch + englisch). Certificate Services ist bisher NICHT verifiziert - einmalig auf einem Host mit dieser Rolle mit
"Get-CimInstance -ComputerName <Host> -ClassName Win32_ServerFeature | Select Name" prüfen und
$RolleLogMap ggf. anpassen.

2. Die Hyper-V-Zusatzlogs Hypervisor-Admin, Compute-Admin, VmSwitch-Operational und StorageVSP-Admin sind NICHT verifiziert. Nicht vorhandene Logs werden nur in der Konsole vermerkt und nicht als Fehler in die Logdatei geschrieben.
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

$Datum = Get-Date -Format "yyyyMMdd"

# - AUSGABEORDNER
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }
$HostListFile = Join-Path $Ausgabepfad "liste-Hypervisors.txt"
$BlockGroesse = 10
$script:Credential = $null
$ZielModus = (@($Ziel | Where-Object { "$_".Trim() -ne "" }).Count -gt 0)

# - KONTEN JE HOST (AUS DEM NET-COCKPIT)
$script:AnmeldedatenHost = @{}
if ($AnmeldedatenJeZiel) {
    foreach ($k in $AnmeldedatenJeZiel.Keys) { $script:AnmeldedatenHost["$k"] = $AnmeldedatenJeZiel[$k] }
}

# - RESERVED FÜR ZUSATZLOGS JE ROLLE
$BasisLogs = @("Application","System")

$RolleLogMap = @(
    [PSCustomObject]@{ Match = "Active Directory-Domänendienste|Active Directory Domain Services"; Logs = @("Directory Service","DFS Replication") }
    [PSCustomObject]@{ Match = "DNS-Server|DNS Server";                                            Logs = @("DNS Server") }
    [PSCustomObject]@{ Match = "DHCP-Server|DHCP Server";                                          Logs = @("Microsoft-Windows-Dhcp-Server/Operational") }
    [PSCustomObject]@{ Match = "Remotedesktop|Remote Desktop";                                     Logs = @("Microsoft-Windows-TerminalServices-LocalSessionManager/Operational","Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin") }
    [PSCustomObject]@{ Match = "Hyper-V";                                                           Logs = @("Microsoft-Windows-Hyper-V-VMMS-Admin","Microsoft-Windows-Hyper-V-Worker-Admin","Microsoft-Windows-Hyper-V-Hypervisor-Admin","Microsoft-Windows-Hyper-V-Compute-Admin","Microsoft-Windows-Hyper-V-VmSwitch-Operational","Microsoft-Windows-Hyper-V-StorageVSP-Admin") }
    [PSCustomObject]@{ Match = "Druck|Print";                                                       Logs = @("Microsoft-Windows-PrintService/Admin","Microsoft-Windows-PrintService/Operational") }
    [PSCustomObject]@{ Match = "Zertifikatdienste|Certificate Services";                            Logs = @("Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational") }
    [PSCustomObject]@{ Match = "Dateiserver|File Server";                                           Logs = @("Microsoft-Windows-SMBServer/Operational") }
)

function Get-ZusatzLogs {
    param($Features)
    $zusatz = @()
    foreach ($f in $Features) {
        foreach ($regel in $RolleLogMap) {
            if ($f.Name -match $regel.Match) {
                $zusatz += $regel.Logs
            }
        }
    }
    return ($zusatz | Select-Object -Unique)
}

# - ANMELDEDATEN-HILFSFUNKTIONEN
function Test-IstLokalerHost {
    param([string]$ComputerName)
    return (($ComputerName -in @($env:COMPUTERNAME, "localhost", "127.0.0.1", "::1", ".")) -or ($ComputerName -like "$env:COMPUTERNAME.*"))
}

function Get-CredParam {
    param([string]$ComputerName)
    if (Test-IstLokalerHost -ComputerName $ComputerName) { return @{} }
    if ($script:AnmeldedatenHost.ContainsKey($ComputerName)) { return @{ Credential = $script:AnmeldedatenHost[$ComputerName] } }
    if ($script:Credential) { return @{ Credential = $script:Credential } }
    return @{}
}

## Name des Kontos, mit dem ein Host angesprochen wird (für den Schutz vor Kontosperrung)
function Get-KontoName {
    param([string]$ComputerName)
    $p = Get-CredParam -ComputerName $ComputerName
    if ($p.Credential) { return ([string]$p.Credential.UserName).ToLower() }
    return "$env:USERDOMAIN\$env:USERNAME".ToLower()
}

# - VORAB-PRÜFUNG JE HOST (PORT 135 + CIM-ANMELDUNG)
function Test-HostZugriff {
    param([string]$ComputerName)

    # Port 135 (RPC) erreichbar?
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $tcp.BeginConnect($ComputerName, 135, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(3000, $false)) {
            return [PSCustomObject]@{ Status = "NichtErreichbar"; Details = "Port 135 (RPC) nach 3 Sekunden nicht erreichbar" }
        }
        $tcp.EndConnect($async)
    }
    catch {
        return [PSCustomObject]@{ Status = "NichtErreichbar"; Details = "Verbindung zu Port 135 fehlgeschlagen: $($_.Exception.Message)" }
    }
    finally {
        $tcp.Close()
    }

    # Anmeldung per CIM prüfen (echte Abfrage, da DCOM-Sessions erst beim ersten Zugriff verbinden)
    $credParam = Get-CredParam -ComputerName $ComputerName
    try {
        $cimOption  = New-CimSessionOption -Protocol Dcom
        $cimSession = New-CimSession -ComputerName $ComputerName -SessionOption $cimOption @credParam -ErrorAction Stop
        $null = Get-CimInstance -CimSession $cimSession -ClassName Win32_OperatingSystem -ErrorAction Stop
        Remove-CimSession $cimSession
        return [PSCustomObject]@{ Status = "OK"; Details = "" }
    }
    catch {
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $_.Exception.Message -match "Zugriff verweigert|Access is denied|0x80070005|Anmeldefehler|logon failure|Benutzername oder Kennwort|user name or password") {
            return [PSCustomObject]@{ Status = "AnmeldungFehlgeschlagen"; Details = $_.Exception.Message }
        }
        return [PSCustomObject]@{ Status = "Fehler"; Details = $_.Exception.Message }
    }
}

# - DATENERFASSUNG JE HOST (EINE CIM-SESSION: SPEICHERPLATZ, BETRIEBSSYSTEM, DIENSTE, ROLLEN)
function Get-HostDaten {
    param([string]$ComputerName)
    $credParam = Get-CredParam -ComputerName $ComputerName
    try {
        $cimOption  = New-CimSessionOption -Protocol Dcom
        $cimSession = New-CimSession -ComputerName $ComputerName -SessionOption $cimOption @credParam -ErrorAction Stop

        $os       = Get-CimInstance -CimSession $cimSession -ClassName Win32_OperatingSystem -ErrorAction Stop
        $disks    = Get-CimInstance -CimSession $cimSession -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        $services = Get-CimInstance -CimSession $cimSession -ClassName Win32_Service -Filter "StartMode='Auto' AND State!='Running'" -ErrorAction Stop

        $features = $null
        try {
            $features = Get-CimInstance -CimSession $cimSession -ClassName Win32_ServerFeature -ErrorAction Stop
        }
        catch {
            if ($_.Exception.Message -match "Invalid class") {
                Write-Host "  ${ComputerName}: kein Server-Betriebssystem, keine Rollenerkennung möglich" -ForegroundColor DarkGray
            }
            else {
                Write-Host "  Rollenerkennung fehlgeschlagen bei ${ComputerName}: $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
        }

        Remove-CimSession $cimSession

        return [PSCustomObject]@{
            OSCaption = $os.Caption
            OSBuild   = $os.BuildNumber
            Disks     = $disks
            Services  = $services
            Features  = $features
        }
    }
    catch {
        Write-Host "  Datenabruf fehlgeschlagen bei ${ComputerName}: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $null
    }
}

# - HOSTLISTE
if ($ZielModus) {
    $Hostliste = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Hosts (aus dem NET-COCKPIT):"
    $Hostliste | ForEach-Object { Write-Host " - $_" }
}
else {
    ## Hostliste verwalten (nur ohne -Ziel)
    if (-not (Test-Path -LiteralPath $HostListFile)) {
        Write-Host "→ Hostliste existiert nicht und wird erstellt..."
        $ersteHosts = Read-Host "Gib die ersten Hostnamen oder IPs ein (durch Komma getrennt)"
        $hosts_init = $ersteHosts -split ",\s*"
        $hosts_init | Out-File -LiteralPath $HostListFile -Encoding utf8
        Write-Host "→ Hostliste wurde erstellt unter $HostListFile"
    }
    Write-Host "`nZu prüfende Hosts nach ${HostListFile} :"
    Get-Content -LiteralPath $HostListFile | ForEach-Object { Write-Host " - $_" }
    $antwort = Read-Host "`nWillst du weitere Hosts hinzufügen? (j/n)"
    if ($antwort -eq "j") {
        $neue = Read-Host "Neue Hostnamen oder IPs (durch Komma getrennt)"
        $hosts_neu = $neue -split ",\s*"
        Add-Content -LiteralPath $HostListFile -Value $hosts_neu
        Write-Host "→ Neue Hosts wurden hinzugefügt."
    }

    $Hostliste = @(Get-Content -LiteralPath $HostListFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
}

if ($Hostliste.Count -eq 0) {
    Write-Host "→ Keine Hosts vorhanden – Skript wird beendet." -ForegroundColor Yellow
    return
}

$Zeitraum = (Get-Date).AddDays(-30)
$AnzahlBloecke = [Math]::Ceiling($Hostliste.Count / $BlockGroesse)

# - ANMELDEDATEN ABFRAGEN (nur ohne NET-COCKPIT; aus dem NET-COCKPIT kommt je Host das eigene Konto)
if (-not $ZielModus) {
    $credAntwort = Read-Host "`nAndere Anmeldedaten verwenden als das aktuelle Konto ($env:USERDOMAIN\$env:USERNAME)? (j/n)"
    if ($credAntwort -eq "j") {
        $c = Get-Credential -Message "Konto mit Admin-Rechten auf den Zielhosts"
        if ($c) { $script:Credential = $c }
        else { Write-Host "→ Keine Anmeldedaten eingegeben, es wird das aktuelle Konto verwendet." -ForegroundColor DarkYellow }
    }
}

# - VORAB-PRÜFUNG ALLER HOSTS (ERREICHBARKEIT + ANMELDUNG)
Write-Host "`nPrüfe Erreichbarkeit und Anmeldung der Hosts..." -ForegroundColor Cyan
$ZugriffErgebnis = @{}
$Wiederholen = $true
while ($Wiederholen) {
    $Wiederholen = $false
    $GesperrteKonten = @{}
    $ZugriffErgebnis = @{}

    foreach ($h in $Hostliste) {

        $kontoName = Get-KontoName -ComputerName $h

        if ($GesperrteKonten.ContainsKey($kontoName)) {
            $ZugriffErgebnis[$h] = [PSCustomObject]@{ Status = "NichtGeprueft"; Details = "Prüfung nach fehlgeschlagener Anmeldung mit dem Konto $kontoName abgebrochen" }
            Write-Host "  ${h}: nicht geprüft" -ForegroundColor DarkGray
            continue
        }

        $r = Test-HostZugriff -ComputerName $h
        $ZugriffErgebnis[$h] = $r

        if ($r.Status -eq "OK") {
            Write-Host "  ${h}: OK" -ForegroundColor Green
        }
        elseif ($r.Status -eq "NichtErreichbar") {
            Write-Host "  ${h}: nicht erreichbar - $($r.Details)" -ForegroundColor DarkYellow
        }
        elseif ($r.Status -eq "AnmeldungFehlgeschlagen") {
            Write-Host "  ${h}: Anmeldung fehlgeschlagen (Konto $kontoName) - $($r.Details)" -ForegroundColor Red
            Write-Host "  Weitere Prüfungen mit diesem Konto pausieren, um Kontosperrungen zu vermeiden." -ForegroundColor Yellow
            $neu = Read-Host "  Anmeldedaten neu eingeben? (j/n)"
            if ($neu -eq "j") {
                $c = Get-Credential -Message "Konto mit Admin-Rechten auf $h"
                if ($c) {
                    if ($ZielModus) { $script:AnmeldedatenHost[$h] = $c } else { $script:Credential = $c }
                    $Wiederholen = $true
                    break
                }
            }
            $GesperrteKonten[$kontoName] = $true
        }
        else {
            Write-Host "  ${h}: Fehler - $($r.Details)" -ForegroundColor DarkYellow
        }
    }
}

$AnzahlOK = @($ZugriffErgebnis.Values | Where-Object { $_.Status -eq "OK" }).Count
Write-Host "`n$AnzahlOK von $($Hostliste.Count) Hosts erreichbar und angemeldet." -ForegroundColor Cyan
if ($AnzahlOK -eq 0) {
    Write-Host "Keine Hosts verfügbar, Script wird beendet." -ForegroundColor Red
    return
}
Write-Host "Weiter mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - VERARBEITUNG IN 10ER-BLOECKEN (JE BLOCK EIGENE LOG-DATEI)
for ($b = 0; $b -lt $AnzahlBloecke; $b++) {

    $Start = $b * $BlockGroesse
    $Ende  = [Math]::Min($Start + $BlockGroesse - 1, $Hostliste.Count - 1)
    $Block = $Hostliste[$Start..$Ende]

    $Bereich = "{0:D2}-{1:D2}" -f ($Start + 1), ($Ende + 1)
    $Dateiname = "Wartung_${Datum}_Hypervisor_${Bereich}.txt"
    $AusgabeDatei = Join-Path $Ausgabepfad $Dateiname

    # Alte Datei löschen, falls vorhanden
    Remove-Item -LiteralPath $AusgabeDatei -ErrorAction SilentlyContinue

    # Kopfbereich
    Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_START"
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "#INFO:"
    Add-Content $AusgabeDatei "# Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
    Add-Content $AusgabeDatei "# Host-Block: $Bereich"
    Add-Content $AusgabeDatei "# Diese Datei wurde automatisch im Rahmen einer proaktiven IT-Wartung erstellt."
    Add-Content $AusgabeDatei "# Regeln für die Auswertung:"
    Add-Content $AusgabeDatei "# 1. Alle enthaltenen Ereignisse technisch bewerten."
    Add-Content $AusgabeDatei "# 2. Kritische Ereignisse zuerst, unkritische danach."
    Add-Content $AusgabeDatei "# 3. Mehrfach vorkommende Ereignisse (Ereignis-ID) zusammenfassen, so dass in der Auswertung nichts zu oft auftaucht. Zum Beispiel wenn Ereignis-ID 1000 mehrfach vorkommt so:"
    Add-Content $AusgabeDatei "#    -- <Datum>, Ereignis-ID: Die App Outlook, Word, Adobe beendet - <Bewertung>"
    Add-Content $AusgabeDatei "# 4. Ausgabe ausschließlich im Codeblock, exakt im Format für das Feld 'Server-Notizen':"
    Add-Content $AusgabeDatei "#    - HOSTNAME:"
    Add-Content $AusgabeDatei "#    -- Speicherplatz, Betriebssystemversion, Datum, Ereignis-ID: kurze Beschreibung / Bewertung"
    Add-Content $AusgabeDatei "# 5. Hosts mit dem Vermerk 'nicht geprüft' wurden nicht ausgewertet, dort keine Bewertung vornehmen und den Vermerk unverändert übernehmen."
    Add-Content $AusgabeDatei "# 6. Keine Kommentare, keine Platzhalter, keine Übergänge."
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "=== BEGINN DER EVENTLOG-DATEN ==="
    Add-Content $AusgabeDatei ""

    Clear-Host
    Write-Host "Prüfe die Hosts. Je nach Anzahl der Rollen dauert das kurz"
    Write-Host "`n=== Block ${Bereich}: Host $($Start+1) bis $($Ende+1) ===`n" -ForegroundColor Cyan

    foreach ($HyperVHost in $Block) {
        Write-Host "----- $HyperVHost -----" -ForegroundColor Cyan

        Add-Content $AusgabeDatei "- ${HyperVHost}:"

        # - HOSTS OHNE ZUGRIFF ÜBERSPRINGEN
        $Zugriff = $ZugriffErgebnis[$HyperVHost]
        if ($Zugriff.Status -ne "OK") {
            $Grund = switch ($Zugriff.Status) {
                "NichtErreichbar"         { "nicht erreichbar" }
                "AnmeldungFehlgeschlagen" { "Anmeldung fehlgeschlagen" }
                "NichtGeprueft"           { "Anmeldung mit demselben Konto an vorherigem Host fehlgeschlagen" }
                default                   { "Fehler beim Verbindungsaufbau" }
            }
            Write-Host "  übersprungen: $Grund" -ForegroundColor DarkYellow
            Add-Content $AusgabeDatei "-- nicht geprüft: $Grund - $($Zugriff.Details)"
            Add-Content $AusgabeDatei ""
            continue
        }

        # - GRUNDINFORMATIONEN AUSGEBEN (SPEICHERPLATZ, BETRIEBSSYSTEMVERSION, AUTOSTART-DIENSTE)
        $Daten = Get-HostDaten -ComputerName $HyperVHost
        $Features = if ($Daten) { $Daten.Features } else { $null }
        if ($Daten) {
            foreach ($disk in $Daten.Disks) {
                $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
                $sizeGB = [math]::Round($disk.Size / 1GB, 1)
                Add-Content $AusgabeDatei ("-- Speicherplatz {0}: {1} GB frei von {2} GB" -f $disk.DeviceID, $freeGB, $sizeGB)
            }
            Add-Content $AusgabeDatei ("-- Betriebssystem: {0} (Build {1})" -f $Daten.OSCaption, $Daten.OSBuild)

            if ($Daten.Services) {
                foreach ($svc in $Daten.Services) {
                    Add-Content $AusgabeDatei ("-- Dienst nicht gestartet (Autostart): {0} ({1}) - Status: {2}, ExitCode: {3}" -f $svc.DisplayName, $svc.Name, $svc.State, $svc.ExitCode)
                }
            }
            else {
                Add-Content $AusgabeDatei "-- Autostart-Dienste: alle gestartet"
            }
        }
        else {
            Add-Content $AusgabeDatei "-- Grundinfo nicht verfügbar"
        }

        Add-Content $AusgabeDatei ""

        # - EVENTLOGS AUSLESEN (BASISLOGS + ROLLENSPEZIFISCHE ZUSATZLOGS)
        $ZusatzLogs = Get-ZusatzLogs -Features $Features
        if ($ZusatzLogs) {
            Write-Host "  Zusatzlogs erkannt: $($ZusatzLogs -join ', ')" -ForegroundColor DarkCyan
        }
        $LogsFuerHost = @($BasisLogs + $ZusatzLogs | Select-Object -Unique)
        $credParam = Get-CredParam -ComputerName $HyperVHost

        $alleEvents = @()
        $logFehler = @()

        foreach ($log in $LogsFuerHost) {
            try {
                $alleEvents += Get-WinEvent -ComputerName $HyperVHost @credParam -FilterHashtable @{
                    LogName   = $log
                    Level     = 1,2
                    StartTime = $Zeitraum
                } -ErrorAction Stop |
                Select-Object TimeCreated, Id, ProviderName, Message
            }
            catch {
                if ($_.FullyQualifiedErrorId -match "NoMatchingEventsFound") {
                    # keine Ereignisse im Zeitraum, kein Fehler
                }
                elseif ($_.FullyQualifiedErrorId -match "NoMatchingLogsFound" -and $log -notin $BasisLogs) {
                    Write-Host "  Log nicht vorhanden: $log" -ForegroundColor DarkGray
                }
                else {
                    $logFehler += "-- Fehler beim Abruf von Log '${log}': $($_.Exception.Message)"
                }
            }
        }

        foreach ($f in $logFehler) { Add-Content $AusgabeDatei $f }

        if ($alleEvents) {

            $norm = foreach ($e in $alleEvents) {

                # Message hart normalisieren
                $short = ($e.Message -split "`n")[0..1] -join " "
                $short = $short.Trim() -replace "\s+", " "

                [PSCustomObject]@{
                    TimeCreated = $e.TimeCreated
                    Id          = $e.Id
                    Provider    = $e.ProviderName
                    ShortMsg    = $short
                }
            }

            $groups = $norm | Group-Object Id, Provider, ShortMsg

            foreach ($grp in $groups) {

                $first = $grp.Group | Sort-Object TimeCreated | Select-Object -First 1

                $id     = $first.Id
                $prov   = $first.Provider
                $short  = $first.ShortMsg

                if ($short.Length -gt 160) {
                    $short = $short.Substring(0,160) + "..."
                }

                Add-Content $AusgabeDatei ("-- {0:dd.MM.yyyy HH:mm}, ID {1}: ${prov}: {2}" -f $first.TimeCreated, $id, $short)
            }
        }
        elseif (-not $logFehler) {
            Add-Content $AusgabeDatei "-- Keine relevanten Ereignisse"
        }

        Add-Content $AusgabeDatei ""
    }

    # Fußbereich
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "=== ENDE DER EVENTLOG-DATEN ==="
    Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_ENDE"

    Write-Host ""
    Write-Host "Die Datei wurde gespeichert in $AusgabeDatei" -ForegroundColor Green
    Write-Host ""
    Start-Process notepad.exe $AusgabeDatei
}

Write-Host "`nFertig."