# NET-COCKPIT-Modul-MOUSEMOVER.ps1
<#
.SYNOPSIS
    Modul MouseMover für das NET-COCKPIT (Menü Werkzeuge > MouseMover)

.DESCRIPTION
    Wird vom NET-COCKPIT beim ersten Aufruf nachgeladen (liegt im selben Ordner) und öffnet ein kleines Fenster, das immer im Vordergrund bleibt.
    - Schiebeschalter I (an) und O (aus): ist er an, bewegt das Modul alle 30 Sekunden den Mauszeiger 1 Pixel nach rechts und gleich wieder 1 Pixel nach links (Windows-Eingabe über SendInput)
    - Das Fenster zeigt unter "Aktives Fenster" das Fenster unter dem Mauszeiger (dorthin geht die Bewegung): Titel und Programm, bei einem RDP-Tab des NET-COCKPIT zusätzlich den Server, dazu den Countdown bis zur nächsten Bewegung
    - Beim Start ist der Mouse Mover aus; Fenster schließen oder das NET-COCKPIT beenden stoppt ihn
    - Hält nur den lokalen Rechner wach; in einer RDP-Sitzung kommt die Bewegung nur an, solange der Mauszeiger über dem RDP-Fenster steht
    Das Modul speichert nichts.
#>

# Einstellungen
## Sekunden zwischen zwei Bewegungen
$script:MmIntervall = 30

## Zustand: Fenster, Steuerelemente, Timer und Countdown (bleibt auch bei geschlossenem Fenster erhalten)
$script:MmFenster = $null
$script:MmC = @{}
$script:MmTimer = $null
$script:MmRest = $script:MmIntervall
$script:MmHandle = [IntPtr]::Zero

# Windows-Funktionen
## Mausbewegung (SendInput) und Fenster unter dem Mauszeiger
if (-not ('WolMausNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WolMausNative
{
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion u; }

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint anzahl, INPUT[] eingaben, int groesse);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr fenster, uint art);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr fenster, StringBuilder text, int max);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr fenster, out uint prozessId);

    // Mauszeiger um dx Pixel in X-Richtung bewegen (relativ)
    public static bool Bewege(int dx)
    {
        INPUT[] eingaben = new INPUT[1];
        eingaben[0].type = 0;
        eingaben[0].u.mi.dx = dx;
        eingaben[0].u.mi.dy = 0;
        eingaben[0].u.mi.dwFlags = 0x0001;
        return SendInput(1, eingaben, Marshal.SizeOf(typeof(INPUT))) == 1;
    }

    // Oberstes Fenster (Hauptfenster) unter dem Mauszeiger
    public static IntPtr FensterUnterZeiger(out uint prozessId)
    {
        prozessId = 0;
        POINT p;
        if (!GetCursorPos(out p)) { return IntPtr.Zero; }
        IntPtr h = WindowFromPoint(p);
        if (h == IntPtr.Zero) { return IntPtr.Zero; }
        IntPtr oben = GetAncestor(h, 2);
        if (oben != IntPtr.Zero) { h = oben; }
        GetWindowThreadProcessId(h, out prozessId);
        return h;
    }

    // Titel eines Fensters
    public static string Titel(IntPtr fenster)
    {
        StringBuilder text = new StringBuilder(256);
        GetWindowText(fenster, text, text.Capacity);
        return text.ToString();
    }
}
'@
}

# Hilfsfunktionen
## Handle eines WPF-Fensters (0, wenn es nicht offen ist)
function script:Get-WolMmHandle {
    param($Fenster)
    if (-not $Fenster) { return [IntPtr]::Zero }
    try { return [System.Windows.Interop.WindowInteropHelper]::new($Fenster).Handle } catch { return [IntPtr]::Zero }
}

## Text für das Fenster unter dem Mauszeiger
function script:Get-WolMmZiel {
    $prozessId = [uint32]0
    $handle = [WolMausNative]::FensterUnterZeiger([ref]$prozessId)
    if ($handle -eq [IntPtr]::Zero) { return 'kein Fenster' }
    if ($handle -eq $script:MmHandle) { return 'MouseMover-Fenster (die Bewegung geht ins Leere)' }
    if ($handle -eq (Get-WolMmHandle -Fenster $script:Fenster)) { return 'NET-COCKPIT' }
    ### RDP-Fenster des NET-COCKPIT: den Server des aktiven Tabs anzeigen (nur, wenn das Modul RDP geladen und offen ist)
    $rdp = Get-Variable -Name RdFenster -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($rdp -and $handle -eq (Get-WolMmHandle -Fenster $rdp)) {
        $rdpC = Get-Variable -Name RdC -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        $tab = $(if ($rdpC -and $rdpC.Tabs) { $rdpC.Tabs.SelectedItem } else { $null })
        if ($tab) { return "RDP-Tab: $($tab.Tag.Ziel)" }
        return 'RDP-Fenster (kein Tab offen)'
    }
    $titel = [WolMausNative]::Titel($handle)
    $programm = ''
    try { $programm = (Get-Process -Id $prozessId -ErrorAction Stop).ProcessName } catch { }
    if ($titel -and $programm) { return "$titel ($programm)" }
    if ($titel) { return $titel }
    if ($programm) { return $programm }
    return 'unbekanntes Fenster'
}

