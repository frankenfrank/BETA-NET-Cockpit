#Requires -Version 7.0
<#
BESCHREIBUNG
Legt im jeweiligen Kunden-Tenant die zentrale Wartungs-App "MAHR-EDV-Wartung" an (App-Registrierung + Service Principal), vergibt die benötigten Microsoft-Graph-Berechtigungen und verwaltet das Zertifikat für die zertifikatsbasierte Anmeldung. Bei Erstanlage wird ein neues Zertifikat erzeugt und lokal als PFX abgelegt; existiert am Tenant bereits ein gültiges Zertifikat, wird dieses übernommen, sodass das Skript auch zum nachträglichen Hinzufügen von Berechtigungen erneut ausgeführt werden kann. Tenant-/App-Infos werden in C:\Kundeninfos\kunden-tenantinfos.json gespeichert.

VORAUSSETZUNGEN
- PowerShell-Module Microsoft.Graph.Authentication und Microsoft.Graph.Applications (werden bei Bedarf nach Rückfrage installiert)
- Global Administrator-Rechte im jeweiligen Kunden-Tenant (Anmeldung + Admin-Consent-Erteilung)
- Zugriff auf KuDo zum Ablegen bzw. Abrufen von Zertifikatspasswort und PFX-Datei
#>

Clear-Host

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " M365 Wartungs-App anlegen / aktualisieren" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN
# -- MODULE
$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Applications",
    "Microsoft.PowerShell.ConsoleGuiTools"
)

foreach ($m in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host ""
        Write-Host "Modul '$m' ist nicht installiert und wird benoetigt." -ForegroundColor Yellow
        $antwort = Read-Host "Jetzt installieren? (J/N)"
        if ($antwort -eq "J" -or $antwort -eq "j") {
            Install-Module $m -Scope CurrentUser -Force
        } else {
            Write-Host "Abgebrochen - Modul '$m' wird benoetigt." -ForegroundColor Red
            exit
        }
    }
}


Write-Host "1. Es werden zuerst die Berechtigungen angefordert um überhaupt eine App registrieren zu dürfen."
Write-Host "2. Dann kommt eine sehr Liste mit angeforderten Berechtigungen, dass sind die, die der App gewährt werden."
Write-Host "3. Es können optional noch weitere Berechtigungen vergeben werden" 
Write-Host "4. Die Berechtigungen müssen später noch als Admin bestätigt werden."
Write-Host ""
# - GRAPH VERBINDUNG
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Connect-MgGraph -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All" -NoWelcome -UseDeviceCode

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
$AppName = "MAHR-EDV-Wartung"
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$CertYearsValid = 2

# - TENANT ERMITTELN
$Tenant = Get-MgOrganization
$TenantName = $Tenant.DisplayName
$TenantId = $Tenant.Id
$CustomerNameClean = $TenantName -replace '[\\\/:\*\?"<>\|]', '' -replace '\s+', '_'

# - KUNDENINFOS (ORDNER + JSON)
$BaseInfoDir = "C:\Kundeninfos"
$AppInfoDir  = Join-Path $BaseInfoDir $AppName
$JsonPath    = Join-Path $BaseInfoDir "kunden-tenantinfos.json"

if (-not (Test-Path $BaseInfoDir)) {
    New-Item -ItemType Directory -Path $BaseInfoDir | Out-Null
}

if (-not (Test-Path $AppInfoDir)) {
    New-Item -ItemType Directory -Path $AppInfoDir | Out-Null
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

# - GRAPH APP PERMISSIONS
$GraphAppPermissions = @(
    "Application.Read.All",
    "AuditLog.Read.All",
    "Device.Read.All",
    "DeviceManagementConfiguration.Read.All",
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementApps.Read.All",
    "Directory.Read.All",
    "Group.Read.All",
    "Organization.Read.All",
    "Policy.Read.All",
    "Reports.Read.All",
    "SecurityAlert.Read.All",
    "SecurityEvents.Read.All",
    "SecurityIncident.Read.All",
    "Sites.Read.All",
    "Team.ReadBasic.All",
    "UserAuthenticationMethod.Read.All",
    "User.Read.All",

# - SCHREIBRECHTE ACHTUNG
    "User.ReadWrite.All"
)

# -- ZUSÄTZLICH VERFÜGBAR (aktuell nicht aktiv)
$GraphAppPermissionsZusaetzlich = @(
    "DeviceManagementScripts.Read.All",
    "GroupMember.Read.All",
    "LicenseAssignment.Read.All",
    "SharePointTenantSettings.Read.All",
    "TeamMember.Read.All",
    "UserAuthMethod-Email.Read.All",
    "UserAuthMethod-External.Read.All",
    "UserAuthMethod-HardwareOATH.Read.All",
    "UserAuthMethod-MicrosoftAuthApp.Read.All",
    "UserAuthMethod-Passkey.Read.All",
    "UserAuthMethod-Password.Read.All",
    "UserAuthMethod-Phone.Read.All",
    "UserAuthMethod-PlatformCred.Read.All",
    "UserAuthMethod-QR.Read.All",
    "UserAuthMethod-SoftwareOATH.Read.All"
)

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
    $PfxPassword = Read-Host "PFX-Passwort für $CustomerNameClean" -AsSecureString

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
Write-Host ""
Write-Host "AKTIVE BERECHTIGUNGEN (werden immer gesetzt)" -ForegroundColor Green
$GraphAppPermissions | ForEach-Object { Write-Host " - $_" }

Write-Host ""
Write-Host "Zusaetzliche Berechtigungen auswaehlen: Leertaste = anhaken, Enter = uebernehmen, Esc = keine." -ForegroundColor Yellow
$ZusaetzlicheAuswahl = $GraphAppPermissionsZusaetzlich |
    ForEach-Object { [PSCustomObject]@{ Berechtigung = $_ } } |
    Out-ConsoleGridView -OutputMode Multiple -Title "Zusaetzliche Berechtigungen"

if ($ZusaetzlicheAuswahl) {
    $GraphAppPermissions = @($GraphAppPermissions) + @($ZusaetzlicheAuswahl.Berechtigung)
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
#Write-Host "Thumbprint   : $Thumbprint = $cert.Thumbprint"

Write-Host ""

# - TRENNEN
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

Write-Host ""
Write-Host "PRÜFEN, OB ADMIN CONSENT NOCH ERFORDERLICH IST!!!" -ForegroundColor Yellow
Write-Host "https://entra.microsoft.com -> App-Registrierungen -> $AppName -> API-Berechtigungen" -ForegroundColor Yellow
Write-Host "Evtl. APP-Seite im Browser mit [F5] aktualisieren!!!" -ForegroundColor Yellow
Write-Host ""
# - ENTRA PORTAL ÖFFNEN (IM AKTIVEN BROWSER)
#Write-Host "Bitte jetzt das richtige Kundenprofil im Browser oeffnen (in den Vordergrund holen)." -ForegroundColor Yellow
#Write-Host "Weiter mit [Enter]." -ForegroundColor Yellow
#Read-Host | Out-Null
#Start-Process "https://entra.microsoft.com/?l=de.de-de#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade/quickStartType~/null/sourceType/Microsoft_AAD_IAM"