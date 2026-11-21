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

**Decizie (2026-11-21): varianta B — o singură bibliotecă `libkde3-qt.so`
care alege X11 sau Wayland la rulare** (un singur build KDE, un singur set de
pachete). Arhitectura: §9.

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
| C. Platforma la rulare (decis: B) | o singură bibliotecă, ABI-ul X11 păstrat, backend-ul Wayland în spatele API-ului public, ales la pornire (§9) | 3–5 săptămâni (Qt) |
| D. kdelibs „X11 opțional” | KApplication, KStartupInfo→xdg-activation, KGlobalAccel→portal, KSelectionOwner→D-Bus, KSystemTray→SNI, NETWM doar cu KWin-compozitor; ținta: KWrite, Konsole, KMail native pe GNOME | 3–5 săptămâni |
| F. KWin ca compozitor Wayland | (1) compozitor nou peste wlroots cu logica de ferestre a KWin3 portată și decorațiile KWin3 (QWidget-uri) rulate ca client Qt3-Wayland intern; (2) pe termen scurt KWin3 rămâne WM X11 într-un Xwayland rootful (etapa 1, funcțională) | (1) 2–3 luni |
| E. kicker/kdesktop | rol nou de suprafață în Qt: `WType_Desktop`/dock → `zwlr_layer_surface_v1`; taskbar pe foreign-toplevel, pager pe ext-workspace, systray SNI | 2–3 săptămâni, după F |

Ordinea recomandată: B → C → D (aplicații native pe GNOME, utile imediat,
inclusiv KMail) → F → E. Sesiunea completă KDE3 rămâne până atunci pe
Xwayland rootful (`wayland-stage0-1.md`).

## 8. Întrebări deschise

- ABI (etapa C): **decis — o singură bibliotecă, platforma aleasă la
  rulare** (§9).
- HiDPI: scalare întreagă prin `buffer_scale` (desen la 2×) vs. lăsat
  compozitorului (încețoșat).
- Rama pe un KWin-compozitor: decorații de server, QWSManager oprit când
  `xdg-decoration` acceptă `SERVER_SIDE`.
- Pe GNOME, aplicațiile KDE native nu au taskbar/pager KDE (nu există
  foreign-toplevel): doar aplicații individuale; sesiunea KDE nativă cere
  propriul compozitor.

## 9. O singură bibliotecă, platforma aleasă la rulare (decizia B)

Revizuit după un review independent (ABI, performanța căii X11,
fezabilitate); corecturile sunt incluse mai jos.

### 9.1 Principii
1. **ABI-ul public rămâne cel X11.** Qt și aplicațiile se compilează cu
   `Q_WS_X11`; nicio clasă publică nu-și schimbă layout-ul, nu apar funcții
   virtuale noi. Se adaugă doar funcții membre private nevirtuale și câmpuri
   la **sfârșitul** structurilor alocate numai de Qt (`QPixmap::QPixmapData`
   — doar date simple, e inițializată cu `memset`; `QWExtra`, `QTLWExtra`;
   `QPainterPrivate`, care pe X11 nici nu e alocat). **Nu** se extinde
   `QPaintDeviceX11Data` (struct public `Q_EXPORT`, construibil din afară).
   Binarele KDE existente rămân valabile pe X11 fără recompilare.
2. **Un flag global, citit o dată:** `bool qt_wayland` (`qplatform_p.h`),
   fixat la începutul lui `qt_init` și niciodată schimbat.
3. **Întâi date, abia apoi ramuri.** Unde codul X11 merge fără server dacă
   staticele au valori potrivite, nu se adaugă nimic:
   - pe Wayland toate staticele `x_app*` și tablourile per ecran
     (`x11AppDepth/Cells/RootWindow/Colormap/Visual(screen)`, inline în
     `qpaintdevice.h`, care altfel indexează tablouri nule) primesc un vizual
     TrueColor 32 bpp fals și DPI 96 (pentru fonturi); doar `x_appdisplay`
     rămâne NULL; `qt_use_xrender = false` oprește singur căile XRender din
     Qt și KStyle;
   - `QColor`: calea TrueColor din `qcolor_x11.cpp` merge fără display cu
     `QColorScreenData` 8/8/8 — fără dispecer;
   - `QRegion`: rămâne **doar** implementarea X11 (algoritmul e propriu,
     Xlib intervine numai în `handle()`); `qregion_qws.cpp` dispare, iar
     QGfx primește un accesor prieten la `QRegionPrivate` (numRects, rects,
     extents). Atenție: QGfxRaster interpreta `handle()` ca propriul
     `_XRegion` — ar fi citit o Region Xlib cu alt layout.
