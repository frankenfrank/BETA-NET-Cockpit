# NET-COCKPIT-Modul-M365APP.ps1
<#
.SYNOPSIS
    Modul M365-Wartungs-App für das NET-COCKPIT (Menü Module > M365-Wartungs-App)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und legt im Kunden-Tenant die Wartungs-App "MAHR-EDV-Wartung" für das M365-Cockpit an oder aktualisiert sie.
    - Das Fenster zeigt den Ablauf, den Status der benötigten PowerShell-Module, die Berechtigungen der App (immer gesetzte und optional wählbare per Haken) und die Ablage der Dateien
    - Der Button startet das eingebaute Skript in einem eigenen PowerShell-7-Fenster ohne Administratorrechte (läuft das NET-COCKPIT als Administrator, startet es mit eingeschränktem Token über runas /trustlevel); das Skript prüft beim Start selbst, ob es erhöht läuft, und bricht dann ab
    - Das Skript wird als Temp-Datei abgelegt und löscht sich beim Start selbst; Anmeldung im Kunden-Tenant per Geräteanmeldung, Zertifikat und PFX unter C:\WorkDir\M365-Cockpit\M365-Tenantinfo, Tenantinfos in kunden-tenantinfos.json
    - Kein Gerätebezug: das Modul braucht keine markierten Geräte und legt keine Spalten an
    Das Modul speichert nichts im Datenordner des NET-COCKPIT.
#>

# Einstellungen
## Namen und Ablage (gleich wie im M365-Cockpit)
$script:MaAppName = 'MAHR-EDV-Wartung'
$script:MaBasisOrdner = 'C:\WorkDir\M365-Cockpit\M365-Tenantinfo'
$script:MaZertOrdner = Join-Path $script:MaBasisOrdner 'MAHR-EDV-Wartung-Cert'
$script:MaJsonPfad = Join-Path $script:MaBasisOrdner 'kunden-tenantinfos.json'
$script:MaPortalUrl = 'https://entra.microsoft.com/?l=de.de-de#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade/quickStartType~/null/sourceType/Microsoft_AAD_IAM'

## Benötigte PowerShell-Module
$script:MaModule = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications'
)

## Berechtigungen der App (Microsoft Graph, Anwendungsberechtigungen): immer gesetzte und optional wählbare
$script:MaAktiv = @(
    'Application.Read.All',
    'AuditLog.Read.All',
    'Device.Read.All',
    'DeviceManagementConfiguration.Read.All',
    'DeviceManagementManagedDevices.Read.All',
    'DeviceManagementApps.Read.All',
    'Directory.Read.All',
    'Group.Read.All',
    'Organization.Read.All',
    'Policy.Read.All',
    'Reports.Read.All',
    'SecurityAlert.Read.All',
    'SecurityEvents.Read.All',
    'SecurityIncident.Read.All',
    'Sites.Read.All',
    'Team.ReadBasic.All',
    'UserAuthenticationMethod.Read.All',
    'User.Read.All',
    'User.ReadWrite.All'
)
$script:MaSchreibrechte = @('User.ReadWrite.All')
$script:MaZusatz = @(
    'DeviceManagementScripts.Read.All',
    'GroupMember.Read.All',
    'LicenseAssignment.Read.All',
    'SharePointTenantSettings.Read.All',
    'TeamMember.Read.All',
    'UserAuthMethod-Email.Read.All',
    'UserAuthMethod-External.Read.All',
    'UserAuthMethod-HardwareOATH.Read.All',
    'UserAuthMethod-MicrosoftAuthApp.Read.All',
    'UserAuthMethod-Passkey.Read.All',
    'UserAuthMethod-Password.Read.All',
    'UserAuthMethod-Phone.Read.All',
    'UserAuthMethod-PlatformCred.Read.All',
    'UserAuthMethod-QR.Read.All',
    'UserAuthMethod-SoftwareOATH.Read.All'
)

## Zustand: Fenster, Steuerelemente, Haken der optionalen Berechtigungen und das zuletzt gestartete Skript
$script:MaFenster = $null
$script:MaC = @{}
$script:MaHaken = [System.Collections.Generic.List[object]]::new()
$script:MaProzess = $null

# Skript
## Das eingebaute Skript (läuft in einem eigenen PowerShell-7-Fenster ohne Administratorrechte); vor dem Start kommen die Werte aus den Einstellungen als Variablen davor
$script:MaSkript = @'
<#
BESCHREIBUNG
Legt im jeweiligen Kunden-Tenant die zentrale Wartungs-App "MAHR-EDV-Wartung" an (App-Registrierung + Service Principal), vergibt die im NET-COCKPIT gewählten Microsoft-Graph-Berechtigungen und verwaltet das Zertifikat für die zertifikatsbasierte Anmeldung. Bei Erstanlage wird ein neues Zertifikat erzeugt und lokal als PFX abgelegt; existiert am Tenant bereits ein gültiges Zertifikat, wird dieses übernommen, sodass das Skript auch zum nachträglichen Hinzufügen von Berechtigungen erneut ausgeführt werden kann. Tenant-/App-Infos werden in der Datei kunden-tenantinfos.json im Ordner M365-Tenantinfo gespeichert.

