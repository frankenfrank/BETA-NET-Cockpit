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
Write-Host "=== Wartung-05.5-SQL-Server ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
SQL-Kurzcheck für eine oder mehrere SQL-Server-Instanzen: prüft Datenbanksicherungen (Voll/Diff/Log aus msdb), Wartungspläne, SQL-Fehlerprotokolle, Speicherplatz des Backup-Laufwerks und SSMS-Version, erstellt einen Protokollvorschlag für Wartungsnotizen. Instanzsuche per Registry (lokal) und SQL-Server-Browser-Dienst (Netzwerk), interaktive Auswahl und Login (bis zu 3 Versuche, SQL-Login oder Windows-Authentifizierung).

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten SQL-Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Server das Konto der Spalte "Konto" (-AnmeldedatenJeZiel). Dann entfallen Netzwerksuche und Instanzauswahl: alle Instanzen der markierten Server (per SQL Server Browser, sonst die Standardinstanz) werden geprüft. Anmeldung an SQL: zuerst Windows-Authentifizierung, dann das Konto aus dem NET-COCKPIT als SQL-Login, danach Abfrage.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner und der PowerShell-7-Endpunkt (PowerShell.7) auf den Zielservern
- Ausführung als Domänen-Admin (sysadmin auf den SQL-Instanzen) auf einem Rechner mit Netzwerkzugriff auf die SQL-Server
- SqlServer-PowerShell-Modul empfohlen (Install-Module SqlServer) – ohne Modul Fallback über System.Data.SqlClient
- SQL Server Browser-Dienst läuft auf den Zielservern (für Netzwerksuche, UDP 1434)
- WinRM aktiviert + lokale Admin-Rechte auf allen Zielservern außer dem, auf dem das Skript läuft (für Fehlerprotokoll-Pfad, Speicherplatz, SSMS-Version) – ohne WinRM werden nur diese Prüfungen übersprungen, die SQL-seitigen Prüfungen laufen unabhängig davon weiter
- Für das Lesen der Backup-Historie ggf. Rechte vergeben:
  USE msdb;
  EXEC sp_addrolemember 'db_datareader', 'DOMÄNE\administrator';
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
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (SQL-Server) nötig." -ForegroundColor Red
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



# - KONFIGURATION
$Datum = Get-Date -Format "yyyyMMdd"
$Heute = Get-Date
$Datei = Join-Path $Ausgabepfad "Wartung_${Datum}_SQL.txt"

$FullMaxDays = 7
$DiffMaxDays = 2
$LogMaxHours = 24
$MaxLoginVersuche = 3

if (Test-Path $Datei) { Remove-Item $Datei -Force }

Add-Content $Datei "# Wartung SQL Check #"
Add-Content $Datei "Ausgeführt von: $env:COMPUTERNAME"

# - HELFER: LOKAL VS. REMOTE
$script:WinRMStatus = @{}

function Test-IsLocalComputer {
    param([string]$ComputerName)
    if ([string]::IsNullOrWhiteSpace($ComputerName)) { return $true }
    if ($ComputerName -in @('.', 'localhost', '127.0.0.1', $env:COMPUTERNAME)) { return $true }
    try {
        $fqdn = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).HostName
        if ($ComputerName -eq $fqdn) { return $true }
    } catch { }
    return $false
}

## WinRM-Prüfung (pro Server einmal, Ergebnis wird gemerkt)
function Test-WinRMAvailable {
    param([Parameter(Mandatory)][string]$ComputerName)
    $key = $ComputerName.ToLowerInvariant()
    if ($script:WinRMStatus.ContainsKey($key)) { return $script:WinRMStatus[$key] }

    try {
        Test-WSMan -ComputerName $ComputerName -ErrorAction Stop | Out-Null
        $script:WinRMStatus[$key] = $true
    } catch {
        $script:WinRMStatus[$key] = $false
        $hinweis = "WinRM auf $ComputerName nicht erreichbar – Remote-Prüfungen (Speicherplatz, Fehlerprotokoll-Pfad, SSMS-Version) werden übersprungen. Lösung: Auf $ComputerName in einer PowerShell als Administrator 'Enable-PSRemoting -Force' ausführen und die Firewall für TCP 5985 prüfen. Alternativ das Skript direkt auf $ComputerName ausführen."
        Write-Host $hinweis -ForegroundColor Yellow
        Add-Content $Datei $hinweis
    }
    return $script:WinRMStatus[$key]
}

function Invoke-OnComputer {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList
    )
    if (Test-IsLocalComputer -ComputerName $ComputerName) {
        return & $ScriptBlock @ArgumentList
    }

    if (-not (Test-WinRMAvailable -ComputerName $ComputerName)) {
        throw "WinRM nicht verfügbar"
    }

    $cp = @{}
    $konto = Get-ZielKonto -Name $ComputerName
    if ($konto) { $cp.Credential = $konto }
    return Invoke-Command -ComputerName $ComputerName @cp -ConfigurationName 'PowerShell.7' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
}
# - SQL FUNKTIONEN
function Invoke-SqlQuery {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$Query,
        [System.Management.Automation.PSCredential]$Credential
    )

    Import-Module SqlServer -ErrorAction SilentlyContinue | Out-Null

    try {
        $sqlParams = @{ ServerInstance = $ServerInstance; Query = $Query; ErrorAction = 'Stop' }
        if ($Credential) { $sqlParams['Credential'] = $Credential }
        $r = Invoke-Sqlcmd @sqlParams
        return @($r)
    } catch {
        $cn = New-Object System.Data.SqlClient.SqlConnection
        if ($Credential) {
            $cn.ConnectionString = "Server=$ServerInstance;Database=master;User ID=$($Credential.UserName);Password=$($Credential.GetNetworkCredential().Password);Connection Timeout=5;"
        } else {
            $cn.ConnectionString = "Server=$ServerInstance;Database=master;Trusted_Connection=True;Connection Timeout=5;"
        }
        $cn.Open()
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = $Query
        $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $dt = New-Object System.Data.DataTable
        [void]$da.Fill($dt)
        $cn.Close()
        return @($dt.Rows)
    }
}

