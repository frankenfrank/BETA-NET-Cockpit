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
Write-Host "=== Wartung-08.1-Router_FritzBox ===" -ForegroundColor Cyan

Write-Host ""
# - VORAUSSETZUNGEN ANZEIGEN
if (-not $Automatik) { Write-Host @'
BESCHREIBUNG
Fragt eine oder mehrere Fritz!Box im lokalen Netz ab (TR-064, UPnP-IGD + Weboberfläche) und schreibt das Ergebnis in eine Datei.
Ruft ab: FRITZ!OS-Version, Update-Verfügbarkeit, letzter Reconnect, externe IP, WAN-Datenrate aus den Verbindungsdetails (Online-Monitor, Seite netMoni) und Log-Einträge mit Warn-/Fehlerbezug (Schlüsselwort-Filter).
Schlägt der Ping fehl, wird nachgefragt, ob die Wartung trotzdem versucht werden soll (manche Fritz!Box blockieren ICMP, sind aber per HTTP/TR-064 erreichbar). Aus dem NET-COCKPIT (Automatik) wird sie ohne Rückfrage trotzdem versucht.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten Fritz!Box (-Ziel), den Ausgabeordner (-Ausgabeordner) und je Gerät das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Dann entfällt die Listenpflege und die Kontoabfrage. Ohne -Ziel läuft das Skript wie bisher interaktiv.

VORAUSSETZUNGEN
- PowerShell 7 muss installiert sein (winget install --id Microsoft.PowerShell -e)
- Fritz!Box: Heimnetz > Netzwerk > Netzwerkeinstellungen > "Zugriff für Anwendungen zulassen" und "Statusinformationen über UPnP übertragen" aktiviert
- Fritz!Box-Benutzer mit der Berechtigung "FRITZ!Box Einstellungen"
- Ausführung auf einem Rechner im selben Netz wie die Fritz!Box
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
    Write-Host "Abbruch: Im Automatikmodus ist -Ziel (Fritz!Box) nötig." -ForegroundColor Red
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
    if ($Automatik) { return $null }
    return (Get-Credential -Message $Meldung)
}


# - PARAMETER
$LogStunden = 0      # 0 = gesamtes Log, sonst nur die letzten X Stunden
$SpeedPage  = $null  # optional: zusätzliche data.lua-Seite, die vor netMoni gelesen wird
$SaveRaw    = $false # $true = rohe JSON-Antworten in den Ausgabeordner speichern (enthalten IPs, Gerätenamen, MAC-Adressen)
$LogPattern = 'fehler|fehlgeschlagen|gescheitert|nicht erfolgreich|warnung|abgelehnt|verloren|unterbrochen|ungültig|ungueltig|angriff|blockiert|timeout|failed|error|warning|denied|attack'

# - FRITZBOX-LISTE
if ($ZielModus) {
    $FritzListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
    Write-Host "`nZu prüfende Geräte (aus dem NET-COCKPIT):"
    $FritzListe | ForEach-Object { Write-Host " - $_" }
}
else {
    $ServerListFile = "C:\Temp\liste-router_fritzbox.txt"
    if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }

    if (-not (Test-Path $ServerListFile)) {
        (Read-Host "Fritz!Box Hostname/IP (Komma getrennt)") -split ",\s*" |
            Out-File $ServerListFile -Encoding utf8
    }

    Write-Host "`nZu prüfende Fritz!Box:"
    Get-Content $ServerListFile | ForEach-Object { Write-Host " - $_" }

    if ((Read-Host "`nWeitere Fritz!Box hinzufügen? (j/n)") -eq "j") {
        (Read-Host "Neue Fritz!Box (Komma getrennt)") -split ",\s*" |
            Add-Content $ServerListFile
    }

    $FritzListe = @(Get-Content $ServerListFile | Where-Object { $_.Trim() -ne "" })
}

# - AUSGABEDATEI
$Datum        = Get-Date -Format "yyyyMMdd"
$Dateiname    = "Wartung_${Datum}_Fritzbox.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname

