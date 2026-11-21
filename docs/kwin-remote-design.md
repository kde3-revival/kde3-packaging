# Desktop la distanță în KWin — faza 1 („monitorul = laptopul”)

Stare: proiect + măsurători, 2026-11-21. Nimic implementat încă. Detaliază
PLAN.md §7.5. Scripturile și rezultatele brute ale măsurătorilor sunt în
`~/Projects/kde3/build/kwin-remote-bench/` (README.txt acolo).

## 0. Rezumat

- **Ce construim**: monitorul secundar de la birou afișează desktopul real al
  laptopului de acasă, pe tot monitorul, fără fereastră de aplicație; KWin de
  la birou tratează monitorul ca pe o ieșire „împrumutată”. Tastatura și
  mouse-ul trec pe laptop când pointerul intră pe acel monitor (model
  KVM/Synergy). Clipboard în ambele sensuri, apoi drag and drop de fișiere.
- **Arhitectură recomandată**: o bibliotecă fără X și fără Qt
  (`libkwinremote`: protocol, pacing, codecuri) folosită de două procese:
  `kwin_remote_source` pe laptop (daemon de sesiune, controlat prin DCOP) și
  `kwin_remote_sink` la birou (proces ajutător pornit și supravegheat de KWin;
  KWin păstrează politica: rezervarea monitorului, focus, grab-uri, overview,
  blocare). Nici codecul, nici rețeaua nu rulează în procesul window
  managerului.
- **Transport**: protocol propriu peste UDP, cu concepte luate din QUIC
  (numere de pachet nerefolosite, ACK cu intervale, pacing), dar cu fiabilitate
  *semantică* pe mesaje: se retransmite starea curentă, nu pachetul pierdut.
  Un singur socket, planificator cu priorități stricte
  (input > cursor > control > video > fișiere). Pierderi: retransmitere
  selectivă (NACK) pe fibră, FEC adaptiv pe Wi-Fi. AEAD pe fiecare pachet de la
  început (costă 5–8 % dintr-un nucleu la 1 Gbit/s).
- **Codare**: fără pierderi pe dale (tiles) de 64×64, cu reziduu XOR față de
  cadrul anterior confirmat, predicție de scroll și zstd-1/lz4; zonele care se
  schimbă continuu (video) trec pe JPEG (libjpeg-turbo), apoi se rafinează fără
  pierderi când se opresc. Codecurile hardware (VAAPI H.264/HEVC) sunt un
  plugin opțional, mai târziu: pe Fedora stock nu există deloc (măsurat).
- **Cifre-cheie** (2560×1440, detalii în §3 și §9):
  - captură X: cadru întreg 2,1 ms, dreptunghi mic de damage 0,02 ms;
  - tastare: ~120 octeți/cadru; scroll de pagină text: 19 kB/cadru
    (9 Mbit/s) cu predicție de scroll, 185 kB fără; cadru întreg fără
    pierderi: 3,0 MB (zstd-1) – 4,1 MB (lz4); video 720p fără pierderi:
    ~1 Gbit/s → obligatoriu cu pierderi (JPEG q90: 79 Mbit/s, 2,9 ms);
  - latență adăugată estimată pe fibră: 2–4 ms pentru actualizări mici,
    10–16 ms pentru schimbări pe tot ecranul; cursorul e local (0 ms);
  - legătura de test cu t590 negociază doar 100 Mbit/s (nu 1 Gbit/s).

## 1. Cerințe și limite

Faza 1 (înlocuitor NoMachine):
1. Oglinda desktopului real al laptopului pe un monitor întreg de la birou,
   gestionată de KWin.
2. Input complet: tastatură (layouturi, diacritice, taste moarte), mouse,
   rotiță (inclusiv hi-res).
3. Copy/paste în ambele sensuri: text, imagini, formate bogate.
4. Ideal: drag and drop de fișiere între cele două desktopuri.
5. Transport UDP propriu, nu ssh. Performanța întâi; securitatea „grea”
   (WireGuard) mai târziu, dar fără a lăsa injecția de input deschisă.
6. Legătură țintă: fibră privată, 1–10 Gbit/s, RTT sub-ms până la câțiva ms.
   Degradare controlată pe 100 Mbit/s și pe Wi-Fi cu pierderi.
7. Ambele capete rulează KDE 3 al nostru pe X11. Protocolul nu are voie să
   conțină noțiuni X11 (XID-uri, atomi, keycode-uri X), ca să rămână valabil
   când KWin devine compozitor Wayland (PLAN §7.2).

În afara fazei 1 (dar proiectat să fie posibil): ferestre detașabile (o
aplicație de pe laptop trasă pe monitorul local devine fereastră-proxy), sunet,
tray, notificări, meniul K al laptopului.

Termeni: **sursă** = laptopul (trimite imagine, primește input);
**destinație** (sink) = stația de la birou.

## 2. Arhitectură

### 2.1 Unde trăiește codul

```
 laptop (sursă)                                   birou (destinație)
┌───────────────────────────────┐   UDP    ┌─────────────────────────────────┐
│ kwin_remote_source (sesiune)  │◄────────►│ kwin_remote_sink (copil al KWin)│
│  captură: XDamage+XShm        │          │  fereastră pe monitorul rezervat│
│  injecție: XTEST / uinput     │          │  decodare, XShmPutImage/Present │
│  clipboard + XDND (proxy)     │          │  input, cursor local, clipboard │
│  libkwinremote                │          │  libkwinremote                  │
└──────────▲────────────────────┘          └──────────▲──────────────────────┘
           │ DCOP                                     │ proprietăți X + DCOP
        kwin (laptop)                              kwin (birou): RemoteOutput
        [faza 2: pixmap-uri per fereastră]         (rezervare monitor, focus,
                                                    grab-uri, overview, blocare)
```

**`libkwinremote`** (statică, C++ simplu, fără Qt și fără X): formatul de
pachete, planificatorul cu priorități, pacer, ACK/NACK/FEC, criptare, codecul
pe dale, fluxuri fiabile (clipboard, fișiere), sincronizarea ceasului.
Interfețele spre platformă sunt abstracte (`FrameSource`, `InputInjector`,
`Presenter`, `ClipboardBackend`), deci aceeași bibliotecă servește mai târziu
un KWin compozitor Wayland. Buclă proprie pe `epoll`, fire de lucru pentru
codare/decodare.

**Destinația: proces ajutător, nu fire în KWin.** Variantele au fost:

| | în procesul KWin (fire) | proces ajutător `kwin_remote_sink` |
|---|---|---|
| o cădere în decodor / driver VAAPI | cade window managerul stației | KWin repornește ajutătorul |
| blocaje (blit de 14,7 MB, zstd) | pot întârzia bucla WM | izolate |
| inputul | KWin îl primește și îl retrimite | ajutătorul îl primește direct pe fereastra lui |
| politica (focus, monitor, overview) | în KWin | tot în KWin, prin proprietăți + DCOP |
| KWin compozitor Wayland | natural | ajutătorul dispare, biblioteca intră în compozitor |

Recomandare: proces ajutător. Pentru utilizator rezultatul e același („KWin
gestionează monitorul”, nu există fereastră de aplicație, intrare în taskbar
sau decorație), iar window managerul nu depinde de codecuri și de rețea. KWin
primește o clasă mică `RemoteOutput` (în `kwin/remoteoutput.{h,cpp}`): pornește
ajutătorul, îi recunoaște fereastra (override-redirect, proprietatea
`_KDE_REMOTE_OUTPUT`), rezervă monitorul și aplică politica din §2.3.

