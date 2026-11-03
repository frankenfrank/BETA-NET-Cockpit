# NET-COCKPIT-Modul-WOL.ps1
<#
.SYNOPSIS
    Modul WOL (Wake-on-LAN) für das NET-COCKPIT (Menü Module > WOL)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und wirkt auf die markierten Geräte der Tabelle.
    - Status prüfen (markierte, grüne Geräte): Hersteller und Modell, Wake-on-LAN der Netzwerkkarte (Magic Packet, "Gerät darf den Computer aktivieren"), Schnellstart von Windows und Wake-on-LAN im BIOS (Dell, HP, Lenovo)
    - Tool nachinstallieren: Dell Command | Configure per WinGet auf dem Zielgerät (nur Dell); danach läuft automatisch Status prüfen
    - Schnellstart ausschalten: nur den Schnellstart von Windows, bei jedem Hersteller (Karte und BIOS bleiben unverändert)
    - WOL aktivieren: schaltet Magic Packet der Netzwerkkarte ein, deaktiviert den Schnellstart und setzt Wake-on-LAN im BIOS, soweit möglich
    - Aufwecken: sendet ein Magic Packet an die MAC-Adresse der markierten Geräte (kein WinRM nötig)
    Verbindung, Konten und Warteschlange kommen aus dem NET-COCKPIT.
    BIOS: Dell über cctk.exe (Dell Command | Configure), HP und Lenovo über WMI. HP und Lenovo sind noch nicht an echten Geräten getestet.
#>

# Einstellungen
## Zustand
$script:WolFenster = $null

## Spalten (nur sichtbar, solange das Modulfenster offen ist)
New-WolSpalte -Key 'WolGeraet' -Titel 'Gerät (BIOS-Angabe)' -Eig '[WolGeraet]' -Breite 200 -Sichtbar $false -Modul 'WOL'
New-WolSpalte -Key 'WolKarte' -Titel 'WoL Netzwerkkarte' -Eig '[WolKarte]' -Breite 200 -Sichtbar $false -Modul 'WOL'
New-WolSpalte -Key 'WolSchnellstart' -Titel 'Schnellstart' -Eig '[WolSchnellstart]' -Breite 90 -Sichtbar $false -Modul 'WOL'
New-WolSpalte -Key 'WolBios' -Titel 'WoL im BIOS' -Eig '[WolBios]' -Breite 220 -Sichtbar $false -Modul 'WOL'

# Skript auf dem Zielgerät
## Läuft per WinRM auf dem Zielgerät (Windows PowerShell 5.1); mit $Aendern = $true werden die Einstellungen gesetzt, danach wird der Stand neu gelesen und als JSON zurückgegeben
$script:WolZielText = @'
param([bool]$Aendern, [string]$Ip, [bool]$NurSchnellstart = $false)
$ErrorActionPreference = 'Stop'
$meldungen = New-Object System.Collections.Generic.List[string]
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
$hersteller = ([string]$cs.Manufacturer).Trim()
$modell = ([string]$cs.Model).Trim()
### Nur Schnellstart: Karte und BIOS bleiben unverändert
$aendernSchnellstart = $Aendern
if ($NurSchnellstart) { $Aendern = $false }

### Netzwerkkarte: die physische Karte mit der Geräte-IP, sonst alle aktiven physischen Karten
$karten = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
$konf = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $Ip -ErrorAction SilentlyContinue | Select-Object -First 1
if ($konf) {
    $eigene = @($karten | Where-Object { $_.InterfaceIndex -eq $konf.InterfaceIndex })
    if ($eigene.Count -gt 0) { $karten = $eigene }
}

function Get-WeckenEintrag($karte) {
    try {
        return (Get-CimInstance -Namespace 'root\wmi' -ClassName MSPower_DeviceWakeEnable -ErrorAction Stop | Where-Object { $_.InstanceName -like ($karte.PnPDeviceID + '*') } | Select-Object -First 1)
    }
    catch { return $null }
}

function Get-KartenStand {
    $liste = @()
    foreach ($k in $karten) {
        $pm = Get-NetAdapterPowerManagement -Name $k.Name -ErrorAction SilentlyContinue
        $wake = $null
        $w = Get-WeckenEintrag $k
        if ($w) { $wake = [bool]$w.Enable }
        $liste += [pscustomobject]@{ Name = [string]$k.Name; Magic = [string]$pm.WakeOnMagicPacket; Pattern = [string]$pm.WakeOnPattern; Wake = $wake }
    }
    return $liste
}

if ($Aendern) {
    foreach ($k in $karten) {
        try {
            Enable-NetAdapterPowerManagement -Name $k.Name -WakeOnMagicPacket -NoRestart -ErrorAction Stop
            $meldungen.Add("Karte $($k.Name): Magic Packet aktiviert")
        }
        catch { $meldungen.Add("Karte $($k.Name): Magic Packet nicht setzbar ($($_.Exception.Message))") }
        try {
            $w = Get-WeckenEintrag $k
            if ($w -and -not $w.Enable) {
                $w.Enable = $true
                Set-CimInstance -InputObject $w
                $meldungen.Add("Karte $($k.Name): Gerät darf den Computer aktivieren")
            }
        }
        catch { $meldungen.Add("Karte $($k.Name): 'Gerät darf den Computer aktivieren' nicht setzbar ($($_.Exception.Message))") }
    }
}

