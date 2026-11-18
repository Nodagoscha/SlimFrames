# SlimFrames

Minimale Unit Frames fuer World of Warcraft: Player, Target, Target-of-Target, Focus und Gruppe (Mitglied 2-5).

- `/slim` oeffnet die Einstellungen (Skalierung, Breite, Klassenfarben, Schrift, Frames verschieben, Testmodus).
- Schriftauswahl: alle Schriften aus LibSharedMedia (falls ein anderes Addon es laedt), sonst die Blizzard-Schriften.
- `/slim test` schaltet den Testmodus um: alle Frames inkl. Gruppe werden mit Beispieldaten gezeigt,
  damit man sie ohne Ziel, Fokus oder Gruppe einstellen kann. Endet automatisch bei Kampfbeginn
  oder beim Schliessen der Einstellungen.
- Player-Frame ist ausgeblendet, solange man nicht im Kampf ist und kein Ziel hat (Fade-out 1 s); bei Mouseover blendet er in 0,3 s ein.
- My-DoTs: ueber dem Target-Frame je ein Balken mit Symbol und Restzeit fuer jeden eigenen Debuff auf dem Ziel (max. 4, z.B. Schlangenbiss).
- Keine Namen auf den Frames; Name & Details zeigt der Tooltip beim Drueberfahren.
- Die Gruppenframes werden als Block verschoben.
- `/slim reset` setzt alle Positionen zurueck.
- `/slim dots` gibt eine Diagnose der My-DoT-Balken im Chat aus.
- Einstellungen werden in `SlimFramesDB` gespeichert.

## Installation

Ordner nach `World of Warcraft/<Version>/Interface/AddOns/SlimFrames` kopieren.
