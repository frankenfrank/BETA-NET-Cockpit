# NET-COCKPIT-Modul-RDP.ps1
<#
.SYNOPSIS
    Modul RDP für das NET-COCKPIT (Menü Module > RDP)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und öffnet Remotedesktop-Verbindungen in einem eigenen Fenster (RDP-MODUL, kein Vollbild) mit einem Tab je Verbindung.
    - Module > RDP verbindet die markierten Geräte der Tabelle, jedes Gerät in einem eigenen Tab; ist das Fenster schon offen, kommen die markierten Geräte als weitere Tabs dazu
    - Ziel ist der Hostname, sonst die IP-Adresse (wie bei den anderen Modulen)
    - Konto und Kennwort kommen aus der Spalte "Konto" (Optionen > Konto für markierte Geräte); das Kennwort geht nur im Arbeitsspeicher an das RDP-Steuerelement und wird nirgends gespeichert
    - Ohne Eintrag in der Spalte "Konto" gilt das angemeldete Windows-Konto: Windows gibt dessen Kennwort nicht heraus, deshalb fragt das Modul es einmal pro Sitzung ab (nur im Arbeitsspeicher, bis das NET-COCKPIT geschlossen wird); per GPO (Delegierung von Standardanmeldeinformationen) entfällt die Abfrage, der Hinweis dazu steht im Fenster
    - Für Geräte mit eigenem Konto in der Spalte "Konto" kommt keine Abfrage; fehlt dort das Kennwort der Sitzung, startet nichts und die Geräte werden genannt
    - Die Auflösung folgt der Fenstergröße, auch beim Vergrößern des Fensters; umgeleitet wird nur die Zwischenablage (keine Laufwerke, Drucker oder Smartcards)
    - Tab schließen oder Fenster schließen trennt die Verbindung (der Benutzer bleibt auf dem Server angemeldet)
    - Das Fenster ist eigenständig (eigenes Taskleistensymbol) und bleibt nicht vor dem NET-COCKPIT liegen; beendest du das NET-COCKPIT, kommt bei bestehenden Verbindungen eine Rückfrage, danach schließt sich das RDP-Fenster mit
    - Knopf "Abmelden" meldet den Benutzer der Sitzung des gerade aktiven Tabs auf dem Server ab (nur Abmelden, kein Neustart und kein Herunterfahren): das Modul sucht die RDP-Sitzung des Kontos über WinRM (quser) und beendet sie mit logoff; vorher kommt eine Rückfrage; danach schließt sich der Tab
    - Knopf "Neu verbinden" baut die Verbindung des gerade aktiven Tabs neu auf (der Benutzer bleibt auf dem Server angemeldet)
    - Ist ein markiertes Gerät schon verbunden, springt das Modul zu seinem Tab statt einen neuen zu öffnen; ein getrennter Tab wird durch den neuen ersetzt
    Sonst speichert das Modul nichts.
#>

# Einstellungen
## Zustand: Fenster, Steuerelemente und Klassen-ID des RDP-Steuerelements (bleibt auch bei geschlossenem Fenster erhalten)
$script:RdFenster = $null
$script:RdC = @{}
$script:RdClsid = $null
$script:RdZeitgeber = $null
$script:RdAktuellKennwort = $null   ### Kennwort des angemeldeten Windows-Kontos, nur Arbeitsspeicher und nur für diese Sitzung
$script:RdBeendenOhneFrage = $false   ### wird gesetzt, wenn das NET-COCKPIT beendet wird und die Rückfrage schon gestellt wurde

## Das RDP-Fenster hat keinen Besitzer (es bleibt nicht vor dem NET-COCKPIT liegen): beim Beenden des NET-COCKPIT kommt bei bestehenden Verbindungen die Rückfrage, danach schließt sich das RDP-Fenster mit
$script:Fenster.Add_Closing({
    param($sender, $e)
    if ($e.Cancel -or -not $script:RdFenster) { return }
    $aktive = Get-WolRdAktive
    if ($aktive -gt 0) {
        $antwort = [System.Windows.MessageBox]::Show("Im RDP-MODUL bestehen noch $aktive Verbindung(en).`r`nNET-COCKPIT beenden und alle Verbindungen trennen?", 'NET-COCKPIT', 'YesNo', 'Question')
        if ($antwort -ne 'Yes') { $e.Cancel = $true; return }
    }
    $script:RdBeendenOhneFrage = $true
})
$script:Fenster.Add_Closed({
    if ($script:RdFenster) { $script:RdBeendenOhneFrage = $true; $script:RdFenster.Close() }
})

