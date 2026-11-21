# kde3-revival — planul proiectului

Starea la 2026-11-21 și planul de lucru, scris ca să poată fi continuat pe
altă mașină (fără memoria sesiunii anterioare). Tot ce e aici e și decizie
luată de proprietar, nu doar propunere, cu excepția celor marcate „propunere”.

## 1. Scop

- KDE 3.5 (DE-ul propriu-zis + KMail, KOrganizer, KAddressBook, un Kontact
  minimal) pe sisteme moderne: Linux și FreeBSD/OpenBSD/NetBSD, X11.
- NU reînviem tot ecosistemul KDE3; multe aplicații sunt depășite.
- Qt 3.3.8b propriu (kde3-qt) curat de warning-uri peste tot (inclusiv tools,
  examples, designer, assistant, linguist).
- Pe termen lung: modernizări (secțiunea 7), inclusiv Wayland.

## 2. Repo-uri (organizația GitHub `kde3-revival`, remote SSH)

| repo | conținut | master la 2026-11-21 |
|---|---|---|
| kde3-qt | Qt 3.3.8b întreținut | d59dedc |
| kde3-kdelibs | kdelibs 3.5.10, port CMake | 401c056 |
| kde3-kdebase | kdebase 3.5.10, port CMake | f85b546 |
| kde3-kdepim | kdepim 3.5.10 redus, port CMake | b12fbb9 |
| kde3-packaging | pachete Arch/Fedora + acest plan | vezi git log |

- Licențe: cele originale (Qt: GPL2/GPL3/QPL; KDE: ale fiecărui fișier).
  Contribuțiile sub aceleași termene.
- Primul commit din fiecare repo e importul nemodificat al tarball-ului
  oficial (Qt 3.3.8b; KDE 3.5.10 din download.kde.org/Attic/3.5.10/src/).
- Nu se rescrie niciodată istoria unui master publicat.
- Vechea muncă (2012–2022: snapshot-uri kdelibs/kdebase/kdepim 20220407, Qt cu
  migrare spre Qt4/5, triq) e în `~/Projects/kde3/ref/` pe mașina veche, doar
  ca referință. Nu se fac cherry-pick-uri de acolo.

## 3. Metoda de lucru

- Un commit pentru fiecare reparație, cu mesaj explicativ (subiect + corp:
  cauză, efect, verificare).
- Reparațiile care trebuie să păstreze comportamentul (warning-uri, build) se
  verifică prin compararea codului mașină înainte/după (`objdump -d
  --no-show-raw-insn`/`cmp`); acceptabile doar diferențe de `__LINE__` și
  șiruri de cale.
- Orice schimbare de comportament sau bug real: commit separat, explicat.
- Categorii riscante (paranteze, switch-uri, fall-through) și orice cod de
  securitate: un agent face, alt agent face review adversarial; push doar după
  review. La securitate s-a dovedit că sunt necesare mai multe runde.
- `[[fallthrough]];` pentru fall-through intenționat.
- Standardul C++: cel implicit al compilatorului (gcc 16 → C++20); nu e nevoie
  de compatibilitate C++98.
- ABI-ul Qt poate diverge de Qt 3.3.8 dacă asta repară un bug (bibliotecile au
  nume proprii, vezi 4.1).
- Istoria trebuie să fie bisectabilă: reparațiile de compilare vin înaintea
  commit-ului care construiește directorul respectiv.
- Mai mulți agenți în paralel: fiecare pe display X propriu (`:51`… — de
  preferat Xvfb, nu Xephyr care apare pe desktop), fiecare în worktree/
  director de build propriu, nimeni nu instalează în stage-ul de test fără
  acord. Pe mașina veche `/home` era aproape plin: agenții se opresc sub 5 GB.

## 4. Starea tehnică

### 4.1 kde3-qt
- Construit cu `./configure` (fără argumente; `echo yes |` pentru licență) +
  `make -j$(nproc)`; în arbore nu trebuie variabile de mediu. Instalare:
  `-prefix /opt/kde3-qt`.
- Biblioteci: `libkde3-qt.so.3` (threaded), `libkde3-qui.so.1`, `kde3-qt.pc`;
  build key-ul pluginurilor începe cu „kde3-revival”.
