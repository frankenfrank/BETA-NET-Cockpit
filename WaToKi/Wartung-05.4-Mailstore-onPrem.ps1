#Requires -Version 7.0

<#
Beschreibung:
Fragt einen MailStore Server per MailStoreCmd.exe ab (GetServerInfo, GetStores mit Größe,
GetLicenseInformation, GetDirectoryServicesConfiguration, GetJobs, GetServiceConfiguration).
Die Ausgabe wird in der Konsole angezeigt und in eine Datei mit Datum geschrieben (ohne Ausgabeordner unter C:\Temp\<Servername>\).
Ausführung: direkt auf dem MailStore-Server, auf einem Rechner mit installiertem MailStoreCmd.exe oder per WinRM auf dem MailStore-Server.

Aus dem NET-COCKPIT (Modul WaToKi) gestartet bekommt das Skript den Server (-Ziel), den Ausgabeordner (-Ausgabeordner) und den MailStore-Benutzer samt Passwort (-Anmeldedaten, Spalte "Konto"). Dann fragt das Skript nichts ab.
Läuft das Skript nicht auf dem MailStore-Server selbst, startet es MailStoreCmd.exe per WinRM auf dem Server (mit dem Windows-Konto, unter dem der Lauf startet).
Ohne Parameter fragt das Skript alles selbst ab.
#>

# - EINGABEPARAMETER
param(
    [string]$Ziel,
    [string]$Ausgabeordner,
    [System.Management.Automation.PSCredential]$Anmeldedaten,
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

# - EINGABEN

## Servername
$ServerName = if ([string]::IsNullOrWhiteSpace($Ziel)) {
    if ($Automatik) { '' } else { Read-Host "Wie lautet der Servername des MailStore-Servers (FQDN)?" }
} else { $Ziel.Trim() }
if ([string]::IsNullOrWhiteSpace($ServerName)) {
    Write-Host "Kein Servername angegeben. Abbruch." -ForegroundColor Red
    if ($Automatik) { exit 1 }
    return
}

## Benutzername und Passwort
if ($Anmeldedaten) {
    $MailStoreUser = $Anmeldedaten.UserName
    $Password      = $Anmeldedaten.GetNetworkCredential().Password
}
elseif ($Automatik) {
    Write-Host "Abbruch: Im Automatikmodus sind -Anmeldedaten (MailStore-Benutzer) nötig." -ForegroundColor Red
    Write-WtErgebnis -Skript '05.4-Mailstore-onPrem' -Ordner $Ausgabeordner -Ergebnisse @([pscustomobject]@{ Ziel = $ServerName; Erreicht = $false; Pruefungen = [pscustomobject]@{}; Werte = [pscustomobject]@{}; Notiz = 'Keine MailStore-Zugangsdaten' })
    exit 1
}
else {
    $MailStoreUser = Read-Host "Wie lautet der Benutzername für die MailStore-Anmeldung?"
    if ([string]::IsNullOrWhiteSpace($MailStoreUser)) { Write-Host "Kein Benutzername angegeben. Abbruch." -ForegroundColor Red; return }
    $SecurePassword = Read-Host "Wie lautet das Passwort des MailStore-Benutzers $MailStoreUser?" -AsSecureString
    $Password = [System.Net.NetworkCredential]::new('', $SecurePassword).Password
}

## Lokal oder per WinRM
$Kurz  = ($ServerName -split '\.')[0]
$Lokal = ($ServerName -in @('localhost', '.', '127.0.0.1')) -or ($Kurz -ieq $env:COMPUTERNAME)

## Mögliche Pfade zur MailStoreCmd.exe (auf dem Rechner, auf dem sie läuft)
$Kandidaten = @(
    'C:\Program Files (x86)\MailStore\MailStore Server\MailStoreCmd.exe',
    'C:\Program Files\MailStore\MailStore Server\MailStoreCmd.exe'
)
if ($Lokal -and -not $Automatik -and -not ($Kandidaten | Where-Object { Test-Path -LiteralPath $_ })) {
    $Eingabe = Read-Host "Unter welchem Pfad liegt die MailStoreCmd.exe (vollständiger Pfad inkl. Dateiname)?"
    if (-not (Test-Path -LiteralPath $Eingabe)) { Write-Host "MailStoreCmd.exe nicht gefunden. Abbruch." -ForegroundColor Red; return }
    $Kandidaten = @($Eingabe)
}

# - AUSGABE UND LOGGING VORBEREITEN

## Konsolen-Kodierung für Umlaute
try { [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) } catch { }

## Ordner und Dateiname
$ServerNameClean = $ServerName -replace '[^a-zA-Z0-9\.\-_]', '_'
$OutputFolder    = if ([string]::IsNullOrWhiteSpace($Ausgabeordner)) { "C:\Temp\$ServerNameClean" } else { $Ausgabeordner.Trim() }
if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $OutputFolder ("MailStore-Abfrage_{0}_{1}.txt" -f $ServerNameClean, (Get-Date -Format "yyyyMMdd"))

## Write-Log
function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -LiteralPath $LogFile -Value $Message
}