function Invoke-SqlNonQuery {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$Query,
        [System.Management.Automation.PSCredential]$Credential
    )

    Import-Module SqlServer -ErrorAction SilentlyContinue | Out-Null

    try {
        $sqlParams = @{ ServerInstance = $ServerInstance; Query = $Query; QueryTimeout = 0; ErrorAction = 'Stop' }
        if ($Credential) { $sqlParams['Credential'] = $Credential }
        Invoke-Sqlcmd @sqlParams | Out-Null
        return $true
    } catch {
        try {
            $cn = New-Object System.Data.SqlClient.SqlConnection
            if ($Credential) {
                $cn.ConnectionString = "Server=$ServerInstance;Database=master;User ID=$($Credential.UserName);Password=$($Credential.GetNetworkCredential().Password);Connection Timeout=5;"
            } else {
                $cn.ConnectionString = "Server=$ServerInstance;Database=master;Trusted_Connection=True;Connection Timeout=5;"
            }
            $cn.Open()
            $cmd = $cn.CreateCommand()
            $cmd.CommandTimeout = 0
            $cmd.CommandText = $Query
            [void]$cmd.ExecuteNonQuery()
            $cn.Close()
            return $true
        } catch {
            return $false
        }
    }
}

function Test-SqlConnection {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [System.Management.Automation.PSCredential]$Credential
    )
    try {
        Invoke-SqlQuery -ServerInstance $ServerInstance -Query "SELECT 1 AS Test" -Credential $Credential | Out-Null
        return $true
    } catch {
        return $false
    }
}

# - HELFER: EDITION / EXPRESS
function Get-InstanceInfo {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [System.Management.Automation.PSCredential]$Credential
    )

    $verQ = "SELECT SERVERPROPERTY('ProductVersion') AS ProductVersion, SERVERPROPERTY('ProductLevel') AS ProductLevel, SERVERPROPERTY('Edition') AS Edition;"
    $ver  = Invoke-SqlQuery -ServerInstance $ServerInstance -Query $verQ -Credential $Credential | Select-Object -First 1

    [PSCustomObject]@{
        ProductVersion = [string]$ver.ProductVersion
        ProductLevel   = [string]$ver.ProductLevel
        Edition        = [string]$ver.Edition
        IsExpress      = ([string]$ver.Edition -match 'Express')
    }
}

# - HELFER: REGISTRY-/DATEISYSTEMINFOS EINER INSTANZ (LOKAL ODER PER WINRM)
function Get-RemoteInstanceInfo {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$InstanceName
    )

    $sb = {
        param($InstanceName)
        $result = [PSCustomObject]@{
            ID              = $null
            SQLDataRoot     = $null
            LogPath         = $null
            ErrorLogs       = @()
            BackupDirectory = $null
        }
        $instBase = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
        if (Test-Path $instBase) {
            $id = (Get-ItemProperty -Path $instBase -ErrorAction SilentlyContinue).$InstanceName
            if ($id) { $result.ID = $id }
        }
        if ($result.ID) {
            $setupKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$($result.ID)\Setup"
            if (Test-Path $setupKey) {
                $root = (Get-ItemProperty $setupKey -ErrorAction SilentlyContinue).SQLDataRoot
                if ($root) {
                    $result.SQLDataRoot = $root
                    $logPath = Join-Path $root "Log"
                    $result.LogPath = $logPath
                    if (Test-Path $logPath) {
                        $result.ErrorLogs = @(Get-ChildItem $logPath -Filter "ERRORLOG*" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 3 -Property Name, LastWriteTime)
                    }
                }
            }
            $mssqlKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$($result.ID)\MSSQLServer"
            if (Test-Path $mssqlKey) {
                $bd = (Get-ItemProperty -Path $mssqlKey -ErrorAction SilentlyContinue).BackupDirectory
                if ($bd) { $result.BackupDirectory = $bd }
            }
        }
        return $result
    }

    try {
        return Invoke-OnComputer -ComputerName $ComputerName -ScriptBlock $sb -ArgumentList $InstanceName
    } catch {
        return [PSCustomObject]@{ ID=$null; SQLDataRoot=$null; LogPath=$null; ErrorLogs=@(); BackupDirectory=$null; RemoteError=$_.Exception.Message }
    }
}

function Get-RemoteDriveFree {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$DriveLetter
    )
    $sb = {
        param($DriveLetter)
        $drive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
        if ($drive -and $drive.Free -gt 0) {
            [PSCustomObject]@{ FreeGB = [math]::Round($drive.Free/1GB,2); TotalGB = [math]::Round(($drive.Free + $drive.Used)/1GB,2) }
        } else { $null }
    }
    try {
        return Invoke-OnComputer -ComputerName $ComputerName -ScriptBlock $sb -ArgumentList $DriveLetter
    } catch {
        return $null
    }
}

function Get-SqlErrorLogEntries {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [System.Management.Automation.PSCredential]$Credential,
        [int]$MaxEintraege = 20
    )
    # xp_readerrorlog liest das ERRORLOG über die SQL-Verbindung (kein zusätzlicher Datei-/WinRM-Zugriff
    # nötig). Parameter: Lognummer 0 = aktuelles Log, Logtyp 1 = SQL Server Log, Suchbegriff 'Error:'
    # entspricht dem Standard-Präfix, mit dem SQL Server echte Fehlermeldungen kennzeichnet
    # (z.B. "Error: 823, Severity: 24, State: 2."). Erfordert sysadmin- bzw. securityadmin-Rechte.
    try {
        $q = "EXEC master.dbo.xp_readerrorlog 0, 1, N'Error:';"
        $rows = Invoke-SqlQuery -ServerInstance $ServerInstance -Query $q -Credential $Credential
        return @($rows | Select-Object -Last $MaxEintraege)
    } catch {
        return @()
    }
}

function Get-RemoteSsmsVersions {
    param([Parameter(Mandatory)][string]$ComputerName)
    $sb = {
        Get-ChildItem "C:\Program Files*\Microsoft SQL Server Management Studio*\*\Common7\IDE\SSMS.exe" -ErrorAction SilentlyContinue |
            ForEach-Object { [PSCustomObject]@{ Path = $_.FullName; Version = $_.VersionInfo.ProductVersion } }
    }
    try {
        return @(Invoke-OnComputer -ComputerName $ComputerName -ScriptBlock $sb)
    } catch {
        return @()
    }
}

