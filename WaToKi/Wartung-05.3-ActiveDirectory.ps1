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
Write-Host "=== Wartung-05.3-ActiveDirectory ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
if (-not $Automatik) { Write-Host @'
BESCHREIBUNG
Prüft einen oder alle Domain Controller: DCDIAG, inaktive Benutzer-/Computerkonten (>90 Tage), GPOs mit Softwarepaketen, gestoppte automatische Dienste, DHCP-Statistik, DNS-Root-Hints-Abgleich gegen offizielle Liste. Interaktive Auswahl von DC und optional OU, Ergebnis wird in Datei geschrieben.
Alle Abfragen laufen auf dem jeweiligen Domaincontroller selbst (per Invoke-Command: DCDIAG, Konten, Gruppenrichtlinien, Dienste, DHCP, DNS-Root-Hints). Der ausführende Rechner braucht dafür keine RSAT-Tools. Bevorzugt wird der Endpunkt PowerShell.7 auf dem DC, fehlt er, nimmt das Skript Windows PowerShell 5.1.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Domaincontroller (-Ziel), den Ausgabeordner (-Ausgabeordner) und je DC das Konto der Spalte "Konto" (-AnmeldedatenJeZiel). Dann entfallen die Abfragen von DC-Auswahl und OU-Einschränkung (es wird die gesamte Domain geprüft).

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Auf den Ziel-DCs: WinRM aktiviert (Enable-PSRemoting -Force) und Domain-Admin-Rechte; die Tools für Active Directory, Gruppenrichtlinien, DNS und DHCP sind dort mit den Rollen vorhanden
- Nur beim manuellen Start ohne NET-COCKPIT (DC-Suche und OU-Auswahl): RSAT "Active Directory-Verwaltungstools" auf dem ausführenden Rechner
- Internetzugriff auf dem ausführenden Rechner für den DNS-Root-Hints-Abgleich (https://www.internic.net/domain/named.root)
'@ -ForegroundColor Yellow }
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
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (Domaincontroller) nötig." -ForegroundColor Red
    exit 1
}
$dcErgebnisse = [System.Collections.Generic.List[object]]::new()

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



# - Modus-Auswahl
$Server = $env:COMPUTERNAME
$Datum  = Get-Date -Format "yyyyMMdd"

## Das ActiveDirectory-Modul braucht nur die manuelle Auswahl (DC-Suche, OU-Auswahl); aus dem NET-COCKPIT laufen alle Abfragen auf den DCs selbst
if (-not $ZielModus) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        throw "ActiveDirectory-Modul fehlt. RSAT 'Active Directory-Verwaltungstools' installieren oder Script auf einem DC/Management-Server ausführen."
    }
}
if ($ZielModus) {
    $AllDCs = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    $OUFilter = $null
    Write-Host "Zu prüfende Domaincontroller (aus dem NET-COCKPIT):" -ForegroundColor Yellow
    $AllDCs | ForEach-Object { Write-Host " - $_" }
    $Dateiname = if ($AllDCs.Count -eq 1) { "Wartung_${Datum}_AD-$($AllDCs[0]).txt" } else { "Wartung_${Datum}_AD-DCs.txt" }
}
else {
    Write-Host "# AUSWAHL DomainController" -ForegroundColor Cyan
    Write-Host "1 = Alle DCs im Netzwerk pruefen"
    Write-Host "2 = Nur einen einzelnen DC pruefen"
    do {
        $Modus = (Read-Host "Bitte Auswahl eingeben [1/2]").Trim()
        if ($Modus -notin @("1","2")) {
            Write-Host "Ungueltige Eingabe. Bitte 1 oder 2 eingeben." -ForegroundColor Red
        }
    } while ($Modus -notin @("1","2"))

    # -- OU-Auswahl (grafisch, 10 Sekunden Zeitfenster)
    function Show-OUPicker {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $OUs = Get-ADOrganizationalUnit -Filter * -Properties DistinguishedName |
            Select-Object Name, DistinguishedName

        $Form = New-Object System.Windows.Forms.Form
        $Form.Text = "OU auswaehlen"
        $Form.Size = New-Object System.Drawing.Size(500,600)
        $Form.StartPosition = "CenterScreen"

        $Tree = New-Object System.Windows.Forms.TreeView
        $Tree.Size = New-Object System.Drawing.Size(465,480)
        $Tree.Location = New-Object System.Drawing.Point(10,10)
        $Form.Controls.Add($Tree)

        $NodeMap = @{}
        foreach ($OU in ($OUs | Sort-Object { $_.DistinguishedName.Length })) {
            $ParentDN = ($OU.DistinguishedName -replace '^OU=[^,]+,', '')
            $Node = New-Object System.Windows.Forms.TreeNode($OU.Name)
            $Node.Tag = $OU.DistinguishedName
            $NodeMap[$OU.DistinguishedName] = $Node

            if ($NodeMap.ContainsKey($ParentDN)) {
                $NodeMap[$ParentDN].Nodes.Add($Node) | Out-Null
            } else {
                $Tree.Nodes.Add($Node) | Out-Null
            }
        }
        $Tree.ExpandAll()

        $OkButton = New-Object System.Windows.Forms.Button
        $OkButton.Text = "OK"
        $OkButton.Location = New-Object System.Drawing.Point(300,500)
        $OkButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $Form.Controls.Add($OkButton)
        $Form.AcceptButton = $OkButton

        $CancelButton = New-Object System.Windows.Forms.Button
        $CancelButton.Text = "Alle OUs"
        $CancelButton.Location = New-Object System.Drawing.Point(390,500)
        $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $Form.Controls.Add($CancelButton)
        $Form.CancelButton = $CancelButton

        $Result = $Form.ShowDialog()

        if ($Result -eq [System.Windows.Forms.DialogResult]::OK -and $Tree.SelectedNode) {
            return $Tree.SelectedNode.Tag
        }
        return $null
    }

    Write-Host "OU einschraenken? ( 10 Sekunden Zeit fuer Eingabe, danach automatisch Option 1 )" -ForegroundColor Cyan
    Write-Host "1 = Nein, gesamte OU pruefen (Standard)"
    Write-Host "2 = Ja, OU einschraenken"

    $OUAuswahl = "1"

    $Runspace = [runspacefactory]::CreateRunspace($Host)
    $Runspace.Open()
    $PS = [PowerShell]::Create()
    $PS.Runspace = $Runspace
    $PS.AddScript({ Read-Host "Eingabe (1/2)" }) | Out-Null

    $Async = $PS.BeginInvoke()
    if ($Async.AsyncWaitHandle.WaitOne(10000)) {
        $Eingabe = $PS.EndInvoke($Async)
        if ($Eingabe -eq "2") { $OUAuswahl = "2" }
    } else {
        Write-Host ""
        Write-Host "Kein Eingabe innerhalb 10 Sekunden - Standard 1 wird verwendet."
        $PS.Stop()
    }
    $PS.Dispose()
    $Runspace.Close()

    if ($OUAuswahl -eq "2") {
        $OUFilter = Show-OUPicker
    } else {
        $OUFilter = $null
    }

    switch ($Modus) {
        "1" {
            $AllDCs = @(Get-ADDomainController -Filter * | Sort-Object HostName | Select-Object -ExpandProperty HostName)
            if (-not $AllDCs -or $AllDCs.Count -lt 1) {
                throw "Keine Domaincontroller gefunden."
            }
            Write-Host "Gefundene Domaincontroller:" -ForegroundColor Yellow
            $AllDCs | ForEach-Object { Write-Host " - $_" }
            $Dateiname = "Wartung_${Datum}_AD-ALL-DCs.txt"
        }
        "2" {
            $DCName = Read-Host "Bitte Domaincontroller eingeben (Enter = $env:COMPUTERNAME)"
            if ([string]::IsNullOrWhiteSpace($DCName)) {
                $DCName = $env:COMPUTERNAME
            }
            try {
                $SelectedDC = Get-ADDomainController -Identity $DCName -ErrorAction Stop
            } catch {
                throw "Domaincontroller '$DCName' wurde nicht gefunden."
            }
            $AllDCs = @($SelectedDC.HostName)
            Write-Host "Pruefe nur diesen Domaincontroller: $($AllDCs[0])" -ForegroundColor Yellow
            $Dateiname = "Wartung_${Datum}_AD-$($AllDCs[0]).txt"
        }
        default {
            throw "Ungueltige Auswahl. Bitte 1 oder 2 eingeben."
        }
    }
}