- Doar Linux + *BSD, X11, g++. Platformele Win/Mac/QWS/Unix-uri vechi scoase
  (etapele 1–3). **Etapa 4 (ramurile `#ifdef` din codul comun) e amânată
  intenționat**: ramurile acelea sunt harta pentru viitorul port Wayland.
- Biblioteci de sistem (zlib, libpng 1.6, libjpeg, libmng); fără sqlite, fără
  NIS. Build 0 warning-uri (inclusiv cu flagurile Fedora: LTO, FORTIFY=3,
  format-security). RUNPATH relativ la `$ORIGIN`.
- Parserul moc regenerat cu bison 3.8.2 / flex 2.6.4 (`src/moc/README`).
- Buclă de evenimente GLib opțională: `./configure -glib-eventloop` (implicit
  oprită; fără ea, codul e identic cu bucla select()). `QT_GLIB_EVENTLOOP` în
  qconfig.h. Teste: `tests/eventloop/run.sh` (99/103 verificări). Bucla
  aparține firului aplicației; vezi README.
- Bug-uri cunoscute, nereparate:
  - `QPaintDevice::x_appdisplay` nu e resetat după distrugerea QApplication
    (getter-ele DPI din destructori statici folosesc un Display închis).
  - Ecran X raportat 0×0 (monitor oprit) → top-level-urile sunt limitate la
    un dreptunghi gol, XCreateWindow dă BadValue.
  - `RRScreenChangeNotify` reîncarcă geometria ecranelor doar dacă se
    schimbă dimensiunea totală (rearanjarea monitoarelor nu e prinsă).
  - Ștergerea unui QWorkspace vizibil cu copii → crash în windowMode().
  - `make install` cu prefixul în directorul de build + INSTALL_ROOT scrie
    `.prl`-urile pe căi greșite (nu afectează pachetele).
  - Patru bug-uri în motorul de text (în curs de reparare la predare):
    `qpainter_x11.cpp:~3056` scriere în afara heap-ului (`items[size]`),
    `qtextengine.cpp:~1144` (`pos+len` în loc de `pos+ilen`),
    `qtextengine.cpp:~954` (copiere logClusters peste dimensiune),
    `qtextengine_unix.cpp:~82` (ascent/descent înaintea verificării motorului).
  - Opțional: `QPopupMenu::adjustSize()` reimplementat ca `updateSize(TRUE)`
    (ar ajuta toate meniurile poziționate după dimensiune; kicker are deja
    reparația locală).

### 4.2 KDE (kdelibs, kdebase, kdepim)
- Build CMake (Ninja). kdelibs exportă pachetul `KDE3Libs`
  (`find_package(KDE3Libs 3.5 REQUIRED)`; ținte `KDE3::…`; macro-uri
  `kde3_add_library/module/kdeinit_executable/executable`, `.skel/.stub/.ui/
  .kcfgc`, `kde3_use_dcopidlng`, `kde3_install_icons`, `kde3_install_time_path`,
  `KDE3_TOOL_LAUNCHER`). Consumatorii moștenesc prefixul (`/opt/kde3`),
  flagurile, RPATH-ul (`$ORIGIN` + `/opt/kde3/lib` + libdir-ul Qt) și
  directoarele de instalare. Instalarea reproduce fișier cu fișier ce instala
  autotools (verificat cu scripturi).
- Configurări de staging folosite: `-DKDE3_QT_RPATH=<qt-in-arbore>/lib`,
  `-DKDEBASE_KONSOLE_FONTS=OFF` dacă lipsește bdftopcf.
- Ce s-a scos: aRts (knotify redă prin PulseAudio/PipeWire cu KPulsePlayer,
  rezervă playere externe pw-play/paplay/aplay), libltdl (dlopen direct, fără
  `.la`), kjava, kcert, kab, kspell2, kmdi, libkmid, kunittest, teste,
  libkdefakes, kdecore/malloc, kdeprint în afară de CUPS (CUPS e singurul
  backend), kimgio jp2/exr, kthemestyle; în kdebase nsplugins, kpersonalizer,
  ktip, kappfinder, knetattach, kpager, kdcop, kdebugdialog, kdeprintfax,
  module kcontrol/kioslave depășite; din kdepim tot ce nu e KMail, KOrganizer
  (+korgac), KAddressBook, Kontact minimal, Kleopatra, kmailcvt.
