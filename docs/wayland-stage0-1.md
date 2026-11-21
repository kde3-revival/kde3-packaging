# Wayland, etapele 0 și 1 (PLAN.md 7.2): KDE3 pe Xwayland, headless

Experiment de noapte, 2026-11-21, 04:20–04:45. Totul a rulat într-un mutter
headless (fără monitoare fizice), izolat de sesiunea live de pe `:0`.

**Pe scurt:** pe Xwayland, KDE3 + Qt3 (cu bucla GLib) merg aproape fără
probleme, atât aplicații individuale rootless sub mutter, cât și o sesiune
completă (`startkde`) în Xwayland rootful. Bucla GLib nu consumă CPU în
repaus, iar timerele sunt exacte. Am găsit un singur bug clar în Qt
(drag-and-drop către partea Wayland), reparat pe branch-ul `xwayland-fixes`.
Limitele care contează sunt arhitecturale: rootful înseamnă un singur
monitor, iar HiDPI nu se scalează în Qt3.

## 1. Mediul de test

| Componentă | Versiune / detalii |
|---|---|
| Compozitor | mutter 51.1 `--headless --wayland --virtual-monitor 2560x1440 --virtual-monitor 2560x1440`, sub `dbus-run-session` propriu, cu HOME/XDG_CONFIG_HOME/XDG_RUNTIME_DIR private (`/tmp/kde3wl.rt`) și `GSETTINGS_BACKEND=memory` |
| Xwayland | 24.1.15; rootless pornit de mutter (a ales singur `:1`, plus `:2` pentru „managed services”, pentru că mutter nu are opțiune pentru numărul display-ului); rootful pornit manual pe `:87` |
| Qt | `kde3-qt` 1a30327 (bucla GLib implicită), `lib/` din arborele in-source, nemodificat |
| KDE | stage-ul `/opt/kde3` (nimic nu a fost reconstruit sau instalat acolo) |
| Mediu KDE | `env -i` cu HOME/KDEHOME/KDETMP/KDEVARTMP/XDG_RUNTIME_DIR/ICEAUTHORITY temporare în `/tmp/kde3wl.*` (căi scurte din cauza limitei de 108 caractere pentru socket-urile unix; scratchpad-ul are deja 108). Am pornit de la `run-kde3-xephyr.sh`, dar cu `env -i`, pentru că shell-ul moștenea `SESSION_MANAGER` și `DCOP*` de la sesiunea live (prima aplicație de test a încercat să se înregistreze la ksmserver-ul live, fără succes: „Session management error: Could not open network socket”) |
| Input | `xt` (XTest + interogări X, cu refuz explicit pentru `:0`), `selwatch` (XFixes) |
| Capturi | `magick x:<id>` fereastră cu fereastră, compuse pe un canvas (în modul rootless, root-ul nu are conținut, iar `import` din IM 7.1.2 dă „missing an image filename”); `magick x:root` în modul rootful |

Scripturi, unelte și capturi:
`/home/serghei/Projects/kde3/build/wayland-stage0/`
(`tools/xt.c`, `tools/qt3test.cpp`, `tools/selwatch.c`, `start-mutter.sh`,
`kenv.sh`, `start-rootful.sh`, `shot.sh`, `cpu.sh`; capturile sunt în
`shots/`, logurile în `logs/`). **Atenție: scratchpad-ul e în /tmp, deci
dispare la reboot.** Dacă vrei uneltele pentru harness, copiază-le de acolo.

### Limitarea principală a harness-ului: inputul XTest nu trece prin compozitor
În Xwayland, XTest e procesat intern de Xwayland. Pornit de mutter cu
`-enable-ei-portal`, Xwayland a cerut portalul RemoteDesktop pe bus-ul
privat; nu există, așa că a revenit la vechea cale internă. Consecințe:
- tastele ajung la fereastra cu focus X și click-urile ajung la fereastra
  de sub cursor, **dar mutter nu vede click-urile**: un click pe altă
  fereastră nu îi dă focus. Am schimbat focusul cu `_NET_ACTIVE_WINDOW`
  (source=2, ca un pager), pe care mutter îl respectă. Pe hardware real,
  inputul trece prin compozitor, deci asta nu e un bug KDE;
- nu se poate testa nimic pe partea Wayland: clipboard sau DnD spre
  aplicații Wayland native, tastatura văzută de compozitor.

