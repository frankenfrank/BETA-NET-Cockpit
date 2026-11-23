# NET-COCKPIT-Hilfe.ps1
<#
.SYNOPSIS
    Hilfetexte der Module für die Info des NET-COCKPIT (Menü Hilfe > Info / Voraussetzungen)

.DESCRIPTION
    Wird vom NET-COCKPIT geladen, wenn die Info geöffnet wird, damit die Reiter aller Module zu lesen sind, ohne die Module zu starten.
    - Liegt die Datei im Ordner des NET-COCKPIT (Dev-Ordner), wird sie direkt gelesen; sonst holt das NET-COCKPIT sie einmal vom Server (Ladefenster, Signaturprüfung)
    - Pro Modul ein Block $script:ModulInfo['SCHLÜSSEL']; die Texte stehen nur hier, nicht in den Modulen
    - Blöcke je Reiter: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten
    - Reihenfolge der Reiter: wie die Module im NET-COCKPIT geführt werden
    Die Datei enthält nur Text und speichert nichts.
#>

# OS-Updates
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['OS'] = {
    @{ Titel = 'OS-Updates'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Sucht und installiert **Windows-Updates** (PSWindowsUpdate) auf den markierten, grünen Geräten, ohne RDP. Das Fenster öffnet sich über **Module > OS** und bleibt neben der Tabelle offen.' }
        @{ T = 'h'; X = 'Voraussetzungen' }
        @{ T = 'i'; X = '**Auf jedem Zielgerät,** in PowerShell als Administrator: Enable-PSRemoting -Force. Bei Clients im Netzwerkprofil "Öffentlich" zusätzlich: Enable-PSRemoting -Force -SkipNetworkProfileCheck' }
        @{ T = 'i'; X = '**Modul PSWindowsUpdate** auf dem Zielgerät: einfacher per Knopf "Update-Modul nachinstallieren", von Hand mit Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force und Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force. Das Gerät braucht dafür Internetzugang zur PSGallery.' }
        @{ T = 'i'; X = '**Dieser Rechner:** PowerShell 7, ein Konto mit Administratorrechten auf den Zielgeräten (oder ein Konto je Gerät über Optionen > Konto für markierte Geräte), Port 5985 erreichbar.' }
        @{ T = 'i'; X = '**Geräte ohne Domäne oder per IP** (Kerberos geht dort nicht): Optionen > Verbindung (TrustedHosts) und ein lokales Konto im Format Gerätename\Benutzer. Bei anderen lokalen Administratorkonten als dem eingebauten Administrator kann Windows den Fernzugriff filtern ("Zugriff verweigert").' }
        @{ T = 'h'; X = 'Knöpfe' }
        @{ T = 'i'; X = '**Status prüfen:** Windows-Version, letzter Neustart (mit Dauer), Neustart ausstehend, geplanter Neustart, Modul, verfügbare Updates und Update-Verlauf. Gesucht wird auf zwei Wegen: normale Updates (PSWindowsUpdate) und optionale Updates wie Feature-Updates (zum Beispiel Windows 11, Version 26H2), in der Detailliste mit Art: Optional.' }
        @{ T = 'i'; X = '**Updates installieren:** ohne automatischen Neustart (-IgnoreReboot). Ist ein Neustart nötig, steht es im Status; auslösen über Aktionen > Neustart planen.' }
        @{ T = 'i'; X = '**Feature-Update installieren:** lädt ein gefundenes optionales Feature-Update über den Windows-Update-Agent herunter und installiert es (mit Rückfrage, kein automatischer Neustart; Neustart über Aktionen > Neustart planen). Updates installieren lässt Feature-Updates aus.' }
        @{ T = 'i'; X = '**Updates installieren und bei Bedarf neu starten:** Neustart nach 30 Sekunden, nur wenn nötig (mit Rückfrage).' }
        @{ T = 'i'; X = '**Update-Modul nachinstallieren:** PSWindowsUpdate auf Geräten, wo es fehlt. Danach läuft automatisch Status prüfen für dieses Gerät.' }
        @{ T = 'i'; X = '**Details des markierten Geräts...:** verfügbare Updates, Update-Verlauf ohne Defender-Definitionen bei "Letzte Updates" (letzte 50 Einträge) und das Log dieses Geräts.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Spalten:** Neustart ausstehend, Letzter Neustart, Update-Modul, OS-Updates und Letzte Updates sind nur sichtbar, wenn im Modulfenster der Haken **Spalten des Moduls in der Tabelle anzeigen** gesetzt ist (beim Öffnen immer aus; Ansicht > Spalten blendet sie bis zum nächsten Öffnen oder Schließen von Hand ein oder aus).' }
        @{ T = 'i'; X = '**Suche und Installation** laufen als kurze geplante Aufgabe (SYSTEM, ohne Trigger) auf dem Gerät, weil Windows das aus einer Remote-Sitzung nicht erlaubt. Sie wird nach dem Ende gelöscht. Läuft schon eine Installation, hängt sich das Cockpit an die laufende an. Wird das Cockpit währenddessen beendet, läuft sie auf dem Gerät weiter.' }
        @{ T = 'i'; X = '**Parallelbetrieb mit APP- und Treiber-Modul:** eigene Aufgaben und Logs; läuft ein anderes NET-COCKPIT-Tool auf dem Gerät, steht "Anderes NET-COCKPIT-Tool läuft". Der geplante Neustart gilt für alle gemeinsam.' }
        @{ T = 'i'; X = '**Log je Gerät:** C:\Temp\BETA-NET-COCKPIT_data\Modul-OS\yyyyMMdd_Gerät_os-log.txt, im Detailfenster der Reiter Log.' }
        @{ T = 'i'; X = '**Spalte Windows:** die Windows-Version ist unabhängig vom Modul unter Ansicht > Spalten immer einblendbar (standardmäßig ausgeblendet).' }
        @{ T = 'i'; X = '**Gespeicherte Listen:** Verfügbare Updates und Update-Verlauf bleiben je Gerät im Ordner C:\Temp\BETA-NET-COCKPIT_data\Geraeteinfos\Gerätename\OS-Updates.json gespeichert und stehen nach einem Neustart des Cockpits sofort im Detailfenster, mit dem Zeitpunkt **gelesen am** in der Titelzeile. Die Listen können veraltet sein, auch wenn sie erst einen Tag alt sind; ein neues Status prüfen liest sie neu.' }
        @{ T = 'i'; X = '**Gespeicherte Werte:** Windows-Version und Update-Modul bleiben je Gerät gespeichert (NET-COCKPIT-werte.json) und stehen nach dem Laden der Liste wieder in den Spalten. Letzter Neustart, Neustart ausstehend und die Anzahl der Updates werden nicht gespeichert.' }
        @{ T = 'w'; X = 'Noch nicht getestet: Clients und die Uhrzeit-Umrechnung im Update-Verlauf.' }
    ) }
}

