# NET-COCKPIT-Modul-FOLDERDETECTIVE.ps1
<#
.SYNOPSIS
    Modul Folder-Detective für das NET-COCKPIT (Menü Module > Folder-Detective)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und öffnet ein Fenster, das Ordner- und Dateigrößen als Baum zeigt, während der Scan noch läuft.
    - "Pfad wählen": Laufwerk oder Ordner auf dem Rechner mit dem NET-COCKPIT
    - "Remote Scan": Laufwerk oder Ordner auf einem anderen Computer per WinRM (Endpunkt PowerShell.7 auf dem Ziel). Ist im NET-COCKPIT genau ein Gerät markiert, übernimmt das Fenster Gerätename und, falls in der Spalte Konto eingetragen, auch dieses Konto; sonst Computername und Konto von Hand
    - Der Baum füllt sich während des Scans: Ordner erscheinen sofort, die Größen wachsen live mit, die Sortierung wird alle zwei Sekunden neu angewendet (offene Ordner bleiben offen)
    - Spalten: Größe, Belegt (Platz auf dem Datenträger), Dateien, Ordner, % Anteil, Letzte Änderung, Hinweis; Sortierung per Klick auf die Spaltenüberschrift
    - Nicht lesbare Ordner werden mit "Zugriff verweigert" markiert, der Scan läuft weiter; der Knopf "Nicht lesbare anzeigen" öffnet die Liste
    - Rechtsklick auf eine Zeile: "Dateipfad öffnen" zeigt Ordner bzw. Datei im Explorer (bei Remote-Scans als Adminfreigabe \\Computer\C$\...); es wird nie eine Datei gestartet
    - Verknüpfungen (Junctions/Symlinks) werden nicht verfolgt
    Das Modul speichert nichts; Start, Ergebnis und Fehler der Scans stehen im Log des NET-COCKPIT.
#>

# Einstellungen
## Vorgaben und Zustand des Moduls (bleibt bis zum Beenden des NET-COCKPIT erhalten)
$script:FdTypVersion = '1.9'
$script:FdKultur = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
$script:FdMaxKinder = 5000
$script:FdAufbauIntervall = 2
$script:FdSortSpalte = 'Groesse'
$script:FdSortAufsteigend = $false
$script:FdProzentbasis = 'Groesse'
$script:FdAnmeldedaten = $null
$script:FdAktuellesKonto = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME
$script:FdModell = $null
$script:FdOffene = [System.Collections.Generic.HashSet[int]]::new()
$script:FdScanModus = ''
$script:FdScanZiel = ''
$script:FdScanComputer = ''
$script:FdRemoteComputer = ''
$script:FdScanStart = Get-Date
$script:FdLetzterAufbau = Get-Date
$script:FdAbbruchAngefordert = $false
$script:FdScrollViewer = $null
$script:FdJob = $null
$script:FdFenster = $null
$script:FdVorgabeZeile = $null
$script:FdCockpitHaken = $false

# Scan-Kern
## C#-Code (Scanner, Datenmodell, Anzeigezeile)
$script:FdCSharp = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class FdVersion
{
    public const string Stand = "1.9";
}

public class FdKnoten
{
    public int Id { get; set; }
    public int ParentId { get; set; }
    public string Name { get; set; }
    public bool IstOrdner { get; set; }
    public long Groesse { get; set; }
    public long Belegt { get; set; }
    public long Dateien { get; set; }
    public long Ordner { get; set; }
    public DateTime Geaendert { get; set; }
    public string Fehler { get; set; }
    internal FdKnoten ElternKnoten;
}