- Securitate (kssl): OpenSSL 3/4, magazinul de CA al sistemului (bundle-ul
  propriu din 2008 eliminat; doar `ksslcalist` local al utilizatorului),
  SNI, potrivirea hostname-ului după RFC 6125 cu libpsl opțional, CVE-2009-2702
  și injecția prin „/” în subiect reparate, fallback-ul CNAME eliminat,
  `SSL_OP_IGNORE_UNEXPECTED_EOF`.
- DCOP: rămâne pe ICE; fișierul ICEauthority se găsește după regula libICE
  (`$ICEAUTHORITY`, `$XDG_RUNTIME_DIR/ICEauthority`, `~/.ICEauthority`).
- KCrash: `prctl(PR_SET_PTRACER)` pentru drkonqi (Yama ptrace_scope=1).
- Iconițe SVG prin librsvg (`KDE3_WITH_SVG`), fără modulele GIO.
- kicker: meniul K nu mai acoperă panoul; fără crash la aplicații necunoscute
  în „Most Used”.
- kdepim: gpgme 2.x (listarea trust items nu mai există), sursele libical
  generate reproductibil.

### 4.3 Pachete (repo-ul acesta)
- `./build.sh <arch|fedora> <pachet>` și `./build.sh test …` în containere
  podman curate; ordinea kde3-qt → kde3-kdelibs → kde3-kdebase → kde3-kdepim.
- `bump.sh <pachet> [commit]` mută un pachet pe alt commit.
- Fedora: subpachete `-devel`, kde3-qt `-designer`/`-doc`, `kde3-kdm`.
- Sesiunea: `/usr/share/xsessions/kde3.desktop` („KDE 3.5”); PAM `kde3`,
  `kde3-np`. KDE3 cere `xorg-server` (X11).
- La predare: pachetele kdepim în lucru (testul `ktnef --help` pica; ktnef nu
  mai e program, doar bibliotecă).

### 4.4 Testare locală (mașina veche)
- Stage combinat: `build/stage/opt/kde3` (kdelibs+kdebase+kdepim); `/opt/kde3`
  era symlink spre el. **Înainte de a instala pachetele, symlink-ul trebuie
  șters.**
- `build/run-kde3-xephyr.sh [display] [WxH]`: sesiune KDE3 în Xephyr, cu HOME
  și KDEHOME temporare (nu atinge home-ul real), `-noreset`.
- Atenție: kcontrol scrie `~/.fonts.conf` (citit de toate aplicațiile, deci și
  de GNOME) și `~/.qt/qtrc`.

## 5. De făcut imediat (ordine propusă)

1. ~~Reparațiile de text din kde3-qt~~ — făcut (0313335; bug-ul 4 e cod mort
   pe X11). Pachetul kde3-qt e încă la e3806fb.
2. ~~Pachetele kdepim~~ — făcut (8179594). Repo-ul kde3-kdepim e privat:
   sursa vine din clona locală (`CLONE=../kde3-kdepim ./bump.sh kde3-kdepim`).
   De făcut: bump kde3-kdelibs la 401c056 și kde3-qt la master.
3. Prima sesiune reală pe mașina fizică (vezi 6): GDM 51 pe Arch încă pornește
   sesiuni X11 (`gdm-x-session`) dacă `xorg-server` e instalat; altfel LightDM
   sau `startx /opt/kde3/bin/startkde` din TTY.
   **Făcute în noaptea 21.11 (de instalat și testat pe sesiunea reală):**
   - Indexurile KMail (pct. 4): kdepim 0110a10…788be9c, cu două review-uri
     adversariale; scanarea read-only a celor 107 indexuri reale: niciunul
     respins. SQLite nu mai pare necesar. Teste: build/kmailidx-tests/.
   - IMAP după standby: kdelibs 49ad130 (keepalive + TCP_USER_TIMEOUT pe
     slave-uri), kdepim 2b7cde1…069a234 (kio_imap4 renunță la conexiuni
     moarte, BYE, o singură eroare; KMail deconectează la PrepareForSleep și
     verifică la 10 s după trezire). Teste: build/kioimap-tests/.
     Rămase minore: put() trimite încă două erori la ruperea înainte de „+”;
     BYE fără închidere așteaptă ResponseTimeout; anularea la somn poate
     redeschide conexiunea la IMAP online; alte dialoguri modale (parolă,
     Reset & Sync) încă rulează somnul/trezirea în bucla lor.
   - ksmserver ICEauthority (pct. 6): kdebase 58afadc.
   - startkde fără mkfontdir/xset fp (pct. 7, parțial): kdebase 3f21213.
   - Wayland etapele 0/1: docs/wayland-stage0-1.md; Qt 3d84a37 (TARGETS pe
     XdndSelection).
