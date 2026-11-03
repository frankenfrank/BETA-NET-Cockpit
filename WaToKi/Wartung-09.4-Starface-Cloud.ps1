#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string]$Ziel,
    [string]$Ausgabeordner,
    [System.Management.Automation.PSCredential]$Anmeldedaten
)

Clear-Host
Write-Host ""
Write-Host "=== Wartung-09.4-Starface-Cloud ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host ""
Write-Host @'
BESCHREIBUNG
Fragt eine STARFACE Cloud Telefonanlage (STARFACE 10) per REST-API ab und schreibt die Wartungsdaten als Textdatei nach <Ausgabeordner>\Wartung_STARFACE_<Anlagenname>.txt (Version, Update-Einstellungen, Lizenzen, Auslastung, Mailserver, Gruppen, Voicemailboxen, Benutzer mit Rufnummern, Gerät und DND). Die Datei wird bei jedem Lauf überschrieben.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die Anlage (-Ziel, Hostname der Anlagen-URL), den Ausgabeordner (-Ausgabeordner) und das Konto der Spalte "Konto" (-Anmeldedaten). Dann entfallen die Abfragen von Anlagen-URL und Benutzer. Das Client-Secret fragt das Skript immer ab. Ohne Parameter fragt es alles selbst ab und speichert in C:\Temp\<Anlagenname>.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Anlagen-URL der STARFACE Cloud (Eingabe mit oder ohne https:// möglich)
- Administrator-Benutzer der Anlage mit der Berechtigung "API Zugriff mit OAuth Password Grant"
- Client-Secret von rest-client-headless (Admin-Oberfläche unter Server -> Status, Bereich REST API)
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - EINGABEN
$anlagenEingabe = if ([string]::IsNullOrWhiteSpace($Ziel)) { Read-Host "Anlagen-URL" } else { $Ziel.Trim() }
$hostname     = $anlagenEingabe -replace '^https?://', '' -replace '/.*$', ''
$cred         = $Anmeldedaten
if (-not $cred) { $cred = Get-Credential -Message "STARFACE Benutzer" }
if (-not $cred) { Write-Host "Keine Zugangsdaten - Skript wird beendet." -ForegroundColor Red; return }
$clientSecret = Read-Host "Client-Secret (rest-client-headless) für $hostname" -AsSecureString
$clientSecret = [System.Net.NetworkCredential]::new("", $clientSecret).Password

# - ANLAGENNAME
$AnlageClean = $hostname -replace '[\\\/:\*\?"<>\|]', '' -replace '\s+', '_'
$host.UI.RawUI.WindowTitle = "$hostname"

# - ORDNER SICHERSTELLEN
$Ordner = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp\$AnlageClean" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ordner)) {
    New-Item -ItemType Directory -Path $Ordner -Force | Out-Null
}

# - DATEIPFAD
$filepath = [System.IO.Path]::Combine($Ordner, "Wartung_STARFACE_$AnlageClean.txt")

# - AUSGABEFUNKTION
function Write-Log {
    param([string]$Text)

    Write-Host $Text
    Add-Content -LiteralPath $filepath -Value $Text
}

# - DATEI LEEREN
"" | Set-Content -LiteralPath $filepath

# - TOKEN HOLEN
$body = @{
    grant_type    = 'password'
    client_id     = 'rest-client-headless'
    client_secret = $clientSecret
    username      = $cred.UserName
    password      = $cred.GetNetworkCredential().Password
    scope         = 'pbx-admin'
}
try {
    $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://$hostname/auth/realms/pbx/oauth2/token" -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
}
catch {
    Write-Host "Anmeldung an $hostname fehlgeschlagen: $($_.Exception.Message) $($_.ErrorDetails.Message)" -ForegroundColor Red
    Write-Host "Bitte Benutzer (Spalte Konto), Berechtigung 'API Zugriff mit OAuth Password Grant' und Client-Secret prüfen." -ForegroundColor Yellow
    return
}
$headers = @{ Authorization = "Bearer $($tokenResponse.access_token)" }
$baseUrl = "https://$hostname/rest"

