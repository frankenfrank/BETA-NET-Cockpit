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
Write-Host "=== $($MyInvocation.MyCommand.Name) ===" -ForegroundColor Cyan
Write-Host ""

# - VORAUSSETZUNGEN ANZEIGEN
Write-Host @'
BESCHREIBUNG
Fragt QNAP-NAS per SSH Rohstatus ab (Firmware, RAID/mdstat, Speicherplatz, Datenträger/SMART) und schreibt das Ergebnis in eine Datei.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript die markierten NAS (-Ziel), den Ausgabeordner (-Ausgabeordner) und je NAS das Konto der Spalte "Konto" (-AnmeldedatenJeZiel, jedes Gerät mit seinem eigenen Konto). Hat ein NAS kein Konto oder schlägt die Anmeldung fehl, fragt das Skript per Anmeldefenster nach (3 Versuche pro NAS). Ohne -Ziel wird wie bisher eine Liste (C:\Temp\liste-nas-qnap.txt) verwendet und interaktiv gepflegt.

VORAUSSETZUNGEN
- PowerShell 7 auf dem ausführenden Rechner
- Posh-SSH-Modul (wird bei Bedarf automatisch installiert: Install-Module Posh-SSH -Scope CurrentUser -Force)
- SSH-Dienst in der QNAP-Systemsteuerung (Netzwerk & Dateidienste > Telnet/SSH) aktiviert
- Zugangsdaten mit Admin-Rechten auf der QNAP (für qcli-Befehle)
'@ -ForegroundColor Yellow
Write-Host ""
Write-Host "Ausgeführt auf: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abbrechen mit [Strg] und [c], fortfahren mit [Enter] ..." -ForegroundColor Yellow
Read-Host | Out-Null

# - AUSGABEORDNER (aus dem NET-COCKPIT, sonst C:\Temp)
$Ausgabepfad = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $Ausgabepfad)) { New-Item -ItemType Directory -Path $Ausgabepfad -Force | Out-Null }