### Schnellstart (fehlt der Wert, gilt er als aus)
$regPfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
function Get-SchnellstartStand {
    $v = (Get-ItemProperty -Path $regPfad -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($null -ne $v -and [int]$v -ne 0) { return 'An' }
    return 'Aus'
}
if ($aendernSchnellstart -and (Get-SchnellstartStand) -eq 'An') {
    Set-ItemProperty -Path $regPfad -Name HiberbootEnabled -Value 0 -Type DWord
    $meldungen.Add('Schnellstart deaktiviert')
}

### BIOS: Art, Status (An, Aus, ToolFehlt, NichtUnterstuetzt, Unbekannt, Fehler) und Wert
$biosArt = ''
$biosStatus = 'NichtUnterstuetzt'
$biosWert = ''

if ($hersteller -match 'Dell') {
    $biosArt = 'Dell'
    $cctk = $null
    foreach ($p in 'C:\Program Files\Dell\Command Configure\X86_64\cctk.exe', 'C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe', 'C:\Program Files (x86)\Dell\Command Configure\X86\cctk.exe') {
        if (Test-Path -LiteralPath $p) { $cctk = $p; break }
    }
    if (-not $cctk) { $biosStatus = 'ToolFehlt' }
    else {
        function Get-DellWol {
            $t = (& $cctk '--wakeonlan' 2>&1 | Out-String).Trim()
            if ($t -match 'wakeonlan\s*=\s*(\S+)') { return $Matches[1] }
            return $t
        }
        try {
            $biosWert = Get-DellWol
            if ($Aendern -and $biosWert -match 'disable') {
                $gesetzt = $false
                foreach ($v in 'lanonly', 'lanwlan', 'enable') {
                    & $cctk "--wakeonlan=$v" 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) { $gesetzt = $true; $meldungen.Add("BIOS (Dell): wakeonlan=$v gesetzt"); break }
                }
                if (-not $gesetzt) { $meldungen.Add('BIOS (Dell): wakeonlan konnte nicht gesetzt werden (BIOS-Kennwort? Option auf diesem Modell anders benannt?)') }
                $biosWert = Get-DellWol
            }
            if ($biosWert -match 'disable') { $biosStatus = 'Aus' }
            elseif ($biosWert -match 'lan|enable') { $biosStatus = 'An' }
            else { $biosStatus = 'Unbekannt' }
        }
        catch { $biosStatus = 'Fehler'; $biosWert = $_.Exception.Message }
    }
}
elseif ($hersteller -match '^(HP|Hewlett)') {
    $biosArt = 'HP'
    try {
        $hpNamen = 'root\HP\InstrumentedBIOS'
        function Get-HpWol { return @(Get-CimInstance -Namespace $hpNamen -ClassName HP_BIOSEnumeration -ErrorAction Stop | Where-Object { $_.Name -match 'Wake\s*On\s*LAN' }) }
        $hp = Get-HpWol
        if ($hp.Count -eq 0) { $biosStatus = 'NichtUnterstuetzt'; $meldungen.Add('BIOS (HP): keine Einstellung "Wake On LAN" gefunden') }
        else {
            if ($Aendern) {
                $schnittstelle = Get-CimInstance -Namespace $hpNamen -ClassName HP_BIOSSettingInterface -ErrorAction Stop | Select-Object -First 1
                foreach ($s in @($hp | Where-Object { $_.CurrentValue -match 'Disable' })) {
                    $moeglich = @($s.PossibleValues | ForEach-Object { [string]$_ })
                    $wert = $null
                    foreach ($bevorzugt in 'Boot to Hard Drive', 'Boot to Network', 'Enable', 'Enabled') { if ($moeglich -contains $bevorzugt) { $wert = $bevorzugt; break } }
                    if (-not $wert) { $wert = $moeglich | Where-Object { $_ -notmatch 'Disable' } | Select-Object -First 1 }
                    if (-not $wert) { $meldungen.Add("BIOS (HP): kein Wert zum Aktivieren für '$($s.Name)' gefunden"); continue }
                    $r = Invoke-CimMethod -InputObject $schnittstelle -MethodName SetBIOSSetting -Arguments @{ Name = [string]$s.Name; Value = [string]$wert; Password = '' }
                    if ($r.Return -eq 0) { $meldungen.Add("BIOS (HP): '$($s.Name)' auf '$wert' gesetzt") }
                    else { $meldungen.Add("BIOS (HP): '$($s.Name)' nicht gesetzt (Rückgabewert $($r.Return), BIOS-Kennwort?)") }
                }
                $hp = Get-HpWol
            }
            $biosWert = (@($hp | ForEach-Object { '{0}: {1}' -f $_.Name, $_.CurrentValue })) -join '; '
            if (@($hp | Where-Object { $_.CurrentValue -match 'Disable' }).Count -gt 0) { $biosStatus = 'Aus' } else { $biosStatus = 'An' }
        }
    }
    catch { $biosStatus = 'Fehler'; $biosWert = $_.Exception.Message }
}
elseif ($hersteller -match 'LENOVO') {
    $biosArt = 'Lenovo'
    try {
        function Get-LenovoWol {
            return @(Get-CimInstance -Namespace 'root\wmi' -ClassName Lenovo_BiosSetting -ErrorAction Stop | Where-Object { $_.CurrentSetting -match '^Wake\s*On\s*LAN' })
        }
        $le = Get-LenovoWol
        if ($le.Count -eq 0) { $biosStatus = 'NichtUnterstuetzt'; $meldungen.Add('BIOS (Lenovo): keine Einstellung "Wake On LAN" gefunden') }
        else {
            if ($Aendern) {
                $setzen = Get-CimInstance -Namespace 'root\wmi' -ClassName Lenovo_SetBiosSetting -ErrorAction Stop | Select-Object -First 1
                $speichern = Get-CimInstance -Namespace 'root\wmi' -ClassName Lenovo_SaveBiosSettings -ErrorAction Stop | Select-Object -First 1
                $geaendert = $false
                foreach ($s in @($le | Where-Object { ($_.CurrentSetting -split ';')[0] -match 'Disable' })) {
                    $teile = ($s.CurrentSetting -split ';')[0] -split ','
                    $moeglich = @()
                    if ($s.CurrentSetting -match '\[Optional:([^\]]*)\]') { $moeglich = @($Matches[1] -split ',') }
                    $wert = $null
                    foreach ($bevorzugt in 'Automatic', 'Primary', 'ACandBattery', 'ACOnly', 'Enable', 'Enabled') { if ($moeglich -contains $bevorzugt) { $wert = $bevorzugt; break } }
                    if (-not $wert -and $moeglich.Count -eq 0) { $wert = 'Enable' }
                    if (-not $wert) { $meldungen.Add("BIOS (Lenovo): kein Wert zum Aktivieren für '$($teile[0])' gefunden"); continue }
                    $r = Invoke-CimMethod -InputObject $setzen -MethodName SetBiosSetting -Arguments @{ parameter = ('{0},{1}' -f $teile[0], $wert) }
                    if ([string]$r.return -eq 'Success') { $geaendert = $true; $meldungen.Add("BIOS (Lenovo): '$($teile[0])' auf '$wert' gesetzt") }
                    else { $meldungen.Add("BIOS (Lenovo): '$($teile[0])' nicht gesetzt (Antwort: $($r.return))") }
                }
                if ($geaendert) {
                    $r = Invoke-CimMethod -InputObject $speichern -MethodName SaveBiosSettings -Arguments @{ parameter = '' }
                    if ([string]$r.return -ne 'Success') { $meldungen.Add("BIOS (Lenovo): Speichern meldet: $($r.return)") }
                }
                $le = Get-LenovoWol
            }
            $biosWert = (@($le | ForEach-Object { ($_.CurrentSetting -split ';')[0] })) -join '; '
            if (@($le | Where-Object { ($_.CurrentSetting -split ';')[0] -match 'Disable' }).Count -gt 0) { $biosStatus = 'Aus' } else { $biosStatus = 'An' }
        }
    }
    catch { $biosStatus = 'Fehler'; $biosWert = $_.Exception.Message }
}