public static class FdScan
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern uint GetCompressedFileSizeW(string dateiname, out uint hoch);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool GetDiskFreeSpaceW(string wurzel, out uint sektorenProCluster, out uint bytesProSektor, out uint freieCluster, out uint gesamtCluster);

    public static volatile bool Abbruch;
    public static volatile bool Pause;
    public static volatile bool Fertig;
    public static volatile bool LetzteFertig;
    public static long ZaehlerDateien;
    public static long ZaehlerFehler;
    public static string Meldung = "";

    static int naechsteId;
    static long clusterGroesse = 4096;
    static readonly object sperre = new object();
    static readonly HashSet<FdKnoten> geaendert = new HashSet<FdKnoten>();

    public static void Starte(string wurzel)
    {
        Abbruch = false;
        Pause = false;
        Fertig = false;
        LetzteFertig = false;
        ZaehlerDateien = 0;
        ZaehlerFehler = 0;
        Meldung = "";
        naechsteId = 0;
        lock (sperre) { geaendert.Clear(); }
        var t = new Thread(() => Arbeit(wurzel), 16 * 1024 * 1024);
        t.IsBackground = true;
        t.Start();
    }

    static void Arbeit(string wurzel)
    {
        try
        {
            string voll = wurzel;
            if (voll.Length == 2 && voll[1] == ':') { voll = voll + "\\"; }
            voll = Path.GetFullPath(voll);
            try
            {
                uint a, b, c, d;
                if (GetDiskFreeSpaceW(Path.GetPathRoot(voll), out a, out b, out c, out d) && (long)a * b > 0)
                {
                    clusterGroesse = (long)a * b;
                }
            }
            catch { }
            Ordner(new DirectoryInfo(voll), null, true);
        }
        catch (Exception ex)
        {
            Meldung = ex.Message;
        }
        finally
        {
            Fertig = true;
        }
    }

    static string Lang(string p)
    {
        if (p.Length < 240 || p.StartsWith(@"\\?\")) { return p; }
        if (p.StartsWith(@"\\")) { return @"\\?\UNC\" + p.Substring(2); }
        return @"\\?\" + p;
    }

    static long Belegt(string pfad, long logisch)
    {
        uint hoch;
        uint tief = GetCompressedFileSizeW(Lang(pfad), out hoch);
        long wert = logisch;
        if (!(tief == 0xFFFFFFFF && Marshal.GetLastWin32Error() != 0))
        {
            wert = ((long)hoch << 32) | tief;
        }
        if (wert <= 0) { return 0; }
        return ((wert + clusterGroesse - 1) / clusterGroesse) * clusterGroesse;
    }

    static void Markiere(FdKnoten k)
    {
        lock (sperre) { geaendert.Add(k); }
    }

    static void Neu(FdKnoten k, FdKnoten eltern, long groesse, long belegt, long dateien, long ordner)
    {
        lock (sperre)
        {
            geaendert.Add(k);
            for (var p = eltern; p != null; p = p.ElternKnoten)
            {
                p.Groesse += groesse;
                p.Belegt += belegt;
                p.Dateien += dateien;
                p.Ordner += ordner;
                geaendert.Add(p);
            }
        }
    }

    static void Ordner(DirectoryInfo di, FdKnoten eltern, bool istWurzel)
    {
        var k = new FdKnoten();
        k.Id = ++naechsteId;
        k.ParentId = eltern == null ? 0 : eltern.Id;
        k.ElternKnoten = eltern;
        k.Name = istWurzel ? di.FullName : di.Name;
        k.IstOrdner = true;
        try { k.Geaendert = di.LastWriteTime; } catch { }
        Neu(k, eltern, 0, 0, 0, 1);

        var opt = new EnumerationOptions();
        opt.IgnoreInaccessible = false;
        opt.AttributesToSkip = 0;
        opt.RecurseSubdirectories = false;
        opt.ReturnSpecialDirectories = false;

        try
        {
            foreach (var e in di.EnumerateFileSystemInfos("*", opt))
            {
                while (Pause && !Abbruch) { Thread.Sleep(100); }
                if (Abbruch) { break; }
                try
                {
                    Eintrag(e, k);
                }
                catch (Exception ex)
                {
                    ZaehlerFehler++;
                    if (k.Fehler == null) { k.Fehler = ex.Message; Markiere(k); }
                }
            }
        }
        catch (UnauthorizedAccessException)
        {
            k.Fehler = "Zugriff verweigert";
            ZaehlerFehler++;
            Markiere(k);
        }
        catch (Exception ex)
        {
            k.Fehler = ex.Message;
            ZaehlerFehler++;
            Markiere(k);
        }
    }

    static void Eintrag(FileSystemInfo e, FdKnoten eltern)
    {
        bool istOrdner = (e.Attributes & FileAttributes.Directory) != 0;
        bool istLink = (e.Attributes & FileAttributes.ReparsePoint) != 0;

        if (istOrdner && !istLink)
        {
            Ordner((DirectoryInfo)e, eltern, false);
            return;
        }

        var k = new FdKnoten();
        k.Id = ++naechsteId;
        k.ParentId = eltern.Id;
        k.ElternKnoten = eltern;
        k.Name = e.Name;
        k.IstOrdner = istOrdner;
        try { k.Geaendert = e.LastWriteTime; } catch { }

        if (istOrdner)
        {
            k.Name = e.Name + " (Verknüpfung)";
            Neu(k, eltern, 0, 0, 0, 1);
            return;
        }

        var f = (FileInfo)e;
        long gr = f.Length;
        long be = 0;
        int attr = (int)f.Attributes;
        bool platzhalter = (attr & (0x1000 | 0x40000 | 0x400000)) != 0;
        if (!platzhalter && gr > 0) { be = Belegt(f.FullName, gr); }
        k.Groesse = gr;
        k.Belegt = be;
        k.Dateien = 1;
        Neu(k, eltern, gr, be, 1, 0);
        ZaehlerDateien++;
    }

    static string Sauber(string s)
    {
        if (s == null) { return ""; }
        return s.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
    }

    public static string Abholen()
    {
        bool fertig = Fertig;
        FdKnoten[] liste;
        lock (sperre)
        {
            liste = new FdKnoten[geaendert.Count];
            geaendert.CopyTo(liste);
            geaendert.Clear();
        }
        LetzteFertig = fertig;

        var inv = CultureInfo.InvariantCulture;
        var sb = new StringBuilder(liste.Length * 90 + 64);
        sb.Append("#Z\t").Append(ZaehlerDateien.ToString(inv)).Append('\t')
          .Append(ZaehlerFehler.ToString(inv)).Append('\t')
          .Append(fertig ? "1" : "0").Append('\t')
          .Append(Sauber(Meldung)).Append('\n');
        foreach (var k in liste)
        {
            sb.Append(k.Id.ToString(inv)).Append('\t')
              .Append(k.ParentId.ToString(inv)).Append('\t')
              .Append(k.IstOrdner ? "1" : "0").Append('\t')
              .Append(k.Groesse.ToString(inv)).Append('\t')
              .Append(k.Belegt.ToString(inv)).Append('\t')
              .Append(k.Dateien.ToString(inv)).Append('\t')
              .Append(k.Ordner.ToString(inv)).Append('\t')
              .Append(k.Geaendert.Ticks.ToString(inv)).Append('\t')
              .Append(Sauber(k.Fehler)).Append('\t')
              .Append(Sauber(k.Name)).Append('\n');
        }
        return sb.ToString();
    }
}

public class FdModell
{
    readonly Dictionary<int, FdKnoten> knoten = new Dictionary<int, FdKnoten>();
    readonly Dictionary<int, List<int>> kinder = new Dictionary<int, List<int>>();

    public int WurzelId { get; private set; }
    public long ZaehlerDateien { get; private set; }
    public long ZaehlerFehler { get; private set; }
    public bool Fertig { get; private set; }
    public string Meldung { get; private set; }
    public int FehlerAnzahl { get; private set; }

    public FdModell()
    {
        Meldung = "";
    }

    public void Uebernehmen(string stapel)
    {
        if (string.IsNullOrEmpty(stapel)) { return; }
        var inv = CultureInfo.InvariantCulture;
        foreach (var zeile in stapel.Split('\n'))
        {
            if (zeile.Length == 0) { continue; }
            var f = zeile.Split('\t');
            if (f[0] == "#Z")
            {
                ZaehlerDateien = long.Parse(f[1], inv);
                ZaehlerFehler = long.Parse(f[2], inv);
                Fertig = f[3] == "1";
                Meldung = f.Length > 4 ? f[4] : "";
                continue;
            }
            if (f.Length < 10) { continue; }

            int id = int.Parse(f[0], inv);
            int eltern = int.Parse(f[1], inv);
            FdKnoten k;
            if (!knoten.TryGetValue(id, out k))
            {
                k = new FdKnoten();
                k.Id = id;
                k.ParentId = eltern;
                k.IstOrdner = f[2] == "1";
                knoten[id] = k;
                if (eltern == 0)
                {
                    WurzelId = id;
                }
                else
                {
                    List<int> l;
                    if (!kinder.TryGetValue(eltern, out l))
                    {
                        l = new List<int>();
                        kinder[eltern] = l;
                    }
                    l.Add(id);
                }
            }
            k.Groesse = long.Parse(f[3], inv);
            k.Belegt = long.Parse(f[4], inv);
            k.Dateien = long.Parse(f[5], inv);
            k.Ordner = long.Parse(f[6], inv);
            long ticks = long.Parse(f[7], inv);
            k.Geaendert = ticks > 0 ? new DateTime(ticks) : DateTime.MinValue;
            string neuerFehler = f[8].Length == 0 ? null : f[8];
            if (k.Fehler == null && neuerFehler != null) { FehlerAnzahl++; }
            else if (k.Fehler != null && neuerFehler == null) { FehlerAnzahl--; }
            k.Fehler = neuerFehler;
            k.Name = f[9];
        }
    }

    public FdKnoten Hole(int id)
    {
        FdKnoten k;
        return knoten.TryGetValue(id, out k) ? k : null;
    }

    public bool HatKinder(int id)
    {
        return kinder.ContainsKey(id);
    }

    public string Pfad(int id)
    {
        var teile = new List<string>();
        int aktuell = id;
        FdKnoten k;
        while (aktuell != 0 && knoten.TryGetValue(aktuell, out k))
        {
            teile.Add(k.Name);
            aktuell = k.ParentId;
        }
        teile.Reverse();
        if (teile.Count == 0) { return ""; }
        string pfad = teile[0];
        for (int i = 1; i < teile.Count; i++)
        {
            pfad = pfad.EndsWith("\\") ? pfad + teile[i] : pfad + "\\" + teile[i];
        }
        return pfad;
    }

    static int NamenVergleich(FdKnoten a, FdKnoten b)
    {
        return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
    }

    public FdKnoten[] Sortiert(int id, string schluessel, bool aufsteigend)
    {
        List<int> l;
        if (!kinder.TryGetValue(id, out l)) { return new FdKnoten[0]; }
        var arr = new FdKnoten[l.Count];
        for (int i = 0; i < arr.Length; i++) { arr[i] = knoten[l[i]]; }

        int modus;
        switch (schluessel)
        {
            case "Groesse": modus = 1; break;
            case "Belegt": modus = 2; break;
            case "Dateien": modus = 3; break;
            case "Ordner": modus = 4; break;
            case "Geaendert": modus = 5; break;
            default: modus = 0; break;
        }

        Comparison<FdKnoten> vergleich = (a, b) =>
        {
            int c;
            switch (modus)
            {
                case 1: c = a.Groesse.CompareTo(b.Groesse); break;
                case 2: c = a.Belegt.CompareTo(b.Belegt); break;
                case 3: c = a.Dateien.CompareTo(b.Dateien); break;
                case 4: c = a.Ordner.CompareTo(b.Ordner); break;
                case 5: c = a.Geaendert.CompareTo(b.Geaendert); break;
                default: c = NamenVergleich(a, b); break;
            }
            if (!aufsteigend) { c = -c; }
            return c != 0 ? c : NamenVergleich(a, b);
        };
        Array.Sort(arr, vergleich);
        return arr;
    }

    public FdFehlerZeile[] FehlerListe()
    {
        var liste = new List<FdFehlerZeile>();
        foreach (var k in knoten.Values)
        {
            if (k.Fehler == null) { continue; }
            var z = new FdFehlerZeile();
            z.Pfad = Pfad(k.Id);
            z.Meldung = k.Fehler;
            liste.Add(z);
        }
        liste.Sort((a, b) => string.Compare(a.Pfad, b.Pfad, StringComparison.CurrentCultureIgnoreCase));
        return liste.ToArray();
    }

    public FdKnoten[] Fehlerknoten()
    {
        var liste = new List<FdKnoten>();
        foreach (var k in knoten.Values)
        {
            if (k.Fehler != null) { liste.Add(k); }
        }
        liste.Sort((a, b) => a.Id.CompareTo(b.Id));
        return liste.ToArray();
    }
}

public class FdFehlerZeile
{
    public string Pfad { get; set; }
    public string Meldung { get; set; }
}

public class FdZeile
{
    public int Id { get; set; }
    public int ElternId { get; set; }
    public int Ebene { get; set; }
    public double Einzug { get; set; }
    public bool IstOrdner { get; set; }
    public bool HatKinder { get; set; }
    public bool Offen { get; set; }
    public string Name { get; set; }
    public string GroesseText { get; set; }
    public string BelegtText { get; set; }
    public long Dateien { get; set; }
    public long Ordner { get; set; }
    public double Prozent { get; set; }
    public string ProzentText { get; set; }
    public string Geaendert { get; set; }
    public string Hinweis { get; set; }
    public string Symbol
    {
        get { return !HatKinder ? "" : (Offen ? "\u2212" : "+"); }
    }
}
'@

## Typen laden oder einen älteren Stand in diesem Prozess erkennen (geladene Typen lassen sich nicht entladen)
$script:FdTypOk = $true
if ('FdScan' -as [type]) {
    $geladen = if ('FdVersion' -as [type]) { [FdVersion]::Stand } else { 'alt' }
    $script:FdTypOk = ($geladen -eq $script:FdTypVersion)
}
else {
    Add-Type -TypeDefinition $script:FdCSharp
}

# Hilfsfunktionen
## Groessenformat
function script:Format-WolFdGroesse {
    param([long]$Bytes)
    if ($Bytes -lt 1024) { return '{0} Bytes' -f $Bytes }
    $einheiten = 'KB', 'MB', 'GB', 'TB', 'PB'
    $wert = [double]$Bytes
    $index = -1
    do {
        $wert = $wert / 1024
        $index++
    } while ($wert -ge 1024 -and $index -lt 4)
    '{0} {1}' -f $wert.ToString('N1', $script:FdKultur), $einheiten[$index]
}

## Anzeigezeile erzeugen
function script:New-WolFdZeile {
    param($Knoten, [int]$Ebene)
    $zeile = [FdZeile]::new()
    $zeile.Id = $Knoten.Id
    $zeile.ElternId = $Knoten.ParentId
    $zeile.Ebene = $Ebene
    $zeile.Einzug = $Ebene * 16
    $zeile.IstOrdner = $Knoten.IstOrdner
    $zeile.HatKinder = $script:FdModell.HatKinder($Knoten.Id)
    $zeile.Name = $Knoten.Name
    $zeile.GroesseText = Format-WolFdGroesse $Knoten.Groesse
    $zeile.BelegtText = Format-WolFdGroesse $Knoten.Belegt
    $zeile.Dateien = $Knoten.Dateien
    $zeile.Ordner = $Knoten.Ordner

    $nachGroesse = $script:FdProzentbasis -eq 'Groesse'
    $eltern = $script:FdModell.Hole($Knoten.ParentId)
    $eigen = if ($nachGroesse) { [double]$Knoten.Groesse } else { [double]$Knoten.Belegt }
    $nenner = if ($eltern) { if ($nachGroesse) { [double]$eltern.Groesse } else { [double]$eltern.Belegt } } else { $eigen }
    $zeile.Prozent = if ($nenner -gt 0) { $eigen / $nenner * 100 } else { 0 }
    $zeile.ProzentText = $zeile.Prozent.ToString('N1', $script:FdKultur) + ' %'

    $datum = $Knoten.Geaendert
    $zeile.Geaendert = if ($datum.Year -gt 1601) { $datum.ToString('dd.MM.yyyy HH:mm') } else { '' }
    $zeile.Hinweis = [string]$Knoten.Fehler
    $zeile
}

## Kinder in eine Liste einfuegen
function script:Add-WolFdKinder {
    param([int]$ElternId, [int]$Ebene, $Liste)
    $alle = $script:FdModell.Sortiert($ElternId, $script:FdSortSpalte, $script:FdSortAufsteigend)
    $anzahl = [Math]::Min($alle.Count, $script:FdMaxKinder)
    for ($i = 0; $i -lt $anzahl; $i++) {
        Add-WolFdSicht -Knoten $alle[$i] -Ebene $Ebene -Liste $Liste
    }
    if ($alle.Count -gt $anzahl) {
        $hinweis = [FdZeile]::new()
        $hinweis.Id = -1
        $hinweis.Ebene = $Ebene
        $hinweis.Einzug = $Ebene * 16 + 16
        $hinweis.Name = '… {0} weitere Einträge nicht angezeigt' -f ($alle.Count - $anzahl)
        $Liste.Add($hinweis)
    }
}

## Knoten samt geoeffneten Kindern einfuegen
function script:Add-WolFdSicht {
    param($Knoten, [int]$Ebene, $Liste)
    $zeile = New-WolFdZeile -Knoten $Knoten -Ebene $Ebene
    $zeile.Offen = $zeile.HatKinder -and $script:FdOffene.Contains($zeile.Id)
    $Liste.Add($zeile)
    if ($zeile.Offen) {
        Add-WolFdKinder -ElternId $zeile.Id -Ebene ($Ebene + 1) -Liste $Liste
    }
}

## Sortierpfeil in der Spaltenueberschrift setzen
function script:Set-WolFdSortPfeil {
    foreach ($spalte in $script:FdUi.Grid.Columns) {
        if ($spalte.SortMemberPath -eq $script:FdSortSpalte) {
            $spalte.SortDirection = if ($script:FdSortAufsteigend) {
                [System.ComponentModel.ListSortDirection]::Ascending
            }
            else {
                [System.ComponentModel.ListSortDirection]::Descending
            }
        }
        else {
            $spalte.SortDirection = $null
        }
    }
}

## ScrollViewer des Gitters finden
function script:Get-WolFdScrollViewer {
    param($Element)
    if ($Element -is [System.Windows.Controls.ScrollViewer]) { return $Element }
    $anzahl = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
    for ($i = 0; $i -lt $anzahl; $i++) {
        $kind = [System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i)
        $treffer = Get-WolFdScrollViewer -Element $kind
        if ($treffer) { return $treffer }
    }
}

## Ansicht neu aufbauen (Auswahl, Scroll-Position und offene Ordner bleiben erhalten)
function script:Update-WolFdAnsicht {
    if (-not $script:FdModell -or -not $script:FdModell.WurzelId) { return }

    $auswahl = $script:FdUi.Grid.SelectedItem
    $auswahlId = if ($auswahl) { $auswahl.Id } else { 0 }
    if (-not $script:FdScrollViewer -and $script:FdZeilen.Count -gt 0) {
        $script:FdScrollViewer = Get-WolFdScrollViewer -Element $script:FdUi.Grid
    }
    $offset = if ($script:FdScrollViewer) { $script:FdScrollViewer.VerticalOffset } else { 0 }

    $liste = [System.Collections.Generic.List[FdZeile]]::new()
    Add-WolFdSicht -Knoten $script:FdModell.Hole($script:FdModell.WurzelId) -Ebene 0 -Liste $liste
    $script:FdZeilen = [System.Collections.ObjectModel.ObservableCollection[FdZeile]]::new($liste)
    $script:FdUi.Grid.ItemsSource = $script:FdZeilen
    Set-WolFdSortPfeil

    if ($auswahlId -gt 0) {
        for ($i = 0; $i -lt $script:FdZeilen.Count; $i++) {
            if ($script:FdZeilen[$i].Id -eq $auswahlId) { $script:FdUi.Grid.SelectedIndex = $i; break }
        }
    }
    if ($offset -gt 0) {
        $script:FdUi.Grid.UpdateLayout()
        if (-not $script:FdScrollViewer) { $script:FdScrollViewer = Get-WolFdScrollViewer -Element $script:FdUi.Grid }
        if ($script:FdScrollViewer) { $script:FdScrollViewer.ScrollToVerticalOffset($offset) }
    }
}

## Ordner auf- und zuklappen
function script:Switch-WolFdKnoten {
    param([int]$Index, [bool]$Oeffnen)
    if ($Index -lt 0 -or $Index -ge $script:FdZeilen.Count) { return }
    $zeile = $script:FdZeilen[$Index]
    if ($zeile.Id -lt 1 -or -not $zeile.HatKinder) { return }
    if ($Oeffnen -eq $zeile.Offen) { return }

    if ($Oeffnen) {
        [void]$script:FdOffene.Add($zeile.Id)
        $zeile.Offen = $true
        $neu = [System.Collections.Generic.List[FdZeile]]::new()
        Add-WolFdKinder -ElternId $zeile.Id -Ebene ($zeile.Ebene + 1) -Liste $neu
        $position = $Index + 1
        foreach ($eintrag in $neu) {
            $script:FdZeilen.Insert($position, $eintrag)
            $position++
        }
    }
    else {
        [void]$script:FdOffene.Remove($zeile.Id)
        $zeile.Offen = $false
        while (($Index + 1) -lt $script:FdZeilen.Count -and $script:FdZeilen[$Index + 1].Ebene -gt $zeile.Ebene) {
            $script:FdZeilen.RemoveAt($Index + 1)
        }
    }
    $script:FdZeilen[$Index] = $zeile
    $script:FdUi.Grid.SelectedIndex = $Index
}

## Zeile unter dem Mauszeiger finden
function script:Get-WolFdGitterZeile {
    param($Quelle)
    while ($Quelle -and $Quelle -isnot [System.Windows.Controls.DataGridRow]) {
        if ($Quelle -is [System.Windows.Media.Visual]) {
            $Quelle = [System.Windows.Media.VisualTreeHelper]::GetParent($Quelle)
        }
        else {
            $Quelle = [System.Windows.LogicalTreeHelper]::GetParent($Quelle)
        }
    }
    $Quelle
}

## Pruefen, ob auf das Plus-/Minus-Kaestchen geklickt wurde
function script:Test-WolFdKaestchenklick {
    param($Quelle)
    while ($Quelle -and $Quelle -isnot [System.Windows.Controls.DataGridRow]) {
        if ($Quelle -is [System.Windows.FrameworkElement] -and $Quelle.Tag -eq 'Kaestchen') { return $true }
        if ($Quelle -is [System.Windows.Media.Visual]) {
            $Quelle = [System.Windows.Media.VisualTreeHelper]::GetParent($Quelle)
        }
        else {
            $Quelle = [System.Windows.LogicalTreeHelper]::GetParent($Quelle)
        }
    }
    $false
}

## Dateipfad im Explorer oeffnen
function script:Open-WolFdDateipfad {
    $auswahl = $script:FdUi.Grid.SelectedItem
    if (-not $auswahl -or $auswahl.Id -lt 1 -or -not $script:FdModell) { return }

    $pfad = $script:FdModell.Pfad($auswahl.Id) -replace ' \(Verknüpfung\)$', ''
    if ($script:FdScanComputer) {
        if ($pfad -match '^([A-Za-z]):\\?(.*)$') {
            $pfad = '\\{0}\{1}$\{2}' -f $script:FdScanComputer, $Matches[1], $Matches[2]
        }
        else {
            [void][System.Windows.MessageBox]::Show("Der Pfad kann nicht als Adminfreigabe geöffnet werden: $pfad", 'FOLDER-DETECTIVE')
            return
        }
    }

    if ($auswahl.IstOrdner) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $pfad)
    }
    else {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $pfad)
    }
}