4. KMail: indexurile maildir corupte după cădere de tensiune/crash (analiză
   2026-11-21, kdepim, nereprodus încă). Întâi reparăm sistemul actual; doar
   dacă tot avem probleme trecem la SQLite (vezi 7.4). Câte un commit:
   - `kmmsgdict.cpp` `appendToFolderIds()`: offset-ul cu `sizeof(ulong)` (8 pe
     x86_64) în loc de `sizeof(Q_UINT32)`; în plus `count` e folosit după
     re-swap. Strică `.index.ids` la fiecare mesaj nou; `updateIndex()` doar
     îl atinge (`utime`) dacă folderul nu e dirty, deci rămâne stricat;
   - `readIndex()`/`getStringPart()`: nicio verificare
     `offset+len <= dimensiunea fișierului` (`fseek` trece de EOF, `mmap`
     citit în afara limitei → SIGBUS/mesaje fantomă) → reconstruire automată
     din maildir în loc de crash;
   - indexul e validat doar după mtime, iar `updateIndexStreamPtr()` face
     `utime` pe folder/index/ids → index nesincronizat pare proaspăt;
     propunere: antet cu flag curat/murdar (murdar înainte de prima scriere
     pe loc, curat după `fsync` la închidere);
   - scrierile pe loc (`syncIndexString`, adăugarea în `addMsg`) fără
     `fsync`; `writeIndex()` ignoră rezultatul `rename` și nu face `fsync`
     pe director;
   - `mmap`-ul nu e refăcut după adăugarea de mesaje (de verificat la
     rulare).
   Test: `kill -9` în timpul adăugării de mesaje, indexuri trunchiate/umplute
   cu zerouri; pe harness, tăiere de curent într-un VM.
5. Claritatea textului, independent de HarfBuzz (kdebase): hint implicit
   „slight” (`kcontrol/fonts/fonts.cpp`, `krdb.cpp`), export `Xft.lcdfilter`,
   KXftConfig să scrie în `$XDG_CONFIG_HOME/fontconfig/fonts.conf`, nu în
   `~/.fonts.conf`.
6. `ksmserver/main.cpp`: verificarea de pornire caută încă doar
   `~/.ICEauthority`; documentația la fel.
7. Curățenia `startkde` (kdebase): cod propriu în locul utilitarelor X
   externe, unde se poate:
   - scoase de tot `mkfontdir` și `xset fp` (fonturi „core” X11, Qt3 folosește
     Xft) — de verificat întâi că nimic din KDE nu mai cere fonturi core;
   - `xsetroot` (fundal negru, cursor `left_ptr`) și `xprop`
     (`KDE_FULL_SESSION` pe root) → un mic utilitar Xlib propriu sau direct
     în `kstartupconfig`/`ksmserver`;
   - `xmessage` → dialog propriu (Qt minimal) pentru erorile de pornire;
   - `xrdb` (din `startkde` și `kcontrol/krdb`) → scriere directă în
     `RESOURCE_MANAGER` cu Xlib/Xrm;
   - `setxkbmap` (kxkb) → XKB direct (`XkbGetKeyboardByName` /
     `XkbRF_*` din libxkbfile);
   - `xauth` rămâne la kdesu (formatul `.Xauthority`, de evaluat separat);
   - apoi scoase dependențele corespunzătoare din pachete.
8. Audit de securitate:
   - `setgroups()` lipsește înaintea `setuid()` în start_kdeinit, drkonqi,
     ksysguardd, konsole, kdm_greet;
   - kio setează lista proprie de cifruri TLS (ocolește politica sistemului);
   - `lnusertemp` folosește `mktemp`;
   - patch-urile de securitate Debian/Trinity pentru kdelibs/kdebase/kdepim
     3.5.10 de după lansare (CVE-uri ulterioare).