## Klassen-IDs der RDP-Steuerelemente, neueste Version zuerst (Microsoft-Dokumentation: Remote Desktop ActiveX control)
$script:RdKandidaten = [ordered]@{
    'MsRdpClient10NotSafeForScripting' = 'A0C63C30-F08D-4AB4-907C-34905D770C7D'
    'MsRdpClient9NotSafeForScripting'  = '8B918B82-7985-4C24-89DF-C33AD2BBFBCD'
    'MsRdpClient8NotSafeForScripting'  = 'A3BC03A0-041D-42E3-AD22-882B7865C9C5'
    'MsRdpClient7NotSafeForScripting'  = '54D38BF7-B1EF-4479-9674-1BD6EA465258'
    'MsRdpClient6NotSafeForScripting'  = 'D2EA46A7-C2BF-426B-AF24-E19C44456399'
    'MsRdpClient5NotSafeForScripting'  = '4EB2F086-C818-447E-B32C-C51CE2B30D31'
}

# Bibliotheken und Hostklasse
## Windows Forms und die Brücke zu WPF (AxHost kann nur abgeleitet verwendet werden)
Add-Type -AssemblyName System.Windows.Forms, WindowsFormsIntegration
if (-not ('RdpAxHost' -as [type])) {
    $quelltext = @'
using System;
using System.Windows.Forms;

public class RdpAxHost : AxHost
{
    public RdpAxHost(string clsid) : base(clsid) { }
    public object Ocx { get { return this.GetOcx(); } }
}
'@
    $referenzen = [System.Collections.Generic.List[string]]::new()
    $steuerAssembly = [System.Windows.Forms.Control].Assembly
    $referenzen.Add($steuerAssembly.Location)
    foreach ($assemblyName in $steuerAssembly.GetReferencedAssemblies()) {
        try {
            $assembly = [System.Reflection.Assembly]::Load($assemblyName)
            if ($assembly.Location -and -not $referenzen.Contains($assembly.Location)) { $referenzen.Add($assembly.Location) }
        }
        catch { }
    }
    Add-Type -TypeDefinition $quelltext -ReferencedAssemblies $referenzen.ToArray() -ErrorAction Stop
}

# Hilfsfunktionen
## Neueste registrierte Version des RDP-Steuerelements suchen
function script:Get-WolRdSteuerelement {
    foreach ($eintrag in $script:RdKandidaten.GetEnumerator()) {
        if (Test-Path -LiteralPath "Registry::HKEY_CLASSES_ROOT\CLSID\{$($eintrag.Value)}") {
            return [pscustomobject]@{ Name = $eintrag.Key; Clsid = "{$($eintrag.Value)}" }
        }
    }
    return $null
}

## Benutzer in Name und Domäne trennen (DOMÄNE\Name wird getrennt, Name@Domäne bleibt ganz im Namen)
function script:Split-WolRdBenutzer {
    param([string]$Benutzer)
    $name = $Benutzer
    $domaene = ''
    if ($Benutzer -match '^(?<d>[^\\]+)\\(?<n>.+)$') { $domaene = $Matches.d; $name = $Matches.n }
    return [pscustomobject]@{ Name = $name; Domaene = $domaene }
}

## Auflösung in echten Pixeln für ein Steuerelement (berücksichtigt die Windows-Skalierung)
function script:Get-WolRdPixel {
    param($Host2)
    $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($Host2)
    return [pscustomobject]@{
        Breite = [Math]::Max(800, [int]($Host2.ActualWidth * $dpi.DpiScaleX))
        Hoehe  = [Math]::Max(600, [int]($Host2.ActualHeight * $dpi.DpiScaleY))
    }
}

## Zustand eines Tabs: 1 = verbunden, 2 = verbindet, 0 = getrennt
function script:Get-WolRdZustand {
    param($Info)
    try { return [int]$Info.Ax.Ocx.Connected } catch { return 0 }
}

## Verbindung eines Tabs trennen
function script:Stop-WolRdVerbindung {
    param($Info)
    try {
        $ocx = $Info.Ax.Ocx
        if ($ocx -and [int]$ocx.Connected -ne 0) { $ocx.Disconnect() }
    }
    catch { }
}

## Anzahl der Tabs mit bestehender oder laufender Verbindung
function script:Get-WolRdAktive {
    $anzahl = 0
    foreach ($tab in @($script:RdC.Tabs.Items)) {
        if ((Get-WolRdZustand -Info $tab.Tag) -ne 0) { $anzahl++ }
    }
    return $anzahl
}

# Tabs
## Nur den Inhalt des gewählten Tabs anzeigen (die anderen bleiben unsichtbar verbunden, sonst würde die Sitzung beim Wechsel verloren gehen)
function script:Update-WolRdAnzeige {
    $c = $script:RdC
    $gewaehlt = $c.Tabs.SelectedItem
    foreach ($tab in @($c.Tabs.Items)) {
        $tab.Tag.Wfh.Visibility = $(if ($tab -eq $gewaehlt) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Hidden })
    }
    $c.TxtLeer.Visibility = $(if ($c.Tabs.Items.Count -eq 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed })
}

