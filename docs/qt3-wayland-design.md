# Qt3 nativ pe Wayland — design

Stare: prototip funcțional (2026-11-21), branch `wayland-proto` în
`~/Projects/kde3/kde3-qt-wayland` (nepublicat). Starea de lucru și pașii
următori: `build/agent-status/qt3-wayland.md`. Pentru KDE3 pe Xwayland
(etapele 0 și 1) vezi `wayland-stage0-1.md`.

**Pe scurt:** Qt 3.3.8 rulează nativ pe Wayland, fără X11, pornind din
platforma Qt/Embedded (QWS) și înlocuind serverul QWS cu un „server” în
proces care vorbește cu compozitorul. Programul de test (`wltest`: meniuri,
butoane, listă, combo, slider, dialog modal) e complet interactiv pe GNOME:
mouse, rotiță și touchpad, tastatură cu xkbcommon (diacritice, taste moarte,
Compose, repetiție), focus, meniuri/submeniuri/liste ca `xdg_popup` cu grab,
mutare/redimensionare/maximizare prin compozitor, ramă desenată de client cu
butoane, cursoare, clipboard și selecția primară între procese. Verificat
automat (39 de verificări) într-un GNOME Shell headless și manual pe t590
(Fedora 44, GNOME 50.6, hardware real).

Capturi: `build/qt3-wayland-proto/shots3/` (headless, cu `RESULT.txt`) și
`build/qt3-wayland-proto/shots-t590/` (hardware real, plus `rec-resize/`).

## 1. Ruta aleasă: platformă derivată din QWS + strat Wayland

- Sursele QWS lipsesc din importul X11; luate din
  `qt-embedded-free-3.3.8b`. Codul comun e identic cu importul X11 (doar
  `moc_lex.cpp` diferă), deci tot fork-ul compilează cu `-DQWS` practic fără
  modificări (C++11, `-fpermissive` pentru conversiile int↔pointer pe 64 de
  biți din codul QWS).
- QWS aduce exact ce lipsește pe Wayland: pictare software în memorie
  (QGfxRaster), widgeturi copil fără ferestre native (regiuni calculate de
  client), decorații desenate de client (QWSManager), fonturi FreeType.
- Licență: Qt/Embedded Free e GPL2/3 (fără QPL) — compatibil cu fork-ul GPL.
  Codul fox2 (`idk2/fox2/lib/cairo/wayland`) a fost doar referință; nimic nu
  a fost copiat (rama, cursoarele, clipboard-ul sunt scrise din nou).
  Fișierele XML ale protocoalelor sunt MIT.
- Costul: ~2 400 de linii noi (`qwindowsystem_wayland.cpp`,
  `qwsdecoration_wayland.cpp`) și ~380 de linii sub `#ifdef QT_WAYLAND` în
  codul QWS, contra ~12 600 de linii de platformă X11
  (`qapplication_x11`, `qwidget_x11`, `qclipboard_x11`, `qdnd_x11`) care ar
  fi trebuit rescrise pentru un port „Q_WS_WAYLAND” de la zero.

## 2. Arhitectura

```
 aplicație Qt3 ── client QWS (qapplication_qws, qwidget_qws, QWSManager)
                     │  apeluri directe (single process) + cozi de comenzi/evenimente
                     ▼
              QWSServer „în proces” (src/kernel/qwindowsystem_wayland.cpp)
                     │  libwayland-client, xkbcommon, wayland-cursor
                     ▼
                compozitor (mutter/GNOME Shell, KWin, ...)
```

- `QApplication` e mereu `GuiServer` (single process); serverul QWS e
  înlocuit de `qwindowsystem_wayland.cpp` (headerul
  `qwindowsystem_wayland_p.h` ia locul lui `qwindowsystem_qws.h`).
- Fiecare top-level (id de la `QWSDisplay::takeId`) devine `wl_surface` cu
  `xdg_toplevel`, sau `xdg_popup` pentru `WType_Popup` și tooltip-uri.
  Regiunea cerută de client e acordată integral: ferestrele nu se decupează
  între ele, compozitorul le compune.
