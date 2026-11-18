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
Write-Host "=== Wartung-04.1-virtServer-EreignislogVM ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Liest Application-/System-Eventlogs (plus rollenspezifische Zusatzlogs wie AD, DNS, DHCP, RDS, Hyper-V, Druck, Zertifikatsdienste, Dateiserver) der letzten 30 Tage von einer Liste virtueller Server aus, fasst wiederkehrende Ereignisse zusammen und schreibt eine formatierte Datei für die Wartungsauswertung. Zusätzlich werden je Server Speicherplatz (lokale Partitionen), Betriebssystemversion/-BuildNumber und nicht gestartete Autostart-Dienste ausgegeben. Am Ende erscheint zusätzlich nur in der Konsole (nicht im Log) eine Rollen-Übersicht für das Wartungsformular. Alle Daten je Server (Speicherplatz, OS, Dienste, Rollen) werden über eine einzige CIM-Session pro Server abgerufen. Serverliste wird bei Bedarf interaktiv angelegt/erweitert.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Gerät das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfällt die Listenpflege und die Kontoabfrage. Ohne -Ziel läuft das Skript wie bisher interaktiv. Server, die nicht erreichbar sind oder deren Anmeldung fehlschlägt, werden in der Logdatei vermerkt und übersprungen.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Auf jedem Zielserver einmalig VORHER ausführen:

New-NetFirewallRule -DisplayName "Allow Remote EventLog RPC" -Direction Inbound -Protocol TCP -LocalPort 135 -Action Allow
New-NetFirewallRule -DisplayName "Allow Remote EventLog RPC Dynamic" -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow

- Ausführendes Konto benötigt Admin-Rechte auf allen Zielservern (Eventlog-Zugriff + CIM/DCOM für Rollenerkennung, Speicherplatz- und OS-Abfrage)
- Alternativ ohne Firewall-Öffnung: Skript direkt auf dem jeweiligen Server selbst ausführen

WICHTIG:
1. Die Rollennamen aus Win32_ServerFeature.Name sind für AD DS, DNS, DHCP, Remotedesktop, Druck, Hyper-V und Dateiserver gegen eine echte Umgebung verifiziert (deutsch + englisch). Certificate Services ist bisher NICHT verifiziert - einmalig auf einem Server mit dieser Rolle mit
"Get-CimInstance -ComputerName <Server> -ClassName Win32_ServerFeature | Select Name" prüfen und
$RolleLogMap ggf. anpassen.

2. SQL Server: hat kein eigenes Eventlog-Log, Meldungen landen im Application-Log
(Quelle MSSQLSERVER bzw. MSSQL$<Instanz>) - deshalb hier nicht als Zusatzlog gelistet.
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
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (Server) nötig." -ForegroundColor Red
    exit 1
}
$ergebnisListe = [System.Collections.Generic.List[object]]::new()

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


$Datum = Get-Date -Format "yyyyMMdd"
$ServerListFile = "C:\Temp\liste-virtuelle_server.txt"
$BlockGroesse = 10
$script:Credential = $null

# - RESERVED FÜR ZUSATZLOGS JE ROLLE
$BasisLogs = @("Application","System")

