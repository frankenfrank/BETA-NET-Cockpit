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
Write-Host "=== Wartung-07.1-Firewall-Sophos ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Prüft eine oder mehrere Sophos Firewalls per XML-API (Firmware-Hinweis, Backup-Hinweis, Log-Hinweis, offene Ports/DNAT von WAN) und schreibt Ergebnis in eine Logdatei.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Firewalls (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Gerät das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfällt die Listenpflege und die Kontoabfrage. Ohne -Ziel läuft das Skript wie bisher interaktiv.

VORAUSSETZUNGEN
- API-Zugriff auf der Sophos Firewall aktiviert (System > Verwaltung > API-Zugriff), inkl. Eintrag der Quell-IP (dieser Rechner) unter den zugelassenen IP-Adressen
- PowerShell 7 auf dem ausführenden Rechner
- Zugangsdaten für ein Konto mit API-Zugriff (aus dem NET-COCKPIT je Firewall, sonst Abfrage)
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
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (Firewalls) nötig." -ForegroundColor Red
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


# - KONFIGURATION
$Datum = Get-Date -Format "yyyyMMdd"
$Datei = Join-Path $Ausgabepfad "Wartung_${Datum}_Sophos.txt"
$Port  = 4444

if (Test-Path $Datei) { Remove-Item $Datei -Force }

# - SERVERLISTE
$ServerListFile = Join-Path $Ausgabepfad "liste-sophos.txt"

if ($ZielModus) {
    $FirewallListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Geräte (aus dem NET-COCKPIT):"
    $FirewallListe | ForEach-Object { Write-Host " - $_" }
}
else {
    if (-not (Test-Path $ServerListFile)) {
        (Read-Host "Sophos Firewall IP-Adresse(n) (Komma getrennt)") -split ",\s*" |
            Out-File $ServerListFile -Encoding utf8
    }

    Write-Host "`nZu prüfende Sophos Firewalls:"
    Get-Content $ServerListFile | ForEach-Object { Write-Host " - $_" }

    if ((Read-Host "`nWeitere Firewall hinzufügen? (j/n)") -eq "j") {
        (Read-Host "Neue IP(s) (Komma getrennt)") -split ",\s*" |
            Add-Content $ServerListFile
    }

    $FirewallListe = Get-Content $ServerListFile
}

Add-Content $Datei "===== Sophos Firewall Kurzcheck ====="
Add-Content $Datei "Ausgeführt von: $env:COMPUTERNAME"
Add-Content $Datei "Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"

# - API HELFER
function Invoke-SophosApi {
    param(
        [Parameter(Mandatory)][string]$Firewall,
        [Parameter(Mandatory)][string]$Xml
    )
    $uri = "https://$($Firewall):$($Port)/webconsole/APIController"
    Invoke-RestMethod -Uri $uri -Method Post -Body @{ reqxml = $Xml } -SkipCertificateCheck
}