[pscustomobject]@{
    Hersteller   = $hersteller
    Modell       = $modell
    Karten       = @(Get-KartenStand)
    Schnellstart = (Get-SchnellstartStand)
    BiosArt      = $biosArt
    BiosStatus   = $biosStatus
    BiosWert     = $biosWert
    Meldungen    = @($meldungen)
} | ConvertTo-Json -Depth 5 -Compress
'@

## Aufgabe auf dem Zielgerät (PowerShell 7, als SYSTEM): Dell Command | Configure per WinGet installieren
$script:WolToolSkript = @'
$log = 'C:\Windows\Temp\WaToKiWolTool.log'
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    Add-Content -Path $log -Encoding utf8 -Value 'Installiere Dell.CommandConfigure'
    $r = @(Install-WinGetPackage -Id 'Dell.CommandConfigure' -Source winget -Mode Silent -ErrorAction Stop)[0]
    Add-Content -Path $log -Encoding utf8 -Value ("  Ergebnis: {0}, Neustart nötig: {1}, Installer-Code: {2}" -f $r.Status, $r.RebootRequired, $r.InstallerErrorCode)
    if ($r.Status -ne 'Ok') { exit 1 }
}
catch {
    Add-Content -Path $log -Encoding utf8 -Value ("  Fehler: {0}" -f $_.Exception.Message)
    exit 1
}
'@