**Sursa: daemon de sesiune, nu modul KWin.** În faza 1 captura e a întregului
ecran și injecția se face prin XTEST: niciuna nu are nevoie de window manager,
iar daemonul trebuie să supraviețuiască unui `kwin --replace`. E pornit de
sesiune (autostart ksmserver) și controlat prin DCOP
(`kwin_remote_source: enable/disable/status/pair`). În faza 2 KWin de pe laptop
(care redirecționează deja ferestrele pentru overview) îi dă daemonului, prin
DCOP, lista ferestrelor și XID-urile; pixmap-urile numite prin XComposite sunt
utilizabile din orice client al aceluiași server X.

### 2.2 Sursa: captura

Opțiuni:

| metodă | plusuri | minusuri |
|---|---|---|
| **XDamage pe root + XShmGetImage pe dreptunghiuri** | fără privilegii; damage exact; merge cu ecranul blocat și cu DPMS oprit; fără cursor în imagine | copie prin CPU; pe Xorg/glamor înseamnă readback din GPU |
| XComposite per fereastră (NameWindowPixmap) | necesar în faza 2; ferestre acoperite | inutil pentru „tot ecranul” |
| DRI3 `BuffersFromPixmap` pe o copie a ecranului → DMA-BUF → VAAPI | zero-copy spre codorul hardware, fără privilegii | doar pentru calea cu codec hardware; de validat |
| DRM/KMS (`drmModeGetFB2` + PRIME) | zero-copy, independent de X | cere CAP_SYS_ADMIN; fără damage; nu merge cu CRTC-ul oprit (DPMS, capac) |

Măsurat pe Xvfb 2560×1440 (`results/capture-xvfb-*.txt`, mediană):

| operație | timp |
|---|---|
| XShmGetImage, tot ecranul (14,7 MB) | 2,14 ms (6,9 GB/s) |
| XGetImage prin socket, tot ecranul | 8,7 ms |
| XShmGetImage 1920×1080 / 1280×720 / 640×480 / 64×64 | 1,02 / 0,22 / 0,073 / 0,007 ms |
| desen 16×16 → DamageNotify → regiune → XShmGetImage | 0,021 ms |
| desen 640×480 → … → XShmGetImage | 0,134 ms |
| desen 1600×1000 → … → XShmGetImage | 1,25 ms |
| pixmap XComposite al unei ferestre 1600×1000 (faza 2) | 0,70 ms |
| comparare cadru întreg pe dale 64×64 (memcmp) | 0,9–1,7 ms |

Limită: Xvfb ține framebufferul în RAM, deci cifrele sunt costul minim. Pe un
Xorg real cu glamor, XShmGetImage face readback din GPU; **asta nu am putut
măsura** (ar fi însemnat să citesc ecranul unei sesiuni în uz). E primul lucru
de măsurat în M5 pe t590 rezervat; dacă readback-ul întregului ecran depășește
~5 ms, pentru actualizările mari se trece la calea DRI3.

Recomandare faza 1: **XDamage + XShmGetImage** într-un framebuffer-umbră al
sursei, apoi comparare pe dale doar în interiorul dreptunghiurilor de damage
(damage-ul X e adesea mai mare decât schimbarea reală). Ritmul: captură imediat
la DamageNotify dacă nu e niciun cadru în lucru (latență minimă la tastare),
altfel la următorul tact (60 Hz sau rata monitorului destinației). Cursorul nu
apare în XShmGetImage; forma lui se ia separat cu XFixes (§2.3).

### 2.3 Destinația: un monitor „împrumutat”

**Suprafața.** `kwin_remote_sink` creează o fereastră override-redirect exact
pe geometria monitorului RandR ales. Pixelii decodați ajung într-un segment
XShm și apoi pe ecran cu XShmPutImage pe dreptunghiurile modificate (măsurat pe
Xvfb: 2,19 ms tot ecranul, 0,28 ms 1280×720, 0,008 ms o dală). Opțional printr-un
pixmap + Present (codul de pipelining din `overview.cpp` se refolosește) ca să
nu existe tearing; implicit „imediat”, pentru latență.

**Rezervarea monitorului** (în KWin, `RemoteOutput`):
- monitorul iese din `clientArea()`, din plasare, din maximizare și din mutarea
  între ecrane; ferestrele locale aflate acolo la activare sunt mutate pe alt
  monitor și readuse la dezactivare;
- KWin publică pe root `_KDE_NET_RESERVED_SCREENS` (dreptunghiuri). `kde3-qt`
  (`QDesktopWidget`) sare peste ecranele rezervate, deci kicker, kdesktop și
  toate aplicațiile KDE 3 se poartă ca și cum monitorul n-ar exista. Avem
  propriul Qt: e o modificare de câteva linii;
- aplicațiile străine (GTK, Qt5) citesc RandR direct; pentru ele rămâne
  constrângerea din KWin. De încercat în M3: un monitor logic RandR 1.5 definit
  de KWin care revendică ambele ieșiri, dar are geometria doar a celei locale.
  Am verificat pe Xvfb că Xinerama raportează exact monitoarele definite cu
  `xrandr --setmonitor` (`results/randr-setmonitor-xvfb.txt`); pe două ieșiri
  reale rămâne de verificat;
- suprafața stă deasupra tuturor ferestrelor locale de pe acel monitor, dar
  **sub** kdesktop_lock: blocarea stației acoperă și monitorul laptopului.

**Legătura apare și dispare.** Stări: `Dezactivat` (monitor local obișnuit),
`Conectare`, `Activ`, `Întrerupt` (ultimul cadru estompat + stare; după N
secunde, configurabil, monitorul revine la desktopul local). Monitorul scos din
priză: sesiunea la distanță intră în pauză, nu se mută într-o fereastră.

**Cursorul e local.** Sursa urmărește forma cursorului (XFixes
`CursorNotify` + `GetCursorImage`) și o trimite ca ARGB + hotspot, identificată
printr-un hash (cache pe destinație). Destinația o pune ca și cursor X al
ferestrei ei: serverul X local o desenează ca și cursor hardware, deci mișcarea
pointerului nu depinde de rețea. Poziția pleacă spre laptop ca absolută.

**Focusul urmează pointerul** (implicit; alternativ „la clic”, din
configurare):
- pointerul intră pe suprafață: destinația reține fereastra locală activă, ia
  focusul X și un `XGrabKeyboard` activ. Grab-ul activ are prioritate față de
  grab-urile pasive ale scurtăturilor globale, deci Alt+Tab, Alt+F2, Super etc.
  ajung la laptop. Se trimite starea tastaturii (§5);
- pointerul iese: ungrab, focus înapoi la fereastra reținută, „eliberează toate
  tastele” spre sursă;
- buton apăsat la ieșire: grab-ul implicit de pointer ține evenimentele pe
  suprafață până la eliberare (selecția continuă, coordonatele se limitează la
  ecranul laptopului). Aceeași situație pornește puntea de drag and drop (§4.3);
- o aplicație locală ține deja un grab (meniu deschis): `XGrabKeyboard` eșuează
  cu AlreadyGrabbed; se reîncearcă la următoarea mișcare. Nu se forțează nimic;
- cât timp focusul e la distanță, KWin tratează suprafața ca fereastră activă
  pentru prevenirea furtului de focus;
- scurtătură locală de scăpare (neretransmisă niciodată), de exemplu
  Ctrl+Alt+Shift+Esc: eliberează grab-ul și scoate pointerul pe monitorul local.

**Interacțiuni cu restul KWin:**
- *Super și overview*: Super apăsat cu pointerul pe monitorul laptopului merge
  la laptop (overview-ul lui apare pe acel monitor). Overview-ul local folosește
  fereastra overlay Composite, care acoperă toate ecranele: se decupează cu
  XFixes Shape dreptunghiul monitorului rezervat, ca imaginea laptopului să
  rămână vizibilă și vie. Cât e activ overview-ul local, inputul e al lui.