## 2. Etapa 0: aplicații KDE3 în Xwayland rootless sub mutter (WM = mutter)

### Matricea de test

| Aplicație | Pornește | Randează | Tastatură | Mouse | Clipboard | DnD | Meniuri popup | Tooltip | Note |
|---|---|---|---|---|---|---|---|---|---|
| qt3test (Qt3 pur) ×2 | da | da (`s0-01-qt3test-crop.png`) | da | da | da: CLIPBOARD A→B (`s0-03-clip-crop.png`), PRIMARY la selecția cu mouse-ul | da: A→B, text (`drag: finished`, `drop: got 'dragged-from-A'`) | da: QPopupMenu sub buton, meniul contextual QTextEdit (`s0-06-07-menus.png`) | da (`s0-05-tooltip-crop.png`) | vezi 2.2 și 2.3 |
| konsole | da | da | da (comandă tastată, fișierul scris pe disc) | – | – | – | – | – | |
| kwrite | da | da (`s0-12-kwrite-typed-crop.png`) | da | da | da: kwrite→qt3test (`clipboard: 'kwrite text for clipboard'`) | – | da: File/View (`s0-09`, `s0-11b`) | – | o singură captură cu textul lipsă (`s0-09-kwrite-menu-crop.png`), nereprodusă, probabil o captură prinsă înaintea repaint-ului |
| kate | da | da | – | da (dialogul Session Chooser, Return) | – | – | – | – | fereastra mică (401x297): sesiunea implicită ignoră `-geometry` |
| konqueror (filemanagement) | da | da, inclusiv thumbnails și KDirWatch (`s0-15-konq-crop.png`) | – | da | – | da: fișier → qt3test (`text/uri-list`) | – | – | |
| kcontrol | da | da (`s0-14-mon2-small.png`) | – | – | – | – | – | – | pe monitorul 2, conform `-geometry +3700+100` |
| kmail (fără cont) | da | da: wizardul, apoi fereastra principală (`s0-14-mon2-small.png`) | da (Escape în wizard) | – | – | – | – | – | doar avertismente vechi `KAction::plugAccel` |
| kicker + kdesktop (fără kwin, mutter = WM) | da | da (`hy-01-small.png`, `hy-02-small.png`) | – | da | – | da: konqueror → desktop, meniul Copy/Move pe monitorul 2 (`hy-04-crop.png`) | da: meniul K | – | taskbar-ul vede ferestrele lui mutter (`_NET_CLIENT_LIST`); kdesktop acoperă 5120x1440 |

(– = netestat)

### 2.1 Geometrie multi-monitor, așa cum o vede Qt
```
xinerama active=1 n=2
  xin 0: 2560x1440+0+0
  xin 1: 2560x1440+2560+0
  randr Meta-0: 2560x1440+0+0 0mm x 0mm
  randr Meta-1: 2560x1440+2560+0 0mm x 0mm
qt3test: numScreens=2 isVirtualDesktop=1 primary=0
  screen 0: geom 2560x1440+0+0, screen 1: geom 2560x1440+2560+0
  x11AppDpiX=96 x11AppDpiY=96, mm=1354x381; Xft.dpi nesetat
```
- Popup-urile sunt corect ținute în ecranul lor. La marginea dintre monitoare
  (fereastra la x=2200..2700), meniul contextual de la (2538,1298) s-a
  deschis spre stânga și în sus (2405..2540) și a rămas pe monitorul 0.
  Meniul butonului s-a deschis deasupra butonului, la marginea de jos
  (`s0-16-edge-crop.png`).
- `-geometry` e respectat. Ferestrele fără poziție sunt centrate de mutter
  pe monitorul primar, iar dialogurile pe monitorul părintelui.
- mutter folosește frame-uri proprii (`mutter-x11-frames`), cu o margine
  invizibilă de 14 px: `move(100,100)` pune frame-ul la 86,88 și clientul
  la 100,139. Partea neagră din capturi e umbra frame-ului.
- Fonturi: fără qtrc (HOME temporar), Qt3 alege Helvetica → „Nimbus Sans
  13pt (17px)”. În aplicațiile KDE fonturile vin din kdeglobals.