## Anzeige im Fenster aktualisieren (Fenster unter dem Mauszeiger, Zustand und Countdown)
function script:Update-WolMmAnzeige {
    $c = $script:MmC
    if (-not $c.TxtFenster) { return }
    $c.TxtFenster.Text = Get-WolMmZiel
    if ($c.Schalter.IsChecked) {
        $c.TxtCountdown.Text = "Nächste Bewegung in $($script:MmRest) s"
        $c.TxtZustand.Text = 'Mouse Mover: AN'
    }
    else {
        $c.TxtCountdown.Text = 'Mouse Mover ist aus'
        $c.TxtZustand.Text = 'Mouse Mover: AUS'
    }
}

## Takt (jede Sekunde): Anzeige aktualisieren, bei Ablauf des Countdowns den Mauszeiger 1 Pixel nach rechts und wieder nach links bewegen
function script:Invoke-WolMmTakt {
    try {
        if ($script:MmC.Schalter -and $script:MmC.Schalter.IsChecked) {
            $script:MmRest--
            if ($script:MmRest -le 0) {
                $script:MmRest = $script:MmIntervall
                [void][WolMausNative]::Bewege(1)
                [void][WolMausNative]::Bewege(-1)
            }
        }
        Update-WolMmAnzeige
    }
    catch { }
}

## Mouse Mover ein- oder ausschalten
function script:Set-WolMmZustand {
    param([bool]$An)
    $script:MmRest = $script:MmIntervall
    Write-WolLog $(if ($An) { "MouseMover: an (alle $($script:MmIntervall) s)" } else { 'MouseMover: aus' })
    Update-WolMmAnzeige
}

# Fenster
## Wird vom Menü Werkzeuge > MouseMover aufgerufen: kleines Fenster, immer im Vordergrund
function script:Show-WolModulMOUSEMOVER {
    if ($script:MmFenster) { [void]$script:MmFenster.Activate(); return }
    $f = New-WolFenster @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MouseMover" Width="330" SizeToContent="Height" Topmost="True" ResizeMode="NoResize"
        WindowStyle="ToolWindow" ShowInTaskbar="False" ShowActivated="False" WindowStartupLocation="Manual">
  <StackPanel Margin="12">
    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
      <ToggleButton x:Name="Schalter" Width="78" Height="34" Cursor="Hand" Margin="0,0,12,0" ToolTip="I = an, O = aus">
        <ToggleButton.Template>
          <ControlTemplate TargetType="ToggleButton">
            <Grid>
              <Border x:Name="Bahn" CornerRadius="17" Background="#FF9A9A9A"/>
              <TextBlock x:Name="TxtI" Text="I" FontWeight="Bold" FontSize="15" Foreground="White" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="16,0,0,0" Visibility="Hidden"/>
              <TextBlock x:Name="TxtO" Text="O" FontWeight="Bold" FontSize="15" Foreground="White" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,16,0"/>
              <Ellipse x:Name="Knopf" Width="26" Height="26" Fill="White" HorizontalAlignment="Left" Margin="4,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bahn" Property="Background" Value="#FF2E9E4F"/>
                <Setter TargetName="Knopf" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knopf" Property="Margin" Value="0,0,4,0"/>
                <Setter TargetName="TxtI" Property="Visibility" Value="Visible"/>
                <Setter TargetName="TxtO" Property="Visibility" Value="Hidden"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </ToggleButton.Template>
      </ToggleButton>
      <StackPanel VerticalAlignment="Center">
        <TextBlock x:Name="TxtZustand" FontWeight="Bold" FontSize="14"/>
        <TextBlock x:Name="TxtCountdown" Foreground="DimGray"/>
      </StackPanel>
    </StackPanel>
    <TextBlock Text="Aktives Fenster (unter dem Mauszeiger):" Foreground="DimGray" FontSize="11"/>
    <TextBlock x:Name="TxtFenster" TextWrapping="Wrap" MaxHeight="60" TextTrimming="CharacterEllipsis"/>
  </StackPanel>
</Window>
'@
    $script:MmC = @{}
    foreach ($name in 'Schalter', 'TxtZustand', 'TxtCountdown', 'TxtFenster') { $script:MmC[$name] = $f.FindName($name) }
    $script:MmC.Schalter.Add_Checked({ Set-WolMmZustand -An $true })
    $script:MmC.Schalter.Add_Unchecked({ Set-WolMmZustand -An $false })

    ### Startposition: oben rechts im Arbeitsbereich
    $f.Left = [System.Windows.SystemParameters]::WorkArea.Right - $f.Width - 20
    $f.Top = [System.Windows.SystemParameters]::WorkArea.Top + 20

    ### Takt jede Sekunde
    $script:MmTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:MmTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:MmTimer.Add_Tick({ Invoke-WolMmTakt })

    ### Schließen: Mouse Mover stoppen
    $f.Add_Closed({
        $script:MmTimer.Stop()
        if ($script:MmC.Schalter -and $script:MmC.Schalter.IsChecked) { Write-WolLog 'MouseMover: aus (Fenster geschlossen)' }
        $script:MmFenster = $null
        $script:MmC = @{}
        $script:MmHandle = [IntPtr]::Zero
    })
    ### Beendet sich das NET-COCKPIT, schließt sich das Fenster mit
    $script:Fenster.Add_Closed({ if ($script:MmFenster) { $script:MmFenster.Close() } })

    $script:MmFenster = $f
    $f.Show()
    $script:MmHandle = Get-WolMmHandle -Fenster $f
    $script:MmRest = $script:MmIntervall
    Update-WolMmAnzeige
    $script:MmTimer.Start()
}