- *Colțuri fierbinți și bariere*: benzile și barierele de pointer din
  `overview.cpp` se calculează fără monitorul rezervat; muchia dintre monitorul
  local și cel la distanță nu primește barieră. Colțurile de pe monitorul
  laptopului aparțin KWin-ului de acolo (mișcarea injectată le declanșează).
- *Blocarea stației*: kdesktop_lock are nevoie de grab-ul de tastatură. Înainte
  de blocare, kdesktop anunță KWin prin DCOP, care eliberează focusul la
  distanță; destinația nu trimite input cât timp nu deține grab-ul.

## 3. Codare

### 3.1 Conținut de test

`gen_content.py` produce cadre 2560×1440 asemănătoare unui desktop: tapet cu
gradient, o fereastră cu o pagină de text antialiasat (1700×1240), un terminal,
o fereastră „video” 1280×720 (zoom Mandelbrot cu granulație), panou. Patru
scenarii de câte 30 de cadre: *typing* (un caracter pe cadru), *scroll* (pagina
urcă 48 px pe cadru), *video*, *mixed* (scroll + video).

Atenție la toate cifrele de timp de pe mașina locală: rulau alte build-uri în
paralel (load 7–20), deci sunt limite superioare.

### 3.2 Fără pierderi: ce încape pe fir

Un cadru brut are 14,75 MB; la 60 fps înseamnă **7,08 Gbit/s**. Un fir de
execuție, i3-12100 (`results/codec-*-t1.txt`):

| scenariu, mod | codec | octeți/cadru | Mbit/s la 60 fps | codare | decodare |
|---|---|---|---|---|---|
| cadru întreg | lz4 | 4,1 MB (3,6×) | ~2000 | 6–9 ms | 2,0–2,6 ms |
| cadru întreg | zstd-1 | 3,0 MB (4,9×) | ~1450 | 11–16 ms | 4,4–5,6 ms |
| cadru întreg | zstd-3 | 2,9 MB | ~1380 | 25–42 ms | 5,5–8 ms |
| cadru întreg | QOI | 2,9 MB | ~1400 | 13–19 ms | 7–11 ms |
| typing, damage 16×24, reziduu XOR | zstd-1 / lz4 | 120 / 149 B | <0,1 | µs | µs |
| scroll, damage intra | zstd-1 | 1,19 MB | 569 | 8,4 ms | 2,9 ms |
| scroll, reziduu XOR | zstd-1 | 185 kB | 89 | 5,6 ms | 2,1 ms |
| scroll, reziduu XOR + predicție de scroll | zstd-1 | **19 kB** | **9** | 3,8 ms | 1,0 ms |
| scroll, reziduu XOR + predicție de scroll | lz4 | 68 kB | 33 | 3,2 ms | 0,9 ms |
| video 720p, damage intra | lz4 / zstd-1 | 3,6 / 2,8 MB | 1740 / 1330 | 4,7 / 7,8 ms | |
| video 720p, reziduu XOR | zstd-1 | 2,1 MB | 992 | 8,0 ms | 2,1 ms |
| mixed, reziduu + predicție | zstd-1 | 2,1 MB | 1009 | 10,3 ms | 2,9 ms |

Cu 4 fire (dalele sunt independente): cadru întreg lz4 3,4–6,2 ms, zstd-1
6,6–9,5 ms; scroll cu predicție zstd-1 3,0 ms, lz4 1,5 ms. i7-8565U din t590
are aceeași viteză pe un fir (zstd: 511 față de ~530 MB/s).

Concluzii:
1. „Aproape brut” e viabil doar pe 10 Gbit/s (lz4 pe cadre întregi, 2 Gbit/s
   la 60 fps, 3–6 ms pe 4 nuclee). Pe 1 Gbit/s cadrele întregi fără pierderi nu
   încap la 60 fps.
2. Munca de birou obișnuită încape oricum, chiar și pe 100 Mbit/s, dacă se
   trimite doar damage-ul ca reziduu față de cadrul anterior: tastarea e
   neglijabilă, iar scrollul scade de la 185 kB la 19 kB pe cadru când dalele
   care se regăsesc deplasate în cadrul anterior se codează ca „mută”.
3. Video-ul nu se comprimă fără pierderi (1,0–1,3 Gbit/s pentru o fereastră
   720p): acolo e nevoie de codare cu pierderi indiferent de legătură.
4. QOI nu câștigă nimic față de zstd-1/lz4 pe acest conținut; nu se folosește.

### 3.3 Cu pierderi

libjpeg-turbo, un fir, fereastra video 1280×720 (`results/jpeg-*.txt`):

| setare | octeți/cadru | Mbit/s la 60 fps | codare | decodare |
|---|---|---|---|---|
| q75 4:2:0 | 76 kB | 37 | 2,6 ms | 2,3 ms |
| q90 4:2:0 | 165 kB | 79 | 2,9 ms | 3,0 ms |
| q90 4:4:4 | 265 kB | 127 | 4,9 ms | 4,9 ms |
| q97 4:4:4 | 762 kB | 366 | 7,1 ms | 9,8 ms |

Codecuri video, tot ecranul 2560×1440, scenariul *mixed*, prin ffmpeg, fără
B-frames (`results/video-*.txt`). Timpul include conversia de culoare și
încărcarea în GPU, care domină (5–9 ms din total; swscale BGRA→NV12 singur
costă 4,6–6,6 ms):

| codor | ms/cadru | Mbit/s la 60 fps | observații |
|---|---|---|---|
| Radeon RX 7600, h264_vaapi QP20 | 6,4 | 110 | fără 4:4:4 |
| Radeon RX 7600, hevc_vaapi QP20 / QP26 | 6,2 / 5,9 | 25 / 15 | fără 4:4:4 |
| Radeon RX 7600, av1_vaapi | 5,9 | 47 | fără 4:4:4 |
| Intel UHD 730, h264_vaapi QP20 | 8,8 | 42 | |
| Intel UHD 730, hevc_vaapi 4:2:0 QP20 | 14,6 | 26 | |
| Intel UHD 730, **hevc_vaapi 4:4:4** QP20 / QP12 | 10,5–14,8 / 15,3 | 57 / 297 | 10,5 ms cu conversia pe GPU |
| x264 ultrafast zerolatency 4:2:0 crf20 | 9,1 (24 ms CPU) | 44 | |
| x264 ultrafast zerolatency 4:4:4 crf20 | 11,5 (31 ms CPU) | 54 | |
| x264rgb fără pierderi | 16,4 (45 ms CPU) | 1003 | |
| t590, Fedora 44 stock: libopenh264 | 14,7 (37 ms CPU) | 20 | singurul codor disponibil |

Decodare 1440p: VAAPI spre suprafață 1,3–2,3 ms/cadru (Intel UHD 730, Radeon);
software H.264 4:4:4 2,4–4,8 ms; HEVC software 11,4 ms; pe t590 stock doar
OpenH264, 6,4 ms/cadru.

**Fedora stock nu are codare hardware și aproape nici decodare**:
`libva-intel-media-driver` din Fedora nu expune niciun profil de codare
(H.264, HEVC, AV1: „No usable encoding profile”), `ffmpeg-free` nu are decodor
HEVC și nici H.264 4:4:4. Driverul complet e în RPM Fusion. Pe Arch, driverul
Intel nu era instalat deloc pe mașina locală (testat cu pachetul despachetat
într-un director temporar). Radeon nu codează 4:4:4; Intel UHD 620 din t590 nu
are HEVC 4:4:4 la codare.