# - SERVERLISTE
$NASListe = @($Ziel | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne "" })
if ($NASListe.Count -gt 0) {
    Write-Host "`
Zu prüfende NAS (aus dem NET-COCKPIT):"
    $NASListe | ForEach-Object { Write-Host " - $_" }
}
else {
    $ServerListFile = Join-Path $Ausgabepfad "liste-nas-qnap.txt"

    if (-not (Test-Path -LiteralPath $ServerListFile)) {
        (Read-Host "NAS Hostname/IP (Komma getrennt)") -split ",\s*" |
            Out-File -LiteralPath $ServerListFile -Encoding utf8
    }

    Write-Host "`
Zu prüfende NAS:"
    Get-Content -LiteralPath $ServerListFile | ForEach-Object { Write-Host " - $_" }

    if ((Read-Host "`
Weitere NAS hinzufügen? (j/n)") -eq "j") {
        (Read-Host "Neue NAS (Komma getrennt)") -split ",\s*" |
            Add-Content -LiteralPath $ServerListFile
    }

    $NASListe = @(Get-Content -LiteralPath $ServerListFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}
$SSHPort  = 22

# - AUSGABEDATEI
$Datum        = Get-Date -Format "yyyyMMdd"
$Dateiname    = "Wartung_${Datum}_NAS.txt"
$AusgabeDatei = Join-Path $Ausgabepfad $Dateiname
$Kunde        = $null # optional befüllen

# - ALTE DATEI LÖSCHEN
Remove-Item -LiteralPath $AusgabeDatei -ErrorAction SilentlyContinue

Start-Transcript -LiteralPath $AusgabeDatei | Out-Null

# - SSH
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Posh-SSH Modul wird installiert ..." -ForegroundColor Yellow
    Install-Module -Name Posh-SSH -Scope CurrentUser -Force
}
Import-Module Posh-SSH

function ConvertTo-Lines {
    # Posh-SSH liefert Output je nach Laenge mal als String-Array, mal als
    # einzelner mehrzeiliger String -> hier robust auf Zeilen-Array normalisieren
    param ($Output)
    return (($Output -join "`n") -split "`r?`n")
}

function Get-MdBlock {
    param ($Lines, $MdRegex)

    $blocks = @()
    $current = @()
    $collect = $false

    foreach ($line in $Lines) {
        if ($line -match '^md\d+') {
            if ($current.Count -gt 0) {
                $blocks += ,$current
                $current = @()
            }
            $collect = ($line -match $MdRegex)
        }
        if ($collect) {
            $current += $line
        }
    }
    if ($current.Count -gt 0) {
        $blocks += ,$current
    }
    return $blocks
}

$Zusammenfassung = @()

foreach ($NAS in $NASListe) {
    Write-Host "`n===== NAS: $NAS ====="

    $summary = [ordered]@{
        NAS      = $NAS
        Name     = ""
        Status   = "OK"
        Firmware = ""
        Build    = ""
        RAID_md1 = ""
        Speicher = ""
        SMART    = ""
    }

    # --- Vorab-Check: Ping ---
    if (-not (Test-Connection -ComputerName $NAS -Count 1 -Quiet)) {
        Write-Host "STATUS          : Nicht erreichbar (Ping fehlgeschlagen)"
        $summary.Status = "Ping fehlgeschlagen"
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }

    # --- Vorab-Check: SSH-Port ---
    $portCheck = Test-NetConnection -ComputerName $NAS -Port $SSHPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $portCheck) {
        Write-Host "STATUS          : Ping OK, SSH-Port $SSHPort nicht erreichbar"
        $summary.Status = "SSH-Port nicht erreichbar"
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }

    # --- Zugangsdaten (pro NAS): zuerst das Konto dieses Geräts aus dem NET-COCKPIT, sonst Abfrage mit sofortiger Wiederholung bei Fehllogin ---
    $cred = $Anmeldedaten
    if ($AnmeldedatenJeZiel -and $AnmeldedatenJeZiel.ContainsKey($NAS)) { $cred = $AnmeldedatenJeZiel[$NAS] }
    $MaxVersuche = 3
    $sid = $null
    for ($Versuch = 1; $Versuch -le $MaxVersuche; $Versuch++) {
        if ($Versuch -gt 1 -or -not $cred) {
            $cred = Get-Credential -Message "Zugangsdaten fuer NAS: $NAS (Versuch $Versuch/$MaxVersuche)"
        }
        if (-not $cred) { break }
        try {
            $session = New-SSHSession -ComputerName $NAS -Port $SSHPort -Credential $cred -AcceptKey -ErrorAction Stop
            $sid = $session.SessionId
            Write-Host "STATUS          : SSH-Login erfolgreich"
            break
        }
        catch {
            Write-Host "STATUS          : SSH-Login fehlgeschlagen (Versuch $Versuch/$MaxVersuche)"
        }
    }

    if (-not $sid) {
        $summary.Status = "SSH-Login fehlgeschlagen"
        $Zusammenfassung += [PSCustomObject]$summary
        continue
    }

    try {
        $hostnameOut = (Invoke-SSHCommand -SessionId $sid -Command "hostname").Output
        Write-Host ("Name            : {0}" -f $hostnameOut)
        $summary.Name = $hostnameOut

        Write-Host "`n--- FIRMWARE VERSION (RAW) ---"
        $fwOut    = (Invoke-SSHCommand -SessionId $sid -Command "getcfg system version").Output
        $buildOut = (Invoke-SSHCommand -SessionId $sid -Command 'getcfg system "Build Number"').Output
        $fwOut
        Write-Host "Build Number    : $buildOut"
        $summary.Firmware = $fwOut
        $summary.Build    = $buildOut

        Write-Host "`n--- RAID (RAW /proc/mdstat) ---"
        $mdstat = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "cat /proc/mdstat").Output
        $mdstat

        Write-Host "`n--- RAID SYSTEM (md0/md1) ---"
        Get-MdBlock $mdstat '^md[01]\b' | ForEach-Object { $_; "" }

        Write-Host "`n--- RAID DATEN (md2+) ---"
        Get-MdBlock $mdstat '^md[2-9]\b' | ForEach-Object { $_; "" }

        # --- roher RAID-Status md1 (Nutzdaten-Array) auslesen ---
        $mdstatText = $mdstat -join "`n"
        if ($mdstatText -match '(?ms)^md1\s*:.*?\[(?<counts>\d+/\d+)\]\s*\[(?<status>[U_]+)\]') {
            $summary.RAID_md1 = "$($matches['counts']) $($matches['status'])"
        } else {
            $summary.RAID_md1 = "Status nicht auslesbar (md1 nicht gefunden)"
        }

        Write-Host "`n--- SPEICHERPLATZ (RAW df -h) ---"
        $dfRaw = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "df -h").Output
        $dfRaw

        # df -h bricht bei langen Geraetenamen (z.B. /dev/mapper/cachedev1) die Zeile um:
        # Zeile 1 = nur der Geraetename, Zeile 2 (eingerueckt) = Size/Used/Avail/Use%/Mount.
        # Hier werden solche Zeilenpaare wieder zu einer Zeile zusammengefuehrt.
        $dfMerged = @()
        $pending  = $null
        foreach ($line in $dfRaw) {
            if ($line -match '^\S+$') {
                $pending = $line.Trim()
            }
            elseif ($pending -and $line -match '^\s') {
                $dfMerged += ($pending + " " + $line.Trim())
                $pending = $null
            }
            else {
                $dfMerged += $line
            }
        }

        # nur die eigentliche(n) Daten-Freigabe(n), keine tmpfs/.quftp/lock-Mounts
        $shareZeilen = $dfMerged | Where-Object { $_ -match '^/dev/\S+.*\s/share/CACHEDEV\d+_DATA\s*$' }
        $summary.Speicher = if ($shareZeilen) { ($shareZeilen -join ' ; ') } else { "keine CACHEDEV_DATA-Zeile gefunden, siehe Logdatei" }

        Write-Host "`n--- DISK-LISTE (RAW qcli_storage) ---"
        $storageRaw = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "qcli_storage").Output
        $storageRaw

        Write-Host "`n--- DISK HEALTH (RAW qcli_hdd, SMART) ---"
        $plainUser = $cred.UserName
        $plainPw   = $cred.GetNetworkCredential().Password
        Invoke-SSHCommand -SessionId $sid -Command "qcli -l user=$plainUser pw=$plainPw saveauthsid=yes" | Out-Null

        $diskPorts = $storageRaw | ForEach-Object {
            $fields = ($_ -split '\s+')
            if ($fields.Count -gt 1 -and $fields[1] -match '^\d+$') { $fields[1] }
        } | Select-Object -Unique

        $diskStatusListe = @()

        foreach ($port in $diskPorts) {
            $diskId = "{0:D8}" -f [int]$port
            Write-Host "`n==== Disk Port $port (diskID=$diskId) ===="
            $hddOutput = ConvertTo-Lines (Invoke-SSHCommand -SessionId $sid -Command "qcli_hdd -m diskID=$diskId").Output
            $hddOutput
            $hddText = $hddOutput -join "`n"

            # roher Status je Attributzeile (SATA/HDD: AttrID am Zeilenanfang, Status am Zeilenende)
            $statusMatches = [regex]::Matches($hddText, '(?m)^\d+\s+\S.*\s(\S+)\s*$')
            $statusWerte   = $statusMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

            if ($statusWerte) {
                $diskStatusListe += "Port$($port)=$($statusWerte -join '/')"
            } else {
                # NVMe hat keine Status-Spalte, dafuer Critical Warning als Rohwert
                if ($hddText -match '(?m)^Critial Warning\s+(\S+)\s*$' -or $hddText -match '(?m)^Critical Warning\s+(\S+)\s*$') {
                    $diskStatusListe += "Port$($port)(NVMe CritWarning)=$($matches[1])"
                } else {
                    $diskStatusListe += "Port$($port)=Status nicht auslesbar"
                }
            }
        }

        $summary.SMART = $diskStatusListe -join ' | '
    }
    catch {
        Write-Host "STATUS          : Fehler beim Abfragen der NAS-Daten"
        $summary.Status = "Fehler beim Abfragen"
    }
    finally {
        Remove-SSHSession -SessionId $sid | Out-Null
        $Zusammenfassung += [PSCustomObject]$summary
    }
}

Stop-Transcript | Out-Null

Write-Host "`n`n===== ZUSAMMENFASSUNG =====" -ForegroundColor Green

foreach ($s in $Zusammenfassung) {
    Write-Host "`n--- $($s.NAS)  ($($s.Name)) ---"
    Write-Host "Status      : $($s.Status)"
    if ($s.Status -eq "OK") {
        Write-Host "Firmware    : $($s.Firmware)  (Build $($s.Build))"
        Write-Host "RAID (md1)  : $($s.RAID_md1)"
        Write-Host "Speicher    : $($s.Speicher)"
        Write-Host "SMART:"
        ($s.SMART -split '\|') | ForEach-Object { Write-Host "   - $($_.Trim())" }
    }
}

Write-Host "`n`nErgebnisdatei: $AusgabeDatei"
Invoke-Item -LiteralPath $AusgabeDatei