$RolleLogMap = @(
    [PSCustomObject]@{ Match = "Active Directory-Domänendienste|Active Directory Domain Services"; Logs = @("Directory Service","DFS Replication") }
    [PSCustomObject]@{ Match = "DNS-Server|DNS Server";                                            Logs = @("DNS Server") }
    [PSCustomObject]@{ Match = "DHCP-Server|DHCP Server";                                          Logs = @("Microsoft-Windows-Dhcp-Server/Operational") }
    [PSCustomObject]@{ Match = "Remotedesktop|Remote Desktop";                                     Logs = @("Microsoft-Windows-TerminalServices-LocalSessionManager/Operational","Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin") }
    [PSCustomObject]@{ Match = "Hyper-V";                                                           Logs = @("Microsoft-Windows-Hyper-V-VMMS-Admin","Microsoft-Windows-Hyper-V-Worker-Admin") }
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

# - ROLLEN-ÜBERSICHT FÜR WARTUNGSFORMULAR (SPALTEN-MAPPING)
$RolleMap = @(
    [PSCustomObject]@{ Spalte = "DNS";            Match = "DNS-Server|DNS Server" }
    [PSCustomObject]@{ Spalte = "AD";             Match = "Domänendienste|Domain Services" }
    [PSCustomObject]@{ Spalte = "DHCP";           Match = "DHCP-Server|DHCP Server" }
    [PSCustomObject]@{ Spalte = "Webserver";      Match = "^Webserver$|^Web Server \(IIS\)$" }
    [PSCustomObject]@{ Spalte = "Dateiserver";    Match = "^Dateiserver$|^File Server$" }
    [PSCustomObject]@{ Spalte = "Datensicherung"; Match = "Sicherung|Backup" }
)

## Anzeigenamen der Rollen (Reihenfolge wie im Wartungsformular)
$KategorieListe = [ordered]@{
    Anwendung      = "Anwendung"
    System         = "System"
    Sicherheit     = "Sicherheit"
    DNS            = "DNS"
    AD             = "Active Directory"
    DHCP           = "DHCP"
    Webserver      = "Webserver"
    Dateiserver    = "Dateiserver"
    Datensicherung = "Datensicherung"
}

function Get-ServerRollen {
    param($Features, [bool]$Erreichbar)

    $result = [ordered]@{
        Anwendung      = $Erreichbar
        System         = $Erreichbar
        Sicherheit     = $Erreichbar
        DNS            = $false
        AD             = $false
        DHCP           = $false
        Webserver      = $false
        Dateiserver    = $false
        Datensicherung = $false
    }

    if (-not $Erreichbar) { return $result }

    foreach ($f in $Features) {
        foreach ($regel in $RolleMap) {
            if ($f.Name -match $regel.Match) {
                $result[$regel.Spalte] = $true
            }
        }
    }

    return $result
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

# - DATENERFASSUNG JE SERVER (EINE CIM-SESSION: SPEICHERPLATZ, BETRIEBSSYSTEM, DIENSTE, ROLLEN)
function Get-ServerDaten {
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

# - SERVERLISTE
if ($ZielModus) {
    $Serverliste = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Server (aus dem NET-COCKPIT):"
    $Serverliste | ForEach-Object { Write-Host " - $_" }
}
else {
    # - SERVERLISTE VERWALTEN
    if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }
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

    ## Auswahl: alle Server der Liste oder einzelner Server
    $Serverliste = @(Get-Content $ServerListFile | Where-Object { $_.Trim() -ne "" })
    $Auswahl = Read-Host "`nAlle Server der Liste prüfen?`nMit [Enter] alle prüfen oder einzelner Servernamen dann Hostname eingeben"
    if (-not [string]::IsNullOrWhiteSpace($Auswahl)) {
        $Serverliste = @($Auswahl.Trim())
        Write-Host "→ Es wird nur geprüft: $($Serverliste[0])" -ForegroundColor Yellow
    }
    else {
        Write-Host "→ Es werden alle $($Serverliste.Count) Server der Liste geprüft." -ForegroundColor Yellow
    }
}

$Zeitraum = (Get-Date).AddDays(-30)
$AnzahlBloecke = [Math]::Ceiling($Serverliste.Count / $BlockGroesse)

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

    foreach ($h in $Serverliste) {

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
            $neu = $(if ($Automatik) { 'n' } else { Read-Host "  Anmeldedaten neu eingeben? (j/n)" })
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
Write-Host "`n$AnzahlOK von $($Serverliste.Count) Hosts erreichbar und angemeldet." -ForegroundColor Cyan
if ($AnzahlOK -eq 0) {
    Write-Host "Keine Hosts verfügbar, Script wird beendet." -ForegroundColor Red
    if ($Automatik) {
        $nicht = foreach ($h in $Serverliste) { [pscustomobject]@{ Ziel = $h; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = "nicht geprüft: $($ZugriffErgebnis[$h].Status) $($ZugriffErgebnis[$h].Details)".Trim() } }
        Write-WtErgebnis -Skript '04.1-virtServer-EreignislogVM' -Ordner $Ausgabepfad -Ergebnisse @($nicht)
        exit 1
    }
    return
}
if (-not $Automatik) {
    Write-Host "Weiter mit [Enter] ..." -ForegroundColor Yellow
    Read-Host | Out-Null
}


Write-Host " "
Write-Host " "


# - VERARBEITUNG IN 10ER-BLOECKEN (JE BLOCK EIGENE LOG-DATEI)
$Zusammenfassung = @()

Write-Host "Prüfe die Server. Je nach Anzahl der Serverrollen dauert das kurz"

for ($b = 0; $b -lt $AnzahlBloecke; $b++) {

    $Start = $b * $BlockGroesse
    $Ende  = [Math]::Min($Start + $BlockGroesse - 1, $Serverliste.Count - 1)
    $Block = $Serverliste[$Start..$Ende]

    $Bereich = "{0:D2}-{1:D2}" -f ($Start + 1), ($Ende + 1)
    $Dateiname = "Wartung_${Datum}_virtuelleServer_${Bereich}.txt"
    $AusgabeDatei = Join-Path $Ausgabepfad $Dateiname

    # Alte Datei löschen, falls vorhanden
    Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue

    # Kopfbereich
    Add-Content $AusgabeDatei "# WARTUNG EVENTLOG VM "
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "## Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
    Add-Content $AusgabeDatei "## Server-Block: $Bereich"
    Add-Content $AusgabeDatei "## Diese Datei wurde automatisch im Rahmen einer proaktiven IT-Wartung erstellt."
    Add-Content $AusgabeDatei "## Regeln für die Auswertung:"
    Add-Content $AusgabeDatei "## 1. Alle enthaltenen Ereignisse technisch bewerten."
    Add-Content $AusgabeDatei "## 2. Kritische Ereignisse zuerst, unkritische danach."
    Add-Content $AusgabeDatei "## 3. Mehrfach vorkommende Ereignisse (Ereignis-ID) zusammenfassen, so dass in der Auswertung zu oft auftaucht. Zum Beispiel wenn Ereignis-ID 1000 mehrfach vorkommt so:"
    Add-Content $AusgabeDatei "##    -- <Datum>, Ereignis-ID: Die App Outlok, Word, Adobe beendet - <Bewertung>"
    Add-Content $AusgabeDatei "## 4. Ausgabe ausschließlich im Codeblock, exakt im Format für das Feld 'Server-Notizen':"
    Add-Content $AusgabeDatei "##    - SERVERNAME:"
    Add-Content $AusgabeDatei "##    -- Speicherplatz, Betriebssystemversion, Protokolle, Datum, Ereignis-ID: kurze Beschreibung / Bewertung"
    Add-Content $AusgabeDatei "## 5. Server mit dem Vermerk 'nicht geprüft' wurden nicht ausgewertet, dort keine Bewertung vornehmen und den Vermerk unverändert übernehmen."
    Add-Content $AusgabeDatei "## 6. Keine Kommentare, keine Platzhalter, keine Übergänge."
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "=== BEGINN DER EVENTLOG-DATEN ==="
    Add-Content $AusgabeDatei ""

    Write-Host "`n=== Block ${Bereich}: Server $($Start+1) bis $($Ende+1) ===`n" -ForegroundColor Cyan

    $FeaturesImBlock = @{}
    $ErreichbarImBlock = @{}
    foreach ($Server in $Block) {
        Write-Host "----- $Server -----" -ForegroundColor Cyan

        Add-Content $AusgabeDatei "- ${Server}:"

        # - SERVER OHNE ZUGRIFF ÜBERSPRINGEN
        $Zugriff = $ZugriffErgebnis[$Server]
        if ($Zugriff.Status -ne "OK") {
            $Grund = switch ($Zugriff.Status) {
                "NichtErreichbar"         { "nicht erreichbar" }
                "AnmeldungFehlgeschlagen" { "Anmeldung fehlgeschlagen" }
                "NichtGeprueft"           { "Anmeldung mit demselben Konto an vorherigem Server fehlgeschlagen" }
                default                   { "Fehler beim Verbindungsaufbau" }
            }
            Write-Host "  übersprungen: $Grund" -ForegroundColor DarkYellow
            Add-Content $AusgabeDatei "-- nicht geprüft: $Grund - $($Zugriff.Details)"
            Add-Content $AusgabeDatei ""
            $FeaturesImBlock[$Server] = $null
            $ErreichbarImBlock[$Server] = $false
            $ergebnisListe.Add([pscustomobject]@{ Ziel = $Server; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = "nicht geprüft: $Grund" })
            continue
        }

        # - GRUNDINFORMATIONEN AUSGEBEN (SPEICHERPLATZ, BETRIEBSSYSTEMVERSION, AUTOSTART-DIENSTE)
        $Daten = Get-ServerDaten -ComputerName $Server
        $FeaturesImBlock[$Server] = if ($Daten) { $Daten.Features } else { $null }
        $ErreichbarImBlock[$Server] = [bool]$Daten
        if ($Daten) {
            foreach ($disk in $Daten.Disks) {
                $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
                $sizeGB = [math]::Round($disk.Size / 1GB, 1)
                Add-Content $AusgabeDatei ("-- Speicherplatz {0}: {1} GB frei von {2} GB" -f $disk.DeviceID, $freeGB, $sizeGB)
            }
            Add-Content $AusgabeDatei ("-- Betriebssystem: {0} (Build {1})" -f $Daten.OSCaption, $Daten.OSBuild)

            ## Protokolle: die Rollen des Servers mit den Namen aus dem Wartungsformular
            $RollenImLog = Get-ServerRollen -Features $FeaturesImBlock[$Server] -Erreichbar $true
            $ProtokollNamen = @($KategorieListe.Keys | Where-Object { $RollenImLog[$_] } | ForEach-Object { $KategorieListe[$_] })
            Add-Content $AusgabeDatei ("-- Protokolle: {0}" -f ($ProtokollNamen -join ", "))

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

        $ZusatzLogs = Get-ZusatzLogs -Features $FeaturesImBlock[$Server]
        if ($ZusatzLogs) {
            Write-Host "  Zusatzlogs erkannt: $($ZusatzLogs -join ', ')" -ForegroundColor DarkCyan
        }
        $LogsFuerServer = @($BasisLogs + $ZusatzLogs | Select-Object -Unique)

        $alleEvents = @()
        $logFehler = @()
        $gelesen = [System.Collections.Generic.List[string]]::new()
        $ereignisse = @()
        $credParam = Get-CredParam -ComputerName $Server

        foreach ($log in $LogsFuerServer) {
            Write-Host "  Lese Log '$log' ..." -NoNewline -ForegroundColor DarkGray
            $logStart = Get-Date
            $logAnzahl = 0
            try {
                $logEvents = @(Get-WinEvent -ComputerName $Server @credParam -FilterHashtable @{
                    LogName   = $log
                    Level     = 1,2
                    StartTime = $Zeitraum
                } -ErrorAction Stop |
                Select-Object TimeCreated, Id, ProviderName, Message, Level, LogName)
                $logAnzahl = $logEvents.Count
                $alleEvents += $logEvents
                $gelesen.Add($log)
            }
            catch {
                if ($_.FullyQualifiedErrorId -notmatch "NoMatchingEventsFound") {
                    $logFehler += "-- Fehler beim Abruf von Log '${log}': $($_.Exception.Message)"
                }
                else { $gelesen.Add($log) }
            }
            Write-Host (" {0} Ereignisse ({1:N0} s)" -f $logAnzahl, ((Get-Date) - $logStart).TotalSeconds) -ForegroundColor DarkGray
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
                    Level       = $e.Level
                    LogName     = $e.LogName
                }
            }

            $groups = $norm | Group-Object Id, Provider, ShortMsg

            ### Checkliste: bis zu 10 schwerste/häufigste Ereignisse (Level 1 = kritisch vor 2 = Fehler, dann nach Häufigkeit)
            $ereignisse = @($groups | ForEach-Object {
                $f = $_.Group | Sort-Object TimeCreated | Select-Object -First 1
                $kurz = [string]$f.ShortMsg
                if ($kurz.Length -gt 160) { $kurz = $kurz.Substring(0, 160) + '...' }
                [pscustomobject]@{ Level = [int]$f.Level; Anzahl = [int]$_.Count; Datum = $f.TimeCreated.ToString('dd.MM.yyyy'); Id = [int]$f.Id; Quelle = [string]$f.Provider; Log = [string]$f.LogName; Text = $kurz }
            } | Sort-Object @{ Expression = 'Level'; Ascending = $true }, @{ Expression = 'Anzahl'; Descending = $true } | Select-Object -First 10)

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

        # - ERGEBNIS FÜR DIE CHECKLISTE (Haken = geprüft; unbekannt bleibt weg)
        $pr = [ordered]@{}
        if ($gelesen -contains 'Application') { $pr['Anwendung'] = $true }
        if ($gelesen -contains 'System') { $pr['System'] = $true }
        if ($gelesen -contains 'Directory Service') { $pr['ActiveDirectory'] = $true }
        if ($gelesen -contains 'DNS Server') { $pr['DNS'] = $true }
        if ($gelesen -contains 'Microsoft-Windows-Dhcp-Server/Operational') { $pr['DHCP'] = $true }
        if ($gelesen -contains 'Microsoft-Windows-SMBServer/Operational') { $pr['Dateiserver'] = $true }
        $speicher = @()
        $notizTeile = @()
        if ($Daten) {
            $speicher = @($Daten.Disks | ForEach-Object {
                $frei = [math]::Round($_.FreeSpace / 1GB, 1); $gr = [math]::Round($_.Size / 1GB, 1)
                [pscustomobject]@{ Laufwerk = [string]$_.DeviceID; FreiGB = $frei; GroesseGB = $gr; FreiProzent = $(if ($_.Size -gt 0) { [math]::Round($_.FreeSpace / $_.Size * 100, 1) } else { 0 }) }
            })
            ### unter 10 % frei gilt als nicht in Ordnung; Dienste: Haken nur, wenn kein Autostart-Dienst gestoppt ist
            $pr['Speicherplatz'] = (@($speicher | Where-Object { $_.FreiProzent -lt 10 }).Count -eq 0)
            $pr['DiensteGestartet'] = (-not $Daten.Services)
        }
        else { $notizTeile += 'Grundinfo (Speicherplatz, Dienste) nicht verfügbar' }
        if ($logFehler.Count -gt 0) { $notizTeile += "$($logFehler.Count) Log(s) nicht lesbar" }
        $ergebnisListe.Add([pscustomobject]@{
            Ziel = $Server; Erreicht = $true
            Pruefungen = [pscustomobject]$pr
            Werte = [pscustomobject]@{
                Betriebssystem = $(if ($Daten) { "$($Daten.OSCaption) (Build $($Daten.OSBuild))" } else { '' })
                Speicherplatz = $speicher
                DiensteGestoppt = @($(if ($Daten -and $Daten.Services) { $Daten.Services | ForEach-Object { [string]$_.DisplayName } }))
                Ereignisse = @($ereignisse)
            }
            Notiz = ($notizTeile -join '; ')
        })
    }

    # Fußbereich
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "=== ENDE DER EVENTLOG-DATEN ==="
    Add-Content $AusgabeDatei "# WARTUNG EVENTLOG ENDE"

    if (-not $Automatik) { Start-Process notepad.exe $AusgabeDatei }

    # - ROLLEN-ERGEBNISSE DES BLOCKS SAMMELN (AUSGABE ERFOLGT NACH ALLEN BLÖCKEN)
    $Ergebnisse = for ($j = 0; $j -lt $Block.Count; $j++) {
        $Server   = $Block[$j]
        $Position = $j + 1
        $VmNummer = $Start + $Position
        $r = Get-ServerRollen -Features $FeaturesImBlock[$Server] -Erreichbar $ErreichbarImBlock[$Server]
        [PSCustomObject]@{ Position = $Position; VM = $VmNummer; Server = $Server; Rollen = $r }
    }

    $Zusammenfassung += [PSCustomObject]@{
        Bereich    = $Bereich
        Datei      = $AusgabeDatei
        Ergebnisse = @($Ergebnisse)
    }
}

# - ABSCHLUSS: LOG-DATEIEN UND ROLLENÜBERSICHT (NUR KONSOLE, NICHT IM LOG)

Write-Host ""
Write-Host "----- LOG -----" -ForegroundColor Cyan
Write-Host "Die Dateien wurden gespeichert unter:"
foreach ($z in $Zusammenfassung) {
    Write-Host $z.Datei -ForegroundColor Green
}

Write-Host ""
Write-Host "----- Rollenübersicht -----" -ForegroundColor Cyan

foreach ($z in $Zusammenfassung) {

    $VmVon = $z.Ergebnisse[0].VM
    $VmBis = $z.Ergebnisse[-1].VM
    $VmTitel = if ($VmVon -eq $VmBis) { "$VmVon" } else { "$VmVon-$VmBis" }

    Write-Host ""
    Write-Host "Definition VM $VmTitel" -ForegroundColor Cyan
    foreach ($e in $z.Ergebnisse) {
        Write-Host ("  VM {0}: {1}" -f $e.VM, $e.Server)
    }

    $TabelleTransponiert = foreach ($key in $KategorieListe.Keys) {
        $row = [ordered]@{ Kategorie = $KategorieListe[$key] }
        foreach ($e in $z.Ergebnisse) {
            $row["$($e.VM)"] = if ($e.Rollen[$key]) { "X" } else { "" }
        }
        [PSCustomObject]$row
    }

    $TabellenSpalten = @("Kategorie") + @($z.Ergebnisse | ForEach-Object { "$($_.VM)" })

    Write-Host ""
    $TabelleText = $TabelleTransponiert | Format-Table -Property $TabellenSpalten -AutoSize | Out-String -Width 250
    Write-Host $TabelleText
}

if ($Automatik) {
    Write-WtErgebnis -Skript '04.1-virtServer-EreignislogVM' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    exit $(if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -gt 0) { 0 } else { 1 })
}