9. Mărunțișuri upstream: shebang-ul `kalyptus` (`-I/Users/duke/…`),
   `checkxrefs` cu mod 644, supra-legare.
10. Qt: bug-urile cunoscute din 4.1 (RandR, ecran 0×0, x_appdisplay).

## 6. Pe mașina fizică de test (harness)

Ce nu se poate verifica în Xephyr/containere:
- sesiune reală prin DM, logout/login, ksmserver, kdm (opțional);
- dual monitor (Xinerama/RandR, panouri per ecran, rearanjare, hotplug);
- suspend/resume (kio_imap4 vechi rămâne agățat — motivația rescrierii);
- sunet (KPulsePlayer pe PipeWire), tastele multimedia;
- tipărire CUPS, montare media (HAL e mort → udisks2, vezi 7.3);
- bucla GLib sub KDE (`-glib-eventloop`) pe desktop real, apoi comparată cu
  bucla select();
- capturi pentru planul de text (HarfBuzz) și, mai târziu, Cairo/Wayland;
  metoda din fox2 (`~/Projects/idk2/fox2/tests`: bless/check/accept, sesiuni
  GNOME/KWin/sway, o sesiune per lot, atenție la memorie).

## 7. Modernizări (după ce desktop-ul și KMail merg stabil pe X11)

### 7.1 Text: HarfBuzz + FreeType (pasul 1), apoi Cairo (pasul 2) — pornit
Design complet făcut. Rezumat:
- Clasă privată `QHbFont`: cache de fețe după (FC_FILE, FC_INDEX), `hb_font`
  cu avansurile suprascrise de rasterizator → în „modul identitate” lățimile
  rămân bit cu bit cele de azi.
- Un singur `qt_hb_shape()` în `QTextEngine::shape` în locul shaperelor per
  script; context complet în buffer; RTL cu `hb_buffer_reverse`; clustere →
  `logClusters`; rotunjire pe glifă (aditivitatea lățimilor).
- `kern`/`liga` oprite implicit pentru scripturile simple și pentru fonturile
  monospațiate (Konsole, Kate). Kerning opțional mai târziu
  (`QFont::setKerning`, `charWidth` contextual, opt-out în Kate) — schimbă
  lățimile cu 0–4 px pe șir, afectează rich text (KMail), Kate proporțional,
  selecția din KHTML.
- Fallback pe caracter la itemizare (FcFontSort + FcCharSet), surogate, emoji
  (Xft 2.3.9 desenează color).
- `XftDrawGlyphSpec` peste tot (azi calea rapidă folosește avansurile Xft).
- Apoi: scoaterea `src/3rdparty/opentype` (~13.700 linii), a shaperelor vechi,
  a fonturilor XLFD (`setRawName` → fontconfig; verificarea fonturilor bitmap
  din Konsole); fribidi opțional; sublinierea din metricile fontului.
- Etape: harness `textcheck` (invarianți width/desen/cursor, capturi pe mai
  multe scrieri) → pkg-config → GlyphSpec → QHbFont → shaping → fallback →
  XLFD → curățenie → (kerning) → (fribidi). ~6–8 săptămâni-om.
- Puntea spre Cairo: `cairo_ft_font_face_create_for_pattern` (același
  pattern), `cairo_show_glyphs`; aceleași glyph id-uri.
- Pentru teste: `xorg-server-xvfb`, `xdotool`, `harfbuzz-utils`.

- **Stare (22.11):** etapa 1 harness `tests/textcheck` (a237a55, f8de94e),
  etapa 2 pkg-config + detecție HarfBuzz 15.1 (badbfe6, f539694; glife în
  harness 0109fc5, 2060ae6), etapa 3 `XftDrawGlyphSpec` cu pozițiile Qt
  (8084801, cu review; 168 imagini mai închise doar la suprapuneri).
  Urmează etapa 4 `QHbFont` (avansuri identice cu Xft, verificate pe tot
  corpusul). De reparat pe drum: offset-urile neinițializate după
  `QTextEngine::reallocate`; în `recalcAdvances` scalarea `_scale` e în
  bucla per glifă. Defecte existente găsite de harness: cursor în mijlocul
  perechilor surogat, lățimi diferite între QFontMetrics/QTextLayout/
  QTextEdit (jamo, surogate, ebraică), boundingRect care taie cerneala,
  fallback-uri cu mărime greșită (de dat FC_PIXEL_SIZE în QHbFont).