# - HILFSFUNKTIONEN
## API-Abfrage mit Fehlerbehandlung
function Get-Api {
    param([string]$Pfad)

    try {
        return Invoke-RestMethod -Method Get -Uri "$baseUrl$Pfad" -Headers $headers
    } catch {
        Write-Host "Abfrage $Pfad fehlgeschlagen: $($_.Exception.Message) $($_.ErrorDetails.Message)" -ForegroundColor Yellow
        return $null
    }
}

## Objekt als Liste ausgeben
function Write-Objekt {
    param($Objekt)

    $Objekt | Format-List | Out-String -Width 250 -Stream | ForEach-Object { if ($_.Trim()) { Write-Log $_.TrimEnd() } }
}

# - DATEN ABFRAGEN
Write-Host "Abfrage laeuft..."

## Rufnummern (Id -> Nummer)
$numberMap = @{}
$phoneNumbers = Get-Api "/phonenumbers"
foreach ($pn in @($phoneNumbers)) {
    if ($pn.type -eq 'EXTERNAL') {
        $numberMap[[int]$pn.id] = "+$($pn.nationalPrefix) $($pn.localPrefix) $($pn.number)"
    } else {
        $numberMap[[int]$pn.id] = $pn.number
    }
}

## Benutzer
$users = Get-Api "/users"

## Serverdaten
$version        = Get-Api "/server/version"
$updateSettings = Get-Api "/server/updates/settings"
$licenseInfo    = Get-Api "/server/licenses/info"
$serverLicenses = Get-Api "/server/licenses"
$moduleLicenses = Get-Api "/server/licenses/modules"
$utilization    = Get-Api "/server/state/utilization/pbx"
$serverTime     = Get-Api "/server/time"
$ntp            = Get-Api "/server/ntp"
$mailserver     = Get-Api "/server/mailserver"
$groups         = Get-Api "/groups"
$voicemailboxes = Get-Api "/voicemailboxes"

# - BENUTZERAUSWERTUNG
$result = foreach ($user in @($users)) {

    ## Rufnummern des Benutzers
    $extern = $null
    $intern = $null
    $numCfg = Get-Api "/users/$($user.id)/phonenumberconfig"
    if ($numCfg) {
        $extern = $numberMap[[int]$numCfg.primaryExternalNumberId]
        $intern = $numberMap[[int]$numCfg.primaryInternalNumberId]
    }

    ## Primaeres Geraet und DND
    $geraet = $null
    $dnd    = $null
    $phoneCfg = Get-Api "/users/$($user.id)/phoneconfig"
    $phones   = Get-Api "/users/$($user.id)/phoneconfig/phones"
    if ($phoneCfg) {
        $geraet = (@($phones) | Where-Object { $_.phoneId -eq $phoneCfg.primaryPhoneId }).phoneName
        $dnd    = if ($phoneCfg.doNotDisturb) { 'Ja' } else { 'Nein' }
    }

    [PSCustomObject]@{
        Lizenz          = $user.licenseType
        Nachname        = $user.familyName
        Vorname         = $user.firstName
        Email           = $user.email
        'Rufnr. Extern' = if ($extern) { $extern } else { '---' }
        'Rufnr. Intern' = if ($intern) { $intern } else { '---' }
        'Prim. Geraet'  = if ($geraet) { $geraet } else { '---' }
        DND             = if ($dnd) { $dnd } else { '---' }
    }
}

# - AUSGABE
Write-Log "= STARFACE Wartungsauswertung ($hostname) ="

## Systemversion
Write-Log ""
Write-Log "=== SYSTEMVERSION ==="
if ($version) {
    Write-Log "Release:              $($version.release)"
    Write-Log "Version:              $($version.version)"
    Write-Log "Release-Datum:        $($version.releaseDate)"
    Write-Log "Letzte Aktualisierung: $($version.lastUpdate)"
}
if ($updateSettings) {
    Write-Log "Update-Benachrichtigung aktiv: $($updateSettings.notifyForUpdate)"
    Write-Log "Download im Hintergrund:       $($updateSettings.downloadInBackground)"
}
Write-Log "Neuere Version verfuegbar: manuell pruefen (nicht per API abfragbar)"