4. **Ramuri doar unde X11 ar chema Xlib**, la intrarea funcției:
   `QT_WL_DISPATCH( return foo_wl( ... ) );` (ramura X11 marcată
   probabilă). Cost pe X11: o comparație cu o globală, perfect predictibilă,
   în funcții care oricum fac apeluri Xlib (begin/end, update pen/brush/font,
   clip, bitBlt, conversii QPixmap, geometria widgeturilor, o iterație de
   buclă). **Primitivele QPainter nu primesc test nou:** un bit `WlDev` în
   `QPainter::flags` (0x80000 e liber) intră în testele existente
   `testf(ExtDev|VxF|WxF)`, deci calea X11 nu plătește nimic. Fonturile au
   deja dispecer: tipul motorului (apel virtual).
5. **Backend-ul Wayland = codul QWS al prototipului, mutat pe layout-ul
   X11:** fișierele `*_qws.cpp` devin `*_wl.cpp` care definesc
   `Clasa::metoda_wl(...)` (funcții private nevirtuale); clasele și
   globalele locale cu nume comune (`QETWidget`, `QClipboardData`,
   `QCursorData`, `QDesktopWidgetPrivate`, `QShapedPixmapWidget`,
   `_XRegion`, `qt_init`, `qt_cleanup`, `bitBlt`, `copyBlt`,
   `qt_button_down`, `qt_set/clear_paintevent_clipping`,
   `qt_draw_background`, `qt_enter/leave_modal`, `qt_modal_state`, timerele,
   handler-ele pre/postselect...) trec **toate** într-un namespace sau
   primesc sufixul `_wl` — altfel simbolurile inline/weak se unesc la link
   și o parte rulează codul celeilalte. Un build de control cu
   `-flto -Wodr` raportează ce a scăpat.
   Starea QWS:
   - `QWidget`: regiunile (`req/alloc/paintable_region`, indexul și
     revizia, `overlapping_children`) și masca → `QWidgetWlData` legată din
     `QWExtra` (pe Wayland fiecare widget are extra); `QWSManager*` și
     `decor_allocated_region` → la sfârșitul `QTLWExtra`;
   - `QPainter`: `QGfx*` → `QPainterPrivate`, alocat numai pe Wayland;
   - `QPixmap`: memoria, `clut`, `numcols`, `rw/rh`, `hasAlpha` → la
     sfârșitul `QPixmapData`; `hd` rămâne 0;
   - virtualele QWS (`graphicsContext/scanLine/bytesPerLine`, `qwsEvent`)
     devin funcții interne care aleg după `devType()`;
   - `WId`-urile Wayland încep de la 0x20000000 (nu pot fi XID-uri valide:
     codul KDE dă `winId()` la Xlib).
6. **Clasele interne QWS** (`QGfx*`, `QScreen`, `QWSDisplay`, `QWSManager`,
   decorațiile, managerul de regiuni, serverul Wayland) se compilează aproape
   neschimbate; `qlock.cpp` și `qregion_qws.cpp` dispar; definițiile
   `QT_NO_QWS_*` din `wayland/gen/qconfig.h` se aplică doar acestor surse.

### 9.2 Pe subsisteme
| Subsistem | X11 (neschimbat) | Wayland (backend) |
|---|---|---|
| Inițializare | `qt_init` X11 | `qt_init`: `qt_choose_platform()`, apoi `qt_init_wl` (staticele false, serverul în proces, ecranul, decorația); constructorii `QApplication(Display*, ...)` forțează X11 |
| Bucla de evenimente | bucla GLib (implicită în configurare) sau cea clasică | un `GSource` Wayland: `prepare` = `wl_display_prepare_read` + flush + `qt_wl_flush()`, `check`/`dispatch` = citire + evenimentele din coada QWS; în bucla clasică același hook în locul blocului X |
| Widgeturi | `qwidget_x11.cpp` | `qwidget_wl.cpp`: doar top-level-urile au suprafețe, copiii sunt regiuni |
| Pictare | `qpainter_x11.cpp` (GC, XRender, Xft) | `qpainter_wl.cpp` (QGfxRaster în memoria clientului), prin bitul `WlDev` |
| Pixmap-uri | Pixmap pe server | memorie în client |
| Fonturi | `QFontEngineXft` | `QFontEngineFT` nou pe clasa de bază X11 (motorul QWS e altă clasă și nu se poate refolosi ca atare) + ramuri în `qfontdatabase_x11.cpp` (inclus în `qfontdatabase.cpp`; ~98 de apeluri Xft/Fc/X, 52 de situri) și în `qfont.cpp` (18). **Etapa 4 din PLAN 7.1 (`QHbFont`) devine calea comună:** aceeași cache de fețe și shaping HarfBuzz pe ambele platforme; desenul diferă (`XftDrawGlyphSpec` vs blit alpha, apoi Cairo) |
| Clipboard, DnD | `qclipboard_x11`, `qdnd_x11` | `qclipboard_wl` (`wl_data_device`, primară); DnD de făcut |
| Cursoare, ecran | `qcursor_x11`, `qdesktopwidget_x11` | `*_wl` (cursor-shape, ieșirile Wayland) |
| OpenGL | GLX | `QGLWidget` invalid pe Wayland (deocamdată) |