# -- ALTE DATEI LÖSCHEN
Remove-Item $AusgabeDatei -ErrorAction SilentlyContinue


# - FUNKTIONEN
Add-Type -AssemblyName System.Net.Http

# -- LOGGING (KONSOLE + DATEI)
function Write-Log {
    param(
        [string]$Message = "",
        [System.ConsoleColor]$ForegroundColor
    )
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { Write-Host $Message -ForegroundColor $ForegroundColor }
    else { Write-Host $Message }
    Add-Content -Path $AusgabeDatei -Value $Message -Encoding utf8
}

# -- SOAP (TR-064 / UPnP)
function Invoke-Soap {
    param($Ctx, [string]$ControlUrl, [string]$Service, [string]$Action)

    $body = @"
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body><u:$Action xmlns:u="$Service" /></s:Body>
</s:Envelope>
"@
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, "$($Ctx.BaseUrl)$ControlUrl")
    [void]$req.Headers.TryAddWithoutValidation('SOAPACTION', "`"$Service#$Action`"")
    $req.Content = [System.Net.Http.StringContent]::new($body, [Text.Encoding]::UTF8, 'text/xml')

    $resp  = $Ctx.Http.SendAsync($req).GetAwaiter().GetResult()
    $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    $text  = [Text.Encoding]::UTF8.GetString($bytes)

    if (-not $resp.IsSuccessStatusCode) {
        $detail = ''
        try {
            $x = [xml]$text
            $detail = " (Fehler $($x.Envelope.Body.Fault.detail.UPnPError.errorCode): $($x.Envelope.Body.Fault.detail.UPnPError.errorDescription))"
        } catch {}
        throw "$Action @ $ControlUrl : HTTP $([int]$resp.StatusCode)$detail"
    }

    $xml = [xml]$text
    $result = @{}
    foreach ($n in $xml.Envelope.Body.FirstChild.ChildNodes) { $result[$n.LocalName] = $n.InnerText }
    return $result
}

# -- DAUER FORMATIEREN
function Format-Duration {
    param([double]$Seconds)
    $ts = [TimeSpan]::FromSeconds($Seconds)
    return ('{0}d {1}h {2}min' -f $ts.Days, $ts.Hours, $ts.Minutes)
}