# APP-Updates
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['APP'] = {
    @{ Titel = 'APP-Updates'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Sucht und installiert **Programm-Updates (WinGet)** auf den markierten, grünen Geräten, ohne automatischen Neustart. Das Fenster öffnet sich über **Module > APP** und bleibt neben der Tabelle offen.' }
        @{ T = 'h'; X = 'Voraussetzungen' }
        @{ T = 'i'; X = '**Auf jedem Zielgerät einmalig,** in Windows PowerShell 5.1 als Administrator (nicht pwsh): Enable-PSRemoting -Force' }
        @{ T = 'i'; X = '**PowerShell 7 und das Modul Microsoft.WinGet.Client** richtet der Knopf "WinGet-Modul nachinstallieren" ein (das Gerät braucht dafür Internetzugang).' }
        @{ T = 'i'; X = '**Dieser Rechner:** PowerShell 7, ein Konto mit Administratorrechten auf den Zielgeräten, Port 5985 erreichbar.' }
        @{ T = 'h'; X = 'Knöpfe' }
        @{ T = 'i'; X = '**Status prüfen:** Windows-Version, letzter Neustart, Neustart ausstehend, geplanter Neustart, Modul, WinGet-Version, WAU (Ja = normale Installation, Intune = Intune-Variante, Nein), verfügbare Programm-Updates und alle installierten Programme (WinGet, für den Reiter im Detailfenster).' }
        @{ T = 'i'; X = '**App-Updates installieren:** öffnet eine Liste mit den Updates aller markierten Geräte (aus dem letzten Status prüfen, jedes Programm einmal, mit "x von n" Geräten) mit Haken, Alle markieren und Keine markieren. Microsoft.PowerShell ist nicht vorangehakt. Installiert wird nur das Angehakte und nur auf Geräten, die das Update haben; andere Geräte bekommen "Kein gewähltes Update - übersprungen". Geräte ohne Statusdaten: "Bitte zuerst Status prüfen". Still, nie automatischer Neustart; ist einer nötig, steht es im Status (auslösen über Aktionen > Neustart planen).' }
        @{ T = 'i'; X = '**Programm installieren...:** WinGet-Id eingeben, zum Beispiel 7zip.7zip.' }
        @{ T = 'i'; X = '**Installierte Programme anzeigen...:** zeigt die installierten Programme (WinGet) der markierten Geräte gemeinsam in einer Liste mit Suche, Filter "Nur Quelle winget", der Spalte "Gelesen am" und CSV-Export (nur Anzeige, es wird nichts verändert). Gespeicherte Listen erscheinen sofort, auch bei ausgeschalteten Geräten; nur Geräte ohne gespeicherte Liste werden gelesen. Der Knopf **Neu auslesen** in der Liste liest alle Geräte der Liste neu (nur grüne Geräte, die anderen behalten ihre gespeicherte Liste). Nach einer Deinstallation wird die gespeicherte Liste des Geräts gelöscht.' }
        @{ T = 'i'; X = '**Programm deinstallieren...:** liest die installierten Programme eines markierten Geräts, danach ein Programm auswählen und still deinstallieren.' }
        @{ T = 'i'; X = '**WinGet-Modul nachinstallieren:** PowerShell 7 und Modul auf dem Zielgerät einrichten. Danach läuft automatisch Status prüfen für dieses Gerät.' }
        @{ T = 'i'; X = '**WAU installieren...:** ein Dialog mit der Ausschlussliste (vorbelegt mit dem Standardvorschlag, eine WinGet-Id je Zeile, * als Platzhalter) gilt für alle markierten Geräte. Installiert wird Winget-AutoUpdate (Romanitho.Winget-AutoUpdate) mit Updates monatlich und bei Anmeldung und Benachrichtigung nur bei Erfolg; die Liste landet in C:\Program Files\Winget-AutoUpdate\excluded_apps.txt. Geräte, auf denen WAU schon läuft (auch die Intune-Variante), werden übersprungen: "WAU schon vorhanden - übersprungen".' }
        @{ T = 'i'; X = '**WAU-Ausschlüsse bearbeiten...:** liest die Liste der markierten Geräte mit normaler WAU (zuerst Status prüfen), zeigt sie zum Bearbeiten und schreibt sie auf alle markierten Geräte; ohne Neuinstallation. Unterscheiden sich die Listen, steht ein Hinweis im Dialog. Geräte mit der Intune-Variante werden nicht geändert ("Intune-Variante, Liste über Intune pflegen").' }
        @{ T = 'i'; X = '**Details des markierten Geräts...:** verfügbare Updates, installierte Programme (mit Suche und "gelesen am"), Cockpit-Verlauf, WAU-Verlauf und das Log dieses Geräts.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Spalten:** Neustart ausstehend, Letzter Neustart, WinGet-Modul, App-Updates, WinGet-Version und WAU sind nur sichtbar, wenn im Modulfenster der Haken **Spalten des Moduls in der Tabelle anzeigen** gesetzt ist (beim Öffnen immer aus; Ansicht > Spalten blendet sie bis zum nächsten Öffnen oder Schließen von Hand ein oder aus).' }
        @{ T = 'i'; X = '**Nur** maschinenweit installierte Programme aus der Quelle winget.' }
        @{ T = 'i'; X = '**Geräte ohne Domäne oder per IP:** Optionen > Verbindung (TrustedHosts) und ein lokales Konto (Optionen > Konto für markierte Geräte, Gerätename\Benutzer).' }
        @{ T = 'i'; X = '**Parallelbetrieb mit OS- und Treiber-Modul:** eigene Aufgaben und Logs; läuft ein anderes NET-COCKPIT-Tool auf dem Gerät, steht "Anderes NET-COCKPIT-Tool läuft". Der geplante Neustart gilt für alle gemeinsam.' }
        @{ T = 'i'; X = '**WAU-Verlauf:** die letzten 100 Updates aus dem Log von Winget-AutoUpdate. Gesucht wird in C:\Program Files\Winget-AutoUpdate\logs\updates.log (Domänengeräte) und C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\logs\updates.log (Intune-Clients).' }
        @{ T = 'i'; X = '**Log je Gerät:** C:\Temp\BETA-NET-COCKPIT_data\Modul-APP\yyyyMMdd_Gerät_app-log.txt. Auf dem Zielgerät liegen Cockpit-Verlauf (C:\ProgramData\BETA-NET-COCKPIT\WingetVerlauf.csv) und Installationslog (C:\Windows\Temp\NetCockpitAppInstall.log).' }
        @{ T = 'i'; X = '**Spalte Windows:** die Windows-Version ist unabhängig vom Modul unter Ansicht > Spalten immer einblendbar (standardmäßig ausgeblendet).' }
        @{ T = 'i'; X = '**Gespeicherte Listen:** Verfügbare Updates, Verläufe und die Liste der installierten Programme bleiben je Gerät im Ordner C:\Temp\BETA-NET-COCKPIT_data\Geraeteinfos\Gerätename\APP-Updates.json (Updates, Cockpit-Verlauf, WAU-Verlauf) und APP-Programme.json (installierte Programme, wird von Status prüfen und von "Installierte Programme anzeigen" aktualisiert) gespeichert und stehen nach einem Neustart des Cockpits sofort im Detailfenster, mit dem Zeitpunkt **gelesen am** in der Titelzeile. Die Listen können veraltet sein, auch wenn sie erst einen Tag alt sind; ein neues Status prüfen liest sie neu.' }
        @{ T = 'i'; X = '**Gespeicherte Werte:** Windows-Version, WinGet-Modul, WinGet-Version und WAU bleiben je Gerät gespeichert (NET-COCKPIT-werte.json) und stehen nach dem Laden der Liste wieder in den Spalten. Letzter Neustart, Neustart ausstehend und App-Updates werden nicht gespeichert.' }
        @{ T = 'w'; X = 'Das Modul ist noch nicht vollständig auf echten Geräten getestet.' }
    ) }
}