### 2.2 Clipboard și selecții
- Între clienți X: CLIPBOARD și PRIMARY merg (Qt3↔Qt3, kwrite→Qt3, klipper
  în etapa 1). Notă: în Qt3, `Ctrl+A` în QTextEdit înseamnă „început de
  linie” (emacs), nu „select all”. Primul test a picat din cauza asta, nu
  din cauza Xwayland.
- Spre Wayland: mutter (XWM) face punte între selecțiile X și cele Wayland.
  Netestat pentru că nu există un client Wayland nativ cu focus (nici
  wl-clipboard). Pentru CLIPBOARD/PRIMARY, Qt3 răspunde corect la `TARGETS`
  (verificat cu `selwatch`, cu toate cele trei timestamp-uri), deci puntea
  ar trebui să meargă.

### 2.3 Bug găsit: DnD, `TARGETS` pe XdndSelection (reparat)
La fiecare drag pornit dintr-o aplicație Qt3, mutter scria:
```
libmutter-WARNING **: 04:29:18.509: Could not create selection source for X11: Format TARGETS not supported
```
`selwatch` confirmă:
```
XdndSelection owner 0xa00001 ...
  conv(ev.timestamp)=REFUSED conv(selection_timestamp)=REFUSED conv(CurrentTime)=REFUSED
```
`qt_xdnd_handle_selection_request()` (`src/kernel/qdnd_x11.cpp`) răspundea
doar la tipurile MIME ale obiectului de drag. XDND între clienți X nu cere
niciodată `TARGETS`, deci DnD X↔X merge, dar puntea XWM a lui mutter nu
poate crea sursa de drag pentru Wayland. Reparația răspunde la `TARGETS` cu
formatele obiectului de drag plus `TARGETS`.

Verificat cu libkde3-qt construit în worktree și pus în față prin
LD_LIBRARY_PATH: avertismentul nu mai apare, `TARGETS` → ok, iar DnD
Qt3→Qt3 și konqueror (patch-uit) → kdesktop (nepatch-uit, pe monitorul 2)
merg în continuare (`hy-04-crop.png`). Nu am putut verifica efectiv un drop
într-un client Wayland.

### 2.4 Bucla GLib, CPU și timere (rootless)
`cpu.sh`, 30 s de repaus, cu toate aplicațiile de mai sus deschise
(`logs/s0-cpu-idle.txt`):
- konsole, kwrite, konqueror, kcontrol, kmail, dcopserver, kdeinit:
  **0.00% CPU, 0.0 treziri/s**; kded 0.2/s, klauncher 0.1/s, kate 0.3/s
  (0.03%);
- qt3test (timer de 100 ms): 10.1 treziri/s, 0.03–0.10% CPU, adică exact
  timerul. Precizie: „100 ticks of 100ms in 9999–10001 ms”, constant timp de
  minute, și sub `make -j8` (build-ul Qt a rulat în paralel);
- Xwayland 0.1 treziri/s, mutter 0.

Nimic nu se învârte în gol și nu am văzut blocaje. DCOP (apeluri sincrone),
KIO (kio_file, kio_thumbnail, kio_trash) și KDirWatch (inotify) au mers
normal.

### 2.5 HiDPI (al doilea mutter: un monitor 3840x2160, scale 2)
Am setat scale 2 prin `org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig`
pe bus-ul privat, cu `experimental-features=['scale-monitor-framebuffer',
'xwayland-native-scaling']` (backend keyfile).
- Cu `xwayland-native-scaling`, X vede 3840x2160 nativ, la 96 dpi și fără
  `Xft.dpi`: aplicațiile KDE3 apar la jumătate din mărimea fizică.
- Cu `Xft.dpi: 192` (xrdb pe display-ul de test), fonturile se dublează
  (meniurile kwrite, `hd-01-small.png`, dreapta), dar iconițele, toolbar-ele,
  scrollbar-urile și decorațiile rămân la 1x. Asta e limita știută a lui Qt3
  (nu are device pixel ratio).
- Ciudățenie: aplicația Qt3 pură fără qtrc are fontul implicit în pixeli
  (13pt/17px la 96 dpi → 6pt/16px la 192), deci nu se scalează. Aplicațiile
  KDE au fonturile în puncte și se scalează.
- Fără native scaling (modul implicit din GNOME), mutter scalează fereastra
  Xwayland 2x: mărimea e corectă, dar imaginea e neclară. Nu se poate
  verifica din partea X.