## Tab schließen und Verbindung trennen
function script:Close-WolRdTab {
    param($Tab)
    $c = $script:RdC
    $info = $Tab.Tag
    Stop-WolRdVerbindung -Info $info
    $index = $c.Tabs.Items.IndexOf($Tab)
    $c.Tabs.Items.Remove($Tab)
    $c.Bereich.Children.Remove($info.Wfh)
    try { $info.Wfh.Dispose() } catch { }
    Write-WolLog "RDP: Verbindung zu $($info.Ziel) beendet"
    if ($c.Tabs.Items.Count -gt 0) { $c.Tabs.SelectedIndex = [Math]::Min($index, $c.Tabs.Items.Count - 1) }
    Update-WolRdAnzeige
}

## Neuen Tab mit Verbindung anlegen (die Verbindung wird hergestellt, sobald das Steuerelement angezeigt wird)
function script:Add-WolRdTab {
    param([string]$Ziel, [string]$Benutzer, $Kennwort)
    $c = $script:RdC
    $teile = Split-WolRdBenutzer -Benutzer $Benutzer

    ### Steuerelement und Host
    $ax = [RdpAxHost]::new($script:RdClsid)
    $wfh = [System.Windows.Forms.Integration.WindowsFormsHost]::new()
    $wfh.Child = $ax
    $wfh.Visibility = [System.Windows.Visibility]::Hidden

    ### Kopf des Tabs: Text und Schließen-Knopf
    $kopfText = [System.Windows.Controls.TextBlock]::new()
    $kopfText.Text = [string][char]0x25CC + ' ' + $Ziel
    $kopfText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $schliessen = [System.Windows.Controls.Button]::new()
    $schliessen.Content = [string][char]0x2715
    $schliessen.Padding = [System.Windows.Thickness]::new(5, 0, 5, 0)
    $schliessen.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
    $schliessen.BorderThickness = [System.Windows.Thickness]::new(0)
    $schliessen.Background = [System.Windows.Media.Brushes]::Transparent
    $kopf = [System.Windows.Controls.StackPanel]::new()
    $kopf.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    [void]$kopf.Children.Add($kopfText)
    [void]$kopf.Children.Add($schliessen)

    $tab = [System.Windows.Controls.TabItem]::new()
    $tab.Header = $kopf
    $tab.Tag = @{ Ax = $ax; Wfh = $wfh; Text = $kopfText; Ziel = $Ziel; Benutzer = $Benutzer; Kennwort = $Kennwort; Gestartet = $false; Verzoegerung = $null }
    $schliessen.Tag = $tab
    $schliessen.Add_Click({ param($sender, $e) Close-WolRdTab -Tab $sender.Tag })

    ### Verbindung herstellen, sobald das Steuerelement ein Fenster hat (einmalig)
    $wfh.Tag = @{ Tab = $tab; Ziel = $Ziel; Name = $teile.Name; Domaene = $teile.Domaene; Kennwort = $Kennwort }
    $wfh.Add_Loaded({
        param($sender, $e)
        $daten = $sender.Tag
        $info = $daten.Tab.Tag
        if ($info.Gestartet) { return }
        $info.Gestartet = $true
        try {
            $ocx = $info.Ax.Ocx
            $ocx.Server = $daten.Ziel
            if ($daten.Name) {
                $ocx.UserName = $daten.Name
                if ($daten.Domaene) { $ocx.Domain = $daten.Domaene }
                if ($daten.Kennwort) {
                    $klartext = [System.Net.NetworkCredential]::new('', [System.Security.SecureString]$daten.Kennwort).Password
                    $ocx.AdvancedSettings2.ClearTextPassword = $klartext
                    Write-WolLog "RDP: $($daten.Ziel) Benutzer '$($daten.Name)' Domäne '$($daten.Domaene)' Kennwort übergeben ($($klartext.Length) Zeichen)"
                    $klartext = $null
                }
            }
            if (-not $daten.Kennwort) { Write-WolLog "RDP: $($daten.Ziel) ohne Kennwort verbunden (kein Kennwort vorhanden)" }
            $ocx.AdvancedSettings2.EnableCredSspSupport = $true
            $ocx.AdvancedSettings2.SmartSizing = $true
            ### Zwischenablage umleiten (sonst nichts)
            foreach ($stufe in 'AdvancedSettings9', 'AdvancedSettings8', 'AdvancedSettings7', 'AdvancedSettings6') {
                try { $ocx.$stufe.RedirectClipboard = $true; break } catch { }
            }
            ### Auflösung = verfügbare Fläche
            $pixel = Get-WolRdPixel -Host2 $sender
            $ocx.DesktopWidth = $pixel.Breite
            $ocx.DesktopHeight = $pixel.Hoehe
            $ocx.Connect()
            $script:RdC.TxtStatus.Text = "Verbinde mit $($daten.Ziel) ..."
            Write-WolLog "RDP: Verbindung zu $($daten.Ziel) gestartet"
        }
        catch {
            $script:RdC.TxtStatus.Text = "Fehler bei $($daten.Ziel): $($_.Exception.Message)"
            Write-WolLog "RDP: $($daten.Ziel) konnte nicht verbunden werden: $($_.Exception.Message)"
        }
        $daten.Kennwort = $null
    })

    ### Fenstergröße geändert: Auflösung der Sitzung verzögert anpassen
    $wfh.Add_SizeChanged({
        param($sender, $e)
        $info = $sender.Tag.Tab.Tag
        if (-not $info.Gestartet) { return }
        if ($info.Verzoegerung) { $info.Verzoegerung.Stop() }
        $zeit = [System.Windows.Threading.DispatcherTimer]::new()
        $zeit.Interval = [TimeSpan]::FromMilliseconds(600)
        $zeit.Tag = $sender
        $zeit.Add_Tick({
            param($uhr, $ea)
            $uhr.Stop()
            try {
                $ocx = $uhr.Tag.Tag.Tab.Tag.Ax.Ocx
                if ([int]$ocx.Connected -eq 1) {
                    $pixel = Get-WolRdPixel -Host2 $uhr.Tag
                    $ocx.UpdateSessionDisplaySettings($pixel.Breite, $pixel.Hoehe, 0, 0, 0, 100, 100)
                }
            }
            catch { }
        })
        $info.Verzoegerung = $zeit
        $zeit.Start()
    })

    [void]$c.Bereich.Children.Add($wfh)
    [void]$c.Tabs.Items.Add($tab)
    $c.Tabs.SelectedItem = $tab
    Update-WolRdAnzeige
}