# - HELFER: BACKUP-STANDARDPFAD (SQL, FALLBACK REGISTRY)
function Get-BackupPath {
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$InstanceName,
        [System.Management.Automation.PSCredential]$Credential
    )

    $backupPath = ""
    try {
        $backupRootQ = "SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(4000)) AS BackupPath;"
        $backupRoot = Invoke-SqlQuery -ServerInstance $ServerInstance -Query $backupRootQ -Credential $Credential | Select-Object -First 1
        if ($backupRoot -and $backupRoot.BackupPath) { $backupPath = [string]$backupRoot.BackupPath }
    } catch { }

    if (-not $backupPath) {
        $regInfo = Get-RemoteInstanceInfo -ComputerName $ComputerName -InstanceName $InstanceName
        if ($regInfo.BackupDirectory) { $backupPath = $regInfo.BackupDirectory }
    }

    return $backupPath
}

function Get-ServerInstanceString {
    param([string]$ComputerName, [string]$InstanceName)
    if ([string]::IsNullOrWhiteSpace($InstanceName) -or $InstanceName -eq 'MSSQLSERVER') {
        return $ComputerName
    } else {
        return "$ComputerName\$InstanceName"
    }
}

# - INSTANZEN
if ($ZielModus) {
    ## Instanzen der markierten Server per SQL Server Browser (UDP 1434) ermitteln, sonst Standardinstanz
    $Ausgewaehlt = @()
    foreach ($zielHost in @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })) {
        $gefunden = @()
        $udp = $null
        try {
            $udp = New-Object System.Net.Sockets.UdpClient
            $udp.Client.ReceiveTimeout = 1500
            $udp.Connect($zielHost, 1434)
            $anfrage = [byte[]]@(0x02)
            [void]$udp.Send($anfrage, $anfrage.Length)
            $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $antwort = [System.Text.Encoding]::ASCII.GetString($udp.Receive([ref]$ep))
            foreach ($eintrag in ($antwort -split ';;' | Where-Object { $_ })) {
                if ($eintrag -match 'InstanceName;(?<inst>[^;]*);') { $gefunden += $matches['inst'] }
            }
        } catch { }
        finally { if ($udp) { $udp.Close() } }

        if ($gefunden.Count -eq 0) {
            Write-Host "$zielHost : keine Antwort vom SQL Server Browser, es wird die Standardinstanz geprüft." -ForegroundColor DarkYellow
            $gefunden = @("MSSQLSERVER")
        }
        foreach ($instName in ($gefunden | Select-Object -Unique)) {
            $Ausgewaehlt += [PSCustomObject]@{
                ComputerName   = $zielHost
                InstanceName   = $instName
                ServerInstance = Get-ServerInstanceString -ComputerName $zielHost -InstanceName $instName
                Quelle         = "NET-COCKPIT"
            }
        }
    }
    Write-Host "Zu prüfende Instanzen (aus dem NET-COCKPIT):" -ForegroundColor Cyan
    $Ausgewaehlt | ForEach-Object { Write-Host " - $($_.ServerInstance)" }
}
else {
    # - LOKALE INSTANZEN ERMITTELN (REGISTRY)
    $instBase = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
    $LokaleInstanzen = @()
    if (Test-Path $instBase) {
        $props = (Get-ItemProperty -Path $instBase).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
        foreach ($p in $props) {
            $LokaleInstanzen += [PSCustomObject]@{
                ComputerName   = $env:COMPUTERNAME
                InstanceName   = $p.Name
                ServerInstance = Get-ServerInstanceString -ComputerName $env:COMPUTERNAME -InstanceName $p.Name
                Quelle         = "Lokal"
            }
        }
    }

    # - NETZWERK NACH WEITEREN SQL-SERVERN DURCHSUCHEN (WIE SSMS "NETZWERK DURCHSUCHEN")
    Write-Host "Durchsuche Netzwerk nach SQL-Servern (SQL Server Browser, UDP 1434, max. 1,5s)..." -ForegroundColor Cyan
    $NetzwerkInstanzen = @()
    try {
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.EnableBroadcast = $true

        $requestData = [byte[]]@(0x02)
        $broadcastEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, 1434)
        $udpClient.Send($requestData, $requestData.Length, $broadcastEndpoint) | Out-Null

        $antworten = New-Object System.Collections.Generic.List[string]
        $deadline = (Get-Date).AddMilliseconds(1500)

        while ((Get-Date) -lt $deadline) {
            $verbleibend = [int](($deadline - (Get-Date)).TotalMilliseconds)
            if ($verbleibend -le 0) { break }
            $receiveTask = $udpClient.ReceiveAsync()
            if ($receiveTask.Wait($verbleibend)) {
                $bytes = $receiveTask.Result.Buffer
                $text = [System.Text.Encoding]::ASCII.GetString($bytes)
                $antworten.Add($text)
                Write-Host "  Antwort von $($receiveTask.Result.RemoteEndPoint)" -ForegroundColor DarkGray
            } else {
                break
            }
        }
        $udpClient.Close()

        foreach ($antwort in $antworten) {
            $eintraege = $antwort -split ';;' | Where-Object { $_ }
            foreach ($eintrag in $eintraege) {
                if ($eintrag -match 'ServerName;(?<sn>[^;]*);InstanceName;(?<inst>[^;]*);') {
                    $cn = $matches['sn']
                    if (-not $cn) { continue }
                    $instName = if ($matches['inst']) { $matches['inst'] } else { "MSSQLSERVER" }
                    $NetzwerkInstanzen += [PSCustomObject]@{
                        ComputerName   = $cn
                        InstanceName   = $instName
                        ServerInstance = Get-ServerInstanceString -ComputerName $cn -InstanceName $instName
                        Quelle         = "Netzwerk"
                    }
                }
            }
        }
        $NetzwerkInstanzen = @($NetzwerkInstanzen | Sort-Object ComputerName, InstanceName -Unique)
        Write-Host "Netzwerk-Scan abgeschlossen: $($NetzwerkInstanzen.Count) Instanz(en) gefunden." -ForegroundColor Cyan
    } catch {
        Write-Host "Netzwerk-Scan fehlgeschlagen (SQL Server Browser Dienst evtl. nicht erreichbar): $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # - KANDIDATEN ZUSAMMENFÜHREN (LOKAL BEVORZUGT BEI DUBLETTEN)
    $KandidatenMap = @{}
    foreach ($k in ($LokaleInstanzen + $NetzwerkInstanzen)) {
        $key = $k.ServerInstance.ToLowerInvariant()
        if (-not $KandidatenMap.ContainsKey($key) -or $k.Quelle -eq "Lokal") {
            $KandidatenMap[$key] = $k
        }
    }
    $Kandidaten = @($KandidatenMap.Values | Sort-Object ComputerName, InstanceName)

    if ($Kandidaten.Count -eq 0) {
        Add-Content $Datei "Keine SQL-Instanzen gefunden (weder lokal noch per Netzwerk-Scan)."
        Write-Host "Keine SQL-Instanzen gefunden." -ForegroundColor Red
        if ($Automatik) { exit 1 }
        Start-Process notepad.exe $Datei
        return
    }

    # - AUSWAHL DER ZU PRÜFENDEN INSTANZEN
    function Select-SqlInstances {
        param([Parameter(Mandatory)][object[]]$Kandidaten)
        $i = 0
        foreach ($k in $Kandidaten) {
            $i++
            Write-Host ("[{0}] {1} ({2})" -f $i, $k.ServerInstance, $k.Quelle)
        }
        $auswahl = Read-Host "Nummern der zu prüfenden Instanzen (kommagetrennt, z.B. 1,3,5)"
        $indices = @($auswahl -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $Kandidaten.Count })
        return @($indices | ForEach-Object { $Kandidaten[$_] })
    }

    $Ausgewaehlt = @(Select-SqlInstances -Kandidaten $Kandidaten)
    if ($Ausgewaehlt.Count -eq 0) {
        Write-Host "Keine Instanz ausgewählt. Skript wird beendet." -ForegroundColor Red
        return
    }
}