# Scan steuern

## Scan starten
function script:Start-WolFdScan {
    $ziel = $script:FdUi.Pfad.Text.Trim()
    $computer = $script:FdRemoteComputer

    if (-not $ziel) {
        [void][System.Windows.MessageBox]::Show('Bitte zuerst ein Laufwerk oder Verzeichnis auswählen oder eingeben.', 'FOLDER-DETECTIVE')
        return
    }
    if (-not $computer -and -not (Test-Path -LiteralPath $ziel -PathType Container)) {
        [void][System.Windows.MessageBox]::Show("Das Verzeichnis existiert nicht oder ist nicht erreichbar: $ziel", 'FOLDER-DETECTIVE')
        return
    }

    $script:FdUi.Scan.IsEnabled = $false
    $script:FdUi.Abbruch.IsEnabled = $true
    $script:FdPausiert = $false
    $script:FdUi.Pause.IsEnabled = -not $computer
    $script:FdUi.PauseSymbol.Text = '❚❚'
    $script:FdUi.PauseText.Text = 'Pause'
    $script:FdUi.ScanText.Text = 'Scan läuft'
    $script:FdSpinnerNr = 0
    $script:FdSpinner.Start()
    $script:FdModell = [FdModell]::new()
    $script:FdOffene.Clear()
    $script:FdZeilen = [System.Collections.ObjectModel.ObservableCollection[FdZeile]]::new()
    $script:FdUi.Grid.ItemsSource = $script:FdZeilen
    Set-WolFdSortPfeil
    $script:FdUi.Auswahl.Text = ''
    $script:FdScanComputer = $computer
    Update-WolFdFehlerKnopf
    $script:FdAbbruchAngefordert = $false
    $script:FdScanStart = Get-Date
    $script:FdLetzterAufbau = Get-Date

    if ($computer) {
        $script:FdScanModus = 'Remote'
        $script:FdScanZiel = '{0}: {1}' -f $computer, $ziel
        $parameter = @{
            ComputerName      = $computer
            ConfigurationName = 'PowerShell.7'
            ScriptBlock       = {
                param($Wurzel, $Code)
                if (-not ('FdScan' -as [type])) { Add-Type -TypeDefinition $Code }
                [FdScan]::Starte($Wurzel)
                try {
                    do {
                        Start-Sleep -Milliseconds 500
                        [FdScan]::Abholen()
                    } while (-not [FdScan]::LetzteFertig)
                }
                finally {
                    [FdScan]::Abbruch = $true
                }
            }
            ArgumentList      = @($ziel, $script:FdCSharp)
            AsJob             = $true
        }
        if ($script:FdAnmeldedaten) { $parameter.Credential = $script:FdAnmeldedaten }
        try { $script:FdJob = Invoke-Command @parameter }
        catch { Complete-WolFdScan -Fehler $_.Exception.Message; return }
    }
    else {
        $script:FdScanModus = 'Lokal'
        $script:FdScanZiel = $ziel
        [FdScan]::Starte($ziel)
    }
    Write-WolLog "Folder-Detective: Scan gestartet: $($script:FdScanZiel)"
    $script:FdTimer.Start()
}

