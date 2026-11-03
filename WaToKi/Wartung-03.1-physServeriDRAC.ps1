#Requires -Version 7.0

# - EINGABEPARAMETER (werden vom NET-COCKPIT, Modul WaToKi, übergeben; ohne Angabe fragt das Skript wie gewohnt)
param(
    [string[]]$Ziel,
    [string]$Ausgabeordner,
    [System.Management.Automation.PSCredential]$Anmeldedaten,
    [hashtable]$AnmeldedatenJeZiel
)

Clear-Host
Write-Host ""
Write-Host "=== Wartung-03.1-physServeriDRAC ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Fragt iDRAC-Hosts per Redfish-API ab (BIOS/Firmware, RAID/Laufwerke, Netzteile, Temperaturen) und schreibt Zusammenfassung + Details in eine gemeinsame Logdatei.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten iDRACs (-Ziel), den Ausgabeordner (-Ausgabeordner) und je iDRAC das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Hat ein iDRAC kein Konto oder schlägt die Anmeldung fehl, fragt das Skript per Anmeldefenster nach (3 Versuche pro iDRAC). Ohne -Ziel wird wie bisher eine Hostliste (C:\Temp\liste-phys_server.txt) verwendet und interaktiv gepflegt.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Netzwerkzugriff (HTTPS) vom ausführenden Rechner zu jedem iDRAC
- Gültige iDRAC-Zugangsdaten für jeden Host (Konto aus dem NET-COCKPIT oder Abfrage pro Host)
- Redfish aktiviert. iDRAC Settings > Services > Redfish > Enabled
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - VERZEICHNIS UND DATEINAME
$LogPath = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Host "→ Verzeichnis $LogPath wird erstellt..."
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}
$Timestamp = (Get-Date).ToString("yyyyMMdd")
$LogFile = Join-Path $LogPath "Wartung_$Timestamp`_physServer.txt"

# - ZIELE BESTIMMEN
$ips = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })

if ($ips.Count -gt 0) {
    Write-Host "`nZu prüfende iDRAC Hosts (aus dem NET-COCKPIT):"
    $ips | ForEach-Object { Write-Host " - $_" }
} else {
    # Hostliste verwalten (nur ohne -Ziel)
    $HostListFile = Join-Path $LogPath "liste-phys_server.txt"
    if (-not (Test-Path -LiteralPath $HostListFile)) {
        Write-Host "→ Hostliste existiert nicht und wird erstellt..."
        Write-Host "IP-Adresse vom iDRAC" -ForegroundColor Yellow
        $ersteHosts = Read-Host "Gib die ersten IPs vom iDRAC ein (durch Komma getrennt)"
        $hosts_init = $ersteHosts -split ",\s*"
        $hosts_init | Out-File -LiteralPath $HostListFile -Encoding utf8
        Write-Host "→ Hostliste wurde erstellt unter $HostListFile"
    }

    Write-Host "`nZu prüfende iDRAC Hosts:"
    Get-Content -LiteralPath $HostListFile | ForEach-Object { Write-Host " - $_" }
    $antwort = Read-Host "`nWillst du weitere iDRAC Hosts hinzufügen? (j/n)"
    if ($antwort -eq "j") {
        $neue = Read-Host "Neue iDRAC IPs (durch Komma getrennt)"
        $neueIps = $neue -split ",\s*"
        Add-Content -LiteralPath $HostListFile -Value $neueIps
        Write-Host "→ Neue iDRAC Hosts wurden hinzugefügt."
    }
    $ips = @(Get-Content -LiteralPath $HostListFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
}

if ($ips.Count -eq 0) {
    Write-Host "→ Keine iDRAC-Adressen vorhanden – Abschnitt wird übersprungen."
    return
}

# - FUNKTIONEN
function Get-RedfishData($uri, $headers) {
    try {
        Invoke-RestMethod -Uri $uri -Headers $headers -SkipCertificateCheck -ErrorAction Stop
    } catch { return $null }
}

function New-RedfishSession($ip, $cred) {
    $body = @{
        UserName = $cred.UserName
        Password = $cred.GetNetworkCredential().Password
    } | ConvertTo-Json

    $uri = "https://$ip/redfish/v1/SessionService/Sessions"
    try {
        $reqHeaders = @{ "Accept" = "application/json" }
        $response = Invoke-WebRequest -Uri $uri -Method Post -Body $body -ContentType "application/json" -Headers $reqHeaders -SkipCertificateCheck -ErrorAction Stop
        $token = $response.Headers["X-Auth-Token"]
        if ($token -is [array]) { $token = $token[0] }
        $location = $response.Headers["Location"]
        if ($location -is [array]) { $location = $location[0] }

        return @{
            Headers  = @{ "X-Auth-Token" = $token; "Accept" = "application/json" }
            Location = $location
        }
    } catch { return $null }
}

function Remove-RedfishSession($location, $headers) {
    if (-not $location) { return }
    try {
        Invoke-RestMethod -Uri $location -Method Delete -Headers $headers -SkipCertificateCheck -ErrorAction Stop | Out-Null
    } catch {}
}

function Test-Health {
    param($value)
    if ($value -and $value -ne "OK") { return "Fehler bitte manuell nachkontrollieren" }
    else { return "OK" }
}

function Test-IdracReachable($ip, $port = 443, $timeoutMs = 2000) {
    for ($versuch = 1; $versuch -le 3; $versuch++) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $result = $client.BeginConnect($ip, $port, $null, $null)
            $success = $result.AsyncWaitHandle.WaitOne($timeoutMs, $false)
            if ($success -and $client.Connected) {
                $client.Close()
                return $true
            }
        } catch {
        } finally {
            $client.Close()
        }
    }
    return $false
}