# Job je Gerät
## Läuft als Thread-Job (Warteschlange des NET-COCKPIT); Aktion: Status, Aktivieren oder Tool
$script:WolBlock = {
    param([string]$Ziel, [string]$Aktion, $Anmeldedaten, [string]$Ip, [string]$ZielText, [string]$ToolSkript, [string]$TaskCode)
    $ProgressPreference = 'SilentlyContinue'
    $meldungen = [System.Collections.Generic.List[string]]::new()
    try {
        $ic = @{ ComputerName = $Ziel; ErrorAction = 'Stop' }
        if ($Anmeldedaten) { $ic.Credential = $Anmeldedaten }

        ### Dell Command | Configure per WinGet nachinstallieren
        if ($Aktion -eq 'Tool') {
            . ([scriptblock]::Create($TaskCode))
            $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
            $pruefen = {
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem
                $cctk = $false
                foreach ($p in 'C:\Program Files\Dell\Command Configure\X86_64\cctk.exe', 'C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe', 'C:\Program Files (x86)\Dell\Command Configure\X86\cctk.exe') {
                    if (Test-Path -LiteralPath $p) { $cctk = $true }
                }
                $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
                $ps7 = Test-Path -LiteralPath $pwsh
                $modul = $false
                if ($ps7) {
                    $befehl = '[bool](Get-Module -ListAvailable -Name Microsoft.WinGet.Client)'
                    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($befehl))
                    $modul = ((& $pwsh -NoProfile -NonInteractive -EncodedCommand $enc 2>$null | Out-String).Trim() -eq 'True')
                }
                [pscustomobject]@{ Hersteller = [string]$cs.Manufacturer; Cctk = $cctk; PS7 = $ps7; Modul = $modul }
            }
            $info = Invoke-Command @ic -ScriptBlock $pruefen
            if ($info.Hersteller -notmatch 'Dell') {
                return [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = 'Kein Dell-Gerät, nichts zu installieren'; Meldungen = @(); Daten = $null }
            }
            if ($info.Cctk) {
                return [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = 'Dell Command | Configure ist schon installiert'; Meldungen = @(); Daten = $null }
            }
            if (-not ($info.PS7 -and $info.Modul)) {
                return [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = 'PowerShell 7 oder WinGet-Modul fehlt (APP-Modul: WinGet-Modul nachinstallieren)'; Meldungen = @(); Daten = $null }
            }
            $name = 'WaToKiWolTool'
            $andere = @(Get-WolZielAnderesTool -Ic $ic -Eigene 'WaToKiWol*')
            if ($andere.Count -gt 0) {
                return [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = 'Anderes WaToKi-Tool läuft auf dem Gerät'; Meldungen = @(); Daten = $null }
            }
            $aufraeumen = $true
            try {
                $null = Remove-WolZielTask -Ic $ic -Name $name
                $null = Start-WolZielTask -Ic $ic -Name $name -Skript $ToolSkript -Programm $pwsh
                $meldungen.Add('Installation gestartet (lokale Aufgabe auf dem Gerät)')
                Start-Sleep -Seconds 5
                $zeile = { param($t) if ($t.Trim()) { $meldungen.Add($t.TrimEnd()) } }
                $w = Wait-WolZielTask -Ic $ic -Name $name -PauseSek 10 -MaxMinuten 20 -Zeile $zeile
                if ($w.Ergebnis -eq 'Verloren') {
                    $aufraeumen = $false
                    return [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = 'Verbindung verloren, Installation läuft evtl. weiter'; Meldungen = @($meldungen); Daten = $null }
                }
                if ($w.Ergebnis -eq 'Zeit') {
                    return [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = 'Installation: Zeitüberschreitung (20 Min)'; Meldungen = @($meldungen); Daten = $null }
                }
            }
            finally {
                if ($aufraeumen) { try { $null = Remove-WolZielTask -Ic $ic -Name $name } catch { } }
            }
            $nachher = Invoke-Command @ic -ScriptBlock $pruefen
            $status = if ($nachher.Cctk) { 'Dell Command | Configure installiert' } else { 'Installation fehlgeschlagen (siehe Log)' }
            return [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = $status; Meldungen = @($meldungen); Daten = $null }
        }

        ### Status prüfen oder Aktivieren
        $aendern = ($Aktion -in 'Aktivieren', 'Schnellstart')
        $nurSchnell = ($Aktion -eq 'Schnellstart')
        $roh = @(Invoke-Command @ic -ScriptBlock ([scriptblock]::Create($ZielText)) -ArgumentList $aendern, $Ip, $nurSchnell)
        $json = [string]($roh | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        if (-not $json) { throw 'keine Rückmeldung vom Zielgerät' }
        $d = $json | ConvertFrom-Json
        [pscustomobject]@{ Erfolg = $true; Fehler = ''; Status = ''; Meldungen = @($d.Meldungen); Daten = $d }
    }
    catch {
        [pscustomobject]@{ Erfolg = $false; Fehler = $_.Exception.Message; Status = ''; Meldungen = @(); Daten = $null }
    }
}