- Fiecare suprafață are un backing store în memorie (32 bpp = XRGB8888);
  `QWidget::graphicsContext()` pictează în el (QGfxRaster), iar
  `qt_wl_flush()`, chemat înainte ca bucla de evenimente să doarmă, îl
  copiază într-un `wl_shm` liber și face commit, cu `ack_configure` și
  limitat de frame callbacks. Tot acolo se procesează evenimentele Wayland
  deja citite în coadă (`wl_display_dispatch_pending`).
- Coordonate globale virtuale (ca în fox2): Wayland nu are poziții globale,
  QWS le folosește peste tot. Un top-level e „unde l-a pus Qt”; un popup e
  plasat relativ la părintele lui cu un `xdg_positioner`, deci translația
  rămâne exactă. Când compozitorul mută un popup (constrângeri de ecran),
  Qt e anunțat.
- Codul din listener-ele Wayland nu reintră în Qt: închideri, mutări,
  rotița, Leave, schimbările de clipboard sunt amânate cu un timer 0.
- Ce trebuie respectat (bug-uri găsite pe drum):
  - backing store-ul își păstrează conținutul la aceeași poziție virtuală
    când originea regiunii se mută (QWS expune doar ce e nou) — altfel rama
    dialogurilor rămânea neagră;
  - pictarea e decupată la backing store: alocarea QWS se actualizează
    după redimensionare (RegionModified), backing store-ul imediat — altfel
    crash la micșorare;
  - QWSManager pictează rama în backing store, nu pe „ecran”
    (`setGlobalRegionIndex` nu are sens aici);
  - adâncimea 1 bpp trebuie activată: măștile `QBitmap` erau create pe 32
    bpp și pixmap-urile cu mască (iconițe XPM cu „None”) erau invizibile;
  - `QWidget::create` calcula frame strut-ul după mutare (dublat),
    `frameGeometry()` era greșit — bug original Qt/Embedded.

## 3. Intrare, focus, ferestre