# Treiber-Updates
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['TREIBER'] = {
    @{ Titel = 'TREIBER-Updates'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Sucht und installiert **Treiber-Updates** für **Dell, HP und Lenovo** auf den markierten, grünen Geräten, ohne RDP. Der PC-Hersteller wird je Gerät erkannt und dessen Tool genutzt: Dell Command | Update, HP Image Assistant, Lenovo LSUClient. Andere Hersteller: "nicht unterstützt". Das Fenster öffnet sich über **Module > TREIBER** und bleibt neben der Tabelle offen.' }
        @{ T = 'h'; X = 'Voraussetzungen' }
        @{ T = 'i'; X = '**Auf jedem Zielgerät einmalig,** in PowerShell als Administrator: Enable-PSRemoting -Force. Bei Clients im Netzwerkprofil "Öffentlich" zusätzlich: Enable-PSRemoting -Force -SkipNetworkProfileCheck' }
        @{ T = 'i'; X = '**Das Gerät braucht Internet** (Hersteller-Server, bei der Tool-Nachinstallation PSGallery bzw. WinGet).' }
        @{ T = 'i'; X = '**Dieser Rechner:** PowerShell 7, ein Konto mit Administratorrechten auf den Zielgeräten, Port 5985 erreichbar.' }
        @{ T = 'h'; X = 'Knöpfe' }
        @{ T = 'i'; X = '**Status prüfen:** PC-Hersteller, Modell, Windows-Version, Neustart, Akkubetrieb, Treiber-Tool und Treiber-Updates.' }
        @{ T = 'i'; X = '**Treiber-Updates installieren:** mit Rückfrage, still, nie automatischer Neustart. Ist einer nötig, steht es im Status; auslösen über Aktionen > Neustart planen.' }
        @{ T = 'i'; X = '**Treiber-Tool nachinstallieren:** mit Rückfrage. Dell: ein inkompatibles Altprodukt wird vorher deinstalliert. HP: Ist das PowerShellGet auf dem Gerät älter als 2.2.5 (Windows PowerShell 5.1 liefert eine ältere Version), lädt das Modul eine neuere Version nur vorübergehend in einen temporären Ordner und löscht ihn danach wieder, damit nichts systemweit zurückbleibt; damit wird HPCMSL in einem neuen PowerShell-Prozess installiert (das Gerät braucht Internetzugang zur PSGallery). Danach läuft automatisch Status prüfen für dieses Gerät.' }
        @{ T = 'i'; X = '**BIOS/Firmware einbeziehen:** standardmäßig aus, bei Akkubetrieb Abbruch. Der Schalter gilt für Status prüfen und Installieren.' }
        @{ T = 'i'; X = '**Details des markierten Geräts...:** verfügbare Treiber, Verlauf der Installationen, Tool-Log und das Log dieses Geräts.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Spalten:** Neustart ausstehend, Letzter Neustart, PC-Hersteller, Modell, Treiber-Tool und Treiber-Updates sind nur sichtbar, wenn im Modulfenster der Haken **Spalten des Moduls in der Tabelle anzeigen** gesetzt ist (beim Öffnen immer aus; Ansicht > Spalten blendet sie bis zum nächsten Öffnen oder Schließen von Hand ein oder aus). Die Spalte "Hersteller" des Cockpits ist der Netzwerk-Hersteller aus der MAC-Adresse.' }
        @{ T = 'i'; X = '**Dell:** gezählt werden nur Updates, die dcu-cli selbst meldet (inventarisiert). Nicht inventarisierte Katalog-Einträge stehen als "(+N)" in der Spalte und im Log.' }
        @{ T = 'i'; X = '**Parallelbetrieb mit OS- und APP-Modul:** eigene Aufgaben und Logs; läuft ein anderes NET-COCKPIT-Tool auf dem Gerät, steht "Anderes NET-COCKPIT-Tool läuft". Der geplante Neustart gilt für alle gemeinsam.' }
        @{ T = 'i'; X = '**Aufgaben auf dem Gerät** laufen als SYSTEM und werden nach dem Ende gelöscht. Verlauf und Tool-Log liegen im Ordner C:\ProgramData\BETA-NET-COCKPIT.' }
        @{ T = 'i'; X = '**Log je Gerät:** C:\Temp\BETA-NET-COCKPIT_data\Modul-TREIBER\yyyyMMdd_Gerät_treiber-log.txt' }
        @{ T = 'i'; X = '**Spalte Windows:** die Windows-Version ist unabhängig vom Modul unter Ansicht > Spalten immer einblendbar (standardmäßig ausgeblendet).' }
        @{ T = 'i'; X = '**Gespeicherte Listen:** Verfügbare Treiber, Verlauf und Tool-Log bleiben je Gerät im Ordner C:\Temp\BETA-NET-COCKPIT_data\Geraeteinfos\Gerätename\Treiber.json gespeichert und stehen nach einem Neustart des Cockpits sofort im Detailfenster, mit dem Zeitpunkt **gelesen am** in der Titelzeile. Die Listen können veraltet sein, auch wenn sie erst einen Tag alt sind; ein neues Status prüfen liest sie neu.' }
        @{ T = 'i'; X = '**Gespeicherte Werte:** PC-Hersteller, Modell und Treiber-Tool bleiben je Gerät gespeichert (NET-COCKPIT-werte.json) und stehen nach dem Laden der Liste wieder in den Spalten. Treiber-Updates, Letzter Neustart und Neustart ausstehend werden nicht gespeichert.' }
        @{ T = 'w'; X = 'Noch nicht an echten Geräten getestet (HP, Lenovo).' }
    ) }
}