# Verbinden
## Zugangsdaten der markierten Geräte klären, bevor etwas geöffnet wird: fehlende Kennwörter der Gerätekonten und das Kennwort des angemeldeten Kontos werden freundlich abgefragt; $false bei Abbruch
function script:Resolve-WolRdZugang {
    param($Zeilen, $Besitzer)
    ### Geräte mit Konto in der Spalte: fehlendes Kennwort der Sitzung abfragen (einmal pro Konto)
    $mitKonto = @($Zeilen | Where-Object { $_.Konto })
    ### Ein Kennwort, das für dasselbe Konto schon bei einem anderen Gerät der Liste (oder für das angemeldete Konto) vorliegt, gilt auch hier
    foreach ($zeile in @($mitKonto | Where-Object { -not $_.Kennwort })) {
        $kontoName = ([string]$zeile.Konto).ToLower()
        $quelle = @($script:Zeilen | Where-Object { $_.Kennwort -and ([string]$_.Konto).ToLower() -eq $kontoName } | Select-Object -First 1)
        if ($quelle.Count -gt 0) { $zeile.Kennwort = $quelle[0].Kennwort }
        elseif ($script:RdAktuellKennwort -and $kontoName -eq ([string][NetCockpitZeile]::StandardKonto).ToLower()) { $zeile.Kennwort = $script:RdAktuellKennwort }
    }
    if ($mitKonto.Count -gt 0 -and -not (Resolve-WolKonten -Zeilen $mitKonto -Besitzer $Besitzer)) { return $false }
    ### Geräte ohne Konto: angemeldetes Windows-Konto, das Kennwort wird einmal pro Sitzung abgefragt
    $ohneKonto = @($Zeilen | Where-Object { -not $_.Konto })
    if ($ohneKonto.Count -gt 0 -and -not $script:RdAktuellKennwort) {
        $liste = @($ohneKonto | ForEach-Object { if ($_.Hostname) { ([string]$_.Hostname).Split('.')[0] } else { [string]$_.IP } })
        $geraete = if ($liste.Count -gt 6) { "$($liste.Count) Geräte" } else { $liste -join ', ' }
        $script:RdAktuellKennwort = Show-WolKennwort -Benutzer "$([NetCockpitZeile]::StandardKonto) (angemeldetes Konto, gilt für alle RDP-Verbindungen dieser Sitzung)" -Geraete $geraete -Besitzer $Besitzer
        if (-not $script:RdAktuellKennwort) { return $false }
    }
    return $true
}

## Tab zu einem Ziel suchen (Name ohne Beachtung der Groß- und Kleinschreibung)
function script:Get-WolRdTab {
    param([string]$Ziel)
    foreach ($tab in @($script:RdC.Tabs.Items)) {
        if (([string]$tab.Tag.Ziel) -ieq $Ziel) { return $tab }
    }
    return $null
}