# Anzeige
## Textform der Werte für die Spalten
function script:Get-WolWolTexte {
    param($D)
    $karten = @($D.Karten | Where-Object { $_ })
    if ($karten.Count -eq 0) { $kartenText = 'keine aktive Karte gefunden' }
    else {
        $magicAn = @($karten | Where-Object { $_.Magic -eq 'Enabled' }).Count
        $nichtUnterstuetzt = @($karten | Where-Object { $_.Magic -eq 'Unsupported' -or -not $_.Magic }).Count
        $magic = if ($magicAn -eq $karten.Count) { 'Magic Packet Ein' } elseif ($nichtUnterstuetzt -eq $karten.Count) { 'Magic Packet nicht unterstützt' } else { 'Magic Packet Aus' }
        $wakeWerte = @($karten | Where-Object { $null -ne $_.Wake })
        $kartenText = $magic
        if ($wakeWerte.Count -gt 0) {
            $kartenText += $(if (@($wakeWerte | Where-Object { -not $_.Wake }).Count -eq 0) { ', Gerät weckt Ein' } else { ', Gerät weckt Aus' })
        }
    }
    $biosText = switch ([string]$D.BiosStatus) {
        'An' { '{0}: Ein ({1})' -f $D.BiosArt, $D.BiosWert }
        'Aus' { '{0}: Aus ({1})' -f $D.BiosArt, $D.BiosWert }
        'ToolFehlt' { 'Dell: Tool fehlt' }
        'Unbekannt' { '{0}: {1}' -f $D.BiosArt, $D.BiosWert }
        'Fehler' { '{0}: Fehler ({1})' -f $D.BiosArt, $D.BiosWert }
        default { 'Hersteller nicht unterstützt' }
    }
    return [pscustomobject]@{ Karte = $kartenText; Bios = $biosText }
}

## Ergebnis in einem Satz: bereit oder was fehlt
function script:Get-WolWolFazit {
    param($D)
    $probleme = [System.Collections.Generic.List[string]]::new()
    $karten = @($D.Karten | Where-Object { $_ })
    if ($karten.Count -eq 0) { $probleme.Add('keine Netzwerkkarte gefunden') }
    elseif (@($karten | Where-Object { $_.Magic -ne 'Enabled' }).Count -gt 0) { $probleme.Add('Karte: Magic Packet aus') }
    if (@($karten | Where-Object { $null -ne $_.Wake -and -not $_.Wake }).Count -gt 0) { $probleme.Add('Karte: darf nicht aktivieren') }
    if ([string]$D.Schnellstart -eq 'An') { $probleme.Add('Schnellstart an') }
    switch ([string]$D.BiosStatus) {
        'Aus' { $probleme.Add('BIOS: WoL aus') }
        'ToolFehlt' { $probleme.Add('BIOS: Tool fehlt') }
        'Fehler' { $probleme.Add('BIOS: Fehler') }
        'Unbekannt' { $probleme.Add('BIOS: Wert unklar') }
    }
    if ($probleme.Count -eq 0) { return 'WoL bereit' }
    return 'WoL nicht vollständig: ' + ($probleme -join ', ')
}

## Werte in die Zeile übernehmen
function script:Update-WolWolZeile {
    param($Zeile, $D)
    $texte = Get-WolWolTexte -D $D
    $Zeile['WolGeraet'] = ('{0} {1}' -f $D.Hersteller, $D.Modell).Trim()
    $Zeile['WolKarte'] = [string]$texte.Karte
    $Zeile['WolSchnellstart'] = [string]$D.Schnellstart
    $Zeile['WolBios'] = [string]$texte.Bios
}

# Aufträge
## Auswertung eines Auftrags (läuft im Poll-Takt des NET-COCKPIT)
$script:WolFertig = {
    param($a)
    $z = $a.Zeile
    $name = $a.Daten.Name
    $fehler = ''
    $erg = $null
    try {
        $erg = @(Receive-Job -Job $a.Job -ErrorAction Stop) | Select-Object -Last 1
        if (-not $erg) { $fehler = 'keine Rückmeldung vom Zielgerät' }
        elseif (-not $erg.Erfolg) { $fehler = [string]$erg.Fehler }
    }
    catch { $fehler = $_.Exception.Message }
    if ($fehler) {
        $kurz = Register-WolVerbindungsfehler -Zeile $z -Text $fehler
        $z.Status = "WOL fehlgeschlagen: $kurz"
        Write-WolLog "WOL fehlgeschlagen: $name - $kurz"
        Write-WolLog "WOL-Fehlertext ${name}: $fehler" -NurDatei
        return
    }
    foreach ($m in @($erg.Meldungen)) { if ($m) { Write-WolLog "WOL ${name}: $m" } }
    if ($erg.Daten) {
        Update-WolWolZeile -Zeile $z -D $erg.Daten
        Save-WolWerteZeile -Zeile $z -Neu
        $fazit = Get-WolWolFazit -D $erg.Daten
        if ($a.Daten.Aktion -eq 'Aktivieren') { $z.Status = "Aktiviert: $fazit" }
        elseif ($a.Daten.Aktion -eq 'Schnellstart') { $z.Status = $(if ([string]$erg.Daten.Schnellstart -eq 'Aus') { 'Schnellstart ist aus' } else { 'Schnellstart konnte nicht ausgeschaltet werden' }) }
        else { $z.Status = $fazit }
    }
    else { $z.Status = [string]$erg.Status }
    Write-WolLog "WOL ${name}: $($z.Status)"

    ### Nach erfolgreicher Tool-Installation gleich den Status prüfen
    if ($a.Daten.Aktion -eq 'Tool' -and $z.Status -eq 'Dell Command | Configure installiert') {
        Start-WolWolAktion -Aktion 'Status' -Ziele @($z)
    }
}