# - ZUGANGSDATEN PRO INSTANZ ABFRAGEN UND VERBINDUNG PRÜFEN (MAX. 3 VERSUCHE)
$Credentials = @{}
$Instanzen = @()
foreach ($k in $Ausgewaehlt) {
    $si = $k.ServerInstance
    $verbunden = $false
    $usedCred  = $null

    if (Test-SqlConnection -ServerInstance $si -Credential $null) {
        $verbunden = $true
        Write-Host "$si : Verbindung erfolgreich (Windows-Authentifizierung)." -ForegroundColor Green
    } else {
        Write-Host "$si : Windows-Authentifizierung fehlgeschlagen, SQL-Zugangsdaten erforderlich." -ForegroundColor Yellow

        ## Konto aus dem NET-COCKPIT als SQL-Login versuchen
        $cockpitKonto = Get-ZielKonto -Name $k.ComputerName
        if ($cockpitKonto -and (Test-SqlConnection -ServerInstance $si -Credential $cockpitKonto)) {
            $verbunden = $true; $usedCred = $cockpitKonto
            Write-Host "$si : Verbindung erfolgreich (Konto aus dem NET-COCKPIT als SQL-Login)." -ForegroundColor Green
        }

        for ($versuch = 1; $versuch -le $MaxLoginVersuche -and -not $verbunden; $versuch++) {
            if ($Automatik) { break }
            $cred = Get-Credential -Message "Versuch $versuch/$MaxLoginVersuche – SQL-Zugangsdaten für '$si' (Benutzername leer lassen = Instanz überspringen)"

            if (-not $cred -or [string]::IsNullOrWhiteSpace($cred.UserName)) {
                Write-Host "$si : keine Zugangsdaten eingegeben – wird übersprungen." -ForegroundColor Yellow
                break
            }

            if (Test-SqlConnection -ServerInstance $si -Credential $cred) {
                $verbunden = $true; $usedCred = $cred
                Write-Host "$si : Verbindung erfolgreich (SQL-Login)." -ForegroundColor Green
            } else {
                Write-Host "$si : Login fehlgeschlagen (Versuch $versuch/$MaxLoginVersuche)." -ForegroundColor Red
            }
        }
    }

    if ($verbunden) {
        $Credentials[$si] = $usedCred
        $Instanzen += $k
    } else {
        Write-Host "$si : nicht erreichbar – wird übersprungen." -ForegroundColor Yellow
        Add-Content $Datei "Instanz $si – nicht erreichbar (Windows-Authentifizierung fehlgeschlagen, keine gültigen SQL-Zugangsdaten), übersprungen."
    }
}