Claritatea textului, o pagină de text 1696×1240 codată intra
(`results/text-quality-*.txt`):

| codare | mărime | PSNR | SSIM |
|---|---|---|---|
| x264 4:2:0 crf12 / crf20 / crf26 | 449 / 275 / 195 kB | 39,4 / 39,0 / 38,3 dB | 0,983 / 0,978 / 0,975 |
| x264 4:4:4 crf12 / crf20 / crf26 | 540 / 297 / 209 kB | 49,2 / 44,9 / 42,4 dB | 0,992 / 0,980 / 0,976 |
| hevc_vaapi 4:2:0 QP12 / QP20 | 305 / 195 kB | 39,4 / 38,9 dB | 0,982 / 0,977 |
| fără pierderi: zstd-1 / x264rgb | 1156 / 1410 kB | ∞ | 1 |

4:2:0 se plafonează la ~39 dB oricât ar crește bitrate-ul (culoarea textului
antialiasat se pierde); 4:4:4 urcă cu 5–10 dB. Dar după primul cadru textul
costă, fără pierderi, zeci de octeți până la zeci de kB pe cadru (§3.2), deci
codecul video pentru text nu aduce nimic.

### 3.4 Schema recomandată

Dale de 64×64, fiecare cu o versiune; pentru fiecare cadru și fiecare dală
modificată, codorul alege:

| tip | când | conținut |
|---|---|---|
| `SKIP` | identică cu referința | nimic |
| `MOVE` | se regăsește deplasată în cadrul anterior (scroll, mutare de fereastră) | vector |
| `FILL` | o singură culoare | 4 octeți |
| `RESIDUAL` | are referință confirmată de destinație | XOR față de referință, zstd-1 sau lz4 |
| `INTRA` | fără referință confirmată (prima oară, după pierdere) | zstd-1 / lz4 |
| `LOSSY` | dala s-a schimbat în ultimele N cadre la rând și reziduul nu se comprimă | JPEG, calitate după buget |

- Dalele `LOSSY` care nu s-au mai schimbat ~200 ms sunt retrimise fără
  pierderi (rafinare), deci imaginea statică e întotdeauna exactă la pixel.
- zstd-1 sau lz4 se alege după bugetul de octeți pe cadru: pe 10 Gbit/s lz4
  (mai puțin CPU), pe ≤1 Gbit/s zstd-1.
- Bugetul vine din pacer (§4.5): octeți pe cadru ≤ rata legăturii
  × timpul de serializare acceptat. La 4 ms: 5 MB pe 10 Gbit/s, 500 kB pe
  1 Gbit/s, 50 kB pe 100 Mbit/s. Când un cadru nu încape, se trimit întâi
  dalele de lângă cursor și cele fără pierderi mici, restul în cadrele
  următoare sau cu calitate JPEG mai mică.
- Toate dependențele (zstd, lz4, libjpeg-turbo) există pe orice distribuție și
  nu au probleme de brevete. Qt leagă deja libjpeg.
- **Codec hardware: plugin opțional, după faza 1** (libavcodec încărcat
  dinamic, detectat la rulare, negociat în handshake). Folos real: legături sub
  ~50 Mbit/s și video pe tot ecranul. HEVC 4:4:4 doar unde există (Intel
  Gen 11+).

### 3.5 Buget de bandă la 2560×1440@60

| conținut | 10 Gbit/s | 1 Gbit/s | 100 Mbit/s |
|---|---|---|---|
| tastare, cursor, meniuri | <1 Mbit/s fără pierderi | la fel | la fel |
| scroll text (9–90 Mbit/s) | fără pierderi, lz4 | fără pierderi, zstd-1 | fără pierderi cu `MOVE`; altfel cadre sărite |
| video 720p într-o fereastră | fără pierderi (1–1,3 Gbit/s) | JPEG q90–97 (80–370 Mbit/s) | JPEG q75 (37 Mbit/s) sau 30 fps |
| tot ecranul se schimbă | lz4 pe cadre întregi (2 Gbit/s) | JPEG 4:4:4 + rafinare | JPEG q75 la 20–30 fps + rafinare; aici ajută codecul hardware |

### 3.6 Buget de latență

Ținte, latență **adăugată** față de lucrul local, pe fibră (RTT ≤ 2 ms):
≤ 5 ms pentru actualizări mici, ≤ 16 ms pentru schimbări pe tot ecranul; 0 ms
pentru cursor.

| etapă | actualizare mică (tastare) | scroll 1700×1240 | sursa cifrei |
|---|---|---|---|
| input: destinație → laptop | 0,3–1 ms | la fel | RTT măsurat 0,5–1 ms |
| aplicația desenează | (ca local) | (ca local) | |
| damage → pixeli în sursă | 0,02 ms | 1,3 ms | măsurat, Xvfb; pe glamor necunoscut |
| comparare + codare | <0,1 ms | 1,5–4 ms (4 fire / 1 fir) | măsurat |
| serializare pe fir | ~0 | 19 kB: 0,15 ms la 1 Gbit/s; 1,5 ms la 100 Mbit/s | calcul |
| propagare | 0,3–1 ms | la fel | măsurat |
| decodare | <0,1 ms | 0,4–1 ms | măsurat |
| XShmPutImage | 0,01 ms | 0,3–1 ms | măsurat, Xvfb |
| **total adăugat** | **~1–2,5 ms** | **~4–9 ms** | |
| așteptarea scanout-ului | 0–16,7 ms | la fel | există și local |

Pentru un cadru întreg fără pierderi pe 1 Gbit/s serializarea singură ar fi
24 ms (3 MB); de aceea bugetul de octeți pe cadru decide tipul dalelor, nu
invers. Nesiguranța mare rămasă e readback-ul din GPU pe sursă.

## 4. Protocolul pe UDP

### 4.1 Blocuri existente, comparate

| | plusuri | minusuri pentru cazul nostru |
|---|---|---|
| **QUIC + DATAGRAM (RFC 9221)** prin msquic / ngtcp2 / quiche | recuperare de pierderi și control al congestiei mature; fluxuri fiabile + datagrame; TLS 1.3; migrarea conexiunii | criptarea nu se poate opri și nici alege; datagramele sunt limitate la un pachet și supuse aceluiași control al congestiei, deci fragmentarea, FEC-ul și „ce mai merită retrimis” rămân tot la noi; prioritizarea între fluxuri și datagrame depinde de implementare; msquic e mare, quiche cere Rust, ngtcp2 cere lipici TLS și bucla UDP proprie |
| **SRT** | ARQ + FEC, făcut pentru video | latență fixă prin buffer (zeci–sute de ms), un singur flux, fără priorități: opusul interactivului |
| ENet / KCP | mici, canale fiabile și nefiabile | fără pacing, fără GSO, tot ne trebuie stratul video; întreținere slabă |
| RTP + FEC (modelul Sunshine/Moonlight) | dovedit pentru jocuri | presupune un codec video pe cadre întregi, nu dale cu stare |
| **protocol propriu** | priorități exacte; retransmitere pe stare, nu pe pachet; criptare la alegere; ~2–3 mii de linii, fără dependențe | controlul congestiei e partea grea și o scriem noi |