## Aktion für Geräte in die Warteschlange des NET-COCKPIT legen (nur grüne Geräte)
function script:Start-WolWolAktion {
    param([string]$Aktion, $Ziele)
    $Ziele = @($Ziele)
    $gruen = @($Ziele | Where-Object { $_.Ampel -eq 'Gruen' })
    foreach ($z in @($Ziele | Where-Object { $_.Ampel -ne 'Gruen' })) { $z.Status = 'WinRM nicht erreichbar - übersprungen' }
    if ($gruen.Count -eq 0) { Show-WolMeldung 'Keines der Geräte ist grün (WinRM erreichbar).'; return }
    if (-not (Resolve-WolKonten -Zeilen $gruen)) { return }
    $text = switch ($Aktion) { 'Aktivieren' { 'WOL wird aktiviert...' } 'Schnellstart' { 'Schnellstart wird ausgeschaltet...' } 'Tool' { 'Dell Command | Configure wird installiert...' } default { 'WOL-Status wird geprüft...' } }
    $gestartet = 0
    foreach ($z in $gruen) {
        if ((Get-WolGruppeOffen -Gruppe 'WOL' -Zeile $z) -gt 0) { continue }
        try { $konto = Get-WolAnmeldung -Zeile $z }
        catch { $z.Status = $_.Exception.Message; continue }
        $name = $(if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { [string]$z.IP })
        Add-WolAuftrag -Zeile $z -Block $script:WolBlock -Argumente @((Get-WolZielName -Zeile $z), $Aktion, $konto, [string]$z.IP, $script:WolZielText, $script:WolToolSkript, $script:ZielTaskCode) -Fertig $script:WolFertig -Gruppe 'WOL' -Daten @{ Name = $name; Aktion = $Aktion } -Starttext $text
        $gestartet++
    }
    if ($gestartet -eq 0) { Write-WolLog 'WOL: Auf den Geräten läuft schon eine Aktion des Moduls'; return }
    Write-WolLog "WOL ${Aktion}: $gestartet Gerät(e)"
}

# Aktionen des Moduls
## Markierte Geräte holen (mit Hinweis, wenn keins markiert ist)
function script:Get-WolWolZiele {
    $ziele = @(Get-WolMarkierte)
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return $null }
    return , $ziele
}

## Namen der Geräte für Texte (Hostname, sonst IP)
function script:Get-WolWolNamen {
    param($Zeilen)
    return (@($Zeilen | ForEach-Object { if ($_.Hostname) { ([string]$_.Hostname).Split('.')[0] } else { [string]$_.IP } }) -join ', ')
}

## Status prüfen
function script:Start-WolWolStatus {
    $ziele = Get-WolWolZiele
    if ($ziele) { Start-WolWolAktion -Aktion 'Status' -Ziele $ziele }
}

## Dell Command | Configure nachinstallieren
function script:Start-WolWolTool {
    $ziele = Get-WolWolZiele
    if (-not $ziele) { return }
    $namen = Get-WolWolNamen -Zeilen $ziele
    $frage = "Dell Command | Configure per WinGet auf diesen Geräten installieren?`r`n`r`n$($namen -replace ', ', "`r`n")`r`n`r`nNur Dell-Geräte ohne das Tool werden bearbeitet. Voraussetzung: PowerShell 7 und das WinGet-Modul auf dem Gerät (APP-Modul > WinGet-Modul nachinstallieren) und Internetzugang."
    if ([System.Windows.MessageBox]::Show($frage, 'Tool nachinstallieren', 'YesNo', 'Question') -eq 'Yes') {
        Start-WolWolAktion -Aktion 'Tool' -Ziele $ziele
    }
}