# - Hilfsfunktion lokal/remote (Loopback-Fix, bevorzugt PowerShell 7, sonst Windows PowerShell 5.1 auf dem DC)
function Invoke-OnDC {
    param(
        [string]$ComputerName,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList
    )
    if ($ComputerName -eq $env:COMPUTERNAME -or $ComputerName -like "$env:COMPUTERNAME.*") {
        & $ScriptBlock @ArgumentList
    } else {
        $cp = @{}
        $konto = Get-ZielKonto -Name $ComputerName
        if ($konto) { $cp.Credential = $konto }
        try {
            Invoke-Command -ComputerName $ComputerName @cp -ConfigurationName 'PowerShell.7' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
        }
        catch {
            if ($_.Exception.Message -match 'PowerShell\.7|Sitzungskonfiguration|session configuration') {
                Invoke-Command -ComputerName $ComputerName @cp -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
            }
            else { throw }
        }
    }
}

# - Domain ermitteln
if ($ZielModus) {
    try {
        $Domain = Invoke-OnDC -ComputerName $AllDCs[0] -ScriptBlock { Import-Module ActiveDirectory; (Get-ADDomain).DNSRoot }
    } catch {
        $Domain = $null
        Write-Host "Domain konnte nicht ermittelt werden: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    $Domain = (Get-ADDomain).DNSRoot
}

# - Ausgabedatei
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname

Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue

Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_START"
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "#INFO:"
Add-Content $AusgabeDatei "# Server: $Server"
Add-Content $AusgabeDatei "# Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
Add-Content $AusgabeDatei "# Domaincontroller (Anzahl): $($AllDCs.Count)"
Add-Content $AusgabeDatei "# Domaincontroller: $($AllDCs -join ', ')"
Add-Content $AusgabeDatei "# OU-Filter (Konten-Pruefung): $(if ($OUFilter) { $OUFilter } else { 'gesamte Domain' })"
Add-Content $AusgabeDatei "# Diese Datei wurde automatisch im Rahmen einer proaktiven IT-Wartung erstellt."
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "=== BEGINN DER ACTIVE DIRECTORY-WARTUNGSDATEN ==="
Add-Content $AusgabeDatei ""

# - Root-Hints Vergleich (Online-Liste)
$OnlineUrl = "https://www.internic.net/domain/named.root"

function Normalize-RootName([string]$n) {
    if (-not $n) { return $null }
    return $n.Trim().TrimEnd('.').ToLower()
}

try {
    $onlineText = (Invoke-WebRequest -Uri $OnlineUrl -UseBasicParsing -ErrorAction Stop).Content
    $onlineLines = $onlineText -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^(;|#)' }

    $OnlineRootServers = @(
        $onlineLines |
        ForEach-Object {
            if ($_ -match '(?i)^\.\s+(?:\d+\s+)?(?:IN\s+)?NS\s+([a-z0-9\.\-]+)\.?$') {
            Normalize-RootName $matches[1]
            }
        } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )

    # -- Offizielle IPs je Nameserver (A/AAAA) aus derselben Datei
    $OnlineRootIPs = @{}
    foreach ($line in $onlineLines) {
        if ($line -match '(?i)^([a-z0-9\.\-]+)\.\s+(?:\d+\s+)?(?:IN\s+)?(A|AAAA)\s+([0-9a-fA-F:\.]+)$') {
            $ns = Normalize-RootName $matches[1]
            $ip = $matches[3].Trim()
            if (-not $OnlineRootIPs.ContainsKey($ns)) { $OnlineRootIPs[$ns] = @() }
            $OnlineRootIPs[$ns] += $ip
        }
    }
} catch {
    $OnlineRootServers = @()
    $OnlineRootIPs = @{}
    Add-Content $AusgabeDatei "WARNUNG: Online Root-Server-Liste konnte nicht geladen werden: $($_.Exception.Message)"
    Add-Content $AusgabeDatei ""
}

# - Pruefungen je DC
foreach ($TargetDC in $AllDCs) {

    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "============================================================"
    Add-Content $AusgabeDatei "===== DOMAINCONTROLLER: $TargetDC"
    Add-Content $AusgabeDatei "============================================================"
    Add-Content $AusgabeDatei ""

    Write-Host "`nAbfrage auf ${TargetDC} wird ausgefuehrt..." -ForegroundColor Yellow
    $prDc = [ordered]@{}
    $werteDc = [ordered]@{}
    $notizDc = @()
    $dcErreicht = $false

     # -- DCDIAG
    Add-Content $AusgabeDatei "===== 1. DCDIAG ====="
    try {
        if ($ZielModus) {
            ### Aus dem NET-COCKPIT: dcdiag läuft auf dem DC selbst
            $dcdiag = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock { dcdiag /v | Out-String }
        } else {
            $dcdiag = dcdiag /s:$TargetDC /v | Out-String
        }
        Add-Content $AusgabeDatei $dcdiag
        $dcErreicht = $true
        $dcdiagFehler = @(($dcdiag -split "`r?`n") | Where-Object { $_ -match '(?i)(\bfailed test\b|nicht bestanden)' })
        $prDc['DcdiagOk'] = ($dcdiagFehler.Count -eq 0)
        if ($dcdiagFehler.Count -gt 0) { $notizDc += "DCDIAG: $($dcdiagFehler.Count) Test(s) nicht bestanden" }
    } catch {
        Add-Content $AusgabeDatei "Fehler beim Ausführen von DCDIAG: $($_.Exception.Message)"
    }

    # -- Inaktive Konten
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "===== 2. Verwaiste / Inaktive Konten ====="
    try {
        $alteBenutzer = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
            param($SearchBase)
            Import-Module ActiveDirectory
            $Grenze = (Get-Date).AddDays(-90)
            $Params = @{ Filter = { Enabled -eq $true }; Properties = "LastLogonDate" }
            if ($SearchBase) { $Params["SearchBase"] = $SearchBase }
            Get-ADUser @Params |
                Where-Object { $_.LastLogonDate -lt $Grenze } |
                Select-Object Name, SamAccountName, LastLogonDate
        } -ArgumentList $OUFilter

        $alteComputer = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
            param($SearchBase)
            Import-Module ActiveDirectory
            $Grenze = (Get-Date).AddDays(-90)
            $Params = @{ Filter = { Enabled -eq $true }; Properties = "LastLogonDate" }
            if ($SearchBase) { $Params["SearchBase"] = $SearchBase }
            Get-ADComputer @Params |
                Where-Object { $_.LastLogonDate -lt $Grenze } |
                Select-Object Name, SamAccountName, LastLogonDate
        } -ArgumentList $OUFilter

        $werteDc['InaktiveBenutzer'] = @($alteBenutzer).Count
        $werteDc['InaktiveComputer'] = @($alteComputer).Count
        Add-Content $AusgabeDatei "Inaktive Benutzerkonten (>90 Tage ohne Anmeldung):"
        if ($alteBenutzer) { $alteBenutzer | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei }
        else { Add-Content $AusgabeDatei "Keine inaktiven Benutzerkonten gefunden." }

        Add-Content $AusgabeDatei ""
        Add-Content $AusgabeDatei "Inaktive Computerkonten (>90 Tage ohne Anmeldung):"
        if ($alteComputer) { $alteComputer | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei }
        else { Add-Content $AusgabeDatei "Keine inaktiven Computerkonten gefunden." }

    } catch {
        Add-Content $AusgabeDatei "Fehler bei der Prüfung verwaister Konten: $($_.Exception.Message)"
    }

    # -- GPO Software
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "===== 3. Gruppenrichtlinien mit Softwarepaketen ====="
    try {
        $gpoSoftware = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
            Import-Module GroupPolicy
            Get-GPO -All | ForEach-Object {
                $gpo = $_
                $xml = Get-GPOReport -Guid $gpo.Id -ReportType Xml
                if ($xml -match "<AppMgmt>") {
                    [PSCustomObject]@{
                        GPOName         = $gpo.DisplayName
                        LetzteAenderung = $gpo.ModificationTime
                    }
                }
            }
        }

        if ($gpoSoftware) {
            Add-Content $AusgabeDatei "Gefundene GPOs mit Softwarepaketen:"
            $gpoSoftware | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei
        } else {
            Add-Content $AusgabeDatei "Keine GPOs mit Softwarepaketen gefunden."
        }
    } catch {
        Add-Content $AusgabeDatei "Fehler bei der Prüfung der Gruppenrichtlinien: $($_.Exception.Message)"
    }

    # -- Dienste (Remote)
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "===== 4. Automatische Dienste im Status 'Stopped' ====="
    try {
        $stoppedServicesText = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
            Get-Service |
                Where-Object { $_.StartType -eq "Automatic" -and $_.Status -eq "Stopped" } |
                Select-Object Status, StartType, DisplayName |
                Format-Table -AutoSize |
                Out-String
        }

        if ($stoppedServicesText -and $stoppedServicesText.Trim()) {
            Add-Content $AusgabeDatei $stoppedServicesText
            $prDc['DiensteGestartet'] = $false
            $werteDc['DiensteGestoppt'] = @(($stoppedServicesText -split "`r?`n") | Where-Object { $_.Trim() -and $_.Trim() -notmatch '^(Status\s|-{3,})' } | ForEach-Object { $_.Trim() })
            $notizDc += 'Automatische Dienste gestoppt'
        } else {
            Add-Content $AusgabeDatei "Keine gestoppten automatischen Dienste gefunden."
            $prDc['DiensteGestartet'] = $true
        }
    } catch {
        Add-Content $AusgabeDatei "Fehler bei der Dienstprüfung: $($_.Exception.Message)"
    }

    # -- DHCP Statistik (nur wenn DHCP-Dienst vorhanden)
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "===== 5. DHCP Statistik ====="
    Write-Host ""
    Write-Host "===== DHCP Statistik =====" -ForegroundColor Cyan
    try {
        $dhcpRole = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
            [bool](Get-Service -Name DHCPServer -ErrorAction SilentlyContinue)
        }

        if (-not $dhcpRole) {
            Add-Content $AusgabeDatei "DHCP-Dienst nicht vorhanden – Statistik wird auf diesem Server nicht geprüft."
            Write-Host "DHCP-Dienst nicht vorhanden auf $TargetDC" -ForegroundColor Yellow
        } else {
            $dhcpStats = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
                Get-DhcpServerv4Statistics | Select-Object TotalScopes, TotalAddresses, AddressesInUse, AddressesAvailable, PercentageInUse, PercentageAvailable | Format-List | Out-String
            }
            Add-Content $AusgabeDatei $dhcpStats
            Write-Host $dhcpStats
        }
    } catch {
        Add-Content $AusgabeDatei "Fehler bei der DHCP-Statistik: $($_.Exception.Message)"
    }

    # -- DNS Root Hints (Online vs. Lokal) (nur wenn DNS-Dienst vorhanden)
    Add-Content $AusgabeDatei ""
    Add-Content $AusgabeDatei "===== DNS Root Hints / Root Nameserver (Online vs. Lokal) ====="
    Write-Host ""
    Write-Host "===== DNS Root Hints =====" -ForegroundColor Cyan
    try {
        $dnsRole = Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
            $svc = Get-Service -Name DNS -ErrorAction SilentlyContinue
            [bool]$svc
        }

        if (-not $dnsRole) {
            Add-Content $AusgabeDatei "DNS-Dienst nicht vorhanden – Root Hints werden auf diesem Server nicht geprüft."
        } else {

            ### Root Hints laufen auf dem DC selbst und kommen als einfache Werte (Nameserver, IP) zurück
            $hintRoh = @(Invoke-OnDC -ComputerName $TargetDC -ScriptBlock {
                Import-Module DnsServer
                Get-DnsServerRootHint -ErrorAction Stop | ForEach-Object {
                    $ns = ([string]$_.NameServer.RecordData.NameServer).Trim().TrimEnd('.').ToLower()
                    foreach ($ipObj in @($_.IPAddress)) {
                        $ip = $null

                        if ($ipObj -is [string]) { $ip = $ipObj }
                        elseif ($ipObj.IPAddressToString) { $ip = $ipObj.IPAddressToString }
                        elseif ($ipObj.RecordData) {
                            if ($ipObj.RecordData.IPv4Address) { $ip = $ipObj.RecordData.IPv4Address.ToString() }
                            if ($ipObj.RecordData.IPv6Address) { $ip = $ipObj.RecordData.IPv6Address.ToString() }
                        }

                        if ($ns -and $ip) { [pscustomobject]@{ NameServer = $ns; IP = $ip.Trim() } }
                    }
                }
            })
            $local = $hintRoh |
                Group-Object NameServer |
                ForEach-Object {
                    [pscustomobject]@{
                        NameServer = $_.Name
                        LocalIPs   = @($_.Group.IP | Where-Object { $_ } | Sort-Object -Unique)
                    }
                }

            $localServers = $local | Select-Object -ExpandProperty NameServer | Sort-Object -Unique

            $onlineServers = $OnlineRootServers
            if (-not $onlineServers -or $onlineServers.Count -lt 1) {
                $onlineServers = $localServers
                Add-Content $AusgabeDatei "Hinweis: Online-Liste nicht verfügbar – Vergleich erfolgt gegen lokal ermittelte Nameserver."
                Add-Content $AusgabeDatei ""
            }

            $missingLocal = $onlineServers | Where-Object { $_ -notin $localServers }
            $extraLocal   = $localServers  | Where-Object { $_ -notin $onlineServers }

            $compare = foreach ($srv in $onlineServers) {
                $localIps = @(($local | Where-Object NameServer -eq $srv).LocalIPs)
                if (-not $localIps) { $localIps = @() }

                $officialIps = @()
                if ($OnlineRootIPs.ContainsKey($srv)) { $officialIps = $OnlineRootIPs[$srv] }

                # Vergleich nur in den Adressfamilien, die lokal vorhanden sind (lokale Hints enthalten meist nur IPv4)
                $vergleichIps = @($officialIps)
                if (-not (@($localIps | Where-Object { $_ -match ":" }).Count)) { $vergleichIps = @($officialIps | Where-Object { $_ -notmatch ":" }) }

                $localJoin    = (@($localIps)    | Sort-Object -Unique) -join "|"
                $officialJoin = (@($vergleichIps) | Sort-Object -Unique) -join "|"

                [pscustomobject]@{
                    NameServer       = $srv
                    LocalIPs         = ($localIps    -join ", ")
                    OfficialIPs      = ($officialIps -join ", ")
                    NameInLocalHints = ($srv -in $localServers)
                    IPsMatch         = ($localJoin -eq $officialJoin)
                }
            }

            Add-Content $AusgabeDatei "ONLINE Root-Servers (Anzahl): $($onlineServers.Count)"
            Add-Content $AusgabeDatei "LOKAL Root-Hints (Anzahl):      $($localServers.Count)"
            Add-Content $AusgabeDatei ""

            if ($missingLocal.Count -gt 0) {
                Add-Content $AusgabeDatei "FEHLT LOKAL: $($missingLocal -join ', ')"
                Write-Host "FEHLT LOKAL: $($missingLocal -join ', ')" -ForegroundColor Red
            } else {
                Add-Content $AusgabeDatei "FEHLT LOKAL: keine"
                Write-Host "FEHLT LOKAL: keine (Root-Hints vollstaendig)" -ForegroundColor Green
            }
            if ($extraLocal.Count -gt 0) {
                Add-Content $AusgabeDatei "ZUSATZ LOKAL: $($extraLocal -join ', ')"
                Write-Host "ZUSATZ LOKAL: $($extraLocal -join ', ')" -ForegroundColor Yellow
            } else {
                Add-Content $AusgabeDatei "ZUSATZ LOKAL: keine"
                Write-Host "ZUSATZ LOKAL: keine" -ForegroundColor Green
            }
            Add-Content $AusgabeDatei ""

            $compare | Sort-Object NameServer | Format-Table -AutoSize | Out-String | Add-Content $AusgabeDatei

            if ($OnlineRootServers.Count -gt 0) {
                $prDc['RootHintsOk'] = (@($missingLocal).Count -eq 0 -and @($compare | Where-Object { $_.IPsMatch -eq $false }).Count -eq 0)
                if (-not $prDc['RootHintsOk']) { $notizDc += 'Root-Hints weichen von der offiziellen Liste ab' }
            }

            if (($compare | Where-Object { $_.NameInLocalHints -eq $false }).Count -gt 0) {
                Add-Content $AusgabeDatei ""
                Add-Content $AusgabeDatei "WARNUNG: Mindestens ein Root-Nameserver fehlt lokal."
            }
            if (($compare | Where-Object { $_.IPsMatch -eq $false }).Count -gt 0) {
                $betroffene = ($compare | Where-Object { $_.IPsMatch -eq $false } | Select-Object -ExpandProperty NameServer) -join ', '

                Add-Content $AusgabeDatei ""
                Add-Content $AusgabeDatei "WARNUNG: Root-Hints stimmen nicht mit der offiziellen Referenzliste ueberein: $betroffene"
                Add-Content $AusgabeDatei "Korrektur: DNS-Konsole (dnsmgmt.msc) -> Servereigenschaften -> Reiter 'Stammhinweise' -> betroffenen Eintrag bearbeiten -> 'Resolve' klicken."

                Write-Host ""
                Write-Host "WARNUNG: Root-Hints stimmen nicht mit der offiziellen Referenzliste ueberein: $betroffene" -ForegroundColor Red
                Write-Host "Korrektur: DNS-Konsole (dnsmgmt.msc) -> Servereigenschaften -> Reiter 'Stammhinweise' -> betroffenen Eintrag bearbeiten -> 'Resolve' klicken." -ForegroundColor Red
            }

            $compare | Sort-Object NameServer | Select-Object NameServer, LocalIPs, NameInLocalHints, IPsMatch | Format-Table -AutoSize

            Write-Host "Die Liste der aktuellen Root Hints ist hier zu finden: $OnlineUrl" -ForegroundColor Gray

        }

    } catch {
        Add-Content $AusgabeDatei "Fehler bei Root-Hints-Prüfung: $($_.Exception.Message)"
        Add-Content $AusgabeDatei "Korrektur der Root-Hints siehe https://github.com/frankenfrank/microsoft/blob/main/server/root-hints_update.ps1"
    }

    $dcErgebnisse.Add([pscustomobject]@{ Ziel = $TargetDC; Erreicht = $dcErreicht; Pruefungen = [pscustomobject]$prDc; Werte = [pscustomobject]$werteDc; Notiz = $(if ($dcErreicht) { $notizDc -join '; ' } else { 'Domaincontroller nicht erreichbar oder DCDIAG fehlgeschlagen' }) })
}

Write-Host "Verwaiste Benutzer- und Computerkonten sind im Auswertungslog $AusgabeDatei aufgelistet" -ForeGroundColor Yellow
Add-Content $AusgabeDatei ""
Add-Content $AusgabeDatei "=== ENDE DER ACTIVE DIRECTORY-WARTUNGSDATEN ==="
Add-Content $AusgabeDatei "#WARTUNG_EVENTLOG_ENDE"
Write-Host ""
Write-Host "Resultate wurden gespeichert in $AusgabeDatei" -ForegroundColor Cyan

if ($Automatik) {
    Get-Content -LiteralPath $AusgabeDatei | Write-Host
    Write-WtErgebnis -Skript '05.3-ActiveDirectory' -Ordner $Ausgabepfad -Ergebnisse $dcErgebnisse.ToArray()
    if (@($dcErgebnisse | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}

Start-Process notepad.exe $AusgabeDatei