VORAUSSETZUNGEN
- läuft ohne Administratorrechte (alles unter dem aktuellen Benutzer)
- PowerShell-Module Microsoft.Graph.Authentication und Microsoft.Graph.Applications (werden bei Bedarf nach Rückfrage installiert)
- Global Administrator-Rechte im jeweiligen Kunden-Tenant (Anmeldung + Admin-Consent-Erteilung)
- Zugriff auf KuDo zum Ablegen bzw. Abrufen von Zertifikatspasswort und PFX-Datei
#>

# - TEMP-DATEI LÖSCHEN
## Das NET-COCKPIT legt dieses Skript als Temp-Datei ab; PowerShell hat es bereits vollständig gelesen
try { Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction Stop } catch { }

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " M365 Wartungs-App anlegen / aktualisieren" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# - ADMINRECHTE PRÜFEN
## Das Skript muss ohne Administratorrechte laufen, damit Module und Zertifikat beim aktuellen Benutzer landen
$IstAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IstAdmin) {
    Write-Host "Dieses Fenster laeuft mit Administratorrechten - das Skript wird nicht ausgefuehrt." -ForegroundColor Red
    Write-Host "Module und Zertifikat wuerden sonst beim falschen Benutzer landen." -ForegroundColor Red
    Write-Host "Bitte das Skript in einem normalen PowerShell-7-Fenster ohne Administratorrechte starten." -ForegroundColor Red
    exit
}

# - VORAUSSETZUNGEN
# -- MODULE
foreach ($m in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host ""
        Write-Host "Modul '$m' ist nicht installiert und wird benoetigt." -ForegroundColor Yellow
        $antwort = Read-Host "Soll das Modul '$m' jetzt fuer dein Benutzerkonto installiert werden? (J/N)"
        if ($antwort -eq "J" -or $antwort -eq "j") {
            Install-Module $m -Scope CurrentUser -Force
        } else {
            Write-Host "Abgebrochen - Modul '$m' wird benoetigt." -ForegroundColor Red
            exit
        }
    }
}

Write-Host "1. Es werden zuerst die Berechtigungen angefordert, um ueberhaupt eine App registrieren zu duerfen."
Write-Host "2. Dann kommt die Liste der Berechtigungen, die der App gewaehrt werden (im NET-COCKPIT gewaehlt)."
Write-Host "3. Die Berechtigungen muessen spaeter noch als Admin bestaetigt werden."
Write-Host ""

# - GRAPH VERBINDUNG
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Connect-MgGraph -Scopes "Application.ReadWrite.All" -NoWelcome -UseDeviceCode

if (-not (Get-MgContext)) {
    Write-Host ""
    Write-Host "ANMELDUNG FEHLGESCHLAGEN - Skript wird abgebrochen." -ForegroundColor Red
    exit
}

# - JSON REGISTRY
# -- TENANT DOMAIN ERMITTELN
$Org = Get-MgOrganization
$TenantDomain = ($Org.VerifiedDomains | Where-Object { $_.IsInitial -eq $true }).Name

# - KONFIG
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$CertYearsValid = 2

# - TENANT ERMITTELN
$Tenant = Get-MgOrganization
$TenantName = $Tenant.DisplayName
$TenantId = $Tenant.Id
$CustomerNameClean = $TenantName -replace '[\\\/:\*\?"<>\|]', '' -replace '\s+', '_'

# - TENANTINFOS (ORDNER + JSON)
if (-not (Test-Path $BaseInfoDir)) {
    New-Item -ItemType Directory -Path $BaseInfoDir -Force | Out-Null
}

if (-not (Test-Path $AppInfoDir)) {
    New-Item -ItemType Directory -Path $AppInfoDir -Force | Out-Null
}

if (-not (Test-Path $JsonPath)) {
    "{}" | Out-File -FilePath $JsonPath -Encoding UTF8
}

# - JSON EINLESEN
# -- LADEN
$jsonText = Get-Content $JsonPath -Raw
if ([string]::IsNullOrWhiteSpace($jsonText)) {
    $JsonRegistry = @{}
} else {
    $JsonRegistry = $jsonText | ConvertFrom-Json -AsHashtable
}

# - ZERTIFIKATSABLAGE
$DefaultPfxPath = Join-Path $AppInfoDir "$AppName-$CustomerNameClean.pfx"
$PfxPath = $DefaultPfxPath
$CertSubject = "CN=$AppName-$CustomerNameClean"

if ($JsonRegistry.ContainsKey($CustomerNameClean)) {
    if ($JsonRegistry[$CustomerNameClean].ContainsKey("PfxPath")) {
        if (-not [string]::IsNullOrWhiteSpace($JsonRegistry[$CustomerNameClean]["PfxPath"])) {
            $PfxPath = [string]$JsonRegistry[$CustomerNameClean]["PfxPath"]
        }
    }
}

# - HILFSFUNKTIONEN
function Get-GraphServicePrincipal {
    param([string]$AppId)
    $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -All | Select-Object -First 1
    if (-not $sp) { throw "ServicePrincipal nicht gefunden (appId=$AppId)." }
    $sp
}