## WOL aktivieren (Netzwerkkarte, Schnellstart, BIOS)
function script:Start-WolWolAktivieren {
    $ziele = Get-WolWolZiele
    if (-not $ziele) { return }
    $namen = Get-WolWolNamen -Zeilen $ziele
    $frage = "Wake-on-LAN auf diesen Geräten aktivieren?`r`n`r`n$($namen -replace ', ', "`r`n")`r`n`r`n1. Netzwerkkarte: Magic Packet und 'Gerät darf den Computer aktivieren' einschalten`r`n2. Windows: Schnellstart ausschalten`r`n3. BIOS: Wake-on-LAN einschalten (Dell mit Dell Command | Configure, HP und Lenovo per WMI), soweit möglich`r`n`r`nDie Netzwerkkarte wird dabei nicht neu gestartet."
    if ([System.Windows.MessageBox]::Show($frage, 'WOL aktivieren', 'YesNo', 'Question') -eq 'Yes') {
        Start-WolWolAktion -Aktion 'Aktivieren' -Ziele $ziele
    }
}

## Schnellstart ausschalten (bei jedem Hersteller, Karte und BIOS bleiben unverändert)
function script:Start-WolWolSchnellstart {
    $ziele = Get-WolWolZiele
    if (-not $ziele) { return }
    $namen = Get-WolWolNamen -Zeilen $ziele
    $frage = "Den Schnellstart von Windows auf diesen Geräten ausschalten?`r`n`r`n$($namen -replace ', ', "`r`n")`r`n`r`nNetzwerkkarte und BIOS bleiben unverändert. Das geht bei jedem Hersteller."
    if ([System.Windows.MessageBox]::Show($frage, 'Schnellstart ausschalten', 'YesNo', 'Question') -eq 'Yes') {
        Start-WolWolAktion -Aktion 'Schnellstart' -Ziele $ziele
    }
}

## Aufwecken: Magic Packet an die MAC der markierten Geräte (kein WinRM nötig)
function script:Start-WolWolAufwecken {
    $ziele = Get-WolWolZiele
    if (-not $ziele) { return }
    foreach ($z in $ziele) {
        if (-not $z.MAC) { $z.Status = 'Keine MAC-Adresse bekannt'; continue }
        $broadcast = $null
        if ($z.Subnetz) {
            $n = Get-WolNetzInfo -Cidr $z.Subnetz
            if ($n) { $broadcast = $n.Broadcast }
        }
        try {
            Send-WolPaket -Mac $z.MAC -Broadcast $broadcast
            $z.Status = 'Magic Packet gesendet ({0:HH:mm:ss})' -f (Get-Date)
            Write-WolLog "Aufwecken: $($z.Hostname) $($z.IP) $($z.MAC)"
        }
        catch { $z.Status = "Fehler: $($_.Exception.Message)" }
    }
}

# Fenster des Moduls
## Wird vom Menü Module > WOL aufgerufen: kleines Fenster neben der Tabelle (bleibt offen, die Tabelle bleibt bedienbar)
function script:Show-WolModulWOL {
    if ($script:WolFenster) {
        $script:WolFenster.Activate()
        Set-WolModulOffen -Key 'WOL' -Offen $true
        return
    }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WOL" Width="400" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Wirkt auf die markierten Geräte der Tabelle. Status, Tool und Aktivieren brauchen WinRM (grüne Geräte), Aufwecken nur die MAC-Adresse." TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,12"/>
    <Button x:Name="BtnStatus" Content="Status prüfen" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Zeigt Hersteller und Modell, Wake-on-LAN der Netzwerkkarte, Schnellstart und Wake-on-LAN im BIOS (Dell, HP, Lenovo)"/>
    <Button x:Name="BtnTool" Content="Tool nachinstallieren (Dell)" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Installiert Dell Command | Configure per WinGet auf Dell-Geräten, auf denen es fehlt"/>
    <Button x:Name="BtnAktivieren" Content="WOL aktivieren" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Schaltet Magic Packet der Netzwerkkarte ein, deaktiviert den Schnellstart und setzt Wake-on-LAN im BIOS, soweit möglich"/>
    <Button x:Name="BtnSchnellstart" Content="Schnellstart ausschalten" Padding="10,5" Margin="0,0,0,6"
            ToolTip="Schaltet nur den Schnellstart von Windows aus (bei jedem Hersteller), Netzwerkkarte und BIOS bleiben unverändert"/>
    <Button x:Name="BtnAufwecken" Content="Aufwecken" FontWeight="Bold" Padding="10,5" Margin="0,8,0,6"
            ToolTip="Sendet ein Magic Packet an die MAC-Adresse der markierten Geräte"/>
    <Button x:Name="BtnSchliessen" Content="Schließen" Padding="10,5" Margin="0,8,0,0"/>
  </StackPanel>
</Window>
'@
    $f.Owner = $script:Fenster
    $f.FindName('BtnStatus').Add_Click({ Start-WolWolStatus })
    $f.FindName('BtnTool').Add_Click({ Start-WolWolTool })
    $f.FindName('BtnAktivieren').Add_Click({ Start-WolWolAktivieren })
    $f.FindName('BtnSchnellstart').Add_Click({ Start-WolWolSchnellstart })
    $f.FindName('BtnAufwecken').Add_Click({ Start-WolWolAufwecken })
    $f.FindName('BtnSchliessen').Add_Click({ $script:WolFenster.Close() })
    $f.Add_Closed({ Set-WolModulOffen -Key 'WOL' -Offen $false; $script:WolFenster = $null })
    $script:WolFenster = $f
    $f.Show()
    Set-WolModulOffen -Key 'WOL' -Offen $true
}