- **Obiectiv explicit: poziționare fracționară a glifelor.** Diferența
  vizibilă față de GNOME nu vine din setările de hinting (fontconfig de pe
  Arch dă deja slight + lcddefault), ci din faptul că Qt3 pune glifele pe
  pixeli întregi cu avansuri hintate; GTK4 folosește poziții fracționare
  și metrici nehintate. De făcut în etapa HarfBuzz/Cairo (26.6 în
  `XftGlyphSpec`-uri sau randare proprie FreeType/Cairo).

### 7.2 Wayland (analiză făcută, pe baza fox2)
Greul nu e Wayland, ci ieșirea din „o fereastră X per QWidget + Xlib direct”.
Etape: 0) matrice de test pe Xwayland (GNOME/Plasma/sway); 1) sesiune KDE3
completă în Xwayland rootful; 2) separarea curată a platformei (`Q_WS_*`);
3) motor Cairo sub QPainter, pe X11, comparat pixel cu pixel cu Xlib (XOR
emulat); 4) widgeturi copil fără fereastră (cel mai riscant: QXEmbed, KParts,
GL care folosesc `winId()`); 5) stratul Wayland portat din fox2
(`lib/cairo/wayland`, + DnD, xkb_compose, text-input-v3); 6) kdelibs: NETWM,
activare, SNI, scurtături globale prin portal; 7) opțional, compozitor KDE3.
~45–65 săptămâni-om „clasic” pentru aplicații native. Licență: fișierele fox2
au antetul FOX LGPLv3+ — se refolosește doar codul scris de proprietar,
relicențiat explicit.

### 7.3 Desktop modern
- GLib devine bucla implicită după testare sub KDE; KDE refuză apoi un Qt fără
  ea (`QT_GLIB_EVENTLOOP`).
- Client D-Bus prin GDBus (nu legătura veche qt3-dbus): **udisks2 pentru
  media manager (necesar — HAL e mort)**, notificări, StatusNotifierItem,
  logind, UPower, inhibare; mai târziu NetworkManager, Secret Service,
  MPRIS. Capcană: `<gio/gio.h>` înaintea headerelor Qt (Qt3 definește
  `signals`).
- DCOP peste D-Bus: API-ul DCOP rămâne, se schimbă doar transportul; probleme:
  `call()` reentrant, numele cu PID, kdesu/root, două sesiuni ale aceluiași
  utilizator. Doar după ce desktop-ul merge pe ICE (referință).
- Mixer de volum nou în kdebase (libpulse, merge pe PipeWire), în locul KMix.
- Multi-monitor: kcm nou pe RandR 1.2+ (aranjare, primar, mod per ieșire,
  profiluri la hotplug).
  Până atunci: `~/.kde/env/monitors.sh` cu `xrandr` (sursat de `startkde`).
- Desktopuri virtuale independente pe fiecare monitor (kwin, opțiune,
  implicit oprită). Pager-ul are deja „Only This Screen” (kdebase aad01a2),
  iar taskbar-ul `ShowCurrentScreenOnly`, dar desktopul curent e încă comun.
  - EWMH are un singur `_NET_CURRENT_DESKTOP`; kwin ar ține câte un desktop
    curent pe monitor și l-ar publica într-o proprietate proprie (ex.
    `_KDE_SCREEN_CURRENT_DESKTOPS`); `_NET_CURRENT_DESKTOP` rămâne desktopul
    monitorului activ, pentru programele care nu știu de ea.
  - Schimbarea desktopului ascunde/arată doar ferestrele monitorului
    respectiv; o fereastră mutată pe alt monitor preia desktopul lui.
  - Adaptate: pager, taskbar, scurtăturile (Ctrl+F1…: monitorul cu mouse-ul
    sau cu fereastra activă), kcm-ul de desktopuri.
  - Cazuri grele: ferestre întinse pe două monitoare, „pe toate
    desktopurile”, dialoguri tranzitorii, restaurarea sesiunii.
  - Câteva zile de lucru, risc de regresii în comportamentul de bază; după
    ce sesiunea e stabilă. Pentru Wayland: gândit din start în compozitor.
- Text: vezi 7.1.