# Diagnose
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['DIAGNOSE'] = {
    @{ Titel = 'Diagnose'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Zeigt per WinRM **Ereignislog, Dienste und Prozesse** eines Geräts, ohne RDP. Das Fenster öffnet sich über **Module > Diagnose** und bleibt neben der Tabelle offen. Jede Anzeige öffnet ein eigenes Fenster pro Gerät und Art.' }
        @{ T = 'h'; X = 'Voraussetzungen' }
        @{ T = 'i'; X = '**Auf dem Zielgerät:** WinRM aktiv (Enable-PSRemoting -Force) und ein Konto mit Administratorrechten. Das Gerät muss grün sein, es muss genau ein Gerät markiert sein.' }
        @{ T = 'i'; X = '**Konto:** wie bei den anderen Modulen das angemeldete Windows-Konto oder das Konto der Spalte "Konto" (Optionen > Konto für markierte Geräte). Geräte ohne Hostname werden per IP angesprochen, dafür fragt das Cockpit Konto und Kennwort ab (und TrustedHosts, Optionen > Verbindung).' }
        @{ T = 'h'; X = 'Anzeigen' }
        @{ T = 'i'; X = '**Ereignislog...:** Auswahl von Log (System, Application, Security, Setup), Stufe (Kritisch und Fehler, Fehler und Warnungen, Alle) und Zeitraum (1 Stunde bis 30 Tage), höchstens 500 Einträge. Ein Klick auf eine Zeile zeigt die ganze Meldung. Das Filterfeld sucht in allen Spalten.' }
        @{ T = 'i'; X = '**Dienste...:** Name, Anzeigename, Status, Starttyp und Konto. Starten, Stoppen und Neu starten wirken auf den markierten Dienst und fragen vorher nach.' }
        @{ T = 'i'; X = '**Prozesse...:** Name, PID, CPU in Prozent (Messung über eine Sekunde), RAM in MB, Threads und Benutzer. Task beenden wirkt auf den markierten Prozess und fragt vorher nach.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Sortieren:** per Klick auf den Spaltennamen. **Aktualisieren** liest die Liste neu; nach einer Aktion wird die Liste automatisch neu geladen.' }
        @{ T = 'i'; X = '**Warteschlange:** Abfragen laufen wie alle Aufträge über die Warteschlange des NET-COCKPIT (Parallelität in den Optionen). Fehler stehen kurz im Fenster, der volle Text in der Logdatei.' }
        @{ T = 'i'; X = '**Security-Log:** braucht Administratorrechte auf dem Gerät. Das Modul legt keine Spalten in der Tabelle an und speichert nichts.' }
        @{ T = 'w'; X = 'Noch nicht getestet: alle Abfragen gegen echte Geräte, die Fenster und die Spaltendarstellung.' }
    ) }
}

