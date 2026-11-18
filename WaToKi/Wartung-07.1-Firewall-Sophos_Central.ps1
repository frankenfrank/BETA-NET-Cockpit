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
Write-Host "=== Wartung-07.1-Firewall-Sophos_Central ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Prüft Sophos Central per API (Endpoint-Health, Tamper Protection, letzter Kontakt, offene Alerts, Firewalls inkl. Firmware/Verbindung, Lizenzen) und schreibt das Ergebnis in eine Logdatei. Bei Partner-/Organisations-Zugang werden alle Mandanten nacheinander geprüft.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet wird der Ausgabeordner (-Ausgabeordner), der Eintrag der Tabelle (-Ziel, nur als Bezeichnung) und das Konto der Spalte "Konto" (-Anmeldedaten: Benutzername = ClientID, Kennwort = Geheimer Clientschlüssel) übergeben. Die Abfrage läuft über die Sophos-Cloud. Ohne -Anmeldedaten werden ClientID und Clientschlüssel abgefragt.

VORAUSSETZUNGEN
- API-Zugangsdaten in Sophos Central angelegt: Sophos Central > Globale Einstellungen > API-Zugangsdatenverwaltung > Zugangsdaten hinzufügen
- Rolle: Service Principal ReadOnly (ausreichend)
- Die Zugangsdaten (ClientID und Geheimer Clientschlüssel) sind in der KuDo des Kunden hinterlegt
- PowerShell 7 auf dem ausführenden Rechner
- Internetzugriff auf id.sophos.com und api.central.sophos.com (HTTPS)
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


# - KONFIGURATION
$Datum        = Get-Date -Format "yyyyMMdd"
$Datei        = Join-Path $Ausgabepfad "Wartung_${Datum}_SophosCentral.txt"
$MaxTageOffline = 7

if (Test-Path $Datei) { Remove-Item $Datei -Force }

# - ZUGANGSDATEN
$ZielName = if ([string]::IsNullOrWhiteSpace($Ziel)) { 'Sophos Central' } else { $Ziel.Trim() }
if ($Anmeldedaten) {
    $clientId     = $Anmeldedaten.UserName
    $clientSecret = $Anmeldedaten.GetNetworkCredential().Password
} elseif ($Automatik) {
    Write-Host "Abbruch: Im Automatikmodus fehlt das Konto (ClientID als Benutzername, Clientschlüssel als Kennwort)." -ForegroundColor Red
    Write-WtErgebnis -Skript '07.1-Firewall-Sophos_Central' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $ZielName; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Kein Konto (ClientID/Clientschlüssel) hinterlegt' })
    exit 1
} else {
    $clientId     = Read-Host "ClientID"
    $secureSecret = Read-Host "Geheimer Clientschlüssel" -AsSecureString
    $clientSecret = [System.Net.NetworkCredential]::new("", $secureSecret).Password
}
$tenantErgebnisse = [System.Collections.Generic.List[object]]::new()

Add-Content $Datei "===== Sophos Central Kurzcheck ====="
Add-Content $Datei "Ausgeführt von: $env:COMPUTERNAME"
Add-Content $Datei "Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"

# - API HELFER
function Get-SophosPaged {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    $items   = @()
    $nextKey = $null
    do {
        $sep = if ($Url -like "*?*") { "&" } else { "?" }
        $u   = if ($nextKey) { "$Url${sep}pageFromKey=$([uri]::EscapeDataString($nextKey))" } else { $Url }
        $r   = Invoke-RestMethod -Uri $u -Headers $Headers -Method Get
        if ($r.items) { $items += @($r.items) }
        $nextKey = $r.pages.nextKey
    } while ($nextKey)
    return $items
}

function Get-SophosTenantList {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    $items = @()
    $page  = 1
    do {
        $r = Invoke-RestMethod -Uri "${Url}?pageTotal=true&page=$page&pageSize=100" -Headers $Headers -Method Get
        if ($r.items) { $items += @($r.items) }
        $page++
    } while ($page -le [int]$r.pages.total)
    return $items
}