### 7.4 Aplicații
- TLS unificat pe GIO (decizia userului, 21.11.2026; pasul intermediar —
  kdelibs legat direct de OpenSSL 3, fără KOpenSSLProxy/dlopen — e făcut
  înainte): KSSL înlocuit cu GTlsConnection din GIO (glib-networking, backend
  GnuTLS sau OpenSSL), un singur strat TLS pentru tot desktopul: kio_http,
  TCPSlaveBase (IMAP/POP3/SMTP), stiva de mail nouă de mai jos, KWPEPart
  (WebKit are deja propriul TLS); certificatele sistemului (p11-kit trust),
  TLS 1.3, OCSP/CRL de la GLib; de adaptat: dialogurile de certificate KDE,
  kcm Crypto (excepții per site, certificate client), KSSLCertificate ca
  fațadă peste GTlsCertificate pentru compatibilitatea API.
- Stiva de mail: protocoalele IMAP/POP3/SMTP integrate în KMail, asincron pe
  GIO (TLS, timeout-uri, reconectare, IDLE), slave-urile KIO scoase pe rând;
  probabil doar IMAP deconectat; MIME: GMime propus (înlocuirea mimelib e un
  proiect separat, cu un corpus de mesaje „urâte”). Întrebări deschise:
  renunțăm la IMAP online? biblioteca MIME?
- Motorul de mail ca bibliotecă separată, independentă de toolkit (C++ pe
  GLib/GIO, GMime, libsecret, stocare + index proprii); KMail din KDE3 e
  primul frontend, înlocuit treptat pe dedesubt; un frontend Qt6/GTK/
  icefact-ui eventual mai târziu, pe același motor. Fără rescriere de la zero
  a întregului client.
- Indexuri pe SQLite (doar dacă reparațiile din 5.4 nu ajung): o singură bază
  WAL, `synchronous=NORMAL`, numărul de serie = `rowid` (dispare `.ids`),
  maildir-ul rămâne sursa de adevăr (flag-urile din numele fișierelor),
  baza e cache reconstruibil; tranzacții grupate pentru schimbări de stare.
- KOrganizer/KAddressBook: CalDAV și CardDAV.
- Konqueror ca browser: KPart nou pe WPE WebKit (ales în locul CEF; repo
  kde3-wpepart, etapele 1–2 făcute); KHTML rămâne pentru mail, khelpcenter,
  pagini interne. Fedora nu are wpewebkit: pachet propriu.

### 7.5 Desktop la distanță integrat în KWin („feature killer”)
Scenariul: un laptop acasă, pornit permanent; la birou userul îl vrea pe unul
dintre monitoare, azi prin NoMachine (aplicație separată, artificial). Ținta:
ferestrele laptopului se comportă ca ferestre locale. Niciun alt DE nu are
asta integrat (Xpra face ferestre „seamless” pe X11, dar fără integrare în WM,
taskbar, meniu, KIO, drag and drop).
- Sursa (laptopul): KWin redirecționează deja fiecare fereastră prin
  XComposite (overview) și are damage tracking → trimite fiecare fereastră
  separat, doar zonele modificate, plus metadatele NETWM (titlu, iconiță, tip,
  transient-for, stare); inputul primit se injectează în fereastra respectivă.
- Destinația (biroul): KWin creează pentru fiecare fereastră la distanță un
  client-proxy gestionat ca unul local (taskbar, Alt+Tab, overview, decorații
  locale cu marcaj „laptop”, maximizare, mutare între monitoare).
- Integrare: drag and drop în ambele sensuri (punte XDND + transfer de fișiere
  prin KIO/sftp), clipboard sincronizat (și imagini), aplicațiile laptopului
  într-un submeniu K „Laptop” (pornite acolo, apar local), notificări, tray,
  sunet (tunel PipeWire/Pulse), opțional imprimare.
- Mod „monitor întreg”: tot desktopul laptopului pe un monitor, ca ieșire
  virtuală a KWin (înlocuitorul direct al NoMachine) — prima etapă.