function Ensure-Application {
    param([string]$DisplayName)
    $app = Get-MgApplication -Filter "displayName eq '$DisplayName'" -All | Select-Object -First 1
    if ($app) { return $app }
    New-MgApplication -DisplayName $DisplayName -SignInAudience "AzureADMultipleOrgs"
}

function Ensure-ServicePrincipal {
    param([string]$AppId)
    $sp = Get-MgServicePrincipal -Filter "appId eq '$AppId'" -All | Select-Object -First 1
    if ($sp) { return $sp }
    New-MgServicePrincipal -AppId $AppId
}

function New-LocalSelfSignedCertAndExportPfx {
    param($Subject,$YearsValid,$PfxPath,$PfxPassword)

    $cert = New-SelfSignedCertificate `
        -Subject $Subject `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -KeyExportPolicy Exportable `
        -NotAfter (Get-Date).AddYears($YearsValid) `
        -HashAlgorithm SHA256 `
        -KeySpec Signature

    Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" -FilePath $PfxPath -Password $PfxPassword | Out-Null
    $cert
}

function Convert-CertToKeyCredential {
    param($Cert)
    @{
        type="AsymmetricX509Cert"
        usage="Verify"
        key=$Cert.GetRawCertData()
        displayName=$Cert.Subject
        keyId=[guid]::NewGuid()
        startDateTime=$Cert.NotBefore.ToUniversalTime().ToString("o")
        endDateTime=$Cert.NotAfter.ToUniversalTime().ToString("o")
    }
}
# - FUNKTION GRAPHAPPPERMISSION
function Ensure-GraphAppPermissions {
    param(
        [Parameter(Mandatory=$true)][string]$ApplicationObjectId,
        [Parameter(Mandatory=$true)][string[]]$PermissionValues
    )

    $graphSp = Get-GraphServicePrincipal -AppId $GraphAppId
    $app = Get-MgApplication -ApplicationId $ApplicationObjectId

    $desiredIds = @()
    foreach ($p in $PermissionValues) {
        $role = $graphSp.AppRoles | Where-Object {
            $_.Value -eq $p -and $_.AllowedMemberTypes -contains "Application"
        } | Select-Object -First 1
        if (-not $role) { throw "Graph App Permission nicht gefunden oder nicht Application-Permission: $p" }
        $desiredIds += [Guid]$role.Id
    }

    $existingIds = @()
    foreach ($rra in @($app.RequiredResourceAccess)) {
        if ($rra.ResourceAppId -eq $GraphAppId) {
            foreach ($ra in @($rra.ResourceAccess)) {
                if ($ra.Type -eq "Role") { $existingIds += [Guid]$ra.Id }
            }
        }
    }

    $allIds = @($existingIds + $desiredIds | Select-Object -Unique)

    $newResourceAccess = @()
    foreach ($id in $allIds) {
        $newResourceAccess += @{
            Id   = [string]$id
            Type = "Role"
        }
    }

    $newRequiredResourceAccess = @()
    foreach ($rra in @($app.RequiredResourceAccess)) {
        if ($rra.ResourceAppId -ne $GraphAppId) {
            $newRequiredResourceAccess += @{
                ResourceAppId  = $rra.ResourceAppId
                ResourceAccess = @($rra.ResourceAccess | ForEach-Object {
                    @{
                        Id   = [string]$_.Id
                        Type = [string]$_.Type
                    }
                })
            }
        }
    }

    $newRequiredResourceAccess += @{
        ResourceAppId  = $GraphAppId
        ResourceAccess = $newResourceAccess
    }

    try {
        Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $newRequiredResourceAccess -ErrorAction Stop | Out-Null
    } catch {
        throw "Update-MgApplication (RequiredResourceAccess) fehlgeschlagen: $($_.Exception.Message)"
    }

    $verify = Get-MgApplication -ApplicationId $app.Id
    $verifyIds = @()
    foreach ($rra in @($verify.RequiredResourceAccess)) {
        if ($rra.ResourceAppId -eq $GraphAppId) {
            foreach ($ra in @($rra.ResourceAccess)) {
                if ($ra.Type -eq "Role") { $verifyIds += [Guid]$ra.Id }
            }
        }
    }

    $missing = @($desiredIds | Where-Object { $verifyIds -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw "GraphAppPermissions wurden nicht übernommen. Fehlende AppRole-Ids: $($missing -join ', ')"
    }
}

# - FUNKTION KEYCREDENTIAL
function Ensure-KeyCredentialOnApp {
    param($ApplicationObjectId,$KeyCredential)

    $app = Get-MgApplication -ApplicationId $ApplicationObjectId

    $exists = $false
    foreach ($kc in @($app.KeyCredentials)) {
        if ($kc.DisplayName -eq $KeyCredential.displayName -and $kc.EndDateTime -eq $KeyCredential.endDateTime) {
            $exists = $true
        }
    }
    if ($exists) { return }

    $all = @()
    foreach ($kc in @($app.KeyCredentials)) {
        $all += @{
            type  = $kc.Type
            usage = $kc.Usage
            key   = $kc.Key
            displayName = $kc.DisplayName
            keyId = $kc.KeyId
            startDateTime = $kc.StartDateTime
            endDateTime   = $kc.EndDateTime
        }
    }
    $all += $KeyCredential

    Update-MgApplication -ApplicationId $app.Id -KeyCredentials $all
}

# - APP / SP
$app = Ensure-Application -DisplayName $AppName
$sp  = Ensure-ServicePrincipal -AppId $app.AppId

# - ZERTIFIKAT
# -- PRÜFEN (APP)
$appReload = Get-MgApplication -ApplicationId $app.Id
$Now = Get-Date

$ValidKeyCredential = $appReload.KeyCredentials |
    Where-Object {
        $_.DisplayName -eq $CertSubject -and
        [datetime]$_.EndDateTime -gt $Now
    } |
    Sort-Object EndDateTime -Descending |
    Select-Object -First 1

$KuDoEintrag = "M365 Mahr-EDV-Wartung Zertifikatspasswort"

if ($ValidKeyCredential) {
    $cert = $null
    $Thumbprint = $ValidKeyCredential.KeyId

    if (-not (Test-Path $PfxPath)) {
        Write-Host ""
        Write-Host "ZERTIFIKAT BEREITS VORHANDEN - ABER NICHT AUF DIESEM RECHNER" -ForegroundColor Yellow
        Write-Host "Passwort und Zertifikat liegen im KuDo-Eintrag '$KuDoEintrag' beim Kunden $TenantName." -ForegroundColor Yellow
        Write-Host "Bitte PFX-Datei aus KuDo laden und hier speichern: $PfxPath" -ForegroundColor Yellow
        Write-Host "Weiter mit [Enter], sobald die Datei dort liegt." -ForegroundColor Yellow
        Read-Host | Out-Null
    }
}
else {
    # -- ERZEUGEN (LOKAL)
    Write-Host ""
    Write-Host "NEUES ZERTIFIKAT WIRD ERSTELLT" -ForegroundColor Yellow
    Write-Host "Bitte jetzt KuDo oeffnen und Eintrag '$KuDoEintrag' beim Kunden $TenantName anlegen, Kennwort erzeugen und dort eintragen." -ForegroundColor Yellow
    $PfxPassword = Read-Host "Welches Passwort soll die PFX-Datei fuer $CustomerNameClean bekommen?" -AsSecureString

    $cert = New-LocalSelfSignedCertAndExportPfx `
        -Subject $CertSubject `
        -YearsValid $CertYearsValid `
        -PfxPath $PfxPath `
        -PfxPassword $PfxPassword

    $Thumbprint = $cert.Thumbprint

    $keyCred = Convert-CertToKeyCredential -Cert $cert
    Ensure-KeyCredentialOnApp -ApplicationObjectId $app.Id -KeyCredential $keyCred

    Write-Host ""
    Write-Host "ZERTIFIKAT ERSTELLT" -ForegroundColor Green
    Write-Host "Bitte die PFX-Datei jetzt in den KuDo-Eintrag '$KuDoEintrag' hochladen." -ForegroundColor Yellow
    Write-Host "Datei: $PfxPath" -ForegroundColor Yellow
    Write-Host "Weiter mit [Enter], sobald hochgeladen." -ForegroundColor Yellow
    Read-Host | Out-Null
}

# - RECHTE
## Aktive Berechtigungen und die im NET-COCKPIT zusätzlich gewählten
Write-Host ""
Write-Host "AKTIVE BERECHTIGUNGEN (werden immer gesetzt)" -ForegroundColor Green
$GraphAppPermissions | ForEach-Object { Write-Host " - $_" }

if (@($ZusatzBerechtigungen).Count -gt 0) {
    Write-Host ""
    Write-Host "ZUSAETZLICH IM NET-COCKPIT GEWAEHLT" -ForegroundColor Green
    $ZusatzBerechtigungen | ForEach-Object { Write-Host " - $_" }
    $GraphAppPermissions = @($GraphAppPermissions) + @($ZusatzBerechtigungen)
}

$appReload = Get-MgApplication -ApplicationId $app.Id

Ensure-GraphAppPermissions `
    -ApplicationObjectId $appReload.Id `
    -PermissionValues $GraphAppPermissions

# - JSON REGISTRY
# -- KUNDEN ERGÄNZEN / AKTUALISIEREN
if (-not $JsonRegistry.ContainsKey($CustomerNameClean)) {
    $JsonRegistry[$CustomerNameClean] = @{
        TenantId     = $TenantId
        ClientId     = $app.AppId
        TenantDomain = $TenantDomain
        PfxPath      = $PfxPath
        Thumbprint   = $Thumbprint
    }
}
else {
    $JsonRegistry[$CustomerNameClean]["TenantId"]     = $TenantId
    $JsonRegistry[$CustomerNameClean]["ClientId"]     = $app.AppId
    $JsonRegistry[$CustomerNameClean]["TenantDomain"] = $TenantDomain
    $JsonRegistry[$CustomerNameClean]["PfxPath"]      = $PfxPath
    $JsonRegistry[$CustomerNameClean]["Thumbprint"]   = $Thumbprint
}

$JsonRegistry | ConvertTo-Json -Depth 5 | Out-File -FilePath $JsonPath -Encoding UTF8

# - ZUSAMMENFASSUNG
Clear-Host
Write-Host "- - - ZUSAMMENFASSUNG - - -`n"
# - Zertifikatinformationen
if ($cert) {
    Write-Host "AKTIVES LOKALES ZERTIFIKAT" -ForegroundColor Green
    Write-Host "Gueltig von  : $($cert.NotBefore)"
    Write-Host "Gueltig bis  : $($cert.NotAfter)"
} else {
    Write-Host "AKTIVES ONLINE APP ZERTIFIKAT" -ForegroundColor Green
    Write-Host "Gueltig von  : $([datetime]$ValidKeyCredential.StartDateTime)"
    Write-Host "Gueltig bis  : $([datetime]$ValidKeyCredential.EndDateTime)"
}
# -- ZERTIFIKATE IN DER APP
Write-Host "`nZERTIFIKATE IN DER APP" -ForegroundColor Green
$appReload = Get-MgApplication -ApplicationId $app.Id

foreach ($kc in @($appReload.KeyCredentials)) {
    Write-Host "DisplayName : $($kc.DisplayName)"
    Write-Host "KeyId       : $($kc.KeyId)"
    Write-Host "Gueltig von : $([datetime]$kc.StartDateTime)"
    Write-Host "Gueltig bis : $([datetime]$kc.EndDateTime)"
}

# - JSON REGISTRY
# -- AKTUELLER TENANT
Write-Host ""
Write-Host "JSON-EINTRAG FÜR AKTUELLEN TENANT" -ForegroundColor Green
if ($JsonRegistry.ContainsKey($CustomerNameClean)) {
    $JsonRegistry[$CustomerNameClean] | ConvertTo-Json -Depth 5 | Write-Host
} else {
    Write-Host "Kein Eintrag für diesen Tenant vorhanden." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "ZUSAMMENFASSUNG" -ForegroundColor Green
Write-Host "AppName      : $AppName"
Write-Host "TenantName   : $TenantName"
Write-Host "TenantId     : $TenantId"
Write-Host "ClientId     : $($app.AppId)"
Write-Host "PFX-Pfad     : $PfxPath"
Write-Host "JSON-Datei   : $JsonPath"
Write-Host "Thumbprint   : $Thumbprint"

Write-Host ""

# - TRENNEN
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

Write-Host ""
Write-Host "PRUEFEN, OB ADMIN CONSENT NOCH ERFORDERLICH IST!!!" -ForegroundColor Yellow
Write-Host "https://entra.microsoft.com -> App-Registrierungen -> $AppName -> API-Berechtigungen" -ForegroundColor Yellow
Write-Host "Evtl. APP-Seite im Browser mit [F5] aktualisieren!!!" -ForegroundColor Yellow
Write-Host ""
'@

# Hilfsfunktionen
## Text für die Einbettung in einfache Anführungszeichen
function script:ConvertTo-WolMaText {
    param([string]$Text)
    return $Text.Replace("'", "''")
}

## Liste als PowerShell-Array-Text (für die Variablen vor dem Skript)
function script:ConvertTo-WolMaListe {
    param([string[]]$Werte)
    return '@(' + ((@($Werte) | ForEach-Object { "'" + (ConvertTo-WolMaText $_) + "'" }) -join ', ') + ')'
}

## Läuft das NET-COCKPIT mit Administratorrechten?
function script:Test-WolMaAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

## Status der benötigten PowerShell-Module (Name, installierte Version oder leer)
function script:Get-WolMaModulStatus {
    foreach ($name in $script:MaModule) {
        $m = Get-Module -ListAvailable -Name $name -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
        [pscustomobject]@{ Name = $name; Version = $(if ($m) { [string]$m.Version } else { '' }) }
    }
}

# Anzeige
## Modulstatus im Fenster neu aufbauen
function script:Update-WolMaModule {
    $c = $script:MaC
    if (-not $c.PnlModule) { return }
    $c.PnlModule.Children.Clear()
    foreach ($s in @(Get-WolMaModulStatus)) {
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Margin = [System.Windows.Thickness]::new(12, 1, 0, 1)
        if ($s.Version) {
            $t.Text = "$($s.Name): installiert (Version $($s.Version))"
            $t.Foreground = [System.Windows.Media.Brushes]::DarkGreen
        }
        else {
            $t.Text = "$($s.Name): fehlt, das Skript fragt beim Start, ob es installiert werden soll"
            $t.Foreground = [System.Windows.Media.Brushes]::DarkOrange
        }
        [void]$c.PnlModule.Children.Add($t)
    }
}

## Status unter der Liste setzen
function script:Set-WolMaStatus {
    param([string]$Text)
    if ($script:MaC.TxtStatus) { $script:MaC.TxtStatus.Text = $Text }
}

# Start
## Skript in einem eigenen PowerShell-7-Fenster ohne Administratorrechte starten
function script:Start-WolMaSkript {
    ### Zusätzlich gewählte Berechtigungen
    $zusatz = @($script:MaHaken | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })

    ### Skriptdatei: Variablen aus den Einstellungen, danach das eingebaute Skript
    $kopf = "Clear-Host`r`n" +
        "`$AppName = '" + (ConvertTo-WolMaText $script:MaAppName) + "'`r`n" +
        "`$BaseInfoDir = '" + (ConvertTo-WolMaText $script:MaBasisOrdner) + "'`r`n" +
        "`$AppInfoDir = '" + (ConvertTo-WolMaText $script:MaZertOrdner) + "'`r`n" +
        "`$JsonPath = '" + (ConvertTo-WolMaText $script:MaJsonPfad) + "'`r`n" +
        "`$RequiredModules = " + (ConvertTo-WolMaListe $script:MaModule) + "`r`n" +
        "`$GraphAppPermissions = " + (ConvertTo-WolMaListe $script:MaAktiv) + "`r`n" +
        "`$ZusatzBerechtigungen = " + (ConvertTo-WolMaListe $zusatz) + "`r`n"
    $datei = Join-Path ([System.IO.Path]::GetTempPath()) ('NET-COCKPIT_M365App_' + [guid]::NewGuid().ToString('N') + '.ps1')
    try {
        $text = ($kopf + $script:MaSkript) -replace "(?<!`r)`n", "`r`n"
        [System.IO.File]::WriteAllText($datei, $text, [System.Text.UTF8Encoding]::new($true))
    }
    catch {
        Set-WolMaStatus "Das Skript konnte nicht abgelegt werden: $($_.Exception.Message)"
        Write-WolLog "M365-Wartungs-App: Skript konnte nicht abgelegt werden: $($_.Exception.Message)"
        return
    }

    ### Befehl: Fenster bleibt am Ende offen, auch bei Fehlern
    $gesamt = "try { & '" + (ConvertTo-WolMaText $datei) + "'; Write-Host ''; [void](Read-Host 'Skript beendet. Zum Schließen Enter drücken') } catch { Write-Host (`$_ | Out-String) -ForegroundColor Red; [void](Read-Host 'Fehler im Skript. Zum Schließen Enter drücken') }"
    $kodiert = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($gesamt))
    $pwsh = (Get-Process -Id $PID).Path
    $erhoeht = Test-WolMaAdmin

    try {
        if ($erhoeht) {
            ### Eingeschränktes Token (normaler Benutzer) über runas
            $befehl = '"' + $pwsh + '" -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $kodiert
            $argumente = '/trustlevel:0x20000 "' + $befehl.Replace('"', '\"') + '"'
            [void](Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\runas.exe') -ArgumentList $argumente -ErrorAction Stop)
            $script:MaProzess = $null
        }
        else {
            $script:MaProzess = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $kodiert -WindowStyle Normal -PassThru -ErrorAction Stop
        }
    }
    catch {
        try { Remove-Item -LiteralPath $datei -Force -ErrorAction SilentlyContinue } catch { }
        Set-WolMaStatus "Das Skript konnte nicht gestartet werden: $($_.Exception.Message)"
        Write-WolLog "M365-Wartungs-App: Start fehlgeschlagen: $($_.Exception.Message)"
        return
    }
    $wie = $(if ($erhoeht) { 'ohne Administratorrechte (das NET-COCKPIT läuft als Administrator)' } else { 'ohne Administratorrechte' })
    Set-WolMaStatus ("Das Skript läuft seit {0} Uhr in einem eigenen PowerShell-Fenster, {1}. Zusätzliche Berechtigungen: {2}." -f (Get-Date).ToString('HH:mm'), $wie, $(if ($zusatz.Count -gt 0) { $zusatz.Count } else { 'keine' }))
    Write-WolLog "M365-Wartungs-App: Skript gestartet ($wie), zusätzliche Berechtigungen: $($zusatz.Count)"
}

## Ordner mit den Tenantinfos im Explorer öffnen
function script:Open-WolMaOrdner {
    if (-not (Test-Path -LiteralPath $script:MaBasisOrdner)) {
        Set-WolMaStatus "Der Ordner $($script:MaBasisOrdner) existiert noch nicht. Er wird beim ersten Lauf des Skripts angelegt."
        return
    }
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($script:MaBasisOrdner)`"" -ErrorAction Stop }
    catch { Set-WolMaStatus "Der Ordner konnte nicht geöffnet werden: $($_.Exception.Message)" }
}

## Entra-Portal (App-Registrierungen) im Standardbrowser öffnen
function script:Open-WolMaPortal {
    try { Start-Process -FilePath $script:MaPortalUrl -ErrorAction Stop }
    catch { Set-WolMaStatus "Das Entra-Portal konnte nicht geöffnet werden: $($_.Exception.Message)" }
}

# Fenster
## Wird vom Menü Module > M365-Wartungs-App aufgerufen: Fenster neben der Tabelle (bleibt offen, die Tabelle bleibt bedienbar)
function script:Show-WolModulM365APP {
    if ($script:MaFenster) { [void]$script:MaFenster.Activate(); return }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="M365-Wartungs-App" Width="820" Height="700" MinWidth="640" MinHeight="480" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,8">
      <TextBlock Text="Wartungs-App MAHR-EDV-Wartung im Kunden-Tenant anlegen oder aktualisieren" FontSize="16" FontWeight="Bold" TextWrapping="Wrap"/>
      <TextBlock x:Name="TxtAdmin" Margin="0,4,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel Margin="0,0,8,0">
        <TextBlock Text="Ablauf" FontWeight="Bold" Margin="0,4,0,2"/>
        <TextBlock x:Name="TxtAblauf" TextWrapping="Wrap" Margin="12,0,0,0"/>
        <TextBlock Text="PowerShell-Module (für dein Benutzerkonto)" FontWeight="Bold" Margin="0,12,0,2"/>
        <StackPanel x:Name="PnlModule"/>
        <TextBlock Text="Berechtigungen der App (Microsoft Graph, Anwendungsberechtigungen)" FontWeight="Bold" Margin="0,12,0,2"/>
        <TextBlock Text="Werden immer gesetzt (Schreibrecht rot markiert):" Margin="12,0,0,2" Foreground="DimGray"/>
        <WrapPanel x:Name="PnlAktiv" Margin="12,0,0,0"/>
        <TextBlock Text="Zusätzlich (Haken setzen, was dazukommen soll):" Margin="12,8,0,2" Foreground="DimGray"/>
        <WrapPanel x:Name="PnlZusatz" Margin="12,0,0,0"/>
        <TextBlock Text="Ablage" FontWeight="Bold" Margin="0,12,0,2"/>
        <TextBlock x:Name="TxtAblage" TextWrapping="Wrap" Margin="12,0,0,0"/>
      </StackPanel>
    </ScrollViewer>
    <TextBlock x:Name="TxtStatus" Grid.Row="2" Margin="0,8,0,8" TextWrapping="Wrap" Foreground="#FF0B5CAD"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnStart" Content="Wartungs-App anlegen / aktualisieren..." Padding="10,6" Margin="0,0,8,0" FontWeight="Bold"/>
      <Button x:Name="BtnPruefen" Content="Module prüfen" Padding="10,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnOrdner" Content="Ordner Tenantinfo öffnen" Padding="10,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnPortal" Content="Entra-Portal öffnen" Padding="10,6" Margin="0,0,8,0"/>
      <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,6"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $script:MaC = @{}
    foreach ($name in 'TxtAdmin', 'TxtAblauf', 'PnlModule', 'PnlAktiv', 'PnlZusatz', 'TxtAblage', 'TxtStatus', 'BtnStart', 'BtnPruefen', 'BtnOrdner', 'BtnPortal', 'BtnSchliessen') {
        $script:MaC[$name] = $f.FindName($name)
    }
    $c = $script:MaC
    if ($script:Fenster -and $script:Fenster.IsVisible) { $f.Owner = $script:Fenster }

    ### Hinweis zu den Adminrechten
    if (Test-WolMaAdmin) {
        $c.TxtAdmin.Text = 'Das NET-COCKPIT läuft als Administrator. Das Skript startet trotzdem in einem eigenen Fenster ohne Administratorrechte, damit Module und Zertifikat bei deinem Benutzer landen.'
    }
    else {
        $c.TxtAdmin.Text = 'Das NET-COCKPIT läuft ohne Administratorrechte. Das Skript startet in einem eigenen PowerShell-Fenster ebenfalls ohne Administratorrechte.'
    }

    ### Ablauf
    $c.TxtAblauf.Text = (
        '1. Anmeldung im Kunden-Tenant per Geräteanmeldung (Global Administrator), nur mit Application.ReadWrite.All, um die App anlegen zu dürfen.',
        '2. App-Registrierung und Service Principal MAHR-EDV-Wartung anlegen oder die vorhandene verwenden.',
        '3. Zertifikat: neu erstellen (selbstsigniert, 2 Jahre, PFX mit Kennwort aus dem KuDo-Eintrag) oder das vorhandene aus KuDo verwenden.',
        '4. Berechtigungen der App setzen (siehe unten).',
        '5. Tenantinfos in kunden-tenantinfos.json speichern.',
        '6. Admin-Consent im Entra-Portal bestätigen (API-Berechtigungen der App).'
    ) -join "`r`n"

    ### Berechtigungen
    foreach ($p in $script:MaAktiv) {
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Text = $p
        $t.Margin = [System.Windows.Thickness]::new(0, 1, 14, 1)
        if ($script:MaSchreibrechte -contains $p) {
            $t.Text = "$p (Schreibrecht)"
            $t.Foreground = [System.Windows.Media.Brushes]::Firebrick
            $t.FontWeight = [System.Windows.FontWeights]::Bold
        }
        [void]$c.PnlAktiv.Children.Add($t)
    }
    $script:MaHaken.Clear()
    foreach ($p in $script:MaZusatz) {
        $h = [System.Windows.Controls.CheckBox]::new()
        $h.Content = $p
        $h.Tag = $p
        $h.IsChecked = $false
        $h.Margin = [System.Windows.Thickness]::new(0, 1, 14, 1)
        [void]$c.PnlZusatz.Children.Add($h)
        $script:MaHaken.Add($h)
    }

    ### Ablage
    $c.TxtAblage.Text = "Tenantinfos: $($script:MaJsonPfad)`r`nZertifikat (PFX): $($script:MaZertOrdner)`r`nDas Zertifikat liegt zusätzlich im Zertifikatspeicher des aktuellen Benutzers; Kennwort und PFX-Datei gehören in den KuDo-Eintrag M365 Mahr-EDV-Wartung Zertifikatspasswort des Kunden."

    Update-WolMaModule

    $c.BtnStart.Add_Click({ Start-WolMaSkript })
    $c.BtnPruefen.Add_Click({ Update-WolMaModule; Set-WolMaStatus 'Module neu geprüft.' })
    $c.BtnOrdner.Add_Click({ Open-WolMaOrdner })
    $c.BtnPortal.Add_Click({ Open-WolMaPortal })
    $c.BtnSchliessen.Add_Click({ $script:MaFenster.Close() })
    $f.Add_Closed({ $script:MaFenster = $null; $script:MaC = @{}; $script:MaHaken.Clear() })
    ### Beendet sich das NET-COCKPIT, schließt sich das Fenster mit
    $script:Fenster.Add_Closed({ if ($script:MaFenster) { $script:MaFenster.Close() } })

    $script:MaFenster = $f
    $f.Show()
}

# Info
## Reiter für die Info des NET-COCKPIT (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['M365APP'] = {
    @{ Titel = 'M365-Wartungs-App'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Legt im **Kunden-Tenant** die Wartungs-App **MAHR-EDV-Wartung** für das M365-Cockpit an oder aktualisiert sie: App-Registrierung, Service Principal, Zertifikat und Berechtigungen. Das Fenster öffnet sich über **Module > M365-Wartungs-App**, zeigt vorher, was installiert und angelegt wird, und bleibt neben der Tabelle offen. Das Modul braucht **keine markierten Geräte**.' }
        @{ T = 'h'; X = 'Bedienung' }
        @{ T = 'i'; X = '**Ablauf** (steht im Fenster): Anmeldung im Tenant, App und Service Principal, Zertifikat, Berechtigungen, Tenantinfos speichern, Admin-Consent im Entra-Portal.' }
        @{ T = 'i'; X = '**PowerShell-Module:** Microsoft.Graph.Authentication und Microsoft.Graph.Applications. Das Fenster zeigt, ob sie installiert sind (**Module prüfen** liest neu). Fehlt eins, fragt das Skript beim Start, ob es für dein Benutzerkonto installiert werden soll (Install-Module -Scope CurrentUser).' }
        @{ T = 'i'; X = '**Berechtigungen:** die oberen werden immer gesetzt (Microsoft Graph, Anwendungsberechtigungen, nur lesend, außer **User.ReadWrite.All** als Schreibrecht, rot markiert). Darunter lassen sich per **Haken** weitere wählen (beim Öffnen immer aus). Die Haken gelten für den nächsten Start.' }
        @{ T = 'i'; X = '**Wartungs-App anlegen / aktualisieren...:** startet das Skript in einem eigenen PowerShell-7-Fenster **ohne Administratorrechte**. Dort läuft die Anmeldung per Geräteanmeldung (Global Administrator des Kunden); die Abfragen (PFX-Kennwort, KuDo-Hinweise) stehen im Skriptfenster.' }
        @{ T = 'i'; X = '**Ordner Tenantinfo öffnen** zeigt C:\WorkDir\M365-Cockpit\M365-Tenantinfo im Explorer, **Entra-Portal öffnen** die App-Registrierungen im Standardbrowser.' }
        @{ T = 'h'; X = 'Zertifikat und Ablage' }
        @{ T = 'i'; X = '**Neues Zertifikat** (wenn die App noch keins hat): selbstsigniert, 2 Jahre, im Zertifikatspeicher des Benutzers und als PFX in C:\WorkDir\M365-Cockpit\M365-Tenantinfo\MAHR-EDV-Wartung-Cert. Kennwort und PFX-Datei gehören in den KuDo-Eintrag **M365 Mahr-EDV-Wartung Zertifikatspasswort** des Kunden.' }
        @{ T = 'i'; X = '**Vorhandenes Zertifikat:** Hat die App schon eins, das auf diesem Rechner fehlt, fordert das Skript auf, die PFX-Datei aus KuDo in den Ordner zu legen. So lässt sich das Skript auch später erneut ausführen, um Berechtigungen nachzuziehen.' }
        @{ T = 'i'; X = '**Tenantinfos:** C:\WorkDir\M365-Cockpit\M365-Tenantinfo\kunden-tenantinfos.json (Tenant-ID, Client-ID, Domain, PFX-Pfad, Thumbprint je Kunde).' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Ohne Administratorrechte:** Läuft das NET-COCKPIT als Administrator, startet das Modul das Skript mit eingeschränktem Token (runas /trustlevel). Das Skript prüft beim Start selbst und bricht mit einem Hinweis ab, wenn es doch erhöht läuft.' }
        @{ T = 'i'; X = '**Admin-Consent:** Nach dem Lauf müssen die Berechtigungen im Entra-Portal unter App-Registrierungen > MAHR-EDV-Wartung > API-Berechtigungen bestätigt werden (Seite mit F5 aktualisieren).' }
        @{ T = 'i'; X = '**Skript:** Das Modul legt es als Temp-Datei ab, es löscht sich beim Start selbst. Das Modul speichert nichts im Datenordner des NET-COCKPIT.' }
        @{ T = 'w'; X = 'Noch nicht getestet: Fenster, Start ohne Administratorrechte (runas /trustlevel), Lauf des Skripts gegen einen Tenant.' }
    ) }
}