# Info
## Reiter für die Info des NET-COCKPIT (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['WOL'] = {
    @{ Titel = 'WOL'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Prüft und richtet **Wake-on-LAN** auf den markierten Geräten ein und weckt Geräte auf. Das Fenster öffnet sich über **Module > WOL** und bleibt neben der Tabelle offen. Die Einrichtung braucht man pro Gerät nur einmal.' }
        @{ T = 'h'; X = 'Voraussetzungen' }
        @{ T = 'i'; X = '**Status, Tool und Aktivieren:** WinRM (TCP 5985), ein Konto mit Administratorrechten auf dem Zielgerät, Gerät grün.' }
        @{ T = 'i'; X = '**Aufwecken:** nur die MAC-Adresse in der Tabelle, kein WinRM.' }
        @{ T = 'h'; X = 'Knöpfe' }
        @{ T = 'i'; X = '**Status prüfen:** Hersteller und Modell, Magic Packet der Netzwerkkarte, "Gerät darf den Computer aktivieren", Schnellstart und Wake-on-LAN im BIOS. Die Zeile zeigt am Ende, ob WoL bereit ist oder was fehlt.' }
        @{ T = 'i'; X = '**Tool nachinstallieren (Dell):** installiert Dell Command | Configure (WinGet-Id Dell.CommandConfigure; danach läuft automatisch Status prüfen) auf Dell-Geräten, auf denen es fehlt. Das Gerät braucht PowerShell 7 und das WinGet-Modul (APP-Modul > WinGet-Modul nachinstallieren) und Internetzugang. HP und Lenovo brauchen kein Tool.' }
        @{ T = 'i'; X = '**Schnellstart ausschalten:** schaltet nur den Schnellstart von Windows aus, bei jedem Hersteller (auch Gigabyte, Alienware und andere, bei denen das BIOS nicht unterstützt wird). Netzwerkkarte und BIOS bleiben unverändert.' }
        @{ T = 'i'; X = '**WOL aktivieren:** schaltet bei der Netzwerkkarte (mit der Geräte-IP) Magic Packet und "Gerät darf den Computer aktivieren" ein, deaktiviert den Schnellstart (HiberbootEnabled = 0) und setzt Wake-on-LAN im BIOS, soweit möglich. Danach liest das Modul den Stand neu.' }
        @{ T = 'i'; X = '**Aufwecken:** sendet ein Magic Packet an die MAC-Adresse der markierten Geräte (Broadcast des Subnetzes und 255.255.255.255, UDP 9 und 7). Bei IP-Bereichen und einzelnen IP-Adressen geht es nur an 255.255.255.255.' }
        @{ T = 'h'; X = 'BIOS' }
        @{ T = 'i'; X = '**Dell:** über cctk.exe von Dell Command | Configure (--wakeonlan). Das Modul probiert lanonly, lanwlan und enable und liest den Wert danach zurück.' }
        @{ T = 'i'; X = '**HP:** über WMI (root\HP\InstrumentedBIOS, Einstellung "Wake On LAN").' }
        @{ T = 'i'; X = '**Lenovo:** über WMI (root\wmi, Lenovo_BiosSetting, Einstellung "Wake On LAN") mit anschließendem Speichern.' }
        @{ T = 'i'; X = '**Andere Hersteller:** werden nicht unterstützt, das BIOS bleibt unverändert.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Spalten:** Gerät, WoL Netzwerkkarte, Schnellstart und WoL im BIOS sind nur sichtbar, solange dieses Modulfenster offen ist.' }
        @{ T = 'i'; X = '**Netzwerkkarte:** Die Änderung läuft ohne Neustart der Karte. Greift sie nicht, hilft ein Neustart des Geräts.' }
        @{ T = 'i'; X = '**BIOS-Kennwort:** Ist eines gesetzt, kann das BIOS nicht geändert werden, das Log nennt den Rückgabewert.' }
        @{ T = 'i'; X = '**Nicht gesetzt oder nicht prüfbar:** Manche BIOS-Versionen haben zusätzliche Optionen für den ausgeschalteten Zustand (zum Beispiel Deep Sleep bei Dell). Diese ändert das Modul nicht.' }
        @{ T = 'i'; X = '**Gespeicherte Werte:** Gerät, WoL Netzwerkkarte, Schnellstart und WoL im BIOS bleiben je Gerät gespeichert (NET-COCKPIT-werte.json) und stehen nach dem Laden der Liste wieder in den Spalten.' }
        @{ T = 'w'; X = 'HP und Lenovo sind noch nicht an echten Geräten getestet. Das Modul ist insgesamt noch nicht vollständig auf echten Geräten getestet.' }
    ) }
}