# - AUTHENTIFIZIERUNG
try {
    $token = Invoke-RestMethod -Uri "https://id.sophos.com/api/v2/oauth2/token" -Method Post -ContentType "application/x-www-form-urlencoded" -Body @{
        grant_type    = "client_credentials"
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = "token"
    }
    $authHeader = @{ Authorization = "Bearer $($token.access_token)" }
    $whoami     = Invoke-RestMethod -Uri "https://api.central.sophos.com/whoami/v1" -Headers $authHeader -Method Get
    Add-Content $Datei "Login erfolgreich. Zugangstyp: $($whoami.idType)"
    Write-Host "Login erfolgreich. Zugangstyp: $($whoami.idType)" -ForegroundColor Green
} catch {
    Add-Content $Datei "LOGIN FEHLGESCHLAGEN: ClientID/Geheimen Clientschlüssel prüfen. Details: $($_.Exception.Message)"
    Write-Host "Login fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    Add-Content $Datei "`n===== Ende Sophos Central Kurzcheck ====="
    if ($Automatik) {
        Write-WtErgebnis -Skript '07.1-Firewall-Sophos_Central' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $ZielName; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Login fehlgeschlagen (ClientID/Clientschlüssel prüfen)' })
        exit 1
    }
    Start-Process notepad.exe $Datei
    return
}

# - MANDANTENLISTE
$tenants = @()
try {
    switch ($whoami.idType) {
        "tenant" {
            $tenants += [PSCustomObject]@{ Id = $whoami.id; Name = "Mandant $($whoami.id)"; ApiHost = $whoami.apiHosts.dataRegion }
        }
        "partner" {
            $h = $authHeader + @{ "X-Partner-ID" = $whoami.id }
            foreach ($t in (Get-SophosTenantList -Url "https://api.central.sophos.com/partner/v1/tenants" -Headers $h)) {
                $tenants += [PSCustomObject]@{ Id = $t.id; Name = $t.name; ApiHost = $t.apiHost }
            }
        }
        "organization" {
            $h = $authHeader + @{ "X-Organization-ID" = $whoami.id }
            foreach ($t in (Get-SophosTenantList -Url "https://api.central.sophos.com/organization/v1/tenants" -Headers $h)) {
                $tenants += [PSCustomObject]@{ Id = $t.id; Name = $t.name; ApiHost = $t.apiHost }
            }
        }
    }
} catch {
    Add-Content $Datei "Fehler beim Abruf der Mandantenliste: $($_.Exception.Message)"
}

Add-Content $Datei "Mandanten gesamt: $($tenants.Count)"

foreach ($tenant in $tenants) {
    Write-Host "`n===== Mandant: $($tenant.Name) =====" -ForegroundColor Cyan
    Add-Content $Datei "`n===== Mandant: $($tenant.Name) ====="

    $tHeader = $authHeader + @{ "X-Tenant-ID" = $tenant.Id }
    $api     = $tenant.ApiHost
    $tn = [ordered]@{ Mandant = [string]$tenant.Name }

    # --- 1. Endpoints ---
    Add-Content $Datei "`n--- Endpoints ---"
    try {
        $endpoints = Get-SophosPaged -Url "$api/endpoint/v1/endpoints?pageSize=500" -Headers $tHeader
        Add-Content $Datei "Endpoints gesamt: $($endpoints.Count)"
        $tn['Endpoints'] = $endpoints.Count

        if ($endpoints.Count -eq 0) {
            Add-Content $Datei "Keine Endpoints in diesem Mandanten registriert."
        } else {
            $health = $endpoints | Where-Object { $_.health.overall -and $_.health.overall -ne "good" }
            $tn['EndpointsHealthNichtGood'] = $health.Count
            if ($health.Count -gt 0) {
                Add-Content $Datei "Endpoints mit Health-Status ungleich 'good': $($health.Count)"
                foreach ($e in $health) {
                    Add-Content $Datei ("  {0} | Health:{1} | Threats:{2} | Services:{3}" -f $e.hostname, $e.health.overall, $e.health.threats.status, $e.health.services.status)
                }
            } else {
                Add-Content $Datei "Alle Endpoints mit Health-Status 'good'."
            }

            $tamper = $endpoints | Where-Object { $_.tamperProtectionEnabled -eq $false }
            $tn['EndpointsOhneTamperProtection'] = $tamper.Count
            if ($tamper.Count -gt 0) {
                Add-Content $Datei "Endpoints ohne Tamper Protection: $($tamper.Count)"
                foreach ($e in $tamper) { Add-Content $Datei "  $($e.hostname)" }
            } else {
                Add-Content $Datei "Tamper Protection auf allen Endpoints aktiv."
            }

            $grenze  = (Get-Date).AddDays(-$MaxTageOffline)
            $offline = $endpoints | Where-Object { $_.lastSeenAt -and ([datetime]$_.lastSeenAt) -lt $grenze }
            $tn['EndpointsOffline'] = $offline.Count
            if ($offline.Count -gt 0) {
                Add-Content $Datei "Endpoints seit mehr als $MaxTageOffline Tagen nicht gesehen: $($offline.Count)"
                foreach ($e in $offline) {
                    Add-Content $Datei ("  {0} | Zuletzt gesehen: {1}" -f $e.hostname, ([datetime]$e.lastSeenAt).ToString('dd.MM.yyyy HH:mm'))
                }
            } else {
                Add-Content $Datei "Alle Endpoints innerhalb der letzten $MaxTageOffline Tage gesehen."
            }
        }
    } catch {
        Add-Content $Datei "Fehler beim Abruf der Endpoints: $($_.Exception.Message)"
    }

    # --- 2. Alerts ---
    Add-Content $Datei "`n--- Alerts ---"
    try {
        $alerts = Get-SophosPaged -Url "$api/common/v1/alerts?pageSize=100" -Headers $tHeader
        $tn['OffeneAlerts'] = $alerts.Count
        if ($alerts.Count -gt 0) {
            Add-Content $Datei "Offene Alerts: $($alerts.Count)"
            foreach ($a in ($alerts | Sort-Object raisedAt -Descending)) {
                Add-Content $Datei ("  {0} | Severity:{1} | Produkt:{2} | Gerät:{3} | {4}" -f ([datetime]$a.raisedAt).ToString('dd.MM.yyyy HH:mm'), $a.severity, $a.product, $a.managedAgent.name, $a.description)
            }
        } else {
            Add-Content $Datei "Keine offenen Alerts."
        }
    } catch {
        Add-Content $Datei "Fehler beim Abruf der Alerts: $($_.Exception.Message)"
    }

    # --- 3. Firewalls ---
    Add-Content $Datei "`n--- Firewalls ---"
    try {
        $fws = Get-SophosPaged -Url "$api/firewall/v1/firewalls?pageSize=100" -Headers $tHeader
        $tn['Firewalls'] = @($fws | ForEach-Object { [pscustomobject]@{ Name = $(if ($_.name) { [string]$_.name } else { [string]$_.hostname }); Modell = [string]$_.model; Firmware = [string]$_.firmwareVersion; Verbunden = $_.status.connected } })
        if ($fws.Count -gt 0) {
            Add-Content $Datei "Firewalls gesamt: $($fws.Count)"
            foreach ($f in $fws) {
                $name = if ($f.name) { $f.name } else { $f.hostname }
                Add-Content $Datei ("  {0} | Modell:{1} | Firmware:{2} | Verbunden:{3} | Seriennummer:{4}" -f $name, $f.model, $f.firmwareVersion, $f.status.connected, $f.serialNumber)
            }
        } else {
            Add-Content $Datei "Keine Firewalls in Sophos Central registriert."
        }
    } catch {
        Add-Content $Datei "Fehler beim Abruf der Firewalls: $($_.Exception.Message)"
    }

    # --- 4. Lizenzen ---
    Add-Content $Datei "`n--- Lizenzen ---"
    try {
        $lic = Invoke-RestMethod -Uri "https://api.central.sophos.com/licenses/v1/licenses" -Headers $tHeader -Method Get
        if ($lic.licenses.Count -gt 0) {
            foreach ($l in $lic.licenses) {
                $ende = if ($l.endDate) { ([datetime]$l.endDate).ToString('dd.MM.yyyy') } else { 'unbefristet' }
                Add-Content $Datei ("  {0} | Typ:{1} | Menge:{2} | Belegt:{3} | Ende:{4}" -f $l.product.name, $l.type, $l.quantity, $l.usage.current.count, $ende)
            }
        } else {
            Add-Content $Datei "Keine Lizenzen gefunden."
        }
    } catch {
        Add-Content $Datei "Fehler beim Abruf der Lizenzen: $($_.Exception.Message)"
    }
    $tenantErgebnisse.Add([pscustomobject]$tn)
}