# WaToKi
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['WATOKI'] = {
    @{ Titel = 'WaToKi'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Startet die **Wartungsskripte** aus dem Unterordner **WaToKi** neben dem NET-COCKPIT. Das Fenster öffnet sich über **Module > WaToKi** und bleibt neben der Tabelle offen. Rechts steht die Beschreibung aus dem Kopf des gewählten Skripts.' }
        @{ T = 'h'; X = 'Ablauf' }
        @{ T = 'i'; X = '**Skript wählen, Starten** (oder Doppelklick): Das Skript läuft in einem eigenen PowerShell-7-Fenster. Es läuft immer nur ein Skript gleichzeitig, **Starten** ist bis zum Ende gesperrt.' }
        @{ T = 'i'; X = '**Parameter:** Das Modul liest den param-Block des Skripts (ohne es auszuführen) und übergibt nur, was das Skript kennt. **-Ziel** bekommt die markierten Geräte der Tabelle (Hostname, sonst IP), **-Ausgabeordner** den Ordner Modul-WaToKi im Datenordner, **-Anmeldedaten** das Konto der markierten Geräte (ein Konto für alle), **-AnmeldedatenJeZiel** das Konto jedes markierten Geräts einzeln.' }
        @{ T = 'i'; X = '**Ohne diese Parameter** startet das Skript unverändert und fragt wie bisher selbst nach Gerät und Ablageort.' }
        @{ T = 'i'; X = '**Ausgabeordner öffnen:** öffnet C:\Temp\BETA-NET-COCKPIT_data\Modul-WaToKi im Explorer.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Konto:** Kennt ein Skript den Parameter **-Anmeldedaten**, bekommt es das Konto aus der Spalte "Konto" (Optionen > Konto für markierte Geräte). Das Modul fragt keine Kennwörter ab: Fehlt bei einem Gerät mit Konto das Kennwort (zum Beispiel nach einem Neustart), meldet das Modul die Geräte, nichts startet. Dann das Kennwort im Cockpit pro Gerät setzen und erneut starten. Ohne Eintrag in der Spalte läuft das Skript mit dem angemeldeten Windows-Konto oder fragt selbst. Skripte mit **-AnmeldedatenJeZiel** bekommen für jedes Gerät sein eigenes Konto, Skripte mit nur **-Anmeldedaten** nehmen ein Konto für alle, dort startet bei unterschiedlichen Konten nichts.' }
        @{ T = 'i'; X = '**Übergabe des Kontos:** über eine verschlüsselte Temp-Datei, die nur dein Windows-Konto auf diesem Rechner lesen kann. Der Startbefehl liest sie ein und löscht sie sofort, nach dem Skriptende löscht das Modul sie noch einmal.' }
        @{ T = 'i'; X = '**Param-Block:** Er muss im Skript ganz oben stehen, vor Clear-Host. Sonst erkennt das Modul die Parameter nicht.' }
        @{ T = 'i'; X = '**Spalte Wartungsreihenfolge:** erscheint, wenn im WaToKi-Fenster der Haken **Spalte Wartungsreihenfolge in der Tabelle anzeigen** gesetzt ist (beim Öffnen immer aus), und lässt sich direkt in der Tabelle eintippen (Doppelklick in die Zelle). Der Wert wird mit der Geräteliste gespeichert, die Spalte lässt sich filtern und sortieren (als Text, also 10 vor 2).' }
        @{ T = 'i'; X = '**Log:** Start und Ende eines Skripts stehen im Log des NET-COCKPIT.' }
        @{ T = 'w'; X = 'Noch nicht getestet: Fenster, Starten, Sperre und Parameterübergabe auf einem echten Rechner.' }
    ) }
}