## 3. Etapa 1: sesiune KDE3 completă în Xwayland rootful

`Xwayland :87 -geometry 2560x1440 -fullscreen -noreset -auth …` (client al
mutter-ului headless), apoi `dbus-run-session -- startkde` cu HOME temporar.

| Verificare | Rezultat |
|---|---|
| startkde → kdeinit, dcopserver, klauncher, kded, ksmserver, kwin, kdesktop, kicker, kaccess, knotify, klipper, korgac | toate pornite, desktopul gata în ~40 s cu ksycoca construit de la zero (`s1-01-small.png`) |
| kwin (decorații, focus, taskbar) | da (`s1-03-small.png`) |
| Meniul K (click XTest) | da (`s1-02-kmenu-crop.png`) |
| Run Command → konsole, tastare | da (`session-konsole-ok` scris pe disc) |
| Home din kicker → konqueror | da (`s1-05-konq-crop.png`) |
| DnD konqueror → kdesktop (Copy Here) | da: meniul Move/Copy/Link, fișierul copiat în `~/Desktop` (`s1-06-dnd-desktop-crop.png`) |
| klipper (`dcop klipper klipper setClipboardContents`) → paste în konqueror | da (`s1-08-paste-crop.png`) |
| DCOP/ICE | ok; ICEauthority în HOME-ul temporar (`$ICEAUTHORITY`); ksmserver pe `/tmp/.ICE-unix/<pid>` |
| Layout tastatură | `setxkbmap -layout ro` merge pe partea X (`-query` → ro), cu avertismentul `WARNING: Running setxkbmap against an Xwayland server`. Keymap-ul îl dictează compozitorul și poate fi rescris la următorul `wl_keyboard.keymap`, deci kxkb pe Xwayland e nesigur. Layoutul trebuie setat în compozitor (netestabil headless) |
| Clipboard spre Wayland | nu există punte: pe display-ul rootful nu rulează XWM-ul lui mutter. Netestabil headless, dar așteptat să lipsească |
| Logout `dcop ksmserver ksmserver logout 0 0 0` | curat, toate procesele ieșite în 3 s, „startkde: Done.” |
| CPU în repaus (60 s, `logs/s1-cpu-idle.txt`) | kicker 0.07% (3.1 treziri/s, ceasul), konqueror 0.05%, kdesktop 0.02%, kwin/klipper/ksmserver ~1 trezire/s, restul 0; Xwayland :87 ~0.85%, mutter 0.37% (redesenează fereastra rootful) |

Erori în `logs/s1-session.log`, niciuna specifică Xwayland:
`X Error: BadWindow (invalid Window parameter) 3` ×2 (probabil embed-ul din
systray; de comparat cu Xorg), `pw_context_connect() failed: Host is down`
(knotify/KPulsePlayer, care nu găsește PipeWire pentru că XDG_RUNTIME_DIR e
privat; artefact al testului), `egrep: warning: egrep is obsolescent` ×2
(`startkde`, de pus în curățenia din PLAN 5.7), kio_trash error 11/41 la
primul `Desktop/Trash` (HOME gol).

### 3.1 Multi-monitor în rootful: nu se poate
- `Xwayland -geometry 5120x1440` (fără fullscreen): mutter limitează
  fereastra la un monitor, iar Xwayland își redimensionează root-ul la
  **2560x1440**. RandR: un singur output, `XWAYLAND0`; Meta-0/Meta-1 apar
  „disconnected”. Xinerama: un ecran.
- `-fullscreen -output Meta-1` merge: sesiunea pe al doilea monitor, dar tot
  doar pe unul.
- `-decorate` scade bara de titlu din geometrie (root 2560x1403).

Concluzie: rootful = un singur monitor. Două monitoare ar însemna două
servere X separate, adică două sesiuni. Configurația ta reală (2×2560x1440)
nu poate fi acoperită de etapa 1.

## 4. Ce merge, ce nu merge