# - ABSCHLUSS
Add-Content $Datei "`n===== Ende Sophos Central Kurzcheck ====="
Write-Host ("`nSophos Central Kurzcheck abgeschlossen. Datei gespeichert unter: {0}" -f $Datei) -ForegroundColor Yellow

if ($Automatik) {
    Get-Content -LiteralPath $Datei | Write-Host
    ## Haken nur für den erfolgreichen Abruf (Berichte aus Sophos Central); Firmware und Konfigurationssicherung der Firewall sind hier nicht belegt
    $pr = [ordered]@{}
    if ($tenants.Count -gt 0) { $pr['CentralBerichteGeprueft'] = $true }
    $notiz = "$($tenants.Count) Mandant(en) geprüft"
    $alertSumme = (@($tenantErgebnisse | Where-Object { $_.PSObject.Properties.Name -contains 'OffeneAlerts' }) | Measure-Object -Property OffeneAlerts -Sum).Sum
    if ($alertSumme -gt 0) { $notiz += "; $alertSumme offene Alerts" }
    Write-WtErgebnis -Skript '07.1-Firewall-Sophos_Central' -Ordner $Ausgabepfad -Ergebnisse @([pscustomobject]@{ Ziel = $ZielName; Erreicht = $true; Pruefungen = [pscustomobject]$pr; Werte = [pscustomobject]@{ Mandanten = $tenantErgebnisse.ToArray() }; Notiz = $notiz })
    exit 0
}

Start-Process notepad.exe $Datei