# RDP
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
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

# SSH
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['SSH'] = {
    @{ Titel = 'SSH'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Öffnet für jedes markierte Gerät ein **eigenes PowerShell-Fenster mit ssh.exe** (OpenSSH-Client von Windows, kein Zusatztool). Aufruf über **Module > SSH**.' }
        @{ T = 'h'; X = 'Ablauf' }
        @{ T = 'i'; X = '**Geräte markieren, Module > SSH:** Es erscheint ein kleines Fenster mit den markierten Geräten, dem **Port** (Vorgabe 22, gilt für alle markierten Geräte) und dem Feld **Benutzer für Geräte ohne Konto**. **Verbinden** öffnet je Gerät ein Fenster. Ziel ist der Hostname, sonst die IP-Adresse.' }
        @{ T = 'i'; X = '**Benutzer:** aus der Spalte "Konto" des Geräts, genau so, wie er dort steht (bei Linux-Geräten der SSH-Benutzer). Ist die Spalte leer, gilt der Benutzer aus dem Feld darunter. Ist beides leer, meldet das Fenster die betroffenen Geräte und nichts startet.' }
        @{ T = 'i'; X = '**Kennwort:** Das NET-COCKPIT speichert und übergibt keins. ssh.exe fragt es im jeweiligen Fenster selbst ab, ebenso die Rückfrage zum Hostschlüssel beim ersten Verbinden.' }
        @{ T = 'i'; X = '**Nach dem Ende der Verbindung** bleibt das Fenster offen, bis Enter gedrückt wird, damit Fehlermeldungen lesbar bleiben.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Voraussetzung:** Der OpenSSH-Client ist installiert (Windows: Einstellungen > System > Optionale Features > OpenSSH-Client) und auf dem Gerät läuft ein SSH-Server. Fehlt ssh.exe, sagt das Modul es.' }
        @{ T = 'i'; X = '**Konto mit Domäne:** Steht in der Spalte zum Beispiel DOMÄNE\Benutzer, übergibt das Modul den Namen unverändert an ssh.exe. Ob das Gerät diesen Namen akzeptiert, hängt vom Gerät ab.' }
        @{ T = 'i'; X = '**Port und Benutzer** bleiben nur bis zum Beenden des NET-COCKPIT im Fenster erhalten und werden nicht gespeichert.' }
        @{ T = 'i'; X = '**Log:** Start der Fenster steht im Log des NET-COCKPIT.' }
        @{ T = 'w'; X = 'Noch nicht getestet: Aufruf über das Menü, Fenster mit ssh.exe, Port-Eingabe und mehrere markierte Geräte auf einem echten Rechner.' }
    ) }
}