Recomandare: **protocol propriu**, cu mecanismele de bază copiate din QUIC
(RFC 9000/9002): numere de pachet monotone, niciodată refolosite, ACK cu
intervale și întârziere de ACK, PTO, pacing. Motivul principal nu e viteza, ci
semantica: o dală pierdută nu se retrimite dacă între timp există o versiune
mai nouă, iar inputul nu are voie să aștepte în spatele video-ului; într-un
QUIC generic amândouă se obțin doar ocolind biblioteca. Riscul asumat e
controlul congestiei; pe o fibră privată e suficient unul simplu, iar legătura
de 100 Mbit/s cu t590 și Wi-Fi-ul sunt bancul de probă. Formatul de cadre e
gândit ca să poată fi dus mai târziu și în datagrame QUIC, dacă va trebui
traversare de NAT.

### 4.2 Pachetul

Antet fix de 16 octeți, apoi cadre (TLV), apoi eticheta AEAD de 16 octeți:

```
 0        1        2                4                         12        16
┌────────┬────────┬────────────────┬─────────────────────────┬─────────┐
│ver+flag│ epocă  │ id conexiune   │ număr de pachet (64 b)  │ timp µs │
└────────┴────────┴────────────────┴─────────────────────────┴─────────┘
```

- numărul de pachet e și nonce-ul AEAD (cheie separată pe sens); antetul e
  date autentificate; fereastră anti-replay de 2048 de pachete;
- „timp” = ceasul expeditorului la trimitere, pentru întârzierea într-un sens;
- sarcină utilă inițială 1200 octeți; se sondează în sus (1452 pe Ethernet
  1500, ~1380 prin WireGuard, 8952 dacă fibra duce jumbo), ca în DPLPMTUD.

Cadre: `HELLO`/`RESUME`/`CLOSE`, `ACK`, `PING`/`PONG`, `INPUT`,
`CURSOR_SHAPE`, `CURSOR_WARP`, `STREAM` (id, offset, lungime, fin — fluxuri
fiabile ordonate: control, clipboard, fișiere), `FRAME_BEGIN`/`FRAME_END`
(suprafață, număr de cadru, timp de captură, număr de bucăți), `TILES`
(bucată dintr-un cadru: dale întregi, decodabile independent), `FEC`,
`NACK`, `REPORT` (rată primită, pierderi, întârziere), `SURFACE` (creare,
geometrie, metadate).

Totul e adresat unei **suprafețe**. În faza 1 există una singură („ieșirea 0”
a laptopului); în faza 2 fiecare fereastră detașabilă devine o suprafață cu
metadate (titlu, clasă, iconiță, tip, părinte), iar inputul poartă id-ul
suprafeței și coordonate relative la ea. Asta e tot ce trebuie pregătit acum
pentru ferestrele-proxy.

### 4.3 Canale și priorități

Un singur socket UDP și un singur pacer; coadă cu priorități stricte la
expeditor:

| prioritate | conținut | fiabilitate |
|---|---|---|
| 0 | `INPUT`, ACK/NACK | redundanță: fiecare pachet repetă ultimele 8 evenimente; poziția absolută e idempotentă |
| 1 | cursor (formă, warp), `PING` | ultima valoare câștigă |
| 2 | control, oferte de clipboard, DnD | flux fiabil |
| 3 | video (`TILES`) | NACK / FEC, „ultima versiune câștigă” pe dală |
| 4 | date de clipboard mari, fișiere | flux fiabil, primește doar banda rămasă |

De ce un singur socket: sub WireGuard toate fluxurile devin oricum un singur
5-tuplu, iar câmpul DSCP interior nu se propagă în exterior, deci izolarea
trebuie făcută la expeditor. Fără tunel se marchează DSCP și, opțional,
fișierele pot merge pe al doilea socket, ca `fq_codel` să le separe (măsurat:
un flux de 1 kHz pe alt socket a rămas la RTT median 1–2 ms, p99 ≤ 4 ms, cu
legătura de 100 Mbit/s saturată de un flux de 105 Mbit/s).

### 4.4 Pierderi

- **Input**: redundanță în fiecare pachet + ACK; o pierdere izolată nu costă
  nimic, nici măcar un RTT.
- **Video**: implicit **NACK selectiv**. Destinația cere (cadru, bucată);
  sursa retrimite bucata doar dacă dalele ei n-au fost înlocuite între timp,
  altfel trimite versiunea curentă. Pe fibră costă un RTT (1–2 ms), mai puțin
  decât ar costa permanent FEC-ul.
- **FEC adaptiv** (o bucată de paritate XOR la k bucăți, k după rata de
  pierderi): pornește când RTT > ~8 ms sau pierderile > 0,5 %, adică pe Wi-Fi.
- **Fără keyframe la cerere**: nu există cadre-cheie. Regula care ține locul
  lor: o dală se codează `RESIDUAL`/`MOVE` doar față de o versiune pe care
  destinația a confirmat-o; altfel `INTRA`. Cu RTT sub un cadru, confirmarea
  sosește aproape mereu înaintea cadrului următor.
- Cadrele învechite nu se mai trimit: dacă există o versiune mai nouă a dalei
  în coadă, cea veche se aruncă.

### 4.5 Congestie, pacing, eficiență

- Pacer cu găleată de jetoane la rata estimată; rafale de cel mult 1 ms.
- Estimarea ratei: la conectare un tren de pachete; apoi rapoartele
  destinației (rată de livrare, pierderi, gradientul întârzierii într-un sens).
  Ținta: 90 % din rata de livrare, întârziere în coadă sub 2 ms. Măsurat pe
  legătura cu t590: 0 % pierderi până la 80–90 Mbit/s, apoi pierderi imediat
  (1 % la 90–95 Mbit/s dinspre t590, 14 % la 110 Mbit/s spre t590); marginea de
  10 % e necesară.
- Trimitere cu `UDP_SEGMENT` (GSO) și primire cu `UDP_GRO`, cu
  `sendmmsg`/`recvmmsg` ca rezervă. Măsurat pe loopback, un fir, mașină
  încărcată: 3,0 Gbit/s cu sendmmsg, 4,5 Gbit/s cu GSO (pachete de 1400
  octeți); la 90 Mbit/s GSO a înjumătățit CPU-ul expeditorului. Pentru 10 Gbit/s
  trebuie jumbo sau mai multe fire; nu e o țintă a fazei 1.
- Buffere de socket: `rmem_max`/`wmem_max` sunt 4 MB pe ambele mașini,
  suficient la 1 Gbit/s cu pacing.

### 4.6 Ceas, latență, reconectare

- `PING`/`PONG` de 10 ori pe secundă cu patru mărci de timp (ca NTP), filtru de
  minim: decalajul ceasurilor și RTT-ul. Fiecare cadru poartă timpul de
  captură, destinația îl compară cu momentul afișării: latența cap-coadă se
  vede într-un OSD de diagnostic și prin DCOP.
- Sesiunea are un id și chei; pachetele autentificate sunt acceptate de la
  orice adresă sursă (laptopul își poate schimba IP-ul, ca la WireGuard/mosh).
- 250 ms fără niciun pachet cu taste apăsate: sursa eliberează tastele. 2 s
  fără pachete: starea `Întrerupt`. Destinația trimite `RESUME` o dată pe
  secundă; la reluare sursa consideră toate dalele neconfirmate (deci `INTRA`,
  de la cursor spre exterior) și se resincronizează starea tastaturii.

## 5. Input

**Taste.** Trei variante: (a) coduri de poziție, laptopul aplică layoutul lui
— greșit când layouturile diferă; (b) keysym-uri, sursa caută o tastă care
produce simbolul și remapează temporar ce lipsește (ca VNC) — strică
scurtăturile și tastele moarte; (c) **sincronizarea layoutului**: tastatura
fizică e cea de la birou, deci layoutul ei decide.