## Scan abschliessen
function script:Complete-WolFdScan {
    param([string]$Fehler = '')
    $script:FdTimer.Stop()
    $dauer = (Get-Date) - $script:FdScanStart

    if ($script:FdJob) {
        Stop-Job -Job $script:FdJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:FdJob -Force -ErrorAction SilentlyContinue
        $script:FdJob = $null
    }
    $script:FdSpinner.Stop()
    $script:FdPausiert = $false
    $script:FdUi.Scan.IsEnabled = $true
    $script:FdUi.Abbruch.IsEnabled = $false
    $script:FdUi.Pause.IsEnabled = $false
    $script:FdUi.PauseSymbol.Text = '❚❚'
    $script:FdUi.PauseText.Text = 'Pause'
    $script:FdUi.ScanSymbol.Text = '▶'
    $script:FdUi.ScanText.Text = 'Scan starten'

    if (-not $Fehler -and $script:FdModell.Meldung) { $Fehler = $script:FdModell.Meldung }
    Update-WolFdAnsicht
    Update-WolFdFehlerKnopf

    if ($Fehler) {
        Write-WolLog "Folder-Detective: Fehler beim Scan ($($script:FdScanZiel)): $Fehler"
        $script:FdUi.Status.Text = "Fehler beim Scan: $(Get-WolFehlerKurz -Text $Fehler)"
        return
    }
    if (-not $script:FdModell.WurzelId) {
        $script:FdUi.Status.Text = 'Keine Daten erhalten.'
        return
    }

    $wurzel = $script:FdModell.Hole($script:FdModell.WurzelId)
    $fehlerKnoten = $script:FdModell.FehlerListe()

    $text = '{0} - Größe {1}, Belegt {2}, {3} Dateien, {4} Ordner, {5} nicht lesbar, Dauer {6} s' -f `
        $script:FdScanZiel,
        (Format-WolFdGroesse $wurzel.Groesse),
        (Format-WolFdGroesse $wurzel.Belegt),
        $wurzel.Dateien.ToString('N0', $script:FdKultur),
        $wurzel.Ordner.ToString('N0', $script:FdKultur),
        $fehlerKnoten.Count,
        [int]$dauer.TotalSeconds
    if ($script:FdAbbruchAngefordert) { $text += ' (abgebrochen, Teilergebnis)' }
    $script:FdUi.Status.Text = $text
    Write-WolLog "Folder-Detective: $text"
}

## Verzeichnis auswaehlen
function script:Select-WolFdOrdner {
    try {
        $dialog = [Microsoft.Win32.OpenFolderDialog]::new()
        $dialog.Title = 'Verzeichnis auswählen'
        $dialog.InitialDirectory = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
        if ($dialog.ShowDialog()) { return $dialog.FolderName }
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.RootFolder = [System.Environment+SpecialFolder]::MyComputer
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
    }
}

# Remote Scan

## Ziel fuer den Remote-Scan setzen und zuruecknehmen
function script:Set-WolFdRemoteZiel {
    param([string]$Computer, $Konto, [string]$Pfad)
    $script:FdRemoteComputer = $Computer
    $script:FdAnmeldedaten = $Konto
    $kontoName = if ($Konto) { $Konto.UserName } else { $script:FdAktuellesKonto }
    $script:FdUi.RemoteText.Text = 'Remote: {0} (Konto: {1})' -f $Computer, $kontoName
    $script:FdUi.RemoteText.Visibility = 'Visible'
    $script:FdUi.RemoteEnde.Visibility = 'Visible'
    if ($Pfad) { $script:FdUi.Pfad.Text = $Pfad }
}

function script:Clear-WolFdRemoteZiel {
    $script:FdRemoteComputer = ''
    $script:FdAnmeldedaten = $null
    $script:FdUi.RemoteText.Text = ''
    $script:FdUi.RemoteText.Visibility = 'Collapsed'
    $script:FdUi.RemoteEnde.Visibility = 'Collapsed'
}

## Knoten fuer den Ordnerbaum (Unterordner werden beim Aufklappen nachgeladen)
function script:New-WolFdBaumKnoten {
    param([string]$Text, [string]$Pfad)
    $knoten = [System.Windows.Controls.TreeViewItem]::new()
    $knoten.Header = $Text
    $knoten.Tag = $Pfad
    $platzhalter = [System.Windows.Controls.TreeViewItem]::new()
    $platzhalter.Header = 'wird geladen …'
    $platzhalter.Tag = '#laden'
    [void]$knoten.Items.Add($platzhalter)
    $knoten
}

## Fenster neu zeichnen lassen, bevor eine laengere Abfrage startet
function script:Update-WolFdDialog {
    $script:FdDlg.Fenster.Dispatcher.Invoke([Action]{ }, [System.Windows.Threading.DispatcherPriority]::Render)
}

## Remote-Dialog: Zugangsdaten, Computer, Laufwerk oder Ordner waehlen
function script:Show-WolFdRemoteDialog {
    [xml]$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xml:lang="de-DE" Title="Remote Scan" Width="580" Height="660" MinWidth="480" MinHeight="520"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <GroupBox Grid.Row="0" Header="Zugangsdaten" Padding="8">
            <StackPanel>
                <RadioButton x:Name="RbGeraet" Margin="0,0,0,6" Visibility="Collapsed"/>
                <RadioButton x:Name="RbAktuell" IsChecked="True" Margin="0,0,0,6"/>
                <RadioButton x:Name="RbAnderes" Content="Anderes Konto verwenden" Margin="0,0,0,6"/>
                <Grid Margin="22,0,0,0" IsEnabled="{Binding IsChecked, ElementName=RbAnderes}">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Benutzername:" VerticalAlignment="Center" Margin="0,0,8,4"/>
                    <TextBox Grid.Row="0" Grid.Column="1" x:Name="TxtBenutzer" Margin="0,0,0,4" Padding="2"/>
                    <TextBlock Grid.Row="1" Text="Kennwort:" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <PasswordBox Grid.Row="1" Grid.Column="1" x:Name="PwKennwort" Padding="2"/>
                </Grid>
            </StackPanel>
        </GroupBox>

        <DockPanel Grid.Row="1" Margin="0,10,0,0">
            <Button x:Name="BtnVerbinden" Content="Verbinden" DockPanel.Dock="Right" Padding="14,3" Margin="8,0,0,0"/>
            <TextBlock Text="Computer:" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBox x:Name="TxtComputer" Padding="2"/>
        </DockPanel>

        <TextBlock Grid.Row="2" x:Name="TxtMeldung" Margin="0,6,0,6" TextWrapping="Wrap" Foreground="DimGray"
                   Text="Computernamen eingeben und auf Verbinden klicken."/>

        <TreeView Grid.Row="3" x:Name="Baum"/>

        <TextBlock Grid.Row="4" x:Name="TxtGewaehlt" Margin="0,8,0,8" TextTrimming="CharacterEllipsis"/>

        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnOk" Content="OK" Width="90" Padding="0,4" Margin="0,0,8,0" IsEnabled="False"/>
            <Button x:Name="BtnAbbruch" Content="Abbrechen" Width="90" Padding="0,4" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $dialog = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($dialogXaml))
    $script:FdDlg = @{ Fenster = $dialog }
    foreach ($name in 'RbGeraet', 'RbAktuell', 'RbAnderes', 'TxtBenutzer', 'PwKennwort', 'TxtComputer', 'BtnVerbinden', 'TxtMeldung', 'Baum', 'TxtGewaehlt', 'BtnOk') {
        $script:FdDlg[$name] = $dialog.FindName($name)
    }
    $script:FdDlg.RbAktuell.Content = 'Aktuellen Benutzer verwenden ({0})' -f $script:FdAktuellesKonto
    $script:FdDlg.TxtComputer.Text = $script:FdRemoteComputer
    ### Genau ein markiertes Gerät im Cockpit: Name und, falls vorhanden, das Konto aus der Geräteliste vorbelegen
    $vorgabe = $script:FdVorgabeZeile
    if ($vorgabe) {
        $script:FdDlg.TxtComputer.Text = Get-WolZielName -Zeile $vorgabe
        if ($vorgabe.Konto) {
            $script:FdDlg.RbGeraet.Content = 'Konto des markierten Geräts verwenden ({0})' -f $vorgabe.Konto
            $script:FdDlg.RbGeraet.Visibility = 'Visible'
            $script:FdDlg.RbGeraet.IsChecked = $true
        }
        $script:FdDlg.TxtMeldung.Text = 'Markiertes Gerät übernommen. Auf Verbinden klicken.'
    }
    $script:FdRemoteSitzung = $null
    $script:FdRemoteErgebnis = $null
    $script:FdDlgComputer = ''
    $script:FdDlgKonto = $null

    ### Verbinden und Laufwerke laden
    $script:FdDlg.BtnVerbinden.Add_Click({
        $computer = $script:FdDlg.TxtComputer.Text.Trim().TrimStart('\')
        if (-not $computer) {
            $script:FdDlg.TxtMeldung.Text = 'Bitte zuerst den Computernamen eingeben.'
            return
        }

        $konto = $null
        if ($script:FdDlg.RbGeraet.IsChecked) {
            $geraet = $script:FdVorgabeZeile
            if (-not (Resolve-WolKonten -Zeilen @($geraet) -Besitzer $script:FdDlg.Fenster)) {
                $script:FdDlg.TxtMeldung.Text = 'Es wurde kein Kennwort für das Konto des Geräts eingegeben.'
                return
            }
            try { $konto = Get-WolAnmeldung -Zeile $geraet }
            catch { $script:FdDlg.TxtMeldung.Text = $_.Exception.Message; return }
        }
        elseif ($script:FdDlg.RbAnderes.IsChecked) {
            $benutzer = $script:FdDlg.TxtBenutzer.Text.Trim()
            if (-not $benutzer -or $script:FdDlg.PwKennwort.SecurePassword.Length -eq 0) {
                $script:FdDlg.TxtMeldung.Text = 'Bitte Benutzername und Kennwort eingeben.'
                return
            }
            $konto = [System.Management.Automation.PSCredential]::new($benutzer, $script:FdDlg.PwKennwort.SecurePassword)
        }

        $script:FdDlg.TxtMeldung.Text = "Verbinde mit $computer …"
        $script:FdDlg.Baum.Items.Clear()
        $script:FdDlg.TxtGewaehlt.Text = ''
        $script:FdDlg.BtnOk.IsEnabled = $false
        $script:FdDlg.Fenster.Cursor = [System.Windows.Input.Cursors]::Wait
        Update-WolFdDialog

        try {
            if ($script:FdRemoteSitzung) {
                Remove-PSSession -Session $script:FdRemoteSitzung -ErrorAction SilentlyContinue
                $script:FdRemoteSitzung = $null
            }
            $parameter = @{ ComputerName = $computer; ConfigurationName = 'PowerShell.7'; ErrorAction = 'Stop' }
            if ($konto) { $parameter.Credential = $konto }
            $script:FdRemoteSitzung = New-PSSession @parameter

            $laufwerke = @(Invoke-Command -Session $script:FdRemoteSitzung -ErrorAction Stop -ScriptBlock {
                [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | ForEach-Object {
                    [pscustomobject]@{
                        Name        = $_.Name
                        Bezeichnung = $_.VolumeLabel
                        Frei        = [long]$_.AvailableFreeSpace
                        Gesamt      = [long]$_.TotalSize
                    }
                }
            })

            foreach ($laufwerk in $laufwerke) {
                $text = '{0}  {1}  {2} frei von {3}' -f $laufwerk.Name, $laufwerk.Bezeichnung, (Format-WolFdGroesse $laufwerk.Frei), (Format-WolFdGroesse $laufwerk.Gesamt)
                [void]$script:FdDlg.Baum.Items.Add((New-WolFdBaumKnoten -Text $text -Pfad $laufwerk.Name))
            }
            $script:FdDlgComputer = $computer
            $script:FdDlgKonto = $konto
            $script:FdDlg.TxtMeldung.Text = "Verbunden mit $computer. Laufwerk oder Ordner auswählen."
        }
        catch {
            $script:FdRemoteSitzung = $null
            Write-WolLog "Folder-Detective: Verbindung zu $computer fehlgeschlagen: $($_.Exception.Message)"
            $script:FdDlg.TxtMeldung.Text = "Verbindung fehlgeschlagen: $(Get-WolFehlerKurz -Text $_.Exception.Message)"
        }
        finally {
            $script:FdDlg.Fenster.Cursor = $null
        }
    })

    ### Unterordner beim Aufklappen nachladen
    $script:FdDlg.Baum.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, [System.Windows.RoutedEventHandler]{
        param($sender, $e)
        $knoten = $e.OriginalSource
        if ($knoten -isnot [System.Windows.Controls.TreeViewItem]) { return }
        if ($knoten.Items.Count -ne 1 -or $knoten.Items[0].Tag -ne '#laden') { return }

        $pfad = [string]$knoten.Tag
        $script:FdDlg.Fenster.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            $namen = @(Invoke-Command -Session $script:FdRemoteSitzung -ErrorAction Stop -ArgumentList $pfad -ScriptBlock {
                param($Ordner)
                Get-ChildItem -LiteralPath $Ordner -Directory -Force -ErrorAction Stop | Sort-Object -Property Name | ForEach-Object { $_.Name }
            })
            $knoten.Items.Clear()
            foreach ($name in $namen) {
                $unterPfad = $pfad.TrimEnd('\') + '\' + $name
                [void]$knoten.Items.Add((New-WolFdBaumKnoten -Text $name -Pfad $unterPfad))
            }
        }
        catch {
            $knoten.Items.Clear()
            $fehler = [System.Windows.Controls.TreeViewItem]::new()
            $fehler.Header = '(nicht lesbar: {0})' -f $_.Exception.Message
            $fehler.Tag = '#fehler'
            $fehler.Foreground = [System.Windows.Media.Brushes]::Firebrick
            [void]$knoten.Items.Add($fehler)
        }
        finally {
            $script:FdDlg.Fenster.Cursor = $null
        }
    })

    ### Auswahl im Baum
    $script:FdDlg.Baum.Add_SelectedItemChanged({
        $knoten = $script:FdDlg.Baum.SelectedItem
        $tag = if ($knoten) { [string]$knoten.Tag } else { '' }
        if ($tag -and -not $tag.StartsWith('#')) {
            $script:FdDlg.TxtGewaehlt.Text = 'Gewählt: {0}' -f $tag
            $script:FdDlg.BtnOk.IsEnabled = $true
        }
        else {
            $script:FdDlg.TxtGewaehlt.Text = ''
            $script:FdDlg.BtnOk.IsEnabled = $false
        }
    })

    ### OK uebernimmt Computer, Konto und Pfad
    $script:FdDlg.BtnOk.Add_Click({
        $knoten = $script:FdDlg.Baum.SelectedItem
        if (-not $knoten) { return }
        $script:FdRemoteErgebnis = @{
            Computer     = $script:FdDlgComputer
            Anmeldedaten = $script:FdDlgKonto
            Pfad         = [string]$knoten.Tag
        }
        $script:FdDlg.Fenster.DialogResult = $true
    })

    $dialog.Owner = $script:FdHauptfenster
    [void]$dialog.ShowDialog()

    if ($script:FdRemoteSitzung) {
        Remove-PSSession -Session $script:FdRemoteSitzung -ErrorAction SilentlyContinue
        $script:FdRemoteSitzung = $null
    }
    $script:FdRemoteErgebnis
}

## Knopf "Nicht lesbar" aktualisieren
function script:Update-WolFdFehlerKnopf {
    $anzahl = if ($script:FdModell) { $script:FdModell.FehlerAnzahl } else { 0 }
    $script:FdUi.Fehler.Content = 'Nicht lesbare anzeigen ({0})' -f $anzahl
    $script:FdUi.Fehler.IsEnabled = $anzahl -gt 0
}

## Fenster mit den nicht lesbaren Ordnern
function script:Show-WolFdFehlerliste {
    [xml]$listeXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xml:lang="de-DE" Title="Nicht lesbare Ordner" Width="920" Height="500" MinWidth="500" MinHeight="300"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid Grid.Row="0" x:Name="FehlerGitter" AutoGenerateColumns="False" IsReadOnly="True"
                  CanUserAddRows="False" HeadersVisibility="Column" GridLinesVisibility="None" SelectionMode="Single">
            <DataGrid.ContextMenu>
                <ContextMenu>
                    <MenuItem x:Name="MenuKopieren" Header="Pfad kopieren"/>
                </ContextMenu>
            </DataGrid.ContextMenu>
            <DataGrid.Columns>
                <DataGridTextColumn Header="Pfad" Binding="{Binding Pfad}" Width="*"/>
                <DataGridTextColumn Header="Meldung" Binding="{Binding Meldung}" Width="300"/>
            </DataGrid.Columns>
        </DataGrid>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button x:Name="BtnAktualisieren" Content="Aktualisieren" Padding="14,4" Margin="0,0,8,0"/>
            <Button x:Name="BtnSchliessen" Content="Schließen" Padding="14,4" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $dialog = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($listeXaml))
    $script:FdFehlerDlg = @{ Fenster = $dialog }
    foreach ($name in 'FehlerGitter', 'BtnAktualisieren', 'MenuKopieren') {
        $script:FdFehlerDlg[$name] = $dialog.FindName($name)
    }
    $script:FdFehlerDlg.FehlerGitter.ItemsSource = $script:FdModell.FehlerListe()

    $script:FdFehlerDlg.BtnAktualisieren.Add_Click({
        $script:FdFehlerDlg.FehlerGitter.ItemsSource = $script:FdModell.FehlerListe()
    })

    $script:FdFehlerDlg.FehlerGitter.Add_PreviewMouseRightButtonDown({
        param($sender, $e)
        $zeile = Get-WolFdGitterZeile -Quelle $e.OriginalSource
        if ($zeile) { $zeile.IsSelected = $true }
    })

    $script:FdFehlerDlg.MenuKopieren.Add_Click({
        $auswahl = $script:FdFehlerDlg.FehlerGitter.SelectedItem
        if ($auswahl) { [System.Windows.Clipboard]::SetText($auswahl.Pfad) }
    })

    $dialog.Owner = $script:FdHauptfenster
    [void]$dialog.ShowDialog()
}

# Fenster
## Wird vom Menü Module > Folder-Detective aufgerufen: Fenster öffnen oder in den Vordergrund holen
function script:Show-WolModulFOLDERDETECTIVE {
    if (-not $script:FdTypOk) {
        Show-WolMeldung "Der Folder-Detective kann nicht starten, weil in diesem Prozess noch eine ältere Version seiner Typen geladen ist.`r`n`r`nBitte das NET-COCKPIT beenden und neu starten." 'Warning'
        return
    }
    if ($script:FdFenster) {
        if ($script:FdFenster.WindowState -eq 'Minimized') { $script:FdFenster.WindowState = 'Normal' }
        [void]$script:FdFenster.Activate()
        return
    }

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xml:lang="de-DE" Title="FOLDER-DETECTIVE" Width="1180" Height="740"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style x:Key="Rechts" TargetType="TextBlock">
            <Setter Property="TextAlignment" Value="Right"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
        </Style>
        <Style x:Key="Fehlertext" TargetType="TextBlock">
            <Setter Property="Foreground" Value="Firebrick"/>
        </Style>
    </Window.Resources>
    <Grid Margin="8">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <WrapPanel Grid.Row="0" Margin="0,0,0,8">
            <WrapPanel.Resources>
                <Style TargetType="TextBlock"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="0,0,6,0"/></Style>
                <Style TargetType="TextBox"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="0,0,12,0"/><Setter Property="Padding" Value="2"/></Style>
                <Style TargetType="Button"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="0,0,12,0"/><Setter Property="Padding" Value="10,3"/></Style>
                <Style TargetType="ComboBox"><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Margin" Value="0,0,12,0"/></Style>
            </WrapPanel.Resources>
            <TextBlock Text="Verzeichnis:"/>
            <TextBox x:Name="Pfad" Width="420"/>
            <Button x:Name="PfadWaehlen" Content="Pfad wählen" ToolTip="Laufwerk oder Ordner auf diesem Rechner auswählen"/>
            <Button x:Name="RemoteScan" Content="Remote Scan" ToolTip="Laufwerk oder Ordner auf einem anderen Computer auswählen"/>
            <TextBlock x:Name="RemoteText" FontWeight="Bold" Foreground="DarkBlue" Visibility="Collapsed"/>
            <Button x:Name="RemoteEnde" Content="Remote beenden" Visibility="Collapsed" ToolTip="Zurück zum Scan auf diesem Rechner"/>
        </WrapPanel>

        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
            <Button x:Name="Scan" FontWeight="Bold" FontSize="14" Padding="26,7"
                    Background="#A5D6A7" BorderBrush="#2E7D32" BorderThickness="2" Margin="0,0,10,0">
                <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="ScanSymbol" Text="▶" Foreground="#2E7D32" Width="22" TextAlignment="Center"/>
                    <TextBlock x:Name="ScanText" Text="Scan starten" Margin="6,0,0,0"/>
                </StackPanel>
            </Button>
            <Button x:Name="Pause" Padding="16,7" Margin="0,0,10,0" IsEnabled="False"
                    ToolTip="Scan anhalten und fortsetzen (nur bei lokalen Scans)">
                <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="PauseSymbol" Text="❚❚" Foreground="#1565C0" Width="22" TextAlignment="Center"/>
                    <TextBlock x:Name="PauseText" Text="Pause" Margin="4,0,0,0"/>
                </StackPanel>
            </Button>
            <Button x:Name="Abbruch" Padding="16,7" IsEnabled="False">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="■" Foreground="#C62828" FontSize="15" Width="22" TextAlignment="Center"/>
                    <TextBlock Text="Abbrechen" Margin="4,0,0,0"/>
                </StackPanel>
            </Button>
            <Button x:Name="Fehler" Content="Nicht lesbare anzeigen (0)" Padding="16,7" Margin="10,0,0,0" IsEnabled="False"/>
        </StackPanel>

        <DataGrid Grid.Row="2" x:Name="Grid" AutoGenerateColumns="False" IsReadOnly="True"
                  CanUserAddRows="False" CanUserSortColumns="True" SelectionMode="Single"
                  HeadersVisibility="Column" GridLinesVisibility="None" RowHeight="22"
                  EnableRowVirtualization="True">
            <DataGrid.ContextMenu>
                <ContextMenu>
                    <MenuItem x:Name="MenuPfadOeffnen" Header="Dateipfad öffnen"/>
                </ContextMenu>
            </DataGrid.ContextMenu>
            <DataGrid.RowStyle>
                <Style TargetType="DataGridRow">
                    <Style.Triggers>
                        <DataTrigger Binding="{Binding IstOrdner}" Value="True">
                            <Setter Property="FontWeight" Value="SemiBold"/>
                        </DataTrigger>
                    </Style.Triggers>
                </Style>
            </DataGrid.RowStyle>
            <DataGrid.Columns>
                <DataGridTemplateColumn Header="Name" Width="*" MinWidth="300" SortMemberPath="Name">
                    <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                            <StackPanel Orientation="Horizontal">
                                <Border Width="{Binding Einzug}"/>
                                <Border Tag="Kaestchen" Width="14" Height="14" Margin="0,0,6,0" CornerRadius="2"
                                        BorderBrush="Gray" BorderThickness="1" Background="White" Cursor="Hand">
                                    <Border.Style>
                                        <Style TargetType="Border">
                                            <Setter Property="Visibility" Value="Hidden"/>
                                            <Style.Triggers>
                                                <DataTrigger Binding="{Binding HatKinder}" Value="True">
                                                    <Setter Property="Visibility" Value="Visible"/>
                                                </DataTrigger>
                                            </Style.Triggers>
                                        </Style>
                                    </Border.Style>
                                    <TextBlock Text="{Binding Symbol}" FontSize="12" FontWeight="Bold" Foreground="#333333"
                                               HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-2,0,0"/>
                                </Border>
                                <TextBlock Text="{Binding Name}"/>
                            </StackPanel>
                        </DataTemplate>
                    </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTextColumn Header="Größe" Binding="{Binding GroesseText}" Width="95" SortMemberPath="Groesse" ElementStyle="{StaticResource Rechts}"/>
                <DataGridTextColumn Header="Belegt" Binding="{Binding BelegtText}" Width="95" SortMemberPath="Belegt" ElementStyle="{StaticResource Rechts}"/>
                <DataGridTextColumn Header="Dateien" Binding="{Binding Dateien, StringFormat=N0}" Width="85" SortMemberPath="Dateien" ElementStyle="{StaticResource Rechts}"/>
                <DataGridTextColumn Header="Ordner" Binding="{Binding Ordner, StringFormat=N0}" Width="75" SortMemberPath="Ordner" ElementStyle="{StaticResource Rechts}"/>
                <DataGridTemplateColumn Header="% Anteil" Width="120" SortMemberPath="Prozent">
                    <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                            <Grid Margin="2,2">
                                <ProgressBar Minimum="0" Maximum="100" Value="{Binding Prozent, Mode=OneWay}"
                                             Foreground="#7F9CF5" Background="#E6E6E6" BorderThickness="0"/>
                                <TextBlock Text="{Binding ProzentText}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Grid>
                        </DataTemplate>
                    </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTextColumn Header="Letzte Änderung" Binding="{Binding Geaendert}" Width="130" SortMemberPath="Geaendert"/>
                <DataGridTextColumn Header="Hinweis" Binding="{Binding Hinweis}" Width="160" CanUserSort="False" ElementStyle="{StaticResource Fehlertext}"/>
            </DataGrid.Columns>
        </DataGrid>

        <DockPanel Grid.Row="3" Margin="0,6,0,0">
            <TextBlock x:Name="Auswahl" DockPanel.Dock="Right" Foreground="Gray" Margin="12,0,0,0" TextTrimming="CharacterEllipsis" MaxWidth="480"/>
            <TextBlock x:Name="Status" Text="Bereit." TextTrimming="CharacterEllipsis"/>
        </DockPanel>
    </Grid>
</Window>
'@

    $fenster = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    $script:FdUi = @{}
    foreach ($name in 'Pfad', 'PfadWaehlen', 'RemoteScan', 'RemoteText', 'RemoteEnde', 'Scan', 'ScanSymbol', 'ScanText', 'Pause', 'PauseSymbol', 'PauseText', 'Abbruch', 'Fehler', 'Grid', 'Status', 'Auswahl', 'MenuPfadOeffnen') {
        $script:FdUi[$name] = $fenster.FindName($name)
    }
    $script:FdHauptfenster = $fenster

    ### Zustand zurücksetzen (das Modul bleibt geladen, wenn das Fenster geschlossen wurde)
    $script:FdModell = $null
    $script:FdScrollViewer = $null
    $script:FdOffene.Clear()
    $script:FdJob = $null
    $script:FdScanModus = ''
    $script:FdScanComputer = ''
    $script:FdRemoteComputer = ''
    $script:FdAnmeldedaten = $null

    $script:FdZeilen = [System.Collections.ObjectModel.ObservableCollection[FdZeile]]::new()
    $script:FdUi.Grid.ItemsSource = $script:FdZeilen
    $script:FdUi.Pfad.Text = ''
    Set-WolFdSortPfeil

    ## Timer: Daten abholen, Ansicht auffrischen
    $script:FdTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:FdTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:FdTimer.Add_Tick({
        $beendet = $false
        try {
            if ($script:FdScanModus -eq 'Lokal') {
                $script:FdModell.Uebernehmen([FdScan]::Abholen())
                $beendet = [FdScan]::LetzteFertig
            }
            else {
                $zustand = $script:FdJob.State
                foreach ($stapel in @(Receive-Job -Job $script:FdJob -ErrorAction Stop)) {
                    $script:FdModell.Uebernehmen([string]$stapel)
                }
                $beendet = $zustand -notin 'Running', 'NotStarted'
            }
        }
        catch {
            if ($script:FdAbbruchAngefordert) { $beendet = $true }
            else { Complete-WolFdScan -Fehler $_.Exception.Message; return }
        }

        if ($script:FdZeilen.Count -eq 0 -and $script:FdModell.WurzelId -ne 0) {
            [void]$script:FdOffene.Add($script:FdModell.WurzelId)
            Update-WolFdAnsicht
            $script:FdLetzterAufbau = Get-Date
        }

        $sekunden = [int]((Get-Date) - $script:FdScanStart).TotalSeconds
        $wurzel = $script:FdModell.Hole($script:FdModell.WurzelId)
        $belegt = if ($wurzel) { Format-WolFdGroesse $wurzel.Belegt } else { '0 Bytes' }
        $script:FdUi.Status.Text = 'Scan läuft … {0} Dateien, {1} belegt, {2} nicht lesbar, {3} s' -f `
            $script:FdModell.ZaehlerDateien.ToString('N0', $script:FdKultur), $belegt, $script:FdModell.FehlerAnzahl, $sekunden
        if ($script:FdPausiert) { $script:FdUi.Status.Text = $script:FdUi.Status.Text -replace '^Scan läuft …', 'Pausiert –' }
        Update-WolFdFehlerKnopf

        if ($beendet) { Complete-WolFdScan; return }

        if (((Get-Date) - $script:FdLetzterAufbau).TotalSeconds -ge $script:FdAufbauIntervall) {
            Update-WolFdAnsicht
            $script:FdLetzterAufbau = Get-Date
        }
    })

    ## Kreisel im Scan-Knopf
    $script:FdSpinner = [System.Windows.Threading.DispatcherTimer]::new()
    $script:FdSpinner.Interval = [TimeSpan]::FromMilliseconds(130)
    $script:FdSpinnerBilder = @('◐', '◓', '◑', '◒')
    $script:FdSpinnerNr = 0
    $script:FdPausiert = $false
    $script:FdSpinner.Add_Tick({
        if ($script:FdPausiert) { return }
        $script:FdSpinnerNr = ($script:FdSpinnerNr + 1) % $script:FdSpinnerBilder.Count
        $script:FdUi.ScanSymbol.Text = $script:FdSpinnerBilder[$script:FdSpinnerNr]
    })

    ## Ereignisse
    $script:FdUi.Scan.Add_Click({ Start-WolFdScan })

    $script:FdUi.Pause.Add_Click({
        if ($script:FdScanModus -ne 'Lokal') { return }
        $script:FdPausiert = -not $script:FdPausiert
        [FdScan]::Pause = $script:FdPausiert
        if ($script:FdPausiert) {
            $script:FdUi.PauseSymbol.Text = '▶'
            $script:FdUi.PauseText.Text = 'Fortsetzen'
            $script:FdUi.ScanSymbol.Text = '❚❚'
            $script:FdUi.ScanText.Text = 'Scan pausiert'
        }
        else {
            $script:FdUi.PauseSymbol.Text = '❚❚'
            $script:FdUi.PauseText.Text = 'Pause'
            $script:FdUi.ScanText.Text = 'Scan läuft'
        }
    })

    $script:FdUi.Abbruch.Add_Click({
        if ($script:FdScanModus -eq 'Lokal') { [FdScan]::Pause = $false }
        $script:FdPausiert = $false
        $script:FdAbbruchAngefordert = $true
        $script:FdUi.Status.Text = 'Abbruch angefordert …'
        if ($script:FdScanModus -eq 'Lokal') { [FdScan]::Abbruch = $true }
        elseif ($script:FdJob) { Stop-Job -Job $script:FdJob -ErrorAction SilentlyContinue }
    })

    $script:FdUi.Fehler.Add_Click({
        if ($script:FdModell) { Show-WolFdFehlerliste }
    })

    $script:FdUi.PfadWaehlen.Add_Click({
        $auswahl = Select-WolFdOrdner
        if ($auswahl) {
            Clear-WolFdRemoteZiel
            $script:FdUi.Pfad.Text = $auswahl
        }
    })

    $script:FdUi.RemoteScan.Add_Click({
        $markiert = @(Get-WolMarkierte)
        $script:FdVorgabeZeile = $(if ($markiert.Count -eq 1) { $markiert[0] } else { $null })
        $ergebnis = Show-WolFdRemoteDialog
        if ($ergebnis) {
            Set-WolFdRemoteZiel -Computer $ergebnis.Computer -Konto $ergebnis.Anmeldedaten -Pfad $ergebnis.Pfad
            Write-WolLog "Folder-Detective: Remote-Ziel $($ergebnis.Computer), Pfad $($ergebnis.Pfad)"
        }
    })

    $script:FdUi.RemoteEnde.Add_Click({
        Clear-WolFdRemoteZiel
        $script:FdUi.Pfad.Text = ''
    })

    $script:FdUi.Grid.Add_Sorting({
        param($sender, $e)
        $e.Handled = $true
        $schluessel = [string]$e.Column.SortMemberPath
        if (-not $schluessel) { return }
        if ($schluessel -eq 'Prozent') { $schluessel = $script:FdProzentbasis }
        elseif ($schluessel -in 'Groesse', 'Belegt') { $script:FdProzentbasis = $schluessel }

        if ($schluessel -eq $script:FdSortSpalte) {
            $script:FdSortAufsteigend = -not $script:FdSortAufsteigend
        }
        else {
            $script:FdSortSpalte = $schluessel
            $script:FdSortAufsteigend = ($schluessel -eq 'Name')
        }
        Set-WolFdSortPfeil
        Update-WolFdAnsicht
    })

    $script:FdUi.Grid.Add_PreviewMouseRightButtonDown({
        param($sender, $e)
        $zeile = Get-WolFdGitterZeile -Quelle $e.OriginalSource
        if ($zeile) { $zeile.IsSelected = $true }
    })

    $script:FdUi.Grid.Add_ContextMenuOpening({
        param($sender, $e)
        $auswahl = $script:FdUi.Grid.SelectedItem
        if (-not $auswahl -or $auswahl.Id -lt 1) { $e.Handled = $true }
    })

    $script:FdUi.MenuPfadOeffnen.Add_Click({ Open-WolFdDateipfad })

    $script:FdUi.Grid.Add_SelectionChanged({
        $auswahl = $script:FdUi.Grid.SelectedItem
        $script:FdUi.Auswahl.Text = if ($auswahl -and $auswahl.Id -gt 0 -and $script:FdModell) { $script:FdModell.Pfad($auswahl.Id) } else { '' }
    })

    $script:FdUi.Grid.Add_PreviewMouseLeftButtonDown({
        param($sender, $e)
        if (-not (Test-WolFdKaestchenklick -Quelle $e.OriginalSource)) { return }
        $e.Handled = $true
        if ($e.ClickCount -gt 1) { return }
        $zeile = Get-WolFdGitterZeile -Quelle $e.OriginalSource
        if (-not $zeile) { return }
        $index = $script:FdUi.Grid.ItemContainerGenerator.IndexFromContainer($zeile)
        if ($index -ge 0) { Switch-WolFdKnoten -Index $index -Oeffnen (-not $script:FdZeilen[$index].Offen) }
    })

    $script:FdUi.Grid.Add_MouseDoubleClick({
        param($sender, $e)
        if (-not (Get-WolFdGitterZeile -Quelle $e.OriginalSource)) { return }
        if (Test-WolFdKaestchenklick -Quelle $e.OriginalSource) { return }
        $index = $script:FdUi.Grid.SelectedIndex
        if ($index -ge 0) { Switch-WolFdKnoten -Index $index -Oeffnen (-not $script:FdZeilen[$index].Offen) }
    })

    $script:FdUi.Grid.Add_PreviewKeyDown({
        param($sender, $e)
        $index = $script:FdUi.Grid.SelectedIndex
        if ($index -lt 0) { return }
        switch ($e.Key) {
            'Right'  { Switch-WolFdKnoten -Index $index -Oeffnen $true; $e.Handled = $true }
            'Left'   { Switch-WolFdKnoten -Index $index -Oeffnen $false; $e.Handled = $true }
            'Return' { Switch-WolFdKnoten -Index $index -Oeffnen (-not $script:FdZeilen[$index].Offen); $e.Handled = $true }
        }
    })

    $fenster.Add_Closing({
        [FdScan]::Abbruch = $true
        $script:FdTimer.Stop()
        $script:FdSpinner.Stop()
        if ($script:FdJob) {
            Stop-Job -Job $script:FdJob -ErrorAction SilentlyContinue
            Remove-Job -Job $script:FdJob -Force -ErrorAction SilentlyContinue
        }
    })

    $fenster.Add_Closed({
        $script:FdFenster = $null
        Write-WolLog 'Folder-Detective: Fenster geschlossen'
    })
    ### Beendet sich das NET-COCKPIT, schließt sich das Fenster mit (nur einmal einhängen)
    if (-not $script:FdCockpitHaken) {
        $script:FdCockpitHaken = $true
        $script:Fenster.Add_Closed({ if ($script:FdFenster) { $script:FdFenster.Close() } })
    }

    $script:FdFenster = $fenster
    $fenster.Show()
    Write-WolLog 'Folder-Detective: Fenster geöffnet'
}