## Markierte Geräte aus der Tabelle in je einem Tab verbinden: hat ein Gerät schon einen Tab mit bestehender oder laufender Verbindung, springt das Modul dorthin; ein getrennter Tab wird durch den neuen ersetzt
function script:Connect-WolRdMarkierte {
    $c = $script:RdC
    $markiert = @(Get-WolMarkierte)
    if ($markiert.Count -eq 0) {
        Show-WolMeldung "Es ist noch kein Gerät markiert.`r`nBitte in der Tabelle ein oder mehrere Geräte markieren und dann auf 'Markierte verbinden' klicken." 'Information'
        return
    }
    ### Geräte mit bestehender oder laufender Verbindung: zum vorhandenen Tab springen, nichts Neues öffnen
    $neu = [System.Collections.Generic.List[object]]::new()
    $vorhanden = $null
    $anzahlVorhanden = 0
    foreach ($zeile in $markiert) {
        $ziel = Get-WolZielName -Zeile $zeile
        $tab = $(if ($ziel) { Get-WolRdTab -Ziel $ziel } else { $null })
        if ($tab -and ((Get-WolRdZustand -Info $tab.Tag) -ne 0 -or -not $tab.Tag.Gestartet)) {
            if (-not $vorhanden) { $vorhanden = $tab }
            $anzahlVorhanden++
        }
        else { $neu.Add($zeile) }
    }
    if ($neu.Count -gt 0 -and -not (Resolve-WolRdZugang -Zeilen @($neu) -Besitzer $script:RdFenster)) { $c.TxtStatus.Text = 'Ohne Kennwort wurden keine Verbindungen gestartet.'; return }
    $aktuellesKonto = [string][NetCockpitZeile]::StandardKonto
    $gestartet = 0
    foreach ($zeile in $neu) {
        $ziel = Get-WolZielName -Zeile $zeile
        if (-not $ziel) { $c.TxtStatus.Text = 'Ein markiertes Gerät hat weder Hostname noch IP-Adresse.'; continue }
        ### getrennter Tab desselben Ziels: wird durch den neuen ersetzt
        $alt = Get-WolRdTab -Ziel $ziel
        if ($alt) { Close-WolRdTab -Tab $alt }
        if ($zeile.Konto) { Add-WolRdTab -Ziel $ziel -Benutzer ([string]$zeile.Konto) -Kennwort $zeile.Kennwort }
        else { Add-WolRdTab -Ziel $ziel -Benutzer $aktuellesKonto -Kennwort $script:RdAktuellKennwort }
        $gestartet++
    }
    ### Nur bestehende Verbindungen markiert: zum ersten davon wechseln
    if ($gestartet -eq 0 -and $vorhanden) { $c.Tabs.SelectedItem = $vorhanden }
    $text = "$gestartet Verbindung(en) gestartet."
    if ($anzahlVorhanden -gt 0) { $text += " $anzahlVorhanden schon verbunden (vorhandener Tab)." }
    $c.TxtStatus.Text = $text
}

## Aktiven Tab neu verbinden: die Verbindung wird getrennt und mit denselben Zugangsdaten in einem neuen Tab aufgebaut (der Benutzer bleibt auf dem Server angemeldet)
function script:Restart-WolRdAktiverTab {
    $c = $script:RdC
    $tab = $c.Tabs.SelectedItem
    if (-not $tab) { $c.TxtStatus.Text = 'Es ist kein Tab offen.'; return }
    $info = $tab.Tag
    $ziel = [string]$info.Ziel
    $benutzer = [string]$info.Benutzer
    $kennwort = $info.Kennwort
    Close-WolRdTab -Tab $tab
    Add-WolRdTab -Ziel $ziel -Benutzer $benutzer -Kennwort $kennwort
    $c.TxtStatus.Text = "Verbindung zu $ziel neu aufgebaut."
}