if ($Instanzen.Count -eq 0) {
    Add-Content $Datei "Keine der ausgewählten Instanzen war erreichbar."
    Write-Host "Keine Instanz erreichbar. Skript wird beendet." -ForegroundColor Red
    if ($Automatik) {
        Get-Content -LiteralPath $Datei | Write-Host
        Write-WtErgebnis -Skript '05.5-SQL-Server' -Ordner $Ausgabepfad -Ergebnisse @($Ausgewaehlt | ForEach-Object { [pscustomobject]@{ Ziel = $_.ServerInstance; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Instanz nicht erreichbar' } })
        exit 1
    }
    Start-Process notepad.exe $Datei
    return
}

Add-Content $Datei ("Geprüfte Instanzen: " + (($Instanzen | ForEach-Object { $_.ServerInstance }) -join ", "))

# - SAMMEL-OBJEKTE
$Proto = [ordered]@{
    Servername         = $env:COMPUTERNAME
    Datum              = (Get-Date -Format "dd.MM.yyyy")
    Speicherplaetze    = @()
    WartungsplaeneText = $null
    SqlLogsText        = $null
    SsmsText           = $null
}

$AllDbFindings         = @()
$AllBackupDriveLetters = New-Object System.Collections.Generic.HashSet[string]
$AllPlanFindings       = @()

# - GRUNDDATEN JE INSTANZ EINMALIG ERMITTELN (Edition, Backup-Pfad, Registry-/Log-Infos)
$InstanceMeta = @{}
foreach ($inst in $Instanzen) {
    $si   = $inst.ServerInstance
    $cred = $Credentials[$si]

    $meta = [PSCustomObject]@{ Info = $null; BackupPath = $null; RegInfo = $null }
    try { $meta.Info = Get-InstanceInfo -ServerInstance $si -Credential $cred } catch { }
    $meta.BackupPath = Get-BackupPath -ServerInstance $si -ComputerName $inst.ComputerName -InstanceName $inst.InstanceName -Credential $cred
    $meta.RegInfo     = Get-RemoteInstanceInfo -ComputerName $inst.ComputerName -InstanceName $inst.InstanceName

    $InstanceMeta[$si] = $meta
}

# - SPEICHERPLATZ (Backup-Ziel-Laufwerke, je Server/Laufwerk nur einmal geprüft)
$DriveWerte = @{}
$ErrAnzahl = @{}
$SsmsVersionen = @{}
Add-Content $Datei "`n--- Speicherplatz Sicherungslaufwerk ---"
$BackupTargetsSeen = New-Object System.Collections.Generic.HashSet[string]

foreach ($inst in $Instanzen) {
    $bp = $InstanceMeta[$inst.ServerInstance].BackupPath
    if ($bp -match '^([A-Z]):\\') {
        $dl  = $matches[1]
        $key = "$($inst.ComputerName)|$dl"
        if ($BackupTargetsSeen.Add($key)) {
            [void]$AllBackupDriveLetters.Add($dl)
            $free = Get-RemoteDriveFree -ComputerName $inst.ComputerName -DriveLetter $dl
            if ($free) {
                if (-not $DriveWerte.ContainsKey($inst.ComputerName)) { $DriveWerte[$inst.ComputerName] = @() }
                $DriveWerte[$inst.ComputerName] += [pscustomobject]@{ Laufwerk = "${dl}:"; FreiGB = [double]$free.FreeGB; GroesseGB = [double]$free.TotalGB; FreiProzent = $(if ($free.TotalGB -gt 0) { [math]::Round($free.FreeGB / $free.TotalGB * 100, 1) } else { 0 }) }
                Add-Content $Datei ("Laufwerk {0}: auf {1} – {2} GB frei von {3} GB" -f $dl, $inst.ComputerName, $free.FreeGB, $free.TotalGB)
                $Proto.Speicherplaetze += ("{0} {1}: {2} GB frei von {3} GB" -f $inst.ComputerName, $dl, $free.FreeGB, $free.TotalGB)
            } else {
                Add-Content $Datei ("Laufwerk {0}: auf {1} – nicht ermittelbar (kein Zugriff/PSDrive)" -f $dl, $inst.ComputerName)
            }
        }
    }
}
if ($BackupTargetsSeen.Count -eq 0) {
    Add-Content $Datei "Backup-Ziellaufwerke konnten aus InstanceDefaultBackupPath/BackupDirectory nicht ermittelt werden."
}

# - SQL SERVER FEHLERPROTOKOLLE (Pfad + letzte 3 Dateien + Fehler-Einträge aus dem aktuellen Log)
Add-Content $Datei "`n--- SQL Server Fehlerprotokolle ---"
foreach ($inst in $Instanzen) {
    $si   = $inst.ServerInstance
    $cred = $Credentials[$si]
    $reg  = $InstanceMeta[$si].RegInfo

    if ($reg -and $reg.PSObject.Properties.Name -contains 'RemoteError' -and $reg.RemoteError) {
        Add-Content $Datei "Instanz $si – Remote-Zugriff (WinRM) auf $($inst.ComputerName) fehlgeschlagen: $($reg.RemoteError)"
    } elseif ($reg -and $reg.LogPath) {
        Add-Content $Datei "Instanz $si – Logpfad: $($reg.LogPath)"
        foreach ($l in $reg.ErrorLogs) {
            Add-Content $Datei ("   {0} – geändert am {1}" -f $l.Name, ([datetime]$l.LastWriteTime).ToString("dd.MM.yyyy HH:mm:ss"))
        }
    } else {
        Add-Content $Datei "Instanz $si – Logpfad nicht ermittelbar."
    }

    $errEntries = Get-SqlErrorLogEntries -ServerInstance $si -Credential $cred
    $ErrAnzahl[$si] = @($errEntries).Count
    if ($errEntries.Count -gt 0) {
        Add-Content $Datei "  Fehler-Einträge im aktuellen ERRORLOG (Suchbegriff 'Error:', letzte $($errEntries.Count)):"
        foreach ($e in $errEntries) {
            $dt = if ($e.LogDate) { ([datetime]$e.LogDate).ToString("dd.MM.yyyy HH:mm:ss") } else { "-" }
            Add-Content $Datei ("    [{0}] {1}" -f $dt, [string]$e.Text)
        }
    } else {
        Add-Content $Datei "  Keine Fehler-Einträge ('Error:') im aktuellen ERRORLOG gefunden."
    }
}

# - SSMS (je Server nur einmal geprüft)
Add-Content $Datei "`n--- Management Studio Version ---"
$SsmsChecked = @{}
foreach ($inst in $Instanzen) {
    $cn = $inst.ComputerName
    if ($SsmsChecked.ContainsKey($cn)) { continue }
    $SsmsChecked[$cn] = $true

    $ssmsList = Get-RemoteSsmsVersions -ComputerName $cn
    if ($ssmsList -and $ssmsList.Count -gt 0) {
        foreach ($s in $ssmsList) {
            Add-Content $Datei ("{0}: Gefundene SSMS-Version: {1} | Pfad: {2}" -f $cn, $s.Version, $s.Path)
            $SsmsVersionen[$cn] = [string]$s.Version
            $Proto.SsmsText = ("{0}: installiert Version {1}, `n-- Aktualität über Microsoft SSMS Release Notes prüfen: https://learn.microsoft.com/de-de/ssms/release-history" -f $cn, $s.Version)
        }
    } else {
        Add-Content $Datei ("{0}: SSMS nicht gefunden oder Remote-Zugriff nicht möglich." -f $cn)
        if (-not $Proto.SsmsText) { $Proto.SsmsText = "nicht ermittelbar" }
    }
}

# - DATENBANKSICHERUNGEN + OPTIONAL EXPRESS BACKUP
Add-Content $Datei "`n--- Datenbanksicherungen ---"

$ExpressBackupPromptShown = $false
$doBackupAllExpress = $null
$defaultBackupDir = "D:\SQLBackups"

foreach ($inst in $Instanzen) {
    $si   = $inst.ServerInstance
    $cred = $Credentials[$si]
    $meta = $InstanceMeta[$si]
    $info = $meta.Info

    try {
        if (-not $info) { throw "Instanzinformationen (Edition/Version) nicht verfügbar." }
        Add-Content $Datei "Instanz: $si ($($info.ProductVersion) $($info.ProductLevel) $($info.Edition))"

        if ($meta.BackupPath) {
            Add-Content $Datei ("  Standard-Backup-Pfad: {0}" -f $meta.BackupPath)
        } else {
            Add-Content $Datei "  Standard-Backup-Pfad: nicht ermittelbar (SQL+Registry leer)"
        }

        if ($info.IsExpress) {
            Add-Content $Datei "  Hinweis: SQL Express erkannt – kein SQL Agent, keine Wartungspläne."

            if (-not $ExpressBackupPromptShown) {
                Add-Content $Datei "  Optional: Manuelles FULL-Backup aller User-DBs (database_id > 4)."
                Add-Content $Datei "  Backup-Ziel (Standard): $defaultBackupDir auf $($inst.ComputerName) (Dateien: <DBNAME>_<yyyyMMdd_HHmmss>_FULL.bak)"
                $doBackupAllExpress = if ($Automatik) { 'n' } else { Read-Host "SQL Express ($si): Manuelles FULL-Backup aller User-DBs nach $defaultBackupDir ausführen? (j/n)" }
                if ($doBackupAllExpress -eq 'j') {
                    try {
                        Invoke-OnComputer -ComputerName $inst.ComputerName -ScriptBlock {
                            param($Path)
                            if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
                        } -ArgumentList $defaultBackupDir | Out-Null
                        Add-Content $Datei "  Backup-Ziel verwendet: $defaultBackupDir auf $($inst.ComputerName)"
                    } catch {
                        Add-Content $Datei "  Backup-Ziel konnte nicht angelegt werden (Remote-Zugriff auf $($inst.ComputerName) fehlgeschlagen): $($_.Exception.Message)"
                        $doBackupAllExpress = 'n'
                    }
                } else {
                    Add-Content $Datei "  Manuelles Backup: übersprungen."
                }
                $ExpressBackupPromptShown = $true
            }

            if ($doBackupAllExpress -eq 'j') {
                $dbListQ = "SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;"
                $dbs = Invoke-SqlQuery -ServerInstance $si -Query $dbListQ -Credential $cred

                if (-not $dbs -or $dbs.Count -eq 0) {
                    Add-Content $Datei "  Manuelles Backup: keine User-Datenbanken gefunden (database_id > 4)."
                } else {
                    foreach ($d in $dbs) {
                        $dbName = [string]$d.name
                        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
                        $bak = Join-Path $defaultBackupDir ("{0}_{1}_FULL.bak" -f $dbName, $ts)

                        $q = "BACKUP DATABASE [$dbName] TO DISK = N'$bak' WITH INIT, CHECKSUM;"
                        $ok = Invoke-SqlNonQuery -ServerInstance $si -Query $q -Credential $cred

                        if ($ok) {
                            Add-Content $Datei "  Manuelles Backup OK: $dbName -> $bak"
                        } else {
                            Add-Content $Datei "  Manuelles Backup FEHLER: $dbName -> $bak"
                        }
                    }
                }
            }
        }

        $bkQ = @"
WITH last_backups AS (
  SELECT
    db.name AS DbName,
    db.recovery_model_desc AS RecoveryModel,
    (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset WHERE database_name = db.name AND type='D') AS LastFull,
    (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset WHERE database_name = db.name AND type='I') AS LastDiff,
    (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset WHERE database_name = db.name AND type='L') AS LastLog
  FROM sys.databases db
  WHERE db.database_id > 4
)
SELECT * FROM last_backups ORDER BY DbName;
"@
        $bk = Invoke-SqlQuery -ServerInstance $si -Query $bkQ -Credential $cred

        if ($bk.Count -gt 0) {
            foreach ($row in $bk) {
                $db  = $row.DbName
                $rec = $row.RecoveryModel

                $lf = if ($null -ne $row.LastFull -and $row.LastFull -isnot [DBNull]) { [datetime]$row.LastFull } else { $null }
                $ld = if ($null -ne $row.LastDiff -and $row.LastDiff -isnot [DBNull]) { [datetime]$row.LastDiff } else { $null }
                $ll = if ($null -ne $row.LastLog  -and $row.LastLog  -isnot [DBNull]) { [datetime]$row.LastLog  } else { $null }

                $fullOK = $lf -and (($Heute - $lf).TotalDays -le $FullMaxDays)
                $diffOK = if ($ld) { (($Heute - $ld).TotalDays -le $DiffMaxDays) } else { $false }
                $logOK  = if ($rec -in @('FULL','BULK_LOGGED')) { $ll -and (($Heute - $ll).TotalHours -le $LogMaxHours) } else { $true }

                $status = if (-not $fullOK) { "KRITISCH: Voll-Backup zu alt/fehlt" }
                          elseif (($rec -in @('FULL','BULK_LOGGED')) -and (-not $logOK)) { "KRITISCH: Log-Backup zu alt/fehlt" }
                          else { "OK" }

                $lfText = if ($lf) { $lf.ToString("dd.MM.yyyy HH:mm:ss") } else { "-" }
                $ldText = if ($ld) { $ld.ToString("dd.MM.yyyy HH:mm:ss") } else { "-" }
                $llText = if ($ll) { $ll.ToString("dd.MM.yyyy HH:mm:ss") } else { "-" }

                Add-Content $Datei "  DB: $db | Recovery: $rec | LastFull: $lfText | LastDiff: $ldText | LastLog: $llText | Bewertung: $status"

                $AllDbFindings += [PSCustomObject]@{
                    Instanz  = $si
                    DB       = $db
                    Recovery = $rec
                    LastFull = $lf
                    LastDiff = $ld
                    LastLog  = $ll
                    FullOK   = $fullOK
                    DiffOK   = $diffOK
                    LogOK    = $logOK
                }
            }
        } else {
            Add-Content $Datei "  Keine benutzerdefinierten Datenbanken gefunden oder keine Sicherungseinträge."
        }

    } catch {
        Add-Content $Datei ("Instanz: {0} – Fehler: {1}" -f $si, $_.Exception.Message)
    }
}

# - WARTUNGSPLÄNE (MSDB, falls vorhanden)
Add-Content $Datei "`n--- Wartungspläne ---"
foreach ($inst in $Instanzen) {
    $si   = $inst.ServerInstance
    $cred = $Credentials[$si]
    $info = $InstanceMeta[$si].Info

    try {
        if ($info -and $info.IsExpress) {
            Add-Content $Datei "Instanz: $si – SQL Express: keine Wartungspläne (kein SQL Agent)."
            continue
        }

        $planQ = @"
IF DB_ID('msdb') IS NULL OR OBJECT_ID('msdb.dbo.sysmaintplan_plans') IS NULL
BEGIN
  SELECT CAST(NULL AS sysname) AS PlanName, CAST(NULL AS datetime) AS Created, CAST(NULL AS datetime) AS Modified WHERE 1=0;
  RETURN;
END

-- Spaltennamen für Erstell-/Änderungsdatum unterscheiden sich je nach SQL Server Version
-- (u.a. createdate/create_date bzw. teils gar nicht vorhanden) -- daher zur Laufzeit ermitteln
-- statt fest zu verdrahten.
DECLARE @createCol sysname, @modifyCol sysname, @sql nvarchar(max);

SELECT TOP 1 @createCol = name FROM sys.columns
WHERE object_id = OBJECT_ID('msdb.dbo.sysmaintplan_plans')
  AND name IN ('createdate','create_date','date_created','datecreated');

SELECT TOP 1 @modifyCol = name FROM sys.columns
WHERE object_id = OBJECT_ID('msdb.dbo.sysmaintplan_plans')
  AND name IN ('modifydate','modify_date','date_modified','datemodified','lastmodifieddate');

SET @sql = N'SELECT name AS PlanName, ' +
           ISNULL(QUOTENAME(@createCol), 'CAST(NULL AS datetime)') + N' AS Created, ' +
           ISNULL(QUOTENAME(@modifyCol), 'CAST(NULL AS datetime)') + N' AS Modified ' +
           N'FROM msdb.dbo.sysmaintplan_plans ORDER BY name;';

EXEC sp_executesql @sql;
"@
        $plans = Invoke-SqlQuery -ServerInstance $si -Query $planQ -Credential $cred

        if ($plans -and $plans.Count -gt 0) {
            Add-Content $Datei "Instanz: $si – Wartungspläne gefunden: $($plans.Count)"
            foreach ($p in $plans) {
                ## DBNull-sichere Datumsauswertung
                $createdValue  = if ($null -ne $p.Created  -and $p.Created  -isnot [DBNull]) { [datetime]$p.Created }  else { $null }
                $modifiedValue = if ($null -ne $p.Modified -and $p.Modified -isnot [DBNull]) { [datetime]$p.Modified } else { $null }

                $AllPlanFindings += [PSCustomObject]@{
                    Instanz  = $si
                    Plan     = [string]$p.PlanName
                    Created  = $createdValue
                    Modified = $modifiedValue
                }
                $c = if ($createdValue)  { $createdValue.ToString("dd.MM.yyyy HH:mm") }  else { "-" }
                $m = if ($modifiedValue) { $modifiedValue.ToString("dd.MM.yyyy HH:mm") } else { "-" }
                Add-Content $Datei ("  Plan: {0} | erstellt: {1} | geändert: {2}" -f $p.PlanName, $c, $m)
            }
        } else {
            Add-Content $Datei "Instanz: $si – keine Wartungspläne gefunden."
        }
    } catch {
        Add-Content $Datei ("Instanz: {0} – Wartungspläne nicht prüfbar: {1}" -f $si, $_.Exception.Message)
    }
}

# - ZUSAMMENFASSUNGSDATEN (WARTUNGSPLÄNE / SQL-LOGS)
$InstanceEditions = foreach ($inst in $Instanzen) {
    $info = $InstanceMeta[$inst.ServerInstance].Info
    [PSCustomObject]@{ Instanz = $inst.ServerInstance; IsExpress = if ($info) { $info.IsExpress } else { $false } }
}
$AllInstancesAreExpress = ($InstanceEditions.Count -gt 0) -and ( ($InstanceEditions | Where-Object { -not $_.IsExpress }).Count -eq 0 )

if ($AllPlanFindings.Count -gt 0) {
    $Proto.WartungsplaeneText = "geprüft, $($AllPlanFindings.Count) Wartungsplan(e) gefunden."
} else {
    if ($AllInstancesAreExpress) {
        $Proto.WartungsplaeneText = "keine vorhanden (SQL Express – kein SQL Agent, daher keine Wartungspläne)."
    } else {
        $Proto.WartungsplaeneText = "keine vorhanden oder Zugriff nicht möglich."
    }
}

$logLines = (Get-Content $Datei) | Where-Object { $_ -match 'ERRORLOG' }
if ($logLines) {
    $times = foreach ($line in $logLines) {
        if ($line -match '(\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}:\d{2})$') {
            [datetime]::ParseExact($matches[1], 'dd.MM.yyyy HH:mm:ss', $null)
        }
    }
    if ($times) {
        $lastLog = ($times | Sort-Object -Descending | Select-Object -First 1)
        $Proto.SqlLogsText = "vorhanden, letzte Änderung am " + $lastLog.ToString("dd.MM.yyyy HH:mm") + " Uhr."
    } else {
        $Proto.SqlLogsText = "vorhanden, Zeitstempel nicht auswertbar."
    }
} else {
    $Proto.SqlLogsText = "nicht lesbar – Pfad-/Berechtigungsprüfung nötig."
}

# - PROTOKOLLVORSCHLAG
Add-Content $Datei "`n===== Protokollvorschlag (für Wartungsnotizen) ====="

Add-Content $Datei ("- {0}: {1}" -f $Proto.Servername, $Proto.Datum)

if ($AllDbFindings.Count -gt 0) {
    $anzahl = $AllDbFindings.Count

    $cntFullBad = ($AllDbFindings | Where-Object { -not $_.FullOK }).Count
    $cntDiffBad = ($AllDbFindings | Where-Object { $_.LastDiff -and (-not $_.DiffOK) }).Count
    $cntLogBad  = ($AllDbFindings | Where-Object { $_.Recovery -in @('FULL','BULK_LOGGED') -and (-not $_.LogOK) }).Count

    $latestFull = ($AllDbFindings | Where-Object LastFull | Sort-Object LastFull -Descending | Select-Object -First 1).LastFull
    $oldestFull = ($AllDbFindings | Where-Object LastFull | Sort-Object LastFull            | Select-Object -First 1).LastFull

    $latestDiff = ($AllDbFindings | Where-Object LastDiff | Sort-Object LastDiff -Descending | Select-Object -First 1).LastDiff
    $oldestDiff = ($AllDbFindings | Where-Object LastDiff | Sort-Object LastDiff            | Select-Object -First 1).LastDiff

    $latestLog  = ($AllDbFindings | Where-Object LastLog  | Sort-Object LastLog  -Descending | Select-Object -First 1).LastLog
    $oldestLog  = ($AllDbFindings | Where-Object LastLog  | Sort-Object LastLog             | Select-Object -First 1).LastLog

    $latestFullText = if ($latestFull) { $latestFull.ToString("dd.MM.yyyy HH:mm") } else { "-" }
    $oldestFullText = if ($oldestFull) { $oldestFull.ToString("dd.MM.yyyy HH:mm") } else { "-" }

    $latestDiffText = if ($latestDiff) { $latestDiff.ToString("dd.MM.yyyy HH:mm") } else { "-" }
    $oldestDiffText = if ($oldestDiff) { $oldestDiff.ToString("dd.MM.yyyy HH:mm") } else { "-" }

    $latestLogText  = if ($latestLog)  { $latestLog.ToString("dd.MM.yyyy HH:mm") } else { "-" }
    $oldestLogText  = if ($oldestLog)  { $oldestLog.ToString("dd.MM.yyyy HH:mm") } else { "-" }

    $backupTargets = if ($AllBackupDriveLetters -and $AllBackupDriveLetters.Count -gt 0) {
        (($AllBackupDriveLetters | Sort-Object) | ForEach-Object { $_ + ":" }) -join ", "
    } else { "-" }

    $bewertung = if (($cntFullBad + $cntLogBad) -eq 0) { "alle Sicherungen aktuell" } else { "Auffälligkeiten vorhanden" }

    $zeile = "- Datenbanksicherungen: $anzahl DB(s), Voll: neueste $latestFullText | älteste $oldestFullText | Abweichungen $cntFullBad; Diff: neueste $latestDiffText | älteste $oldestDiffText | Abweichungen $cntDiffBad; Log: neueste $latestLogText | älteste $oldestLogText | Abweichungen $cntLogBad; Ziel (msdb/Reg): $backupTargets – $bewertung."
    Add-Content $Datei $zeile
} else {
    Add-Content $Datei "- Datenbanksicherungen: keine Datenbanken gefunden oder Zugriff fehlgeschlagen."
}

if ($Proto.Speicherplaetze.Count -gt 0) {
    $sp = ($Proto.Speicherplaetze -join " | ").Replace(",", ".")
    Add-Content $Datei ("- Speicherplatz: {0}" -f $sp)
} else {
    Add-Content $Datei "- Speicherplatz: keine Backup-Ziellaufwerke ermittelt."
}

Add-Content $Datei ("- Wartungspläne: {0}" -f $Proto.WartungsplaeneText)
Add-Content $Datei ("- SQL-Protokolle: {0}" -f $Proto.SqlLogsText)

$ssmsText = if ($Proto.SsmsText) { $Proto.SsmsText } else { "nicht geprüft" }
Add-Content $Datei ("- Management Studio: {0}" -f $ssmsText)

# - ABSCHLUSS
Add-Content $Datei "`n===== Ende SQL Check ====="
Write-Host ("SQL Kurzcheck abgeschlossen. Datei gespeichert unter: {0}" -f $Datei) -ForegroundColor Yellow

if ($Automatik) {
    Get-Content -LiteralPath $Datei | Write-Host

    # - ERGEBNIS FÜR DIE CHECKLISTE (je Instanz; Haken = geprüft und in Ordnung; nur was ermittelt wurde, steht drin)
    $erreichbar = @($Instanzen | ForEach-Object { $_.ServerInstance })
    $ergebnisListe = [System.Collections.Generic.List[object]]::new()
    foreach ($k in $Ausgewaehlt) {
        $si = $k.ServerInstance
        if ($si -notin $erreichbar) {
            $ergebnisListe.Add([pscustomobject]@{ Ziel = $si; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Instanz nicht erreichbar (Anmeldung fehlgeschlagen)' })
            continue
        }
        $pr = [ordered]@{}
        $probleme = @()
        $meta = $InstanceMeta[$si]
        $werte = [ordered]@{}
        if ($meta.Info) { $werte['Version'] = "$($meta.Info.ProductVersion) $($meta.Info.ProductLevel)"; $werte['Edition'] = $meta.Info.Edition }
        $dbs = @($AllDbFindings | Where-Object { $_.Instanz -eq $si })
        $werte['Datenbanken'] = $dbs.Count
        if ($dbs.Count -gt 0) {
            $schlecht = @($dbs | Where-Object { -not $_.FullOK -or ($_.Recovery -in @('FULL', 'BULK_LOGGED') -and -not $_.LogOK) })
            $pr['SqlSicherungenAktuell'] = ($schlecht.Count -eq 0)
            if ($schlecht.Count -gt 0) { $probleme += "Sicherung zu alt/fehlt: $(@($schlecht | ForEach-Object { $_.DB }) -join ', ')" }
        }
        if ($DriveWerte.ContainsKey($k.ComputerName)) {
            $werte['Speicherplatz'] = @($DriveWerte[$k.ComputerName])
            $pr['SpeicherplatzOk'] = (@($DriveWerte[$k.ComputerName] | Where-Object { $_.FreiProzent -lt 10 }).Count -eq 0)
            if (-not $pr['SpeicherplatzOk']) { $probleme += 'Sicherungslaufwerk unter 10 % frei' }
        }
        $werte['Wartungsplaene'] = @($AllPlanFindings | Where-Object { $_.Instanz -eq $si }).Count
        if ($ErrAnzahl.ContainsKey($si)) { $werte['FehlerImErrorlog'] = $ErrAnzahl[$si] }
        if ($SsmsVersionen.ContainsKey($k.ComputerName)) { $werte['SsmsVersion'] = $SsmsVersionen[$k.ComputerName] }
        $ergebnisListe.Add([pscustomobject]@{ Ziel = $si; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]$werte; Notiz = ($probleme -join '; ') })
    }
    Write-WtErgebnis -Skript '05.5-SQL-Server' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    exit 0
}

Start-Process notepad.exe $Datei