foreach ($Firewall in $FirewallListe) {
    Write-Host "`n===== Sophos: $Firewall ====="
    Add-Content $Datei "`n===== Sophos: $Firewall ====="

    $erreicht = $false
    $notizFw = ''
    $offenListe = @()

    # --- Zugangsdaten: Konto aus dem NET-COCKPIT, sonst einmalige Abfrage für alle Firewalls ---
    $cred = Get-ZielKonto -Name $Firewall
    if (-not $cred) {
        if (-not $script:ManuellKonto -and -not $Automatik) { $script:ManuellKonto = Get-Credential -Message "API-Zugangsdaten für Sophos Firewall (Benutzer mit API-Zugriff)" }
        $cred = $script:ManuellKonto
    }
    if (-not $cred) {
        Add-Content $Datei "Keine Zugangsdaten vorhanden, Firewall übersprungen."
        $ergebnisListe.Add([pscustomobject]@{ Ziel = $Firewall; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Keine Zugangsdaten' })
        continue
    }
    $user = [System.Security.SecurityElement]::Escape($cred.UserName)
    $pass = [System.Security.SecurityElement]::Escape($cred.GetNetworkCredential().Password)

    # --- 1. Firmware-Update ---
    Add-Content $Datei "`n--- Firmware ---"
    Add-Content $Datei "Hinweis: Firmwarestand/Aktualität ist über die Sophos XML-API nicht abrufbar (kein Firmware-Objekt vorhanden)."
    Add-Content $Datei "Manuell prüfen: WebAdmin > Backup & Firmware > Firmware, Abgleich mit https://www.sophos.com/en-us/support/release-notes"

    # --- 2. Konfiguration gesichert ---
    Add-Content $Datei "`n--- Konfigurationssicherung ---"
    Add-Content $Datei "Hinweis: Backup-Status ist über die Sophos XML-API nicht abrufbar. Manuell prüfen: Backup & Firmware > Backup, oder Zeitstempel am Backup-Ziel (FTP/lokal/E-Mail je nach Konfiguration)."

    # --- 3. Log auf Angriffe ---
    Add-Content $Datei "`n--- Log / Angriffe ---"
    Add-Content $Datei "Hinweis: Log-Auswertung ist über die Sophos XML-API nicht möglich (keine Log-Objekte vorhanden)."
    Add-Content $Datei "Manuell prüfen: Log Viewer > Angriffsschutz/IPS im WebAdmin, oder Sophos Central, falls dort verwaltet."

    # --- 4. Offene Ports (DNAT) ---
    Add-Content $Datei "`n--- Offene Ports (DNAT) ---"
    try {
        $xml = @"
<Request>
  <Login>
    <Username>$user</Username>
    <Password>$pass</Password>
  </Login>
  <Get>
    <FirewallRule></FirewallRule>
  </Get>
</Request>
"@
        $result = Invoke-SophosApi -Firewall $Firewall -Xml $xml

        if ($result.Response.Login.status -eq "Authentication Failure") {
            Add-Content $Datei "LOGIN FEHLGESCHLAGEN: Benutzername/Passwort prüfen, oder API-Zugriff/Quell-IP auf der Firewall nicht freigegeben."
            Write-Host "  Login fehlgeschlagen bei $Firewall" -ForegroundColor Red
            $notizFw = 'Login fehlgeschlagen (API-Zugriff/Quell-IP/Konto prüfen)'
        } else {
            Add-Content $Datei "Login erfolgreich."
            $erreicht = $true

            $rules = @($result.Response.FirewallRule)
            Add-Content $Datei "Regeln gesamt: $($rules.Count)"

            # Relevant fuer "offene Ports von extern": Regeln mit AUSSCHLIESSLICH Quellzone WAN und Action Accept.
            # Multi-Zonen-Regeln (WAN neben LAN/DMZ/VPN/...) sind i.d.R. keine echten Freigaben von aussen.
            $offen = foreach ($r in $rules) {
                $policy = if ($r.NetworkPolicy) { $r.NetworkPolicy } elseif ($r.UserPolicy) { $r.UserPolicy } else { $null }
                if (-not $policy) { continue }

                $srcZones = @($policy.SourceZones.Zone)
                if ($policy.Action -eq 'Accept' -and $srcZones.Count -eq 1 -and $srcZones[0] -eq 'WAN') {
                    $services  = if ($policy.Services.Service)          { (@($policy.Services.Service) -join ', ') }          else { 'Any' }
                    $destZones = if ($policy.DestinationZones.Zone)     { (@($policy.DestinationZones.Zone) -join ', ') }     else { '-' }
                    $destNets  = if ($policy.DestinationNetworks.Network) { (@($policy.DestinationNetworks.Network) -join ', ') } else { '-' }
                    [PSCustomObject]@{
                        Name        = [string]$r.Name
                        Status      = [string]$r.Status
                        ZielZone    = $destZones
                        ZielNetz    = $destNets
                        Dienste     = $services
                        Beschreibung = [string]$r.Description
                    }
                }
            }

            $offenListe = @($offen | Where-Object { $_ })
            if ($offenListe.Count -gt 0) {
                Add-Content $Datei "Offene Freigaben von WAN (SourceZone=WAN, Action=Accept): $($offenListe.Count)"
                foreach ($o in $offen) {
                    Add-Content $Datei ("  {0} | Status:{1} | Ziel-Zone:{2} | Ziel-Netz:{3} | Dienste:{4} | Beschreibung:{5}" -f $o.Name, $o.Status, $o.ZielZone, $o.ZielNetz, $o.Dienste, $o.Beschreibung)
                }
            } else {
                Add-Content $Datei "Keine Freigaben von WAN gefunden."
            }
        }
    } catch {
        Add-Content $Datei "Fehler beim API-Zugriff: $($_.Exception.Message)"
        $notizFw = "Fehler beim API-Zugriff: $($_.Exception.Message)"
    }

    ## Firmware, Konfigurationssicherung und Log sind über die XML-API nicht prüfbar, daher keine Haken; nur die WAN-Freigaben stehen in den Werten
    if ($erreicht) { $notizFw = "$($offenListe.Count) Freigabe(n) von WAN (Relevanz manuell prüfen)" }
    $ergebnisListe.Add([pscustomobject]@{
        Ziel       = $Firewall
        Erreicht   = $erreicht
        Pruefungen = [pscustomobject]@{}
        Werte      = [pscustomobject]@{ WanFreigaben = @($offenListe | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Status = $_.Status; ZielZone = $_.ZielZone; ZielNetz = $_.ZielNetz; Dienste = $_.Dienste; Beschreibung = $_.Beschreibung } }) }
        Notiz      = $notizFw
    })
}

# - ABSCHLUSS
Add-Content $Datei "`n===== Ende Sophos Kurzcheck ====="
Write-Host ("Sophos Kurzcheck abgeschlossen. Datei gespeichert unter: {0}" -f $Datei) -ForegroundColor Yellow
if ($Automatik) {
    Get-Content -LiteralPath $Datei | Write-Host
    Write-WtErgebnis -Skript '07.1-Firewall-Sophos' -Ordner $Ausgabepfad -Ergebnisse $ergebnisListe.ToArray()
    if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}

Start-Process notepad.exe $Datei