# Abmelden
## Benutzer des aktiven Tabs auf dem Zielgerät abmelden (nur Abmelden, kein Neustart und kein Herunterfahren): die RDP-Sitzung des Kontos wird über WinRM gesucht (quser) und mit logoff beendet
function script:Disconnect-WolRdAktiverTab {
    $c = $script:RdC
    $tab = $c.Tabs.SelectedItem
    if (-not $tab) { $c.TxtStatus.Text = 'Es ist kein Tab offen.'; return }
    $info = $tab.Tag
    $ziel = [string]$info.Ziel
    $benutzer = [string]$info.Benutzer
    $kurzName = $benutzer
    if ($kurzName -match '\\') { $kurzName = $kurzName.Split('\')[-1] }
    if ($kurzName -match '@') { $kurzName = $kurzName.Split('@')[0] }
    if (-not $kurzName) {
        Show-WolMeldung "Für diesen Tab ist kein Benutzer bekannt, deshalb kann das Modul die Sitzung nicht finden.`r`nBitte im RDP-Fenster selbst abmelden." 'Information'
        return
    }
    $antwort = [System.Windows.MessageBox]::Show("$kurzName auf $ziel abmelden?`r`n`r`nNicht gespeicherte Arbeit in der Sitzung geht verloren. Der Server wird nicht neu gestartet oder heruntergefahren.", 'NET-COCKPIT', 'YesNo', 'Question')
    if ($antwort -ne 'Yes') { return }
    $c.TxtStatus.Text = "Melde $kurzName auf $ziel ab ..."
    try {
        $parameter = @{ ComputerName = $ziel; ErrorAction = 'Stop'; SessionOption = (New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 30000) }
        if ($info.Kennwort -and $benutzer) { $parameter.Credential = [System.Management.Automation.PSCredential]::new($benutzer, [System.Security.SecureString]$info.Kennwort) }
        $ergebnis = Invoke-Command @parameter -ArgumentList $kurzName -ScriptBlock {
            param($Name)
            $treffer = @()
            foreach ($zeile in @(quser 2>$null)) {
                if ($zeile -match '^\s*>?(?<n>\S+)\s+(?<s>rdp-tcp#\d+)\s+(?<id>\d+)\s+') {
                    if ($Matches.n -ieq $Name) { $treffer += [int]$Matches.id }
                }
            }
            if ($treffer.Count -eq 0) { return 'KEINE' }
            if ($treffer.Count -gt 1) { return "MEHRERE:$($treffer -join ',')" }
            logoff $treffer[0]
            return "OK:$($treffer[0])"
        }
        $ergebnis = [string]($ergebnis | Select-Object -Last 1)
        if ($ergebnis -like 'OK:*') {
            $c.TxtStatus.Text = "$kurzName wurde auf $ziel abgemeldet."
            Write-WolLog "RDP: $kurzName auf $ziel abgemeldet (Sitzung $($ergebnis.Substring(3)))"
            ### Tab schließen, die Sitzung ist beendet
            Close-WolRdTab -Tab $tab
            $c.TxtStatus.Text = "$kurzName wurde auf $ziel abgemeldet, der Tab wurde geschlossen."
        }
        elseif ($ergebnis -eq 'KEINE') {
            $c.TxtStatus.Text = "Auf $ziel wurde keine aktive RDP-Sitzung von $kurzName gefunden."
        }
        else {
            $c.TxtStatus.Text = "Auf $ziel laufen mehrere RDP-Sitzungen von $kurzName ($($ergebnis.Substring(8)))."
            Show-WolMeldung "Auf $ziel laufen mehrere aktive RDP-Sitzungen von $kurzName.`r`nDamit nicht die falsche Sitzung beendet wird, melde dich bitte direkt im RDP-Fenster ab." 'Information'
        }
    }
    catch {
        $c.TxtStatus.Text = "Abmelden auf $ziel nicht möglich: $(Get-WolFehlerKurz -Text $_.Exception.Message)"
        Write-WolLog "RDP: Abmelden auf $ziel fehlgeschlagen: $($_.Exception.Message)" -NurDatei
    }
}

# Fenster
## Wird vom Menü Module > RDP aufgerufen: Fenster öffnen (oder in den Vordergrund holen) und die markierten Geräte verbinden
function script:Show-WolModulRDP {
    if ($script:RdFenster) {
        [void]$script:RdFenster.Activate()
        if (@(Get-WolMarkierte).Count -gt 0) { Connect-WolRdMarkierte }
        return
    }
    ### Zugangsdaten klären, bevor das Fenster geöffnet wird; bei Abbruch öffnet sich nichts
    $markiertVorab = @(Get-WolMarkierte)
    if ($markiertVorab.Count -gt 0 -and -not (Resolve-WolRdZugang -Zeilen $markiertVorab -Besitzer $script:Fenster)) { return }
    $steuerelement = Get-WolRdSteuerelement
    if (-not $steuerelement) {
        Show-WolMeldung "Auf diesem Rechner ist kein RDP-Steuerelement (mstscax.dll) registriert.`r`nDas Modul RDP braucht das Remotedesktop-Steuerelement von Windows." 'Warning'
        return
    }
    $script:RdClsid = $steuerelement.Clsid

    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RDP-MODUL" Width="1200" Height="780" MinWidth="800" MinHeight="500" WindowStartupLocation="CenterScreen">
  <Grid Margin="8">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,6">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="BtnVerbinden" Content="Markierte verbinden" Padding="14,4" FontWeight="Bold" Margin="0,0,8,0"/>
        <Button x:Name="BtnAbmelden" Content="Abmelden" Padding="14,4" Margin="0,0,8,0"/>
        <Button x:Name="BtnNeuVerbinden" Content="Neu verbinden" Padding="14,4" Margin="0,0,8,0"/>
        <TextBlock Text="Die in der Tabelle markierten Geräte öffnen je einen Tab. Konto und Kennwort kommen aus der Spalte Konto." Foreground="DimGray" VerticalAlignment="Center"/>
      </StackPanel>
      <Expander Header="Hinweis zur Anmeldung (angemeldetes Konto, GPO)" Margin="0,6,0,0">
        <TextBox x:Name="TxtHinweis" IsReadOnly="True" TextWrapping="Wrap" Margin="0,4,0,0" Padding="6" Background="#FFF7F7F7"/>
      </Expander>
    </StackPanel>
    <TabControl x:Name="Tabs" Grid.Row="1"/>
    <Grid x:Name="Bereich" Grid.Row="2" Background="#FFDDDDDD">
      <TextBlock x:Name="TxtLeer" Text="Keine Verbindung. Geräte in der Tabelle markieren und auf 'Markierte verbinden' klicken." Foreground="DimGray" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Grid>
    <TextBlock x:Name="TxtStatus" Grid.Row="3" TextWrapping="Wrap" Foreground="DimGray" Margin="0,6,0,0"/>
  </Grid>
</Window>
'@
    $script:RdC = @{}
    foreach ($name in 'BtnVerbinden', 'BtnAbmelden', 'BtnNeuVerbinden', 'TxtHinweis', 'Tabs', 'Bereich', 'TxtLeer', 'TxtStatus') { $script:RdC[$name] = $f.FindName($name) }
    $script:RdC.BtnVerbinden.Add_Click({ Connect-WolRdMarkierte })
    $script:RdC.BtnAbmelden.Add_Click({ Disconnect-WolRdAktiverTab })
    $script:RdC.BtnNeuVerbinden.Add_Click({ Restart-WolRdAktiverTab })
    $script:RdC.TxtHinweis.Text = (@(
        'Geräte ohne Eintrag in der Spalte "Konto" verbinden mit dem angemeldeten Windows-Konto. Windows gibt dessen Kennwort nicht heraus, deshalb fragt das Modul es einmal pro Sitzung ab und nutzt es für alle weiteren Verbindungen, bis das NET-COCKPIT geschlossen wird (nur im Arbeitsspeicher, nichts wird gespeichert). Bei Geräten mit eigenem Konto in der Spalte "Konto" kommt keine Abfrage.'
        ''
        'Ohne Abfrage geht es per GPO (Delegierung von Standardanmeldeinformationen):'
        '1. Gruppenrichtlinie (oder lokal gpedit.msc) öffnen: Computerkonfiguration > Administrative Vorlagen > System > Delegierung von Anmeldeinformationen.'
        '2. "Delegierung von Standardanmeldeinformationen zulassen" aktivieren, auf "Anzeigen" klicken und TERMSRV/* (alle Server) oder TERMSRV/Servername eintragen.'
        '3. Auf dem Rechner mit dem NET-COCKPIT gpupdate /force ausführen und sich neu anmelden.'
        ''
        'Die Verbindung muss über den Servernamen (nicht die IP-Adresse) erfolgen, damit die Delegierung greift.'
    ) -join "`r`n")
    $script:RdC.Tabs.Add_SelectionChanged({ Update-WolRdAnzeige })

    ### Status der Tabs (alle 2 Sekunden im Tab-Kopf: ● verbunden, ◌ verbindet, ○ getrennt)
    $script:RdZeitgeber = [System.Windows.Threading.DispatcherTimer]::new()
    $script:RdZeitgeber.Interval = [TimeSpan]::FromSeconds(2)
    $script:RdZeitgeber.Add_Tick({
        foreach ($tab in @($script:RdC.Tabs.Items)) {
            $info = $tab.Tag
            if (-not $info.Gestartet) { continue }
            $zeichen = switch (Get-WolRdZustand -Info $info) { 1 { [string][char]0x25CF } 2 { [string][char]0x25CC } default { [string][char]0x25CB } }
            $info.Text.Text = "$zeichen $($info.Ziel)"
        }
    })

    ### Schließen: bei bestehenden Verbindungen nachfragen, dann alle trennen
    $f.Add_Closing({
        param($sender, $e)
        $aktive = Get-WolRdAktive
        if ($aktive -gt 0 -and -not $script:RdBeendenOhneFrage) {
            $antwort = [System.Windows.MessageBox]::Show("Es bestehen noch $aktive Verbindung(en).`r`nFenster schließen und alle Verbindungen trennen?", 'NET-COCKPIT', 'YesNo', 'Question')
            if ($antwort -ne 'Yes') { $e.Cancel = $true; return }
        }
        $script:RdZeitgeber.Stop()
        foreach ($tab in @($script:RdC.Tabs.Items)) { Stop-WolRdVerbindung -Info $tab.Tag }
    })
    $f.Add_Closed({ $script:RdFenster = $null; $script:RdC = @{} })

    $script:RdFenster = $f
    $script:RdZeitgeber.Start()
    Update-WolRdAnzeige
    $script:RdC.TxtStatus.Text = "RDP-Steuerelement: $($steuerelement.Name)"
    $f.Show()
    if (@(Get-WolMarkierte).Count -gt 0) { Connect-WolRdMarkierte }
}

# Info
## Reiter für die Info des NET-COCKPIT (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['RDP'] = {
    @{ Titel = 'RDP'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Öffnet **Remotedesktop-Verbindungen** in einem eigenen Fenster (kein Vollbild) mit **einem Tab je Verbindung**. Das Fenster **RDP-MODUL** öffnet sich über **Module > RDP**, ist eigenständig (eigenes Taskleistensymbol) und bleibt nicht vor dem Cockpit liegen.' }
        @{ T = 'h'; X = 'Ablauf' }
        @{ T = 'i'; X = '**Geräte markieren, Module > RDP** (oder im offenen Fenster **Markierte verbinden**): Jedes markierte Gerät bekommt einen Tab. Ziel ist der Hostname, sonst die IP-Adresse.' }
        @{ T = 'i'; X = '**Konto:** Konto und Kennwort kommen aus der Spalte "Konto" (Optionen > Konto für markierte Geräte). Das Modul fragt keine Kennwörter ab: Fehlt bei einem Gerät mit Konto das Kennwort (zum Beispiel nach einem Neustart), meldet das Modul die Geräte, nichts startet. Ohne Eintrag in der Spalte gilt das angemeldete Windows-Konto: Windows gibt dessen Kennwort nicht heraus, deshalb fragt das Modul es einmal pro Sitzung ab (nur im Arbeitsspeicher).' }
        @{ T = 'i'; X = '**Tab-Kopf:** ● verbunden, ◌ verbindet, ○ getrennt. Das ✕ im Tab trennt die Verbindung und schließt den Tab.' }
        @{ T = 'i'; X = '**Abmelden:** meldet nur den Benutzer des gerade angezeigten Tabs auf dem Server ab, es gibt keinen Neustart und kein Herunterfahren. Das Modul sucht dafür die RDP-Sitzung des Kontos auf dem Server (WinRM, quser) und beendet sie mit logoff, vorher kommt eine Rückfrage, danach schließt sich der Tab. Gibt es mehrere aktive RDP-Sitzungen desselben Kontos, passiert nichts, dann bitte im RDP-Fenster selbst abmelden. **Tab schließen** oder **Fenster schließen** trennt dagegen nur die Verbindung, die Sitzung bleibt auf dem Server bestehen.' }
        @{ T = 'i'; X = '**Neu verbinden:** baut die Verbindung des gerade angezeigten Tabs neu auf, mit denselben Zugangsdaten. Der Benutzer bleibt auf dem Server angemeldet, nur die Verbindung wird getrennt und neu hergestellt.' }
        @{ T = 'i'; X = '**Gerät schon verbunden:** Markierst du ein Gerät, das schon einen Tab mit bestehender oder laufender Verbindung hat, springt das Modul zu diesem Tab, statt einen neuen zu öffnen. Ein getrennter Tab (○) wird durch den neuen ersetzt.' }
        @{ T = 'i'; X = '**Auflösung:** folgt der Fenstergröße, auch beim Vergrößern des Fensters.' }
        @{ T = 'i'; X = '**Zwischenablage:** wird umgeleitet, sonst nichts (keine Laufwerke, Drucker oder Smartcards).' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Voraussetzung:** Remotedesktop auf dem Ziel aktiv (TCP 3389) und das Konto darf sich per Remotedesktop anmelden. Das Steuerelement mstscax.dll ist Bestandteil von Windows.' }
        @{ T = 'i'; X = '**Ohne Abfrage per GPO:** Computerkonfiguration > Administrative Vorlagen > System > Delegierung von Anmeldeinformationen > **Delegierung von Standardanmeldeinformationen zulassen**, TERMSRV/* eintragen, gpupdate /force und neu anmelden. Die Schritte stehen auch im Fenster unter **Hinweis zur Anmeldung**.' }
        @{ T = 'i'; X = '**Kennwort:** geht nur im Arbeitsspeicher an das RDP-Steuerelement und wird nicht gespeichert.' }
        @{ T = 'i'; X = '**Fenster schließen** trennt alle Verbindungen (mit Rückfrage, solange Verbindungen bestehen). Beendest du das NET-COCKPIT, kommt dieselbe Rückfrage und das RDP-Fenster schließt sich mit.' }
        @{ T = 'i'; X = '**Log:** Start und Ende einer Verbindung stehen im Log des NET-COCKPIT.' }
        @{ T = 'w'; X = 'Aus dem Testskript übernommen (Verbindung, Tabs, Zwischenablage, Auflösung getestet). Neu und noch nicht getestet: Abmelden, Aufruf über das Menü, Kennwortabfrage für das angemeldete Konto, Konto aus der Spalte, mehrere Tabs gleichzeitig.' }
    ) }
}