Codul comun: ~183 de situri `Q_WS_X11` (cele mai multe inofensive pe
Wayland, pentru că `x11Screen()`/`hd` sunt 0; periculoase: `XSetTransientForHint`
în `qdialog.cpp`, `qsizegrip.cpp`, `x11_initialize_style` din
`qapplication_x11.cpp`, `qpsprinter.cpp`, `qt_xfocusout_grab_counter` din
`qmenubar.cpp`) și ~60 de situri `Q_WS_QWS` (qimage 13, qtextcodec 9,
qpainter 8, qfont 8, qwidget 6) care pe Wayland trebuie să devină ramuri la
rulare. Triere: ~2 zile.

### 9.3 API-uri X11 pe Wayland
`qt_xdisplay()`/`x11AppDisplay()` și `handle()` întorc NULL/0; celelalte
statice au valorile false de la 9.1.3. `x11Event`/`x11EventFilter` nu mai
sunt chemate, deci în KApplication tac KIPC și acceleratoarele globale
(așteptat; vin înlocuitorii din etapa D). Măsurat în surse:
- kdelibs: 38 de fișiere cu `qt_xdisplay/x11Display` (311 apeluri),
  19 cu apeluri Xlib directe, 35 cu NETWM/`KWin::`;
- kdebase: 101 fișiere (746 de apeluri), 48 cu Xlib direct, 56 cu NETWM;
- kdepim: 4 fișiere.
Cea mai mare parte a kdebase (kwin, kicker, kdesktop, ksmserver, kxkb,
khotkeys, klipper, kcontrol/randr, kdm) e oricum X11-only sau înlocuită pe
Wayland. În kdelibs cele ~38 de fișiere primesc gărzi `if (!qt_xdisplay())`
sau ramuri Wayland: 1–2 săptămâni pentru „nu crapă”, plus etapa D pentru
înlocuitori. Un `qt_wayland_display()` nou dă `wl_display*` pentru cine
integrează.

### 9.4 Alegerea platformei
Doar variabila `QT3_PLATFORM=x11|wayland` (fără opțiune în linia de
comandă: `KCmdLineArgs` refuză opțiunile Qt necunoscute). Altfel: **X11
întâi** cât `DISPLAY` e setat (Xwayland în sesiunile Wayland), Wayland dacă
lipsește `DISPLAY` și există `WAYLAND_DISPLAY`, și Wayland ca rezervă când
`XOpenDisplay` eșuează și `WAYLAND_DISPLAY` există. Aplicațiile alese pot
fi pornite cu `QT3_PLATFORM=wayland` din .desktop. Atenție: variabila se
moștenește prin kdeinit/klauncher în procesele copil — fie e scoasă din
mediu după citire, fie klauncher o gestionează explicit (de decis în etapa
D). După etapa D ordinea se inversează pentru `XDG_SESSION_TYPE=wayland`.

### 9.5 Pașii, fiecare verificabil
1. Build-ul X11 din worktree (făcut: `wayland/Makefile.rt`, 0 avertismente)
   și un display X de test fără serverul utilizatorului: Xwayland rootful
   în compozitorul headless (`run-headless.sh --xwayland :84`).
2. Clasele interne QWS și `*_wl.cpp` (redenumite) compilate în biblioteca
   X11 fără să fie chemate; `-flto -Wodr`, `--no-undefined`. Verificare:
   obiectele X11 neschimbate (objdump), `tests/textcheck` și
   `tests/eventloop` identice.
3. `qt_wayland`, alegerea platformei, staticele false, `qt_init_wl`
   (conexiunea și GSource-ul). Verificare: un QApplication fără ferestre
   pornește și iese pe Wayland.
4. QPixmap în memorie, QPainter prin `WlDev`, adaptorul QRegion→QGfx.
   Verificare: desen într-un pixmap, `convertToImage`, PNG comparat pixel cu
   pixel cu același program pe X11 — partea cea mai sensibilă la ABI, fără
   ferestre.
5. Motorul FreeType și ramura din baza de fonturi; același test cu text.
6. Widgeturi top-level cu backing store, regiunile copiilor, QWSManager,
   apoi intrarea, popup-urile și clipboard-ul din prototip. Verificare
   (obiectivul 1): același `libkde3-qt.so` rulează `wltest` pe X11 (`:84`)
   și pe GNOME Wayland headless.
- Regula fără avertismente rămâne: codul QWS importat se curăță
  (`-fpermissive` dispare).