| Subiect | Implementare | Verificat |
|---|---|---|
| Pointer | `wl_pointer` → `QWSMouseEvent` (enter, motion, butoane stânga/mijloc/dreapta); la `leave`, widgetul primește `Leave` (`qt_wl_pointer_left`) | hover in/out pe buton, click, drag pe slider, dublu-click |
| Rotiță | seat v8: `axis_value120` (120/treaptă, părți pentru rotițe hi-res); `axis_source` finger/continuous: pixeli acumulați (2,5 unități Qt/pixel, livrat de la 24); orizontal → `Qt::Horizontal`; livrat ca pe X11 (`QETWidget::translateWheelEvent`, propagare la părinți); `wheelScrollLines()` era 0 în QWS | listă derulată cu 3 trepte, în sus, 12 pași mici de touchpad, orizontal; pe t590 la fel |
| Tastatură | keymap de la `wl_keyboard` (xkbcommon), modificatori, repetiție după `repeat_info`, Ctrl+literă → literă pentru acceleratori | „Hello”, BackSpace, Return, 25 de repetiții în 1,2 s |
| Diacritice | keymap-ul compozitorului (schimbat din GNOME în timpul rulării) | `ăâîșț ĂÂÎȘȚ` (headless, layout `ro`) și pe t590 („Factură nr. 12 ăâîșț ĂÂÎȘȚ”) |
| Compose | `xkb_compose` cu tabela locale-ului (`LC_ALL`/`LC_CTYPE`/`LANG`, „C” → en_US.UTF-8); tastele consumate de o secvență nu trimit release | `dead_acute e` → é (us intl), `Compose a e` → æ |
| Focus | `wl_keyboard.enter/leave` → `QWSFocusEvent`; focusul pe un popup rămâne la fereastra lui; mutter ia tastatura cât mută/redimensionează fereastra, deci focus-out-ul e amânat până la sfârșitul operației (altfel bara de titlu devine inactivă) | fereastra nouă și dialogul modal primesc focus; titlul rămâne activ în resize |
| Activare | `xdg-activation-v1`: prima fereastră folosește `$XDG_ACTIVATION_TOKEN`; ferestrele ulterioare și `setActiveWindow()` cer un token cu serialul ultimei intrări și suprafața noastră cu focus | implementat; pe GNOME focusul a venit oricum |
| Popup-uri | `xdg_popup` cu `xdg_positioner` relativ la părinte; `WType_Popup` cere grab; un popup cu grab e copilul celui mai de sus popup cu grab (submeniurile); grab-ul folosește **serialul ultimei apăsări de buton/tastă** (mutter compară cu `grab_serial` al implicit grab-ului: serialul unui enter sau release dă `popup_done` imediat); `popup_done` închide meniul | File, Edit→More→Beta, combo, meniu contextual, click în afară închide meniul, tooltip; pe t590 la fel |
| Mutare | apăsare pe titlu, iar după 4 px de drag `xdg_toplevel.move` (astfel dublu-click-ul ajunge la QWSManager) | 356,190 → 206,110 |
| Redimensionare | marginea de 4 px și colțurile → `xdg_toplevel.resize`; `configure` → `resize()` cu rama stării noi | colț +100,+60 → 660x480 în 14 pași; pe t590 fiecare configure e urmat de un frame (rata e dată de intrare, ~16/s la drag-ul harness-ului) |
| Maximizare | dublu-click pe titlu sau buton → `set/unset_maximized`; maximizat, rama pierde marginea și butonul devine „restaurare” | 1280x744 headless, 1920x1056 pe t590 |
| Minimizare | `xdg_toplevel.set_minimized` | – |
| Închidere | butonul ramei și `xdg_toplevel.close` → `QWidget::close()` | aplicația iese cu 0 (headless și t590) |
| Cursoare | `wp_cursor_shape_v1` dacă există; altfel tema `wl_cursor` (`$XCURSOR_THEME`, `$XCURSOR_SIZE`, nume freedesktop + vechile nume X11); `BlankCursor` ascunde | I-beam, săgeți de resize, în ambele moduri (`QT_WAYLAND_NO_CURSOR_SHAPE=1` forțează tema) |
| Clipboard | `wl_data_device`: sursa noastră oferă formatele QMimeSource plus aliasurile text X11 (`text/plain;charset=utf-8`, `UTF8_STRING`, `TEXT`, `STRING`); oferta celuilalt client e un QMimeSource citit prin pipe (poll 2 s); cât timp suntem proprietari, QClipboard răspunde local, fără compozitor | copy/paste între două procese, în ambele sensuri; pe t590 cu clipboard-ul GNOME, în ambele sensuri |
| Selecția primară | `zwp_primary_selection_v1`, același cod; `supportsSelection()` e adevărat dacă protocolul există | selecție cu mouse-ul într-un proces, click mijloc în celălalt (headless și t590) |
| Drag and drop | ofertele de drag sunt refuzate | de făcut |

### Rama (decorația)
GNOME nu are decorații de server (`xdg-decoration` lipsește în mutter), deci
fiecare top-level e încadrat de QWSManager cu `QWSWaylandDecoration`
(`qwsdecoration_wayland.cpp`): bară de titlu de 24 px cu gradient din
culorile paletei (activ/inactiv), iconița ferestrei (meniul ferestrei),
titlul îngroșat, butoanele minimizare/maximizare-restaurare/închidere
desenate cu primitive QPainter (hover; închiderea devine roșie), margine de
4 px pentru resize. Pe compozitoarele cu `xdg-decoration` se cere oricum
`CLIENT_SIDE`. Cu un KWin-compozitor rama ar trebui să fie a lui KWin
(`SERVER_SIDE`), iar QWSManager oprit.

## 4. Text și imagini

- Text: motorul FreeType din QWS; familiile vin din fontconfig
  (`QFontManager` listează fonturile scalabile, `FcFontMatch` pentru nume).
  Diacriticele românești se văd corect în titlu, meniuri, liste, status bar.
  Defect: în QLineEdit accentele majusculelor (Ă Â Î) sunt tăiate sus
  (ascent-ul raportat nu include accentele).
- QGfxRaster nu are antialiasing pentru forme; textul e randat de FreeType
  cu alpha. Plan: shaping cu HarfBuzz (comun cu X11, `QHbFont`), glife
  FreeType în blit-uri alpha QGfxRaster; mai târziu un QGfx peste Cairo.
- `QImage`/`QPixmap` sunt în memorie; pixmap-urile cu mască merg după
  activarea adâncimii 1, cele cu canal alpha merg (InlineAlpha).