Recomandare: (c). Destinația trimite descrierea layoutului (numele XKB:
reguli, model, layout, variantă, opțiuni) și grupul curent, la conectare și la
fiecare schimbare; sursa aplică aceeași hartă pe serverul X al laptopului cât
timp sesiunea e activă și o reface la deconectare. Apoi circulă doar coduri de
poziție (coduri evdev, adică keycode X − 8). Diacriticele, AltGr, tastele
moarte și Compose se rezolvă pe laptop exact ca la o tastatură locală, iar
scurtăturile rămân pe poziție. Fiecare eveniment poartă totuși și keysym-ul +
caracterul Unicode calculate pe destinație, ca rezervă pentru capete unde harta
nu se poate aplica. Protocolul nu conține nimic specific X11.

**Starea la schimbarea focusului.** La intrare destinația trimite mulțimea
tastelor apăsate și starea Caps/Num Lock și grupul; sursa eliberează orice ține
apăsat în plus și aliniază lock-urile (`XkbLockModifiers`, `XkbLockGroup`). La
ieșire: „eliberează tot”.

**Taste blocate și autorepeat.** Repetarea se face pe destinație (serverul X
local repetă, evenimentele se trimit marcate „repeat”); sursa oprește
autorepeat-ul serverului laptopului cât e controlat de la distanță și injectează
eliberare + apăsare pentru fiecare repetare. O eliberare întârziată nu mai
poate produce un șir de caractere. În plus: semnal de viață la 50 ms cât e vreo
tastă apăsată; fără el 250 ms, sursa eliberează tot.

**Pointer.** Poziție absolută în coordonatele suprafeței, în virgulă fixă
16.16, cel mult un pachet pe milisecundă (ultima poziție + evenimentele
adunate). Injecție cu XTEST (trece și prin grab-uri, deci merge cu ecranul
blocat). Dacă o aplicație de pe laptop mută pointerul, sursa vede diferența
față de ultima poziție injectată și trimite `CURSOR_WARP`; destinația face
`XWarpPointer` doar dacă pointerul e pe suprafață. Aplicațiile care țin
pointerul capturat și îl recentrează (jocuri, vizualizatoare 3D) cer un mod
relativ; rămâne în afara fazei 1.

**Butoane și rotiță.** Butoanele 1–3 și 8–9. Rotița: destinația citește
valuatorii de scroll XI2 și trimite deplasări în unități de 1/120 de crestătură
(aceeași convenție ca `REL_WHEEL_HI_RES` și Wayland). Injecția are două
variante în spatele aceleiași interfețe `InputInjector`:
- XTEST (implicit, fără nicio configurare): doar crestături întregi (butoanele
  4–7), fracțiunile se acumulează;
- uinput (opțional, dacă `/dev/uinput` e accesibil — regulă udev în pachet):
  dispozitiv virtual cu `REL_WHEEL_HI_RES`, deci scroll fin real în
  aplicațiile XI2 ale laptopului. Aplicațiile Qt 3 folosesc oricum butoanele
  4/5, deci scrollul fin contează doar pentru aplicațiile străine.

## 6. Clipboard și drag and drop

### 6.1 Clipboard

Fiecare capăt are un proxy de selecții (în `kwin_remote_source`, respectiv
`kwin_remote_sink`), pentru CLIPBOARD și PRIMARY:
1. Proprietarul local se schimbă (XFixes `SelectionNotify`): proxy-ul citește
   doar `TARGETS` și trimite o **ofertă**: selecția, un număr de serie, lista
   de tipuri MIME. Atomii nu trec pe fir; `UTF8_STRING` devine
   `text/plain;charset=utf-8`, restul țintelor MIME trec nemodificate
   (`text/html`, `image/png`, `text/uri-list`, `application/x-qiconlist`…).
2. Celălalt capăt devine proprietarul selecției cu o fereastră proprie și
   anunță aceleași tipuri. Schimbările provocate de propria fereastră se
   ignoră (fără ecou).
3. O aplicație lipește (`SelectionRequest` pentru un tip): proxy-ul cere
   datele peste rețea, capătul de origine face `XConvertSelection` la
   proprietarul real (inclusiv recepție INCR) și le trimite pe un flux fiabil;
   proxy-ul răspunde solicitantului, cu INCR peste ~256 kB.

Transferul e **leneș**: până la lipire circulă doar lista de tipuri. O imagine
de 100 MB durează ~1 s pe 1 Gbit/s, sub timpii de așteptare ai toolkit-urilor.
`TIMESTAMP` se răspunde local, `MULTIPLE` se refuză în prima versiune.

Fișiere: `text/uri-list` cu `file://` se rescrie în
`kremote://<capăt>/xfer/<jeton>/<nume>` (§6.3). Copy în Konqueror pe un
desktop + paste în Konqueror pe celălalt funcționează astfel înainte de a
exista drag and drop.

De hotărât: Klipper cere conținutul la fiecare schimbare, ceea ce anulează
lenea pentru date mari; propunere: cererile venite de la Klipper peste o limită
(1 MB) se refuză.

### 6.2 Drag and drop (XDND v5)

Ambele capete trebuie să fie pe rând și sursă, și țintă XDND.

**Birou → laptop.** Fereastra suprafeței e `XdndAware`. La
`XdndEnter`/`XdndPosition` destinația trimite tipurile și poziția;
`kwin_remote_source` joacă rolul de sursă XDND pe laptop: deține
`XdndSelection`, găsește fereastra `XdndAware` de sub pointer și îi trimite
`XdndEnter`/`Position`/`Drop`. `XdndStatus`-ul țintei se întoarce la birou, ca
sursa locală să arate cursorul corect. La drop, ținta de pe laptop cere
`text/uri-list` și primește URL-uri `kremote://`; alte tipuri (text, imagini)
se aduc leneș, ca la clipboard.

**Laptop → birou.** Utilizatorul apasă pe un fișier în Konqueror-ul
laptopului și trage peste muchie. Local, grab-ul implicit ține evenimentele pe
suprafață. Când pointerul iese cu butonul apăsat, sursa mapează pe laptop, sub
pointerul oprit la margine, o fereastră-portal `XdndAware`: aplicația de pe
laptop îi trimite `XdndEnter` cu tipurile (așa aflăm că e un drag și ce
oferă). Destinația devine sursă XDND locală și conduce drag-ul peste
ferestrele locale. La eliberarea butonului peste o țintă locală, sursa
injectează eliberarea pe laptop, portalul primește `XdndDrop`, convertește
`XdndSelection` la cererea țintei locale și răspunde `XdndFinished`. Portalul
anunță întotdeauna acțiunea „copiere”: aplicația de pe laptop nu are voie să
șteargă originalul pe baza unui drop pe care nu-l putem garanta.

Volum estimat: 1500–2500 de linii, cu multe particularități de aplicații; de
aceea e ultimul jalon funcțional.

### 6.3 Transferul de fișiere: canalul propriu, expus prin KIO

Nu sftp/fish (ar cere chei și configurare ssh, și e exact transportul
respins), ci canalul de prioritate 4 al protocolului, expus ca **kioslave
`kremote:`**. Slave-ul vorbește printr-un socket Unix cu procesul local
(`kwin_remote_sink` sau `kwin_remote_source`), care servește fișierele peste
rețea. Konqueror și kdesktop nu au nevoie de nicio modificare: un drop sau un
paste cu URL-uri non-locale pornește `KIO::copy` cu dialogul obișnuit de
progres, anulare și reluare.

Serviciul de fișiere expune **doar** ce a fost oferit într-o tranzacție de
clipboard sau DnD, prin jetoane cu durată limitată; nu e un acces general la
sistemul de fișiere al celuilalt capăt.