# - HAUPTAUSFÜHRUNG
$summary = @()
$details = @()

foreach ($ip in $ips) {
    Write-Host "`n→ Prüfe Erreichbarkeit von $ip..."

    if (-not (Test-IdracReachable $ip)) {
        Write-Host "$ip"
        Write-Host "Verbindung fehlgeschlagen"
        continue
    }

    $loginOk = $false
    $session = $null
    $sys = $null

    # Zuerst das Konto dieses Geräts aus dem NET-COCKPIT versuchen (sonst das gemeinsame Konto)
    $hostKonto = $Anmeldedaten
    if ($AnmeldedatenJeZiel -and $AnmeldedatenJeZiel.ContainsKey($ip)) { $hostKonto = $AnmeldedatenJeZiel[$ip] }
    if ($hostKonto) {
        Write-Host "→ Anmeldung mit Konto $($hostKonto.UserName)..."
        $session = New-RedfishSession -ip $ip -cred $hostKonto
        if ($session) {
            $sys = Get-RedfishData "https://$ip/redfish/v1/Systems/System.Embedded.1" $session.Headers
            if ($sys) {
                $loginOk = $true
            } else {
                Remove-RedfishSession -location $session.Location -headers $session.Headers
            }
        }
        if (-not $loginOk) {
            Write-Host "→ Anmeldung mit Konto $($hostKonto.UserName) fehlgeschlagen." -ForegroundColor Yellow
        }
    }

    # Sonst Abfrage per Anmeldefenster (3 Versuche)
    if (-not $loginOk) {
        for ($loginVersuch = 1; $loginVersuch -le 3; $loginVersuch++) {
            $cred = Get-Credential -Message "Zugangsdaten für iDRAC $ip (Versuch $loginVersuch von 3)"
            if (-not $cred) { break }
            $session = New-RedfishSession -ip $ip -cred $cred
            if ($session) {
                $sys = Get-RedfishData "https://$ip/redfish/v1/Systems/System.Embedded.1" $session.Headers
                if ($sys) {
                    $loginOk = $true
                    break
                }
                Remove-RedfishSession -location $session.Location -headers $session.Headers
            }
        }
    }

    if (-not $loginOk) {
        Write-Host "$ip"
        Write-Host "Anmeldung fehlgeschlagen"
        continue
    }

    $headers = $session.Headers

    $power = Get-RedfishData "https://$ip/redfish/v1/Chassis/System.Embedded.1/Power" $headers
    $thermal = Get-RedfishData "https://$ip/redfish/v1/Chassis/System.Embedded.1/Thermal" $headers
    $storage = Get-RedfishData "https://$ip/redfish/v1/Systems/System.Embedded.1/Storage" $headers

    $biosv = $sys.BiosVersion
    $firmv = $sys.FirmwareVersion
    $biosHealth = Test-Health $sys.Status.Health
    $firmHealth = Test-Health $sys.Status.Health

    # RAID-Status prüfen
    $raidStatus = "OK"
    $foundAny = $false

    if ($storage -and $storage.Members) {
        foreach ($m in $storage.Members) {
            $ctrl = Get-RedfishData ("https://$ip" + $m.'@odata.id') $headers
            if ($ctrl) {
                if ($ctrl.Status.Health) {
                    $foundAny = $true
                    if ($ctrl.Status.Health -ne "OK") { $raidStatus = "Fehler bitte manuell nachkontrollieren" }
                }
                if ($ctrl.Drives) {
                    foreach ($dRef in $ctrl.Drives) {
                        $d = Get-RedfishData ("https://$ip" + $dRef.'@odata.id') $headers
                        if ($d -and $d.Status.Health) {
                            $foundAny = $true
                            if ($d.Status.Health -ne "OK") { $raidStatus = "Fehler bitte manuell nachkontrollieren" }
                        }
                    }
                }
            }
        }
    }

    if (-not $foundAny) { $raidStatus = "Fehler bitte manuell nachkontrollieren" }

    # Netzteile prüfen
    $psuStatus = "OK"
    if ($power -and $power.PowerSupplies) {
        foreach ($ps in $power.PowerSupplies) {
            if ($ps.Status.Health -ne "OK") { $psuStatus = "Fehler bitte manuell nachkontrollieren" }
        }
    } else { $psuStatus = "Fehler bitte manuell nachkontrollieren" }

    # Zusammenfassung
    $summary += "$ip"
    $summary += "Raid/HDD: $raidStatus"
    $summary += "Firmware: $firmHealth $firmv"
    $summary += "Bios: $biosHealth $biosv"
    $summary += "Netzteile: $psuStatus`r`n"

    # Detaildaten
    $details += "============================================================="
    $details += "HOST: $ip"
    $details += "-------------------------------------------------------------"
    $details += "BIOS-Version: $biosv"
    $details += "Firmware-Version: $firmv"
    $details += "CPU: $($sys.ProcessorSummary.Model) ($($sys.ProcessorSummary.Count)x)"
    $details += "RAM: $($sys.MemorySummary.TotalSystemMemoryGiB) GB"
    $details += "Gesamt-Health: $($sys.Status.Health)"
    $details += "-------------------------------------------------------------"
    if ($storage -and $storage.Members) {
        $details += "RAID / Laufwerke:"
        foreach ($m in $storage.Members) {
            $ctrl = Get-RedfishData ("https://$ip" + $m.'@odata.id') $headers
            if ($ctrl) {
                $details += " - Controller: $($ctrl.Name) | Status: $($ctrl.Status.Health)"
                if ($ctrl.Drives) {
                    foreach ($dRef in $ctrl.Drives) {
                        $d = Get-RedfishData ("https://$ip" + $dRef.'@odata.id') $headers
                        if ($d) {
                            $size = [math]::Round($d.CapacityBytes / 1GB,2)
                            $details += "   - $($d.Name): $size GB | Status: $($d.Status.Health)"
                        }
                    }
                }
            }
        }
    }
    if ($power -and $power.PowerSupplies) {
        $details += "-------------------------------------------------------------"
        $details += "Netzteile:"
        foreach ($ps in $power.PowerSupplies) {
            $details += " - $($ps.Name) | Modell: $($ps.Model) | Status: $($ps.Status.Health)"
        }
    }
    if ($thermal -and $thermal.Temperatures) {
        $details += "-------------------------------------------------------------"
        $details += "Temperaturen:"
        foreach ($t in $thermal.Temperatures) {
            $details += " - $($t.Name): $($t.ReadingCelsius) °C | Health: $($t.Status.Health)"
        }
    }
    $details += "============================================================="

    Remove-RedfishSession -location $session.Location -headers $headers
}

# - LOGDATEI SCHREIBEN
if ($summary.Count -gt 0) {
    Write-Host "`nLogdatei gespeichert unter: $LogFile" -ForegroundColor Cyan
    @($summary; "============================================================="; $details) | Out-File -LiteralPath $LogFile -Encoding utf8

    # - DATEI ÖFFNEN
    Start-Process notepad.exe $LogFile
} else {
    Write-Host "`nKeine erfolgreiche Abfrage – keine Logdatei erstellt." -ForegroundColor Yellow
}
Write-Host "`nFertig."