- Dificultăți: latența meniurilor/popup-urilor/tooltip-urilor (poziționare
  exactă); codare adaptivă pe zone (fără pierderi pentru text, H.264/AV1 cu
  VAAPI pentru zone video); unde trăiesc ferestrele pe laptop (sesiunea reală,
  eventual blocată, vs. o sesiune separată invizibilă); conexiune criptată cu
  chei, acces de la birou la laptopul de acasă (WireGuard/Tailscale sau
  releu), reconectare transparentă; protocol independent de X11, ca să meargă
  și cu KWin compozitor Wayland (7.2).
- Etape (decizia userului, 22.11.2026):
  (1) PRIMA FAZĂ — înlocuitor NoMachine: monitorul secundar e oglinda
      laptopului (desktopul și taskbar-ul lui, pe tot monitorul, ca o ieșire
      virtuală gestionată de KWin, fără fereastră de aplicație); input,
      reconectare transparentă; copy/paste în ambele direcții (text, imagini);
      eventual drag and drop de fișiere între desktop-uri / file managere
      (Konqueror local ↔ laptop), cu transferul prin KIO. Userul e deja
      obișnuit cu modelul „monitorul = laptopul”.
  (2) LA FINAL — ferestre detașabile: tot desktopul laptopului rămâne pe
      monitorul secundar, dar o aplicație pornită acolo poate fi trasă pe
      celălalt monitor și devine fereastră-proxy locală (taskbar, Alt+Tab,
      overview); apoi aplicațiile laptopului în meniul K, sunet, notificări,
      tray, codare hardware.
  Prototip posibil între două Xephyr-uri locale, apoi între mașina locală și
  t590.

## 7b. Release: Fedora Remix + COPR (după ce sesiunea e stabilă)
Scop: prezentarea proiectului comunității (Fedora, r/linux, Hacker News) cu
un ISO live instalabil și un depozit de pachete.
- **COPR:** pachetele construite automat din git pentru Fedora curentă și
  precedentă (rețetele din `fedora/` există deja; `CLONE=` doar până devin
  publice toate repo-urile). Instalare: `dnf copr enable …` + `dnf install
  kde3-kdebase …`.
- **ISO live (Fedora Remix):** kiwi-ng (uneltele spin-urilor Fedora):
  depozitul COPR, KDE 3, display manager (LightDM sau kdm), Anaconda pentru
  instalare, Firefox ca browser de rezervă lângă Konqueror/WPE. Testat pe
  t590 și în VM prin harness.
- **Marcă și licențe:** numele „Fedora Remix” e permis; dacă modificăm
  pachete cu branding Fedora → `generic-logos`. Fără „Fedora” în numele
  produsului. Pe ISO nimic ne-liber (unrar, codecuri: doar opțional din
  depozite externe; HEIC cere libheif-freeworld din RPM Fusion).
- **Ce trebuie gata înainte:** sesiunea (desktop, Konsole, KMail, utilitare,
  sleep/shutdown, rețea NM, UDisks2, sunet, baterie, overview, panou pe toate
  monitoarele), browserul WPE la nivel decent, o listă onestă de securitate
  (ce e vechi: KHTML, codul KDE 3; ce s-a modernizat: TLS, KConfig $(…),
  kdm, kimgio, KMail), câteva săptămâni de folosire zilnică.
- **De pregătit pentru prezentare:** pagină cu capturi și funcții, răspunsul
  la „de ce nu Trinity (TDE)?” (CMake curat, Qt3 reparat cu buclă GLib/
  HarfBuzz/calea Wayland, logind/UDisks2/NetworkManager/PipeWire native,
  KMail reparat (indexuri, standby), review de securitate cu CVE-uri,
  overview modern), instrucțiuni COPR, link ISO.
- **Identitatea sesiunii:** `DesktopNames=KDE3;GNOME;` (decis 22.11, „cel puțin
  pentru început”), `kde3-portals.conf` (backend gtk), autostart XDG cu filtru
  (fără intrările „doar GNOME”).

## 8. Decizii respinse (pe scurt, ca să nu se reia)
- Migrarea KDE3 la Qt4/5/6 sau un strat de compatibilitate Qt3→Qt6.
- clang-format pe sursele KDE (poate mai târziu, un singur commit verificat).
- Reparat KHTML + QuickJS ca browser modern (DOM/CSS sunt problema, nu JS).
- DCOP înlocuit de API-ul D-Bus (doar transportul, eventual).
- Păstrarea backend-urilor de tipărire în afară de CUPS; a bundle-ului de CA.