# -- WEBOBERFLÄCHE LOGIN (SID)
function Get-FritzSid {
    param($Ctx)

    $xml  = [xml](Invoke-RestMethod -Uri "$($Ctx.WebUrl)/login_sid.lua?version=2")
    $info = $xml.SessionInfo
    if ($info.SID -ne '0000000000000000') { return $info.SID }

    $challenge = $info.Challenge
    if ($challenge -like '2$*') {
        # PBKDF2 (FRITZ!OS 7.24+)
        $p     = $challenge.Split('$')
        $iter1 = [int]$p[1]; $salt1 = [Convert]::FromHexString($p[2])
        $iter2 = [int]$p[3]; $salt2 = [Convert]::FromHexString($p[4])
        $alg   = [System.Security.Cryptography.HashAlgorithmName]::SHA256
        $hash1 = [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2([Text.Encoding]::UTF8.GetBytes($Ctx.Password), $salt1, $iter1, $alg, 32)
        $hash2 = [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2($hash1, $salt2, $iter2, $alg, 32)
        $response = $p[4] + '$' + [Convert]::ToHexString($hash2).ToLower()
    }
    else {
        # MD5 (ältere FRITZ!OS-Versionen)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $response = "$challenge-" + [Convert]::ToHexString($md5.ComputeHash([Text.Encoding]::Unicode.GetBytes("$challenge-$($Ctx.Password)"))).ToLower()
    }

    $uri  = "$($Ctx.WebUrl)/login_sid.lua?version=2&username=$([Uri]::EscapeDataString($Ctx.Username))&response=$response"
    $xml2 = [xml](Invoke-RestMethod -Uri $uri)
    if ($xml2.SessionInfo.SID -eq '0000000000000000') { throw 'Login an der Weboberfläche fehlgeschlagen (Benutzer/Passwort?).' }
    return $xml2.SessionInfo.SID
}

# -- DATA.LUA ABFRAGEN
function Get-DataLua {
    param($Ctx, [string]$Page)

    if (-not $Ctx.Sid) { $Ctx.Sid = Get-FritzSid -Ctx $Ctx }
    $body = "xhr=1&sid=$($Ctx.Sid)&lang=de&page=$Page&xhrId=all&useajax=1&no_sidrenew="
    $r = Invoke-RestMethod -Uri "$($Ctx.WebUrl)/data.lua" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    if ($r -is [string]) { $r = $r | ConvertFrom-Json }

    if ($SaveRaw) {
        $file = Join-Path $Ausgabepfad "fritz_raw_$($Ctx.Host)_$Page.json"
        $r | ConvertTo-Json -Depth 30 | Set-Content -Path $file -Encoding UTF8
        Write-Log "  (Rohdaten gespeichert: $file)" -ForegroundColor DarkGray
    }
    return $r
}

# -- WAN-RATE FORMATIEREN (AVM liefert kbit/s)
function Format-FritzRate {
    param($Value)

    if ($null -eq $Value -or "$Value".Trim() -eq '') { return $null }
    $s = "$Value".Trim()
    if ($s -match '(?i)(mbit|kbit|gbit|bit/s)') { return $s }

    $n    = 0.0
    $norm = $s -replace ',', '.'
    if (-not [double]::TryParse($norm, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $s }
    if ($n -lt 0) { return $null }

    $mbit = $n / 1000.0
    $de   = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    if ($mbit -ge 100) { return ($mbit.ToString('0.#', $de) + ' Mbit/s') }
    return ($mbit.ToString('0.0', $de) + ' Mbit/s')
}

# -- WAN-VERBINDUNGEN AUS JSON
function Get-WanConnections {
    param($Json)

    $conns = @()
    if ($Json.data.internet.connections) { $conns = @($Json.data.internet.connections) }
    elseif ($Json.data.connections)      { $conns = @($Json.data.connections) }
    return $conns
}

# -- STATUS EINER FRITZ!BOX
function Get-FritzStatus {
    param([string]$FritzHost, [pscredential]$Cred)

    $netCred  = $Cred.GetNetworkCredential()
    $problems = [System.Collections.Generic.List[string]]::new()
    $sum = [ordered]@{
        Fritzbox   = $FritzHost
        Status     = "OK"
        Modell     = ""
        OS         = ""
        Update     = ""
        Reconnect  = ""
        IPv4       = ""
        Download   = ""
        Upload     = ""
        LogTreffer = ""
        Probleme   = ""
    }

    $cache = [System.Net.CredentialCache]::new()
    $cache.Add([Uri]"http://${FritzHost}:49000", 'Digest', $netCred)
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.Credentials = $cache
    $http = [System.Net.Http.HttpClient]::new($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(20)

    $ctx = @{
        Host     = $FritzHost
        BaseUrl  = "http://${FritzHost}:49000"
        WebUrl   = "http://${FritzHost}"
        Username = $Cred.UserName
        Password = $netCred.Password
        Sid      = $null
        Http     = $http
    }

    try {
        # --- System: Version + Update ---
        Write-Log "`n--- SYSTEM ---" -ForegroundColor Yellow
        try {
            $dev   = Invoke-Soap -Ctx $ctx -ControlUrl '/upnp/control/deviceinfo' -Service 'urn:dslforum-org:service:DeviceInfo:1' -Action 'GetInfo'
            $raw   = $dev['NewSoftwareVersion']
            $parts = $raw.Split('.')
            $osVer = if ($parts.Count -ge 3) { '{0}.{1}' -f [int]$parts[1], $parts[2] } else { $raw }
            Write-Log "Modell            : $($dev['NewModelName'])"
            Write-Log "FRITZ!OS-Version  : $osVer  (Rohwert: $raw)"
            Write-Log "System-Laufzeit   : $(Format-Duration ([double]$dev['NewUpTime']))"
            $sum.Modell = $dev['NewModelName']
            $sum.OS     = $osVer
        }
        catch {
            $problems.Add("FRITZ!OS-Version: $($_.Exception.Message)")
            Write-Log 'FRITZ!OS-Version  : NICHT ABRUFBAR' -ForegroundColor Red
        }

        try {
            $ui = Invoke-Soap -Ctx $ctx -ControlUrl '/upnp/control/userif' -Service 'urn:dslforum-org:service:UserInterface:1' -Action 'GetInfo'
            if ($ui['NewUpgradeAvailable'] -eq '1') {
                Write-Log "Update verfügbar  : JA  (neue Version: $($ui['NewX_AVM-DE_Version']))" -ForegroundColor Green
                if ($ui['NewX_AVM-DE_InfoURL']) { Write-Log "Update-Infos      : $($ui['NewX_AVM-DE_InfoURL'])" }
                $sum.Update = "Ja ($($ui['NewX_AVM-DE_Version']))"
            }
            else {
                Write-Log 'Update verfügbar  : Nein'
                $sum.Update = "Nein"
            }
        }
        catch {
            $problems.Add("Update-Status: $($_.Exception.Message)")
            Write-Log 'Update verfügbar  : NICHT ABRUFBAR' -ForegroundColor Red
        }

        # --- Internetverbindung: Reconnect + IP ---
        Write-Log "`n--- INTERNETVERBINDUNG ---" -ForegroundColor Yellow
        $candidates = @(
            @{ Url = '/upnp/control/wanipconnection1'; Svc = 'urn:dslforum-org:service:WANIPConnection:1' },
            @{ Url = '/upnp/control/wanpppconn1';      Svc = 'urn:dslforum-org:service:WANPPPConnection:1' },
            @{ Url = '/igdupnp/control/WANIPConn1';    Svc = 'urn:schemas-upnp-org:service:WANIPConnection:1' }
        )
        $status = $null; $used = $null; $errs = @()
        foreach ($c in $candidates) {
            try {
                $status = Invoke-Soap -Ctx $ctx -ControlUrl $c.Url -Service $c.Svc -Action 'GetStatusInfo'
                $used = $c
                break
            }
            catch { $errs += $_.Exception.Message }
        }

        if ($status) {
            Write-Log "Status            : $($status['NewConnectionStatus'])"
            $sum.Verbindung = [string]$status['NewConnectionStatus']
            $up = [double]$status['NewUptime']
            $reconnect = '{0:dd.MM.yyyy HH:mm:ss}' -f (Get-Date).AddSeconds(-$up)
            Write-Log ("Letzter Reconnect : {0}  (online seit {1})" -f $reconnect, (Format-Duration $up))
            $sum.Reconnect = $reconnect
            if ($status['NewLastConnectionError'] -and $status['NewLastConnectionError'] -ne 'ERROR_NONE') {
                Write-Log "Letzter Fehler    : $($status['NewLastConnectionError'])" -ForegroundColor Yellow
            }
            try {
                $ip = Invoke-Soap -Ctx $ctx -ControlUrl $used.Url -Service $used.Svc -Action 'GetExternalIPAddress'
                Write-Log "Externe IPv4      : $($ip['NewExternalIPAddress'])"
                $sum.IPv4 = $ip['NewExternalIPAddress']
            }
            catch {
                $problems.Add("Externe IPv4: $($_.Exception.Message)")
                Write-Log 'Externe IPv4      : NICHT ABRUFBAR' -ForegroundColor Red
            }
            try {
                $v6 = Invoke-Soap -Ctx $ctx -ControlUrl $used.Url -Service $used.Svc -Action 'X_AVM_DE_GetExternalIPv6Address'
                if ($v6['NewExternalIPv6Address']) { Write-Log "Externe IPv6      : $($v6['NewExternalIPv6Address'])" }
            }
            catch {}
        }
        else {
            $problems.Add("Reconnect/IP: keine WAN-Schnittstelle antwortete. Details: " + ($errs -join ' | '))
            Write-Log 'Reconnect/IP      : NICHT ABRUFBAR' -ForegroundColor Red
        }

        # --- WAN-Datenrate (netMoni) ---
        Write-Log "`n--- GESCHWINDIGKEIT LAUT VERBINDUNGSDETAILS (WAN) ---" -ForegroundColor Yellow
        try {
            $pages = @()
            if ($SpeedPage) { $pages += $SpeedPage }
            $pages += 'netMoni', 'overview'
            $shown = $false
            $pageErrors = @()

            foreach ($pg in ($pages | Select-Object -Unique)) {
                try { $json = Get-DataLua -Ctx $ctx -Page $pg }
                catch { $pageErrors += "${pg}: $($_.Exception.Message)"; continue }

                $conns = @(Get-WanConnections $json | Where-Object {
                    $null -ne $_.downstream -or $null -ne $_.upstream -or $null -ne $_.medium_downstream -or $null -ne $_.medium_upstream
                })
                if ($conns.Count -eq 0) { continue }

                $active = @($conns | Where-Object { $_.active -eq $true -or $_.connected -eq $true -or $_.state -eq 'connected' })
                if ($active.Count -eq 0) { $active = $conns }

                Write-Log "Quelle            : $pg (Internet > Online-Monitor > Verbindungsdetails)"
                foreach ($con in $active) {
                    $medium = if ($con.medium) { $con.medium } elseif ($con.type) { $con.type } else { '' }
                    $label  = @($con.name, $medium, $con.provider) | Where-Object { $_ }
                    if ($label)     { Write-Log ("Verbindung        : {0}" -f ($label -join ' / ')) }
                    if ($con.state) { Write-Log "Status            : $($con.state)" }

                    $down = Format-FritzRate $con.downstream
                    $upR  = Format-FritzRate $con.upstream
                    $md   = Format-FritzRate $con.medium_downstream
                    $mu   = Format-FritzRate $con.medium_upstream
                    if ($down) { Write-Log "Download          : $down"; $sum.Download = $down }
                    if ($upR)  { Write-Log "Upload            : $upR";  $sum.Upload   = $upR }
                    if ($md -and $md -ne $down) { Write-Log "Download (Medium) : $md" }
                    if ($mu -and $mu -ne $upR)  { Write-Log "Upload (Medium)   : $mu" }
                    if ($con.shapedrate -eq $true) { Write-Log 'Hinweis           : Datenrate ist geformt (shapedrate)' -ForegroundColor DarkGray }
                    if (-not $down -and -not $upR) { Write-Log 'Download/Upload   : Felder vorhanden, aber leer' -ForegroundColor Yellow }
                    $shown = $true
                }
                if ($shown) { break }
            }

            if (-not $shown) {
                $detail = if ($pageErrors) { ' ' + ($pageErrors -join ' | ') } else { '' }
                $problems.Add("WAN-Datenrate: In netMoni/overview keine Verbindungsdetails mit downstream/upstream gefunden.$detail Mit `$SaveRaw = `$true die Rohdaten prüfen.")
                Write-Log 'WAN-Datenrate     : NICHT GEFUNDEN' -ForegroundColor Red
            }
        }
        catch {
            $problems.Add("WAN-Datenrate: $($_.Exception.Message)")
            Write-Log 'WAN-Datenrate     : NICHT ABRUFBAR' -ForegroundColor Red
        }

        # --- Log: Warnungen/Fehler ---
        Write-Log "`n--- LOG: WARNUNGEN/FEHLER (Schlüsselwort-Filter) ---" -ForegroundColor Yellow
        try {
            $json    = Get-DataLua -Ctx $ctx -Page 'log'
            $entries = @($json.data.log)
            if (-not $entries -or $entries.Count -eq 0) { throw 'Log-Antwort war leer oder hat ein unbekanntes Format.' }

            $parsed = foreach ($e in $entries) {
                if ($e -is [System.Array]) { [pscustomobject]@{ Date = $e[0]; Time = $e[1]; Group = ''; Msg = $e[2] } }
                else { [pscustomobject]@{ Date = $e.date; Time = $e.time; Group = $e.group; Msg = $e.msg } }
            }

            if ($LogStunden -gt 0) {
                $limit  = (Get-Date).AddHours(-$LogStunden)
                $parsed = $parsed | Where-Object {
                    $dt = [datetime]::MinValue
                    [datetime]::TryParseExact("$($_.Date) $($_.Time)", 'dd.MM.yy HH:mm:ss',
                        [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$dt) -and $dt -ge $limit
                }
            }

            $hits = @($parsed | Where-Object { $_.Msg -match $LogPattern })
            Write-Log "Geprüft: $(@($parsed).Count) Log-Einträge"
            $sum.LogTreffer = "$($hits.Count)"
            if ($hits.Count -eq 0) {
                Write-Log 'Es gab KEINE Warnmeldungen/Fehler im Log (nach Schlüsselwort-Filter).' -ForegroundColor Green
            }
            else {
                Write-Log "$($hits.Count) verdächtige Einträge:" -ForegroundColor Yellow
                $hits | ForEach-Object { Write-Log ("  {0} {1}  [{2}]  {3}" -f $_.Date, $_.Time, $_.Group, $_.Msg) }
            }
        }
        catch {
            $problems.Add("Log: $($_.Exception.Message)")
            Write-Log 'Log               : NICHT ABRUFBAR' -ForegroundColor Red
        }

        # --- Nicht abrufbare Parameter ---
        Write-Log "`n--- NICHT ABRUFBARE PARAMETER / FEHLER ---" -ForegroundColor Yellow
        if ($problems.Count -eq 0) { Write-Log 'Alle Parameter konnten abgerufen werden.' -ForegroundColor Green }
        else { $problems | ForEach-Object { Write-Log " - $_" -ForegroundColor Red } }
    }
    finally {
        $http.Dispose()
    }

    if ($problems.Count -gt 0) {
        $sum.Status   = "Teilweise nicht abrufbar"
        $sum.Probleme = $problems -join ' | '
    }
    return [PSCustomObject]$sum
}

# - FRITZBOX ABFRAGEN
$Zusammenfassung = @()

foreach ($Fritz in $FritzListe) {
    Write-Log "`n===== FRITZ!BOX: $Fritz ====="

    $summary = [ordered]@{
        Fritzbox   = $Fritz
        Status     = "OK"
        Modell     = ""
        OS         = ""
        Update     = ""
        Reconnect  = ""
        IPv4       = ""
        Download   = ""
        Upload     = ""
        LogTreffer = ""
        Probleme   = ""
    }

    # -- Vorab-Check: Ping (bei Fehlschlag Rückfrage, ob die Wartung trotzdem versucht werden soll; in der Automatik ohne Rückfrage immer versuchen)
    $pingFehlgeschlagen = $false
    $pingOk = Test-Connection -ComputerName $Fritz -Count 1 -Quiet
    if (-not $pingOk) {
        $pingFehlgeschlagen = $true
        Write-Log "STATUS          : Nicht erreichbar (Ping fehlgeschlagen)" -ForegroundColor Red

        $antwort = if ($Automatik) { 'j' } else { Read-Host "Ping fehlgeschlagen. Wartung für $Fritz trotzdem versuchen? (j/n)" }
        if ($antwort -ne 'j') {
            Write-Log "Wartung für $Fritz wurde nach fehlgeschlagenem Ping übersprungen."
            $summary.Status = "Ping fehlgeschlagen (übersprungen)"
            $Zusammenfassung += [PSCustomObject]$summary
            continue
        }

        Write-Log "Wartung wird trotz fehlgeschlagenem Ping versucht." -ForegroundColor Yellow
    }

    # -- Zugangsdaten (pro Fritz!Box)
    $cred = Get-ZielAnmeldung -Name $Fritz -Meldung "Zugangsdaten für Fritz!Box: $Fritz"
    if (-not $cred) {
        Write-Log "STATUS          : Keine Zugangsdaten eingegeben"
        $summary.Status = "Keine Zugangsdaten"
        if ($pingFehlgeschlagen) { $summary.Probleme = "Ping fehlgeschlagen (Wartung trotzdem versucht)" }
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }

    try {
        $ergebnis = Get-FritzStatus -FritzHost $Fritz -Cred $cred
        if ($pingFehlgeschlagen) {
            $hinweis = "Ping fehlgeschlagen (Wartung trotzdem versucht)"
            $ergebnis.Probleme = if ($ergebnis.Probleme) { "$hinweis | $($ergebnis.Probleme)" } else { $hinweis }
        }
        $Zusammenfassung += $ergebnis
    }
    catch {
        Write-Log "STATUS          : Fehler beim Abfragen der Fritz!Box: $($_.Exception.Message)" -ForegroundColor Red
        $summary.Status = "Fehler beim Abfragen"
        if ($pingFehlgeschlagen) { $summary.Probleme = "Ping fehlgeschlagen (Wartung trotzdem versucht)" }
        $Zusammenfassung += [PSCustomObject]$summary
    }
}


# - ZUSAMMENFASSUNG
Write-Log "`n`n===== ZUSAMMENFASSUNG =====" -ForegroundColor Green

foreach ($s in $Zusammenfassung) {
    Write-Log "`n--- $($s.Fritzbox)  ($($s.Modell)) ---"
    Write-Log "Status      : $($s.Status)"
    if ($s.Modell) {
        Write-Log "FRITZ!OS    : $($s.OS)"
        Write-Log "Update      : $($s.Update)"
        Write-Log "Reconnect   : $($s.Reconnect)"
        Write-Log "Externe IP  : $($s.IPv4)"
        Write-Log "Download    : $($s.Download)"
        Write-Log "Upload      : $($s.Upload)"
        Write-Log "Log-Treffer : $($s.LogTreffer)"
    }
    if ($s.Probleme) { Write-Log "Probleme    : $($s.Probleme)" -ForegroundColor Red }
}

Write-Log "`n`nErgebnisdatei: $AusgabeDatei"

if ($Automatik) {
    # - ERGEBNIS FÜR DIE CHECKLISTE (Haken nur bei belegter Aussage: Firmware = Abruf der Version und ausdrücklich kein Update; Internet = Verbindung "Connected" mit externer IP)
    $ergebnisListe = foreach ($s in $Zusammenfassung) {
        $abgerufen = [bool]$s.Modell
        $pr = [ordered]@{}
        if ($abgerufen) {
            if ($s.OS -and $s.Update -eq 'Nein') { $pr['FirmwareAktuell'] = $true }
            elseif ($s.Update -like 'Ja*') { $pr['FirmwareAktuell'] = $false }
            if ($s.Verbindung) { $pr['InternetOnline'] = (($s.Verbindung -eq 'Connected') -and [bool]$s.IPv4) }
        }
        $teile = @()
        if ($abgerufen) {
            $teile += "$($s.Modell), FRITZ!OS $($s.OS)"
            if ($s.Update) { $teile += "Update: $($s.Update)" }
            if ($s.IPv4) { $teile += "IP $($s.IPv4)" }
            if ($s.Download -or $s.Upload) { $teile += "$($s.Download) / $($s.Upload)" }
            if ($s.Probleme) { $teile += "Probleme: $($s.Probleme)" }
        } else { $teile += [string]$s.Status }
        [pscustomobject]@{
            Ziel       = [string]$s.Fritzbox
            Erreicht   = $abgerufen
            Pruefungen = [pscustomobject]$pr
            Werte      = [pscustomobject]@{ Modell = $s.Modell; FritzOS = $s.OS; Update = $s.Update; Verbindung = $s.Verbindung; Reconnect = $s.Reconnect; ExterneIPv4 = $s.IPv4; Download = $s.Download; Upload = $s.Upload; LogTreffer = $s.LogTreffer }
            Notiz      = ($teile -join '; ')
        }
    }
    Write-WtErgebnis -Skript '08.1-Router_FritzBox' -Ordner $Ausgabepfad -Ergebnisse @($ergebnisListe)
    if (@($ergebnisListe | Where-Object { $_.Erreicht }).Count -eq 0) { exit 1 }
    exit 0
}

Invoke-Item $AusgabeDatei