# Folder-Detective
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['FOLDERDETECTIVE'] = {
    @{ Titel = 'Folder-Detective'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Zeigt **Ordner- und Dateigrößen als Baum**, während der Scan noch läuft: Ordner erscheinen sofort, die Größen wachsen live mit, die Sortierung wird alle zwei Sekunden neu angewendet (offene Ordner bleiben offen). Das Fenster öffnet sich über **Module > Folder-Detective** und bleibt neben dem NET-COCKPIT offen.' }
        @{ T = 'h'; X = 'Scan starten' }
        @{ T = 'i'; X = '**Pfad wählen:** Laufwerk oder Ordner auf dem Rechner mit dem NET-COCKPIT. Der Pfad lässt sich auch ins Feld **Verzeichnis** tippen.' }
        @{ T = 'i'; X = '**Remote Scan:** Laufwerk oder Ordner auf einem anderen Computer. Ein Fenster fragt nach den Zugangsdaten und dem Computer; **Verbinden** lädt die Laufwerke, Ordner lassen sich aufklappen, **OK** übernimmt Computer, Konto und Pfad. Gescannt wird danach mit **Scan starten**. **Remote beenden** schaltet zurück auf den eigenen Rechner.' }
        @{ T = 'i'; X = '**Markiertes Gerät:** Ist im NET-COCKPIT genau ein Gerät markiert, übernimmt das Remote-Fenster dessen Namen (bei Geräten ohne auflösbaren Namen die IP-Adresse) und, wenn in der Spalte Konto eins steht, auch dieses Konto. Fehlt das Kennwort in dieser Sitzung, fragt das NET-COCKPIT danach. Bei keinem oder mehreren markierten Geräten gibt man Computer und Konto von Hand ein.' }
        @{ T = 'i'; X = '**Pause und Abbrechen:** Pause gibt es nur bei lokalen Scans. Abbrechen zeigt das Teilergebnis.' }
        @{ T = 'h'; X = 'Anzeige' }
        @{ T = 'i'; X = '**Spalten:** Größe, Belegt (Platz auf dem Datenträger), Dateien, Ordner, % Anteil, Letzte Änderung und Hinweis. Klick auf eine Spaltenüberschrift sortiert, nochmal klicken dreht die Richtung um.' }
        @{ T = 'i'; X = '**Aufklappen:** Klick auf das Plus-/Minus-Kästchen, Doppelklick auf einen Ordner oder Pfeiltasten Rechts/Links. Ein Doppelklick auf eine Datei macht nichts, es wird nie eine Datei gestartet.' }
        @{ T = 'i'; X = '**Dateipfad öffnen** (Rechtsklick auf eine Zeile): zeigt Ordner oder Datei im Explorer, bei Remote-Scans als Adminfreigabe \\Computer\C$\...' }
        @{ T = 'i'; X = '**Nicht lesbare Ordner:** werden mit "Zugriff verweigert" markiert, der Scan läuft weiter. Der Knopf **Nicht lesbare anzeigen** öffnet eine Liste mit Pfad und Meldung (Rechtsklick: Pfad kopieren).' }
        @{ T = 'h'; X = 'Voraussetzungen und Gut zu wissen' }
        @{ T = 'i'; X = '**Remote Scan:** WinRM (TCP 5985), ein Konto mit Administratorrechten auf dem Ziel und der PowerShell-7-Endpunkt (Sitzungskonfiguration PowerShell.7) auf dem Ziel. Fehlt PowerShell 7 dort, scheitert die Verbindung.' }
        @{ T = 'i'; X = '**Adminfreigabe:** "Dateipfad öffnen" bei Remote-Scans braucht Zugriff auf die Adminfreigabe (zum Beispiel C$) des Ziels.' }
        @{ T = 'i'; X = '**Verknüpfungen:** Junctions und Symlinks werden nicht verfolgt.' }
        @{ T = 'i'; X = '**Log:** Start, Ergebnis und Fehler der Scans stehen im Log des NET-COCKPIT. Das Modul speichert nichts.' }
        @{ T = 'w'; X = 'Noch nicht im NET-COCKPIT getestet: Fenster, lokaler Scan und Remote Scan mit markiertem Gerät auf einem echten Rechner.' }
    ) }
}

