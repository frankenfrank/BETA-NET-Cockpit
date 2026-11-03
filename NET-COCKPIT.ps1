<#
.SYNOPSIS
    NET-COCKPIT - Netzwerkscan, Neustart, Herunterfahren und Geräteinformationen für die KuDo, mit nachladbaren Modulen (Updates, Diagnose, M365-Wartungs-App und WaToKi)

.DESCRIPTION
    PowerShell-7-/WPF-Oberfläche zum Verwalten von Geräten, die meist ausgeschaltet sind.
    - Startet immer leer: Eine Geräteliste wird über Datei > Öffnen geladen oder durch Scan bzw. OU-Auswahl aufgebaut; Datei > Neue Liste beginnt wieder leer
    - Anzeigen-Auswahl (Alle, Nur WinRM, Online, Offline) filtert Anzeige, Markierung und Export; Datei-Dialoge starten im Ordner der Liste, sonst im Datenordner
    - Scannt ein Netz per Ping, liest MAC-Adressen aus der ARP-Tabelle und Hersteller aus der IEEE-OUI-Liste
    - Liest die Computer einer OU aus dem Active Directory (LDAP, kein RSAT nötig)
    - Geräteliste als Semikolon-getrennte Textdatei; Speichern ohne bekannte Datei fragt nach Name und Ort, Auto-Speichern schreibt nur in die zuletzt geöffnete oder gespeicherte Datei
    - Datenordner C:\Temp\NET-COCKPIT_data: Logdatei, Herstellerliste, Einstellungen (Optionen und Spalten), die von den Modulen ausgelesenen Werte (NET-COCKPIT-werte.json) und pro Gerät die ausgelesenen KuDo-Informationen (Unterordner Geraeteinfos); Optionen > "NET-COCKPIT Daten löschen..." entfernt alles
    - Neustart, Neustart planen (Aufgabe auf dem Zielgerät), Neustart abbrechen und Herunterfahren per WinRM
    - Aufträge an mehrere Geräte laufen in einer Warteschlange; die Parallelität (Standard 10) ist in den Optionen einstellbar
    - Ampel: Grün = Ping + WinRM (Port 5985), Gelb = nur Ping, Rot = offline
    - Spalten lassen sich per Rechtsklick auf die Spaltenüberschrift oder über Ansicht > Spalten ein- und ausblenden (Auswahl wird gespeichert); bei vielen Spalten gibt es einen waagerechten Scrollbalken
    - Doppelklick auf "Aktion / Status" zeigt das Log des Geräts (Cockpit-Log und Modul-Logs)
    - Spaltenfilter mit Platzhaltern (* und ?), mit ! für leere Zellen und mit !Text zum Ausschließen (zum Beispiel !2012)
    - Ausgelesene Modulwerte (Windows-Version, WinGet, WAU, WOL, Hersteller und Modell) bleiben je Gerät gespeichert (MAC, sonst IP) und erscheinen nach dem Laden der Liste wieder; Spalte "Werte gelesen am"
    - Portscan (TCP), Dauerping, PowerShell-Befehl an mehrere Geräte, KuDo-Informationen auslesen (Client, Server physisch, Server virtuell; Windows per WinRM, Linux per SSH mit Posh-SSH; ergänzt leeres Hostname, MAC und Hersteller)
    - Konto pro Gerät (Spalte "Konto"; Dialog mit vorbelegtem Benutzernamen, leeres Kennwort erlaubt = Abfrage bei der ersten Aktion); scheitert eine Verbindung an den TrustedHosts, bietet das Cockpit das Eintragen an
    - Werkzeuge: Portscan, Dauerping, PowerShell-Befehl, KuDo-Informationen (mit Laufwerken und Speicherbalken), Neuer Client von Hand, Einzel-Scan markierter Geräte, MouseMover
    - Zuordnung beim Scan über die MAC-Adresse; eine IP, die ein anderes Gerät belegt, wird beim alten Eintrag entfernt
    - Module im Menü Module (OS, APP, Treiber, Diagnose, M365-Wartungs-App, RDP, WaToKi, WOL): jeweils eine eigene Datei im Ordner des NET-COCKPIT, wird erst beim ersten Aufruf geladen; beim Start über start.ps1 liegt nur das NET-COCKPIT bereit, ein Modul (beim Modul WaToKi auch die Wartungsskripte) holt das Cockpit beim ersten Aufruf mit Ladefenster vom Server und prüft es gegen seine .sig-Datei
    - Info: Reiter Voraussetzungen mit Allgemein sowie je einer Anleitung zur Grundfreischaltung (WinRM und Ping) per GPO und per Intune
    - Hilfetexte der Module: Datei NET-COCKPIT-Hilfe.ps1 neben dem Cockpit; die Info lädt sie beim Öffnen (bei Bedarf vom Server), damit alle Modul-Reiter ohne Start der Module lesbar sind
    - Modul APP: Status, App-Updates, Programme installieren, anzeigen (gemeinsame Liste mit Suche und CSV-Export) und deinstallieren, WinGet-Modul nachinstallieren, Winget-AutoUpdate (WAU) installieren und dessen Ausschlussliste bearbeiten (auch die Intune-Variante wird erkannt)
    - Modul M365-Wartungs-App: legt im Kunden-Tenant die Wartungs-App MAHR-EDV-Wartung für das M365-Cockpit an oder aktualisiert sie (App-Registrierung, Zertifikat, Berechtigungen); zeigt vorher, was installiert wird, wählt zusätzliche Berechtigungen per Haken und startet das eingebaute Skript in einem eigenen PowerShell-Fenster ohne Administratorrechte (kein Gerätebezug)
    - Modul WOL: Wake-on-LAN prüfen und einrichten (Netzwerkkarte, Schnellstart, BIOS bei Dell, HP, Lenovo), Tool nachinstallieren (Dell) und Geräte per Magic Packet aufwecken
    - Modul WaToKi (Spalte "Wartungsreihenfolge", bearbeitbar, wird mit der Geräteliste gespeichert; sichtbar, wenn im Fenster der Haken für die Spalte gesetzt ist): startet die Wartungsskripte aus dem Unterordner WaToKi in einem eigenen PowerShell-Fenster, immer nur eines gleichzeitig; markierte Geräte und der Ausgabeordner (Modul-WaToKi im Datenordner) werden übergeben, wenn das Skript die Parameter -Ziel, -Ausgabeordner und -Anmeldedaten kennt (Konto aus der Spalte Konto)

.NOTES
    Voraussetzungen:
    - PowerShell 7 unter Windows
    - MAC-Adressen werden nur im eigenen Subnetz gefunden (ARP)
    - Wake-on-LAN muss im BIOS/UEFI und in der Netzwerkkarte aktiviert sein
    - Neustart, Herunterfahren, PowerShell-Befehl und KuDo-Informationen: WinRM (TCP 5985) und Administratorrechte auf dem Ziel (Windows)
    - KuDo-Informationen bei Linux-Geräten und ESXi-Hosts: SSH (TCP 22), PowerShell-Modul Posh-SSH auf dem Rechner mit dem Cockpit (das Cockpit bietet die Installation an), Benutzer aus der Spalte Konto (Kennwort, kein Root nötig)
    - Geräte, die Ping blockieren, werden als offline (Rot) angezeigt
    - Module: Dateien NET-COCKPIT-Modul-OS.ps1, NET-COCKPIT-Modul-APP.ps1 und NET-COCKPIT-Modul-TREIBER.ps1, NET-COCKPIT-Modul-DIAGNOSE.ps1, NET-COCKPIT-Modul-WATOKI.ps1, NET-COCKPIT-Modul-M365APP.ps1, NET-COCKPIT-Modul-RDP.ps1, NET-COCKPIT-Modul-MOUSEMOVER.ps1 und NET-COCKPIT-Modul-WOL.ps1 sowie die Hilfedatei NET-COCKPIT-Hilfe.ps1 im selben Ordner wie dieses Skript; die Wartungsskripte des Moduls WaToKi liegen im Unterordner WaToKi
    - Start über start.ps1: Der Starter setzt die Umgebungsvariablen NETCOCKPIT_BASE (Proxy-Adresse) und NETCOCKPIT_KEY (öffentlicher Schlüssel) und legt zusätzlich die Datei net-cockpit-server.json neben das Cockpit; fehlt eine Moduldatei im Ordner, lädt das Cockpit sie darüber nach (Signaturprüfung), sonst bleibt es beim Ordner
#>

Clear-Host

# Startzeit messen
## Zeitstempel sammeln; sie stehen nach dem Start im Log (Zeilen "Startzeit: ...")
$script:StartUhr = [System.Diagnostics.Stopwatch]::StartNew()
$script:StartMarken = [System.Collections.Generic.List[string]]::new()
$script:ProzessAlter = 0
try { $script:ProzessAlter = [math]::Round(((Get-Date) - (Get-Process -Id $PID).StartTime).TotalSeconds, 1) } catch { }
function Add-WolStartMarke {
    param([string]$Name)
    $script:StartMarken.Add(('{0} nach {1:N1} s' -f $Name, $script:StartUhr.Elapsed.TotalSeconds))
}

# Versionsprüfung
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show("Das NET-COCKPIT läuft nur unter PowerShell 7.`r`nInstallation: https://aka.ms/install-powershell", 'NET-COCKPIT', 'OK', 'Warning')
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Add-WolStartMarke 'Bibliotheken geladen'

# Einstellungen
## Pfade
$script:ArbeitsOrdner     = 'C:\Temp'
$script:DatenOrdner       = Join-Path $script:ArbeitsOrdner 'NET-COCKPIT_data'
$script:GeraeteOrdner     = Join-Path $script:DatenOrdner 'Geraeteinfos'
$script:LogPfad           = Join-Path $script:DatenOrdner 'NET-COCKPIT.log'
$script:OuiPfad           = Join-Path $script:DatenOrdner 'NET-COCKPIT-oui.csv'
$script:EinstellungenPfad = Join-Path $script:DatenOrdner 'NET-COCKPIT-einstellungen.json'
$script:ModulOrdner       = $PSScriptRoot
$script:ServerBasis      = [string]$env:NETCOCKPIT_BASE
$script:ServerSchluessel  = [string]$env:NETCOCKPIT_KEY
### Fehlen die Umgebungsvariablen, steht der Server in der Datei net-cockpit-server.json neben dem Cockpit (legt start.ps1 an)
if ($PSScriptRoot -and (-not $script:ServerBasis -or -not $script:ServerSchluessel)) {
    $serverDatei = Join-Path $PSScriptRoot 'net-cockpit-server.json'
    if (Test-Path -LiteralPath $serverDatei) {
        try {
            $serverInfo = Get-Content -LiteralPath $serverDatei -Raw -Encoding utf8 | ConvertFrom-Json
            $script:ServerBasis = [string]$serverInfo.Base
            $script:ServerSchluessel = [string]$serverInfo.Key
        }
        catch { }
    }
}
$script:ListenPfad        = $null
if (-not (Test-Path $script:DatenOrdner)) { New-Item -Path $script:DatenOrdner -ItemType Directory -Force | Out-Null }

## Logdatei bei jedem Start leeren
if (Test-Path $script:LogPfad) { try { Clear-Content -Path $script:LogPfad -ErrorAction Stop } catch { } }

## Laufzeitwerte
$script:NetzCidr     = $null
$script:ScanJob      = $null
$script:ScanAktiv    = $false
$script:BefehlMax     = 20
$script:BefehlFenster = $null
$script:BefehlZiele  = @()
$script:BefehlText   = ''
$script:KudoStat     = $null
$script:NeuHinweis   = ''
$script:KudoHinweis  = ''
$script:KudoPanel    = $null
$script:KudoZeile    = $null
$script:KudoKopf     = $null
$script:KudoKnopf    = $null
$script:Opt          = @{ AutoScan = $true; AutoMin = '5'; Status = $true; StatusMin = '1'; AutoSpeichern = $true; Parallel = 10; Anzeige = 'Alle'; Spalten = @{} }
$script:SpaltenFilter = @{}
$script:FilterBoxen  = [System.Collections.Generic.List[object]]::new()
$script:SpaltenListe = [System.Collections.Generic.List[object]]::new()
$script:StatusJob    = $null
$script:ScanInfo     = $null
$script:Warteschlange = [System.Collections.Generic.List[object]]::new()
$script:AuftragJobs  = [System.Collections.Generic.List[object]]::new()
$script:TrustedOffen = [System.Collections.Generic.List[object]]::new()
$script:TrustedDialog = $false
$script:Geaendert    = $false
$script:AutoHinweisGezeigt = $false
$script:DatenLoeschen = $false
$script:OhneSpeichern = $false
$script:PingFenster  = $null
$script:PingTabs     = [System.Collections.Generic.List[object]]::new()
$script:PortJobs     = [System.Collections.Generic.List[object]]::new()
$script:PortWarteschlange = [System.Collections.Generic.List[object]]::new()
$script:PortBereich  = '1-1024'
## Nachladbare Module: eine Datei je Modul im Ordner des NET-COCKPIT; die Datei legt ihre Funktionen mit "function script:Name" an und stellt "Show-WolModul<Schlüssel>" bereit
$script:Module = [ordered]@{
    OS      = @{ Name = 'OS-Updates';      Datei = 'NET-COCKPIT-Modul-OS.ps1';      Geladen = $false }
    APP     = @{ Name = 'APP-Updates';     Datei = 'NET-COCKPIT-Modul-APP.ps1';     Geladen = $false }
    TREIBER = @{ Name = 'Treiber-Updates'; Datei = 'NET-COCKPIT-Modul-TREIBER.ps1'; Geladen = $false }
    DIAGNOSE = @{ Name = 'Diagnose';       Datei = 'NET-COCKPIT-Modul-DIAGNOSE.ps1'; Geladen = $false }
    WATOKI  = @{ Name = 'WaToKi';          Datei = 'NET-COCKPIT-Modul-WATOKI.ps1';  Geladen = $false }
    M365APP = @{ Name = 'M365-Wartungs-App'; Datei = 'NET-COCKPIT-Modul-M365APP.ps1'; Geladen = $false }
    RDP     = @{ Name = 'RDP';             Datei = 'NET-COCKPIT-Modul-RDP.ps1';     Geladen = $false }
    MOUSEMOVER = @{ Name = 'MouseMover';   Datei = 'NET-COCKPIT-Modul-MOUSEMOVER.ps1'; Geladen = $false }
    WOL     = @{ Name = 'WOL';             Datei = 'NET-COCKPIT-Modul-WOL.ps1';     Geladen = $false }
}
$script:ModulInfo = @{}
## Hilfedatei mit den Reitern aller Module (wird beim Öffnen der Info geladen)
$script:HilfeDatei = 'NET-COCKPIT-Hilfe.ps1'
$script:HilfeGeladen = $false
$script:ModulOffen = [System.Collections.Generic.HashSet[string]]::new()
$script:ModulSpaltenAn = [System.Collections.Generic.HashSet[string]]::new()
$script:PortNamen    = @{
    21 = 'FTP'; 22 = 'SSH'; 23 = 'Telnet'; 25 = 'SMTP'; 53 = 'DNS'; 80 = 'HTTP'; 88 = 'Kerberos'; 110 = 'POP3'
    111 = 'RPC-Portmapper'; 135 = 'RPC'; 139 = 'NetBIOS'; 143 = 'IMAP'; 389 = 'LDAP'; 443 = 'HTTPS'; 445 = 'SMB'
    465 = 'SMTPS'; 515 = 'LPD'; 548 = 'AFP'; 554 = 'RTSP'; 587 = 'SMTP-Submission'; 593 = 'RPC-HTTP'; 631 = 'IPP'
    636 = 'LDAPS'; 993 = 'IMAPS'; 995 = 'POP3S'; 1433 = 'SQL Server'; 1521 = 'Oracle'; 1723 = 'PPTP'; 2049 = 'NFS'
    3268 = 'AD Global Catalog'; 3269 = 'AD Global Catalog SSL'; 3306 = 'MySQL'; 3389 = 'RDP'; 5060 = 'SIP'; 5357 = 'WSD'
    5432 = 'PostgreSQL'; 5900 = 'VNC'; 5985 = 'WinRM'; 5986 = 'WinRM-HTTPS'; 8080 = 'HTTP-Alt'; 8443 = 'HTTPS-Alt'
    9100 = 'Drucker (RAW)'; 9389 = 'AD Web Services'
}
$script:C            = @{}

Add-WolStartMarke 'Einstellungen gesetzt'

# Zeilenklasse
## Datenzeile für das DataGrid (meldet Änderungen an die Oberfläche)
### Der Indexer nimmt beliebige zusätzliche Werte auf (zum Beispiel Spalten der Module)
if (-not ('NetCockpitZeile' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System.ComponentModel;
using System.Collections.Generic;
public class NetCockpitZeile : INotifyPropertyChanged
{
    public const int Version = 1;
    public event PropertyChangedEventHandler PropertyChanged;
    private void Melde(string n) { PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(n)); }
    private Dictionary<string, string> _werte = new Dictionary<string, string>();
    public string this[string schluessel]
    {
        get { string v; return _werte.TryGetValue(schluessel, out v) ? v : ""; }
        set { _werte[schluessel] = value; Melde("Item[]"); }
    }
    private string _ampel = "Unbekannt"; public string Ampel { get { return _ampel; } set { _ampel = value; Melde("Ampel"); } }
    private string _hostname = ""; public string Hostname { get { return _hostname; } set { _hostname = value; Melde("Hostname"); } }
    private string _typ = ""; public string Typ { get { return _typ; } set { _typ = value; Melde("Typ"); } }
    public static string StandardKonto = "";
    private string _konto = ""; public string Konto { get { return _konto; } set { _konto = value; Melde("Konto"); Melde("KontoAnzeige"); } }
    public string KontoAnzeige { get { return string.IsNullOrEmpty(_konto) ? StandardKonto + " (aktuelles Konto)" : _konto; } }
    public object Kennwort = null;
    private string _ip = ""; private long _ipsort = long.MaxValue;
    public string IP { get { return _ip; } set { _ip = value; _ipsort = BerechneIp(value); Melde("IP"); Melde("IpSort"); } }
    public long IpSort { get { return _ipsort; } }
    private static long BerechneIp(string s)
    {
        System.Net.IPAddress a;
        if (s != null && System.Net.IPAddress.TryParse(s.Trim(), out a))
        {
            byte[] b = a.GetAddressBytes();
            if (b.Length == 4) { return ((long)b[0] << 24) | ((long)b[1] << 16) | ((long)b[2] << 8) | (long)b[3]; }
        }
        return long.MaxValue;
    }
    private string _mac = ""; public string MAC { get { return _mac; } set { _mac = value; Melde("MAC"); } }
    private string _hersteller = ""; public string Hersteller { get { return _hersteller; } set { _hersteller = value; Melde("Hersteller"); } }
    private string _subnetz = ""; public string Subnetz { get { return _subnetz; } set { _subnetz = value; Melde("Subnetz"); } }
    private string _zuletzt = ""; public string ZuletztGesehen { get { return _zuletzt; } set { _zuletzt = value; Melde("ZuletztGesehen"); } }
    private string _bemerkung = ""; public string Bemerkung { get { return _bemerkung; } set { _bemerkung = value; Melde("Bemerkung"); } }
    private string _ports = ""; public string Ports { get { return _ports; } set { _ports = value; Melde("Ports"); } }
    private string _status = ""; public string Status { get { return _status; } set { _status = value; Melde("Status"); } }
}
'@
}
elseif ([NetCockpitZeile]::Version -ne 1) {
    [void][System.Windows.MessageBox]::Show("In diesem PowerShell-Fenster ist noch eine ältere Version des NET-COCKPIT geladen.`r`nBitte das PowerShell-Fenster schließen, ein neues öffnen und das Skript erneut starten.", 'NET-COCKPIT', 'OK', 'Warning')
    return
}
$script:Zeilen  = New-Object 'System.Collections.ObjectModel.ObservableCollection[NetCockpitZeile]'
$script:Ansicht = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:Zeilen)

Add-WolStartMarke 'C#-Zeilenklasse bereit'

# Hilfsfunktionen
## Fenster aus XAML-Text laden
function New-WolFenster {
    param([string]$Xaml)
    $x = [xml]$Xaml
    $r = [System.Xml.XmlNodeReader]::new($x)
    return [Windows.Markup.XamlReader]::Load($r)
}

## Meldungsfenster
function Show-WolMeldung {
    param([string]$Text, [string]$Bild = 'Information')
    [void][System.Windows.MessageBox]::Show($Text, 'NET-COCKPIT', 'OK', $Bild)
}

## Fehlertext von WinRM kurz und verständlich machen (der volle Text gehört nur in die Logdatei)
function Get-WolFehlerKurz {
    param([string]$Text)
    if (-not $Text) { return 'unbekannter Fehler' }
    if ($Text -match 'explicit credentials') { return 'Für die Verbindung per IP sind Konto und Kennwort nötig' }
    if ($Text -match 'TrustedHosts') { return 'TrustedHosts fehlt' }
    if ($Text -match 'Zugriff verweigert|Access is denied|AccessDenied|Access denied') { return 'Zugriff verweigert' }
    if ($Text -match 'Kerberos|Dom.ne|domain controller|Benutzername oder Kennwort|user name or password|logon failure|Anmeldefehler|0x8009030[89A-F]|0x80090311') { return 'Anmeldung nicht möglich (Konto oder Domäne)' }
    $zeile = ($Text -split "[\r\n]+" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if (-not $zeile) { return 'unbekannter Fehler' }
    $zeile = $zeile.Trim()
    if ($zeile.Length -gt 100) { $zeile = $zeile.Substring(0, 97) + '...' }
    return $zeile
}

## Logzeile (Oberfläche und Datei)
function Write-WolLog {
    param([string]$Text, [switch]$NurDatei)
    $zeile = '{0:HH:mm:ss}  {1}' -f (Get-Date), $Text
    if ($script:C.Log -and -not $NurDatei) {
        $script:C.Log.AppendText($zeile + "`r`n")
        $script:C.Log.ScrollToEnd()
    }
    if (-not $script:DatenLoeschen) {
        try { Add-Content -Path $script:LogPfad -Value ('{0:yyyy-MM-dd} {1}' -f (Get-Date), $zeile) -Encoding utf8 } catch { }
    }
}

## IP-Zahl in Textform umwandeln
function ConvertTo-WolIp {
    param([uint64]$N)
    return '{0}.{1}.{2}.{3}' -f (($N -shr 24) -band 255), (($N -shr 16) -band 255), (($N -shr 8) -band 255), ($N -band 255)
}

## IP-Text in Zahl umwandeln (-1 bei ungültiger Adresse)
function ConvertFrom-WolIp {
    param([string]$Text)
    $t = $Text.Trim()
    if ($t -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return [int64]-1 }
    $o = $null
    if (-not [System.Net.IPAddress]::TryParse($t, [ref]$o)) { return [int64]-1 }
    $b = $o.GetAddressBytes()
    return [int64]$b[0] * 16777216 + [int64]$b[1] * 65536 + [int64]$b[2] * 256 + [int64]$b[3]
}

## Netzinformationen aus Netzadresse/Präfix berechnen (erlaubt: /22 bis /30)
function Get-WolNetzInfo {
    param([string]$Cidr)
    $teile = $Cidr.Trim().Split('/')
    if ($teile.Count -ne 2) { return $null }
    $ipObj = $null
    if (-not [System.Net.IPAddress]::TryParse($teile[0], [ref]$ipObj)) { return $null }
    if ($ipObj.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $null }
    $praefix = 0
    if (-not [int]::TryParse($teile[1], [ref]$praefix)) { return $null }
    if ($praefix -lt 22 -or $praefix -gt 30) { return $null }
    $b = $ipObj.GetAddressBytes()
    $ipZahl = [uint64]$b[0] * 16777216 + [uint64]$b[1] * 65536 + [uint64]$b[2] * 256 + [uint64]$b[3]
    $groesse = [uint64][math]::Pow(2, 32 - $praefix)
    $netz = [uint64]([math]::Floor($ipZahl / $groesse) * $groesse)
    $broadcast = $netz + $groesse - 1
    $adressen = for ($n = $netz + 1; $n -lt $broadcast; $n++) { ConvertTo-WolIp $n }
    return [pscustomobject]@{
        Cidr      = '{0}/{1}' -f (ConvertTo-WolIp $netz), $praefix
        Broadcast = ConvertTo-WolIp $broadcast
        Adressen  = [string[]]@($adressen)
    }
}

## Eingabe in Scanbereiche zerlegen: Netz (Adresse/Präfix), IP-Bereich (von-bis) oder einzelne IP, mehrere mit Komma; insgesamt maximal 1024 Adressen
function Get-WolScanBereiche {
    param([string]$Text)
    $maximum = 1024
    $bereiche = [System.Collections.Generic.List[object]]::new()
    $alle = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($teil in $Text.Split(',')) {
        $t = $teil.Trim()
        if (-not $t) { continue }
        $broadcast = ''
        if ($t.Contains('/')) {
            $info = Get-WolNetzInfo -Cidr $t
            if (-not $info) {
                return [pscustomobject]@{ Bereiche = @(); Adressen = @(); Fehler = "Das Netz '$t' ist ungültig oder liegt außerhalb von /22 bis /30." }
            }
            $adressen = $info.Adressen
            $label = $info.Cidr
            $broadcast = $info.Broadcast
        }
        elseif ($t.Contains('-')) {
            $paar = $t.Split('-')
            $von = if ($paar.Count -eq 2) { ConvertFrom-WolIp $paar[0] } else { [int64]-1 }
            $bis = if ($paar.Count -eq 2) { ConvertFrom-WolIp $paar[1] } else { [int64]-1 }
            if ($von -lt 0 -or $bis -lt 0 -or $von -gt $bis) {
                return [pscustomobject]@{ Bereiche = @(); Adressen = @(); Fehler = "Der IP-Bereich '$t' ist ungültig (Format: von-bis, die erste Adresse darf nicht größer sein als die letzte)." }
            }
            if (($bis - $von + 1) -gt $maximum) {
                return [pscustomobject]@{ Bereiche = @(); Adressen = @(); Fehler = "Der IP-Bereich '$t' umfasst mehr als $maximum Adressen." }
            }
            $adressen = for ($n = $von; $n -le $bis; $n++) { ConvertTo-WolIp ([uint64]$n) }
            $label = '{0}-{1}' -f (ConvertTo-WolIp ([uint64]$von)), (ConvertTo-WolIp ([uint64]$bis))
        }
        else {
            $n = ConvertFrom-WolIp $t
            if ($n -lt 0) {
                return [pscustomobject]@{ Bereiche = @(); Adressen = @(); Fehler = "Die IP-Adresse '$t' ist ungültig." }
            }
            $adressen = @(ConvertTo-WolIp ([uint64]$n))
            $label = $adressen[0]
        }
        foreach ($a in $adressen) { [void]$alle.Add([string]$a) }
        $bereiche.Add([pscustomobject]@{ Label = $label; Broadcast = $broadcast; Adressen = [string[]]@($adressen) })
    }
    if ($bereiche.Count -eq 0) {
        return [pscustomobject]@{ Bereiche = @(); Adressen = @(); Fehler = 'Es wurde kein Netz, IP-Bereich oder keine IP-Adresse eingegeben.' }
    }
    if ($alle.Count -gt $maximum) {
        return [pscustomobject]@{ Bereiche = @(); Adressen = @(); Fehler = "Es sind insgesamt maximal $maximum Adressen erlaubt (eingegeben: $($alle.Count))." }
    }
    return [pscustomobject]@{ Bereiche = @($bereiche); Adressen = [string[]]@($alle); Fehler = '' }
}

## Netz der aktiven Netzwerkkarte mit Gateway ermitteln
function Get-WolAktuellesNetz {
    $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.IPv4DefaultGateway -and $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1
    if (-not $cfg) { return $null }
    $adr = $cfg.IPv4Address[0]
    return '{0}/{1}' -f $adr.IPAddress, $adr.PrefixLength
}

## Magic Packet senden (Subnetz-Broadcast und 255.255.255.255, Port 9 und 7)
function Send-WolPaket {
    param([string]$Mac, [string]$Broadcast)
    $macBytes = [byte[]]($Mac.Split(':') | ForEach-Object { [Convert]::ToByte($_, 16) })
    $paket = [byte[]](@(0xFF) * 6) + [byte[]]($macBytes * 16)
    $ziele = @('255.255.255.255')
    if ($Broadcast) { $ziele += $Broadcast }
    $udp = [System.Net.Sockets.UdpClient]::new()
    try {
        $udp.EnableBroadcast = $true
        foreach ($ziel in $ziele) {
            foreach ($port in 9, 7) { [void]$udp.Send($paket, $paket.Length, $ziel, $port) }
        }
    }
    finally { $udp.Dispose() }
}

## Dateinamen- und Listenfunktionen
### Anzeige von Fenstertitel und Listenpfad
function Update-WolListeAnzeige {
    if ($script:ListenPfad) {
        $script:Fenster.Title = "NET-COCKPIT - $($script:ListenPfad)"
        $script:C.TxtListe.Text = "Geräteliste: $($script:ListenPfad)"
        $script:AutoHinweisGezeigt = $false
    }
    else {
        $script:Fenster.Title = 'NET-COCKPIT'
        $script:C.TxtListe.Text = 'Geräteliste: noch keine Datei (Speichern fragt nach Name und Ort)'
    }
}

### Startordner für Datei-Dialoge: Ordner der aktuellen Liste, sonst Daten-Ordner
function Get-WolStartOrdner {
    if ($script:ListenPfad) {
        $ordner = Split-Path -Path $script:ListenPfad -Parent
        if ($ordner -and (Test-Path -LiteralPath $ordner)) { return $ordner }
    }
    if (Test-Path -LiteralPath $script:DatenOrdner) { return $script:DatenOrdner }
    return [Environment]::GetFolderPath('MyDocuments')
}

### Gespeicherte Werte: was die Module je Gerät auslesen, bleibt in NET-COCKPIT-werte.json erhalten (Schlüssel = MAC ohne Trennzeichen, sonst IP)
$script:WerteDatei = Join-Path $script:DatenOrdner 'NET-COCKPIT-werte.json'
$script:WerteKeys = @(
    'Windows', 'AppModul', 'AppWinget', 'WauStatus', 'OsModul', 'TrHersteller', 'TrModell', 'TrTool',
    'WolGeraet', 'WolKarte', 'WolSchnellstart', 'WolBios'
)
$script:WerteSpeicher = @{}
$script:WerteGeladen = $false

### Schlüssel eines Geräts: MAC (12 Hexzeichen, groß), sonst IP; leer = nicht speicherbar
function Get-WolWerteId {
    param($Zeile, [switch]$NurIp)
    if (-not $NurIp) {
        $mac = ([string]$Zeile.MAC) -replace '[^0-9A-Fa-f]', ''
        if ($mac.Length -eq 12) { return $mac.ToUpper() }
    }
    return ([string]$Zeile.IP).Trim()
}

### Datei einmal einlesen
function Import-WolWerte {
    if ($script:WerteGeladen) { return }
    $script:WerteGeladen = $true
    try {
        if (Test-Path -LiteralPath $script:WerteDatei) {
            $daten = Get-Content -LiteralPath $script:WerteDatei -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
            if ($daten) { foreach ($id in $daten.Keys) { $script:WerteSpeicher[[string]$id] = $daten[$id] } }
        }
    }
    catch { Write-WolLog "Gespeicherte Werte konnten nicht gelesen werden: $($_.Exception.Message)" }
}

### Gespeicherte Werte in eine Zeile einsetzen (nur in leere Felder, aktuelle Werte bleiben)
function Restore-WolWerteZeile {
    param($Zeile)
    Import-WolWerte
    if ($script:WerteSpeicher.Count -eq 0) { return }
    $eintrag = $null
    foreach ($id in @((Get-WolWerteId -Zeile $Zeile), (Get-WolWerteId -Zeile $Zeile -NurIp))) {
        if ($id -and $script:WerteSpeicher.ContainsKey($id)) { $eintrag = $script:WerteSpeicher[$id]; break }
    }
    if (-not $eintrag) { return }
    foreach ($schluessel in @($script:WerteKeys) + 'WerteStand') {
        if ($eintrag.ContainsKey($schluessel) -and -not $Zeile[$schluessel]) { $Zeile[$schluessel] = [string]$eintrag[$schluessel] }
    }
}

### Alle Zeilen der Tabelle auffüllen (beim Öffnen eines Moduls)
function Restore-WolWerteAlle {
    foreach ($z in @($script:Zeilen)) { Restore-WolWerteZeile -Zeile $z }
}

### Werte einer Zeile speichern; -Neu = frisch gelesen (setzt "Werte gelesen am"), sonst nur bei geänderten Werten
function Save-WolWerteZeile {
    param($Zeile, [switch]$Neu)
    try {
        Import-WolWerte
        $id = Get-WolWerteId -Zeile $Zeile
        if (-not $id) { return }
        $eintrag = $(if ($script:WerteSpeicher.ContainsKey($id)) { $script:WerteSpeicher[$id] } else { @{} })
        $geaendert = $false
        $vorhanden = $false
        foreach ($schluessel in $script:WerteKeys) {
            $wert = [string]$Zeile[$schluessel]
            if (-not $wert) { continue }
            $vorhanden = $true
            if ([string]$eintrag[$schluessel] -ne $wert) { $eintrag[$schluessel] = $wert; $geaendert = $true }
        }
        if (-not $vorhanden -or (-not $geaendert -and -not $Neu)) { return }
        $stand = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $eintrag['WerteStand'] = $stand
        $Zeile['WerteStand'] = $stand
        $script:WerteSpeicher[$id] = $eintrag
        if (-not (Test-Path -LiteralPath $script:DatenOrdner)) { New-Item -Path $script:DatenOrdner -ItemType Directory -Force | Out-Null }
        $script:WerteSpeicher | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:WerteDatei -Encoding utf8
    }
    catch { Write-WolLog "Gespeicherte Werte konnten nicht geschrieben werden: $($_.Exception.Message)" }
}

### Offene Zelleingabe abschließen (erst Zelle, dann Zeile) und als Änderung vormerken
$script:Bearbeitet = $false
function Complete-WolBearbeitung {
    [void]$script:C.Gitter.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)
    [void]$script:C.Gitter.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)
    if ($script:Bearbeitet) { $script:Geaendert = $true; $script:Bearbeitet = $false }
}

### Liste speichern; ohne Pfad passiert nichts. Rückgabe: $true bei Erfolg
function Save-WolListe {
    param([string]$Pfad, [switch]$Still)
    if (-not $Pfad) { return $false }
    try {
        Complete-WolBearbeitung
        $ordner = Split-Path -Path $Pfad -Parent
        if ($ordner -and -not (Test-Path $ordner)) { New-Item -Path $ordner -ItemType Directory -Force | Out-Null }
        $script:Zeilen | ForEach-Object {
            [pscustomobject]@{
                Hostname       = $_.Hostname
                Typ            = $_.Typ
                Konto          = $_.Konto
                IP             = $_.IP
                MAC            = $_.MAC
                Hersteller     = $_.Hersteller
                Subnetz        = $_.Subnetz
                ZuletztGesehen = $_.ZuletztGesehen
                OffenePorts    = $(if ($_.Ports -like 'Portscan *') { '' } else { $_.Ports })
                Bemerkung      = $_.Bemerkung
                Wartungsreihenfolge = $_['Wartungsreihenfolge']
            }
        } | Export-Csv -Path $Pfad -Delimiter ';' -NoTypeInformation -Encoding utf8BOM
        $script:Geaendert = $false
        if (-not $Still) { Write-WolLog "Liste gespeichert: $Pfad ($($script:Zeilen.Count) Einträge)" }
        return $true
    }
    catch {
        Write-WolLog "Fehler beim Speichern: $($_.Exception.Message)"
        return $false
    }
}

### Auto-Speichern: schreibt nur in die bekannte Liste, ohne Liste bleibt es still (einmal ein Hinweis im Log)
function Save-WolAuto {
    if (-not $script:Opt.AutoSpeichern) { return }
    if ($script:ListenPfad) { [void](Save-WolListe -Pfad $script:ListenPfad -Still); return }
    if (-not $script:AutoHinweisGezeigt) {
        $script:AutoHinweisGezeigt = $true
        Write-WolLog 'Auto-Speichern wartet: Es ist noch keine Geräteliste festgelegt (Datei > Speichern unter)'
    }
}

### Speichern unter: fragt nach Dateiname und Ort; Rückgabe: $true, wenn gespeichert wurde
function Save-WolListeUnter {
    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Title = 'Geräteliste speichern unter'
    $dlg.InitialDirectory = Get-WolStartOrdner
    $dlg.Filter = 'Listen (*.txt)|*.txt|Alle Dateien (*.*)|*.*'
    $dlg.FileName = if ($script:ListenPfad) { Split-Path -Path $script:ListenPfad -Leaf } else { 'Liste-NET-COCKPIT.txt' }
    if (-not $dlg.ShowDialog()) { return $false }
    if (-not (Save-WolListe -Pfad $dlg.FileName)) { return $false }
    $script:ListenPfad = $dlg.FileName
    Update-WolListeAnzeige
    return $true
}

### Speichern: in die bekannte Datei, sonst Nachfrage nach Name und Ort
function Save-WolListeAktuell {
    if ($script:ListenPfad) { [void](Save-WolListe -Pfad $script:ListenPfad) }
    else { [void](Save-WolListeUnter) }
}

### Liste öffnen (ersetzt die Tabelle)
function Open-WolListe {
    param([string]$Pfad)
    try {
        $script:Zeilen.Clear()
        if (Test-Path $Pfad) {
            foreach ($r in @(Import-Csv -Path $Pfad -Delimiter ';' -Encoding utf8)) {
                $z = New-Object NetCockpitZeile
                $z.Hostname       = [string]$r.Hostname
                $z.Typ            = [string]$r.Typ
                $z.Konto          = [string]$r.Konto
                $z.IP             = [string]$r.IP
                $z.MAC            = [string]$r.MAC
                $z.Hersteller     = [string]$r.Hersteller
                $z.Subnetz        = [string]$r.Subnetz
                $datum = [string]$r.ZuletztGesehen
                if ($datum -match '^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}:\d{2})$') { $datum = '{0}-{1}-{2} {3}' -f $Matches[3], $Matches[2], $Matches[1], $Matches[4] }
                $z.ZuletztGesehen = $datum
                $z.Ports          = [string]$r.OffenePorts
                $z.Bemerkung      = [string]$r.Bemerkung
                $z['Wartungsreihenfolge'] = [string]$r.Wartungsreihenfolge
                $z.Status         = 'Noch nicht geprüft'
                Restore-WolWerteZeile -Zeile $z
                $script:Zeilen.Add($z)
            }
        }
        $script:ListenPfad = $Pfad
        Update-WolListeAnzeige
        Update-WolAnsicht
        $script:Geaendert = $false
        Write-WolLog "Liste geladen: $Pfad ($($script:Zeilen.Count) Einträge)"
        return $true
    }
    catch {
        Write-WolLog "Fehler beim Laden: $($_.Exception.Message)"
        return $false
    }
}

### Bei ungespeicherten Änderungen nachfragen (true = weitermachen, false = abbrechen)
function Confirm-WolSpeichern {
    if (-not $script:Geaendert) { return $true }
    if ($script:ListenPfad -and $script:Opt.AutoSpeichern) {
        [void](Save-WolListe -Pfad $script:ListenPfad -Still)
        return $true
    }
    if (-not $script:ListenPfad -and $script:Zeilen.Count -eq 0) { return $true }
    $ziel = if ($script:ListenPfad) { $script:ListenPfad } else { 'Es folgt die Abfrage von Dateiname und Ort.' }
    $antwort = [System.Windows.MessageBox]::Show("Die Geräteliste hat ungespeicherte Änderungen. Jetzt speichern?`r`n$ziel", 'NET-COCKPIT', 'YesNoCancel', 'Question')
    if ($antwort -eq 'Yes') {
        if ($script:ListenPfad) { [void](Save-WolListe -Pfad $script:ListenPfad); return $true }
        return [bool](Save-WolListeUnter)
    }
    if ($antwort -eq 'No') { return $true }
    return $false
}

### Neue, leere Liste: Hintergrundarbeit anhalten, Tabelle und Filter leeren (Scanbereich, Konten und Optionen bleiben)
function New-WolListe {
    Complete-WolBearbeitung
    if (-not (Confirm-WolSpeichern)) { return }
    if ($script:ScanJob) { Stop-WolScanSteuerung }
    if ($script:StatusJob) { Remove-Job -Job $script:StatusJob -Force -ErrorAction SilentlyContinue; $script:StatusJob = $null }
    foreach ($p in @($script:PortJobs)) { $p.Status.Abbruch = $true; Remove-Job -Job $p.Job -Force -ErrorAction SilentlyContinue }
    $script:PortJobs.Clear()
    $script:PortWarteschlange.Clear()
    Stop-WolAlleAuftraege
    $script:Zeilen.Clear()
    foreach ($box in $script:FilterBoxen) { $box.Text = '' }
    $script:ListenPfad = $null
    $script:Geaendert = $false
    Update-WolListeAnzeige
    Update-WolAnsicht -Bestaetigen
    Write-WolLog 'Neue Liste: Tabelle geleert'
}

### Liste über den Öffnen-Dialog laden
function Open-WolListeDialog {
    $dlg = [Microsoft.Win32.OpenFileDialog]::new()
    $dlg.Title = 'Geräteliste öffnen'
    $dlg.InitialDirectory = Get-WolStartOrdner
    $dlg.Filter = 'Listen (*.txt)|*.txt|Alle Dateien (*.*)|*.*'
    if (-not $dlg.ShowDialog()) { return }
    if (-not (Confirm-WolSpeichern)) { return }
    if (Open-WolListe -Pfad $dlg.FileName) { Start-WolStatusPruefung }
}

## Tabellenansicht aktualisieren (Filter, Ausblenden); -Bestaetigen schließt eine laufende Zelleingabe zuerst ab, sonst wird bei laufender Eingabe nicht aktualisiert
function Update-WolAnsicht {
    param([switch]$Bestaetigen)
    try {
        if ($Bestaetigen -and $script:C.Gitter) {
            Complete-WolBearbeitung
        }
        $script:Ansicht.Refresh()
    }
    catch { }
}

## Markierte (sichtbare) Zeilen
function Get-WolMarkierte {
    ## Reihenfolge wie in der angezeigten Tabelle (SelectedItems liefert die Klick-Reihenfolge)
    $angezeigt = @($script:Ansicht)
    return @($script:C.Gitter.SelectedItems | Where-Object { $script:Ansicht.Contains($_) } | Sort-Object { [array]::IndexOf($angezeigt, $_) })
}

## Markierte Geräte nach Rückfrage aus der Liste entfernen (Werkzeuge)
function Remove-WolMarkierte {
    $ziele = Get-WolMarkierte
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    $antwort = [System.Windows.MessageBox]::Show("$($ziele.Count) Eintrag/Einträge aus der Liste entfernen?", 'NET-COCKPIT', 'YesNo', 'Warning')
    if ($antwort -ne 'Yes') { return }
    foreach ($z in $ziele) { [void]$script:Zeilen.Remove($z) }
    $script:Geaendert = $true
    Save-WolAuto
}

## Prüfen, ob sich ein Hostname auflösen lässt (DNS, hosts-Datei); das Ergebnis wird 10 Minuten gemerkt, damit nicht bei jedem Aufruf neu abgefragt wird
$script:NameAufloesung = @{}
function Test-WolNameAufloesbar {
    param([string]$Name)
    $eintrag = $script:NameAufloesung[$Name]
    if ($eintrag -and ((Get-Date) - $eintrag.Zeit).TotalMinutes -lt 10) { return $eintrag.Ok }
    $ok = $false
    try { $ok = (@([System.Net.Dns]::GetHostAddresses($Name)).Count -gt 0) } catch { }
    $script:NameAufloesung[$Name] = @{ Ok = $ok; Zeit = Get-Date }
    if (-not $ok) { Write-WolLog "Hostname $Name lässt sich nicht auflösen, das Cockpit verbindet sich per IP-Adresse" }
    return $ok
}

## Name, unter dem ein Gerät per WinRM angesprochen wird: der Hostname, bei Sonderzeichen (zum Beispiel Umlauten), ohne Hostname oder wenn sich der Hostname nicht auflösen lässt (zum Beispiel Gerät ohne Domäne) die IP-Adresse
function Get-WolZielName {
    param($Zeile)
    $name = [string]$Zeile.Hostname
    if ($name -and $name -match '^[\x21-\x7E]+$') {
        if (-not [string]$Zeile.IP -or (Test-WolNameAufloesbar -Name $name)) { return $name }
    }
    return [string]$Zeile.IP
}

## Anmeldedaten für ein Gerät: eigenes Konto (Benutzername aus der Geräteliste, Kennwort aus der Sitzung), sonst $null (= angemeldetes Windows-Konto)
function Get-WolAnmeldung {
    param($Zeile)
    if ($Zeile.Konto) {
        if (-not $Zeile.Kennwort) { throw "Für das Konto $($Zeile.Konto) liegt in dieser Sitzung kein Kennwort vor." }
        return [System.Management.Automation.PSCredential]::new([string]$Zeile.Konto, [System.Security.SecureString]$Zeile.Kennwort)
    }
    return $null
}

## Fehlende Kennwörter der Gerätekonten abfragen (einmal pro Benutzername); $false bei Abbruch
function Resolve-WolKonten {
    param($Zeilen, $Besitzer)
    ### Geräte ohne Hostname werden per IP angesprochen, das geht nur mit Konto und Kennwort
    $perIp = @($Zeilen | Where-Object { -not $_.Konto -and (Get-WolZielName -Zeile $_) -eq [string]$_.IP })
    if ($perIp.Count -gt 0) {
        $ipListe = @($perIp | ForEach-Object { [string]$_.IP })
        $ipNamen = if ($ipListe.Count -gt 6) { "$($ipListe.Count) Geräte" } else { $ipListe -join ', ' }
        $text = "Diese Geräte haben keinen Hostnamen und werden über die IP-Adresse angesprochen ($ipNamen). Dafür sind ein Konto und ein Kennwort nötig (bleibt das Kennwort leer, wird es gleich danach abgefragt). Benutzername als Domäne\Benutzer oder .\Benutzer (lokales Konto des Geräts)."
        $erg = Show-WolAnmeldung -Titel 'Konto für Geräte ohne Hostname' -Text $text -ZurueckText 'Ohne Konto fortfahren'
        if (-not $erg) { return $false }
        if ($erg -isnot [string]) {
            foreach ($z in $perIp) { $z.Konto = $erg.UserName; $z.Kennwort = $erg.Password }   ### leeres Kennwort: wird unten einmal abgefragt
            $script:Geaendert = $true
            Save-WolAuto
            Update-WolAnsicht
            Write-WolLog "Konto $($erg.UserName) für $($perIp.Count) Gerät(e) ohne Hostname gesetzt"
        }
    }
    $fehlend = @($Zeilen | Where-Object { $_.Konto -and -not $_.Kennwort })
    if ($fehlend.Count -eq 0) { return $true }
    foreach ($gruppe in @($fehlend | Group-Object { ([string]$_.Konto).ToLower() })) {
        $liste = @($gruppe.Group | ForEach-Object { if ($_.Hostname) { ([string]$_.Hostname).Split('.')[0] } else { $_.IP } })
        $namen = if ($liste.Count -gt 6) { "$($liste.Count) Geräte" } else { $liste -join ', ' }
        $kennwort = Show-WolKennwort -Benutzer ([string]$gruppe.Group[0].Konto) -Geraete $namen -Besitzer $Besitzer
        if (-not $kennwort) { return $false }
        foreach ($z in $gruppe.Group) { $z.Kennwort = $kennwort }
    }
    return $true
}

# Scan-Block
## Läuft als Thread-Job: Ping, WinRM-Port, Hostname, MAC (ARP), Hersteller (OUI)
$script:ScanBlock = {
    param([string[]]$Adressen, [int]$Drossel, [string]$OuiPfad)

    $gefunden = @($Adressen | ForEach-Object -ThrottleLimit $Drossel -Parallel {
        $ip = $_
        $antwort = $null
        $ping = [System.Net.NetworkInformation.Ping]::new()
        try { $antwort = $ping.Send($ip, 700) } catch { } finally { $ping.Dispose() }
        if ($antwort -and $antwort.Status -eq 'Success') {
            $name = ''
            try {
                $dns = [System.Net.Dns]::GetHostEntryAsync($ip)
                if ($dns.Wait(2500)) { $name = $dns.Result.HostName }
            } catch { }
            if ($name -eq $ip) { $name = '' }
            $winrm = $false
            $tcp = [System.Net.Sockets.TcpClient]::new()
            try {
                $task = $tcp.ConnectAsync($ip, 5985)
                $winrm = ($task.Wait(700) -and $tcp.Connected)
            } catch { } finally { $tcp.Dispose() }
            [pscustomobject]@{ IP = $ip; Hostname = $name; WinRM = $winrm }
        }
    })

    # MAC-Adressen aus ARP-Tabelle und lokalen Netzwerkkarten
    $arp = @{}
    Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne 'FF-FF-FF-FF-FF-FF' } |
        ForEach-Object { $arp[$_.IPAddress] = $_.LinkLayerAddress }
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
        $karte = $_.NetAdapter
        foreach ($a in $_.IPv4Address) { if ($karte.LinkLayerAddress) { $arp[$a.IPAddress] = $karte.LinkLayerAddress } }
    }

    # Hersteller aus lokaler OUI-Liste (ohne Liste bleibt der Hersteller leer)
    $oui = @{}
    $ouiFehler = ''
    if ($gefunden.Count -gt 0 -and (Test-Path $OuiPfad)) {
        try { Import-Csv -Path $OuiPfad | ForEach-Object { $oui[$_.Assignment] = $_.'Organization Name' } }
        catch { $ouiFehler = $_.Exception.Message }
    }

    $ergebnis = foreach ($g in ($gefunden | Sort-Object { [version]$_.IP })) {
        $mac = ''
        $roh = $arp[$g.IP]
        if ($roh) {
            $hex = ($roh -replace '[^0-9A-Fa-f]', '').ToUpper()
            if ($hex.Length -eq 12) { $mac = $hex -replace '(.{2})(?!$)', '$1:' }
        }
        $hersteller = ''
        if ($mac) { $hersteller = [string]$oui[$mac.Replace(':', '').Substring(0, 6)] }
        [pscustomobject]@{ IP = $g.IP; Hostname = $g.Hostname; WinRM = $g.WinRM; MAC = $mac; Hersteller = $hersteller }
    }

    [pscustomobject]@{ Gefunden = @($ergebnis); OuiFehler = $ouiFehler }
}

# Aktions-Block
## Läuft als Thread-Job je Gerät: Neustart, Neustart planen, Herunterfahren, Abbrechen oder Prüfen eines geplanten Neustarts per WinRM
$script:AktionBlock = {
    param([string]$Ziel, [string]$Art, $Wert, $Anmeldedaten, [string]$TaskCode)
    $ic = @{ ComputerName = $Ziel; ErrorAction = 'Stop' }
    if ($Anmeldedaten) { $ic.Credential = $Anmeldedaten }
    switch ($Art) {
        'Neustart' {
            Invoke-Command @ic -ArgumentList $Wert -ScriptBlock {
                param($v)
                & shutdown.exe /r /t $v /c 'Neustart durch Wartung (NET-COCKPIT)' | Out-Null
                $LASTEXITCODE
            }
        }
        'Herunterfahren' {
            Invoke-Command @ic -ArgumentList $Wert -ScriptBlock {
                param($v)
                & shutdown.exe /s /t $v /c 'Herunterfahren durch Wartung (NET-COCKPIT)' | Out-Null
                $LASTEXITCODE
            }
        }
        'Planen' {
            . ([scriptblock]::Create($TaskCode))
            Set-WolZielNeustart -Ic $ic -ZeitText ([string]$Wert)
        }
        'Abbrechen' {
            . ([scriptblock]::Create($TaskCode))
            Remove-WolZielNeustart -Ic $ic
        }
        'Pruefen' {
            . ([scriptblock]::Create($TaskCode))
            Get-WolZielNeustartPruefung -Ic $ic
        }
    }
}

# Befehl-Block
## Läuft als Thread-Job je Gerät: führt den eingegebenen Text per Invoke-Command als ScriptBlock auf dem Zielgerät aus
$script:BefehlBlock = {
    param([string]$Ziel, [string]$Text, $Anmeldedaten)
    $ProgressPreference = 'SilentlyContinue'
    try {
        $sb = [scriptblock]::Create($Text)
        $p = @{ ComputerName = $Ziel; ErrorAction = 'Stop' }
        if ($Anmeldedaten) { $p.Credential = $Anmeldedaten }
        $alle = @(& { Invoke-Command @p -ScriptBlock $sb } *>&1)
        $fehler = @($alle | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count
        [pscustomobject]@{ Erfolg = ($fehler -eq 0); Ausgabe = (($alle | Out-String -Width 200).TrimEnd()) }
    }
    catch {
        [pscustomobject]@{ Erfolg = $false; Ausgabe = "Fehler: $($_.Exception.Message)" }
    }
}

# KuDo-Block
## Läuft als Thread-Job je Gerät: liest per Invoke-Command die Geräteinformationen aus (Typ: Client, Server physisch oder Server virtuell) und liefert sie als Felderliste zurück
$script:KudoBlock = {
    param([string]$Ziel, [string]$TypVorgabe, $Anmeldedaten, [string]$Ip)
    $ProgressPreference = 'SilentlyContinue'
    try {
        $p = @{ ComputerName = $Ziel; ErrorAction = 'Stop' }
        if ($Anmeldedaten) { $p.Credential = $Anmeldedaten }
        $roh = @(Invoke-Command @p -ArgumentList $TypVorgabe, $Ip -ScriptBlock {
            param($Vorgabe, $Adresse)
            $ErrorActionPreference = 'Stop'
            function Feld($n, $w) { [pscustomobject]@{ Name = $n; Wert = [string]$w } }

            ### Grunddaten des Zielgeräts
            $os = Get-CimInstance -ClassName Win32_OperatingSystem
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem
            $bios = Get-CimInstance -ClassName Win32_BIOS
            $cpus = @(Get-CimInstance -ClassName Win32_Processor)
            $platten = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $_.Size })

            ### Typ bestimmen (eine gültige Vorgabe aus der Spalte "Typ" gilt, sonst Erkennung)
            $typ = @('Client', 'Server physisch', 'Server virtuell') | Where-Object { $_ -eq $Vorgabe } | Select-Object -First 1
            if (-not $typ) {
                $modell = '{0} {1}' -f $cs.Manufacturer, $cs.Model
                if ($os.ProductType -eq 1) { $typ = 'Client' }
                elseif ($modell -match 'Virtual Machine|VMware|VirtualBox|innotek|QEMU|\bKVM\b|\bXen\b|HVM domU|Parallels|Nutanix|\bAHV\b|Bochs') { $typ = 'Server virtuell' }
                else { $typ = 'Server physisch' }
            }

            ### Gemeinsame Werte
            try { $fqdn = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName } catch { $fqdn = $env:COMPUTERNAME }

            ### MAC-Adresse des Adapters mit der Geräte-IP; ist er virtuell (zum Beispiel VPN), zählt der einzige aktive physische Adapter, bei mehreren bleibt die MAC leer
            $mac = ''
            try {
                $konf = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $Adresse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($konf) {
                    $karte = Get-NetAdapter -InterfaceIndex $konf.InterfaceIndex -ErrorAction SilentlyContinue
                    if ($karte -and $karte.HardwareInterface) { $mac = [string]$karte.MacAddress }
                    else {
                        $physisch = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
                        if ($physisch.Count -eq 1) { $mac = [string]$physisch[0].MacAddress }
                    }
                }
            }
            catch { $mac = '' }
            $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 0)
            $kerne = ($cpus | Measure-Object -Property NumberOfCores -Sum).Sum
            $cpuName = (@($cpus | ForEach-Object { ([string]$_.Name).Trim() } | Select-Object -Unique)) -join ', '
            $installDatum = ''
            if ($os.InstallDate) { $installDatum = $os.InstallDate.ToString('dd.MM.yyyy') }
            $hddClient = (@($platten | ForEach-Object { '{0}{1}GB' -f $_.DeviceID, [math]::Round($_.Size / 1GB, 0) })) -join '; '
            $hddServer = (@($platten | ForEach-Object { '{0}:{1}' -f $_.DeviceID.TrimEnd(':'), [math]::Round([math]::Round($_.Size / 1TB, 2) * 1000, 0) })) -join '; '

            ### Serverrollen und IP-Adressen (nur Server)
            $rollenText = ''
            $protokolle = ''
            $ipNamen = ''
            $ipNur = ''
            $laufwerke = @($platten | ForEach-Object { [pscustomobject]@{ Laufwerk = $_.DeviceID; Frei = [math]::Round($_.FreeSpace / 1GB, 0); Gesamt = [math]::Round($_.Size / 1GB, 0) } })
            if ($typ -ne 'Client') {
                $rollen = [ordered]@{
                    'Domain Controller' = 'AD-Domain-Services'; 'File Server' = 'FS-FileServer'; 'Print Server' = 'Print-Server'
                    'DHCP Server' = 'DHCP'; 'DNS Server' = 'DNS'; 'Webserver' = 'Web-Server'; 'SQL Server' = 'RSAT-SQL-Tools'
                    'Remote Desktop Services' = 'RDS-RD-Server'; 'Hyper-V' = 'Hyper-V'; 'Backup Server' = 'Windows-Server-Backup'
                    'Mail Server' = 'Messaging'; 'WSUS' = 'UpdateServices'; 'Active Directory Certificate Services' = 'AD-Certificate'
                }
                try {
                    $features = @(Get-WindowsFeature -Name @($rollen.Values))
                    $installiert = [System.Collections.Generic.List[string]]::new()
                    foreach ($anzeige in $rollen.Keys) {
                        $feature = $features | Where-Object { $_.Name -eq $rollen[$anzeige] } | Select-Object -First 1
                        if ($feature -and $feature.Installed) { $installiert.Add($anzeige) }
                    }
                    if ($installiert.Count -gt 0) { $rollenText = $installiert -join ', ' } else { $rollenText = 'Keine relevanten Rollen installiert' }

                    ### Protokolle für das Feld Notizen (Anzeigenamen wie im Wartungsformular, Reihenfolge wie dort)
                    $protokollListe = [System.Collections.Generic.List[string]]::new()
                    foreach ($basis in 'Anwendung', 'System', 'Sicherheit') { $protokollListe.Add($basis) }
                    $protokollRollen = [ordered]@{ 'DNS' = 'DNS'; 'Active Directory' = 'AD-Domain-Services'; 'DHCP' = 'DHCP'; 'Webserver' = 'Web-Server'; 'Dateiserver' = 'FS-FileServer'; 'Datensicherung' = 'Windows-Server-Backup' }
                    foreach ($anzeige in $protokollRollen.Keys) {
                        $feature = $features | Where-Object { $_.Name -eq $protokollRollen[$anzeige] } | Select-Object -First 1
                        if ($feature -and $feature.Installed) { $protokollListe.Add($anzeige) }
                    }
                    $protokolle = 'Protokolle: ' + ($protokollListe -join ', ')
                }
                catch { $rollenText = 'nicht ermittelbar: ' + $_.Exception.Message; $protokolle = 'Protokolle: nicht ermittelbar' }
                $adressen = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -and $_.IPAddress -notlike '127.*' } | Sort-Object InterfaceIndex)
                $ipNamen = (@($adressen | ForEach-Object { '{0}: {1}' -f $_.InterfaceAlias, $_.IPAddress })) -join ', '
                $ipNur = (@($adressen | ForEach-Object { $_.IPAddress })) -join ', '
                $laufwerke = @($platten | ForEach-Object { [pscustomobject]@{ Laufwerk = $_.DeviceID; Frei = [math]::Round($_.FreeSpace / 1GB, 0); Gesamt = [math]::Round($_.Size / 1GB, 0) } })
            }

            ### Felder je Typ (Namen und Reihenfolge wie in den KuDo-Skripten)
            if ($typ -eq 'Client') {
                $felder = @(
                    Feld 'Hostname' $env:COMPUTERNAME
                    Feld 'Hersteller' $cs.Manufacturer
                    Feld 'Modell' $cs.Model
                    Feld 'Betriebssystem' $os.Caption
                    Feld 'CPU' $cpuName
                    Feld 'RAM (GB)' $ramGb
                    Feld 'HDD (GB)' $hddClient
                    Feld 'Seriennummer' $bios.SerialNumber
                    Feld 'Installationsdatum' $installDatum
                )
                $fussnote = ''
            }
            elseif ($typ -eq 'Server physisch') {
                $felder = @(
                    Feld 'Hostname' $fqdn
                    Feld 'Hersteller' $cs.Manufacturer
                    Feld 'Modell' $cs.Model
                    Feld 'IP-Adressen' $ipNamen
                    Feld 'Betriebssystem' $os.Caption
                    Feld 'Server Rollen*' $rollenText
                    Feld 'CPU' ('{0} ({1} Cores)' -f $cpuName, $kerne)
                    Feld 'RAM (GB)' $ramGb
                    Feld 'HDD (GB)' $hddServer
                    Feld 'RAID' 'Nicht ermittelt'
                    Feld 'Seriennummer' $bios.SerialNumber
                    Feld 'OS Install Date' ('{0} (evtl. Kaufdatum)' -f $installDatum)
                    Feld 'Notizen' $protokolle
                )
                $fussnote = '*Es werden nur die wichtigsten Rollen ermittelt.'
            }
            else {
                $felder = @(
                    Feld 'Name' $fqdn
                    Feld 'IP-Adresse' $ipNur
                    Feld 'Betriebssystem' $os.Caption
                    Feld 'Server Rollen*' $rollenText
                    Feld 'CPU (Cores)' $kerne
                    Feld 'RAM (GB)' $ramGb
                    Feld 'HDD (GB)' $hddServer
                    Feld 'Notizen' $protokolle
                )
                $fussnote = '*Es werden nur die wichtigsten Rollen ermittelt.'
            }

            [pscustomobject]@{ Typ = $typ; Felder = @($felder); Laufwerke = @($laufwerke); Fussnote = $fussnote; Hostname = [string]$fqdn; Mac = $mac } | ConvertTo-Json -Depth 5 -Compress
        })
        $json = [string]($roh | Where-Object { $_ -is [string] } | Select-Object -Last 1)
        if (-not $json) { throw 'keine Rückmeldung vom Zielgerät' }
        $d = $json | ConvertFrom-Json
        [pscustomobject]@{ Erfolg = $true; Typ = [string]$d.Typ; Felder = @($d.Felder); Laufwerke = @($d.Laufwerke); Fussnote = [string]$d.Fussnote; Fehler = ''; Hostname = [string]$d.Hostname; Mac = [string]$d.Mac }
    }
    catch {
        [pscustomobject]@{ Erfolg = $false; Typ = ''; Felder = @(); Laufwerke = @(); Fussnote = ''; Fehler = $_.Exception.Message; Hostname = ''; Mac = '' }
    }
}

# KuDo-Block Linux
## Läuft als Thread-Job: prüft nur die SSH-Anmeldung mit Posh-SSH (der Hostschlüssel wird beim ersten Kontakt akzeptiert und gespeichert, danach geprüft)
$script:SshPruefBlock = {
    param([string]$Ziel, $Anmeldedaten)
    $ProgressPreference = 'SilentlyContinue'
    $sitzung = $null
    try {
        Import-Module -Name Posh-SSH -ErrorAction Stop
        ### Posh-SSH schreibt die Hostschlüssel in eine gemeinsame Datei (hosts.json): Verbindungsaufbau nacheinander, bei gesperrter Datei wiederholen
        $sperre = [System.Threading.Mutex]::new($false, 'Local\NetCockpitPoshSsh')
        $hatSperre = $false
        try {
            $hatSperre = $sperre.WaitOne(90000)
            for ($versuch = 1; $versuch -le 3; $versuch++) {
                try { $sitzung = New-SSHSession -ComputerName $Ziel -Credential $Anmeldedaten -AcceptKey -ConnectionTimeout 15 -ErrorAction Stop; break }
                catch {
                    if ($versuch -eq 3 -or $_.Exception.Message -notmatch 'cannot access the file|kann nicht auf die Datei zugreifen|being used by another process|wird von einem anderen Prozess verwendet') { throw }
                    Start-Sleep -Milliseconds 700
                }
            }
        }
        finally { if ($hatSperre) { $sperre.ReleaseMutex() }; $sperre.Dispose() }
        [pscustomobject]@{ Erfolg = $true; Fehler = '' }
    }
    catch { [pscustomobject]@{ Erfolg = $false; Fehler = $_.Exception.Message } }
    finally { if ($sitzung) { [void](Remove-SSHSession -SSHSession $sitzung -ErrorAction SilentlyContinue) } }
}

## Läuft als Thread-Job je Linux-Gerät: liest per SSH (Posh-SSH, Kennwort, ohne Root und ohne sudo, nur lesende Befehle) und liefert dieselbe Ergebnisform wie der Windows-Block
$script:KudoLinuxBlock = {
    param([string]$Ziel, [string]$TypVorgabe, $Anmeldedaten, [string]$Ip)
    $ProgressPreference = 'SilentlyContinue'
    $sitzung = $null
    try {
        Import-Module -Name Posh-SSH -ErrorAction Stop

        ### Skript für das Zielgerät (POSIX-Shell, nur lesend); es wird als Base64 übergeben, damit keine Anführungszeichen stören
        $skript = @'
LC_ALL=C; export LC_ALL
p() { printf '%s=%s\n' "$1" "$2"; }
p HOST "$(hostname -f 2>/dev/null || hostname 2>/dev/null)"
if [ -r /etc/os-release ]; then . /etc/os-release; p OS "$PRETTY_NAME"; fi
p KERNEL "$(uname -r 2>/dev/null)"
cpu=$(grep -m1 -i 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
if [ -z "$cpu" ]; then cpu=$(lscpu 2>/dev/null | sed -n 's/^Model name: *//p' | head -1); fi
p CPU "$cpu"
cores=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/{gsub(/ /,"",$2);c=$2} /^Socket\(s\)/{gsub(/ /,"",$2);s=$2} END{if(c>0&&s>0)print c*s}')
if [ -z "$cores" ]; then cores=$(nproc 2>/dev/null); fi
p CORES "$cores"
p RAM "$(awk '/^MemTotal/{printf "%d", ($2/1048576)+0.5}' /proc/meminfo 2>/dev/null)"
df -P -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | awk 'NR>1{print "DISK="$6"|"$2"|"$4}'
p VIRT "$(systemd-detect-virt 2>/dev/null)"
p VENDOR "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
p MODEL "$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
p SERIAL "$(cat /sys/class/dmi/id/product_serial 2>/dev/null)"
ip -o -4 addr show scope global 2>/dev/null | awk '{print "IP="$2"|"$4}'
for d in /sys/class/net/*; do
  n=${d##*/}
  if [ "$n" = lo ]; then continue; fi
  k=0
  if [ -e "$d/device" ] || [ -d "$d/bridge" ] || [ -d "$d/bonding" ]; then k=1; fi
  p NIC "$n|$(cat "$d/address" 2>/dev/null)|$k"
done
p UPSEC "$(cut -d. -f1 /proc/uptime 2>/dev/null)"
p BOOT "$(date -d "@$(( $(date +%s) - $(cut -d. -f1 /proc/uptime) ))" '+%d.%m.%Y %H:%M' 2>/dev/null)"
if command -v apt-get >/dev/null 2>&1; then
  p UPD "$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c '^Inst')"
elif command -v dnf >/dev/null 2>&1; then
  out=$(dnf -q --cacheonly check-update 2>/dev/null); rc=$?
  if [ "$rc" -eq 100 ]; then p UPD "$(printf '%s\n' "$out" | grep -cE '^[^ ]+\.[^ .]+ +[^ ]+ +[^ ]+')"; elif [ "$rc" -eq 0 ]; then p UPD 0; fi
fi
if command -v systemctl >/dev/null 2>&1; then
  p SVC "$(systemctl list-units --type=service --state=running --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
fi
p ENDE 1
'@
        $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($skript -replace "`r", '')))

        ### Posh-SSH schreibt die Hostschlüssel in eine gemeinsame Datei (hosts.json): Verbindungsaufbau nacheinander, bei gesperrter Datei wiederholen
        $sperre = [System.Threading.Mutex]::new($false, 'Local\NetCockpitPoshSsh')
        $hatSperre = $false
        try {
            $hatSperre = $sperre.WaitOne(90000)
            for ($versuch = 1; $versuch -le 3; $versuch++) {
                try { $sitzung = New-SSHSession -ComputerName $Ziel -Credential $Anmeldedaten -AcceptKey -ConnectionTimeout 15 -ErrorAction Stop; break }
                catch {
                    if ($versuch -eq 3 -or $_.Exception.Message -notmatch 'cannot access the file|kann nicht auf die Datei zugreifen|being used by another process|wird von einem anderen Prozess verwendet') { throw }
                    Start-Sleep -Milliseconds 700
                }
            }
        }
        finally { if ($hatSperre) { $sperre.ReleaseMutex() }; $sperre.Dispose() }

        ### ESXi (VMkernel) erkennen: eigene Abfragen mit esxcli, ohne base64
        $art = [string](@((Invoke-SSHCommand -SessionId $sitzung.SessionId -Command 'uname -s' -TimeOut 30 -ErrorAction Stop).Output) -join '').Trim()
        $esxi = ($art -eq 'VMkernel')
        if ($esxi) {
            $skript = @'
p() { printf '%s=%s\n' "$1" "$2"; }
p HOST "$(hostname 2>/dev/null)"
p OS "$(vmware -v 2>/dev/null)"
p KERNEL "$(uname -r 2>/dev/null)"
p CPU "$(esxcli hardware cpu list 2>/dev/null | awk -F': *' '/Brand:/{print $2; exit}')"
p CORES "$(esxcli hardware cpu global get 2>/dev/null | awk -F': *' '/CPU Cores:/{print $2; exit}')"
p RAM "$(esxcli hardware memory get 2>/dev/null | awk '/Physical Memory/{printf "%d", ($3/1073741824)+0.5}')"
esxcli storage filesystem list 2>/dev/null | awk 'NR>2 && ($(NF-2) ~ /^(VMFS|NFS|vsan)/) { name=""; for (i=2;i<=NF;i++) { if ($i ~ /^[0-9a-fA-F]+-[0-9a-fA-F-]+$/) break; name=name (name==""?"":" ") $i }; if (name=="") name=$1; print "DISK="name"|"$(NF-1)"|"$NF }'
p VIRT none
p VENDOR "$(esxcli hardware platform get 2>/dev/null | sed -n 's/^ *Vendor Name: *//p' | head -1)"
p MODEL "$(esxcli hardware platform get 2>/dev/null | sed -n 's/^ *Product Name: *//p' | head -1)"
p SERIAL "$(esxcli hardware platform get 2>/dev/null | sed -n 's/^ *Serial Number: *//p' | head -1)"
esxcli network ip interface ipv4 get 2>/dev/null | awk 'NR>2 && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print "IP="$1"|"$2}'
esxcli network ip interface list 2>/dev/null | awk '/^vmk/{n=$1} /MAC Address:/{if(n!=""){print "NIC="n"|"$3"|1"; n=""}}'
p UPSEC "$(esxcli system stats uptime get 2>/dev/null | awk '/Uptime:/{printf "%d", $2/1000000}')"
p ENDE 1
'@
            $befehl = "sh <<'NETCOCKPITEND'`n" + ($skript -replace "`r", '') + "`nNETCOCKPITEND"
            $antwort = Invoke-SSHCommand -SessionId $sitzung.SessionId -Command $befehl -TimeOut 120 -ErrorAction Stop
        }
        else {
            $antwort = Invoke-SSHCommand -SessionId $sitzung.SessionId -Command "echo $b64 | base64 -d | sh" -TimeOut 90 -ErrorAction Stop
            ### Fehlt base64 (zum Beispiel BusyBox), das Skript ohne base64 senden
            if (-not (@($antwort.Output) | Where-Object { ([string]$_) -like 'ENDE=*' }) -and (@($antwort.Error) -join ' ') -match 'base64') {
                $befehl = "sh <<'NETCOCKPITEND'`n" + ($skript -replace "`r", '') + "`nNETCOCKPITEND"
                $antwort = Invoke-SSHCommand -SessionId $sitzung.SessionId -Command $befehl -TimeOut 90 -ErrorAction Stop
            }
        }

        ### Rückmeldung zerlegen (Zeilen der Form NAME=Wert; DISK, IP und NIC kommen mehrfach vor)
        $w = @{}
        $platten = [System.Collections.Generic.List[object]]::new()
        $adressen = [System.Collections.Generic.List[object]]::new()
        $karten = [System.Collections.Generic.List[object]]::new()
        foreach ($zeile in @($antwort.Output)) {
            $s = [string]$zeile
            $i = $s.IndexOf('=')
            if ($i -lt 1) { continue }
            $name = $s.Substring(0, $i)
            $wert = $s.Substring($i + 1).Trim()
            $teile = $wert.Split('|')
            switch ($name) {
                'DISK' { if ($teile.Count -ge 3 -and [double]$teile[1] -ge 104857600) { $platten.Add([pscustomobject]@{ Mount = $teile[0]; Gesamt = [double]$teile[1]; Frei = [double]$teile[2] }) } }
                'IP' { if ($teile.Count -ge 2) { $adressen.Add([pscustomobject]@{ Karte = $teile[0]; Adresse = $teile[1].Split('/')[0] }) } }
                'NIC' { if ($teile.Count -ge 3) { $karten.Add([pscustomobject]@{ Karte = $teile[0]; Mac = $teile[1]; Physisch = ($teile[2] -eq '1') }) } }
                default { $w[$name] = $wert }
            }
        }
        if (-not $w.ContainsKey('ENDE')) {
            $err = (@($antwort.Error) -join ' ').Trim()
            throw "Unvollständige Rückmeldung vom Linux-Gerät (Exitcode $($antwort.ExitStatus))$(if ($err) { ': ' + $err })"
        }
        function Zahl($t) { $n = [int]0; [void][int]::TryParse([string]$t, [ref]$n); return $n }

        ### Grunddaten
        $hostVoll = [string]$w['HOST']
        $hostKurz = $hostVoll.Split('.')[0]
        $ramGb = Zahl $w['RAM']
        $kerne = Zahl $w['CORES']
        $cpuName = [string]$w['CPU']
        $os = [string]$w['OS']
        $hersteller = [string]$w['VENDOR']
        $modell = [string]$w['MODEL']
        $seriennummer = [string]$w['SERIAL']

        ### Typ (eine gültige Vorgabe aus der Spalte "Typ" gilt, sonst Erkennung; ein Linux-Gerät ohne Vorgabe ist ein Server)
        $typ = @('Client', 'Server physisch', 'Server virtuell') | Where-Object { $_ -eq $TypVorgabe } | Select-Object -First 1
        if (-not $typ) {
            $virt = [string]$w['VIRT']
            if ($virt -and $virt -ne 'none') { $typ = 'Server virtuell' }
            elseif ("$hersteller $modell" -match 'Virtual Machine|VMware|VirtualBox|innotek|QEMU|\bKVM\b|\bXen\b|HVM domU|Parallels|Nutanix|\bAHV\b|Bochs') { $typ = 'Server virtuell' }
            else { $typ = 'Server physisch' }
        }

        ### MAC: Karte mit der Geräte-IP; ist sie virtuell (zum Beispiel VPN), zählt die einzige aktive physische Karte (mit IPv4-Adresse), bei mehreren bleibt die MAC leer
        $mac = ''
        $eigene = $adressen | Where-Object { $_.Adresse -eq $Ip } | Select-Object -First 1
        if ($eigene) {
            $karte = $karten | Where-Object { $_.Karte -eq $eigene.Karte } | Select-Object -First 1
            if ($karte -and $karte.Physisch) { $mac = $karte.Mac }
            else {
                $physisch = @($karten | Where-Object { $k = $_; $_.Physisch -and @($adressen | Where-Object { $_.Karte -eq $k.Karte }).Count -gt 0 })
                if ($physisch.Count -eq 1) { $mac = $physisch[0].Mac }
            }
        }

        ### IP-Adressen, Laufwerke, Laufzeit, Updates, Rollen
        $ipNamen = (@($adressen | ForEach-Object { '{0}: {1}' -f $_.Karte, $_.Adresse })) -join ', '
        $ipNur = (@($adressen | ForEach-Object { $_.Adresse })) -join ', '
        $hddClient = (@($platten | ForEach-Object { '{0}:{1}GB' -f $_.Mount, [math]::Round($_.Gesamt / 1GB, 0) })) -join '; '
        $hddServer = (@($platten | ForEach-Object { '{0}:{1}' -f $_.Mount, [math]::Round([math]::Round($_.Gesamt / 1TB, 2) * 1000, 0) })) -join '; '
        $laufwerke = @($platten | ForEach-Object { [pscustomobject]@{ Laufwerk = $_.Mount; Frei = [math]::Round($_.Frei / 1GB, 0); Gesamt = [math]::Round($_.Gesamt / 1GB, 0) } })
        $laufzeit = ''
        if ($w.ContainsKey('UPSEC') -and $w['UPSEC']) {
            $ts = [timespan]::FromSeconds([double](Zahl $w['UPSEC']))
            $laufzeit = '{0} Tage, {1} Std., {2} Min.' -f $ts.Days, $ts.Hours, $ts.Minutes
        }
        $updates = 'nicht ermittelbar'
        if ($w.ContainsKey('UPD') -and $w['UPD'] -ne '') { $updates = '{0} (nach Stand der Paketlisten)' -f (Zahl $w['UPD']) }

        $rollenText = 'nicht ermittelbar'
        if ($w.ContainsKey('SVC')) {
            $dienste = @(([string]$w['SVC']).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_ -replace '\.service$', '' })
            $rollen = [ordered]@{
                'Webserver'            = 'apache2|httpd|nginx|lighttpd|caddy'
                'Datenbank'            = 'mysql|mysqld|mariadb|postgresql|mongod'
                'File Server'          = 'smbd|smb|nfs-server|nfsd'
                'DNS Server'           = 'named|bind9|unbound|pdns|dnsmasq'
                'DHCP Server'          = 'isc-dhcp-server|dhcpd|kea-dhcp4-server|kea-dhcp4'
                'Mail Server'          = 'postfix|exim4|exim|dovecot'
                'Print Server'         = 'cups|cupsd'
                'Virtualisierung'      = 'libvirtd|virtqemud|pveproxy'
                'Container (Docker)'   = 'docker|podman'
            }
            $gefunden = [System.Collections.Generic.List[string]]::new()
            foreach ($anzeige in $rollen.Keys) {
                if (@($dienste | Where-Object { $_ -match ('^(?:' + $rollen[$anzeige] + ')$') }).Count -gt 0) { $gefunden.Add($anzeige) }
            }
            if ($gefunden.Count -gt 0) { $rollenText = $gefunden -join ', ' } else { $rollenText = 'Keine relevanten Rollen erkannt' }
        }

        if ($esxi) { $rollenText = 'Virtualisierung (ESXi)' }

        function Feld($n, $v) { [pscustomobject]@{ Name = $n; Wert = [string]$v } }
        $extra = @(
            Feld 'Kernel' $w['KERNEL']
            Feld 'Letzter Start' $w['BOOT']
            Feld 'Laufzeit' $laufzeit
            Feld 'Ausstehende Updates' $updates
        )

        ### Felder je Typ (Namen und Reihenfolge wie beim Windows-Block; Windows-spezifische und ohne Root nicht lesbare Felder bleiben leer)
        if ($typ -eq 'Client') {
            $felder = @(
                Feld 'Hostname' $hostKurz
                Feld 'Hersteller' $hersteller
                Feld 'Modell' $modell
                Feld 'Betriebssystem' $os
                Feld 'CPU' $cpuName
                Feld 'RAM (GB)' $ramGb
                Feld 'HDD (GB)' $hddClient
                Feld 'Seriennummer' $seriennummer
                Feld 'Installationsdatum' ''
            ) + $extra
            $fussnote = 'Linux-Gerät: ohne Root gelesen, leere Felder sind unter Linux nicht ermittelbar.'
        }
        elseif ($typ -eq 'Server physisch') {
            $felder = @(
                Feld 'Hostname' $hostVoll
                Feld 'Hersteller' $hersteller
                Feld 'Modell' $modell
                Feld 'IP-Adressen' $ipNamen
                Feld 'Betriebssystem' $os
                Feld 'Server Rollen*' $rollenText
                Feld 'CPU' ('{0} ({1} Cores)' -f $cpuName, $kerne)
                Feld 'RAM (GB)' $ramGb
                Feld 'HDD (GB)' $hddServer
                Feld 'RAID' 'Nicht ermittelt'
                Feld 'Seriennummer' $seriennummer
                Feld 'OS Install Date' ''
                Feld 'Notizen' ''
            ) + $extra
            $fussnote = '*Es werden nur die wichtigsten Rollen ermittelt. Linux-Gerät: ohne Root gelesen, leere Felder sind unter Linux nicht ermittelbar.'
        }
        else {
            $felder = @(
                Feld 'Name' $hostVoll
                Feld 'IP-Adresse' $ipNur
                Feld 'Betriebssystem' $os
                Feld 'Server Rollen*' $rollenText
                Feld 'CPU (Cores)' $kerne
                Feld 'RAM (GB)' $ramGb
                Feld 'HDD (GB)' $hddServer
                Feld 'Notizen' ''
            ) + $extra
            $fussnote = '*Es werden nur die wichtigsten Rollen ermittelt. Linux-Gerät: ohne Root gelesen, leere Felder sind unter Linux nicht ermittelbar.'
        }
        if ($esxi) { $fussnote = 'ESXi-Host: per esxcli gelesen; Laufwerke sind die Datenspeicher (VMFS, NFS, vSAN). Updates und Letzter Start sind nicht ermittelbar.' }
        [pscustomobject]@{ Erfolg = $true; Typ = [string]$typ; Felder = @($felder); Laufwerke = @($laufwerke); Fussnote = $fussnote; Fehler = ''; Hostname = $hostVoll; Mac = [string]$mac }
    }
    catch {
        [pscustomobject]@{ Erfolg = $false; Typ = ''; Felder = @(); Laufwerke = @(); Fussnote = ''; Fehler = $_.Exception.Message; Hostname = ''; Mac = '' }
    }
    finally { if ($sitzung) { [void](Remove-SSHSession -SSHSession $sitzung -ErrorAction SilentlyContinue) } }
}

# Herstellerliste-Block
## Läuft als Thread-Job: lädt die Liste (zuerst IEEE, dann Wireshark) und speichert sie einheitlich als CSV
$script:OuiBlock = {
    param([string]$Pfad)
    $fehler = @()
    $tmp = "$Pfad.tmp"

    # IEEE (zwei Versuche: ohne und mit Browser-Kennung)
    foreach ($ua in @('', 'Mozilla/5.0')) {
        try {
            $p = @{ Uri = 'https://standards-oui.ieee.org/oui/oui.csv'; OutFile = $tmp; TimeoutSec = 60; ErrorAction = 'Stop' }
            if ($ua) { $p.UserAgent = $ua }
            Invoke-WebRequest @p
            Move-Item -Path $tmp -Destination $Pfad -Force
            return [pscustomobject]@{ Quelle = 'IEEE'; Anzahl = @(Import-Csv -Path $Pfad).Count; Fehler = ($fehler -join ' | ') }
        }
        catch { $fehler += "IEEE: $($_.Exception.Message)" }
    }
    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue

    # Wireshark (nur Einträge mit 3-Byte-Präfix ohne Maske)
    try {
        $inhalt = (Invoke-WebRequest -Uri 'https://gitlab.com/wireshark/wireshark/-/raw/master/manuf' -TimeoutSec 60 -ErrorAction Stop).Content
        $liste = foreach ($zeile in ($inhalt -split "`n")) {
            if ($zeile.StartsWith('#') -or -not $zeile.Trim()) { continue }
            $f = $zeile.TrimEnd("`r").Split("`t")
            if ($f.Count -ge 2 -and $f[0] -match '^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$') {
                $name = if ($f.Count -ge 3 -and $f[2]) { $f[2] } else { $f[1] }
                [pscustomobject]@{ Assignment = ($f[0] -replace ':', '').ToUpper(); 'Organization Name' = $name }
            }
        }
        $liste | Export-Csv -Path $Pfad -NoTypeInformation -Encoding utf8
        return [pscustomobject]@{ Quelle = 'Wireshark'; Anzahl = @($liste).Count; Fehler = ($fehler -join ' | ') }
    }
    catch { $fehler += "Wireshark: $($_.Exception.Message)" }

    return [pscustomobject]@{ Quelle = ''; Anzahl = 0; Fehler = ($fehler -join ' | ') }
}

# Statusprüfung-Block
## Läuft als Thread-Job: Ping und WinRM-Port für alle bekannten IP-Adressen der Geräteliste
$script:StatusBlock = {
    param([string[]]$Ips, [int]$Drossel)
    @($Ips | ForEach-Object -ThrottleLimit $Drossel -Parallel {
        $ip = $_
        $online = $false
        $winrm = $false
        $ping = [System.Net.NetworkInformation.Ping]::new()
        try {
            $antwort = $ping.Send($ip, 700)
            $online = ($antwort -and $antwort.Status -eq 'Success')
        } catch { } finally { $ping.Dispose() }
        if ($online) {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            try {
                $task = $tcp.ConnectAsync($ip, 5985)
                $winrm = ($task.Wait(700) -and $tcp.Connected)
            } catch { } finally { $tcp.Dispose() }
        }
        [pscustomobject]@{ IP = $ip; Online = $online; WinRM = $winrm }
    })
}

# Portscan-Block
## Läuft als Thread-Job je Gerät: TCP-Verbindungstest in Blöcken zu 2048 Ports, Fortschritt über $Status
$script:PortBlock = {
    param([string]$Ip, [int[]]$Ports, [int]$Drossel, $Status)
    $offen = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $Ports.Count; $i += 2048) {
        if ($Status.Abbruch) { break }
        $ende = [math]::Min($i + 2047, $Ports.Count - 1)
        $teil = $Ports[$i..$ende]
        $treffer = @($teil | ForEach-Object -ThrottleLimit $Drossel -Parallel {
            $port = $_
            $tcp = [System.Net.Sockets.TcpClient]::new()
            try {
                $task = $tcp.ConnectAsync($using:Ip, $port)
                if ($task.Wait(500) -and $tcp.Connected) { $port }
            } catch { } finally { $tcp.Dispose() }
        })
        foreach ($t in $treffer) { $offen.Add([int]$t) }
        $Status.Fertig = $ende + 1
    }
    [pscustomobject]@{ Offen = @($offen | Sort-Object); Abgebrochen = [bool]$Status.Abbruch }
}

# Dialoge
## Texteingabe
function Show-WolEingabe {
    param([string]$Titel, [string]$Frage, [string]$Vorgabe = '', [string]$Hinweis = '')
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="560" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="Frage" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <TextBox x:Name="Eingabe" Margin="0,0,0,8"/>
    <TextBlock x:Name="Hinweis" TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,12" Visibility="Collapsed"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Ok" Content="OK" Width="80" IsDefault="True" Margin="0,0,8,0"/>
      <Button x:Name="Abbruch" Content="Abbrechen" Width="80" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $d.Title = $Titel
    $d.Owner = $script:Fenster
    $d.FindName('Frage').Text = $Frage
    if ($Hinweis) {
        $d.FindName('Hinweis').Text = $Hinweis
        $d.FindName('Hinweis').Visibility = 'Visible'
    }
    $eingabe = $d.FindName('Eingabe')
    $eingabe.Text = $Vorgabe
    $d.FindName('Ok').Add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $eingabe.Focus() | Out-Null
    if ($d.ShowDialog()) { return $eingabe.Text }
    return $null
}

## Optionen (Auto-Scan, Statusprüfung, automatisches Speichern, Parallelität); Ergebnis: Objekt oder $null bei Abbruch
function Show-WolOptionen {
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Optionen" Width="560" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
      <CheckBox x:Name="ChkA" Content="Auto-Scan alle" VerticalAlignment="Center"/>
      <TextBox x:Name="TxtA" Width="50" Margin="8,0,6,0" VerticalContentAlignment="Center"/>
      <TextBlock Text="Minuten" VerticalAlignment="Center"/>
    </StackPanel>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
      <CheckBox x:Name="ChkS" Content="Status der Geräteliste prüfen alle" VerticalAlignment="Center"/>
      <TextBox x:Name="TxtS" Width="50" Margin="8,0,6,0" VerticalContentAlignment="Center"/>
      <TextBlock Text="Minuten" VerticalAlignment="Center"/>
    </StackPanel>
    <CheckBox x:Name="ChkG" Content="Geräteliste automatisch speichern (nach Scan, Statusprüfung und Portscan)" Margin="0,0,0,10"/>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
      <TextBlock Text="Parallelität: höchstens" VerticalAlignment="Center"/>
      <TextBox x:Name="TxtP" Width="50" Margin="8,0,6,0" VerticalContentAlignment="Center"/>
      <TextBlock Text="Geräte gleichzeitig" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock Text="Gilt für Neustart, Herunterfahren, PowerShell-Befehl, KuDo-Informationen und die Update-Module. Weitere Geräte warten in der Warteschlange." Foreground="DimGray" TextWrapping="Wrap" Margin="0,0,0,14"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Ok" Content="OK" Width="80" IsDefault="True" Margin="0,0,8,0"/>
      <Button x:Name="Abbruch" Content="Abbrechen" Width="80" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $d.Owner = $script:Fenster
    $d.FindName('ChkA').IsChecked = [bool]$script:Opt.AutoScan
    $d.FindName('TxtA').Text = [string]$script:Opt.AutoMin
    $d.FindName('ChkS').IsChecked = [bool]$script:Opt.Status
    $d.FindName('TxtS').Text = [string]$script:Opt.StatusMin
    $d.FindName('ChkG').IsChecked = [bool]$script:Opt.AutoSpeichern
    $d.FindName('TxtP').Text = [string]$script:Opt.Parallel
    $d.FindName('Ok').Add_Click({
        $f = [System.Windows.Window]::GetWindow($this)
        $m = 0
        if (-not [int]::TryParse($f.FindName('TxtA').Text, [ref]$m) -or $m -lt 1 -or -not [int]::TryParse($f.FindName('TxtS').Text, [ref]$m) -or $m -lt 1) {
            [void][System.Windows.MessageBox]::Show($f, 'Bitte bei beiden Zeiten ganze Minuten ab 1 eingeben.', 'Optionen', 'OK', 'Warning')
            return
        }
        if (-not [int]::TryParse($f.FindName('TxtP').Text, [ref]$m) -or $m -lt 1 -or $m -gt 50) {
            [void][System.Windows.MessageBox]::Show($f, 'Bitte bei der Parallelität eine ganze Zahl von 1 bis 50 eingeben.', 'Optionen', 'OK', 'Warning')
            return
        }
        $f.DialogResult = $true
    })
    if (-not $d.ShowDialog()) { return $null }
    return [pscustomobject]@{
        AutoScan      = [bool]$d.FindName('ChkA').IsChecked
        AutoMin       = $d.FindName('TxtA').Text.Trim()
        Status        = [bool]$d.FindName('ChkS').IsChecked
        StatusMin     = $d.FindName('TxtS').Text.Trim()
        AutoSpeichern = [bool]$d.FindName('ChkG').IsChecked
        Parallel      = [int]$d.FindName('TxtP').Text.Trim()
    }
}

## Anmeldedaten für WinRM; liefert $null (Abbruch oder kein Benutzername), 'zurueck' oder ein Objekt mit UserName und Password (SecureString, bei leerem Kennwortfeld $null); -Benutzer belegt den Benutzernamen vor
function Show-WolAnmeldung {
    param(
        [string]$Benutzer = '',
        [string]$Titel = 'Konto für markierte Geräte',
        [string]$Text = 'Mit welchem Konto sollen die markierten Geräte angesprochen werden? Benutzername als Domäne\Benutzer, .\Benutzer (lokales Konto des Geräts) oder als UPN.',
        [string]$ZurueckText = 'Mit aktuellem Konto verbinden'
    )
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Anderes Konto verwenden" Width="540" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="Frage" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <TextBlock Text="Benutzername" Margin="0,0,0,2"/>
    <TextBox x:Name="Benutzer" Margin="0,0,0,8"/>
    <TextBlock Text="Kennwort" Margin="0,0,0,2"/>
    <PasswordBox x:Name="Kennwort" Margin="0,0,0,12"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Ok" Content="OK" Width="80" IsDefault="True" Margin="0,0,8,0"/>
      <Button x:Name="Zurueck" Content="Mit aktuellem Konto verbinden" Padding="10,0" Margin="0,0,8,0"/>
      <Button x:Name="Abbruch" Content="Abbrechen" Width="80" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $d.Owner = $script:Fenster
    $d.Title = $Titel
    $d.FindName('Frage').Text = $Text
    $d.FindName('Zurueck').Content = $ZurueckText
    $d.FindName('Benutzer').Text = $Benutzer
    $d.Add_ContentRendered({
        $b = $this.FindName('Benutzer')
        if ($b.Text) { $this.FindName('Kennwort').Focus() | Out-Null } else { $b.Focus() | Out-Null }
    })
    $script:DlgModus = ''
    $d.FindName('Ok').Add_Click({ $script:DlgModus = 'ok'; [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $d.FindName('Zurueck').Add_Click({ $script:DlgModus = 'zurueck'; [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    if (-not $d.ShowDialog()) { return $null }
    if ($script:DlgModus -eq 'zurueck') { return 'zurueck' }
    $benutzer = $d.FindName('Benutzer').Text.Trim()
    $kennwort = $d.FindName('Kennwort').SecurePassword
    if (-not $benutzer) { return $null }
    return [pscustomobject]@{ UserName = $benutzer; Password = $(if ($kennwort.Length -gt 0) { $kennwort } else { $null }) }
}

## Kennwort für ein Gerätekonto abfragen; Rückgabe: SecureString oder $null bei Abbruch
function Show-WolKennwort {
    param([string]$Benutzer, [string]$Geraete, $Besitzer)
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kennwort eingeben" Width="470" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="Frage" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <PasswordBox x:Name="Kennwort" Margin="0,0,0,12"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Ok" Content="OK" Width="80" IsDefault="True" Margin="0,0,8,0"/>
      <Button x:Name="Abbruch" Content="Abbrechen" Width="80" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    if ($Besitzer) { $d.Owner = $Besitzer } else { $d.Owner = $script:Fenster }
    $d.FindName('Frage').Text = "Kennwort für das Konto $Benutzer (Geräte: $Geraete)"
    $d.FindName('Ok').Add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    if (-not $d.ShowDialog()) { return $null }
    $kennwort = $d.FindName('Kennwort').SecurePassword
    if ($kennwort.Length -eq 0) { return $null }
    return $kennwort
}

## Info / Voraussetzungen (Reiter mit Suche)
### Inhalt der Info: Reiter mit Blöcken (h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten, a = Ampelzeile); die Reiter folgen der Menüleiste; der Reiter Module hat eine Auswahlleiste mit der Hilfe je Modul
function Get-WolInfoInhalt {
    $inhalt = [System.Collections.Generic.List[object]]::new()

    $inhalt.Add(@{ Titel = 'Überblick'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das NET-COCKPIT?' }
        @{ T = 'p'; X = 'Das Cockpit sammelt Geräte in einer **Geräteliste** (per Scan, aus einer OU oder aus einer geladenen Datei) und bietet **Neustart**, **Neustart planen**, **Herunterfahren**, **Portscan**, **Dauerping**, **PowerShell-Befehle**, die **KuDo-Informationen**, **Neuer Client** und **Einzel-Scan** und im Menü **Module** die Module für OS-, APP- und Treiber-Updates sowie die **Diagnose** (Ereignislog, Dienste, Prozesse), **WaToKi** (Wartungsskripte starten), **M365-Wartungs-App** (Wartungs-App im Kunden-Tenant anlegen) und **WOL** (Wake-on-LAN prüfen, einrichten und Geräte aufwecken).' }
        @{ T = 'h'; X = 'Typischer Ablauf' }
        @{ T = 'i'; X = '**1. Liste bereitstellen:** Datei > Neue Liste (leer anfangen), Datei > Öffnen, Datei > OU wählen oder ein Netz wählen und scannen. Das Cockpit startet immer leer.' }
        @{ T = 'i'; X = '**2. Geräte markieren:** Zeilen anklicken wie im Explorer (Strg+Klick, Umschalt+Klick, Ziehen, Strg+A).' }
        @{ T = 'i'; X = '**3. Aktion wählen:** Menü Aktionen, Module oder Werkzeuge. Aktionen wirken nur auf markierte, sichtbare Geräte.' }
        @{ T = 'h'; X = 'Ampel' }
        @{ T = 'a'; C = 'LimeGreen'; X = '**Grün:** Ping und WinRM (TCP 5985) erreichbar' }
        @{ T = 'a'; C = 'Gold'; X = '**Gelb:** nur Ping erreichbar (Nicht-Windows-Gerät oder Windows ohne WinRM)' }
        @{ T = 'a'; C = 'Red'; X = '**Rot:** nicht per Ping erreichbar (offline oder Ping blockiert)' }
        @{ T = 'a'; C = 'Gray'; X = '**Grau:** noch nicht geprüft' }
        @{ T = 'h'; X = 'Aufbau des Fensters' }
        @{ T = 'i'; X = '**Menüleiste:** Datei, Aktionen, Module, Werkzeuge, Ansicht, Optionen und Hilfe.' }
        @{ T = 'i'; X = '**Scan-Bereich:** Netzauswahl und die Knöpfe "Scan starten" und "Scan stoppen".' }
        @{ T = 'i'; X = '**Tabelle:** alle Geräte, unter jeder Spaltenüberschrift ein Filterfeld. **Log** und die Anzeige der Geräteliste stehen darunter.' }
    ) })

    $inhalt.Add(@{ Titel = 'Scan & Status'; Bloecke = @(
        @{ T = 'h'; X = 'Scanbereich' }
        @{ T = 'i'; X = '**Aktuelles Netz verwenden:** nimmt das Netz der aktiven Netzwerkkarte mit Gateway. Es wird nichts von selbst gewählt oder gescannt.' }
        @{ T = 'i'; X = '**Anderes Netz eingeben:** Netze (Netzadresse/Präfixlänge, /22 bis /30), IP-Bereiche (von-bis) und einzelne IP-Adressen, mehrere mit Komma getrennt, insgesamt höchstens 1024 Adressen.' }
        @{ T = 'w'; X = 'MAC-Adresse und Hersteller kommen aus der ARP-Tabelle und gibt es nur im eigenen Subnetz. Ohne MAC ist kein Aufwecken möglich.' }
        @{ T = 'h'; X = 'Scan' }
        @{ T = 'i'; X = '**Scan starten:** scannt sofort. Ist der Auto-Scan aktiv, wiederholt sich der Scan danach im eingestellten Abstand. **Scan stoppen** bricht ab und hält den Auto-Scan an.' }
        @{ T = 'i'; X = '**Was der Scan einträgt:** Er sucht neue Geräte und trägt sie ein. Die Zuordnung zu bekannten Geräten läuft über die MAC-Adresse; dabei aktualisiert er IP, Hostname und Hersteller. Eine Zeile ohne MAC mit derselben IP (zum Beispiel aus der OU) wird mit der gefundenen MAC-Zeile zusammengeführt. Steht eine IP jetzt bei einem Gerät mit anderer MAC, wird sie beim alten Eintrag entfernt (Status "IP veraltet"); Hostname, MAC und Bemerkung bleiben. Neue Geräte meldet die orange Statuszeile.' }
        @{ T = 'h'; X = 'Statusprüfung' }
        @{ T = 'p'; X = 'Sie prüft alle Geräte der Geräteliste per Ping und WinRM (Port 5985) auf ihrer gespeicherten IP-Adresse und setzt die Ampel. Sie läuft nach dem Öffnen einer Liste und danach im eingestellten Abstand; ohne Liste gibt es nichts zu prüfen.' }
        @{ T = 'w'; X = 'Wechselt ein Gerät die IP per DHCP, erscheint es bis zum nächsten Scan als offline. Findet der Scan es unter der neuen IP über seine MAC wieder, wird die IP aktualisiert.' }
    ) })

    $inhalt.Add(@{ Titel = 'Tabelle'; Bloecke = @(
        @{ T = 'h'; X = 'Filter und Anzeige' }
        @{ T = 'i'; X = '**Spaltenfilter:** Das Feld unter der Überschrift filtert diese Spalte nach Teiltext (Groß-/Kleinschreibung egal). Mehrere Filter gelten gleichzeitig. Ein Sternchen (*) steht für beliebig viele, ein Fragezeichen (?) für genau ein Zeichen. Nur * zeigt alle Zeilen mit Inhalt in der Spalte, nur ! alle mit leerer Spalte. **Ausschluss:** ein Ausrufezeichen vor dem Text zeigt alles, was den Text nicht enthält (zum Beispiel !2012 in der Bemerkung; Zeilen mit leerer Spalte bleiben sichtbar). Platzhalter gehen auch dort.' }
        @{ T = 'i'; X = '**Waagerecht scrollen:** sind mehr Spalten eingeblendet, als ins Fenster passen, erscheint unten ein Scrollbalken; die Spalten behalten ihre Breite (Spaltenbreite per Ziehen an der Überschrift änderbar).' }
        @{ T = 'i'; X = '**Gespeicherte Werte:** was die Module (OS, APP, Treiber, WOL) über ein Gerät auslesen, bleibt erhalten und steht nach dem Laden der Liste sofort wieder in den Spalten: Windows-Version, WinGet-Modul und -Version, WAU, Update-Modul, PC-Hersteller, Modell, Treiber-Tool und die WOL-Werte. Zugeordnet wird über die MAC-Adresse, sonst über die IP. Die Spalte **Werte gelesen am** (standardmäßig ausgeblendet) zeigt, wann zuletzt gelesen wurde. Nicht gespeichert werden Letzter Neustart, Neustart ausstehend und die Anzahl der Updates, weil sich diese Werte laufend ändern. Ein neues "Status prüfen" überschreibt die gespeicherten Werte.' }
        @{ T = 'i'; X = '**Filter löschen:** leert alle Filterfelder. **Anzeigen:** Alle (auch grau = noch nicht geprüft), Nur WinRM (grün), Online Geräte (grün und gelb) oder Offlinegeräte (rot). Bei den letzten drei sind graue Geräte ausgeblendet. Gilt für Anzeige, Markieren und Export und wird gespeichert.' }
        @{ T = 'i'; X = '**Sortieren:** per Klick auf den Spaltennamen. Beim Start nach IP in Zahlenreihenfolge.' }
        @{ T = 'h'; X = 'Spalten ein- und ausblenden' }
        @{ T = 'i'; X = '**Rechtsklick auf eine Spaltenüberschrift** (auf den Namen, nicht auf das Filterfeld) oder **Ansicht > Spalten:** Haken setzen oder entfernen. Die Auswahl wird gespeichert (Spalten der Module ausgenommen). Beim Ausblenden wird der Filter dieser Spalte geleert.' }
        @{ T = 'i'; X = '**Spalten der Module** (zum Beispiel Windows-Version oder Neustart ausstehend) sind nur sichtbar, wenn im Modulfenster der Haken **Spalten des Moduls in der Tabelle anzeigen** gesetzt ist (beim Öffnen immer aus), und werden beim Schließen des Fensters wieder ausgeblendet. Die Werte bleiben in den Zeilen erhalten. Sie werden nicht gespeichert; Ausnahme ist die Spalte **Wartungsreihenfolge** des Moduls WaToKi, sie wird mit der Geräteliste gespeichert.' }
        @{ T = 'h'; X = 'Markieren und Bearbeiten' }
        @{ T = 'i'; X = '**Alle / Keine / Nur Online markieren** stehen über der Tabelle, **Markierte aus Liste entfernen** im Menü Werkzeuge.' }
        @{ T = 'i'; X = '**Hostname, Typ, MAC und Bemerkung** lassen sich direkt in der Tabelle bearbeiten (Doppelklick in die Zelle), bei geöffnetem Modul WaToKi auch die **Wartungsreihenfolge**.' }
        @{ T = 'i'; X = '**MAC von Hand eintragen oder ändern:** erlaubt sind 00:20:6b:f4:cd:28, 00-20-6b-f4-cd-28 und 00206bf4cd28; gespeichert und angezeigt wird sie als 00:20:6B:F4:CD:28. Eine MAC, die schon in einer anderen Zeile steht, wird abgelehnt (Esc verwirft die Eingabe). Der Hersteller wird neu aus der Herstellerliste bestimmt; eine geleerte MAC leert auch den Hersteller. Gedacht für Geräte, deren MAC nicht automatisch ermittelt werden kann (zum Beispiel Drucker in einem anderen Netz).' }
        @{ T = 'i'; X = '**Doppelklick auf "Aktion / Status"** öffnet das Log dieses Geräts: die Zeilen des Cockpit-Logs und die Logs der Module APP, OS und Treiber, nur für dieses Gerät (mit Aktualisieren).' }
        @{ T = 'i'; X = '**Doppelklick auf ein Gerät** (in allen anderen Spalten als den bearbeitbaren und Aktion / Status) öffnet das Detailfenster mit allen Infos, den offenen Ports, der Bemerkung und den gespeicherten KuDo-Informationen.' }
        @{ T = 'h'; X = 'Besondere Spalten' }
        @{ T = 'i'; X = '**Typ:** frei editierbar. Beim Auslesen der KuDo-Informationen trägt das Cockpit den erkannten Typ ein, aber nur, wenn die Zelle leer ist.' }
        @{ T = 'i'; X = '**Konto:** das Konto, mit dem das Gerät per WinRM angesprochen wird (bei Linux-Geräten der SSH-Benutzer). Ohne eigenes Konto steht dort das Konto, mit dem Du angemeldet bist. Gespeichert wird nur der Benutzername, nie das Kennwort.' }
        @{ T = 'i'; X = '**Offene Ports:** Ergebnis des Portscans, wird mitgespeichert. **Aktion / Status:** zeigt die letzte Aktion; "ausgelöst" heißt nur, dass der Befehl angenommen wurde.' }
    ) })

    $inhalt.Add(@{ Titel = 'Geräteliste'; Bloecke = @(
        @{ T = 'h'; X = 'Menü Datei' }
        @{ T = 'i'; X = '**Öffnen...:** lädt eine Geräteliste (Semikolon-getrennte Textdatei) und merkt sich den Pfad. Danach läuft die Statusprüfung.' }
        @{ T = 'i'; X = '**Speichern:** schreibt in die bekannte Datei. Ist noch keine bekannt, fragt das Cockpit nach Dateiname und Ort. **Speichern unter...:** speichert unter einem neuen Namen.' }
        @{ T = 'i'; X = '**OU wählen...:** zeigt die OUs der Domäne (LDAP, kein RSAT nötig). Die Computer der gewählten OU werden der Tabelle hinzugefügt (bereits vorhandene Namen nicht doppelt) und per DNS aufgelöst.' }
        @{ T = 'i'; X = '**Exportieren...:** schreibt die sichtbaren oder markierten Zeilen mit wählbaren Feldern (Tabellenspalten und gespeicherte KuDo-Felder) als Textdatei.' }
        @{ T = 'h'; X = 'Speichern' }
        @{ T = 'i'; X = '**Auto-Speichern** (Optionen) schreibt nach Scan, Statusprüfung und Portscan, aber nur in die bekannte Datei. Ohne bekannte Datei bleibt es still, im Log steht ein Hinweis.' }
        @{ T = 'i'; X = 'Beim Beenden und beim Öffnen einer anderen Liste fragt das Cockpit bei ungespeicherten Änderungen nach; ohne bekannte Datei mit Dateidialog.' }
        @{ T = 'h'; X = 'Datenordner' }
        @{ T = 'p'; X = 'Alles, was das Cockpit selbst ablegt, liegt in **C:\Temp\NET-COCKPIT_data** (wird beim Start angelegt): **NET-COCKPIT.log** (bei jedem Start geleert), **NET-COCKPIT-oui.csv** (Herstellerliste), **NET-COCKPIT-einstellungen.json** (Optionen und Spalten), **NET-COCKPIT-werte.json** (die von den Modulen ausgelesenen Werte je Gerät) und der Unterordner **Geraeteinfos** mit den KuDo-Informationen je Gerät. Die Ausgaben der Wartungsskripte (Modul WaToKi) liegen im Unterordner **Modul-WaToKi**.' }
        @{ T = 'i'; X = '**Optionen > NET-COCKPIT Daten löschen...:** löscht nach einer Rückfrage den ganzen Ordner und beendet das Cockpit. Listen an anderen Orten und Exporte bleiben. Lässt sich etwas nicht löschen (Datei gesperrt), bleibt das Cockpit offen und nennt die betroffenen Dateien. Der nächste Start ist ein normaler Erststart.' }
    ) })

    $inhalt.Add(@{ Titel = 'Aktionen'; Bloecke = @(
        @{ T = 'h'; X = 'Aufwecken' }
        @{ T = 'i'; X = '**Aufwecken** sitzt im Modul **WOL** (Menü Module > WOL), dort auch die Einrichtung von Wake-on-LAN.' }
        @{ T = 'h'; X = 'Neustart und Herunterfahren (per WinRM, nur bei Grün)' }
        @{ T = 'i'; X = '**Neustart / Herunterfahren:** fragt die Verzögerung in Sekunden ab (vorausgefüllt 60, 0 = sofort), danach eine Sicherheitsabfrage.' }
        @{ T = 'i'; X = '**Neustart planen...:** Datum und Uhrzeit wählen (nach der Uhr des Zielgeräts). Auf dem Gerät entsteht die Aufgabe "NetCockpitNeustart" (als SYSTEM). Benutzer erhalten 5 Minuten vorher einen Hinweis. Die Aufgabe läuft ohne das Cockpit. Nach dem Termin prüft das Cockpit, sobald das Gerät wieder grün ist, ob der Neustart stattgefunden hat.' }
        @{ T = 'i'; X = '**Neustart abbrechen:** löscht eine geplante Aufgabe und stoppt einen laufenden Neustart oder ein laufendes Herunterfahren (innerhalb der Verzögerung).' }
        @{ T = 'h'; X = 'Parallelität' }
        @{ T = 'p'; X = 'Aufträge an mehrere Geräte laufen höchstens so viele gleichzeitig, wie in Optionen > Einstellungen steht (Standard 10). Die übrigen Geräte warten in der Warteschlange; ihr Status zeigt "wartet".' }
    ) })

    $inhalt.Add(@{ Titel = 'Werkzeuge'; Bloecke = @(
        @{ T = 'h'; X = 'Dauerping' }
        @{ T = 'i'; X = '**Dauerping:** eigenes Fenster mit einem Tab je markiertem Gerät (ein Ping pro Sekunde, Timeouts blass); höchstens 20 Geräte. Das "x" im Tab beendet den Ping dieses Geräts.' }
        @{ T = 'h'; X = 'Einzel-Scan' }
        @{ T = 'i'; X = '**Einzel-Scan für markierte Geräte:** prüft die markierten Geräte (eins oder mehrere) neu: Ping, WinRM-Port, Hostname per DNS, MAC aus der ARP-Tabelle (nur im eigenen Subnetz) und Hersteller. Ampel und Status werden gesetzt, Hostname, MAC und Hersteller nur ergänzt, wenn sie leer sind.' }
        @{ T = 'h'; X = 'KuDo-Informationen auslesen' }
        @{ T = 'i'; X = '**KuDo-Informationen auslesen:** liest die Geräteinformationen der markierten Geräte aus. Das Cockpit prüft dafür je Gerät live die Ports: Ist WinRM (5985) offen, gilt das Gerät als Windows, auch wenn SSH ebenfalls offen ist. Sonst gilt es bei offenem SSH-Port 22 als Linux. Rote Geräte und Geräte, bei denen beide Ports zu sind, werden übersprungen. Das Ergebnis steht im Log und in der orangen Statuszeile; ein Fehler zeigt kurz die Spalte "Aktion / Status", der volle Text steht in der Logdatei.' }
        @{ T = 'i'; X = '**Hostname, MAC und Hersteller:** werden beim Auslesen in die Tabelle ergänzt, aber nur in leere Zellen; vorhandene Werte werden nie überschrieben. Die MAC kommt vom Adapter mit der Geräte-IP. Virtuelle Adapter (zum Beispiel VPN) zählen nicht: Dann gilt die MAC des einzigen aktiven physischen Adapters, bei mehreren bleibt das Feld leer. Eine MAC, die schon in einer anderen Zeile steht, wird nicht eingetragen. Der Hersteller kommt aus der Herstellerliste. Geräte ohne Hostname werden per IP angesprochen, dafür fragt das Cockpit Konto und Kennwort ab.' }
        @{ T = 'i'; X = '**Typ:** Client (kein Server-Betriebssystem), Server virtuell (Hersteller oder Modell weist auf Hyper-V, VMware, VirtualBox, QEMU/KVM, Xen, Parallels oder Nutanix AHV hin), sonst Server physisch. Steht in der Spalte "Typ" schon Client, Server physisch oder Server virtuell, gilt dieser Typ. Ein vorhandener Eintrag wird nie überschrieben.' }
        @{ T = 'i'; X = '**Anzeige:** im Detailfenster (Doppelklick) mit "Kopieren" je Wert (außer beim freien Speicher der Laufwerke, bei Clients und Servern: dort stehen Text und Balken, der Balken zeigt den belegten Anteil und wird ab 90 % rot). Geänderte Felder gegenüber der vorherigen Auslesung stehen orange mit dem alten Wert. Die Ergebnisse liegen im Datenordner und sind beim nächsten Start wieder da.' }
        @{ T = 'i'; X = '**Linux-Geräte:** brauchen das PowerShell-Modul Posh-SSH auf dem Rechner mit dem Cockpit (fehlt es, fragt das Cockpit, ob es für dein Benutzerkonto installiert werden soll: Install-Module -Name Posh-SSH -Scope CurrentUser; dafür braucht dieser Rechner Internet) und in der Spalte "Konto" einen Benutzer mit SSH-Zugang (root hat meist keinen). Die Anmeldung läuft nur mit Kennwort. Vor dem Auslesen testet das Cockpit die Anmeldung. Bei einer Herausforderung (Kennwort, Benutzer, Port, Hostschlüssel) fragt es: Ja = Gerät überspringen und weitermachen, Nein = das gesamte Auslesen abbrechen. Der Hostschlüssel wird beim ersten Kontakt automatisch akzeptiert und gespeichert, danach wird er geprüft. Die Anmeldungen laufen nacheinander, weil Posh-SSH alle Hostschlüssel in einer gemeinsamen Datei speichert.' }
        @{ T = 'i'; X = '**ESXi-Hosts:** werden an der Shell erkannt (uname -s = VMkernel) und per esxcli gelesen: Hersteller, Modell, Seriennummer, ESXi-Version, CPU, Kerne, RAM, Datenspeicher und IP-Adressen mit MAC. Rollen zeigt "Virtualisierung (ESXi)"; Updates und Letzter Start sind nicht ermittelbar. Das Konto braucht SSH-Zugang (am ESXi-Host muss SSH gestartet sein).' }
        @{ T = 'i'; X = '**Was bei Linux gelesen wird:** ohne Root und ohne sudo, nur lesende Befehle: Hostname, Distribution, Kernel, CPU, RAM, Laufwerke, IPs und MACs, Laufzeit, letzter Start und ausstehende Updates (nach dem Stand der Paketlisten; bei dnf nur mit vorhandenem Cache). Gefüllt werden dieselben Felder wie bei Windows-Servern, soweit es sie gibt; Windows-spezifische Felder (zum Beispiel RAID, Notizen, Installationsdatum) und alles, was ohne Root nicht lesbar ist (oft die Seriennummer), bleiben leer. Der Typ kommt aus der Spalte "Typ", sonst wird virtuell erkannt (systemd-detect-virt, DMI), sonst gilt Server physisch.' }
        @{ T = 'h'; X = 'Herstellerliste' }
        @{ T = 'i'; X = '**Hersteller-Namen laden:** lädt die Zuordnung "MAC-Präfix zu Hersteller" von der IEEE (ersatzweise von Wireshark) nach C:\Temp\NET-COCKPIT_data\NET-COCKPIT-oui.csv. Einmal laden reicht; der Hersteller erscheint ab dem nächsten Scan. Der Scan lädt nichts selbst.' }
        @{ T = 'h'; X = 'Portscan' }
        @{ T = 'i'; X = '**Portscan...:** für die markierten Geräte. Ein Fenster fragt nach den Ports (vorausgefüllt 1-1024, Einzelports und Bereiche, bis 1-65535). Offen heißt: die TCP-Verbindung kommt zustande. Rote Geräte werden übersprungen, bis zu drei Geräte gleichzeitig. **Portscan abbrechen** stoppt laufende und wartende Scans.' }
        @{ T = 'w'; X = 'Eine Firewall oder ein IPS im Netz kann einen Portscan melden.' }
        @{ T = 'h'; X = 'Neuer Client' }
        @{ T = 'i'; X = '**Neuer Client...:** trägt ein Gerät von Hand ein. Pflichtfeld ist die IP-Adresse, optional sind MAC-Adresse, Hostname, Typ, Konto und Bemerkung (die KuDo-Informationen und der Scan ergänzen eine fehlende MAC später; ohne MAC geht kein Aufwecken). Steht eine angegebene MAC schon in der Liste, wird der Eintrag abgelehnt. Bei gleicher IP oder gleichem Hostname fragt das Cockpit nach. Der Hersteller kommt aus der Herstellerliste, danach läuft die Statusprüfung.' }
        @{ T = 'h'; X = 'Markierte aus Liste entfernen' }
        @{ T = 'i'; X = '**Markierte aus Liste entfernen:** entfernt die markierten, sichtbaren Geräte nach einer Rückfrage aus der Geräteliste.' }
        @{ T = 'h'; X = 'PowerShell-Befehl senden' }
        @{ T = 'i'; X = '**PowerShell-Befehl senden...:** führt den Text als PowerShell auf den markierten, grünen Geräten aus (höchstens 20). Die Ausgabe steht pro Gerät in einem eigenen Reiter. Der Befehl läuft als ScriptBlock auf dem Zielgerät, Eingaben wie Read-Host funktionieren dort nicht. "Skript laden..." lädt eine .ps1-Datei in das Textfeld.' }
        @{ T = 'h'; X = 'MouseMover' }
        @{ T = 'i'; X = '**MouseMover:** öffnet ein kleines Fenster, das immer im Vordergrund bleibt. Mit dem Schiebeschalter (I = an, O = aus) bewegt es alle 30 Sekunden den Mauszeiger 1 Pixel nach rechts und wieder zurück. Es zeigt das aktive Fenster unter dem Mauszeiger und den Countdown. Mehr dazu weiter unten in diesem Reiter.' }
    ) })

    $inhalt.Add(@{ Titel = 'Ansicht'; Bloecke = @(
        @{ T = 'h'; X = 'Spalten' }
        @{ T = 'i'; X = '**Ansicht > Spalten:** Spalten der Tabelle ein- und ausblenden, wie per Rechtsklick auf eine Spaltenüberschrift. Die Auswahl wird gespeichert.' }
        @{ T = 'i'; X = '**Anzeigen** (Alle, Nur WinRM, Online Geräte, Offlinegeräte), **Filter** und **Sortieren** stehen im Reiter Tabelle.' }
    ) })

    $inhalt.Add(@{ Titel = 'Optionen'; Bloecke = @(
        @{ T = 'h'; X = 'Einstellungen und Daten' }
        @{ T = 'i'; X = '**Auto-Scan, Auto-Speichern, Parallelität...:** Auto-Scan (Reiter Scan & Status), Auto-Speichern (Reiter Geräteliste) und die Parallelität der Aufträge (Reiter Aktionen, Standard 10).' }
        @{ T = 'i'; X = '**NET-COCKPIT Daten löschen...:** löscht nach einer Rückfrage den Datenordner (Reiter Geräteliste, Abschnitt Datenordner).' }
        @{ T = 'h'; X = 'Konto pro Gerät' }
        @{ T = 'i'; X = '**Optionen > Konto für markierte Geräte...:** fragt Benutzername und Kennwort ab und setzt das Konto für alle markierten Geräte (Domäne\Benutzer, .\Benutzer für das lokale Konto des jeweiligen Geräts, oder UPN). Haben alle markierten Geräte dasselbe Konto, ist der Benutzername vorbelegt. Bleibt das Kennwort leer, wird nur der Benutzername eingetragen und das Kennwort bei der ersten Aktion abgefragt. Bleibt der Benutzername unverändert, genügt ein neues Kennwort, um nur das Kennwort zu ändern. **Mit aktuellem Konto verbinden** entfernt das eigene Konto wieder; das Gerät nutzt dann das Windows-Konto, mit dem Du angemeldet bist.' }
        @{ T = 'i'; X = '**Kennwort:** Der Benutzername steht in der Geräteliste, das Kennwort wird nur für die laufende Sitzung gemerkt. Nach einem Neustart des Cockpits fragt es das Kennwort bei der nächsten Aktion einmal pro Benutzername ab.' }
        @{ T = 'i'; X = '**Wirkung:** Alles, was sich per WinRM anmeldet, nutzt das Konto des jeweiligen Geräts. Aufwecken (Modul WOL), Portscan, Dauerping, Scan und Statusprüfung melden sich nirgends an.' }
        @{ T = 'h'; X = 'TrustedHosts' }
        @{ T = 'i'; X = '**Scheitert eine Verbindung an den TrustedHosts,** zeigt das Cockpit nach dem Lauf einmal eine Liste der betroffenen Geräte und bietet an, sie auf diesem Rechner einzutragen. Danach die Aktion erneut ausführen.' }
        @{ T = 'i'; X = '**Optionen > Verbindung:** Markierte eintragen, Markierte entfernen und TrustedHosts anzeigen. Eingetragen wird der Name, mit dem das Cockpit das Gerät anspricht (Hostname; bei Sonderzeichen, ohne Hostname oder wenn sich der Hostname nicht auflösen lässt die IP-Adresse). Vorhandene Einträge bleiben, Doppelte werden vermieden. Steht dort * (alle Hosts), entfernt das Cockpit nichts einzeln.' }
        @{ T = 'w'; X = 'Für die TrustedHosts braucht das Cockpit Administratorrechte (PowerShell 7 als Administrator starten). TrustedHosts schaltet die Prüfung der Gegenstelle für diese Geräte ab.' }
    ) })

    ### Reiter Voraussetzungen: Allgemein, Freischaltung per GPO (Domäne) und per Intune (ohne Domäne)
    $inhalt.Add(@{ Titel = 'Voraussetzungen'; Unter = @(
        @{ Titel = 'Allgemein'; Bloecke = @(
        @{ T = 'h'; X = 'Voraussetzungen' }
    @{ T = 'i'; X = '**PowerShell 7** unter Windows.' }
    @{ T = 'i'; X = '**MAC-Adressen** werden nur im eigenen Subnetz gefunden (ARP). Geräte in fremden Netzen werden über die IP-Adresse erkannt.' }
    @{ T = 'i'; X = '**Aufwecken (Modul WOL):** Wake-on-LAN im BIOS/UEFI und in der Netzwerkkarte aktiv, Gerät per Kabel, MAC der weckenden Netzwerkkarte.' }
    @{ T = 'i'; X = '**Neustart, Herunterfahren, PowerShell-Befehl und KuDo-Informationen:** WinRM (TCP 5985) und Administratorrechte auf dem Ziel, Windows-Geräte. **KuDo-Informationen bei Linux:** SSH (TCP 22), Posh-SSH und ein Benutzer mit Kennwort, kein Root nötig.' }
    @{ T = 'i'; X = '**OU wählen:** Rechner in der Domäne, kein RSAT nötig.' }
    @{ T = 'i'; X = '**Module** (Menü Module): die Dateien NET-COCKPIT-Modul-OS.ps1, NET-COCKPIT-Modul-APP.ps1, NET-COCKPIT-Modul-TREIBER.ps1, NET-COCKPIT-Modul-DIAGNOSE.ps1, NET-COCKPIT-Modul-WATOKI.ps1, NET-COCKPIT-Modul-M365APP.ps1, NET-COCKPIT-Modul-RDP.ps1, NET-COCKPIT-Modul-MOUSEMOVER.ps1 und NET-COCKPIT-Modul-WOL.ps1 liegen im selben Ordner wie das NET-COCKPIT, ebenso die Hilfedatei NET-COCKPIT-Hilfe.ps1 mit den Reitern der Module (die Info lädt sie beim Öffnen, die Module müssen dafür nicht gestartet sein), die Skripte des Moduls WaToKi im Unterordner WaToKi. Startest du das Cockpit über start.ps1, liegt anfangs nur das NET-COCKPIT bereit: **Beim ersten Aufruf eines Moduls** (bei WaToKi auch der Skripte) erscheint ein Ladefenster **Modul ... wird gestartet** mit Fortschrittsbalken, das Cockpit holt die Datei vom Server und prüft sie gegen ihre Signatur. Ohne gültige Signatur wird nichts geladen.' }
    @{ T = 'i'; X = '**Geräte, die Ping blockieren,** werden als offline (Rot) angezeigt.' }
    @{ T = 'h'; X = 'Log' }
    @{ T = 'p'; X = 'C:\Temp\NET-COCKPIT_data\NET-COCKPIT.log (wird bei jedem Programmstart geleert)' }
        ) }
        @{ Titel = 'Freischaltung per GPO (Domäne)'; Bloecke = @(
            @{ T = 'h'; X = 'Wofür?' }
            @{ T = 'p'; X = 'Grundfreischaltung der Geräte in einer Domäne für das NET-COCKPIT: WinRM (TCP 5985) und Ping, nur vom Admin-PC aus und nur im Firmennetz. Alles Weitere (zum Beispiel RDP) lässt sich danach über das Cockpit aktivieren. Die Anleitung gilt für die GPO **cp - Enable PSRemoting**.' }
            @{ T = 'h'; X = 'Variablen' }
            @{ T = 'i'; X = '**ADMIN-IP:** IP-Adresse des Admin-PCs oder Admin-Servers, von dem aus verwaltet wird (mehrere durch Komma getrennt).' }
            @{ T = 'i'; X = '**CLIENT-NETZ:** Netzbereich der Clients, zum Beispiel im Format 192.168.1.0/24 (mehrere Netze durch Komma getrennt).' }
            @{ T = 'h'; X = '1. WinRM aktivieren' }
            @{ T = 'i'; X = 'Computerkonfiguration > Richtlinien > Administrative Vorlagen > Windows-Komponenten > Windows-Remoteverwaltung (WinRM) > WinRM-Dienst.' }
            @{ T = 'i'; X = '**Remoteserververwaltung über WinRM zulassen:** Aktiviert, IPv4-Filter * (Sternchen).' }
            @{ T = 'h'; X = '2. Dienst WinRM automatisch starten' }
            @{ T = 'i'; X = 'Computerkonfiguration > Einstellungen > Systemsteuerungseinstellungen > Dienste > Neu > Dienst.' }
            @{ T = 'i'; X = 'Dienstname **WinRM**, Starttyp **Automatisch**, Dienstaktion **Dienst starten**.' }
            @{ T = 'h'; X = '3. Firewall: Regel WinRM' }
            @{ T = 'i'; X = 'Computerkonfiguration > Richtlinien > Windows-Einstellungen > Sicherheitseinstellungen > Windows Defender Firewall mit erweiterter Sicherheit > Eingehende Regeln > Neue Regel > Benutzerdefiniert.' }
            @{ T = 'i'; X = 'Alle Programme, Protokoll TCP, lokaler Port **5985**.' }
            @{ T = 'i'; X = 'Bereich: Lokale IP-Adressen = **CLIENT-NETZ**, Remote-IP-Adressen = **ADMIN-IP**.' }
            @{ T = 'i'; X = 'Verbindung zulassen, Profil: nur Domäne. Name: **WinRM (TCP 5985) eingehend - nur Admin-PC**.' }
            @{ T = 'h'; X = '4. Firewall: Regel Ping' }
            @{ T = 'i'; X = 'Neue Regel > Benutzerdefiniert > Alle Programme.' }
            @{ T = 'i'; X = 'Protokolltyp **ICMPv4**, ICMP-Einstellungen anpassen: nur **Echoanforderung**.' }
            @{ T = 'i'; X = 'Bereich: Lokale IP-Adressen = **CLIENT-NETZ**, Remote-IP-Adressen = **ADMIN-IP**.' }
            @{ T = 'i'; X = 'Verbindung zulassen, Profil: nur Domäne. Name: **Ping (ICMPv4 Echo) eingehend - nur Admin-PC**.' }
            @{ T = 'h'; X = '5. Verknüpfen und prüfen' }
            @{ T = 'i'; X = 'GPO mit der Test-OU verknüpfen, auf dem Gerät **gpupdate /force**.' }
            @{ T = 'i'; X = 'Vom Admin-PC: **Test-WSMan -ComputerName** mit dem FQDN des Geräts, dazu ein Ping. Danach im Cockpit die Statusprüfung: Grün heißt Ping und WinRM erreichbar.' }
        ) }
        @{ Titel = 'Freischaltung per Intune (ohne Domäne)'; Bloecke = @(
            @{ T = 'h'; X = 'Wofür?' }
            @{ T = 'p'; X = 'Grundfreischaltung für Geräte ohne Domäne (zum Beispiel Entra-joined mit Intune): WinRM (TCP 5985) und Ping, nur vom Admin-PC aus und nur im Firmennetz. Das Netzwerkprofil des Geräts (Öffentlich, Privat) spielt keine Rolle, weil die Firewallregeln für alle Netzwerktypen gelten. Für Domänengeräte gilt die Anleitung im Reiter GPO.' }
            @{ T = 'h'; X = 'Variablen' }
            @{ T = 'i'; X = '**ADMIN-IP:** IP-Adresse des Admin-PCs oder Admin-Servers, von dem aus verwaltet wird (mehrere durch Komma getrennt).' }
            @{ T = 'i'; X = '**CLIENT-NETZ:** Netzbereich der Clients, zum Beispiel im Format 192.168.1.0/24 (mehrere Netze durch Komma getrennt).' }
            @{ T = 'h'; X = '1. WinRM aktivieren (Einstellungskatalog)' }
            @{ T = 'i'; X = 'Intune > Geräte > Konfiguration > Erstellen > Windows 10 und höher > Einstellungskatalog, Name zum Beispiel **cp - Enable PSRemoting**.' }
            @{ T = 'i'; X = 'Administrative Vorlagen > Windows-Komponenten > Windows-Remoteverwaltung (WinRM) > WinRM-Dienst > **Remoteserververwaltung über WinRM zulassen** = Aktiviert, IPv4-Filter * (Sternchen).' }
            @{ T = 'w'; X = 'Der IPv4-Filter legt fest, auf welchen Adressen der WinRM-Dienst lauscht; leer heißt: keine Adresse, also kein Listener. Die Einschränkung auf den Admin-PC und das Firmennetz erledigen die Firewallregeln (Punkt 3).' }
            @{ T = 'h'; X = '2. Dienst WinRM automatisch starten (Plattformskript)' }
            @{ T = 'p'; X = 'Ein Windows-Client liefert den Dienst WinRM gestoppt und mit Starttyp Manuell aus (auf einem geprüften Windows-11-Client war es so). Dafür gibt es ein Plattformskript.' }
            @{ T = 'i'; X = 'Intune > Geräte > Skripte und Korrekturen > Plattformskripte > Hinzufügen > Windows 10 und höher, Name zum Beispiel **cp - WinRM Dienst automatisch**.' }
            @{ T = 'i'; X = 'Inhalt: **Set-Service -Name WinRM -StartupType Automatic** und **Start-Service -Name WinRM**.' }
            @{ T = 'i'; X = 'Skript im Benutzerkontext ausführen: **Nein**. Skript mit 64-Bit-PowerShell-Host ausführen: **Ja**. Plattformskripte laufen pro Gerät einmal, bei einer Änderung am Skript erneut.' }
            @{ T = 'h'; X = '3. Firewall (Endpoint Security)' }
            @{ T = 'i'; X = 'Intune > Endpoint Security > Firewall > Richtlinie erstellen > Windows > Microsoft Defender-Firewallregeln, Name zum Beispiel **cp - WinRM und Ping**, zwei Regeln.' }
            @{ T = 'i'; X = '**WinRM (TCP 5985) eingehend - nur Admin-PC:** Richtung Eingehend, Aktion Zulassen, Protokoll TCP (6), lokaler Port **5985**, lokale Adressen **CLIENT-NETZ**, Remote-Adressen **ADMIN-IP**, Netzwerktypen alle.' }
            @{ T = 'i'; X = '**Ping (ICMPv4 Echo) eingehend - nur Admin-PC:** Richtung Eingehend, Aktion Zulassen, Protokoll **1** (ICMPv4), ICMP-Typen und -Codes 8:*, lokale Adressen **CLIENT-NETZ**, Remote-Adressen **ADMIN-IP**, Netzwerktypen alle.' }
            @{ T = 'i'; X = 'Ist ein Gerät in einem anderen Netz (zum Beispiel zu Hause), passen die lokalen Adressen nicht und es ist von außen nicht erreichbar.' }
            @{ T = 'h'; X = '4. Zuweisen und prüfen' }
            @{ T = 'i'; X = 'Alle drei zuerst an eine Testgruppe zuweisen. Auf dem Gerät synchronisieren: Einstellungen > Konten > Auf Arbeits- oder Schulkonto zugreifen > Info > Synchronisieren (die Plattformskripte können etwas länger brauchen).' }
            @{ T = 'i'; X = 'Vom Admin-PC: **Test-NetConnection -ComputerName** mit der IP des Geräts (Ping) und mit **-Port 5985** (TcpTestSucceeded muss True sein).' }
            @{ T = 'h'; X = 'Anmeldung ohne Domäne' }
            @{ T = 'i'; X = 'Im Cockpit unter **Optionen > Konto für markierte Geräte** das lokale Konto als **.\Benutzername** eintragen.' }
            @{ T = 'i'; X = 'Lässt sich der Hostname eines Geräts nicht auflösen (ohne Domäne meist kein DNS-Eintrag), verbindet sich das Cockpit automatisch per IP-Adresse. Dafür braucht die IP den Eintrag in den TrustedHosts, und Konto und Kennwort werden abgefragt.' }
            @{ T = 'i'; X = 'Der Admin-PC braucht die Geräte in den TrustedHosts: **Optionen > Verbindung** (das Cockpit muss dafür als Administrator laufen).' }
            @{ T = 'i'; X = 'Bei lokalen Konten außer dem eingebauten Administrator filtert Windows das Admin-Token beim Remotezugriff, solange **LocalAccountTokenFilterPolicy** nicht gesetzt ist.' }
        ) }
    ) })

    ### Reiter Module: eine Auswahlleiste, darunter die Hilfe des gewählten Moduls (Reihenfolge wie im Menü Module)
    $menueModule = 'APP', 'DIAGNOSE', 'M365APP', 'OS', 'RDP', 'TREIBER', 'WATOKI', 'WOL'
    $seiten = @($menueModule | Where-Object { $script:ModulInfo.ContainsKey($_) } | ForEach-Object { & $script:ModulInfo[$_] })
    if ($seiten.Count -gt 0) {
        $inhalt.Add(@{ Titel = 'Module'; Unter = $seiten })
    }
    else {
        $inhalt.Add(@{ Titel = 'Module'; Bloecke = @(
            @{ T = 'w'; X = "Die Hilfe der Module konnte nicht geladen werden. Erwartet wird die Datei $($script:HilfeDatei) im selben Ordner wie das NET-COCKPIT oder, beim Start über start.ps1, der Zugriff auf den Server." }
        ) })
    }

    ### MouseMover gehört zum Menü Werkzeuge: seine Hilfe hängt unten am Reiter Werkzeuge
    if ($script:ModulInfo.ContainsKey('MOUSEMOVER')) {
        $mm = & $script:ModulInfo['MOUSEMOVER']
        $werkzeuge = $inhalt | Where-Object { $_.Titel -eq 'Werkzeuge' } | Select-Object -First 1
        $werkzeuge.Bloecke = @($werkzeuge.Bloecke) + @(@{ T = 'h'; X = 'MouseMover (Details)' }) + @($mm.Bloecke)
    }

    ### Reihenfolge der Reiter: wie die Menüleiste
    $reihenfolge = 'Überblick', 'Scan & Status', 'Tabelle', 'Geräteliste', 'Aktionen', 'Module', 'Werkzeuge', 'Ansicht', 'Optionen', 'Voraussetzungen'
    return @($reihenfolge | ForEach-Object { $t = $_; $inhalt | Where-Object { $_.Titel -eq $t } })
}

### Text mit **fett** und Suchtreffern in einen Absatz schreiben; Rückgabe: Anzahl der Treffer
function Add-WolInfoText {
    param($Absatz, [string]$Text, [string]$Suche)
    $treffer = 0
    foreach ($teil in [regex]::Split($Text, '(\*\*.+?\*\*)')) {
        if (-not $teil) { continue }
        $fett = ($teil.Length -gt 4 -and $teil.StartsWith('**') -and $teil.EndsWith('**'))
        $t = if ($fett) { $teil.Substring(2, $teil.Length - 4) } else { $teil }
        $stuecke = @(if ($Suche) { [regex]::Split($t, '(' + [regex]::Escape($Suche) + ')', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) } else { $t })
        for ($i = 0; $i -lt $stuecke.Count; $i++) {
            if ($stuecke[$i] -eq '') { continue }
            $lauf = [System.Windows.Documents.Run]::new($stuecke[$i])
            if ($fett) { $lauf.FontWeight = [System.Windows.FontWeights]::Bold }
            if ($Suche -and ($i % 2 -eq 1)) { $lauf.Background = [System.Windows.Media.Brushes]::Yellow; $treffer++ }
            [void]$Absatz.Inlines.Add($lauf)
        }
    }
    return $treffer
}

### Dokument eines Reiters aufbauen (mit Formatierung und Suchtreffern)
function New-WolInfoDokument {
    param($Bloecke, [string]$Suche)
    $farben = [System.Windows.Media.BrushConverter]::new()
    $dok = [System.Windows.Documents.FlowDocument]::new()
    $dok.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
    $dok.FontSize = 13
    $dok.PagePadding = [System.Windows.Thickness]::new(10)
    $treffer = 0
    foreach ($b in $Bloecke) {
        $absatz = [System.Windows.Documents.Paragraph]::new()
        $absatz.Margin = [System.Windows.Thickness]::new(0, 2, 0, 4)
        $text = [string]$b.X
        switch ($b.T) {
            'h' {
                $absatz.FontSize = 17
                $absatz.FontWeight = [System.Windows.FontWeights]::Bold
                $absatz.Foreground = $farben.ConvertFromString('#0078D4')
                $absatz.Margin = [System.Windows.Thickness]::new(0, 14, 0, 4)
            }
            'i' {
                $absatz.Margin = [System.Windows.Thickness]::new(14, 1, 0, 4)
                [void]$absatz.Inlines.Add([System.Windows.Documents.Run]::new([string][char]0x2022 + '  '))
            }
            'w' {
                $absatz.Background = $farben.ConvertFromString('#FFF8DC')
                $absatz.BorderBrush = $farben.ConvertFromString('#E0A800')
                $absatz.BorderThickness = [System.Windows.Thickness]::new(4, 0, 0, 0)
                $absatz.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
                $absatz.Margin = [System.Windows.Thickness]::new(0, 6, 0, 8)
                $text = '**Hinweis:** ' + $text
            }
            'a' {
                $absatz.Margin = [System.Windows.Thickness]::new(14, 2, 0, 2)
                $punkt = [System.Windows.Documents.Run]::new([string][char]0x25CF + '  ')
                $punkt.Foreground = $farben.ConvertFromString([string]$b.C)
                $punkt.FontSize = 18
                [void]$absatz.Inlines.Add($punkt)
            }
        }
        $treffer += (Add-WolInfoText -Absatz $absatz -Text $text -Suche $Suche)
        [void]$dok.Blocks.Add($absatz)
    }
    return [pscustomobject]@{ Dokument = $dok; Treffer = $treffer }
}

### Info-Fenster
### Seite eines Info-Reiters anzeigen (bei Reitern mit Auswahlleiste: das gewählte Modul) und die Schaltflächen markieren
function Set-WolInfoSeite {
    param($Reiter, [int]$Index)
    $Reiter.Aktiv = $Index
    $Reiter.Box.Document = (New-WolInfoDokument -Bloecke $Reiter.Seiten[$Index].Bloecke -Suche $script:InfoAktSuche).Dokument
    for ($i = 0; $i -lt $Reiter.Knoepfe.Count; $i++) { $Reiter.Knoepfe[$i].IsChecked = ($i -eq $Index) }
}

function Show-WolInfo {
    Import-WolHilfe
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NET-COCKPIT - Info / Voraussetzungen" Width="940" Height="720" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="Suche:" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox x:Name="Suche" Width="300" VerticalContentAlignment="Center" Padding="2,3"/>
      <TextBlock x:Name="SucheInfo" Foreground="DimGray" VerticalAlignment="Center" Margin="10,0,0,0"/>
    </StackPanel>
    <TabControl x:Name="Reiter" Grid.Row="1"/>
    <Button x:Name="Zu" Grid.Row="2" Content="Schließen" Width="90" HorizontalAlignment="Right" Margin="0,10,0,0" IsCancel="True"/>
  </Grid>
</Window>
'@
    $d.Owner = $script:Fenster
    $script:InfoReiterCtl = $d.FindName('Reiter')
    $script:InfoSuche = $d.FindName('Suche')
    $script:InfoSucheInfo = $d.FindName('SucheInfo')
    $script:InfoReiter = [System.Collections.Generic.List[object]]::new()
    $script:InfoAktSuche = ''
    foreach ($r in (Get-WolInfoInhalt)) {
        $seiten = @(if ($r.Unter) { $r.Unter } else { @{ Titel = $r.Titel; Bloecke = $r.Bloecke } })
        $box = [System.Windows.Controls.RichTextBox]::new()
        $box.IsReadOnly = $true
        $box.BorderThickness = [System.Windows.Thickness]::new(0)
        $box.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $tab = [System.Windows.Controls.TabItem]::new()
        $tab.Header = $r.Titel
        $eintrag = @{ Titel = $r.Titel; Seiten = $seiten; Box = $box; Tab = $tab; Treffer = 0; Aktiv = 0; Knoepfe = [System.Collections.Generic.List[object]]::new() }
        if ($seiten.Count -gt 1) {
            ### Auswahlleiste mit einer Schaltfläche je Seite (zum Beispiel je Modul)
            $leiste = [System.Windows.Controls.WrapPanel]::new()
            $leiste.Margin = [System.Windows.Thickness]::new(4, 6, 4, 4)
            for ($i = 0; $i -lt $seiten.Count; $i++) {
                $k = [System.Windows.Controls.Primitives.ToggleButton]::new()
                $k.Content = $seiten[$i].Titel
                $k.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
                $k.Margin = [System.Windows.Thickness]::new(0, 0, 6, 4)
                $k.Tag = @{ Eintrag = $eintrag; Index = $i }
                $k.Add_Click({ Set-WolInfoSeite -Reiter $this.Tag.Eintrag -Index $this.Tag.Index })
                [void]$leiste.Children.Add($k)
                $eintrag.Knoepfe.Add($k)
            }
            $dock = [System.Windows.Controls.DockPanel]::new()
            [System.Windows.Controls.DockPanel]::SetDock($leiste, [System.Windows.Controls.Dock]::Top)
            [void]$dock.Children.Add($leiste)
            [void]$dock.Children.Add($box)
            $tab.Content = $dock
        }
        else { $tab.Content = $box }
        Set-WolInfoSeite -Reiter $eintrag -Index 0
        [void]$script:InfoReiterCtl.Items.Add($tab)
        $script:InfoReiter.Add($eintrag)
    }
    $script:InfoSuche.Add_TextChanged({
        $suche = $script:InfoSuche.Text.Trim()
        if ($suche.Length -lt 2) { $suche = '' }
        $script:InfoAktSuche = $suche
        $summe = 0
        $erster = $null
        foreach ($r in $script:InfoReiter) {
            $r.Treffer = 0
            for ($i = 0; $i -lt $r.Seiten.Count; $i++) {
                $erg = New-WolInfoDokument -Bloecke $r.Seiten[$i].Bloecke -Suche $suche
                $r.Seiten[$i].Treffer = $erg.Treffer
                $r.Treffer += $erg.Treffer
                if ($r.Knoepfe.Count -gt $i) {
                    $r.Knoepfe[$i].Content = if ($suche -and $erg.Treffer -gt 0) { '{0} ({1})' -f $r.Seiten[$i].Titel, $erg.Treffer } else { $r.Seiten[$i].Titel }
                }
            }
            $aktiv = $r.Aktiv
            if ($suche -and $r.Treffer -gt 0 -and $r.Seiten[$aktiv].Treffer -eq 0) {
                $aktiv = @(0..($r.Seiten.Count - 1) | Where-Object { $r.Seiten[$_].Treffer -gt 0 })[0]
            }
            Set-WolInfoSeite -Reiter $r -Index $aktiv
            $r.Tab.Header = if ($suche -and $r.Treffer -gt 0) { '{0} ({1})' -f $r.Titel, $r.Treffer } else { $r.Titel }
            $summe += $r.Treffer
            if ($r.Treffer -gt 0 -and -not $erster) { $erster = $r.Tab }
        }
        if (-not $suche) { $script:InfoSucheInfo.Text = ''; return }
        $script:InfoSucheInfo.Text = if ($summe -gt 0) { "$summe Treffer" } else { 'keine Treffer' }
        $aktuell = $script:InfoReiter | Where-Object { $_.Tab -eq $script:InfoReiterCtl.SelectedItem } | Select-Object -First 1
        if ($erster -and (-not $aktuell -or $aktuell.Treffer -eq 0)) { $script:InfoReiterCtl.SelectedItem = $erster }
    })
    $script:InfoReiterCtl.SelectedIndex = 0
    $script:InfoSuche.Focus() | Out-Null
    [void]$d.ShowDialog()
}

# Portscan-Dialoge
## Ports einlesen (Einzelports und Bereiche von 1 bis 65535); $null bei ungültiger Eingabe
function ConvertTo-WolPortListe {
    param([string]$Text)
    $menge = [System.Collections.Generic.SortedSet[int]]::new()
    foreach ($teil in $Text.Split(',')) {
        $t = $teil.Trim()
        if (-not $t) { continue }
        if ($t -match '^(\d{1,5})$') { $von = [int]$Matches[1]; $bis = $von }
        elseif ($t -match '^(\d{1,5})\s*-\s*(\d{1,5})$') { $von = [int]$Matches[1]; $bis = [int]$Matches[2] }
        else { return $null }
        if ($von -lt 1 -or $bis -gt 65535 -or $von -gt $bis) { return $null }
        for ($p = $von; $p -le $bis; $p++) { [void]$menge.Add($p) }
    }
    if ($menge.Count -eq 0) { return $null }
    return [int[]]@($menge)
}

## Ports mit Dienstnamen als Text (zum Beispiel "80 HTTP, 443 HTTPS")
function Format-WolPorts {
    param([int[]]$Ports)
    $teile = foreach ($port in ($Ports | Sort-Object)) {
        if ($script:PortNamen.ContainsKey($port)) { '{0} {1}' -f $port, $script:PortNamen[$port] } else { [string]$port }
    }
    return ($teile -join ', ')
}

## Fenster zur Portauswahl (vorausgefüllt 1-1024)
function Show-WolPortDialog {
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Portscan" Width="540" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="Frage" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <TextBox x:Name="Eingabe" Margin="0,0,0,6"/>
    <TextBlock x:Name="Hinweis" TextWrapping="Wrap" Foreground="DarkOrange" Margin="0,0,0,12"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Ok" Content="Scan starten" Width="100" IsDefault="True" Margin="0,0,8,0"/>
      <Button x:Name="Abbruch" Content="Abbrechen" Width="80" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $d.Owner = $script:Fenster
    $d.FindName('Frage').Text = 'Welche Ports sollen geprüft werden? Einzelports und Bereiche, durch Komma getrennt. Erlaubt sind die Ports 1 bis 65535.'
    $d.FindName('Hinweis').Text = 'Hinweis: Je mehr Ports, desto länger dauert der Scan. Bei sehr großen Bereichen (zum Beispiel alle 65535 Ports) kann er sehr lange dauern.'
    $eingabe = $d.FindName('Eingabe')
    $eingabe.Text = $script:PortBereich
    $d.FindName('Ok').Add_Click({
        $f = [System.Windows.Window]::GetWindow($this)
        if (-not (ConvertTo-WolPortListe -Text $f.FindName('Eingabe').Text)) {
            [void][System.Windows.MessageBox]::Show($f, 'Die Eingabe ist ungültig. Beispiel: 1-1024, 8080, 8443', 'Portscan', 'OK', 'Warning')
            return
        }
        $f.DialogResult = $true
    })
    $eingabe.Focus() | Out-Null
    if (-not $d.ShowDialog()) { return $null }
    $script:PortBereich = $eingabe.Text.Trim()
    return [pscustomobject]@{ Ports = (ConvertTo-WolPortListe -Text $script:PortBereich); Text = $script:PortBereich }
}

# Detailfenster
## Alle Infos zu einem Gerät, offene Ports (80 und 443 öffnen den Browser), Bemerkung bearbeitbar
function Show-WolDetails {
    param($Zeile)
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="780" SizeToContent="Height" MaxHeight="900" WindowStartupLocation="CenterOwner">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid Grid.Row="0">
    <Grid.Resources>
      <Style TargetType="TextBlock"><Setter Property="Margin" Value="0,4,8,4"/></Style>
      <Style TargetType="TextBox"><Setter Property="Margin" Value="0,3"/></Style>
    </Grid.Resources>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="140"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Hostname" FontWeight="Bold"/>
    <TextBox x:Name="VHostname" Grid.Row="0" Grid.Column="1" IsReadOnly="True" BorderThickness="0" Background="Transparent" TextWrapping="Wrap"/>
    <TextBlock Grid.Row="1" Text="IP" FontWeight="Bold"/>
    <TextBox x:Name="VIP" Grid.Row="1" Grid.Column="1" IsReadOnly="True" BorderThickness="0" Background="Transparent"/>
    <TextBlock Grid.Row="2" Text="MAC" FontWeight="Bold"/>
    <TextBox x:Name="VMAC" Grid.Row="2" Grid.Column="1" IsReadOnly="True" BorderThickness="0" Background="Transparent"/>
    <TextBlock Grid.Row="3" Text="Hersteller" FontWeight="Bold"/>
    <TextBox x:Name="VHersteller" Grid.Row="3" Grid.Column="1" IsReadOnly="True" BorderThickness="0" Background="Transparent" TextWrapping="Wrap"/>
    <TextBlock Grid.Row="4" Text="Subnetz" FontWeight="Bold"/>
    <TextBox x:Name="VSubnetz" Grid.Row="4" Grid.Column="1" IsReadOnly="True" BorderThickness="0" Background="Transparent"/>
    <TextBlock Grid.Row="5" Text="Zuletzt gesehen" FontWeight="Bold"/>
    <TextBox x:Name="VZuletzt" Grid.Row="5" Grid.Column="1" IsReadOnly="True" BorderThickness="0" Background="Transparent"/>
    <TextBlock Grid.Row="6" Text="Status" FontWeight="Bold"/>
    <TextBox x:Name="VStatus" Grid.Row="6" Grid.Column="1" IsReadOnly="True" BorderThickness="0" Background="Transparent" TextWrapping="Wrap"/>
    <TextBlock Grid.Row="7" Text="Offene Ports" FontWeight="Bold"/>
    <StackPanel x:Name="PortListe" Grid.Row="7" Grid.Column="1" Margin="0,3"/>
    <TextBlock Grid.Row="8" Text="Bemerkung" FontWeight="Bold"/>
    <TextBox x:Name="VBemerkung" Grid.Row="8" Grid.Column="1" TextWrapping="Wrap" AcceptsReturn="False"/>
    </Grid>
    <Border Grid.Row="1" BorderBrush="#CCCCCC" BorderThickness="0,1,0,0" Margin="0,10,0,0" Padding="0,8,0,0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <DockPanel>
          <Button x:Name="BtnKudo" DockPanel.Dock="Right" Content="Auslesen" Padding="14,3" Margin="8,0,0,0"/>
          <TextBlock x:Name="KudoKopf" FontWeight="Bold" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </DockPanel>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,6,0,0">
          <StackPanel x:Name="KudoPanel"/>
        </ScrollViewer>
      </Grid>
    </Border>
    <Button x:Name="Zu" Grid.Row="2" Content="Schließen" Width="90" HorizontalAlignment="Right" Margin="0,12,0,0" IsCancel="True"/>
  </Grid>
</Window>
'@
    $d.Owner = $script:Fenster
    $name = if ($Zeile.Hostname) { $Zeile.Hostname } else { $Zeile.IP }
    $d.Title = "Gerätedetails - $name"
    $d.FindName('VHostname').Text = $Zeile.Hostname
    $d.FindName('VIP').Text = $Zeile.IP
    $d.FindName('VMAC').Text = $Zeile.MAC
    $d.FindName('VHersteller').Text = $Zeile.Hersteller
    $d.FindName('VSubnetz').Text = $Zeile.Subnetz
    $d.FindName('VZuletzt').Text = $Zeile.ZuletztGesehen
    $ampel = switch ($Zeile.Ampel) { 'Gruen' { 'Grün (Ping und WinRM)' } 'Gelb' { 'Gelb (nur Ping)' } 'Rot' { 'Rot (offline)' } default { 'Grau (noch nicht geprüft)' } }
    $d.FindName('VStatus').Text = "$ampel - $($Zeile.Status)"

    $liste = $d.FindName('PortListe')
    $eintraege = @(([string]$Zeile.Ports) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($eintraege.Count -eq 0) {
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Text = 'Noch kein Portscan durchgeführt'
        [void]$liste.Children.Add($t)
    }
    foreach ($eintrag in $eintraege) {
        $port = 0
        if ($eintrag -match '^(\d+)') { $port = [int]$Matches[1] }
        if ($port -eq 80 -or $port -eq 443) {
            $schema = if ($port -eq 443) { 'https' } else { 'http' }
            $knopf = [System.Windows.Controls.Button]::new()
            $knopf.Content = "$eintrag  -  im Browser öffnen"
            $knopf.Tag = '{0}://{1}' -f $schema, $Zeile.IP
            $knopf.HorizontalAlignment = 'Left'
            $knopf.Padding = [System.Windows.Thickness]::new(10, 2, 10, 2)
            $knopf.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
            $knopf.Add_Click({ Start-Process -FilePath $this.Tag })
            [void]$liste.Children.Add($knopf)
        }
        else {
            $t = [System.Windows.Controls.TextBlock]::new()
            $t.Text = $eintrag
            [void]$liste.Children.Add($t)
        }
    }

    $script:KudoPanel = $d.FindName('KudoPanel')
    $script:KudoKopf = $d.FindName('KudoKopf')
    $script:KudoKnopf = $d.FindName('BtnKudo')
    $script:KudoZeile = $Zeile
    $script:KudoKnopf.Add_Click({ Start-WolKudo -Ziele @($script:KudoZeile) -Einzeln })
    Show-WolKudoAnzeige

    $bemerkung = $d.FindName('VBemerkung')
    $bemerkung.Text = $Zeile.Bemerkung
    [void]$d.ShowDialog()
    $script:KudoPanel = $null
    $script:KudoZeile = $null
    $script:KudoKopf = $null
    $script:KudoKnopf = $null
    if ($bemerkung.Text -ne $Zeile.Bemerkung) {
        $Zeile.Bemerkung = $bemerkung.Text
        $script:Geaendert = $true
        Save-WolAuto
    }
}

# Einstellungsdatei
## Optionen und Spaltenauswahl speichern (C:\Temp\NET-COCKPIT_data\NET-COCKPIT-einstellungen.json)
function Save-WolEinstellungen {
    if ($script:DatenLoeschen) { return }
    try {
        if (-not (Test-Path $script:DatenOrdner)) { New-Item -Path $script:DatenOrdner -ItemType Directory -Force | Out-Null }
        $script:Opt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:EinstellungenPfad -Encoding utf8
    }
    catch { Write-WolLog "Einstellungen konnten nicht gespeichert werden: $($_.Exception.Message)" }
}

## Gespeicherte Optionen und Spaltenauswahl lesen (fehlt die Datei, gelten die Standardwerte)
function Import-WolEinstellungen {
    if (-not (Test-Path -LiteralPath $script:EinstellungenPfad)) { return }
    try {
        $e = Get-Content -LiteralPath $script:EinstellungenPfad -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        foreach ($k in 'AutoScan', 'Status', 'AutoSpeichern') {
            if ($e.ContainsKey($k)) { $script:Opt[$k] = [bool]$e[$k] }
        }
        foreach ($k in 'AutoMin', 'StatusMin') {
            $m = 0
            if ($e.ContainsKey($k) -and [int]::TryParse([string]$e[$k], [ref]$m) -and $m -ge 1) { $script:Opt[$k] = [string]$m }
        }
        if ($e.ContainsKey('Anzeige') -and [string]$e['Anzeige'] -in 'Alle', 'NurWinRM', 'Online', 'Offline', 'OhneOffline') { $script:Opt.Anzeige = if ([string]$e['Anzeige'] -eq 'OhneOffline') { 'Online' } else { [string]$e['Anzeige'] } }
        $p = 0
        if ($e.ContainsKey('Parallel') -and [int]::TryParse([string]$e['Parallel'], [ref]$p) -and $p -ge 1 -and $p -le 50) { $script:Opt.Parallel = $p }
        if ($e.ContainsKey('Spalten') -and $e['Spalten'] -is [System.Collections.IDictionary]) {
            foreach ($k in $e['Spalten'].Keys) { $script:Opt.Spalten[[string]$k] = [bool]$e['Spalten'][$k] }
        }
    }
    catch { Write-WolLog "Einstellungen konnten nicht gelesen werden: $($_.Exception.Message)" }
}

Add-WolStartMarke 'Funktionen und Dialoge definiert'

# Oberfläche
## Hauptfenster
$script:Fenster = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NET-COCKPIT" Width="1500" Height="760" WindowStartupLocation="CenterScreen">
  <Grid Margin="8">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="130"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Menu Grid.Row="0" Margin="0,0,0,6">
      <MenuItem Header="Datei">
        <MenuItem x:Name="MnuNeueListe" Header="Neue Liste"/>
        <MenuItem x:Name="MnuOeffnen" Header="Öffnen..."/>
        <MenuItem x:Name="MnuSpeichern" Header="Speichern"/>
        <MenuItem x:Name="MnuSpeichernUnter" Header="Speichern unter..."/>
        <Separator/>
        <MenuItem x:Name="MnuOu" Header="OU wählen..."/>
        <MenuItem x:Name="MnuExport" Header="Exportieren..."/>
        <Separator/>
        <MenuItem x:Name="MnuBeenden" Header="Beenden"/>
      </MenuItem>
      <MenuItem Header="Aktionen">
        <MenuItem x:Name="MnuNeustart" Header="Neustart"/>
        <MenuItem x:Name="MnuNeustartPlanen" Header="Neustart planen..."/>
        <MenuItem x:Name="MnuNeustartAbbrechen" Header="Neustart abbrechen"/>
        <MenuItem x:Name="MnuHerunterfahren" Header="Herunterfahren"/>
      </MenuItem>
      <MenuItem Header="Module">
        <MenuItem x:Name="MnuUpdApp" Header="APP"/>
        <MenuItem x:Name="MnuDiagnose" Header="Diagnose"/>
        <MenuItem x:Name="MnuM365App" Header="M365-Wartungs-App"/>
        <MenuItem x:Name="MnuUpdOs" Header="OS"/>
        <MenuItem x:Name="MnuRdp" Header="RDP"/>
        <MenuItem x:Name="MnuUpdTreiber" Header="Treiber"/>
        <MenuItem x:Name="MnuWatoki" Header="WaToKi"/>
        <MenuItem x:Name="MnuWol" Header="WOL"/>
      </MenuItem>
      <MenuItem Header="Werkzeuge">
        <MenuItem x:Name="MnuPing" Header="Dauerping"/>
        <MenuItem x:Name="MnuEinzelScan" Header="Einzel-Scan für markierte Geräte"/>
        <MenuItem x:Name="MnuKudo" Header="KuDo-Informationen auslesen"/>
        <MenuItem x:Name="MnuHersteller" Header="Hersteller-Namen laden"/>
        <MenuItem x:Name="MnuPortscan" Header="Portscan..."/>
        <MenuItem x:Name="MnuPortscanAbbrechen" Header="Portscan abbrechen"/>
        <Separator/>
        <MenuItem x:Name="MnuNeuerClient" Header="Neuer Client..."/>
        <MenuItem x:Name="MnuEntfernen" Header="Markierte aus Liste entfernen"/>
        <MenuItem x:Name="MnuBefehl" Header="PowerShell-Befehl senden..."/>
        <Separator/>
        <MenuItem x:Name="MnuMouseMover" Header="MouseMover"/>
      </MenuItem>
      <MenuItem Header="Ansicht">
        <MenuItem x:Name="MnuSpalten" Header="Spalten"/>
      </MenuItem>
      <MenuItem Header="Optionen">
        <MenuItem x:Name="MnuKonto" Header="Konto für markierte Geräte..."/>
        <MenuItem Header="Verbindung">
          <MenuItem x:Name="MnuTrustedEintragen" Header="TrustedHosts: Markierte eintragen"/>
          <MenuItem x:Name="MnuTrustedEntfernen" Header="TrustedHosts: Markierte entfernen"/>
          <MenuItem x:Name="MnuTrustedAnzeigen" Header="TrustedHosts: anzeigen"/>
        </MenuItem>
        <MenuItem x:Name="MnuEinstellungen" Header="Auto-Scan, Auto-Speichern, Parallelität..."/>
        <Separator/>
        <MenuItem x:Name="MnuDatenLoeschen" Header="NET-COCKPIT Daten löschen..."/>
      </MenuItem>
      <MenuItem Header="Hilfe">
        <MenuItem x:Name="MnuInfo" Header="Info / Voraussetzungen"/>
      </MenuItem>
    </Menu>

    <StackPanel Grid.Row="1">
      <StackPanel.Resources>
        <Style TargetType="Button"><Setter Property="Margin" Value="0,0,6,6"/><Setter Property="Padding" Value="10,4"/></Style>
        <Style TargetType="CheckBox"><Setter Property="Margin" Value="0,0,6,6"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
        <Style TargetType="TextBlock"><Setter Property="Margin" Value="0,0,6,6"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
      </StackPanel.Resources>
      <WrapPanel>
        <Button x:Name="BtnAktuellesNetz" Content="Aktuelles Netz verwenden"/>
        <Button x:Name="BtnAnderesNetz" Content="Anderes Netz eingeben..."/>
        <TextBlock x:Name="TxtNetz" Text="Scanbereich: nicht gewählt" FontWeight="Bold"/>
      </WrapPanel>
      <WrapPanel>
        <Button x:Name="BtnScanStart" Content="▶ Scan starten" FontSize="18" FontWeight="Bold" Margin="0,2,10,8" Padding="26,8">
          <Button.Style>
            <Style TargetType="Button">
              <Setter Property="Foreground" Value="DarkGreen"/>
              <Style.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="Gray"/></Trigger></Style.Triggers>
            </Style>
          </Button.Style>
        </Button>
        <Button x:Name="BtnScanStopp" Content="■ Scan stoppen" FontSize="18" FontWeight="Bold" Margin="0,2,18,8" Padding="26,8">
          <Button.Style>
            <Style TargetType="Button">
              <Setter Property="Foreground" Value="DarkRed"/>
              <Style.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Foreground" Value="Gray"/></Trigger></Style.Triggers>
            </Style>
          </Button.Style>
        </Button>
        <TextBlock x:Name="TxtScan" Text="" Foreground="DarkOrange"/>
      </WrapPanel>
      <WrapPanel>
        <Button x:Name="BtnFilterLoeschen" Content="Filter löschen"/>
        <TextBlock Text="Anzeigen:" Margin="12,0,6,6" VerticalAlignment="Center"/>
        <ComboBox x:Name="CmbAnzeige" Width="190" Margin="0,0,6,6">
          <ComboBoxItem Tag="Alle" Content="Alle anzeigen"/>
          <ComboBoxItem Tag="NurWinRM" Content="Nur WinRM anzeigen"/>
          <ComboBoxItem Tag="Online" Content="Online Geräte anzeigen"/>
          <ComboBoxItem Tag="Offline" Content="Offlinegeräte anzeigen"/>
        </ComboBox>
        <TextBlock Margin="12,0,0,6">
          <Run Text="●" Foreground="LimeGreen"/><Run Text=" Ping + WinRM   "/>
          <Run Text="●" Foreground="Gold"/><Run Text=" nur Ping   "/>
          <Run Text="●" Foreground="Red"/><Run Text=" offline   "/>
          <Run Text="●" Foreground="Gray"/><Run Text=" noch nicht geprüft"/>
        </TextBlock>
      </WrapPanel>
    </StackPanel>

    <DockPanel Grid.Row="2">
      <Button x:Name="BtnBeenden" Content="Beenden" DockPanel.Dock="Right" VerticalAlignment="Top" Margin="6,0,0,6" Padding="14,4" FontWeight="Bold"/>
      <WrapPanel>
        <WrapPanel.Resources>
          <Style TargetType="Button"><Setter Property="Margin" Value="0,0,6,6"/><Setter Property="Padding" Value="10,4"/></Style>
        </WrapPanel.Resources>
        <Button x:Name="BtnAlle" Content="Alle markieren"/>
        <Button x:Name="BtnKeine" Content="Keine markieren"/>
        <Button x:Name="BtnNurOnline" Content="Nur Online markieren"/>
      </WrapPanel>
    </DockPanel>

    <DataGrid x:Name="Gitter" Grid.Row="3" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False"
              SelectionMode="Extended" SelectionUnit="FullRow" GridLinesVisibility="Horizontal" HeadersVisibility="Column"
              HorizontalScrollBarVisibility="Auto"
              RowBackground="White" AlternatingRowBackground="#FAFAFA" AlternationCount="2">
      <DataGrid.Resources>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#BBDDF7"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="Black"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#CFE6F8"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="Black"/>
      </DataGrid.Resources>
      <DataGrid.ColumnHeaderStyle>
        <Style TargetType="DataGridColumnHeader"><Setter Property="HorizontalContentAlignment" Value="Stretch"/></Style>
      </DataGrid.ColumnHeaderStyle>
      <DataGrid.Columns>
        <DataGridTemplateColumn Header="Status" Width="50" IsReadOnly="True" SortMemberPath="Ampel">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate>
              <TextBlock Text="●" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock.Style>
                  <Style TargetType="TextBlock">
                    <Setter Property="Foreground" Value="Gray"/>
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding Ampel}" Value="Rot"><Setter Property="Foreground" Value="Red"/></DataTrigger>
                      <DataTrigger Binding="{Binding Ampel}" Value="Gelb"><Setter Property="Foreground" Value="Gold"/></DataTrigger>
                      <DataTrigger Binding="{Binding Ampel}" Value="Gruen"><Setter Property="Foreground" Value="LimeGreen"/></DataTrigger>
                    </Style.Triggers>
                  </Style>
                </TextBlock.Style>
              </TextBlock>
            </DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
        </DataGridTemplateColumn>
      </DataGrid.Columns>
    </DataGrid>

    <TextBox x:Name="Log" Grid.Row="4" Margin="0,8,0,0" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
             TextWrapping="NoWrap" FontFamily="Consolas"/>
    <TextBlock x:Name="TxtListe" Grid.Row="5" Margin="0,6,0,0" Foreground="DimGray"/>
  </Grid>
</Window>
'@

foreach ($name in 'BtnAktuellesNetz', 'BtnAnderesNetz', 'TxtNetz', 'BtnScanStart', 'BtnScanStopp', 'TxtScan',
    'BtnFilterLoeschen', 'CmbAnzeige', 'MnuSpalten',
    'BtnAlle', 'BtnKeine', 'BtnNurOnline', 'BtnBeenden',
    'Gitter', 'Log', 'TxtListe') {
    $script:C[$name] = $script:Fenster.FindName($name)
}
$script:C.Gitter.ItemsSource = $script:Ansicht

## Anzeigefilter (Alle, Ohne Offline, Nur WinRM) und Spaltenfilter
$script:Ansicht.Filter = [System.Predicate[object]]{
    param($z)
    switch ($script:Opt.Anzeige) {
        'NurWinRM' { if ($z.Ampel -ne 'Gruen') { return $false } }
        'Online'   { if ($z.Ampel -ne 'Gruen' -and $z.Ampel -ne 'Gelb') { return $false } }
        'Offline'  { if ($z.Ampel -ne 'Rot') { return $false } }
    }
    foreach ($pfad in @($script:SpaltenFilter.Keys)) {
        $text = $script:SpaltenFilter[$pfad]
        if (-not $text) { continue }
        $wert = if ($pfad.StartsWith('[')) { [string]$z[$pfad.Trim('[', ']')] } else { [string]$z.$pfad }
        if ($text -eq '*') { if (-not $wert.Trim()) { return $false } }
        elseif ($text -eq '!') { if ($wert.Trim()) { return $false } }
        elseif ($text.Length -gt 1 -and $text.StartsWith('!')) {
            $ohne = $text.Substring(1)
            if ($ohne.Contains('*') -or $ohne.Contains('?')) { if ($wert -like "*$ohne*") { return $false } }
            elseif ($wert.IndexOf($ohne, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
        }
        elseif ($text.Contains('*') -or $text.Contains('?')) { if ($wert -notlike "*$text*") { return $false } }
        elseif ($wert.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    }
    return $true
}

## Nächsten Vorfahren eines bestimmten Typs im visuellen (sonst logischen) Baum suchen
function Get-WolVorfahre {
    param($Start, [type]$Typ)
    $o = $Start -as [System.Windows.DependencyObject]
    while ($o) {
        if ($Typ.IsInstanceOfType($o)) { return $o }
        if ($o -is [System.Windows.Media.Visual]) { $o = [System.Windows.Media.VisualTreeHelper]::GetParent($o) }
        else { $o = [System.Windows.LogicalTreeHelper]::GetParent($o) }
    }
    return $null
}

## Spalten
### Spalte anlegen: Spaltenkopf mit Filterfeld (Teiltext, Groß-/Kleinschreibung egal; filtert nur die jeweilige Spalte), in die Spaltenliste eintragen; Spalten der Module (-Modul) stehen vor "Bemerkung", sind nur sichtbar, wenn im offenen Modulfenster der Haken "Spalten des Moduls in der Tabelle anzeigen" gesetzt ist, und werden nicht in den Einstellungen gespeichert
function New-WolSpalte {
    param(
        [string]$Key, [string]$Titel, [string]$Eig, [string]$Sort = '', $Breite = 120, $MinBreite = 40,
        [bool]$NurLesen = $true, [bool]$Sichtbar = $true, [string]$Modul = ''
    )
    if ($script:SpaltenListe | Where-Object { $_.Key -eq $Key }) { return }
    $spalte = [System.Windows.Controls.DataGridTextColumn]::new()
    $bindung = [System.Windows.Data.Binding]::new($Eig)
    if ($NurLesen) { $bindung.Mode = [System.Windows.Data.BindingMode]::OneWay }
    $spalte.Binding = $bindung
    $spalte.SortMemberPath = $(if ($Sort) { $Sort } else { $Eig })
    $spalte.IsReadOnly = $NurLesen
    $spalte.MinWidth = [double]$MinBreite
    if ([string]$Breite -eq '*') { $spalte.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star) }
    else { $spalte.Width = [System.Windows.Controls.DataGridLength]::new([double]$Breite) }

    $kopf = [System.Windows.Controls.StackPanel]::new()
    $beschriftung = [System.Windows.Controls.TextBlock]::new()
    $beschriftung.Text = $Titel
    $beschriftung.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
    $box = [System.Windows.Controls.TextBox]::new()
    $box.Tag = $Eig
    $box.MinWidth = 40
    $box.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
    $box.ToolTip = "Filter für die Spalte $Titel (Teiltext, Groß-/Kleinschreibung egal; * und ? als Platzhalter; nur * = nicht leer, nur ! = leer, !Text = alles ohne diesen Text)"
    $box.Add_TextChanged({
        $script:SpaltenFilter[$this.Tag] = $this.Text
        Update-WolAnsicht -Bestaetigen
    })
    [void]$kopf.Children.Add($beschriftung)
    [void]$kopf.Children.Add($box)
    $spalte.Header = $kopf

    $stelle = $script:C.Gitter.Columns.Count
    if ($Modul) {
        $bemerkung = $script:SpaltenListe | Where-Object { $_.Key -eq 'Bemerkung' } | Select-Object -First 1
        if ($bemerkung) { $stelle = $script:C.Gitter.Columns.IndexOf($bemerkung.Spalte) }
    }
    $script:C.Gitter.Columns.Insert($stelle, $spalte)

    $zeigen = $Sichtbar
    if (-not $Modul -and $script:Opt.Spalten.ContainsKey($Key)) { $zeigen = [bool]$script:Opt.Spalten[$Key] }
    $spalte.Visibility = $(if ($zeigen) { 'Visible' } else { 'Collapsed' })

    $script:SpaltenListe.Add([pscustomobject]@{ Key = $Key; Titel = $Titel; Eig = $Eig; Spalte = $spalte; Box = $box; Modul = $Modul; Standard = $Sichtbar })
    $script:FilterBoxen.Add($box)
    if ($script:SpaltenFertig) { Update-WolSpaltenMenues }
}

### Spalte ein- oder ausblenden (beim Ausblenden wird ihr Filter geleert)
function Set-WolSpalteSichtbar {
    param([string]$Key, [bool]$Sichtbar, [switch]$OhneSpeichern)
    $s = $script:SpaltenListe | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if (-not $s) { return }
    $s.Spalte.Visibility = $(if ($Sichtbar) { 'Visible' } else { 'Collapsed' })
    if (-not $Sichtbar -and $s.Box.Text) { $s.Box.Text = '' }
    if (-not $s.Modul) { $script:Opt.Spalten[$Key] = $Sichtbar }
    foreach ($menue in @($script:SpaltenMenue, $script:C.MnuSpalten)) {
        foreach ($punkt in $menue.Items) {
            if ($punkt.Tag -eq $Key) { $punkt.IsChecked = $Sichtbar }
        }
    }
    if (-not $OhneSpeichern) { Save-WolEinstellungen }
}

### Alle Spalten auf ihre Standardansicht zurücksetzen
function Reset-WolSpalten {
    foreach ($s in $script:SpaltenListe) {
        if ($s.Modul) { continue }
        Set-WolSpalteSichtbar -Key $s.Key -Sichtbar $s.Standard -OhneSpeichern
    }
    Update-WolModulSpalten
    Save-WolEinstellungen
}

### Spalten der Module ein- oder ausblenden: sichtbar, wenn im offenen Modulfenster der Haken "Spalten des Moduls in der Tabelle anzeigen" gesetzt ist (Gruppe "Updates" = gemeinsame Spalten, sichtbar, sobald der Haken bei irgendeinem Modul außer WaToKi gesetzt ist)
function Update-WolModulSpalten {
    foreach ($s in @($script:SpaltenListe | Where-Object { $_.Modul })) {
        $an = $(if ($s.Modul -eq 'Updates') { @($script:ModulSpaltenAn | Where-Object { $_ -ne 'WATOKI' }).Count -gt 0 } else { $script:ModulSpaltenAn.Contains([string]$s.Modul) })
        Set-WolSpalteSichtbar -Key $s.Key -Sichtbar $an -OhneSpeichern
    }
}

### Meldet ein Modulfenster als geöffnet oder geschlossen und passt die Spalten an (beim Schließen wird der Haken "Spalten anzeigen" zurückgesetzt)
function Set-WolModulOffen {
    param([string]$Key, [bool]$Offen)
    if ($Offen) { [void]$script:ModulOffen.Add($Key) } else { [void]$script:ModulOffen.Remove($Key); [void]$script:ModulSpaltenAn.Remove($Key) }
    Update-WolModulSpalten
    ### Beim Schließen eines Modulfensters das Cockpit nach vorn holen (sonst springt das PowerShell-Fenster hoch)
    if (-not $Offen -and $script:Fenster) {
        try { [void]$script:Fenster.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{ [void]$script:Fenster.Activate() }) }
        catch { }
    }
}

### Haken "Spalten des Moduls in der Tabelle anzeigen" eines Modulfensters: Spalten des Moduls ein- oder ausblenden
function Set-WolModulSpalten {
    param([string]$Key, [bool]$An)
    if ($An) { [void]$script:ModulSpaltenAn.Add($Key) } else { [void]$script:ModulSpaltenAn.Remove($Key) }
    Update-WolModulSpalten
}

### Haken eines Modulfensters (CheckBox ChkSpalten) verdrahten; er steht beim Öffnen immer auf aus und wird nicht gespeichert
function Connect-WolModulSpaltenHaken {
    param($Fenster, [string]$Key)
    $haken = $Fenster.FindName('ChkSpalten')
    if (-not $haken) { return }
    $haken.Tag = $Key
    $haken.IsChecked = $false
    $haken.Add_Checked({ param($sender, $e) Set-WolModulSpalten -Key ([string]$sender.Tag) -An $true })
    $haken.Add_Unchecked({ param($sender, $e) Set-WolModulSpalten -Key ([string]$sender.Tag) -An $false })
}

### Auswahlmenü der Spalten (Rechtsklick auf die Spaltenüberschrift und Ansicht > Spalten) neu aufbauen
function Update-WolSpaltenMenues {
    foreach ($menue in @($script:SpaltenMenue, $script:C.MnuSpalten)) {
        $menue.Items.Clear()
        foreach ($s in $script:SpaltenListe) {
            $punkt = [System.Windows.Controls.MenuItem]::new()
            $punkt.Header = $(if ($s.Modul) { '{0} ({1})' -f $s.Titel, $s.Modul } else { $s.Titel })
            $punkt.IsCheckable = $true
            $punkt.StaysOpenOnClick = $true
            $punkt.IsChecked = ($s.Spalte.Visibility -eq 'Visible')
            $punkt.Tag = $s.Key
            $punkt.Add_Click({
                param($sender, $e)
                Set-WolSpalteSichtbar -Key ([string]$sender.Tag) -Sichtbar ([bool]$sender.IsChecked)
            })
            [void]$menue.Items.Add($punkt)
        }
        [void]$menue.Items.Add([System.Windows.Controls.Separator]::new())
        $standard = [System.Windows.Controls.MenuItem]::new()
        $standard.Header = 'Standard wiederherstellen'
        $standard.Add_Click({ Reset-WolSpalten })
        [void]$menue.Items.Add($standard)
    }
}

## Spaltenköpfe mit Filterfeld (Teiltext, Groß-/Kleinschreibung egal; filtert nur die jeweilige Spalte)
Import-WolEinstellungen
foreach ($item in $script:C.CmbAnzeige.Items) { if ($item.Tag -eq $script:Opt.Anzeige) { $script:C.CmbAnzeige.SelectedItem = $item } }
$script:SpaltenMenue = [System.Windows.Controls.ContextMenu]::new()
$script:SpaltenFertig = $false
foreach ($def in @(
    @{ Key = 'Hostname'; Titel = 'Hostname'; Eig = 'Hostname'; Breite = 180; NurLesen = $false }
    @{ Key = 'Typ'; Titel = 'Typ'; Eig = 'Typ'; Breite = 120; NurLesen = $false }
    @{ Key = 'Konto'; Titel = 'Konto'; Eig = 'KontoAnzeige'; Breite = 170 }
    @{ Key = 'IP'; Titel = 'IP'; Eig = 'IP'; Sort = 'IpSort'; Breite = 110 }
    @{ Key = 'MAC'; Titel = 'MAC'; Eig = 'MAC'; Breite = 130; NurLesen = $false }
    @{ Key = 'Hersteller'; Titel = 'Hersteller'; Eig = 'Hersteller'; Breite = 160 }
    @{ Key = 'Subnetz'; Titel = 'Subnetz'; Eig = 'Subnetz'; Breite = 105 }
    @{ Key = 'ZuletztGesehen'; Titel = 'Zuletzt gesehen'; Eig = 'ZuletztGesehen'; Breite = 120 }
    @{ Key = 'WerteStand'; Titel = 'Werte gelesen am'; Eig = '[WerteStand]'; Breite = 120; Sichtbar = $false }
    @{ Key = 'Ports'; Titel = 'Offene Ports'; Eig = 'Ports'; Breite = 200 }
    @{ Key = 'Bemerkung'; Titel = 'Bemerkung'; Eig = 'Bemerkung'; Breite = 200; MinBreite = 140; NurLesen = $false }
    @{ Key = 'Status'; Titel = 'Aktion / Status'; Eig = 'Status'; Breite = 200 }
)) {
    New-WolSpalte @def
}
$script:SpaltenFertig = $true
Update-WolSpaltenMenues

## Rechtsklick auf eine Spaltenüberschrift öffnet die Spaltenauswahl (im Filterfeld bleibt das normale Menü)
$script:C.Gitter.Add_PreviewMouseRightButtonUp({
    param($sender, $e)
    if (Get-WolVorfahre -Start $e.OriginalSource -Typ ([System.Windows.Controls.TextBox])) { return }
    $kopf = Get-WolVorfahre -Start $e.OriginalSource -Typ ([System.Windows.Controls.Primitives.DataGridColumnHeader])
    if (-not $kopf) { return }
    $script:SpaltenMenue.PlacementTarget = $kopf
    $script:SpaltenMenue.Placement = [System.Windows.Controls.Primitives.PlacementMode]::MousePoint
    $script:SpaltenMenue.IsOpen = $true
    $e.Handled = $true
})

## Standardsortierung: nach IP in Zahlenreihenfolge (34 vor 100)
[void]$script:Ansicht.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('IpSort', [System.ComponentModel.ListSortDirection]::Ascending))
foreach ($spalte in $script:C.Gitter.Columns) {
    if ($spalte.SortMemberPath -eq 'IpSort') { $spalte.SortDirection = [System.ComponentModel.ListSortDirection]::Ascending }
}


Add-WolStartMarke 'Oberfläche aufgebaut'

# Scan-Steuerung
## Zustandsanzeige und Knöpfe (Start/Stopp) aktualisieren
function Update-WolScanAnzeige {
    if ($script:ScanJob) { $text = 'Scan läuft...' }
    elseif ($script:ScanAktiv) { $text = 'Gestartet, wartet auf den nächsten Scan' }
    else { $text = 'Gestoppt' }
    if ($script:NeuHinweis) { $text += ' - ' + $script:NeuHinweis }
    if ($script:KudoHinweis) { $text += ' - ' + $script:KudoHinweis }
    $script:C.TxtScan.Text = $text
    $script:C.BtnScanStart.IsEnabled = -not $script:ScanAktiv
    $script:C.BtnScanStopp.IsEnabled = $script:ScanAktiv
}

## Scan per Hand starten (mit Auto-Scan, wenn der Haken gesetzt ist)
function Start-WolScanSteuerung {
    if (-not $script:NetzCidr) {
        Show-WolMeldung 'Bitte zuerst ein Netz wählen.' 'Warning'
        return
    }
    $script:ScanAktiv = $true
    Start-WolScan
    if ($script:Opt.AutoScan) { Set-WolAutoScan }
    Update-WolScanAnzeige
}

## Scan per Hand stoppen: laufenden Scan abbrechen und Auto-Scan anhalten
function Stop-WolScanSteuerung {
    $script:ScanAktiv = $false
    $script:AutoTimer.Stop()
    if ($script:ScanJob) {
        Stop-Job -Job $script:ScanJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:ScanJob -Force -ErrorAction SilentlyContinue
        $script:ScanJob = $null
    }
    Write-WolLog 'Scan gestoppt'
    Update-WolScanAnzeige
}

## Scan starten
function Start-WolScan {
    param([switch]$Still)
    if ($script:ScanJob -or -not $script:NetzCidr) { return }
    $script:ScanStill = [bool]$Still
    $ziel = Get-WolScanBereiche -Text $script:NetzCidr
    if ($ziel.Fehler) { return }
    $script:ScanInfo = $ziel.Bereiche
    $adressen = $ziel.Adressen
    $drossel = 64
    $script:ScanJob = Start-ThreadJob -ScriptBlock $script:ScanBlock -ArgumentList $adressen, $drossel, $script:OuiPfad
    Update-WolScanAnzeige
    if (-not $script:ScanStill) { Write-WolLog "Scan gestartet: $($script:NetzCidr) ($($adressen.Count) Adressen)" }
}

## Netz setzen und sofort scannen
function Set-WolNetz {
    param([string]$Cidr)
    $ziel = Get-WolScanBereiche -Text $Cidr
    if ($ziel.Fehler) {
        Show-WolMeldung "$($ziel.Fehler)`r`nErlaubt sind Netze (Netzadresse/Präfixlänge von /22 bis /30), IP-Bereiche (von-bis) und einzelne IP-Adressen, mehrere mit Komma getrennt." 'Warning'
        return
    }
    $script:NetzCidr = ($ziel.Bereiche.Label -join ', ')
    $anzeige = foreach ($b in $ziel.Bereiche) {
        if ($b.Label.Contains('/')) { '{0} ({1} - {2})' -f $b.Label, $b.Adressen[0], $b.Adressen[-1] } else { $b.Label }
    }
    $summe = if ($ziel.Bereiche.Count -gt 1) { " - $($ziel.Adressen.Count) Adressen" } else { '' }
    $script:C.TxtNetz.Text = "Scanbereich: $($anzeige -join '; ')$summe"
}

## Scan-Ergebnis einarbeiten: neue Geräte werden hinzugefügt, bekannte Geräte bekommen nur aktuelle IP, MAC, Hostname und Hersteller (der Status kommt aus der Statusprüfung)
function Merge-WolErgebnis {
    param($Ergebnis, $Info)
    $karte = @{}
    foreach ($b in $Info) { foreach ($a in $b.Adressen) { if (-not $karte.ContainsKey($a)) { $karte[$a] = $b } } }
    $jetzt = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $neue = 0
    $merkmale = 'Windows', 'NeustartAusstehend', 'LetzterNeustart', 'GeplantBis', 'OsModul', 'OsUpdates', 'OsLetzte', 'AppModul', 'AppUpdates', 'AppWinget', 'TrHersteller', 'TrModell', 'TrTool', 'TrUpdates'
    foreach ($f in $Ergebnis.Gefunden) {
        $zeile = $null
        if ($f.MAC) {
            ### Die MAC-Adresse ist ausschlaggebend
            $zeile = $script:Zeilen | Where-Object { $_.MAC -eq $f.MAC } | Select-Object -First 1
            foreach ($a in @($script:Zeilen | Where-Object { $_ -ne $zeile -and $_.IP -eq $f.IP })) {
                if ([string]::IsNullOrEmpty($a.MAC)) {
                    ### Zeile ohne MAC auf dieser IP (zum Beispiel aus der OU): mit der MAC-Zeile zusammenführen oder deren MAC erhalten
                    if (-not $zeile) { $zeile = $a; continue }
                    if (-not $zeile.Hostname) { $zeile.Hostname = $a.Hostname }
                    if (-not $zeile.Typ) { $zeile.Typ = $a.Typ }
                    if (-not $zeile.Konto) { $zeile.Konto = $a.Konto }
                    if (-not $zeile.Kennwort) { $zeile.Kennwort = $a.Kennwort }
                    if (-not $zeile.Bemerkung) { $zeile.Bemerkung = $a.Bemerkung }
                    foreach ($k in $merkmale) { if (-not $zeile[$k] -and $a[$k]) { $zeile[$k] = $a[$k] } }
                    [void]$script:Zeilen.Remove($a)
                    $script:Geaendert = $true
                }
                else {
                    ### Zeile mit anderer MAC auf dieser IP: die IP ist veraltet
                    $a.IP = ''
                    $a.Ampel = 'Unbekannt'
                    $a.Status = 'IP veraltet (unter dieser IP antwortet ein anderes Gerät)'
                    $script:Geaendert = $true
                    Write-WolLog "IP $($f.IP) gehört jetzt zur MAC $($f.MAC), bei $(if ($a.Hostname) { $a.Hostname } else { $a.MAC }) wurde die IP entfernt"
                }
            }
        }
        else {
            ### Ohne MAC (zum Beispiel anderes Netz): nur über die IP zuordnen, Zeilen ohne MAC zuerst
            $zeile = $script:Zeilen | Where-Object { $_.IP -eq $f.IP } | Sort-Object { [string]::IsNullOrEmpty($_.MAC) } -Descending | Select-Object -First 1
        }
        $neu = $false
        if (-not $zeile) {
            $zeile = New-Object NetCockpitZeile
            $script:Zeilen.Add($zeile)
            $neu = $true
            $neue++
        }
        $vorher = '{0}|{1}|{2}|{3}|{4}' -f $zeile.IP, $zeile.MAC, $zeile.Hostname, $zeile.Hersteller, $zeile.Subnetz
        $zeile.IP = $f.IP
        if ($f.MAC) { $zeile.MAC = $f.MAC }
        if ($f.Hostname) { $zeile.Hostname = $f.Hostname }
        if ($f.Hersteller) { $zeile.Hersteller = $f.Hersteller }
        $zeile.Subnetz = $karte[$f.IP].Label
        if ($neu) { $zeile.ZuletztGesehen = $jetzt }
        $nachher = '{0}|{1}|{2}|{3}|{4}' -f $zeile.IP, $zeile.MAC, $zeile.Hostname, $zeile.Hersteller, $zeile.Subnetz
        if ($neu -or $vorher -ne $nachher) { $script:Geaendert = $true }
        if ($neu -or $zeile.Status -like 'IP veraltet*') {
            if ($f.WinRM) { $zeile.Ampel = 'Gruen'; $zeile.Status = 'Online (WinRM erreichbar)' }
            else { $zeile.Ampel = 'Gelb'; $zeile.Status = 'Online (kein WinRM)' }
        }
    }
    if ($neue -eq 1) { $script:NeuHinweis = 'neues Gerät gefunden ({0:HH:mm})' -f (Get-Date) }
    elseif ($neue -gt 1) { $script:NeuHinweis = '{0} neue Geräte gefunden ({1:HH:mm})' -f $neue, (Get-Date) }
    else { $script:NeuHinweis = '' }
    $script:KudoHinweis = ''
    Update-WolAnsicht
    Update-WolScanAnzeige
}

## Auto-Scan-Timer einstellen
function Set-WolAutoScan {
    $script:AutoTimer.Stop()
    if (-not $script:Opt.AutoScan) { return }
    if (-not $script:ScanAktiv) { return }
    $min = 0
    if (-not [int]::TryParse($script:Opt.AutoMin, [ref]$min) -or $min -lt 1) {
        Show-WolMeldung 'Bitte für den Auto-Scan ganze Minuten ab 1 eingeben.' 'Warning'
        $script:Opt.AutoScan = $false
        return
    }
    if (-not $script:NetzCidr) {
        Show-WolMeldung 'Bitte zuerst ein Netz wählen.' 'Warning'
        $script:Opt.AutoScan = $false
        return
    }
    $script:AutoTimer.Interval = [TimeSpan]::FromMinutes($min)
    $script:AutoTimer.Start()
    Write-WolLog "Auto-Scan aktiv: alle $min Minuten"
}

# Statusprüfung
## Status aller Geräte der Geräteliste prüfen (unabhängig vom Scan)
function Start-WolStatusPruefung {
    if ($script:StatusJob) { return }
    $ips = [string[]]@($script:Zeilen | Where-Object { $_.IP } | ForEach-Object { $_.IP } | Select-Object -Unique)
    if ($ips.Count -eq 0) { return }
    $script:StatusJob = Start-ThreadJob -ScriptBlock $script:StatusBlock -ArgumentList $ips, 64
}

## Timer der Statusprüfung einstellen
function Set-WolStatusTimer {
    $script:StatusTimer.Stop()
    if (-not $script:Opt.Status) { return }
    $min = 0
    if (-not [int]::TryParse($script:Opt.StatusMin, [ref]$min) -or $min -lt 1) {
        Show-WolMeldung 'Bitte für die Statusprüfung ganze Minuten ab 1 eingeben.' 'Warning'
        $script:Opt.Status = $false
        return
    }
    $script:StatusTimer.Interval = [TimeSpan]::FromMinutes($min)
    $script:StatusTimer.Start()
    Write-WolLog "Statusprüfung aktiv: alle $min Minuten"
}

# Aktionen
## Neustart, Neustart planen, Herunterfahren, Abbrechen
function Start-WolAktion {
    param([string]$Art)
    $ziele = Get-WolMarkierte
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }

    $wert = 0
    $namen = ($ziele | ForEach-Object { if ($_.Hostname) { $_.Hostname } else { $_.IP } }) -join ', '
    if ($Art -eq 'Neustart' -or $Art -eq 'Herunterfahren') {
        $eingabe = Show-WolEingabe -Titel $Art -Frage "Nach wie vielen Sekunden soll der Befehl '$Art' ausgeführt werden? Mit 0 passiert es sofort." -Vorgabe '60'
        if ($null -eq $eingabe) { return }
        if (-not [int]::TryParse($eingabe.Trim(), [ref]$wert) -or $wert -lt 0) {
            Show-WolMeldung 'Bitte bei der Verzögerung ganze Sekunden eingeben.' 'Warning'
            return
        }
        $antwort = [System.Windows.MessageBox]::Show("$Art für $($ziele.Count) Gerät(e) in $wert Sekunden auslösen?`r`n`r`n$namen", 'NET-COCKPIT', 'YesNo', 'Warning')
        if ($antwort -ne 'Yes') { return }
    }
    elseif ($Art -eq 'Planen') {
        $zeit = Show-WolNeustartZeit -Namen $namen
        if (-not $zeit) { return }
        $wert = $zeit.ToString('yyyy-MM-dd HH:mm')
    }

    if (-not (Resolve-WolKonten -Zeilen @($ziele | Where-Object { $_.Ampel -eq 'Gruen' }))) { return }
    foreach ($z in $ziele) {
        if ($z.Ampel -ne 'Gruen') { $z.Status = 'WinRM nicht erreichbar - übersprungen'; continue }
        $ziel = Get-WolZielName -Zeile $z
        $konto = Get-WolAnmeldung -Zeile $z
        $text = switch ($Art) { 'Planen' { 'Neustart wird geplant...' } 'Abbrechen' { 'Abbruch wird gesendet...' } default { "$Art wird gesendet..." } }
        Add-WolAuftrag -Zeile $z -Block $script:AktionBlock -Argumente @($ziel, $Art, $wert, $konto, $script:ZielTaskCode) -Fertig $script:AktionFertig -Gruppe 'Aktion' -Daten @{ Art = $Art } -Starttext $text
        Write-WolLog "${Art}: $ziel"
    }
}

## Auswertung eines Aktionsauftrags (läuft im Poll-Timer)
$script:AktionFertig = {
    param($a)
    $z = $a.Zeile
    $art = $a.Daten.Art
    try {
        $ausgabe = @(Receive-Job -Job $a.Job -ErrorAction Stop)
        $letzte = $ausgabe | Select-Object -Last 1
        if ($null -eq $letzte) { throw 'keine Rückmeldung vom Ziel' }
        switch ($art) {
            'Planen' {
                $ziel = [datetime]::ParseExact([string]$letzte, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
                $z['GeplantBis'] = $ziel.ToString('yyyy-MM-dd HH:mm')
                $text = 'Neustart geplant {0:dd.MM. HH:mm}' -f $ziel
            }
            'Abbrechen' {
                $z['GeplantBis'] = ''
                if ($letzte.AbbruchCode -eq 0) { $text = 'Laufender Neustart oder Herunterfahren abgebrochen' }
                elseif ($letzte.TaskGeloescht) { $text = 'Geplanter Neustart abgebrochen' }
                else { $text = 'Es war nichts geplant oder laufend' }
            }
            'Pruefen' {
                $boot = [datetime]::ParseExact([string]$letzte.Boot, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
                $ziel = [datetime]::MinValue
                [void][datetime]::TryParseExact([string]$a.Daten.Ziel, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ziel)
                $z['GeplantBis'] = ''
                if ($boot -ge $ziel.AddMinutes(-2)) { $text = 'Neustart durchgeführt, Gerät läuft seit {0:dd.MM. HH:mm}' -f $boot }
                elseif ($letzte.Task) { $text = 'Neustart nicht erfolgt, geplante Aufgabe noch vorhanden' }
                else { $text = 'Geplanter Neustart nicht ausgeführt (abgebrochen oder Gerät war aus)' }
            }
            default {
                $code = [int]$letzte
                if ($code -eq 0) {
                    switch ($art) {
                        'Neustart'       { $text = 'Neustart ausgelöst um {0:yyyy-MM-dd HH:mm}' -f (Get-Date) }
                        'Herunterfahren' { $text = 'Herunterfahren ausgelöst um {0:yyyy-MM-dd HH:mm}' -f (Get-Date) }
                    }
                }
                else { $text = "shutdown.exe Rückgabecode $code" }
            }
        }
    }
    catch {
        $kurz = Register-WolVerbindungsfehler -Zeile $z -Text $_.Exception.Message
        $text = "Fehler: $kurz"
        Write-WolLog "Aktion-Fehlertext $($z.IP): $($_.Exception.Message)" -NurDatei
        if ($art -eq 'Pruefen') { $z['GeplantBis'] = '' }
    }
    $z.Status = $text
    Write-WolLog "$art $($z.IP): $text"
}

# Herstellerliste
## Download starten
function Start-WolHerstellerDownload {
    if (Get-WolGruppeOffen -Gruppe 'Oui') { return }
    Add-WolAuftrag -Zeile $null -Block $script:OuiBlock -Argumente @($script:OuiPfad) -Fertig $script:OuiFertig -Gruppe 'Oui'
    Write-WolLog 'Herstellerliste wird heruntergeladen...'
}

## Auswertung des Downloads (läuft im Poll-Timer)
$script:OuiFertig = {
    param($a)
    try {
        $erg = @(Receive-Job -Job $a.Job -ErrorAction Stop) | Select-Object -Last 1
        if ($erg.Quelle) { Write-WolLog "Herstellerliste geladen ($($erg.Quelle), $($erg.Anzahl) Einträge) - gilt ab dem nächsten Scan" }
        else { Write-WolLog 'Herstellerliste konnte nicht geladen werden' }
        if ($erg.Fehler) { Write-WolLog "Hinweis: $($erg.Fehler)" }
    }
    catch { Write-WolLog "Fehler bei der Herstellerliste: $($_.Exception.Message)" }
}

# Portscan
## Portscan für die markierten Geräte starten (nur nicht-rote Geräte, bis zu drei gleichzeitig)
function Start-WolPortscan {
    $ziele = Get-WolMarkierte
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    $auswahl = Show-WolPortDialog
    if (-not $auswahl) { return }
    foreach ($z in $ziele) {
        if ($z.Ampel -eq 'Rot') { $z.Status = 'Portscan übersprungen (offline)'; continue }
        if (-not $z.IP) { continue }
        $laeuft = $script:PortJobs | Where-Object { $_.Zeile -eq $z }
        $wartet = $script:PortWarteschlange | Where-Object { $_.Zeile -eq $z }
        if ($laeuft -or $wartet) { continue }
        $z.Ports = 'Portscan wartet...'
        $script:PortWarteschlange.Add([pscustomobject]@{ Zeile = $z; Ip = $z.IP; Ports = $auswahl.Ports; Bereich = $auswahl.Text })
    }
}

## Laufende und wartende Portscans abbrechen
function Stop-WolPortscan {
    foreach ($w in @($script:PortWarteschlange)) { $w.Zeile.Ports = 'Portscan abgebrochen' }
    $script:PortWarteschlange.Clear()
    foreach ($p in $script:PortJobs) { $p.Status.Abbruch = $true }
    Write-WolLog 'Portscan wird abgebrochen...'
}

# Befehl senden
## Fenster zum Eingeben und Ausführen eines PowerShell-Befehls auf den markierten, grünen Geräten
function Show-WolBefehl {
    if ((Get-WolGruppeOffen -Gruppe 'Befehl') -gt 0) {
        Show-WolMeldung 'Es läuft noch ein Befehl. Bitte warten, bis er fertig ist.'
        if ($script:BefehlFenster) { [void]$script:BefehlFenster.Activate() }
        return
    }
    $markiert = Get-WolMarkierte
    if ($markiert.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    $bereit = @($markiert | Where-Object { $_.Ampel -eq 'Gruen' })
    $uebersprungen = @($markiert | Where-Object { $_.Ampel -ne 'Gruen' })
    if ($bereit.Count -eq 0) { Show-WolMeldung 'Keines der markierten Geräte ist grün (WinRM erreichbar).'; return }
    if ($bereit.Count -gt $script:BefehlMax) {
        Show-WolMeldung "Es sind $($bereit.Count) erreichbare Geräte markiert. Pro Befehl sind höchstens $($script:BefehlMax) Geräte erlaubt."
        return
    }
    foreach ($z in $uebersprungen) { $z.Status = 'WinRM nicht erreichbar - übersprungen' }
    $script:BefehlZiele = $bereit

    if (-not $script:BefehlFenster) {
        $script:BefehlFenster = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NET-COCKPIT - PowerShell-Befehl senden" Width="920" Height="740" WindowStartupLocation="CenterOwner">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="170"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="TxtZiele" TextWrapping="Wrap" Margin="0,0,0,6" FontWeight="Bold"/>
    <TextBox x:Name="TxtBefehl" Grid.Row="1" AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
             HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="13"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,8,0,8">
      <Button x:Name="BtnAusfuehren" Content="Ausführen" Padding="22,6" FontWeight="Bold" Margin="0,0,8,0"/>
      <Button x:Name="BtnLaden" Content="Skript laden..." Padding="14,6" Margin="0,0,12,0"/>
      <TextBlock x:Name="TxtHinweis" Foreground="DimGray" VerticalAlignment="Center"
                 Text="Der gesamte Text wird als PowerShell auf den Zielgeräten ausgeführt. Eingaben (zum Beispiel Read-Host) funktionieren dort nicht."/>
    </StackPanel>
    <TabControl x:Name="Reiter" Grid.Row="3"/>
  </Grid>
</Window>
'@
        $script:BefehlFenster.Owner = $script:Fenster
        $script:BefehlBox = $script:BefehlFenster.FindName('TxtBefehl')
        $script:BefehlZielText = $script:BefehlFenster.FindName('TxtZiele')
        $script:BefehlKnopf = $script:BefehlFenster.FindName('BtnAusfuehren')
        $script:BefehlReiter = $script:BefehlFenster.FindName('Reiter')
        $script:BefehlBox.Text = $script:BefehlText
        $script:BefehlKnopf.Add_Click({ Start-WolBefehl })
        $script:BefehlFenster.FindName('BtnLaden').Add_Click({
            $dlg = [Microsoft.Win32.OpenFileDialog]::new()
            $dlg.Title = 'PowerShell-Skript laden'
            $dlg.Filter = 'PowerShell-Skripte (*.ps1)|*.ps1|Alle Dateien (*.*)|*.*'
            if ($dlg.ShowDialog($script:BefehlFenster)) {
                try { $script:BefehlBox.Text = Get-Content -Path $dlg.FileName -Raw -Encoding utf8 -ErrorAction Stop }
                catch { Show-WolMeldung "Das Skript konnte nicht geladen werden: $($_.Exception.Message)" 'Warning' }
            }
        })
        $script:BefehlFenster.Add_Closed({
            $script:BefehlText = $script:BefehlBox.Text
            Stop-WolGruppe -Gruppe 'Befehl'
            $script:BefehlFenster = $null
        })
        $script:BefehlFenster.Show()
    }
    $namen = ($script:BefehlZiele | ForEach-Object { if ($_.Hostname) { $_.Hostname.Split('.')[0] } else { $_.IP } }) -join ', '
    $script:BefehlZielText.Text = "Ziele ($($script:BefehlZiele.Count)): $namen"
    [void]$script:BefehlFenster.Activate()
    $script:BefehlBox.Focus() | Out-Null
}

## Befehl auf allen Zielgeräten gleichzeitig starten
function Start-WolBefehl {
    if ((Get-WolGruppeOffen -Gruppe 'Befehl') -gt 0) { return }
    $text = $script:BefehlBox.Text
    if ([string]::IsNullOrWhiteSpace($text)) { Show-WolMeldung 'Bitte zuerst einen Befehl eingeben.' 'Warning'; return }
    $script:BefehlText = $text
    if (-not (Resolve-WolKonten -Zeilen $script:BefehlZiele -Besitzer $script:BefehlFenster)) { return }
    $script:BefehlReiter.Items.Clear()
    $script:BefehlKnopf.IsEnabled = $false
    foreach ($z in $script:BefehlZiele) {
        $ziel = Get-WolZielName -Zeile $z
        $name = if ($z.Hostname) { $z.Hostname.Split('.')[0] } else { $z.IP }
        $box = [System.Windows.Controls.TextBox]::new()
        $box.IsReadOnly = $true
        $box.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
        $box.FontSize = 12
        $box.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $box.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $box.Text = '[{0:HH:mm:ss}] läuft...' -f (Get-Date)
        $tab = [System.Windows.Controls.TabItem]::new()
        $tab.Header = "$name (läuft)"
        $tab.Content = $box
        [void]$script:BefehlReiter.Items.Add($tab)
        $konto = Get-WolAnmeldung -Zeile $z
        Add-WolAuftrag -Zeile $z -Block $script:BefehlBlock -Argumente @($ziel, $text, $konto) -Fertig $script:BefehlFertig -Gruppe 'Befehl' -Daten @{ Name = $name; Box = $box; Tab = $tab } -Starttext 'Befehl wird ausgeführt...'
        Write-WolLog "Befehl gestartet: $ziel"
    }
    $script:BefehlReiter.SelectedIndex = 0
}

## Auswertung eines Befehlsauftrags (läuft im Poll-Timer)
$script:BefehlFertig = {
    param($b)
    $name = $b.Daten.Name
    $erfolg = $false
    try {
        $erg = @(Receive-Job -Job $b.Job -ErrorAction Stop) | Select-Object -Last 1
        $erfolg = [bool]$erg.Erfolg
        $ausgabe = [string]$erg.Ausgabe
    }
    catch { $ausgabe = "Fehler: $($_.Exception.Message)" }
    $kopf = if ($erfolg) { 'OK' } else { 'Fehler' }
    $b.Daten.Box.Text = ('[{0:HH:mm:ss}] fertig ({1})' -f (Get-Date), $kopf) + "`r`n`r`n" + $ausgabe
    $b.Daten.Tab.Header = '{0} ({1})' -f $name, $kopf
    if ($erfolg) { $b.Zeile.Status = 'Befehl ausgeführt' }
    elseif ($ausgabe -like 'Fehler: *') {
        $b.Zeile.Status = 'Befehl fehlgeschlagen: ' + (Register-WolVerbindungsfehler -Zeile $b.Zeile -Text $ausgabe.Substring(8))
        Write-WolLog "Befehl-Fehlertext ${name}: $ausgabe" -NurDatei
    }
    else { $b.Zeile.Status = 'Befehl mit Fehler beendet' }
    Write-WolLog "Befehl fertig: $name ($kopf)"
    if ((Get-WolGruppeOffen -Gruppe 'Befehl') -eq 0 -and $script:BefehlKnopf) { $script:BefehlKnopf.IsEnabled = $true }
}

# KuDo-Informationen
## Dateipfad der gespeicherten Informationen eines Geräts (Hostname ohne Domain, sonst IP-Adresse)
function Get-WolKudoPfad {
    param($Zeile)
    $name = if ($Zeile.Hostname) { ([string]$Zeile.Hostname).Split('.')[0] } else { [string]$Zeile.IP }
    $name = [regex]::Replace($name, '[\\/:*?"<>|\s]', '_')
    if (-not $name) { return $null }
    return Join-Path $script:GeraeteOrdner ($name + '.json')
}

## Gespeicherte Informationen eines Geräts lesen ($null, wenn es keine gibt)
function Get-WolKudoDaten {
    param($Zeile)
    $pfad = Get-WolKudoPfad -Zeile $Zeile
    if (-not $pfad -or -not (Test-Path $pfad)) { return $null }
    try { return (Get-Content -Path $pfad -Raw -Encoding utf8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch { return $null }
}

## Ergebnis speichern; Felder, die sich gegenüber dem letzten Stand geändert haben, werden mit dem alten Wert festgehalten
function Save-WolKudoDaten {
    param($Zeile, $Ergebnis)
    $pfad = Get-WolKudoPfad -Zeile $Zeile
    if (-not $pfad) { throw 'Das Gerät hat weder Hostname noch IP-Adresse.' }
    if (-not (Test-Path $script:GeraeteOrdner)) { New-Item -Path $script:GeraeteOrdner -ItemType Directory -Force | Out-Null }
    $alt = Get-WolKudoDaten -Zeile $Zeile
    $aenderungen = [System.Collections.Generic.List[object]]::new()
    $vorherStand = ''
    if ($alt) {
        $vorherStand = [string]$alt.Stand
        $altWerte = @{}
        foreach ($f in @($alt.Felder)) { $altWerte[[string]$f.Name] = [string]$f.Wert }
        foreach ($f in @($Ergebnis.Felder)) {
            $n = [string]$f.Name
            if ($altWerte.ContainsKey($n) -and $altWerte[$n] -ne [string]$f.Wert) {
                $aenderungen.Add([pscustomobject]@{ Name = $n; Vorher = $altWerte[$n] })
            }
        }
    }
    [ordered]@{
        Hostname    = [string]$Zeile.Hostname
        IP          = [string]$Zeile.IP
        Typ         = [string]$Ergebnis.Typ
        Stand       = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        VorherStand = $vorherStand
        Felder      = @($Ergebnis.Felder)
        Laufwerke   = @($Ergebnis.Laufwerke)
        Fussnote    = [string]$Ergebnis.Fussnote
        Aenderungen = @($aenderungen)
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $pfad -Encoding utf8
}

## Zeile mit Feldname, Wert (markierbar) und eigenem Kopieren-Knopf ins Detailfenster einfügen
function Add-WolKudoZeile {
    param($Panel, [string]$Name, [string]$Wert, $Vorher)
    $gitter = [System.Windows.Controls.Grid]::new()
    $gitter.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
    Set-WolZeilenHover -Gitter $gitter
    $spalte1 = [System.Windows.Controls.ColumnDefinition]::new()
    $spalte1.Width = [System.Windows.GridLength]::new(160)
    $spalte2 = [System.Windows.Controls.ColumnDefinition]::new()
    $spalte2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $spalte3 = [System.Windows.Controls.ColumnDefinition]::new()
    $spalte3.Width = [System.Windows.GridLength]::Auto
    [void]$gitter.ColumnDefinitions.Add($spalte1)
    [void]$gitter.ColumnDefinitions.Add($spalte2)
    [void]$gitter.ColumnDefinitions.Add($spalte3)

    $beschriftung = [System.Windows.Controls.TextBlock]::new()
    $beschriftung.Text = $Name
    $beschriftung.FontWeight = [System.Windows.FontWeights]::Bold
    $beschriftung.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $beschriftung.Margin = [System.Windows.Thickness]::new(0, 3, 8, 0)
    $beschriftung.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    [System.Windows.Controls.Grid]::SetColumn($beschriftung, 0)
    [void]$gitter.Children.Add($beschriftung)

    $inhalt = [System.Windows.Controls.StackPanel]::new()
    $feld = [System.Windows.Controls.TextBox]::new()
    $feld.Text = $Wert
    $feld.IsReadOnly = $true
    $feld.BorderThickness = [System.Windows.Thickness]::new(0)
    $feld.Background = [System.Windows.Media.Brushes]::Transparent
    $feld.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $feld.Padding = [System.Windows.Thickness]::new(0, 2, 0, 2)
    [void]$inhalt.Children.Add($feld)
    if ($null -ne $Vorher) {
        $feld.Foreground = [System.Windows.Media.Brushes]::DarkOrange
        $feld.FontWeight = [System.Windows.FontWeights]::SemiBold
        $hinweis = [System.Windows.Controls.TextBlock]::new()
        $hinweis.Text = "geändert, vorher: $Vorher"
        $hinweis.Foreground = [System.Windows.Media.Brushes]::DarkOrange
        $hinweis.FontSize = 11
        $hinweis.TextWrapping = [System.Windows.TextWrapping]::Wrap
        [void]$inhalt.Children.Add($hinweis)
    }
    [System.Windows.Controls.Grid]::SetColumn($inhalt, 1)
    [void]$gitter.Children.Add($inhalt)

    $knopf = [System.Windows.Controls.Button]::new()
    $knopf.Content = 'Kopieren'
    $knopf.Tag = $Wert
    $knopf.Padding = [System.Windows.Thickness]::new(10, 1, 10, 1)
    $knopf.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $knopf.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $knopf.Add_Click({
        try { [System.Windows.Clipboard]::SetText([string]$this.Tag) }
        catch { Show-WolMeldung 'Die Zwischenablage ist gerade belegt. Bitte noch einmal versuchen.' 'Warning' }
    })
    [System.Windows.Controls.Grid]::SetColumn($knopf, 2)
    [void]$gitter.Children.Add($knopf)
    [void]$Panel.Children.Add($gitter)
}

## Gespeicherte Informationen im Detailfenster anzeigen (jeder Wert hat einen eigenen Kopieren-Knopf)
function Show-WolKudoAnzeige {
    if (-not $script:KudoPanel) { return }
    $script:KudoPanel.Children.Clear()
    $daten = Get-WolKudoDaten -Zeile $script:KudoZeile
    if (-not $daten) {
        $script:KudoKopf.Text = 'KuDo-Informationen: noch nicht ausgelesen'
        $script:KudoKnopf.Content = 'Auslesen'
        return
    }
    $script:KudoKnopf.Content = 'Neu auslesen'
    $script:KudoKopf.Text = 'KuDo-Informationen ({0}, Stand {1})' -f $daten.Typ, $daten.Stand
    $aenderung = @{}
    foreach ($a in @($daten.Aenderungen)) { $aenderung[[string]$a.Name] = [string]$a.Vorher }
    if ($aenderung.Count -gt 0) {
        $hinweis = [System.Windows.Controls.TextBlock]::new()
        $hinweis.Text = "Orange: seit dem vorherigen Auslesen ($($daten.VorherStand)) geändert"
        $hinweis.Foreground = [System.Windows.Media.Brushes]::DarkOrange
        $hinweis.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        [void]$script:KudoPanel.Children.Add($hinweis)
    }
    foreach ($f in @($daten.Felder)) {
        $name = [string]$f.Name
        $vorher = $null
        if ($aenderung.ContainsKey($name)) { $vorher = $aenderung[$name] }
        Add-WolKudoZeile -Panel $script:KudoPanel -Name $name -Wert ([string]$f.Wert) -Vorher $vorher
    }
    $laufwerke = @($daten.Laufwerke)
    if ($laufwerke.Count -gt 0) {
        $kopf = [System.Windows.Controls.TextBlock]::new()
        $kopf.Text = 'Freier Speicher'
        $kopf.FontWeight = [System.Windows.FontWeights]::Bold
        $kopf.Margin = [System.Windows.Thickness]::new(0, 10, 0, 2)
        [void]$script:KudoPanel.Children.Add($kopf)
        foreach ($l in $laufwerke) {
            Add-WolLaufwerkZeile -Panel $script:KudoPanel -Laufwerk $l
        }
    }
    if ($daten.Fussnote) {
        $fuss = [System.Windows.Controls.TextBlock]::new()
        $fuss.Text = [string]$daten.Fussnote
        $fuss.Foreground = [System.Windows.Media.Brushes]::Gray
        $fuss.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
        [void]$script:KudoPanel.Children.Add($fuss)
    }
}

## Zusammenfassung am Ende eines Auslesens (Log und orange Statuszeile, kein Fenster)
function Show-WolKudoZusammenfassung {
    $st = $script:KudoStat
    if (-not $st) { return }
    $fehlerAnz = $st.Fehler.Count
    $text = 'KuDo: {0} von {1} ausgelesen' -f $st.Ok, $st.Gesamt
    if ($fehlerAnz -gt 0) { $text += ", $fehlerAnz fehlgeschlagen" }
    if ($st.Uebersprungen -gt 0) { $text += ", $($st.Uebersprungen) übersprungen" }
    if ($st.Ergaenzt -gt 0) { $text += ", bei $($st.Ergaenzt) Hostname/MAC/Hersteller ergänzt" }
    Write-WolLog $text
    $script:KudoHinweis = '{0} ({1:HH:mm})' -f $text, (Get-Date)
    Update-WolScanAnzeige
    $script:KudoStat = $null
    $script:OuiKarte = $null
}

## Art der Geräte bestimmen: Port 5985 (WinRM) zuerst = Windows (auch wenn SSH ebenfalls offen ist), sonst Port 22 (SSH) = Linux, sonst leer; alle Geräte werden gleichzeitig geprüft (höchstens 1,5 Sekunden)
function Get-WolKudoArt {
    param($Zeilen)
    $liste = [System.Collections.Generic.List[object]]::new()
    $aufgaben = [System.Collections.Generic.List[object]]::new()
    foreach ($z in @($Zeilen)) {
        $eintrag = [pscustomobject]@{ Zeile = $z; Tcp5985 = [System.Net.Sockets.TcpClient]::new(); Tcp22 = [System.Net.Sockets.TcpClient]::new(); Task5985 = $null; Task22 = $null }
        try { $eintrag.Task5985 = $eintrag.Tcp5985.ConnectAsync([string]$z.IP, 5985); $aufgaben.Add($eintrag.Task5985) } catch { }
        try { $eintrag.Task22 = $eintrag.Tcp22.ConnectAsync([string]$z.IP, 22); $aufgaben.Add($eintrag.Task22) } catch { }
        $liste.Add($eintrag)
    }
    try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($aufgaben), 1500) } catch { }
    $ergebnis = foreach ($e in $liste) {
        $winrm = ($e.Task5985 -and $e.Task5985.Status -eq 'RanToCompletion' -and $e.Tcp5985.Connected)
        $ssh = ($e.Task22 -and $e.Task22.Status -eq 'RanToCompletion' -and $e.Tcp22.Connected)
        $art = if ($winrm) { 'Windows' } elseif ($ssh) { 'Linux' } else { '' }
        $e.Tcp5985.Dispose()
        $e.Tcp22.Dispose()
        [pscustomobject]@{ Zeile = $e.Zeile; Art = $art }
    }
    return @($ergebnis)
}

## Ursache eines SSH-Fehlers in einem Satz (der volle Text steht in der Logdatei)
function Get-WolSshUrsache {
    param([string]$Text)
    if (-not $Text) { return 'unbekannte Ursache' }
    if ($Text -match 'Permission denied|Authentication|authenticat|password|Kennwort') { return 'Benutzer oder Kennwort wird nicht akzeptiert' }
    if ($Text -match 'host key|hostkey|fingerprint|Fingerabdruck|Hostschl|known.?host') { return 'der Hostschlüssel stimmt nicht mit dem gespeicherten überein' }
    if ($Text -match 'No such host|could not be resolved|Name or service|nicht aufgel') { return 'der Host ist nicht auflösbar' }
    if ($Text -match 'refused|timed out|timeout|Zeitüberschreitung|not established|No route|unreachable|actively') { return 'Port 22 (SSH) ist nicht erreichbar' }
    if ($Text -match 'Posh-SSH') { return 'das Modul Posh-SSH konnte nicht geladen werden' }
    return (Get-WolFehlerKurz -Text $Text)
}

## Vorprüfung der Linux-Geräte: Posh-SSH vorhanden, Konto eingetragen, SSH-Anmeldung möglich; bei einer Herausforderung Ja/Nein (Ja = Gerät überspringen, Nein = das ganze Auslesen abbrechen)
function Test-WolKudoLinux {
    param($Zeilen)
    $Zeilen = @($Zeilen)
    $ergebnis = @{ Abbruch = $false; Bereit = [System.Collections.Generic.List[object]]::new(); Uebersprungen = [System.Collections.Generic.List[object]]::new() }
    if ($Zeilen.Count -eq 0) { return $ergebnis }
    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        $frage = "Für Linux-Geräte braucht das Cockpit das PowerShell-Modul Posh-SSH. Es ist auf diesem Rechner nicht installiert.`r`n`r`nJetzt für dein Benutzerkonto installieren (Install-Module -Name Posh-SSH -Scope CurrentUser)? Dieser Rechner braucht dafür Internetzugang zur PSGallery.`r`n`r`nNein = die Linux-Geräte ($($Zeilen.Count)) werden übersprungen."
        if ([System.Windows.MessageBox]::Show($frage, 'Posh-SSH installieren', 'YesNo', 'Question') -eq 'Yes') {
            $alterZeiger = $script:Fenster.Cursor
            try {
                $script:Fenster.Cursor = [System.Windows.Input.Cursors]::Wait
                Write-WolLog 'Posh-SSH wird installiert...'
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                $ProgressPreference = 'SilentlyContinue'
                Install-Module -Name Posh-SSH -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
                Write-WolLog 'Posh-SSH installiert'
            }
            catch {
                Write-WolLog "Posh-SSH konnte nicht installiert werden: $($_.Exception.Message)"
                Show-WolMeldung "Posh-SSH konnte nicht installiert werden:`r`n`r`n$($_.Exception.Message)" 'Warning'
            }
            finally { $script:Fenster.Cursor = $alterZeiger }
        }
    }
    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        Show-WolMeldung "Posh-SSH ist nicht installiert. Die Linux-Geräte ($($Zeilen.Count)) werden übersprungen." 'Warning'
        foreach ($z in $Zeilen) { $z.Status = 'Posh-SSH fehlt - übersprungen'; $ergebnis.Uebersprungen.Add($z) }
        Write-WolLog "KuDo: Posh-SSH fehlt, $($Zeilen.Count) Linux-Gerät(e) übersprungen"
        return $ergebnis
    }

    ### Anmeldetests starten (parallel)
    $tests = [System.Collections.Generic.List[object]]::new()
    foreach ($z in $Zeilen) {
        $konto = $null
        $fehler = ''
        if (-not $z.Konto) { $fehler = 'In der Spalte "Konto" steht kein Benutzer. Für Linux muss dort der SSH-Benutzer stehen (nicht root, wenn root keinen SSH-Zugang hat).' }
        else { try { $konto = Get-WolAnmeldung -Zeile $z } catch { $fehler = $_.Exception.Message } }
        $job = $null
        if (-not $fehler) {
            try { $job = Start-ThreadJob -ScriptBlock $script:SshPruefBlock -ArgumentList @([string]$z.IP, $konto) }
            catch { $fehler = $_.Exception.Message }
        }
        $tests.Add([pscustomobject]@{ Zeile = $z; Konto = $konto; Job = $job; Fehler = $fehler })
    }
    $laufende = @($tests | Where-Object { $_.Job } | ForEach-Object { $_.Job })
    if ($laufende.Count -gt 0) {
        Write-WolLog "KuDo: SSH-Anmeldung wird geprüft ($($laufende.Count) Linux-Gerät(e))"
        $vorher = $script:Fenster.Cursor
        $script:Fenster.Cursor = [System.Windows.Input.Cursors]::Wait
        try { [void](Wait-Job -Job $laufende -Timeout 60) } finally { $script:Fenster.Cursor = $vorher }
    }

    ### Ergebnisse auswerten und bei einer Herausforderung nachfragen
    foreach ($t in $tests) {
        $z = $t.Zeile
        if ($t.Job) {
            if ($t.Job.State -eq 'Completed') {
                $erg = @(Receive-Job -Job $t.Job -ErrorAction SilentlyContinue) | Select-Object -Last 1
                if (-not $erg) { $t.Fehler = 'keine Rückmeldung' }
                elseif (-not $erg.Erfolg) { $t.Fehler = [string]$erg.Fehler }
            }
            else { $t.Fehler = 'Zeitüberschreitung bei der Anmeldung' }
            Remove-Job -Job $t.Job -Force -ErrorAction SilentlyContinue
        }
        if (-not $t.Fehler) { $ergebnis.Bereit.Add($z); continue }
        $name = if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { [string]$z.IP }
        $ursache = if ($t.Fehler -like 'In der Spalte*') { $t.Fehler } else { 'Ursache: ' + (Get-WolSshUrsache -Text $t.Fehler) }
        Write-WolLog "KuDo: SSH-Anmeldung fehlgeschlagen: $name - $ursache"
        Write-WolLog "KuDo-SSH-Fehlertext ${name}: $($t.Fehler)" -NurDatei
        $benutzer = if ($z.Konto) { [string]$z.Konto } else { '(keiner)' }
        $text = "Anmeldung am Linux-Gerät nicht möglich.`r`n`r`nGerät: $name ($($z.IP))`r`nBenutzer: $benutzer`r`n$ursache`r`n`r`nDieses Gerät überspringen und mit den übrigen weitermachen?`r`n`r`nJa = Gerät überspringen, es geht weiter`r`nNein = das gesamte Auslesen abbrechen"
        $antwort = [System.Windows.MessageBox]::Show($text, 'NET-COCKPIT', 'YesNo', 'Warning')
        if ($antwort -ne 'Yes') { $ergebnis.Abbruch = $true; return $ergebnis }
        $z.Status = 'SSH-Anmeldung fehlgeschlagen - übersprungen'
        $ergebnis.Uebersprungen.Add($z)
    }
    return $ergebnis
}

## Hostname, MAC und Hersteller aus dem Auslesen in die Tabelle ergänzen, aber nur in leere Zellen; Rückgabe: die ergänzten Spalten
function Set-WolKudoAdresse {
    param($Zeile, [string]$Mac, [string]$Hostname)
    $neu = [System.Collections.Generic.List[string]]::new()
    $name = if ($Zeile.Hostname) { ([string]$Zeile.Hostname).Split('.')[0] } else { [string]$Zeile.IP }
    $hex = ($Mac -replace '[^0-9A-Fa-f]', '').ToUpper()
    if (-not $Zeile.MAC -and $hex.Length -eq 12) {
        $m = $hex -replace '(.{2})(?!$)', '$1:'
        $andere = $script:Zeilen | Where-Object { $_ -ne $Zeile -and $_.MAC -eq $m } | Select-Object -First 1
        if ($andere) { Write-WolLog "MAC $m von $name steht schon in einer anderen Zeile (IP $($andere.IP)) und wurde nicht eingetragen" }
        else { $Zeile.MAC = $m; $neu.Add('MAC') }
    }
    if ($Zeile.MAC -and -not $Zeile.Hersteller) {
        $h = Get-WolHerstellerName -Mac ([string]$Zeile.MAC)
        if ($h) { $Zeile.Hersteller = $h; $neu.Add('Hersteller') }
    }
    if (-not $Zeile.Hostname -and $Hostname) { $Zeile.Hostname = $Hostname; $neu.Add('Hostname') }
    if ($neu.Count -gt 0) { $script:Geaendert = $true; Save-WolAuto }
    return @($neu)
}

## Informationen auslesen: Windows (WinRM) und Linux (SSH) je nach offenem Port; -Einzeln für ein Gerät aus dem Detailfenster
function Start-WolKudo {
    param($Ziele, [switch]$Einzeln)
    $Ziele = @($Ziele)
    if ($Ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    if (-not $Einzeln -and (Get-WolGruppeOffen -Gruppe 'Kudo') -gt 0) {
        Show-WolMeldung 'Es läuft noch ein Auslesen. Bitte warten, bis es fertig ist.'
        return
    }
    ### Offline-Geräte (rot) und Geräte ohne IP fallen sofort heraus, bei den übrigen entscheiden die Ports
    $offline = @($Ziele | Where-Object { $_.Ampel -eq 'Rot' -or -not $_.IP })
    $erreichbar = @($Ziele | Where-Object { $_.Ampel -ne 'Rot' -and $_.IP })
    foreach ($z in $offline) { $z.Status = 'Offline - übersprungen' }
    if ($erreichbar.Count -eq 0) { Show-WolMeldung 'Keines der Geräte ist erreichbar (alle offline).'; return }
    $arten = @(Get-WolKudoArt -Zeilen $erreichbar)
    $windows = @($arten | Where-Object { $_.Art -eq 'Windows' } | ForEach-Object { $_.Zeile })
    $linux = @($arten | Where-Object { $_.Art -eq 'Linux' } | ForEach-Object { $_.Zeile })
    $keine = @($arten | Where-Object { -not $_.Art } | ForEach-Object { $_.Zeile })
    foreach ($z in $keine) { $z.Status = 'Weder WinRM (5985) noch SSH (22) erreichbar - übersprungen' }
    if ($windows.Count + $linux.Count -eq 0) { Show-WolMeldung 'Bei keinem der Geräte ist WinRM (Port 5985) oder SSH (Port 22) erreichbar.'; return }
    if (-not (Resolve-WolKonten -Zeilen (@($windows) + @($linux)))) { return }
    $linuxBereit = @()
    $linuxUebersprungen = 0
    if ($linux.Count -gt 0) {
        $pruefung = Test-WolKudoLinux -Zeilen $linux
        if ($pruefung.Abbruch) {
            Write-WolLog 'KuDo-Auslesen abgebrochen (SSH-Anmeldung, Antwort Nein)'
            Show-WolMeldung 'Das Auslesen wurde abgebrochen. Es wurde nichts ausgelesen.'
            return
        }
        $linuxBereit = @($pruefung.Bereit)
        $linuxUebersprungen = $pruefung.Uebersprungen.Count
    }
    if (-not $script:KudoStat) {
        $script:KudoStat = @{ Gesamt = 0; Ok = 0; Uebersprungen = 0; Ergaenzt = 0; Fehler = [System.Collections.Generic.List[string]]::new(); Meldung = (-not $Einzeln) }
    }
    $script:KudoStat.Uebersprungen += $offline.Count + $keine.Count + $linuxUebersprungen
    $gestartet = 0
    foreach ($z in $windows) {
        if ((Get-WolGruppeOffen -Gruppe 'Kudo' -Zeile $z) -gt 0) { continue }
        $ziel = Get-WolZielName -Zeile $z
        $name = if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { $z.IP }
        $typ = ([string]$z.Typ).Trim()
        $konto = Get-WolAnmeldung -Zeile $z
        Add-WolAuftrag -Zeile $z -Block $script:KudoBlock -Argumente @($ziel, $typ, $konto, [string]$z.IP) -Fertig $script:KudoFertig -Gruppe 'Kudo' -Daten @{ Name = $name } -Starttext 'KuDo-Informationen werden ausgelesen...'
        $script:KudoStat.Gesamt++
        $gestartet++
    }
    foreach ($z in $linuxBereit) {
        if ((Get-WolGruppeOffen -Gruppe 'Kudo' -Zeile $z) -gt 0) { continue }
        $name = if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { $z.IP }
        $typ = ([string]$z.Typ).Trim()
        $konto = Get-WolAnmeldung -Zeile $z
        Add-WolAuftrag -Zeile $z -Block $script:KudoLinuxBlock -Argumente @([string]$z.IP, $typ, $konto, [string]$z.IP) -Fertig $script:KudoFertig -Gruppe 'Kudo' -Daten @{ Name = $name } -Starttext 'KuDo-Informationen werden per SSH ausgelesen...'
        $script:KudoStat.Gesamt++
        $gestartet++
    }
    if ($gestartet -eq 0) { $script:KudoStat = $null; return }
    Write-WolLog "KuDo-Informationen werden ausgelesen: $gestartet Gerät(e) ($($windows.Count) Windows, $($linuxBereit.Count) Linux)"
}

## Auswertung eines KuDo-Auftrags (läuft im Poll-Timer)
$script:KudoFertig = {
    param($k)
    $fehler = ''
    $ergaenzt = @()
    try {
        $erg = @(Receive-Job -Job $k.Job -ErrorAction Stop) | Select-Object -Last 1
        if (-not $erg) { $fehler = 'keine Rückmeldung vom Zielgerät' }
        elseif (-not $erg.Erfolg) { $fehler = [string]$erg.Fehler }
        else {
            ### Hostname, MAC und Hersteller nur in leere Zellen eintragen; die gespeicherte Datei heißt nach dem Hostnamen und zieht bei einem neuen Hostnamen mit um
            $pfadVor = Get-WolKudoPfad -Zeile $k.Zeile
            $ergaenzt = @(Set-WolKudoAdresse -Zeile $k.Zeile -Mac ([string]$erg.Mac) -Hostname ([string]$erg.Hostname))
            $pfadNach = Get-WolKudoPfad -Zeile $k.Zeile
            if ($pfadVor -and $pfadNach -and $pfadVor -ne $pfadNach -and (Test-Path -LiteralPath $pfadVor) -and -not (Test-Path -LiteralPath $pfadNach)) {
                Move-Item -LiteralPath $pfadVor -Destination $pfadNach -ErrorAction SilentlyContinue
            }
            Save-WolKudoDaten -Zeile $k.Zeile -Ergebnis $erg
            if ($ergaenzt.Count -gt 0) {
                if ($script:KudoStat) { $script:KudoStat.Ergaenzt++ }
                Write-WolLog "KuDo: $($k.Daten.Name) - ergänzt: $($ergaenzt -join ', ')"
                Update-WolAnsicht
            }
            if (-not ([string]$k.Zeile.Typ).Trim()) {
                $k.Zeile.Typ = [string]$erg.Typ
                $script:Geaendert = $true
                Save-WolAuto
            }
        }
    }
    catch { $fehler = $_.Exception.Message }
    if ($fehler) {
        $kurz = Register-WolVerbindungsfehler -Zeile $k.Zeile -Text $fehler
        $k.Zeile.Status = "Auslesen fehlgeschlagen: $kurz"
        if ($script:KudoStat) { $script:KudoStat.Fehler.Add("$($k.Daten.Name): $kurz") }
        Write-WolLog "KuDo-Informationen fehlgeschlagen: $($k.Daten.Name) - $kurz"
        Write-WolLog "KuDo-Fehlertext $($k.Daten.Name): $fehler" -NurDatei
    }
    else {
        $k.Zeile.Status = 'KuDo-Informationen ausgelesen um {0:HH:mm}' -f (Get-Date)
        if ($ergaenzt.Count -gt 0) { $k.Zeile.Status += ' (ergänzt: ' + ($ergaenzt -join ', ') + ')' }
        if ($script:KudoStat) { $script:KudoStat.Ok++ }
        Write-WolLog "KuDo-Informationen ausgelesen: $($k.Daten.Name)"
    }
    if ($script:KudoPanel -and $script:KudoZeile -eq $k.Zeile) { Show-WolKudoAnzeige }
    if ((Get-WolGruppeOffen -Gruppe 'Kudo') -eq 0) { Show-WolKudoZusammenfassung }
}

## Markierte Geräte auslesen (Menü Werkzeuge)
function Start-WolKudoMarkierte {
    Start-WolKudo -Ziele (Get-WolMarkierte)
}

# Export
## Fenster: Zeilen (sichtbare oder markierte) und Felder wählen; Rückgabe: Auswahl oder $null bei Abbruch
function Show-WolExportDialog {
    param([int]$AnzahlSichtbar, [int]$AnzahlMarkiert, $ListenFelder, [string[]]$KudoFelder)
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NET-COCKPIT - Geräteliste exportieren" Width="520" Height="640" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <GroupBox Header="Zeilen" Margin="0,0,0,10">
      <StackPanel Margin="8,6,8,6">
        <RadioButton x:Name="RbSichtbar" GroupName="Zeilen" IsChecked="True" Margin="0,2"/>
        <RadioButton x:Name="RbMarkiert" GroupName="Zeilen" Margin="0,2"/>
      </StackPanel>
    </GroupBox>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,6">
      <TextBlock Text="Felder:" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,12,0"/>
      <Button x:Name="BtnAlle" Content="Alle" Padding="12,2" Margin="0,0,6,0"/>
      <Button x:Name="BtnKeine" Content="Keine" Padding="12,2"/>
    </StackPanel>
    <Border Grid.Row="2" BorderBrush="#CCCCCC" BorderThickness="1">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="Felder" Margin="8,4,8,6"/>
      </ScrollViewer>
    </Border>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnOk" Content="Exportieren..." IsDefault="True" Width="120" Padding="0,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnAbbruch" Content="Abbrechen" IsCancel="True" Width="90" Padding="0,4"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $d.Owner = $script:Fenster
    $script:ExportFenster = $d
    $script:ExportErgebnis = $null
    $script:ExportBoxen = [System.Collections.Generic.List[object]]::new()
    $rbMarkiert = $d.FindName('RbMarkiert')
    $d.FindName('RbSichtbar').Content = "Sichtbare Zeilen ($AnzahlSichtbar, mit den aktuellen Filtern)"
    $rbMarkiert.Content = "Markierte Zeilen ($AnzahlMarkiert)"
    $rbMarkiert.IsEnabled = ($AnzahlMarkiert -gt 0)

    $panel = $d.FindName('Felder')
    $kopf = [System.Windows.Controls.TextBlock]::new()
    $kopf.Text = 'Geräteliste'
    $kopf.FontWeight = [System.Windows.FontWeights]::Bold
    $kopf.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
    [void]$panel.Children.Add($kopf)
    foreach ($f in $ListenFelder) {
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.Content = [string]$f.Titel
        $cb.Tag = [pscustomobject]@{ Art = 'Liste'; Name = [string]$f.Titel; Eig = [string]$f.Eig }
        $cb.IsChecked = $true
        $cb.Margin = [System.Windows.Thickness]::new(8, 2, 0, 2)
        [void]$panel.Children.Add($cb)
        $script:ExportBoxen.Add($cb)
    }
    if ($KudoFelder.Count -gt 0) {
        $kopf2 = [System.Windows.Controls.TextBlock]::new()
        $kopf2.Text = 'KuDo-Informationen (soweit ausgelesen)'
        $kopf2.FontWeight = [System.Windows.FontWeights]::Bold
        $kopf2.Margin = [System.Windows.Thickness]::new(0, 12, 0, 4)
        [void]$panel.Children.Add($kopf2)
        foreach ($name in $KudoFelder) {
            $cb = [System.Windows.Controls.CheckBox]::new()
            $cb.Content = $name
            $cb.Tag = [pscustomobject]@{ Art = 'Kudo'; Name = $name; Eig = '' }
            $cb.IsChecked = $false
            $cb.Margin = [System.Windows.Thickness]::new(8, 2, 0, 2)
            [void]$panel.Children.Add($cb)
            $script:ExportBoxen.Add($cb)
        }
    }

    $d.FindName('BtnAlle').Add_Click({ foreach ($b in $script:ExportBoxen) { $b.IsChecked = $true } })
    $d.FindName('BtnKeine').Add_Click({ foreach ($b in $script:ExportBoxen) { $b.IsChecked = $false } })
    $d.FindName('BtnOk').Add_Click({
        $gewaehlt = @($script:ExportBoxen | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($gewaehlt.Count -eq 0) { Show-WolMeldung 'Bitte mindestens ein Feld auswählen.' 'Warning'; return }
        $script:ExportErgebnis = [pscustomobject]@{
            Markiert = [bool]$script:ExportFenster.FindName('RbMarkiert').IsChecked
            Felder   = $gewaehlt
        }
        $script:ExportFenster.DialogResult = $true
    })
    [void]$d.ShowDialog()
    return $script:ExportErgebnis
}

## Geräteliste exportieren (Textdatei mit Semikolon und Kopfzeile)
function Export-WolListe {
    Complete-WolBearbeitung
    $sichtbar = @($script:Ansicht)
    if ($sichtbar.Count -eq 0) { Show-WolMeldung 'Es sind keine Zeilen sichtbar, die exportiert werden könnten.'; return }
    $markiert = @(Get-WolMarkierte)
    $listenFelder = @(
        @{ Titel = 'Hostname'; Eig = 'Hostname' }
        @{ Titel = 'Typ'; Eig = 'Typ' }
        @{ Titel = 'Konto'; Eig = 'Konto' }
        @{ Titel = 'IP'; Eig = 'IP' }
        @{ Titel = 'MAC'; Eig = 'MAC' }
        @{ Titel = 'Hersteller'; Eig = 'Hersteller' }
        @{ Titel = 'Subnetz'; Eig = 'Subnetz' }
        @{ Titel = 'Zuletzt gesehen'; Eig = 'ZuletztGesehen' }
        @{ Titel = 'Offene Ports'; Eig = 'Ports' }
        @{ Titel = 'Bemerkung'; Eig = 'Bemerkung' }
    )

    ### KuDo-Felder, die bei mindestens einem Gerät gespeichert sind
    $kudoNamen = [System.Collections.Generic.List[string]]::new()
    $kudoVorhanden = $false
    foreach ($z in $script:Zeilen) {
        $daten = Get-WolKudoDaten -Zeile $z
        if (-not $daten) { continue }
        $kudoVorhanden = $true
        foreach ($f in @($daten.Felder)) {
            if (-not $kudoNamen.Contains([string]$f.Name)) { $kudoNamen.Add([string]$f.Name) }
        }
    }
    if ($kudoVorhanden) {
        foreach ($extra in 'Laufwerke', 'KuDo-Stand') {
            if (-not $kudoNamen.Contains($extra)) { $kudoNamen.Add($extra) }
        }
    }

    $wahl = Show-WolExportDialog -AnzahlSichtbar $sichtbar.Count -AnzahlMarkiert $markiert.Count -ListenFelder $listenFelder -KudoFelder @($kudoNamen)
    if (-not $wahl) { return }
    $zeilen = @(if ($wahl.Markiert) { $markiert } else { $sichtbar })

    $dlg = [Microsoft.Win32.SaveFileDialog]::new()
    $dlg.Title = 'Geräteliste exportieren'
    $dlg.InitialDirectory = Get-WolStartOrdner
    $dlg.Filter = 'Textdatei (*.txt)|*.txt|Alle Dateien (*.*)|*.*'
    $dlg.FileName = 'Export-NET-COCKPIT_{0:yyyyMMdd}.txt' -f (Get-Date)
    if (-not $dlg.ShowDialog()) { return }

    ### Kopfzeilen der KuDo-Felder (bei gleichem Namen wie ein Listenfeld mit Vorsatz "KuDo ")
    $listeGewaehlt = @($wahl.Felder | Where-Object { $_.Art -eq 'Liste' })
    $kudoGewaehlt = @($wahl.Felder | Where-Object { $_.Art -eq 'Kudo' })
    $listenTitel = @($listeGewaehlt | ForEach-Object { $_.Name })
    $kopfName = @{}
    foreach ($f in $kudoGewaehlt) {
        if ($listenTitel -contains $f.Name) { $kopfName[$f.Name] = 'KuDo ' + $f.Name } else { $kopfName[$f.Name] = $f.Name }
    }

    try {
        $zeilen | ForEach-Object {
            $z = $_
            $o = [ordered]@{}
            foreach ($f in $listeGewaehlt) { $o[$f.Name] = [string]$z.($f.Eig) }
            if ($kudoGewaehlt.Count -gt 0) {
                $daten = Get-WolKudoDaten -Zeile $z
                $karte = @{}
                $laufwerke = ''
                $stand = ''
                if ($daten) {
                    foreach ($feld in @($daten.Felder)) { $karte[[string]$feld.Name] = [string]$feld.Wert }
                    $laufwerke = (@($daten.Laufwerke) | ForEach-Object { '{0}; {1}; {2}' -f $_.Laufwerk, $_.Frei, $_.Gesamt }) -join ' | '
                    $stand = [string]$daten.Stand
                }
                foreach ($f in $kudoGewaehlt) {
                    $wert = ''
                    if ($f.Name -eq 'Laufwerke') { $wert = $laufwerke }
                    elseif ($f.Name -eq 'KuDo-Stand') { $wert = $stand }
                    elseif ($karte.ContainsKey($f.Name)) { $wert = $karte[$f.Name] }
                    $o[$kopfName[$f.Name]] = $wert
                }
            }
            [pscustomobject]$o
        } | Export-Csv -Path $dlg.FileName -Delimiter ';' -NoTypeInformation -UseQuotes AsNeeded -Encoding utf8BOM
        Write-WolLog "Export: $($zeilen.Count) Zeile(n), $(@($wahl.Felder).Count) Feld(er) nach $($dlg.FileName)"
    }
    catch { Show-WolMeldung "Der Export ist fehlgeschlagen: $($_.Exception.Message)" 'Warning' }
}

# Konto pro Gerät
## Eigenes Konto der angegebenen Geräte entfernen (sie nutzen danach das angemeldete Windows-Konto)
function Reset-WolKontoZeilen {
    param($Zeilen)
    foreach ($z in $Zeilen) { $z.Konto = ''; $z.Kennwort = $null }
    $script:Geaendert = $true
    Save-WolAuto
    Update-WolAnsicht
    Write-WolLog "Eigenes Konto entfernt bei $(@($Zeilen).Count) Gerät(en), es gilt das angemeldete Konto"
}

## Konto für die markierten Geräte setzen (der Benutzername wird in der Geräteliste gespeichert, das Kennwort nur für diese Sitzung gemerkt)
function Set-WolKontoMarkierte {
    $ziele = Get-WolMarkierte
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    $text = "Mit welchem Konto sollen die $($ziele.Count) markierten Geräte angesprochen werden? Benutzername als Domäne\Benutzer, .\Benutzer (lokales Konto des Geräts) oder als UPN. Das Kennwort wird nur für diese Sitzung gemerkt, der Benutzername steht in der Geräteliste.`r`n`r`nMit `"Mit aktuellem Konto verbinden`" entfällt das eigene Konto; es gilt dann das Windows-Konto, mit dem Du angemeldet bist ($([NetCockpitZeile]::StandardKonto))."
    ### Benutzername vorbelegen, wenn alle markierten Geräte dasselbe Konto haben
    $konten = @($ziele | ForEach-Object { ([string]$_.Konto).Trim() } | Sort-Object -Unique)
    $vorgabe = if ($konten.Count -eq 1) { $konten[0] } else { '' }
    $erg = Show-WolAnmeldung -Titel 'Konto für markierte Geräte' -Text $text -Benutzer $vorgabe
    if (-not $erg) { return }
    if ($erg -is [string]) { Reset-WolKontoZeilen -Zeilen $ziele; return }
    foreach ($z in $ziele) {
        ### Kennwort: neues übernehmen; leer = bisheriges behalten, solange der Benutzername gleich bleibt, sonst bei der ersten Aktion abfragen
        if ($erg.Password) { $z.Kennwort = $erg.Password }
        elseif (([string]$z.Konto) -ne $erg.UserName) { $z.Kennwort = $null }
        $z.Konto = $erg.UserName
    }
    $script:Geaendert = $true
    Save-WolAuto
    Update-WolAnsicht
    Write-WolLog "Konto $($erg.UserName) für $($ziele.Count) Gerät(e) gesetzt"
}

# TrustedHosts
## Läuft das Cockpit mit Administratorrechten?
function Test-WolAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return ([System.Security.Principal.WindowsPrincipal]::new($id)).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

## TrustedHosts dieses Rechners als Liste lesen
function Get-WolTrustedHosts {
    $wert = [string](Get-Item -Path WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
    return @($wert -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

## Geräte als TrustedHost eintragen (bestehende Einträge bleiben, Doppelte werden vermieden); ohne -Zeilen die markierten, mit -OhneFrage ohne eigene Rückfrage (wenn der Aufrufer schon gefragt hat)
function Add-WolTrustedHosts {
    param($Zeilen, [switch]$OhneFrage)
    $ziele = if ($PSBoundParameters.ContainsKey('Zeilen')) { @($Zeilen) } else { @(Get-WolMarkierte) }
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    if (-not (Test-WolAdmin)) {
        Show-WolMeldung 'Für die TrustedHosts braucht das Cockpit Administratorrechte. Bitte PowerShell 7 als Administrator starten und das Cockpit neu öffnen.' 'Warning'
        return
    }
    try { $vorhanden = @(Get-WolTrustedHosts) }
    catch { Show-WolMeldung "Die TrustedHosts konnten nicht gelesen werden: $($_.Exception.Message)" 'Warning'; return }
    if ($vorhanden -contains '*') { Show-WolMeldung 'In den TrustedHosts steht bereits * (alle Hosts). Es ist nichts einzutragen.'; return }
    $neu = [System.Collections.Generic.List[string]]::new()
    $schonDa = [System.Collections.Generic.List[string]]::new()
    foreach ($z in $ziele) {
        $name = Get-WolZielName -Zeile $z
        if (-not $name) { continue }
        if ($vorhanden -contains $name) { if (-not $schonDa.Contains($name)) { $schonDa.Add($name) } }
        elseif (-not $neu.Contains($name)) { $neu.Add($name) }
    }
    if ($neu.Count -eq 0) {
        Write-WolLog "TrustedHosts: alle $($schonDa.Count) Geräte stehen schon drin"
        Show-WolMeldung 'Alle Geräte stehen schon in den TrustedHosts.'
        return
    }
    if (-not $OhneFrage) {
        $frage = "Diese Geräte als TrustedHosts auf diesem Rechner eintragen?`r`n`r`n$($neu -join ', ')`r`n`r`nFür TrustedHosts prüft WinRM die Identität der Gegenstelle nicht."
        if ([System.Windows.MessageBox]::Show($frage, 'NET-COCKPIT', 'YesNo', 'Warning') -ne 'Yes') { return }
    }
    try {
        Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value ((@($vorhanden) + @($neu)) -join ',') -Force -ErrorAction Stop
        Write-WolLog "TrustedHosts eingetragen: $($neu -join ', ')"
        if ($schonDa.Count -gt 0) { Write-WolLog "TrustedHosts schon vorhanden: $($schonDa -join ', ')" }
    }
    catch { Show-WolMeldung "Die TrustedHosts konnten nicht geändert werden: $($_.Exception.Message)" 'Warning' }
}

## Markierte Geräte aus den TrustedHosts entfernen
function Remove-WolTrustedHosts {
    $ziele = Get-WolMarkierte
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    if (-not (Test-WolAdmin)) {
        Show-WolMeldung 'Für die TrustedHosts braucht das Cockpit Administratorrechte. Bitte PowerShell 7 als Administrator starten und das Cockpit neu öffnen.' 'Warning'
        return
    }
    try { $vorhanden = @(Get-WolTrustedHosts) }
    catch { Show-WolMeldung "Die TrustedHosts konnten nicht gelesen werden: $($_.Exception.Message)" 'Warning'; return }
    if ($vorhanden -contains '*') { Show-WolMeldung 'In den TrustedHosts steht * (alle Hosts). Das Cockpit entfernt keine einzelnen Geräte daraus.'; return }
    $namen = @($ziele | ForEach-Object { Get-WolZielName -Zeile $_ } | Where-Object { $_ })
    $entfernen = @($vorhanden | Where-Object { $namen -contains $_ })
    if ($entfernen.Count -eq 0) { Show-WolMeldung 'Keines der markierten Geräte steht in den TrustedHosts.'; return }
    $frage = "Diese Geräte aus den TrustedHosts dieses Rechners entfernen?`r`n`r`n$($entfernen -join ', ')"
    if ([System.Windows.MessageBox]::Show($frage, 'NET-COCKPIT', 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $rest = @($vorhanden | Where-Object { $entfernen -notcontains $_ })
        Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value ($rest -join ',') -Force -ErrorAction Stop
        Write-WolLog "TrustedHosts entfernt: $($entfernen -join ', ')"
    }
    catch { Show-WolMeldung "Die TrustedHosts konnten nicht geändert werden: $($_.Exception.Message)" 'Warning' }
}

## TrustedHosts dieses Rechners anzeigen
function Show-WolTrustedHosts {
    try { $vorhanden = @(Get-WolTrustedHosts) }
    catch { Show-WolMeldung "Die TrustedHosts konnten nicht gelesen werden: $($_.Exception.Message)" 'Warning'; return }
    if ($vorhanden.Count -eq 0) { Show-WolMeldung 'Die TrustedHosts dieses Rechners sind leer.'; return }
    Show-WolMeldung ("TrustedHosts dieses Rechners ($($vorhanden.Count)):`r`n`r`n" + ($vorhanden -join "`r`n"))
}

## Verbindungsfehler einer Zeile auswerten: liefert den Kurztext und merkt sich Geräte, bei denen die TrustedHosts fehlen
function Register-WolVerbindungsfehler {
    param($Zeile, [string]$Text)
    $kurz = Get-WolFehlerKurz -Text $Text
    if ($kurz -eq 'TrustedHosts fehlt' -and $Zeile -and -not $script:TrustedOffen.Contains($Zeile)) { $script:TrustedOffen.Add($Zeile) }
    return $kurz
}

## Wenn keine Aufträge mehr laufen: einmal anbieten, die betroffenen Geräte als TrustedHost einzutragen
function Test-WolTrustedHinweis {
    if ($script:TrustedOffen.Count -eq 0 -or $script:TrustedDialog) { return }
    if ($script:AuftragJobs.Count -gt 0 -or $script:Warteschlange.Count -gt 0) { return }
    $script:TrustedDialog = $true
    $script:PollTimer.Stop()
    try {
        $zeilen = @($script:TrustedOffen | Where-Object { $script:Zeilen.Contains($_) })
        $script:TrustedOffen.Clear()
        if ($zeilen.Count -eq 0) { return }
        $namen = @($zeilen | ForEach-Object { Get-WolZielName -Zeile $_ })
        $liste = if ($namen.Count -gt 12) { (($namen | Select-Object -First 12) -join ', ') + " ... (und $($namen.Count - 12) weitere)" } else { $namen -join ', ' }
        $frage = "Die Verbindung zu $($zeilen.Count) Gerät(en) ist an den TrustedHosts gescheitert:`r`n`r`n$liste`r`n`r`nJetzt als TrustedHost auf diesem Rechner eintragen? Für TrustedHosts prüft WinRM die Identität der Gegenstelle nicht. Danach die Aktion erneut ausführen."
        if ([System.Windows.MessageBox]::Show($frage, 'NET-COCKPIT', 'YesNo', 'Warning') -eq 'Yes') {
            Add-WolTrustedHosts -Zeilen $zeilen -OhneFrage
        }
    }
    finally {
        $script:TrustedDialog = $false
        $script:PollTimer.Start()
    }
}

# Dauerping
## Zeile ins Ping-Log schreiben (Timeouts ganz blass), scrollt nur mit, wenn am Ende
function Add-WolPingZeile {
    param($Box, [string]$Text, [bool]$Blass)
    $amEnde = ($Box.VerticalOffset + $Box.ViewportHeight) -ge ($Box.ExtentHeight - 2)
    $p = [System.Windows.Documents.Paragraph]::new([System.Windows.Documents.Run]::new($Text))
    $p.Margin = [System.Windows.Thickness]::new(0)
    if ($Blass) { $p.Foreground = [System.Windows.Media.Brushes]::Silver }
    $Box.Document.Blocks.Add($p)
    while ($Box.Document.Blocks.Count -gt 2000) { $Box.Document.Blocks.Remove($Box.Document.Blocks.FirstBlock) }
    if ($amEnde) { $Box.ScrollToEnd() }
}

## Ping-Tab schließen und Ping stoppen
function Stop-WolPingTab {
    param([string]$Ip)
    $t = $script:PingTabs | Where-Object { $_.IP -eq $Ip } | Select-Object -First 1
    if (-not $t) { return }
    $script:PingTabsCtl.Items.Remove($t.Tab)
    try { $t.Ping.Dispose() } catch { }
    [void]$script:PingTabs.Remove($t)
}

## Ping-Takt: Ergebnisse auswerten, nächsten Ping jede Sekunde senden
function Update-WolPing {
    foreach ($t in @($script:PingTabs)) {
        if ($t.Task -and $t.Task.IsCompleted) {
            $zeit = Get-Date -Format 'HH:mm:ss'
            $t.Gesendet++
            if ($t.Task.IsFaulted -or $t.Task.IsCanceled) {
                Add-WolPingZeile -Box $t.Box -Text "$zeit  Fehler beim Senden" -Blass $true
                $t.Verloren++
            }
            else {
                $r = $t.Task.Result
                if ($r.Status -eq 'Success') { Add-WolPingZeile -Box $t.Box -Text "$zeit  Antwort von $($t.IP): $($r.RoundtripTime) ms" -Blass $false }
                elseif ($r.Status -eq 'TimedOut') { Add-WolPingZeile -Box $t.Box -Text "$zeit  Zeitüberschreitung" -Blass $true; $t.Verloren++ }
                else { Add-WolPingZeile -Box $t.Box -Text "$zeit  $($r.Status)" -Blass $true; $t.Verloren++ }
            }
            $t.Task = $null
            $t.Stat.Text = "Gesendet: $($t.Gesendet)   Verloren: $($t.Verloren)"
        }
        if (-not $t.Task -and (Get-Date) -ge $t.Naechster) {
            $t.Naechster = (Get-Date).AddSeconds(1)
            try { $t.Task = $t.Ping.SendPingAsync($t.IP, 1000) } catch { }
        }
    }
}

## Pingfenster öffnen (eigenes, nicht blockierendes Fenster) und je markiertem Gerät einen Tab anlegen
function Show-WolPing {
    $ziele = Get-WolMarkierte
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    if ($ziele.Count -gt $script:BefehlMax) {
        Show-WolMeldung "Es sind $($ziele.Count) Geräte markiert. Für den Dauerping sind höchstens $($script:BefehlMax) Geräte gleichzeitig erlaubt."
        return
    }

    if (-not $script:PingFenster) {
        $script:PingFenster = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NET-COCKPIT - Dauerping" Width="720" Height="480" WindowStartupLocation="CenterOwner">
  <TabControl x:Name="Tabs" Margin="6"/>
</Window>
'@
        $script:PingFenster.Owner = $script:Fenster
        $script:PingTabsCtl = $script:PingFenster.FindName('Tabs')
        $script:PingTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:PingTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $script:PingTimer.Add_Tick({ Update-WolPing })
        $script:PingTimer.Start()
        $script:PingFenster.Add_Closed({
            $script:PingTimer.Stop()
            foreach ($t in @($script:PingTabs)) { try { $t.Ping.Dispose() } catch { } }
            $script:PingTabs.Clear()
            $script:PingFenster = $null
        })
        $script:PingFenster.Show()
    }

    foreach ($z in $ziele) {
        if (-not $z.IP) { continue }
        $vorhanden = $script:PingTabs | Where-Object { $_.IP -eq $z.IP } | Select-Object -First 1
        if ($vorhanden) { $script:PingTabsCtl.SelectedItem = $vorhanden.Tab; continue }

        $name = if ($z.Hostname) { $z.Hostname.Split('.')[0] } else { $z.IP }
        $inhalt = New-WolFenster @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>
    <RowDefinition Height="*"/>
  </Grid.RowDefinitions>
  <TextBlock x:Name="Stat" Margin="4" Foreground="DimGray" Text="Gesendet: 0   Verloren: 0"/>
  <RichTextBox x:Name="Box" Grid.Row="1" IsReadOnly="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12">
    <RichTextBox.Resources>
      <Style TargetType="Paragraph"><Setter Property="Margin" Value="0"/></Style>
    </RichTextBox.Resources>
  </RichTextBox>
</Grid>
'@
        $kopf = [System.Windows.Controls.StackPanel]::new()
        $kopf.Orientation = 'Horizontal'
        $kopfText = [System.Windows.Controls.TextBlock]::new()
        $kopfText.Text = "$name ($($z.IP))"
        $zu = [System.Windows.Controls.Button]::new()
        $zu.Content = 'x'
        $zu.Tag = $z.IP
        $zu.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $zu.Padding = [System.Windows.Thickness]::new(4, 0, 4, 0)
        $zu.BorderThickness = [System.Windows.Thickness]::new(0)
        $zu.Background = [System.Windows.Media.Brushes]::Transparent
        $zu.ToolTip = 'Ping für dieses Gerät beenden'
        $zu.Add_Click({ Stop-WolPingTab -Ip $this.Tag })
        [void]$kopf.Children.Add($kopfText)
        [void]$kopf.Children.Add($zu)

        $tab = [System.Windows.Controls.TabItem]::new()
        $tab.Header = $kopf
        $tab.Content = $inhalt
        [void]$script:PingTabsCtl.Items.Add($tab)
        $script:PingTabsCtl.SelectedItem = $tab

        $script:PingTabs.Add([pscustomobject]@{
            IP = $z.IP; Tab = $tab; Box = $inhalt.FindName('Box'); Stat = $inhalt.FindName('Stat')
            Ping = [System.Net.NetworkInformation.Ping]::new(); Task = $null; Naechster = (Get-Date)
            Gesendet = 0; Verloren = 0
        })
        Write-WolLog "Dauerping gestartet: $($z.IP)"
    }
    $script:PingFenster.Activate() | Out-Null
}

# Warteschlange
## Aufträge (je Gerät ein Thread-Job) laufen höchstens so viele gleichzeitig, wie die Parallelität in den Optionen erlaubt; die übrigen warten
### Auftrag einreihen: Block und Argumente laufen im Thread-Job, Fertig wird im Poll-Timer mit dem Auftrag aufgerufen (Job, Zeile, Daten); Gruppe fasst zusammengehörige Aufträge zusammen
function Add-WolAuftrag {
    param($Zeile, [scriptblock]$Block, [object[]]$Argumente = @(), [scriptblock]$Fertig, [string]$Gruppe, $Daten = $null, [string]$Starttext = '', [string]$Wartetext = 'Wartet auf einen freien Platz...')
    $ausgelastet = ($script:AuftragJobs.Count + $script:Warteschlange.Count) -ge $script:Opt.Parallel
    $script:Warteschlange.Add([pscustomobject]@{
        Zeile = $Zeile; Block = $Block; Argumente = $Argumente; Fertig = $Fertig; Gruppe = $Gruppe; Daten = $Daten; Starttext = $Starttext; Job = $null
    })
    if ($Zeile) {
        if ($ausgelastet) { $Zeile.Status = $Wartetext }
        elseif ($Starttext) { $Zeile.Status = $Starttext }
    }
}

### Anzahl der laufenden und wartenden Aufträge einer Gruppe (optional nur für eine Zeile)
function Get-WolGruppeOffen {
    param([string]$Gruppe, $Zeile = $null)
    $n = 0
    foreach ($a in $script:Warteschlange) { if ($a.Gruppe -eq $Gruppe -and (-not $Zeile -or $a.Zeile -eq $Zeile)) { $n++ } }
    foreach ($a in $script:AuftragJobs) { if ($a.Gruppe -eq $Gruppe -and (-not $Zeile -or $a.Zeile -eq $Zeile)) { $n++ } }
    return $n
}

### Alle Aufträge einer Gruppe verwerfen (wartende entfernen, laufende Jobs beenden)
function Stop-WolGruppe {
    param([string]$Gruppe)
    foreach ($a in @($script:Warteschlange)) { if ($a.Gruppe -eq $Gruppe) { [void]$script:Warteschlange.Remove($a) } }
    foreach ($a in @($script:AuftragJobs)) {
        if ($a.Gruppe -ne $Gruppe) { continue }
        Remove-Job -Job $a.Job -Force -ErrorAction SilentlyContinue
        [void]$script:AuftragJobs.Remove($a)
    }
}

### Alle Aufträge verwerfen (Beenden, Daten löschen)
function Stop-WolAlleAuftraege {
    $script:Warteschlange.Clear()
    foreach ($a in @($script:AuftragJobs)) { Remove-Job -Job $a.Job -Force -ErrorAction SilentlyContinue }
    $script:AuftragJobs.Clear()
}

### Poll-Takt: fertige Aufträge auswerten, danach wartende starten
function Update-WolAuftraege {
    foreach ($a in @($script:AuftragJobs)) {
        if ($a.Job.State -notin 'Completed', 'Failed', 'Stopped') { continue }
        [void]$script:AuftragJobs.Remove($a)
        try { & $a.Fertig $a }
        catch { Write-WolLog "Fehler bei der Auswertung ($($a.Gruppe)): $($_.Exception.Message)" }
        Remove-Job -Job $a.Job -Force -ErrorAction SilentlyContinue
    }
    while ($script:Warteschlange.Count -gt 0 -and $script:AuftragJobs.Count -lt $script:Opt.Parallel) {
        $a = $script:Warteschlange[0]
        $script:Warteschlange.RemoveAt(0)
        try {
            $a.Job = Start-ThreadJob -ScriptBlock $a.Block -ArgumentList $a.Argumente
            $script:AuftragJobs.Add($a)
            if ($a.Zeile -and $a.Starttext) { $a.Zeile.Status = $a.Starttext }
        }
        catch {
            if ($a.Zeile) { $a.Zeile.Status = 'Start fehlgeschlagen: ' + (Get-WolFehlerKurz -Text $_.Exception.Message) }
            Write-WolLog "Auftrag konnte nicht gestartet werden ($($a.Gruppe)): $($_.Exception.Message)"
        }
    }
}

# Aufgaben auf dem Zielgerät
## Funktionen für die Jobs: Der Job lädt sie mit ". ([scriptblock]::Create($TaskCode))"; $Ic ist die Parameterliste für Invoke-Command (ComputerName, Credential, ErrorAction)
### Aufgaben als SYSTEM ohne Trigger anlegen und starten, Status abfragen, auf das Ende warten, Reste entfernen; geplanter Neustart (Aufgabe NetCockpitNeustart, Beschreibung = Zielzeit yyyy-MM-dd HH:mm, Hinweis 5 Minuten vorher); Windows-Version, letzter Neustart, Neustart ausstehend (gemeinsam für alle Update-Module)
$script:ZielTaskCode = @'
function Start-WolZielTask {
    param($Ic, [string]$Name, [string]$Skript, [string]$Programm = 'powershell.exe')
    Invoke-Command @Ic -ArgumentList $Name, $Skript, $Programm -ScriptBlock {
        param($n, $s, $prog)
        $pfad = "C:\Windows\Temp\$n.ps1"
        Set-Content -Path $pfad -Value $s -Encoding UTF8
        $a = New-ScheduledTaskAction -Execute $prog -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$pfad`""
        $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $einst = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 4) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $n -Action $a -Principal $p -Settings $einst -Force | Out-Null
        Start-ScheduledTask -TaskName $n
    }
}

function Get-WolZielTaskStatus {
    param($Ic, [string]$Name)
    Invoke-Command @Ic -ArgumentList $Name -ScriptBlock {
        param($n)
        $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
        if (-not $t) { return [pscustomobject]@{ Vorhanden = $false; State = ''; Result = $null; Zeilen = @() } }
        $i = Get-ScheduledTaskInfo -TaskName $n -ErrorAction Stop
        $f = "C:\Windows\Temp\$n.log"
        [pscustomobject]@{
            Vorhanden = $true
            State     = [string]$t.State
            Result    = $i.LastTaskResult
            Zeilen    = @(if (Test-Path $f) { Get-Content -Path $f })
        }
    }
}

function Remove-WolZielTask {
    param($Ic, [string]$Name)
    Invoke-Command @Ic -ArgumentList $Name -ScriptBlock {
        param($n)
        Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\Temp\$n.ps1", "C:\Windows\Temp\$n.log", "C:\Windows\Temp\$n.json" -Force -ErrorAction SilentlyContinue
    }
}

function Get-WolZielAnderesTool {
    param($Ic, [string]$Eigene)
    Invoke-Command @Ic -ArgumentList $Eigene -ScriptBlock {
        param($e)
        @(Get-ScheduledTask -TaskName 'NetCockpit*' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -notlike $e -and $_.TaskName -ne 'NetCockpitNeustart' -and [string]$_.State -in 'Running', 'Queued' } | ForEach-Object { [string]$_.TaskName })
    }
}

function Set-WolZielNeustart {
    param($Ic, [string]$ZeitText)
    Invoke-Command @Ic -ArgumentList $ZeitText -ScriptBlock {
        param($zeitText)
        $jetzt = Get-Date
        $ziel = [datetime]::ParseExact($zeitText, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
        if ($ziel -le $jetzt.AddMinutes(1)) {
            throw ('Der gewählte Zeitpunkt liegt in der Vergangenheit. Aktuelle Uhrzeit des Rechners: ' + $jetzt.ToString('dd.MM.yyyy HH:mm'))
        }
        $start = $ziel.AddMinutes(-5)
        if ($start -lt $jetzt.AddMinutes(1)) { $start = $jetzt.AddMinutes(1) }
        $sek = [int][math]::Max(30, ($ziel - $start).TotalSeconds)
        $text = 'Der Rechner wird um ' + $ziel.ToString('HH:mm') + ' Uhr neu gestartet. Bitte Arbeit speichern. Abbruch durch einen Administrator mit: shutdown /a'
        $skript = @(
            ('shutdown.exe /r /t ' + $sek + ' /c "' + $text + '"'),
            'Start-Sleep -Seconds 5',
            "Unregister-ScheduledTask -TaskName 'NetCockpitNeustart' -Confirm:`$false -ErrorAction SilentlyContinue",
            "Remove-Item -Path 'C:\Windows\Temp\NetCockpitNeustart.ps1' -Force -ErrorAction SilentlyContinue"
        ) -join "`r`n"
        Unregister-ScheduledTask -TaskName 'NetCockpitNeustart' -Confirm:$false -ErrorAction SilentlyContinue
        $pfad = 'C:\Windows\Temp\NetCockpitNeustart.ps1'
        Set-Content -Path $pfad -Value $skript -Encoding UTF8
        $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $pfad + '"')
        $tr = New-ScheduledTaskTrigger -Once -At $start
        $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $einst = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        Register-ScheduledTask -TaskName 'NetCockpitNeustart' -Action $a -Trigger $tr -Principal $p -Settings $einst -Description $ziel.ToString('yyyy-MM-dd HH:mm') -Force | Out-Null
        $ziel.ToString('yyyy-MM-dd HH:mm')
    }
}

function Remove-WolZielNeustart {
    param($Ic)
    Invoke-Command @Ic -ScriptBlock {
        $geloescht = $false
        if (Get-ScheduledTask -TaskName 'NetCockpitNeustart' -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName 'NetCockpitNeustart' -Confirm:$false
            $geloescht = $true
        }
        Remove-Item -Path 'C:\Windows\Temp\NetCockpitNeustart.ps1' -Force -ErrorAction SilentlyContinue
        $null = shutdown.exe /a 2>&1
        [pscustomobject]@{ TaskGeloescht = $geloescht; AbbruchCode = $LASTEXITCODE }
    }
}

function Get-WolZielNeustart {
    param($Ic)
    $zielText = Invoke-Command @Ic -ScriptBlock {
        $t = Get-ScheduledTask -TaskName 'NetCockpitNeustart' -ErrorAction SilentlyContinue
        if (-not $t) { return $null }
        $ziel = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$t.Description, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ziel)) { return $null }
        if ($ziel -lt (Get-Date).AddMinutes(-10)) {
            Unregister-ScheduledTask -TaskName 'NetCockpitNeustart' -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path 'C:\Windows\Temp\NetCockpitNeustart.ps1' -Force -ErrorAction SilentlyContinue
            return $null
        }
        return $ziel.ToString('yyyy-MM-dd HH:mm')
    }
    return $zielText
}

function Get-WolZielNeustartPruefung {
    param($Ic)
    Invoke-Command @Ic -ScriptBlock {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        [pscustomobject]@{
            Boot = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm')
            Task = [bool](Get-ScheduledTask -TaskName 'NetCockpitNeustart' -ErrorAction SilentlyContinue)
        }
    }
}

function Get-WolZielWindows {
    param($Ic)
    $info = Invoke-Command @Ic -ScriptBlock {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $feature = if ($cv.DisplayVersion) { [string]$cv.DisplayVersion } else { [string]$cv.ReleaseId }
        [pscustomobject]@{ Name = [string]$os.Caption; Feature = $feature; Build = [string]$os.BuildNumber; Revision = [string]$cv.UBR }
    }
    $teile = @(($info.Name -replace '^Microsoft\s+', '').Trim())
    if ($info.Feature) { $teile += $info.Feature }
    return (($teile -join ' ') + " (Build $($info.Build).$($info.Revision))")
}

function Get-WolZielLetzterNeustart {
    param($Ic)
    $text = Invoke-Command @Ic -ScriptBlock {
        (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
    }
    $zeit = [datetime]::ParseExact([string]$text, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
    return $zeit.ToString('dd.MM.yyyy HH:mm')
}

function Test-WolZielNeustartAusstehend {
    param($Ic)
    $ausstehend = Invoke-Command @Ic -ScriptBlock {
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    }
    return [bool]$ausstehend
}

### Auf das Ende einer Aufgabe warten; Zeile wird mit jeder neuen Logzeile der Aufgabe aufgerufen, Meldung mit Hinweisen zur Verbindung; Ergebnis: Fertig, Weg (Aufgabe nicht mehr vorhanden), Verloren (12 Abfragen in Folge fehlgeschlagen) oder Zeit (MaxMinuten überschritten)
function Wait-WolZielTask {
    param($Ic, [string]$Name, [int]$PauseSek = 5, [int]$MaxMinuten = 0, [scriptblock]$Zeile = $null, [scriptblock]$Meldung = $null)
    $gelesen = 0
    $fehler = 0
    $start = Get-Date
    while ($true) {
        try {
            $st = Get-WolZielTaskStatus -Ic $Ic -Name $Name
            $fehler = 0
        }
        catch {
            $fehler++
            if ($Meldung) { & $Meldung "Statusabfrage fehlgeschlagen ($fehler/12): $($_.Exception.Message)" }
            if ($fehler -ge 12) { return [pscustomobject]@{ Ergebnis = 'Verloren'; Result = $null } }
            Start-Sleep -Seconds $PauseSek
            continue
        }
        if ($Zeile) {
            $zeilen = @($st.Zeilen)
            for ($i = $gelesen; $i -lt $zeilen.Count; $i++) { & $Zeile ([string]$zeilen[$i]) }
            $gelesen = $zeilen.Count
        }
        if (-not $st.Vorhanden) { return [pscustomobject]@{ Ergebnis = 'Weg'; Result = $null } }
        if ($st.State -notin 'Running', 'Queued') { return [pscustomobject]@{ Ergebnis = 'Fertig'; Result = $st.Result } }
        if ($MaxMinuten -gt 0 -and ((Get-Date) - $start).TotalMinutes -gt $MaxMinuten) { return [pscustomobject]@{ Ergebnis = 'Zeit'; Result = $null } }
        Start-Sleep -Seconds $PauseSek
    }
}
'@

## Geplante Neustarts nach Ablauf prüfen: sobald das Gerät nach dem Termin wieder grün ist, wird abgefragt, ob der Neustart stattgefunden hat
function Test-WolGeplanteNeustarts {
    foreach ($z in $script:Zeilen) {
        $text = $z['GeplantBis']
        if (-not $text -or $z.Ampel -ne 'Gruen') { continue }
        $ziel = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($text, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ziel)) { $z['GeplantBis'] = ''; continue }
        if ((Get-Date) -lt $ziel.AddMinutes(3)) { continue }
        if ((Get-WolGruppeOffen -Gruppe 'Pruefen' -Zeile $z) -gt 0) { continue }
        if ($z.Konto -and -not $z.Kennwort) { continue }
        Add-WolAuftrag -Zeile $z -Block $script:AktionBlock -Argumente @((Get-WolZielName -Zeile $z), 'Pruefen', 0, (Get-WolAnmeldung -Zeile $z), $script:ZielTaskCode) -Fertig $script:AktionFertig -Gruppe 'Pruefen' -Daten @{ Art = 'Pruefen'; Ziel = $text } -Starttext 'Prüfe geplanten Neustart...'
    }
}

# Neustart planen
## Fenster für Datum und Uhrzeit des geplanten Neustarts; Rückgabe: Zeitpunkt oder $null bei Abbruch
function Show-WolNeustartZeit {
    param([string]$Namen)
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Neustart planen" Width="500" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="LblNamen" TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,12"/>
    <Grid Margin="0,0,0,12">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="12"/>
        <ColumnDefinition Width="130"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <TextBlock Text="Datum" Margin="0,0,0,4"/>
        <DatePicker x:Name="DatTag"/>
      </StackPanel>
      <StackPanel Grid.Column="2">
        <TextBlock Text="Uhrzeit (HH:mm)" Margin="0,0,0,4"/>
        <TextBox x:Name="TxtZeit" Text="22:00" VerticalContentAlignment="Center" Padding="2,3"/>
      </StackPanel>
    </Grid>
    <Border BorderBrush="#CCCCCC" BorderThickness="1" Padding="10" Margin="0,0,0,6">
      <TextBlock x:Name="LblVorschau" TextWrapping="Wrap"/>
    </Border>
    <TextBlock Text="Datum und Uhrzeit gelten nach der Uhr des Zielgeräts. Die Aufgabe läuft auf dem Gerät und braucht das NET-COCKPIT danach nicht mehr." TextWrapping="Wrap" Foreground="DimGray" Margin="0,0,0,14"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnOk" Content="Neustart planen" Padding="14,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BtnAbbruch" Content="Abbrechen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $f.Owner = $script:Fenster
    $datum = $f.FindName('DatTag')
    $zeit = $f.FindName('TxtZeit')
    $vorschau = $f.FindName('LblVorschau')
    $f.FindName('LblNamen').Text = "Geräte: $Namen"
    $datum.DisplayDateStart = (Get-Date).Date
    $datum.SelectedDate = (Get-Date).Date
    $de = [cultureinfo]::GetCultureInfo('de-DE')
    $erg = @{ Ziel = $null }

    ### Datum und Uhrzeit zu einem Zeitpunkt zusammensetzen ($null, wenn ungültig)
    $berechne = {
        $t = [datetime]::MinValue
        if ($datum.SelectedDate -and [datetime]::TryParseExact($zeit.Text.Trim(), 'H:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$t)) {
            return $datum.SelectedDate.Date.Add($t.TimeOfDay)
        }
        return $null
    }.GetNewClosure()

    ### Vorschau live aktualisieren
    $aktualisieren = {
        $ziel = & $berechne
        if ($ziel) {
            $vorschau.Foreground = [System.Windows.Media.Brushes]::Black
            $vorschau.Text = "Neustart am $($ziel.ToString('dddd, dd.MM.yyyy', $de)) um $($ziel.ToString('HH:mm')) Uhr.`nBenutzer erhalten ab $($ziel.AddMinutes(-5).ToString('HH:mm')) Uhr einen Hinweis."
        }
        else {
            $vorschau.Foreground = [System.Windows.Media.Brushes]::DarkRed
            $vorschau.Text = 'Bitte ein Datum wählen und die Uhrzeit im Format HH:mm eingeben, zum Beispiel 22:00.'
        }
    }.GetNewClosure()

    $zeit.Add_TextChanged({ & $aktualisieren }.GetNewClosure())
    $datum.Add_SelectedDateChanged({ & $aktualisieren }.GetNewClosure())
    & $aktualisieren

    $f.FindName('BtnOk').Add_Click({
        $ziel = & $berechne
        if (-not $ziel) {
            [void][System.Windows.MessageBox]::Show($f, 'Bitte ein Datum wählen und die Uhrzeit im Format HH:mm eingeben, zum Beispiel 22:00.', 'Neustart planen', 'OK', 'Warning')
            return
        }
        if ($ziel -le (Get-Date).AddMinutes(1)) {
            [void][System.Windows.MessageBox]::Show($f, 'Der gewählte Zeitpunkt liegt in der Vergangenheit.', 'Neustart planen', 'OK', 'Warning')
            return
        }
        $erg.Ziel = $ziel
        $f.DialogResult = $true
    }.GetNewClosure())

    if ($f.ShowDialog() -ne $true) { return $null }
    return $erg.Ziel
}

# OU-Auswahl
## OUs aus dem Active Directory lesen (LDAP, kein RSAT nötig)
function Get-WolOuListe {
    $rootDse = [System.DirectoryServices.DirectoryEntry]::new('LDAP://RootDSE')
    $basis = [string]$rootDse.Properties['defaultNamingContext'].Value
    $rootDse.Dispose()
    if (-not $basis) { throw 'Die Domäne wurde nicht gefunden.' }

    $start = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$basis")
    $suche = [System.DirectoryServices.DirectorySearcher]::new($start)
    $suche.Filter = '(objectCategory=organizationalUnit)'
    $suche.SearchScope = 'Subtree'
    $suche.PageSize = 1000
    [void]$suche.PropertiesToLoad.Add('name')
    [void]$suche.PropertiesToLoad.Add('distinguishedName')

    $liste = [System.Collections.Generic.List[object]]::new()
    try {
        $treffer = $suche.FindAll()
        foreach ($t in $treffer) {
            $liste.Add([pscustomobject]@{ Name = [string]$t.Properties['name'][0]; DN = [string]$t.Properties['distinguishedname'][0] })
        }
        $treffer.Dispose()
    }
    finally {
        $suche.Dispose()
        $start.Dispose()
    }
    return [pscustomobject]@{ Basis = $basis; Liste = $liste.ToArray() }
}

## Computer einer OU lesen (aktive Konten, DNS-Name wenn vorhanden)
function Get-WolOuComputer {
    param([string]$DN, [bool]$Unter)
    $start = [System.DirectoryServices.DirectoryEntry]::new('LDAP://' + ($DN -replace '/', '\/'))
    $suche = [System.DirectoryServices.DirectorySearcher]::new($start)
    $suche.Filter = '(&(objectCategory=computer)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))'
    $suche.SearchScope = $(if ($Unter) { 'Subtree' } else { 'OneLevel' })
    $suche.PageSize = 1000
    [void]$suche.PropertiesToLoad.Add('dNSHostName')
    [void]$suche.PropertiesToLoad.Add('name')

    $namen = [System.Collections.Generic.List[string]]::new()
    try {
        $treffer = $suche.FindAll()
        foreach ($t in $treffer) {
            $dns = $(if ($t.Properties['dnshostname'].Count -gt 0) { [string]$t.Properties['dnshostname'][0] } else { '' })
            $kurz = $(if ($t.Properties['name'].Count -gt 0) { [string]$t.Properties['name'][0] } else { '' })
            $eintrag = $(if ($dns) { $dns } else { $kurz })
            if ($eintrag) { $namen.Add($eintrag) }
        }
        $treffer.Dispose()
    }
    finally {
        $suche.Dispose()
        $start.Dispose()
    }
    return @($namen.ToArray() | Sort-Object -Unique)
}

## Dialog: OU im Baum wählen; Rückgabe: DN, Name und "Unter-OUs einschließen" oder $null bei Abbruch
function Show-WolOuDialog {
    param($OuListe, [string]$Basis)
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OU wählen" Width="520" Height="580" WindowStartupLocation="CenterOwner">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="OU auswählen, deren Computer eingelesen werden sollen:" Margin="0,0,0,8"/>
    <TreeView x:Name="Baum" Grid.Row="1"/>
    <CheckBox x:Name="ChkUnter" Grid.Row="2" Content="Unter-OUs einschließen" Margin="0,10,0,0"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnOk" Content="Computer einlesen" Padding="14,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button Content="Abbrechen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $baum = $f.FindName('Baum')
    $unter = $f.FindName('ChkUnter')

    ### Baum aufbauen: Wurzel = Domäne, darunter die OUs
    $wurzel = [System.Windows.Controls.TreeViewItem]::new()
    $wurzel.Header = ($Basis -replace 'DC=', '' -replace ',', '.')
    $wurzel.Tag = $Basis
    $wurzel.IsExpanded = $true
    [void]$baum.Items.Add($wurzel)

    $knoten = @{}
    $sortiert = @($OuListe | Sort-Object Name)
    foreach ($ou in $sortiert) {
        $k = [System.Windows.Controls.TreeViewItem]::new()
        $k.Header = $ou.Name
        $k.Tag = $ou.DN
        $knoten[$ou.DN] = $k
    }
    foreach ($ou in $sortiert) {
        $elternDN = $ou.DN -replace '^(?:\\.|[^,\\])+,', ''
        $eltern = $(if ($knoten.ContainsKey($elternDN)) { $knoten[$elternDN] } else { $wurzel })
        [void]$eltern.Items.Add($knoten[$ou.DN])
    }

    $erg = @{ DN = $null; Unter = $false; Name = $null }
    $f.FindName('BtnOk').Add_Click({
        $gewaehlt = $baum.SelectedItem
        if (-not $gewaehlt) {
            [void][System.Windows.MessageBox]::Show($f, 'Bitte eine OU auswählen.', 'OU wählen', 'OK', 'Warning')
            return
        }
        $erg.DN = [string]$gewaehlt.Tag
        $erg.Name = [string]$gewaehlt.Header
        $erg.Unter = [bool]$unter.IsChecked
        $f.DialogResult = $true
    }.GetNewClosure())

    if ($f.ShowDialog() -ne $true) { return $null }
    return [pscustomobject]$erg
}

## Namensauflösung der OU-Computer: läuft als Thread-Job und liefert je Name die IPv4-Adresse (leer, wenn keine gefunden wurde)
$script:DnsBlock = {
    param([string[]]$Namen)
    @($Namen | ForEach-Object -ThrottleLimit 32 -Parallel {
        $ip = ''
        try {
            $e = [System.Net.Dns]::GetHostEntryAsync($_)
            if ($e.Wait(3000)) {
                $adr = $e.Result.AddressList | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
                if ($adr) { $ip = $adr.IPAddressToString }
            }
        } catch { }
        [pscustomobject]@{ Name = $_; IP = $ip }
    })
}

## Datei > OU wählen: Computer der OU der Tabelle hinzufügen (vorhandene Hostnamen nicht doppelt), IP-Adressen per DNS auflösen
function Import-WolOu {
    try { $ous = Get-WolOuListe }
    catch { Show-WolMeldung "Das Active Directory konnte nicht gelesen werden: $($_.Exception.Message)" 'Warning'; return }
    $wahl = Show-WolOuDialog -OuListe $ous.Liste -Basis $ous.Basis
    if (-not $wahl) { return }
    try { $namen = @(Get-WolOuComputer -DN $wahl.DN -Unter $wahl.Unter) }
    catch { Show-WolMeldung "Die Computer der OU konnten nicht gelesen werden: $($_.Exception.Message)" 'Warning'; return }
    if ($namen.Count -eq 0) { Show-WolMeldung "In der OU '$($wahl.Name)' wurden keine aktiven Computer gefunden."; return }

    $bekannt = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($z in $script:Zeilen) { if ($z.Hostname) { [void]$bekannt.Add(([string]$z.Hostname).Split('.')[0].ToLower()) } }
    $neu = [System.Collections.Generic.List[object]]::new()
    foreach ($n in $namen) {
        if (-not $bekannt.Add($n.Split('.')[0].ToLower())) { continue }
        $z = New-Object NetCockpitZeile
        $z.Hostname = $n
        $z.Status = 'Namensauflösung...'
        $script:Zeilen.Add($z)
        $neu.Add($z)
    }
    Write-WolLog "OU '$($wahl.Name)': $($namen.Count) Computer gefunden, $($neu.Count) neu in der Liste"
    if ($neu.Count -eq 0) { return }
    $script:Geaendert = $true
    Update-WolAnsicht
    Add-WolAuftrag -Zeile $null -Block $script:DnsBlock -Argumente @(, [string[]]@($neu | ForEach-Object { $_.Hostname })) -Fertig $script:DnsFertig -Gruppe 'OU' -Daten @{ Zeilen = $neu }
}

## Auswertung der Namensauflösung (läuft im Poll-Timer)
$script:DnsFertig = {
    param($a)
    try {
        $karte = @{}
        foreach ($e in @(Receive-Job -Job $a.Job -ErrorAction Stop)) { $karte[[string]$e.Name] = [string]$e.IP }
        foreach ($z in $a.Daten.Zeilen) {
            $ip = $karte[[string]$z.Hostname]
            if ($ip) { $z.IP = $ip; $z.Status = 'Noch nicht geprüft' }
            else { $z.Status = 'Keine IP-Adresse gefunden (DNS)' }
        }
        Write-WolLog "OU: Namensauflösung fertig ($(@($karte.Values | Where-Object { $_ }).Count) von $($karte.Count) aufgelöst)"
    }
    catch { Write-WolLog "Fehler bei der Namensauflösung: $($_.Exception.Message)" }
    $script:Geaendert = $true
    Update-WolAnsicht
    Start-WolStatusPruefung
    Save-WolAuto
}

# Module
## Block (Thread-Job): Dateien über den Proxy holen und jede gegen ihre .sig-Datei prüfen; gibt nur bei gültigen Signaturen Bytes zurück
$script:NachladeBlock = {
    param([string]$Base, [string]$Schluessel, [string]$PfadText, [string]$RepoOrdner, $Fortschritt)
    $ProgressPreference = 'SilentlyContinue'

    function Get-NcBytes {
        param([string]$P)
        $adresse = '{0}?path={1}' -f $Base, [uri]::EscapeDataString($P)
        $antwort = Invoke-WebRequest -Uri $adresse
        return , [byte[]]$antwort.RawContentStream.ToArray()
    }

    ### Datei holen und gegen ihre .sig-Datei prüfen (ohne gültige Signatur wird abgebrochen)
    function Get-NcGeprueft {
        param([string]$P)
        $Fortschritt.Text = [System.IO.Path]::GetFileName($P)
        $inhalt = Get-NcBytes -P $P
        try {
            $sigText = [System.Text.Encoding]::UTF8.GetString((Get-NcBytes -P "$P.sig")).Trim()
            $sigBytes = [Convert]::FromBase64String($sigText)
        }
        catch {
            throw "Zu '$P' gibt es keine gültige Signaturdatei. Die Datei wird nicht geladen."
        }
        $pruefer = [System.Security.Cryptography.ECDsa]::Create()
        try {
            $gelesen = 0
            $pruefer.ImportSubjectPublicKeyInfo([Convert]::FromBase64String($Schluessel), [ref]$gelesen)
            $gueltig = $pruefer.VerifyData($inhalt, $sigBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        }
        finally {
            $pruefer.Dispose()
        }
        if (-not $gueltig) {
            throw "Die Signatur von '$P' ist ungültig. Die Datei wird nicht geladen."
        }
        $Fortschritt.Aktuell = $Fortschritt.Aktuell + 1
        return , $inhalt
    }

    $alle = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($PfadText.Split('|'))) { if ($p) { $alle.Add($p) } }
    if ($RepoOrdner) {
        $liste = Invoke-RestMethod -Uri ('{0}?path={1}' -f $Base, [uri]::EscapeDataString($RepoOrdner))
        foreach ($e in @($liste | Where-Object { $_.type -eq 'file' -and $_.name -like '*.ps1' })) { $alle.Add([string]$e.path) }
    }
    $Fortschritt.Gesamt = $alle.Count
    $ergebnis = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $alle) {
        $ergebnis.Add([pscustomobject]@{ Name = [System.IO.Path]::GetFileName($p); Bytes = (Get-NcGeprueft -P $p) })
    }
    [pscustomobject]@{ Dateien = @($ergebnis.ToArray()) }
}

## Dateien vom Server holen (Ladefenster mit Fortschrittsbalken), prüfen und in den Zielordner schreiben: einzelne Repo-Pfade und/oder alle .ps1-Dateien eines Repo-Ordners; $true, wenn mindestens eine Datei geschrieben wurde
function Install-WolNachladen {
    param([string]$Titel, [string[]]$Pfade = @(), [string]$RepoOrdner = '', [string]$ZielOrdner)
    $script:NlFortschritt = [hashtable]::Synchronized(@{ Aktuell = 0; Gesamt = 0; Text = 'Verbinde mit dem Server ...' })
    $script:NlErgebnis = $null
    $script:NlFehler = ''
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NET-COCKPIT" Width="440" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True"
        Background="White" FontFamily="Segoe UI">
  <StackPanel Margin="24">
    <TextBlock x:Name="TxtHinweis" Text="" FontSize="16" FontWeight="SemiBold" Foreground="#0078D4" TextWrapping="Wrap"/>
    <ProgressBar x:Name="Balken" Height="12" Margin="0,14,0,0" IsIndeterminate="True" Minimum="0" Maximum="1"/>
    <TextBlock x:Name="TxtDatei" Text="" FontSize="12" Foreground="DimGray" Margin="0,8,0,0" TextWrapping="Wrap"/>
  </StackPanel>
</Window>
'@
    $script:NlFenster = $f
    $script:NlC = @{ Balken = $f.FindName('Balken'); Datei = $f.FindName('TxtDatei') }
    $f.FindName('TxtHinweis').Text = $Titel
    if ($script:Fenster -and $script:Fenster.IsVisible) {
        $f.Owner = $script:Fenster
        $f.WindowStartupLocation = 'CenterOwner'
    }
    $script:NlJob = Start-ThreadJob -ScriptBlock $script:NachladeBlock -ArgumentList $script:ServerBasis, $script:ServerSchluessel, ($Pfade -join '|'), $RepoOrdner, $script:NlFortschritt
    $script:NlTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:NlTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $script:NlTimer.Add_Tick({
        $gesamt = [int]$script:NlFortschritt.Gesamt
        if ($gesamt -gt 0) {
            $aktuell = [int]$script:NlFortschritt.Aktuell
            $script:NlC.Balken.IsIndeterminate = $false
            $script:NlC.Balken.Maximum = $gesamt
            $script:NlC.Balken.Value = $aktuell
            $script:NlC.Datei.Text = ('Datei {0} von {1}: {2}' -f ([Math]::Min($aktuell + 1, $gesamt)), $gesamt, $script:NlFortschritt.Text)
        }
        else {
            $script:NlC.Datei.Text = [string]$script:NlFortschritt.Text
        }
        if ($script:NlJob.State -notin 'Completed', 'Failed', 'Stopped') { return }
        $script:NlTimer.Stop()
        try { $script:NlErgebnis = @(Receive-Job -Job $script:NlJob -ErrorAction Stop) | Select-Object -Last 1 }
        catch { $script:NlFehler = $_.Exception.Message }
        $script:NlFenster.Close()
    })
    $script:NlTimer.Start()
    [void]$f.ShowDialog()
    $script:NlTimer.Stop()
    if ($script:NlJob) {
        Stop-Job -Job $script:NlJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:NlJob -Force -ErrorAction SilentlyContinue
        $script:NlJob = $null
    }
    if ($script:NlFehler) {
        Write-WolLog "Nachladen fehlgeschlagen ($Titel): $($script:NlFehler)"
        Show-WolMeldung "Das Laden vom Server hat nicht geklappt:`r`n$($script:NlFehler)" 'Warning'
        return $false
    }
    if (-not $script:NlErgebnis -or @($script:NlErgebnis.Dateien).Count -eq 0) { return $false }
    try {
        if (-not (Test-Path -LiteralPath $ZielOrdner)) { [void](New-Item -Path $ZielOrdner -ItemType Directory -Force) }
        foreach ($d in @($script:NlErgebnis.Dateien)) {
            [System.IO.File]::WriteAllBytes((Join-Path $ZielOrdner $d.Name), [byte[]]$d.Bytes)
        }
    }
    catch {
        Write-WolLog "Nachladen: Datei konnte nicht gespeichert werden: $($_.Exception.Message)"
        Show-WolMeldung "Die geladenen Dateien konnten nicht gespeichert werden:`r`n$($_.Exception.Message)" 'Warning'
        return $false
    }
    Write-WolLog "Vom Server geladen: $(@($script:NlErgebnis.Dateien).Count) Datei(en) für '$Titel'"
    return $true
}

## Hilfedatei laden (einmal): liegt sie nicht im Ordner des NET-COCKPIT und kennt das Cockpit den Server (Start über start.ps1), holt es sie vorher mit Ladefenster
function Import-WolHilfe {
    if ($script:HilfeGeladen -or -not $script:ModulOrdner) { return }
    $pfad = Join-Path $script:ModulOrdner $script:HilfeDatei
    if (-not (Test-Path -LiteralPath $pfad) -and $script:ServerBasis -and $script:ServerSchluessel) {
        [void](Install-WolNachladen -Titel 'Hilfe wird geladen' -Pfade @($script:HilfeDatei) -ZielOrdner $script:ModulOrdner)
    }
    if (-not (Test-Path -LiteralPath $pfad)) { Write-WolLog "Hilfe: Datei $($script:HilfeDatei) nicht gefunden"; return }
    try {
        . $pfad
        $script:HilfeGeladen = $true
        Write-WolLog "Hilfe geladen: $($script:HilfeDatei)"
    }
    catch { Write-WolLog "Hilfe konnte nicht geladen werden: $($_.Exception.Message)" }
}

## Modul beim ersten Aufruf nachladen (Dot-Sourcing); das Modul legt seine Funktionen mit "function script:Name" an, trägt eigene Spalten über New-WolSpalte ein und stellt Show-WolModul<Schlüssel> bereit; fehlt die Datei und kennt das Cockpit den Server (Start über start.ps1), holt es sie vorher mit Ladefenster
function Open-WolModul {
    param([string]$Key)
    $m = $script:Module[$Key]
    if (-not $m.Geladen) {
        $pfad = $(if ($script:ModulOrdner) { Join-Path $script:ModulOrdner $m.Datei } else { '' })
        if ($pfad -and -not (Test-Path -LiteralPath $pfad) -and $script:ServerBasis -and $script:ServerSchluessel) {
            if (-not (Install-WolNachladen -Titel "Modul $($m.Name) wird gestartet" -Pfade @($m.Datei) -ZielOrdner $script:ModulOrdner)) { return }
        }
        if (-not $pfad -or -not (Test-Path -LiteralPath $pfad)) {
            $serverHinweis = $(if ($script:ServerBasis -and $script:ServerSchluessel) { '' } else { "`r`n`r`nDem NET-COCKPIT ist kein Server bekannt (Start nicht über start.ps1), deshalb kann es das Modul nicht nachladen." })
            Show-WolMeldung "Das Modul $($m.Name) wurde nicht gefunden.`r`nErwartet wird die Datei $($m.Datei) im selben Ordner wie das NET-COCKPIT.$serverHinweis" 'Warning'
            return
        }
        try {
            . $pfad
            $m.Geladen = $true
            Write-WolLog "Modul geladen: $($m.Datei)"
        }
        catch {
            Show-WolMeldung "Das Modul $($m.Name) konnte nicht geladen werden: $($_.Exception.Message)" 'Warning'
            return
        }
    }
    Restore-WolWerteAlle
    & ('Show-WolModul' + $Key)
}

# Daten löschen
## Hintergrundarbeit anhalten: Timer stoppen, Jobs beenden (Beenden und Daten löschen)
function Stop-WolHintergrund {
    $script:PollTimer.Stop()
    $script:AutoTimer.Stop()
    $script:StatusTimer.Stop()
    $script:ScanAktiv = $false
    if ($script:StatusJob) { Remove-Job -Job $script:StatusJob -Force -ErrorAction SilentlyContinue; $script:StatusJob = $null }
    if ($script:ScanJob) { Remove-Job -Job $script:ScanJob -Force -ErrorAction SilentlyContinue; $script:ScanJob = $null }
    foreach ($p in @($script:PortJobs)) { $p.Status.Abbruch = $true; Remove-Job -Job $p.Job -Force -ErrorAction SilentlyContinue }
    $script:PortJobs.Clear()
    $script:PortWarteschlange.Clear()
    Stop-WolAlleAuftraege
}

## Optionen > NET-COCKPIT Daten löschen: einmal nachfragen, dann Jobs stoppen, Datenordner samt Inhalt löschen und das Cockpit beenden
function Remove-WolDaten {
    $frage = "Bist Du sicher, dass Du ALLE Daten löschen willst?`r`n`r`nOrdner: $($script:DatenOrdner)`r`n`r`nDarin liegen: die Logdatei, die Herstellerliste, die Einstellungen (Optionen und Spalten) und die ausgelesenen Geräteinformationen (KuDo)."
    if ($script:ListenPfad -and $script:ListenPfad.StartsWith($script:DatenOrdner, [System.StringComparison]::OrdinalIgnoreCase)) {
        $frage += "`r`n`r`nAchtung: Die geöffnete Geräteliste liegt in diesem Ordner und wird mitgelöscht."
    }
    $frage += "`r`n`r`nGerätelisten an anderen Orten und Exporte bleiben erhalten. Das NET-COCKPIT wird danach beendet."
    if ([System.Windows.MessageBox]::Show($frage, 'NET-COCKPIT Daten löschen', 'YesNo', 'Warning', 'No') -ne 'Yes') { return }

    $script:DatenLoeschen = $true
    Stop-WolHintergrund
    if ($script:PingFenster) { $script:PingFenster.Close() }
    Remove-Item -LiteralPath $script:DatenOrdner -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:DatenOrdner) {
        $rest = @(Get-ChildItem -LiteralPath $script:DatenOrdner -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $script:DatenLoeschen = $false
        $script:PollTimer.Start()
        Set-WolStatusTimer
        Update-WolScanAnzeige
        $anzeige = @($rest | Select-Object -First 15) -join "`r`n"
        if ($rest.Count -gt 15) { $anzeige += "`r`n... und $($rest.Count - 15) weitere" }
        Write-WolLog "Daten löschen: $($rest.Count) Eintrag/Einträge konnten nicht gelöscht werden"
        Show-WolMeldung "Nicht alles konnte gelöscht werden (zum Beispiel weil eine Datei gesperrt ist). Das NET-COCKPIT bleibt geöffnet.`r`n`r`nNoch vorhanden:`r`n$anzeige" 'Warning'
        return
    }
    $script:OhneSpeichern = $true
    $script:Fenster.Close()
}

# Herstellername
## Herstellername zu einer MAC-Adresse aus der lokalen Herstellerliste (die Liste wird einmal gelesen und bis zum Ende der Abfrage gemerkt)
function Get-WolHerstellerName {
    param([string]$Mac)
    $hex = ($Mac -replace '[^0-9A-Fa-f]', '').ToUpper()
    if ($hex.Length -lt 6 -or -not (Test-Path -LiteralPath $script:OuiPfad)) { return '' }
    if (-not $script:OuiKarte) {
        $script:OuiKarte = @{}
        try { Import-Csv -Path $script:OuiPfad | ForEach-Object { $script:OuiKarte[$_.Assignment] = $_.'Organization Name' } } catch { }
    }
    return [string]$script:OuiKarte[$hex.Substring(0, 6)]
}

# Darstellung im Detailfenster
## Zeile hervorheben, solange die Maus darüber ist (reiner WPF-Stil, ohne Skriptcode im Betrieb)
function Set-WolZeilenHover {
    param($Gitter)
    if (-not $script:ZeilenStil) {
        $stil = [System.Windows.Style]::new([System.Windows.Controls.Grid])
        [void]$stil.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Panel]::BackgroundProperty, [System.Windows.Media.Brushes]::Transparent))
        $trigger = [System.Windows.Trigger]::new()
        $trigger.Property = [System.Windows.UIElement]::IsMouseOverProperty
        $trigger.Value = $true
        $pinsel = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(232, 241, 251))
        $pinsel.Freeze()
        [void]$trigger.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Panel]::BackgroundProperty, $pinsel))
        [void]$stil.Triggers.Add($trigger)
        $script:ZeilenStil = $stil
    }
    $Gitter.Style = $script:ZeilenStil
}

## Laufwerkszeile: Text "frei von gesamt (belegt)" und Balken mit dem belegten Anteil (ab 90 % rot), ohne Kopieren-Knopf
function Add-WolLaufwerkZeile {
    param($Panel, $Laufwerk)
    $gesamt = [double]$Laufwerk.Gesamt
    $frei = [double]$Laufwerk.Frei
    $belegt = [math]::Max($gesamt - $frei, 0)
    $anteil = if ($gesamt -gt 0) { [math]::Min(($belegt / $gesamt) * 100, 100) } else { 0 }

    $gitter = [System.Windows.Controls.Grid]::new()
    $gitter.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
    Set-WolZeilenHover -Gitter $gitter
    $spalte1 = [System.Windows.Controls.ColumnDefinition]::new()
    $spalte1.Width = [System.Windows.GridLength]::new(160)
    $spalte2 = [System.Windows.Controls.ColumnDefinition]::new()
    $spalte2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    [void]$gitter.ColumnDefinitions.Add($spalte1)
    [void]$gitter.ColumnDefinitions.Add($spalte2)

    $beschriftung = [System.Windows.Controls.TextBlock]::new()
    $beschriftung.Text = "Laufwerk $($Laufwerk.Laufwerk)"
    $beschriftung.FontWeight = [System.Windows.FontWeights]::Bold
    $beschriftung.Margin = [System.Windows.Thickness]::new(0, 3, 8, 0)
    $beschriftung.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    [System.Windows.Controls.Grid]::SetColumn($beschriftung, 0)
    [void]$gitter.Children.Add($beschriftung)

    $inhalt = [System.Windows.Controls.StackPanel]::new()
    $text = [System.Windows.Controls.TextBlock]::new()
    $text.Text = '{0} GB frei von {1} GB (belegt {2} GB)' -f $frei, $gesamt, $belegt
    $text.Margin = [System.Windows.Thickness]::new(0, 2, 0, 3)
    [void]$inhalt.Children.Add($text)
    $balken = [System.Windows.Controls.ProgressBar]::new()
    $balken.Minimum = 0
    $balken.Maximum = 100
    $balken.Value = $anteil
    $balken.Height = 14
    $balken.Width = 300
    $balken.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $farbe = if ($anteil -ge 90) { [System.Windows.Media.Color]::FromRgb(218, 38, 38) } else { [System.Windows.Media.Color]::FromRgb(38, 160, 218) }
    $balken.Foreground = [System.Windows.Media.SolidColorBrush]::new($farbe)
    $balken.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(230, 230, 230))
    $balken.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(188, 188, 188))
    [void]$inhalt.Children.Add($balken)
    [System.Windows.Controls.Grid]::SetColumn($inhalt, 1)
    [void]$gitter.Children.Add($inhalt)
    [void]$Panel.Children.Add($gitter)
}

# Neuer Client und Einzel-Scan
## MAC-Adresse in die Schreibweise AA:BB:CC:DD:EE:FF bringen; leer, wenn sie nicht aus 12 Hexadezimalzeichen besteht
function ConvertTo-WolMac {
    param([string]$Text)
    $hex = ($Text -replace '[^0-9A-Fa-f]', '').ToUpper()
    if ($hex.Length -ne 12) { return '' }
    return ($hex -replace '(.{2})(?!$)', '$1:')
}

## Neuen Client von Hand eintragen (Werkzeuge): Pflichtfeld ist die IP-Adresse, die MAC-Adresse ist optional
function Show-WolNeuerClient {
    $d = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Neuer Client" Width="460" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Pflichtfelder sind mit * markiert." Foreground="DimGray" Margin="0,0,0,8"/>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Text="MAC-Adresse" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtMac" Grid.Row="0" Grid.Column="1" Margin="0,0,0,6" ToolTip="Optional. Zum Beispiel AA:BB:CC:DD:EE:FF oder AA-BB-CC-DD-EE-FF"/>
      <TextBlock Grid.Row="1" Text="IP-Adresse *" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtIp" Grid.Row="1" Grid.Column="1" Margin="0,0,0,6"/>
      <TextBlock Grid.Row="2" Text="Hostname" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtHost" Grid.Row="2" Grid.Column="1" Margin="0,0,0,6"/>
      <TextBlock Grid.Row="3" Text="Typ" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <ComboBox x:Name="CmbTyp" Grid.Row="3" Grid.Column="1" Margin="0,0,0,6">
        <ComboBoxItem Content=""/><ComboBoxItem Content="Client"/><ComboBoxItem Content="Server physisch"/><ComboBoxItem Content="Server virtuell"/>
      </ComboBox>
      <TextBlock Grid.Row="4" Text="Konto" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtKonto" Grid.Row="4" Grid.Column="1" Margin="0,0,0,6" ToolTip="Leer = angemeldetes Windows-Konto. Sonst Domäne\Benutzer oder .\Benutzer; das Kennwort wird bei der ersten Aktion abgefragt."/>
      <TextBlock Grid.Row="5" Text="Bemerkung" VerticalAlignment="Center" Margin="0,0,0,6"/>
      <TextBox x:Name="TxtBem" Grid.Row="5" Grid.Column="1" Margin="0,0,0,6"/>
    </Grid>
    <TextBlock x:Name="TxtFehler" Foreground="Firebrick" TextWrapping="Wrap" Margin="0,4,0,0"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnOk" Content="Hinzufügen" Padding="14,4" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="BtnAbbruch" Content="Abbrechen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $d.Owner = $script:Fenster
    $c = @{}
    foreach ($n in 'TxtMac', 'TxtIp', 'TxtHost', 'CmbTyp', 'TxtKonto', 'TxtBem', 'TxtFehler', 'BtnOk', 'BtnAbbruch') { $c[$n] = $d.FindName($n) }
    $c.CmbTyp.SelectedIndex = 0
    $c.BtnAbbruch.Add_Click({ $d.Close() })
    $c.BtnOk.Add_Click({
        $c.TxtFehler.Text = ''
        $mac = ''
        if ($c.TxtMac.Text.Trim()) {
            $mac = ConvertTo-WolMac -Text $c.TxtMac.Text
            if (-not $mac) { $c.TxtFehler.Text = 'Die MAC-Adresse ist ungültig. Erwartet werden 12 Hexadezimalzeichen, zum Beispiel AA:BB:CC:DD:EE:FF. Sie darf auch leer bleiben.'; return }
        }
        $ip = $c.TxtIp.Text.Trim()
        $adr = $null
        if (-not ([System.Net.IPAddress]::TryParse($ip, [ref]$adr)) -or $adr.AddressFamily -ne 'InterNetwork' -or ($ip.Split('.').Count -ne 4)) {
            $c.TxtFehler.Text = 'Die IP-Adresse ist ungültig. Erwartet wird eine IPv4-Adresse, zum Beispiel 192.168.1.50.'; return
        }
        $vorhanden = $null
        if ($mac) { $vorhanden = $script:Zeilen | Where-Object { $_.MAC -eq $mac } | Select-Object -First 1 }
        if ($vorhanden) {
            $wer = if ($vorhanden.Hostname) { $vorhanden.Hostname } else { $vorhanden.IP }
            $c.TxtFehler.Text = "Diese MAC-Adresse steht schon in der Liste ($wer, IP $($vorhanden.IP))."
            return
        }
        $hostname = $c.TxtHost.Text.Trim()
        $hinweise = [System.Collections.Generic.List[string]]::new()
        $gleicheIp = $script:Zeilen | Where-Object { $_.IP -eq $ip } | Select-Object -First 1
        if ($gleicheIp) { $hinweise.Add("Die IP-Adresse $ip steht schon bei $(if ($gleicheIp.Hostname) { $gleicheIp.Hostname } else { 'einem anderen Eintrag' }).") }
        if ($hostname) {
            $kurz = $hostname.Split('.')[0].ToLower()
            $gleicherName = $script:Zeilen | Where-Object { $_.Hostname -and ([string]$_.Hostname).Split('.')[0].ToLower() -eq $kurz } | Select-Object -First 1
            if ($gleicherName) { $hinweise.Add("Der Hostname $hostname steht schon in der Liste (IP $($gleicherName.IP)).") }
        }
        if ($hinweise.Count -gt 0) {
            $antwort = [System.Windows.MessageBox]::Show(($hinweise -join "`r`n") + "`r`n`r`nTrotzdem eintragen?", 'NET-COCKPIT', 'YesNo', 'Question', 'No')
            if ($antwort -ne 'Yes') { return }
        }
        $z = New-Object NetCockpitZeile
        $z.MAC = $mac
        $z.IP = $ip
        $z.Hostname = $hostname
        $z.Typ = [string]$c.CmbTyp.Text
        $z.Konto = $c.TxtKonto.Text.Trim()
        $z.Bemerkung = $c.TxtBem.Text.Trim()
        if ($mac) {
            $h = Get-WolHerstellerName -Mac $mac
            $script:OuiKarte = $null
            if ($h) { $z.Hersteller = $h }
        }
        $z.ZuletztGesehen = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $z.Status = 'Noch nicht geprüft'
        $script:Zeilen.Add($z)
        $script:Geaendert = $true
        Save-WolAuto
        Update-WolAnsicht
        Write-WolLog "Neuer Client eingetragen: $(if ($hostname) { $hostname } else { $ip })$(if ($mac) { " ($mac)" })"
        $d.Close()
        Start-WolStatusPruefung
    })
    [void]$d.ShowDialog()
}

## Einzel-Scan: läuft als Thread-Job je Gerät (Ping, WinRM-Port, Name per DNS, MAC aus der ARP-Tabelle)
$script:EinzelBlock = {
    param([string]$Ip)
    $ping = $false
    try { $ping = ([System.Net.NetworkInformation.Ping]::new().Send($Ip, 1500)).Status -eq 'Success' } catch { }
    $winrm = $false
    if ($ping) {
        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $winrm = $tcp.ConnectAsync($Ip, 5985).Wait(1500) -and $tcp.Connected
            $tcp.Dispose()
        } catch { }
    }
    $name = ''
    try {
        $dns = [System.Net.Dns]::GetHostEntryAsync($Ip)
        if ($dns.Wait(2500)) { $name = [string]$dns.Result.HostName }
    } catch { }
    if ($name -eq $Ip) { $name = '' }
    $mac = ''
    if ($ping) {
        try {
            $n = Get-NetNeighbor -IPAddress $Ip -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' } | Select-Object -First 1
            if ($n) { $mac = [string]$n.LinkLayerAddress }
        } catch { }
    }
    [pscustomobject]@{ Ping = $ping; WinRM = $winrm; Hostname = $name; Mac = $mac }
}

## Auswertung des Einzel-Scans (läuft im Poll-Timer): Ampel und Status setzen, nur leere Felder füllen
$script:EinzelFertig = {
    param($a)
    $z = $a.Zeile
    $name = if ($z.Hostname) { ([string]$z.Hostname).Split('.')[0] } else { $z.IP }
    try {
        $erg = @(Receive-Job -Job $a.Job -ErrorAction Stop) | Select-Object -Last 1
        if (-not $erg) { throw 'keine Rückmeldung' }
        $neu = [System.Collections.Generic.List[string]]::new()
        if ($erg.Ping -and $erg.WinRM) { $z.Ampel = 'Gruen'; $z.Status = 'Online (WinRM erreichbar)' }
        elseif ($erg.Ping) { $z.Ampel = 'Gelb'; $z.Status = 'Online (kein WinRM)' }
        else { $z.Ampel = 'Rot'; $z.Status = 'Offline' }
        if (-not $z.Hostname -and $erg.Hostname) { $z.Hostname = [string]$erg.Hostname; $neu.Add('Hostname') }
        $mac = ConvertTo-WolMac -Text ([string]$erg.Mac)
        if (-not $z.MAC -and $mac) {
            $andere = $script:Zeilen | Where-Object { $_ -ne $z -and $_.MAC -eq $mac } | Select-Object -First 1
            if ($andere) { Write-WolLog "MAC $mac von $name steht schon in einer anderen Zeile (IP $($andere.IP)) und wurde nicht eingetragen" }
            else { $z.MAC = $mac; $neu.Add('MAC') }
        }
        if ($z.MAC -and -not $z.Hersteller) {
            $h = Get-WolHerstellerName -Mac $z.MAC
            if ($h) { $z.Hersteller = $h; $neu.Add('Hersteller') }
        }
        if ($neu.Count -gt 0) { $script:Geaendert = $true; Save-WolAuto }
        Write-WolLog "Einzel-Scan $name : $($z.Status)$(if ($neu.Count -gt 0) { ', ergänzt: ' + ($neu -join ', ') })"
    }
    catch {
        $z.Status = 'Einzel-Scan fehlgeschlagen'
        Write-WolLog "Einzel-Scan fehlgeschlagen: $name - $($_.Exception.Message)"
    }
    Update-WolAnsicht
    if ((Get-WolGruppeOffen -Gruppe 'Einzel') -eq 0) { $script:OuiKarte = $null }
}

## Markierte Geräte einzeln scannen (Werkzeuge)
function Start-WolEinzelScan {
    $ziele = @(Get-WolMarkierte)
    if ($ziele.Count -eq 0) { Show-WolMeldung 'Es ist kein Gerät markiert.'; return }
    $bereit = @($ziele | Where-Object { $_.IP })
    if ($bereit.Count -eq 0) { Show-WolMeldung 'Die markierten Geräte haben keine IP-Adresse.'; return }
    $gestartet = 0
    foreach ($z in $bereit) {
        if ((Get-WolGruppeOffen -Gruppe 'Einzel' -Zeile $z) -gt 0) { continue }
        Add-WolAuftrag -Zeile $z -Block $script:EinzelBlock -Argumente @([string]$z.IP) -Fertig $script:EinzelFertig -Gruppe 'Einzel' -Starttext 'Einzel-Scan läuft...'
        $gestartet++
    }
    if ($gestartet -gt 0) { Write-WolLog "Einzel-Scan gestartet: $gestartet Gerät(e)" }
}

Add-WolStartMarke 'Funktionen der Aktionen definiert'

# Timer
## Abfrage laufender Jobs (Scan, Statusprüfung, Portscan und die Warteschlange)
$script:PollTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:PollTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:PollTimer.Add_Tick({
    # Scan
    if ($script:ScanJob -and $script:ScanJob.State -in 'Completed', 'Failed', 'Stopped') {
        $job = $script:ScanJob
        $script:ScanJob = $null
        if (-not $script:Opt.AutoScan) { $script:ScanAktiv = $false }
        Update-WolScanAnzeige
        try {
            $erg = @(Receive-Job -Job $job -ErrorAction Stop) | Select-Object -Last 1
            Merge-WolErgebnis -Ergebnis $erg -Info $script:ScanInfo
            if (-not $script:ScanStill) { Write-WolLog "Scan fertig: $($erg.Gefunden.Count) Geräte antworten" }
            if ($erg.OuiFehler) { Write-WolLog "Hersteller-Liste: $($erg.OuiFehler)" }
            Save-WolAuto
        }
        catch { Write-WolLog "Scan-Fehler: $($_.Exception.Message)" }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    # Statusprüfung
    if ($script:StatusJob -and $script:StatusJob.State -in 'Completed', 'Failed', 'Stopped') {
        $job = $script:StatusJob
        $script:StatusJob = $null
        try {
            $karte = @{}
            foreach ($e in @(Receive-Job -Job $job -ErrorAction Stop)) { $karte[$e.IP] = $e }
            $jetzt = Get-Date -Format 'yyyy-MM-dd HH:mm'
            foreach ($z in $script:Zeilen) {
                if (-not $z.IP) { continue }
                $e = $karte[$z.IP]
                if (-not $e) { continue }
                if ($e.WinRM) { $z.Ampel = 'Gruen'; $text = 'Online (WinRM erreichbar)' }
                elseif ($e.Online) { $z.Ampel = 'Gelb'; $text = 'Online (kein WinRM)' }
                else { $z.Ampel = 'Rot'; $text = 'Offline' }
                if ($z.Status -match '^(Noch nicht geprüft|Online|Offline)') { $z.Status = $text }
                if ($e.Online) { $z.ZuletztGesehen = $jetzt }
            }
            Update-WolAnsicht
            Save-WolAuto
        }
        catch { Write-WolLog "Fehler bei der Statusprüfung: $($_.Exception.Message)" }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    # Portscan
    while ($script:PortWarteschlange.Count -gt 0 -and $script:PortJobs.Count -lt 3) {
        $w = $script:PortWarteschlange[0]
        $script:PortWarteschlange.RemoveAt(0)
        $st = [hashtable]::Synchronized(@{ Fertig = 0; Gesamt = $w.Ports.Count; Abbruch = $false })
        $job = Start-ThreadJob -ScriptBlock $script:PortBlock -ArgumentList $w.Ip, $w.Ports, 150, $st
        $w.Zeile.Ports = 'Portscan läuft... 0 %'
        $script:PortJobs.Add([pscustomobject]@{ Job = $job; Zeile = $w.Zeile; Status = $st; Bereich = $w.Bereich })
        Write-WolLog "Portscan gestartet: $($w.Ip) ($($w.Ports.Count) Ports)"
    }
    foreach ($p in @($script:PortJobs)) {
        if ($p.Job.State -notin 'Completed', 'Failed', 'Stopped') {
            $p.Zeile.Ports = 'Portscan läuft... {0} %' -f [int](100 * $p.Status.Fertig / [math]::Max(1, $p.Status.Gesamt))
            continue
        }
        try {
            $erg = @(Receive-Job -Job $p.Job -ErrorAction Stop) | Select-Object -Last 1
            if ($erg.Abgebrochen) { $p.Zeile.Ports = 'Portscan abgebrochen' }
            elseif (@($erg.Offen).Count -eq 0) { $p.Zeile.Ports = "keine offen ($($p.Bereich))" }
            else { $p.Zeile.Ports = Format-WolPorts -Ports ([int[]]@($erg.Offen)) }
            Write-WolLog "Portscan fertig: $($p.Zeile.IP) - $($p.Zeile.Ports)"
        }
        catch { $p.Zeile.Ports = "Fehler: $($_.Exception.Message)" }
        Remove-Job -Job $p.Job -Force -ErrorAction SilentlyContinue
        [void]$script:PortJobs.Remove($p)
        $script:Geaendert = $true
        Save-WolAuto
    }

    # Aufträge der Warteschlange (Aktionen, Befehl, KuDo, Herstellerliste, OU und die Module)
    Update-WolAuftraege
    Test-WolGeplanteNeustarts
    Test-WolTrustedHinweis
})

## Auto-Scan
$script:AutoTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:AutoTimer.Add_Tick({ Start-WolScan -Still })

## Statusprüfung
$script:StatusTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:StatusTimer.Add_Tick({ Start-WolStatusPruefung })

Add-WolStartMarke 'Timer definiert'

# Ereignisse
$script:C.BtnAktuellesNetz.Add_Click({
    $cidr = Get-WolAktuellesNetz
    if (-not $cidr) { Show-WolMeldung 'Es wurde keine aktive Netzwerkkarte mit Gateway gefunden.' 'Warning'; return }
    Set-WolNetz -Cidr $cidr
})
$script:C.BtnAnderesNetz.Add_Click({
    $frage = 'Welche Netze sollen gescannt werden? Erlaubt sind Netze (Netzadresse/Präfixlänge von /22 bis /30), IP-Bereiche (von-bis) und einzelne IP-Adressen. Mehrere Einträge werden mit Komma getrennt.'
    $hinweis = 'Hinweis: MAC-Adresse und Hersteller kommen aus der ARP-Tabelle und werden nur im eigenen Subnetz gefunden. Ein Bereich im eigenen Subnetz liefert MAC-Adressen, ein Bereich in einem fremden Netz nicht. Ohne MAC-Adresse ist kein Aufwecken möglich, und die Geräte werden über die IP-Adresse erkannt. Insgesamt sind maximal 1024 Adressen über alle Netze und Bereiche erlaubt.'
    $eingabe = Show-WolEingabe -Titel 'Anderes Netz eingeben' -Frage $frage -Vorgabe ([string]$script:NetzCidr) -Hinweis $hinweis
    if ($eingabe) { Set-WolNetz -Cidr $eingabe }
})
$script:C.BtnScanStart.Add_Click({ Start-WolScanSteuerung })
$script:C.BtnScanStopp.Add_Click({ Stop-WolScanSteuerung })
$script:C.CmbAnzeige.Add_SelectionChanged({
    $item = $script:C.CmbAnzeige.SelectedItem
    if (-not $item -or $script:Opt.Anzeige -eq [string]$item.Tag) { return }
    $script:Opt.Anzeige = [string]$item.Tag
    Update-WolAnsicht -Bestaetigen
    Save-WolEinstellungen
})

## Optionen ändern (Auto-Scan, Statusprüfung, Auto-Speichern, Parallelität)
function Edit-WolOptionen {
    $erg = Show-WolOptionen
    if (-not $erg) { return }
    $script:Opt.AutoScan = $erg.AutoScan
    $script:Opt.AutoMin = $erg.AutoMin
    $script:Opt.Status = $erg.Status
    $script:Opt.StatusMin = $erg.StatusMin
    $script:Opt.AutoSpeichern = $erg.AutoSpeichern
    $script:Opt.Parallel = $erg.Parallel
    Set-WolAutoScan
    if (-not $script:Opt.AutoScan -and -not $script:ScanJob -and $script:ScanAktiv) { $script:ScanAktiv = $false }
    Set-WolStatusTimer
    if ($script:Opt.Status) { Start-WolStatusPruefung }
    Update-WolScanAnzeige
    Save-WolEinstellungen
}

## Menüleiste: Menüpunkte mit ihren Aktionen verbinden
$script:MenueAktionen = [ordered]@{
    MnuNeueListe         = { New-WolListe }
    MnuOeffnen           = { Open-WolListeDialog }
    MnuSpeichern         = { Save-WolListeAktuell }
    MnuSpeichernUnter    = { [void](Save-WolListeUnter) }
    MnuOu                = { Import-WolOu }
    MnuExport            = { Export-WolListe }
    MnuBeenden           = { $script:Fenster.Close() }
    MnuNeustart          = { Start-WolAktion -Art 'Neustart' }
    MnuNeustartPlanen    = { Start-WolAktion -Art 'Planen' }
    MnuNeustartAbbrechen = { Start-WolAktion -Art 'Abbrechen' }
    MnuHerunterfahren    = { Start-WolAktion -Art 'Herunterfahren' }
    MnuUpdOs             = { Open-WolModul -Key 'OS' }
    MnuUpdApp            = { Open-WolModul -Key 'APP' }
    MnuUpdTreiber        = { Open-WolModul -Key 'TREIBER' }
    MnuDiagnose          = { Open-WolModul -Key 'DIAGNOSE' }
    MnuWatoki            = { Open-WolModul -Key 'WATOKI' }
    MnuM365App           = { Open-WolModul -Key 'M365APP' }
    MnuRdp               = { Open-WolModul -Key 'RDP' }
    MnuWol               = { Open-WolModul -Key 'WOL' }
    MnuPortscan          = { Start-WolPortscan }
    MnuPortscanAbbrechen = { Stop-WolPortscan }
    MnuPing              = { Show-WolPing }
    MnuBefehl            = { Show-WolBefehl }
    MnuKudo              = { Start-WolKudoMarkierte }
    MnuNeuerClient       = { Show-WolNeuerClient }
    MnuEntfernen         = { Remove-WolMarkierte }
    MnuEinzelScan        = { Start-WolEinzelScan }
    MnuMouseMover        = { Open-WolModul -Key 'MOUSEMOVER' }
    MnuHersteller        = { Start-WolHerstellerDownload }
    MnuKonto             = { Set-WolKontoMarkierte }
    MnuTrustedEintragen  = { Add-WolTrustedHosts }
    MnuTrustedEntfernen  = { Remove-WolTrustedHosts }
    MnuTrustedAnzeigen   = { Show-WolTrustedHosts }
    MnuEinstellungen     = { Edit-WolOptionen }
    MnuInfo              = { Show-WolInfo }
    MnuDatenLoeschen     = { Remove-WolDaten }
}
foreach ($name in $script:MenueAktionen.Keys) {
    $punkt = $script:Fenster.FindName($name)
    $punkt.Add_Click($script:MenueAktionen[$name])
}

## Filter löschen
$script:C.BtnFilterLoeschen.Add_Click({ foreach ($box in $script:FilterBoxen) { $box.Text = '' } })

$script:C.BtnBeenden.Add_Click({ $script:Fenster.Close() })

$script:C.BtnAlle.Add_Click({ $script:C.Gitter.SelectAll() })
$script:C.BtnKeine.Add_Click({ $script:C.Gitter.UnselectAll() })
$script:C.BtnNurOnline.Add_Click({
    $script:C.Gitter.UnselectAll()
    foreach ($z in @($script:Ansicht)) {
        if ($z.Ampel -in 'Gruen', 'Gelb') { [void]$script:C.Gitter.SelectedItems.Add($z) }
    }
})
$script:C.Gitter.Add_CellEditEnding({
    param($sender, $e)
    $script:Geaendert = $true
    ### MAC-Spalte: Eingabe prüfen und als AA:BB:CC:DD:EE:FF übernehmen, Hersteller neu bestimmen
    if ($e.EditAction -ne [System.Windows.Controls.DataGridEditAction]::Commit) { return }
    if ($e.Column.SortMemberPath -ne 'MAC') { return }
    $feld = $e.EditingElement -as [System.Windows.Controls.TextBox]
    if (-not $feld) { return }
    $z = $e.Row.Item
    $text = $feld.Text.Trim()
    if (-not $text) {
        $feld.Text = ''
        $z.Hersteller = ''
        Write-WolLog "MAC von $(if ($z.Hostname) { $z.Hostname } else { $z.IP }) geleert"
        return
    }
    $mac = ConvertTo-WolMac -Text $text
    if (-not $mac) {
        $e.Cancel = $true
        Show-WolMeldung 'Die MAC-Adresse ist ungültig. Erwartet werden 12 Hexadezimalzeichen, zum Beispiel 00:20:6b:f4:cd:28, 00-20-6b-f4-cd-28 oder 00206bf4cd28. Esc verwirft die Eingabe.'
        return
    }
    $andere = $script:Zeilen | Where-Object { $_ -ne $z -and $_.MAC -eq $mac } | Select-Object -First 1
    if ($andere) {
        $e.Cancel = $true
        Show-WolMeldung "Diese MAC-Adresse steht schon in der Liste ($(if ($andere.Hostname) { $andere.Hostname } else { $andere.IP }), IP $($andere.IP)). Esc verwirft die Eingabe."
        return
    }
    $feld.Text = $mac
    $h = Get-WolHerstellerName -Mac $mac
    $z.Hersteller = $(if ($h) { $h } else { '' })
    Write-WolLog "MAC von $(if ($z.Hostname) { $z.Hostname } else { $z.IP }) eingetragen: $mac"
})
$script:C.Gitter.Add_BeginningEdit({ $script:Bearbeitet = $true })
## Log eines Geräts: Zeilen aus dem Cockpit-Log und die Logs der Module APP, OS und Treiber, nur für dieses Gerät
function Get-WolGeraeteLogText {
    param($Zeile)
    $kurz = $(if ($Zeile.Hostname) { ([string]$Zeile.Hostname).Split('.')[0] } else { '' })
    $namen = @($kurz, ([string]$Zeile.IP).Trim()) | Where-Object { $_ }
    if ($namen.Count -eq 0) { return 'Das Gerät hat weder Hostname noch IP, daher gibt es kein Log.' }
    $muster = '(?i)(?<![\w.\-])(' + ((@($namen | ForEach-Object { [regex]::Escape($_) })) -join '|') + ')(?![\w\-])'
    $sb = [System.Text.StringBuilder]::new()

    ### Cockpit-Log
    [void]$sb.AppendLine('===== Cockpit-Log (NET-COCKPIT.log) =====')
    $treffer = 0
    if (Test-Path -LiteralPath $script:LogPfad) {
        try {
            foreach ($l in @(Get-Content -LiteralPath $script:LogPfad -Encoding utf8 -ErrorAction Stop)) {
                if ($l -match $muster) { [void]$sb.AppendLine($l); $treffer++ }
            }
        }
        catch { [void]$sb.AppendLine("Log nicht lesbar: $($_.Exception.Message)") }
    }
    if ($treffer -eq 0) { [void]$sb.AppendLine('(keine Einträge seit dem Start des Cockpits)') }

    ### Logs der Module je Gerät (Dateiname yyyyMMdd_Gerät_...-log.txt)
    $sicher = ($(if ($kurz) { $kurz } else { ([string]$Zeile.IP).Trim() }) -replace '[^\w\.\-]', '_')
    foreach ($ordner in 'Modul-APP', 'Modul-OS', 'Modul-TREIBER') {
        $pfad = Join-Path $script:DatenOrdner $ordner
        if (-not (Test-Path -LiteralPath $pfad)) { continue }
        foreach ($datei in @(Get-ChildItem -LiteralPath $pfad -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*_${sicher}_*" } | Sort-Object -Property Name)) {
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("===== $ordner : $($datei.Name) =====")
            try { foreach ($l in @(Get-Content -LiteralPath $datei.FullName -Encoding utf8 -ErrorAction Stop)) { [void]$sb.AppendLine($l) } }
            catch { [void]$sb.AppendLine("Log nicht lesbar: $($_.Exception.Message)") }
        }
    }
    return $sb.ToString()
}

## Fenster mit dem Log eines Geräts (Doppelklick auf die Spalte "Aktion / Status")
function Show-WolGeraeteLog {
    param($Zeile)
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="950" Height="600" WindowStartupLocation="CenterOwner">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBox x:Name="TxtLog" Grid.Row="0" IsReadOnly="True" TextWrapping="NoWrap" FontFamily="Consolas" FontSize="12"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnNeu" Content="Aktualisieren" Padding="14,4" Margin="0,0,8,0"/>
      <Button x:Name="BtnZu" Content="Schließen" Padding="14,4" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $f.Owner = $script:Fenster
    $f.Tag = $Zeile
    $f.Title = 'Log: ' + $(if ($Zeile.Hostname) { [string]$Zeile.Hostname } else { [string]$Zeile.IP })
    $box = $f.FindName('TxtLog')
    $box.Text = Get-WolGeraeteLogText -Zeile $Zeile
    $box.ScrollToEnd()
    $f.FindName('BtnNeu').Add_Click({
        param($sender, $e)
        $w = [System.Windows.Window]::GetWindow($sender)
        $b = $w.FindName('TxtLog')
        $b.Text = Get-WolGeraeteLogText -Zeile $w.Tag
        $b.ScrollToEnd()
    })
    $f.FindName('BtnZu').Add_Click({
        param($sender, $e)
        [System.Windows.Window]::GetWindow($sender).Close()
    })
    $f.Show()
}

$script:C.Gitter.Add_MouseDoubleClick({
    param($sender, $e)
    $zelle = Get-WolVorfahre -Start $e.OriginalSource -Typ ([System.Windows.Controls.DataGridCell])
    if (-not $zelle) { return }
    if ($zelle.Column.SortMemberPath -eq 'Status') {
        if ($zelle.DataContext -is [NetCockpitZeile]) { Show-WolGeraeteLog -Zeile $zelle.DataContext }
        return
    }
    if ($zelle.Column.SortMemberPath -in 'Hostname', 'Typ', 'Bemerkung', '[Wartungsreihenfolge]') { return }
    $zeile = $zelle.DataContext
    if ($zeile -is [NetCockpitZeile]) { Show-WolDetails -Zeile $zeile }
})

$script:Fenster.Add_Closing({
    param($sender, $e)
    if (-not $script:OhneSpeichern) {
        Complete-WolBearbeitung
        if (-not (Confirm-WolSpeichern)) { $e.Cancel = $true; return }
        Save-WolEinstellungen
    }
    Stop-WolHintergrund
})

Add-WolStartMarke 'Ereignisse verbunden'

# Start
try {
    [NetCockpitZeile]::StandardKonto = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Update-WolListeAnzeige
    $script:PollTimer.Start()
    Update-WolScanAnzeige
    Set-WolStatusTimer
    Write-WolLog 'Bereit: Liste über Datei > Öffnen laden, Computer über Datei > OU wählen einlesen oder ein Netz wählen und scannen'
    ## Startzeiten ins Log schreiben
    Add-WolStartMarke 'Start-Block fertig'
    Write-WolLog "Startzeit: Der PowerShell-Prozess war beim Skriptstart schon $($script:ProzessAlter) s alt"
    foreach ($marke in $script:StartMarken) { Write-WolLog "Startzeit: $marke" }
    ## Fenster sicher sichtbar machen: Taskleiste, normaler Zustand, einmal in den Vordergrund
    $script:Fenster.ShowInTaskbar = $true
    $script:Fenster.Add_ContentRendered({
        try {
            $script:Fenster.ShowInTaskbar = $true
            if ($script:Fenster.WindowState -ne 'Normal') { $script:Fenster.WindowState = 'Normal' }
            [void]$script:Fenster.Activate()
            Add-WolStartMarke 'Fenster sichtbar'
            Write-WolLog "Startzeit: $($script:StartMarken[$script:StartMarken.Count - 1])"
            $script:Fenster.Topmost = $true
            $script:Fenster.Topmost = $false
            $script:Fenster.Focus() | Out-Null
        }
        catch { }
    })
    [void]$script:Fenster.ShowDialog()
}
catch {
    Show-WolMeldung "Fehler beim Start: $($_.Exception.Message)" 'Error'
}