- Scalare: nu e implementată (fără `wl_surface.set_buffer_scale`, fără
  fractional-scale). Pe HiDPI: `buffer_scale` întreg și desen la 2× în Qt
  (fonturi și metrici dublate) — de decis.
- Performanță: la fiecare commit se copiază toată suprafața (fără damage
  tracking); pe t590 redimensionarea a ținut pasul cu fiecare configure.

## 5. Mediul de test

- `wayland/test/run-headless.sh [--mutter] scenario.py ...`: GNOME Shell
  (implicit) sau mutter `--headless --virtual-monitor 1280x800`, într-un
  `dbus-run-session` propriu, cu `XDG_RUNTIME_DIR`, `XDG_CONFIG_HOME` (deci
  și dconf), `XDG_DATA/CACHE/STATE_HOME` private; `DISPLAY` șters, fără
  Xwayland. Sesiunea și setările utilizatorului nu sunt atinse.
  `XDG_RUNTIME_DIR` trebuie să fie scurt: socket-ul Wayland are maxim 108
  caractere (sub scratchpad, gnome-shell moare la pornire).
- `wayland/test/wldrive.py`: intrare reală prin API-ul D-Bus
  `org.gnome.Mutter.RemoteDesktop` (dispozitive virtuale: clientul primește
  `wl_pointer`/`wl_keyboard` adevărate — spre deosebire de XTest în
  Xwayland). Fără stream ScreenCast nu există mișcare absolută, așa că
  pointerul e împins în colțul stânga-sus și mutat relativ (dispozitivele
  virtuale nu au accelerație). Tastele merg ca keysym-uri (keysym-ul
  „legacy” unde keymap-ul îl folosește, de ex. `abreve` pentru ă); mutter
  alege tasta și nivelul, dar nu un nivel care cere Shift cu AltGr — pentru
  majusculele cu diacritice driverul apasă Shift. Poziția ferestrei vine din
  `wl_pointer.enter` (urma `QT_WAYLAND_DEBUG=1`), pozițiile widgeturilor
  din liniile `GEOM:` tipărite de wltest.
- Capturi reale ale compozitorului: `org.gnome.Shell.Screenshot` e permis
  doar unor nume de bus; pe bus-ul privat driverul deține
  `org.gnome.SettingsDaemon.MediaKeys`, care e pe listă.
- Layout-uri de tastatură: `gsettings set org.gnome.desktop.input-sources
  ...` în sesiunea privată (dconf privat); GNOME trimite keymap-ul nou.
- `wayland/test/scenario.py`: 39 de verificări (pointer, tastatură, rotiță,
  popup-uri, ramă, cursoare, clipboard, închidere) cu capturi.
- Hardware real: t590 prin `ice-harness` (`launch --remote`, `--screen`
  click/type/scroll, `screenshot --scope screen`, `record`); construit
  nativ pe t590 în ~40 s (deps: `wayland-devel libxkbcommon-devel
  fontconfig-devel freetype-devel libpng-devel cups-devel`; fișierele moc
  copiate, cu căile include rescrise). `window info`/`screenshot` pe
  fereastră nu merg pentru ferestre Wayland native (harness-ul cunoaște doar
  ferestre X11): se lucrează în coordonate de ecran.

## 6. API-uri X11 folosite de KDE3 și înlocuitorii lor

