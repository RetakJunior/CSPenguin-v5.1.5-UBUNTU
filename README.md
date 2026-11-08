# Clip Studio Paint 5 — Ubuntu (Wayland) için kurulum betiği

`setup-csp5-ubuntu.sh`, [garrusdrummer/clip-studio-paint-wine-installer](https://github.com/garrusdrummer/clip-studio-paint-wine-installer) projesinin (GPL-3.0) **Ubuntu uyarlamasıdır**. Orijinal CachyOS/Arch içindir. Asıl emek ona ve şu projelere aittir: [parka6060/CSPenguin-Installer](https://github.com/parka6060/CSPenguin-Installer) (dcomp), [taron-sys/CSP5-for-Wine](https://github.com/taron-sys/CSP5-for-Wine) (dcomp yaması, WinTab), [Sylixa/WineTab](https://github.com/Sylixa/WineTab).

> **Durum: uçtan uca test EDİLDİ.**

## Neden ayrı bir betik?

CSP 5'te pencereler beyaz çıkıyor: Wine'ın `dcomp.dll` (DirectComposition) bileşeni boş bir taslak. Çözüm üç parça:

1. **wine-staging ≥ 11.19** (CSP'nin istediği WinRT sınıflarını yalnızca bu kaydediyor). Ubuntu'daki Wine 10.0 yetmez.
2. **Yamalı `dcomp.dll`**, kaynaktan derleniyor.
3. **WebView2** + özel başlatma argümanları, **XInput2 tabanlı wintab32** (Wayland'de kalem basıncı için).

## Ubuntu için değişenler

| Orijinal (Arch) | Bu betik (Ubuntu) |
|---|---|
| `pacman` | `apt` (`mingw-w64`, `build-essential`, `winetricks`, …) |
| Arch'ın `wine-staging` paketi, pacman imzasıyla doğrulanıyor | WineHQ'nun **imzalı** `.deb` paketleri (`wine-staging`, `-amd64`, `-dev`). `InRelease` imzası WineHQ anahtarıyla, paket SHA-256'ları dizinle doğrulanıyor. **Sisteme kurulmuyor**, `~/.local/share/csp5/wine` içine açılıyor. Sistemdeki `wine` 10.0'a dokunulmuyor. |
| Gecko sistem paketinden | Wine Gecko 2.47.4 indirilip runner'a konuyor (Ubuntu paketlemiyor) |
| — | Tarayıcıdan "Giriş yap → Open app" için `clipstudio://` işleyicisi |
| `csp-scale` (`strtonum`: yalnızca gawk) | Ubuntu'nun varsayılan `mawk`'ı ile çalışacak şekilde yeniden yazıldı |

Önceki 4.1.0 kurulumun (`~/.wine-csp`) **ayrı kalır**. csp5 şuralarda yaşar: `~/.local/share/csp5` (Wine + prefix), `~/.cache/csp5-installer` (indirmeler).

## Kurulum
1) Ilk olarak csp5 klasoru olustur sonra Realese kismindan CSP 5.1.5 surumunu ve zip'i indirip csp5 klasorune koy...
2)
```bash
cd csp5-ubuntu
./setup-csp5-ubuntu.sh
```

- `sudo` şifresi bir kez sorulur (apt için).
- CSP yükleyicisi (~490 MB) otomatik inecek. **CSP yükleyici penceresi açılınca** varsayılan klasörle ilerle, son sayfada **"CLIP STUDIO PAINT'i başlat" kutusunun işaretini kaldır**.
- Bitince uygulama menüsünde **CLIP STUDIO PAINT 5** çıkar. Terminalden: `clip-studio-paint`. Materyaller / giriş için: `clip-studio-paint --hub`.

Seçenekler:

| Seçenek | Anlamı |
|---|---|
| `--csp-installer DOSYA` | indirilmiş `CSP_xxxw_setup.exe` kullan |
| `CSP_VERSION=520 ./setup-csp5-ubuntu.sh` | farklı bir CSP sürümü (resmi indirme adresindeki numara). Test edilmiş olan varsayılan `515` (5.1.5) |
| `--wine-dir DIZIN` | WineHQ yerine kendi wine-staging (≥ 11.19, **wow64**, `winegcc` ve `include/wine` içeren) klasörünü kullan |
| `--skip-deps` | apt'yi çalıştırma |
| `--update-wine` | Wine runner'ını yenile |
| `--uninstall` | csp5'i kaldır (4.1.0'a dokunmaz) |

## Bilinen belirsizlikler

- **WineHQ'nun 26.10 deposu var mı?** Bilmiyorum. Betik önce kendi kod adını, yoksa `resolute` (26.04) sonra `noble` (24.04) paketlerini dener ve bunu uyarıyla belirtir. Sistem kütüphaneleri uyuşmazsa `ldd` ile eksikleri listeler.
- **WineHQ paketi WoW64 mi?** Değilse (`i386-windows` yok), betik durur ve `--wine-dir` ile bir "wow64" staging derlemesi ister.
- **Ekran kartı:** Intel HD 2500'de Vulkan yok. Bu yol Wine'ın `wined3d` (OpenGL) yolunu kullanır, DXVK **kurulmaz**. HD 2500 yalnızca OpenGL 4.2 verir. CSP 5'in Direct3D 11 gereksinimini karşılayıp karşılamayacağı ve hızı belirsiz.
- **Wayland:** Kalem basıncı için `wintab32` değişimi XWayland üzerinden XInput2 kullanıyor. XENX 1060B ile sonuç bilinmiyor.
- **Zaman atlamalı video (timelapse) dışa aktarma** Wine sınırlaması.

## Giriş (hesap) bağlantısı

Tarayıcıda "Open app" düğmesi `clipstudio://…` açar. Betik bu protokolü csp5'e yönlendirir. 4.1.0 için kurduğun işleyicinin **yerini alır**. İkisi aynı anda aynı protokolü tutamaz. Geri almak için:

```bash
xdg-mime default clipstudio-url.desktop x-scheme-handler/clipstudio
xdg-mime default clipstudio-url.desktop x-scheme-handler/clipstudiopaint
```

## Arayüz boyutu

`csp-scale` komutu mevcut ölçeği gösterir, `csp-scale 150` %150 yapar (100–300). Sonra CSP'yi yeniden başlat. GNOME/Wayland'de ölçek otomatik algılanmaz, gerekirse elle ayarla.

## Sorun ayıklama

- CSP'yi tamamen kapat: `WINEPREFIX=~/.local/share/csp5/prefix ~/.local/share/csp5/wine/bin/wineserver -k`
- Log ile başlat: `WINEDEBUG=err+all clip-studio-paint 2>&1 | tee ~/csp5-log.txt`
- Menü/ipucu sorunları: `CSP_POPUPS_LOG=1 clip-studio-paint` (log: `~/.local/share/csp5/prefix/drive_c/dcomp-csp.log`)

## Lisans

Bu klasör **GPL-3.0** altındadır (`LICENSE`), çünkü orijinal installer'ın türevidir. `src/csp_popups.cpp` orijinal projeden alınmıştır. Clip Studio Paint, WebView2 ve Wine kendi sahiplerinin yazılımlarıdır, burada dağıtılmaz.