Limită cunoscută: aplicațiile non-KDE nu înțeleg `kremote:`. Pentru ele, mai
târziu: materializare într-un director temporar (fișiere mici) sau montare
FUSE.

## 7. Sesiunea de pe laptop

**Sesiunea reală, inclusiv blocată.** Daemonul rulează în sesiunea
utilizatorului. kdesktop_lock e o fereastră X obișnuită cu grab-uri: apare în
captura root-ului, iar XTEST livrează inputul către deținătorul grab-ului, deci
ecranul blocat se vede și se deblochează de la distanță. Cu DPMS oprit serverul
X desenează în continuare în pixmap-ul ecranului, deci captura la nivel X merge
(captura KMS nu ar merge — încă un motiv pentru alegerea din §2.2).

Înainte de autentificare (după o repornire a laptopului) daemonul nu există:
ecranul display managerului e alt server/altă sesiune. Pentru faza 1:
autologin + blocare imediată. Un serviciu de sistem care se atașează la
greeter rămâne pentru mai târziu.

Intimitate: cât e folosit de la distanță, panoul laptopului arată tot. Inputul
injectat trezește DPMS-ul, deci „DPMS off” nu ține. Soluție: luminozitate 0
prin logind (`SetBrightness`, fără privilegii) sau ieșirea virtuală de mai jos
cu panoul oprit.

**Capac închis.** logind suspendă implicit: trebuie `HandleLidSwitch=ignore`
(și varianta pentru alimentare externă) sau un inhibitor `handle-lid-switch`
ținut de daemon. Panoul eDP rămâne de obicei „conectat” pentru Xorg.

**Rezoluția: 2560×1440 pe un laptop cu panou mai mic.** Ce se poate pe Xorg cu
driverul modesetting, azi:

| metodă | privilegii | observații |
|---|---|---|
| `xrandr --output eDP-1 --scale-from 2560x1440` | niciunul | ecranul X devine 2560×1440, panoul îl arată micșorat; captura X ia pixelii nativi |
| `xrandr --fb 2560x1440 --panning …` | niciunul | panoul arată o porțiune care urmărește pointerul |
| `--fb` mai mare + `xrandr --setmonitor REMOTE … none` | niciunul | monitor logic RandR 1.5 fără CRTC, lângă panou; verificat pe Xvfb că Xinerama îl raportează; e un al doilea „monitor”, nu oglinda desktopului existent |
| toate ieșirile oprite, doar framebuffer | niciunul | riscant: aplicații fără niciun monitor (vezi bugul „ecran 0×0” din PLAN §4.1) |
| conector fizic liber forțat „on” cu EDID propriu (`video=HDMI-A-1:2560x1440@60e` + `drm.edid_firmware=`, sau un dop HDMI) | root, o singură dată | monitor adevărat pentru GPU: CRTC, vblank, accelerare; permite și captura KMS |
| xf86-video-intel `VirtualHeads` | — | doar driverul vechi intel; nu |
| xf86-video-dummy | — | alt server X, nu sesiunea reală, fără accelerare; nu |
| EVDI (DisplayLink), VKMS | modul de kernel | EVDI e în afara kernelului (DKMS); VKMS e pentru teste; nu pentru faza 1 |

Recomandare: la conectare destinația își anunță rezoluția; sursa încearcă în
ordine (1) un mod existent pe o ieșire conectată, (2) `--scale-from` pe panou,
(3) conectorul forțat, dacă administratorul l-a configurat, cu panoul oprit.
La deconectare se revine (configurabil). **Niciuna dintre variantele pe Xorg
real n-a fost încercată în acest studiu**; e un experiment de o zi pe t590, în
M5. Dacă nu se poate potrivi rezoluția: scalare pe destinație (XRender) sau
benzi negre, niciodată deformare.

## 8. Securitate

**Mai târziu**: WireGuard între cele două mașini (în kernel, roaming, chei
publice); desktopul la distanță ascultă atunci doar pe interfața `wg`.

**De la început**, pentru că un canal de input neautentificat înseamnă execuție
de cod ca utilizatorul laptopului:
- împerechere cu o cheie pre-partajată de 32 de octeți, generată pe un capăt și
  dusă pe celălalt o singură dată (fișier 0600; interfață în kcontrol mai
  târziu); sursa acceptă doar capetele împerecheate;
- handshake: `HELLO` cu nonce-uri aleatoare de ambele părți, chei de sesiune pe
  fiecare sens derivate cu HKDF din cheia pre-partajată și nonce-uri;
- **AEAD pe fiecare pachet** (ChaCha20-Poly1305 sau AES-256-GCM, nonce = numărul
  de pachet), fereastră anti-replay; un pachet rătăcit sau falsificat e aruncat
  înainte de a fi interpretat;
- socketul se leagă de adresa/interfața configurată, nu de `0.0.0.0`;
- secretizare înainte (X25519 efemer, schema Noise folosită și de WireGuard)
  se adaugă odată cu interfața de împerechere; până atunci o cheie furată
  permite decriptarea traficului înregistrat.

Cost măsurat (`openssl speed`, blocuri de 1200 de octeți, un nucleu):

| | i3-12100 (încărcat) | i7-8565U (t590) |
|---|---|---|
| ChaCha20-Poly1305 | 1,55 GB/s | 1,71 GB/s |
| AES-256-GCM | 2,22 GB/s | 2,52 GB/s |

Adică 0,5–0,8 µs pe pachet; la 1 Gbit/s (125 MB/s) 5–8 % dintr-un nucleu, la
100 Mbit/s sub 1 %. Nu există motiv de performanță pentru a rula fără AEAD.
Sub WireGuard se poate alege „doar autentificare” ca să nu se cripteze de două
ori; „fără nimic” e permis numai pe o interfață `wg`. Implementare: OpenSSL
EVP (kdelibs depinde deja de OpenSSL).

## 9. Rețeaua de test, măsurată

`results/udp-t590.txt`; mașina locală e server, t590 inițiază (firewalld
rămâne neatins).

- **Ethernetul lui t590 negociază 100 Mbit/s** (mașina locală: 1000). Placa
  din T590 e gigabit, deci probabil cablul sau portul de switch. Banda
  utilă: ~89–95 Mbit/s.
- RTT, 1 kHz, fără trafic: 64 octeți — min 0,27, mediană 0,54, p95 2,0,
  p99 2,8 ms; 1200 octeți — mediană 1,03 ms.
- t590 → local: 0 % pierderi la 20/50/80 Mbit/s; ~1 % la 90–110 (o parte pot
  fi pachete aruncate de coada de trimitere a lui t590).
- local → t590: 0 % la 50 și 90 Mbit/s; 0,12 % la 95; 13,7 % la 110.
- RTT la 1 kHz cu un flux paralel de 50/80/93/105 Mbit/s: mediană
  1,0/1,1/2,1/2,1 ms, p99 1,7/2,9/3,9/4,1 ms.
- Wi-Fi 5 GHz (80 MHz, 2 fluxuri), doar sensul spre t590: RTT mediană 3,5,
  p95 6,4, p99 9,1, max 85 ms; 0 % pierderi până la 200 Mbit/s, 0,02 % la 300,
  saturație la ~312 Mbit/s.

Consecință: perechea locală ↔ t590 e bancul pentru cazul *degradat*
(100 Mbit/s și Wi-Fi cu vârfuri de 85 ms), nu pentru fibră. Comportamentul la
1–10 Gbit/s se poate verifica deocamdată doar pe loopback și, la sfârșit, pe
legătura reală a colegului.

## 10. Plan de implementare

Estimările sunt orientative (săptămâni de lucru concentrat).