# MouseMover
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
$script:ModulInfo['MOUSEMOVER'] = {
    @{ Titel = 'MouseMover'; Bloecke = @(
        @{ T = 'h'; X = 'Was macht das Modul?' }
        @{ T = 'p'; X = 'Bewegt alle **30 Sekunden** den Mauszeiger **1 Pixel nach rechts** und gleich wieder **1 Pixel nach links** und hält Rechner und Bildschirm wach (SetThreadExecutionState), damit der Rechner nicht in den Leerlauf geht. Das Fenster öffnet sich über **Werkzeuge > MouseMover** und bleibt immer im Vordergrund.' }
        @{ T = 'h'; X = 'Bedienung' }
        @{ T = 'i'; X = '**Schiebeschalter:** **I** = an, **O** = aus. Beim Öffnen des Fensters ist der Mouse Mover aus.' }
        @{ T = 'i'; X = '**Aktives Fenster:** das Fenster unter dem Mauszeiger (Titel und Programm), dorthin geht die Bewegung. Bei einem RDP-Tab des NET-COCKPIT steht zusätzlich der Server. Dazu der Countdown bis zur nächsten Bewegung.' }
        @{ T = 'i'; X = '**Fenster schließen** oder das NET-COCKPIT beenden stoppt den Mouse Mover. Es wird nichts gespeichert.' }
        @{ T = 'h'; X = 'Gut zu wissen' }
        @{ T = 'i'; X = '**Lokaler Rechner:** Der Mouse Mover hält den Rechner wach, auf dem das NET-COCKPIT läuft.' }
        @{ T = 'i'; X = '**Bildschirm bleibt an:** Solange der Schalter an ist, meldet das Modul Windows zusätzlich (SetThreadExecutionState), dass Rechner und Bildschirm gebraucht werden. Der Rechner geht dann nicht in den Standby und der Bildschirm bleibt an. Beim Ausschalten, Schließen des Fensters oder Beenden des NET-COCKPIT gilt wieder die normale Energieeinstellung von Windows.' }
        @{ T = 'i'; X = '**RDP-Sitzungen:** Die Bewegung kommt in einer Sitzung nur an, solange der Mauszeiger über dem RDP-Fenster steht. Dann zählt sie dort als Eingabe.' }
        @{ T = 'i'; X = '**Richtlinien:** Eine per GPO erzwungene Sperre kann je nach Richtlinie trotzdem greifen.' }
        @{ T = 'w'; X = 'Noch nicht getestet: Schalter, Bewegung, Anzeige des Fensters unter dem Mauszeiger und Countdown auf einem echten Rechner.' }
    ) }
}

# WOL
## Reiter der Info (Blöcke: h = Überschrift, p = Absatz, i = Listenpunkt, w = Hinweiskasten)
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
        @{ T = 'i'; X = '**Spalten:** Gerät, WoL Netzwerkkarte, Schnellstart und WoL im BIOS sind nur sichtbar, wenn im Modulfenster der Haken **Spalten des Moduls in der Tabelle anzeigen** gesetzt ist (beim Öffnen immer aus).' }
        @{ T = 'i'; X = '**Netzwerkkarte:** Die Änderung läuft ohne Neustart der Karte. Greift sie nicht, hilft ein Neustart des Geräts.' }
        @{ T = 'i'; X = '**BIOS-Kennwort:** Ist eines gesetzt, kann das BIOS nicht geändert werden, das Log nennt den Rückgabewert.' }
        @{ T = 'i'; X = '**Nicht gesetzt oder nicht prüfbar:** Manche BIOS-Versionen haben zusätzliche Optionen für den ausgeschalteten Zustand (zum Beispiel Deep Sleep bei Dell). Diese ändert das Modul nicht.' }
        @{ T = 'i'; X = '**Gespeicherte Werte:** Gerät, WoL Netzwerkkarte, Schnellstart und WoL im BIOS bleiben je Gerät gespeichert (NET-COCKPIT-werte.json) und stehen nach dem Laden der Liste wieder in den Spalten.' }
        @{ T = 'w'; X = 'HP und Lenovo sind noch nicht an echten Geräten getestet. Das Modul ist insgesamt noch nicht vollständig auf echten Geräten getestet.' }
    ) }
}