**Merge:** randare (Xft, XRender, iconițe, stiluri), tastatură, mouse,
clipboard X↔X, PRIMARY, XDND X↔X (Qt3, KURLDrag, kdesktop), popup-uri și
tooltip-uri poziționate corect pe două monitoare, Xinerama/RandR văzute
corect de QDesktopWidget, DCOP, KIO, KDirWatch, sesiunea completă cu
login/logout, bucla GLib (fără consum în repaus, timere exacte). În plus,
neplanificat: **kicker + kdesktop direct sub mutter**, fără kwin și fără
Xwayland rootful, merge pe ambele monitoare.

**Nu merge sau e limitat:**
1. DnD Qt3 → Wayland: bug Qt, reparat pe `xwayland-fixes` (2.3).
2. HiDPI: doar fonturile, prin `Xft.dpi`. Pentru restul (scalare reală) e
   nevoie de Qt nativ pe Wayland sau de scalarea compozitorului (neclară).
3. Rootful: un singur monitor, fără punte de clipboard spre Wayland, layout
   tastatură dictat de compozitor.
4. Netestat: rezize interactiv (Qt3 nu implementează
   `_NET_WM_SYNC_REQUEST`, deci sub mutter ar putea pâlpâi), startup
   notification, `_NET_WM_PING` (Qt3 îl suportă), kdesktop_lock, kxkb real,
   drop efectiv într-un client Wayland.

## 5. Recomandare pentru pasul următor

1. **Merge-uiește `xwayland-fixes` (3d84a37) după review.** E mic, izolat și
   ajută oriunde rulează KDE3 pe Xwayland (GNOME, KWin 6, sway).
2. **Calea pe termen mediu: „KDE3 rootless pe un compozitor Wayland”,** nu
   rootful. kicker și kdesktop merg deja sub mutter, cu multi-monitor
   corect. Lipsesc WM-ul KDE (decorațiile kwin, regulile) și ksmserver-ul
   fără kwin. Mai departe se poate face fie un profil de sesiune „KDE3 shell
   + mutter/kwin_wayland ca WM” (startkde cu `KDEWM` alternativ), fie, mai
   ambițios, un compozitor mic (wlroots) care să joace rolul lui kwin
   (decorații, `_NET_*`) cu Xwayland rootless. Rootful rămâne doar pentru
   un singur monitor sau pentru demo.
3. **Harness:** ca să poți testa partea Wayland (clipboard, DnD, focus
   real), injectează inputul prin compozitor, nu prin XTest: API-ul
   `org.gnome.Mutter.RemoteDesktop` (EIS) pe bus-ul privat al mutter-ului
   headless, plus un client Wayland mic (wl-clipboard sau un client C de 100
   de linii) ca țintă pentru clipboard/DnD. Uneltele de azi (`xt`,
   `selwatch`, `qt3test`, `cpu.sh`) se pot muta în
   `kde3-packaging/tests/wayland/`.
4. **HiDPI:** până la Qt nativ, de documentat în kcontrol
   („Force fonts DPI” = 192 pentru scale 2) și de evaluat dacă merită un
   factor global de scalare pentru iconițe (KIconLoader) și stil. E mult de
   lucru; mai bine direct în planul Cairo/Wayland.
5. Bucla GLib a trecut primul test larg. Următorul pas e comparația pe
   desktopul real (PLAN 6).

## 6. Branch-uri și commit-uri

- `kde3-qt`, branch local `xwayland-fixes` (din master 1a30327), nepush-uit:
  - `3d84a37 qt_xdnd_handle_selection_request(): answer TARGETS for XdndSelection`
- Worktree-ul de build:
  `/home/serghei/Projects/kde3/build/wayland-stage0/qt-wt`
  (112 MB; dispare la reboot, iar după aceea e nevoie de `git worktree
  prune` în kde3-qt; commit-ul e deja în repo).
- În kdelibs și kdebase: nimic.

## 7. Curățenie
Toate procesele pornite au fost oprite: mutter ×2, Xwayland :1/:3/:87,
dbus-urile private, portalurile și gvfs din bus-ul privat, toate procesele
KDE. Am șters HOME-urile temporare `/tmp/kde3wl.*`, socket-urile/lock-urile
X `:1`/`:2` rămase, socket-urile mele moarte din `/tmp/.ICE-unix` și
montările fuse private. Sesiunea de pe `:0` și `/run/user/1000` nu au fost
atinse. Pe mașină rulau și `Xephyr :82` și `:84` (altă sesiune, „kioimap
test”), plus socket-urile lor DCOP/ICE; le-am lăsat neatinse.