| jalon | conținut | criteriu de ieșire | est. |
|---|---|---|---|
| M0 | acest document, măsurătorile | — | făcut |
| M1 | `libkwinremote`: pachete, pacer, ACK/NACK, codecul pe dale fără pierderi; sursă pe Xvfb `:91`, destinație ca fereastră simplă pe `:92` | imaginea destinației identică la pixel cu sursa sub o sarcină scriptată, inclusiv cu 2 % pierderi simulate | 2–3 |
| M2 | input (XTEST), cursor local, sincronizarea layoutului, autorepeat, stare la focus; instrumentarea latenței | diacritice și taste moarte corecte cu layouturi diferite la capete; histograma tastă→pixel | 1–2 |
| M3 | integrarea în KWin la destinație: `RemoteOutput`, monitor rezervat (KWin + `QDesktopWidget`), focus după pointer, grab-uri, overview, blocare, stările legăturii | o zi de lucru fără ferestre locale rătăcite pe monitor și fără taste blocate | 2–3 |
| M4 | clipboard: text, apoi imagini/HTML, apoi leneș + INCR, apoi fișiere prin `kremote:` | copy/paste de 100 MB în ambele sensuri; copiere de fișiere Konqueror ↔ Konqueror | 2 |
| M5 | hardware real: local ↔ t590 pe Ethernet și Wi-Fi; readback glamor; rezoluție/ieșire virtuală; capac închis; ecran blocat; dale JPEG și controlul ratei | utilizabil pe 100 Mbit/s; țintele de latență din §3.6 măsurate pe sistem real | 2 |
| M6 | drag and drop în ambele sensuri | fișiere trase între cele două Konqueror-uri și de pe/pe kdesktop | 2–3 |
| M7 | plugin de codec hardware, cale DRI3 fără copii, X25519 + împerechere în kcontrol, uinput pentru scroll fin | opțional, după nevoie | 2–3 |
| M8 | pilot la coleg, pe fibră | NoMachine dezinstalat | — |

**Strategia de test**
- Toate testele automate rulează pe displayuri proprii (Xvfb `:91`/`:92`),
  niciodată pe `:0`/`:1`.
- Bibliotecă: teste unitare pentru codec (dus-întors pe conținut aleator și pe
  cadrele din `gen_content.py`) și pentru protocol cu o „rețea” simulată
  determinist în proces (pierderi, reordonare, duplicare, limită de bandă).
- Cap-coadă pe două Xvfb: sarcini scriptate, comparație de hash între
  framebufferul sursei și cel al destinației după liniștire.
- Rețea proastă fără root: un proxy UDP de test în spațiul utilizatorului
  (pierderi, întârziere, jitter, limită de rată) între cele două procese.
- Latență: un client de test care își schimbă culoarea la o tastă; destinația
  măsoară tastă → pixel schimbat; histogramele se păstrează ca referință și se
  compară la fiecare modificare a codecului sau a protocolului.
- Clipboard: client de test propriu (TARGETS, INCR, 100 MB, proprietar care
  dispare în timpul transferului).
- Pe t590: input real prin ice-harness, cu nodul rezervat pe durata testelor;
  scenariile DnD, ecran blocat, capac închis, cablu scos și repus.

**Riscuri**
1. Readback-ul din GPU la captură pe Xorg/glamor (nemăsurat). Rezervă: calea
   DRI3; în cel mai rău caz codare pe GPU.
2. Controlul congestiei scris de noi, mai ales pe Wi-Fi. Rezervă: plafon de
   rată configurat manual; în ultimă instanță același format de cadre peste
   QUIC.
3. Focus și grab-uri: interacțiunea cu kdesktop_lock, cu meniurile deschise și
   cu aplicațiile care iau grab-uri proprii.
4. Puntea XDND: multe aplicații cu abateri de la protocol.
5. Sincronizarea layoutului se poate bate cu kxkb de pe laptop (indicatorul din
   tray, layout per fereastră).
6. Potrivirea rezoluției pe laptopul colegului depinde de driverul și
   conectorii lui.
7. Codecurile hardware lipsesc pe Fedora stock; faza 1 nu depinde de ele.
8. Monitorul rezervat și aplicațiile străine care citesc RandR direct.

## 11. Întrebări pentru utilizator

1. **Laptopul colegului**: ce model/GPU, ce rezoluție are panoul, stă cu
   capacul închis, are un conector video liber (pentru varianta cu conector
   forțat sau dop HDMI)? De asta depinde §7.
2. **Legătura**: ce viteză are de fapt fibra (1 sau 10 Gbit/s), MTU jumbo
   posibil? Și: Ethernetul lui t590 merge la 100 Mbit/s — cablu/switch de
   schimbat, sau îl păstrăm intenționat ca banc pentru cazul degradat?
3. **Focus**: după pointer (implicit, ca la KVM) sau la clic? Ce scurtătură
   locală de scăpare?
4. **Panoul laptopului în timpul sesiunii**: stins/întunecat (intimitate) sau
   lăsat aprins?
5. **Înainte de login** (după repornirea laptopului): e acceptabil autologin +
   blocare, sau trebuie acces și la ecranul de autentificare din prima fază?
6. **Monitorul când legătura cade**: rămâne rezervat cu ultimul cadru estompat
   sau revine imediat la desktopul local?
7. **PRIMARY** (selecția cu mouse-ul, lipire cu butonul din mijloc): se
   sincronizează și ea sau doar CLIPBOARD? Și limita pentru Klipper (§6.1)?
8. **Fișierele**: e de acord cu `kremote:` (canalul propriu expus prin KIO) în
   locul „KIO/sftp” din PLAN §7.5? Aplicațiile non-KDE rămân fără DnD de
   fișiere în prima versiune.
9. **Criptarea**: AEAD cu cheie pre-partajată activ din prima zi (5–8 % dintr-un
   nucleu la 1 Gbit/s) — de acord, sau chiar „fără nimic” până la WireGuard?
10. **Codecuri hardware**: rămân plugin opțional după faza 1 (pe Fedora cer RPM
    Fusion), sau sunt necesare mai devreme pentru un caz anume (video pe tot
    ecranul)?

## Decizii ale userului (chestionar, 21.11.2026)
- Focusul tastaturii: după poziția mouse-ului (KVM/Synergy); ieșire forțată la desktopul local: **Ctrl+Alt+Shift+Esc**.
- Legătura căzută: monitorul de la birou rămâne rezervat (ultima imagine estompată, „Reconectare…”), revine automat.
- Ecranul laptopului în timpul sesiunii: **lăsat aprins** (fără blanking pentru intimitate).
- Securitate în prima versiune: **nimic până la WireGuard** (fibra e privată); AEAD cu cheie partajată rămâne opțiune ulterioară, protocolul păstrează loc pentru ea în antet.
- Clipboard: CLIPBOARD + PRIMARY, transfer leneș (doar lista de tipuri până la paste).
- Fișiere la drag and drop: canal propriu, expus ca kioslave `kremote:` (nu sftp/fish); aplicațiile non-KDE fără DnD de fișiere în prima versiune.
- După reboot-ul laptopului: autologin + blocare imediată; ecranul de blocare se deblochează de la distanță.
- Codare video hardware: plugin după faza 1.
- Fibra: **1 Gbit/s** → proiectat pentru 1 Gbit/s: zone fără pierderi + JPEG pentru zone video; ecran întreg la 60 fps doar cu compresie.
- Laptopul colegului: GPU **Intel integrat** (VAAPI; 4:4:4 doar pe generațiile noi — de verificat modelul).
- t590: rămâne pe 100 Mbit/s deocamdată (banc de test pentru cazul degradat); userul repară link-ul mai târziu.