## Serverzeit
Write-Log ""
Write-Log "=== SERVERZEIT ==="
if ($serverTime) { Write-Objekt $serverTime }
if ($ntp)        { Write-Objekt $ntp }

## Lizenzen
Write-Log ""
Write-Log "=== LIZENZEN ==="
if ($licenseInfo) {
    Write-Log "User:          $($licenseInfo.licensedUsers) lizenziert, $($licenseInfo.availableUserLicenses) frei"
    Write-Log "User Light:    $($licenseInfo.licensedLightUsers) lizenziert, $($licenseInfo.availableUserLightLicenses) frei"
    Write-Log "UCC:           $($licenseInfo.licensedUccUsers) lizenziert, $($licenseInfo.availableUccLicenses) frei"
    Write-Log "Terminal:      $($licenseInfo.licensedTerminalUsers) lizenziert, $($licenseInfo.availableTerminalLicenses) frei"
    if ($licenseInfo.updateOption) {
        Write-Log "Update-Option: $($licenseInfo.updateOption.users) User, gueltig bis $($licenseInfo.updateOption.expireDate)"
    }
}
foreach ($sl in @($serverLicenses)) {
    if ($sl) { Write-Log "Serverlizenz:  $($sl.productName), Version $($sl.licensedVersion), max. $($sl.maxUsers) User, gueltig bis $($sl.validUntil)" }
}
foreach ($ml in @($moduleLicenses)) {
    if ($ml) { Write-Log "Modul:         $($ml.productName), Version $($ml.licensedVersion), max. $($ml.maxInstances) Instanzen, gueltig bis $($ml.validUntil)" }
}

## Auslastung
Write-Log ""
Write-Log "=== AUSLASTUNG (aktuell) ==="
if ($utilization) {
    Write-Log "Benutzer:            $($utilization.users)"
    Write-Log "Aktive Anrufe:       $($utilization.calls)"
    Write-Log "Konferenzen:         $($utilization.conferences)"
    Write-Log "Gehaltene Anrufe:    $($utilization.hold)"
    Write-Log "Angemeldete Clients: $($utilization.loggedClientUsers)"
    Write-Log "UCC-Clients:         $($utilization.uccClients)"
}

## Mailserver
Write-Log ""
Write-Log "=== MAILSERVER ==="
if ($mailserver) {
    Write-Log "Absenderadresse: $($mailserver.senderMailAddress)"
    Write-Log "SMTP-Host:       $($mailserver.smtpHost)"
    Write-Log "SMTP-Benutzer:   $($mailserver.smtpUsername)"
    Write-Log "SMTP-Sicherheit: $($mailserver.smtpSecurity)"
    Write-Log "SMTP-Auth:       $($mailserver.smtpAuth)"
}

## Gruppen und Voicemailboxen
## Gruppen und Voicemailboxen
Write-Log ""
Write-Log "=== GRUPPEN UND VOICEMAILBOXEN ==="
Write-Log "Gruppen: $(@($groups).Count)"
foreach ($g in @($groups)) {
    Write-Log "- $($g.groupname) (intern $($g.groupinternalnumber), extern $($g.groupexternalnumber))"
}
Write-Log "Voicemailboxen: $(@($voicemailboxes).Count)"

## Benutzer
Write-Log ""
Write-Log "=== BENUTZER ($(@($result).Count)) ==="
$result | Sort-Object Nachname | Format-Table -AutoSize | Out-String -Width 250 -Stream | ForEach-Object { if ($_.Trim()) { Write-Log $_.TrimEnd() } }

## Manuell zu pruefen
Write-Log ""
Write-Log "=== MANUELL ZU PRUEFEN ==="
Write-Log "SIP Trunk / Anlagenanschluesse online: in der Oberflaeche unter Leitungen pruefen (nicht per API abfragbar)"
Write-Log "Endgeraete auf dem neusten Stand: Firmware bei Festnetz-Telefonen und Client-Version manuell pruefen (nicht per API abfragbar)"
Write-Log "Konfiguration gesichert: Backup in der Oberflaeche unter Server -> Backup pruefen (nicht per API abfragbar)"

Write-Host ""
Write-Host "Bericht gespeichert: $filepath" -ForegroundColor Green