| Folosit în KDE3 | Pentru ce | Pe Wayland |
|---|---|---|
| `qt_xdisplay()`, `x11AppDisplay()`, `QWidget::handle()`, atomi X | peste tot în kdelibs/kdebase | kdelibs „X11 opțional”: ramuri `#ifdef` sau no-op-uri, după decizia de ABI (etapa C) |
| NETWM (`netwm.cpp`, `KWin::windowInfo`, `KWinModule`) | taskbar, pager, stări ferestre | `ext-foreign-toplevel-list-v1`/`zwlr_foreign_toplevel_management_v1` + `ext-workspace-v1` într-un KWin-compozitor; GNOME nu le are |
| `KStartupInfo` | feedback de pornire, focus pentru ferestre noi | `xdg-activation-v1` (`XDG_ACTIVATION_TOKEN`, deja în Qt) |
| `KGlobalAccel` (`XGrabKey`) | scurtături globale | portalul `org.freedesktop.portal.GlobalShortcuts` (GNOME îl are) sau un protocol al KWin-ului nostru |
| `KSelectionOwner`/`KSelectionWatcher` | „există deja un manager” (systray, WM, compozitor) | nume D-Bus / DCOP |
| XEmbed systray (`KSystemTray`) | iconițe în tavă | StatusNotifierItem (D-Bus); kicker gazdă SNI |
| `KXMessages`, `KXErrorHandler` | mesaje între clienți | DCOP/D-Bus |
| XDND, `QDragObject` | drag and drop | `wl_data_device` enter/motion/drop (etapa B) |
| XRandR (kcontrol), XKB (kxkb) | ecrane, layout-uri | ale compozitorului: `wlr-output-management` în KWin; pe GNOME, setările GNOME |
| kicker, kdesktop | panou, desktop | **layer-shell** (`zwlr_layer_shell_v1`): panou ancorat pe o margine cu zonă exclusivă, desktop pe stratul background. mutter nu îl are → kicker/kdesktop nativi cer KWin-compozitor (sau un compozitor wlroots) |
| KWin (WM X11) | ferestre, decorații | KWin ca compozitor Wayland (etapa F) |

## 7. Plan pe etape

| Etapa | Conținut | Estimare |
|---|---|---|
| A. Prototip Qt (făcut) | platforma QWS+Wayland, intrare completă, popup-uri, ramă, cursoare, clipboard + primară, activare, test headless + t590 | – |
| B. Qt complet | DnD, damage tracking, `buffer_scale`/HiDPI, text-input-v3 (IME), `set_parent` pentru toate dialogurile, `show_window_menu`, `showMaximized/FullScreen/Minimized` din Qt → xdg, fonturi (HarfBuzz, accentele tăiate), AA pentru forme, `QWidget::grabMouse/Keyboard` (nu există pe Wayland: emulate în proces) | 2–3 săptămâni |
| C. Decizia de ABI | bibliotecă separată `libqt-wl` (ABI `Q_WS_QWS`, KDE compilat de două ori) **sau** o singură bibliotecă cu platforma aleasă la rulare (X11 sau Wayland), cu `Q_WS_X11` păstrat pentru API și stub-uri pe Wayland. A doua e mai grea în Qt (două backend-uri de pictare și evenimente în același binar), dar evită dublarea kdelibs/kdebase | decizie + 1–2 săptămâni |
| D. kdelibs „X11 opțional” | KApplication, KStartupInfo→xdg-activation, KGlobalAccel→portal, KSelectionOwner→D-Bus, KSystemTray→SNI, NETWM doar cu KWin-compozitor; ținta: KWrite, Konsole, KMail native pe GNOME | 3–5 săptămâni |
| F. KWin ca compozitor Wayland | (1) compozitor nou peste wlroots cu logica de ferestre a KWin3 portată și decorațiile KWin3 (QWidget-uri) rulate ca client Qt3-Wayland intern; (2) pe termen scurt KWin3 rămâne WM X11 într-un Xwayland rootful (etapa 1, funcțională) | (1) 2–3 luni |
| E. kicker/kdesktop | rol nou de suprafață în Qt: `WType_Desktop`/dock → `zwlr_layer_surface_v1`; taskbar pe foreign-toplevel, pager pe ext-workspace, systray SNI | 2–3 săptămâni, după F |

Ordinea recomandată: B → C → D (aplicații native pe GNOME, utile imediat,
inclusiv KMail) → F → E. Sesiunea completă KDE3 rămâne până atunci pe
Xwayland rootful (`wayland-stage0-1.md`).

## 8. Întrebări deschise

- ABI (etapa C) — de decis înainte de orice lucru în kdelibs.
- HiDPI: scalare întreagă prin `buffer_scale` (desen la 2×) vs. lăsat
  compozitorului (încețoșat).
- Rama pe un KWin-compozitor: decorații de server, QWSManager oprit când
  `xdg-decoration` acceptă `SERVER_SIDE`.
- Pe GNOME, aplicațiile KDE native nu au taskbar/pager KDE (nu există
  foreign-toplevel): doar aplicații individuale; sesiunea KDE nativă cere
  propriul compozitor.