# - ABFRAGEN AUSFÜHREN

## Liste der Funktionen
$Abfragen = @(
    @{ Name = "GetServerInfo";                     Parameter = @() },
    @{ Name = "GetStores";                         Parameter = @("--includeSize=true") },
    @{ Name = "GetLicenseInformation";             Parameter = @() },
    @{ Name = "GetDirectoryServicesConfiguration"; Parameter = @() },
    @{ Name = "GetJobs";                           Parameter = @() },
    @{ Name = "GetServiceConfiguration";           Parameter = @() }
)

## Skriptblock: läuft lokal oder per WinRM auf dem MailStore-Server
$Abfrage_SB = {
    param($Kandidaten, $Srv, $User, $Pw, $Abfragen)
    $Cmd = $Kandidaten | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $Cmd) { return [pscustomobject]@{ Fehler = 'MailStoreCmd.exe nicht gefunden'; Ergebnisse = @() } }
    try { [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) } catch { }
    $res = foreach ($a in $Abfragen) {
        $aus = & $Cmd --h=$Srv --u=$User --p=$Pw --nologo -c $a.Name @($a.Parameter) 2>&1
        [pscustomobject]@{ Name = $a.Name; ExitCode = $LASTEXITCODE; Zeilen = @($aus | ForEach-Object { [string]$_ }) }
    }
    [pscustomobject]@{ Fehler = ''; Ergebnisse = @($res) }
}

## Ausführung
Write-Log ("MailStore-Abfrage auf {0} am {1}{2}" -f $ServerName, (Get-Date -Format "dd.MM.yyyy HH:mm"), $(if ($Lokal) { '' } else { ' (per WinRM)' }))

$Antwort = $null
$VerbindungsFehler = ''
try {
    if ($Lokal) {
        $Antwort = & $Abfrage_SB $Kandidaten $ServerName $MailStoreUser $Password $Abfragen
    }
    else {
        $Antwort = Invoke-Command -ComputerName $ServerName -ScriptBlock $Abfrage_SB -ArgumentList $Kandidaten, $ServerName, $MailStoreUser, $Password, $Abfragen -ErrorAction Stop
    }
}
catch {
    $VerbindungsFehler = $_.Exception.Message
}

$Erfolgreich = 0
$Fehlgeschlagen = @()
if ($VerbindungsFehler) {
    Write-Log "FEHLER: Verbindung per WinRM zu $ServerName nicht möglich: $VerbindungsFehler"
}
elseif ($Antwort.Fehler) {
    Write-Log "FEHLER: $($Antwort.Fehler) (Server $ServerName)"
}
else {
    foreach ($e in $Antwort.Ergebnisse) {
        Write-Log ""
        Write-Log "=== $($e.Name) ==="
        foreach ($Zeile in $e.Zeilen) { Write-Log $Zeile }
        if ($e.ExitCode -ne 0) {
            Write-Log "FEHLER: $($e.Name) wurde mit Exitcode $($e.ExitCode) beendet."
            $Fehlgeschlagen += $e.Name
        }
        else { $Erfolgreich++ }
    }
}

# - ABSCHLUSS

## Passwort aus dem Speicher entfernen
$Password = $null
$SecurePassword = $null

## Hinweis auf die Datei
Write-Log ""
Write-Log "Ausgabe gespeichert unter: $LogFile"

if ($Automatik) {
    # - ERGEBNIS FÜR DIE CHECKLISTE (keine Haken: Die Ausgabe von MailStoreCmd wird nicht ausgewertet, alles steht in der Technikerinfo)
    $erreicht = ($Erfolgreich -gt 0)
    $notiz = if ($VerbindungsFehler) { 'Per WinRM nicht erreichbar' }
             elseif ($Antwort.Fehler) { [string]$Antwort.Fehler }
             elseif (-not $erreicht) { 'MailStore-Abfragen fehlgeschlagen (Anmeldung prüfen)' }
             elseif ($Fehlgeschlagen.Count -gt 0) { "$Erfolgreich von $($Abfragen.Count) Abfragen ok, fehlgeschlagen: $($Fehlgeschlagen -join ', ')" }
             else { "$Erfolgreich von $($Abfragen.Count) Abfragen ok, Details in der Technikerinfo" }
    Write-WtErgebnis -Skript '05.4-Mailstore-onPrem' -Ordner $Ausgabeordner -Ergebnisse @([pscustomobject]@{
        Ziel       = $ServerName
        Erreicht   = $erreicht
        Pruefungen = [pscustomobject]@{}
        Werte      = [pscustomobject]@{ AbfragenOk = $Erfolgreich; AbfragenFehlgeschlagen = @($Fehlgeschlagen) }
        Notiz      = $notiz
    })
    if ($erreicht) { exit 0 } else { exit 1 }
}
