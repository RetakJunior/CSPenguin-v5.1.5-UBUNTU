#!/usr/bin/env bash
# setup-csp5-ubuntu.sh - Clip Studio Paint 5 icin Ubuntu (Wayland/GNOME) kurulum betigi.
#
# Bu betik, garrusdrummer/clip-studio-paint-wine-installer (GPL-3.0) projesinin Ubuntu'ya
# uyarlamasidir. Orijinal CachyOS/Arch icindir ve pacman kullanir. Degisen kisimlar:
#   * apt ile bagimliliklar
#   * wine-staging (>= 11.19), WineHQ'nun imzali .deb paketlerinden sisteme KURULMADAN
#     ~/.local/share/csp5/wine altina acilir (sistemdeki 'wine' paketine dokunulmaz)
#   * Wine Gecko 2.47.4 (Ubuntu paketlemiyor) indirilip runner'a konur
#   * "Giris yap" tarayici baglantisi (clipstudio://) icin xdg isleyicisi
# Kalan kisimlar (dcomp shim, XInput2 wintab, WebView2 ayarlari) orijinaldir.
# Kredi: garrusdrummer (installer), parka6060/CSPenguin-Installer (dcomp),
#        taron-sys/CSP5-for-Wine (dcomp yamasi, WinTab.c), Sylixa/WineTab (XWinTabHelper).
#
# Kullanim: ./setup-csp5-ubuntu.sh [--csp-installer DOSYA] [--skip-deps] [--wine-dir DIZIN]
#                                  [--update-wine] [--uninstall]
# NOT: Bu betik uzerinde calisilan makinede UCTAN UCA TEST EDILMEDI (bkz. README.md).
set -euo pipefail

# ---- ayarlar ----------------------------------------------------------------
CSP_VERSION=${CSP_VERSION:-515}   # 515 = 5.1.5 (test edilmis surum); indirme adresi icin
CSP_URL="https://vd.clipstudio.net/clipcontent/paint/app/${CSP_VERSION}/CSP_${CSP_VERSION}w_setup.exe"

WEBVIEW2_URL="https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/79f5276c-391e-481d-9e0f-50d730ae66a9/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
WEBVIEW2_MD5="39d6235aa199e156491d348c3ea02089"

GECKO_VERSION="2.47.4"
GECKO_URL="https://dl.winehq.org/wine/wine-gecko/${GECKO_VERSION}"

# dcomp shim: CSPenguin-Installer kaynagi + CSP5-for-Wine Linux yamasi (sabit surum, SHA-256 kontrollu)
DCOMP_SRC_URL="https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/868d022adfdc3740449241f4721debbf4b1b1426/patches/dcomp"
DCOMP_PATCH_URL="https://raw.githubusercontent.com/taron-sys/CSP5-for-Wine/f08c62c5fb322cdc78fd17dd26de5300b429e590/bundle/files/src/dcomp-csp-linux.patch"
DCOMP_CPP_SHA256="e516fd33b7da2452a90b96a9bbb42920564afd1a91d4ba629cad34acfb0cc83a"
DCOMP_DEF_SHA256="319c1a01d6ca059c5127f62a4a6250ccead3af8ae1f4b335b7c2b1f7fe8b4e92"
DCOMP_PATCH_SHA256="1e7488090f73c3a9195c868d90ee08dedfd2a877e1f96b873fec02e195c574bb"

# kalem basinci: XInput2 tabanli wintab32 (Wayland/XWayland icin)
WINTAB_DLL_URL="https://raw.githubusercontent.com/taron-sys/CSP5-for-Wine/5334f1414faa46282037adf32e51fa2f56bd2bbe/diag/csp-wintab"
WINTAB_HELPER_URL="https://raw.githubusercontent.com/Sylixa/WineTab/14bc8e4d7ad0c1729f771071ec8c48c35d3a0c7c/build64"
WINTAB_SHA256=(
    "WinTab.c 1aa059cba12611c9a4c02232080e1a689a0c1a23865deb4cc1b22f7a66871ac0"
    "wintab.h f675d846155b7e4f7ead057e70cfcd64da46c2b25d2c0e235448be668ba1e0f9"
    "wintab32.def 386d9838495246206ec6d5b1c1395aeed68f08c9583f5d5b321ea9f19f564821"
    "XWinTabTypes.h 2225f949cb07ae510eb92b58957cac501902756c1b9288b933c8951998f94753"
    "LICENSE c1b91abf430e15612956476c06111fda3dd82c32e397d0fc0aa4f428d4148df2"
    "XWinTabHelper.c 4c58e929b1cf3b6a41f5d642c8750e8d3dd8119dd931732a5a1fe967d88de66a"
    "XWinTabHelper.dll.spec 93c86246964677101d9b507036e446b304cd2ddf2345e73d9cb18be9cae8c623"
)

MIN_WINE_VERSION="11.19"
WINEHQ_URL="https://dl.winehq.org/wine-builds"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

BASE=${CSP_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/csp5}
WINE_DIR="$BASE/wine"
PREFIX="$BASE/prefix"
SHIM="$BASE/dcomp.dll"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/csp5-installer"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
LAUNCHER="$BIN_DIR/clip-studio-paint"
URL_HANDLER="$BIN_DIR/csp5-url-handler"
CELSYS_DIR="$PREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5"

APT_PACKAGES=(
    mingw-w64 build-essential curl xz-utils patch cabextract winetricks icoutils
    gnupg gpgv libxcb1-dev libxcb-xinput-dev wine
)

# ---- yardimcilar ------------------------------------------------------------
say()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m==> UYARI:\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m==> HATA:\e[0m %s\n' "$*" >&2; exit 1; }

wine_env() {
    export WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG=-all
    export WINE="$WINE_DIR/bin/wine" WINESERVER="$WINE_DIR/bin/wineserver"
    # winetricks ve wine, bu runner'in wineserver'ini bulsun
    export PATH="$WINE_DIR/bin:$PATH"
    # Wine kendi menu kisayollarini yapmasin (yanlis wine'a isaret ederlerdi); mono istemi cikmasin
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d"
}
wine_run()  { "$WINE_DIR/bin/wine" "$@"; }
wine_wait() { "$WINE_DIR/bin/wineserver" -w; }

# URL'yi DOSYA'ya indir (varsa tekrar indirme)
fetch() {
    local url=$1 out=$2
    [[ -s $out ]] && return 0
    say "Indiriliyor: ${url##*/}"
    curl -fL --retry 3 -o "$out.part" "$url"
    mv "$out.part" "$out"
}

check_sha256() { echo "$2  $1" | sha256sum -c --quiet - || die "sağlama toplamı (SHA-256) uyuşmuyor: $1"; }

# ---- WineHQ paket dizini (imza dogrulamali) ---------------------------------
# WineHQ'nun apt deposundaki InRelease imzasi WineHQ anahtariyla (gpgv) dogrulanir,
# Packages.xz bu dosyadaki SHA-256 ile, .deb'ler de Packages icindeki SHA-256 ile denetlenir.
winehq_keyring() {
    local ring="$CACHE/winehq.gpg"
    if [[ ! -s $ring ]]; then
        local gh; gh=$(mktemp -d)
        curl -fsSL --retry 3 "$WINEHQ_URL/winehq.key" | gpg --homedir "$gh" --dearmor > "$ring.part"
        rm -rf "$gh"
        mv "$ring.part" "$ring"
    fi
    echo "$ring"
}

# winehq_index CODENAME  ->  WH_INDEX = acilmis Packages dosyasinin yolu
winehq_index() {
    local cn=$1 dir="$CACHE/winehq-$1" base="$WINEHQ_URL/ubuntu/dists/$1" ring want="" sum="" ext="" err
    mkdir -p "$dir"; rm -f "$dir/InRelease" "$dir/Release" "$dir/Release.gpg" "$dir"/Packages*
    err="$dir/curl.err"
    ring=$(winehq_keyring) || { warn "WineHQ anahtarı indirilemedi ($WINEHQ_URL/winehq.key)"; return 1; }

    # WineHQ'da InRelease olmayabilir: once InRelease, yoksa Release + Release.gpg (ayrik imza)
    if curl -fsSL --retry 2 -o "$dir/InRelease" "$base/InRelease" 2>"$err"; then
        gpgv --keyring "$ring" --output "$dir/Release" "$dir/InRelease" >/dev/null 2>&1 \
            || { warn "$cn: InRelease imzası doğrulanamadı"; return 1; }
    elif curl -fsSL --retry 2 -o "$dir/Release" "$base/Release" 2>"$err" \
         && curl -fsSL --retry 2 -o "$dir/Release.gpg" "$base/Release.gpg" 2>"$err"; then
        gpgv --keyring "$ring" "$dir/Release.gpg" "$dir/Release" >/dev/null 2>&1 \
            || { warn "$cn: Release imzası doğrulanamadı"; return 1; }
    else
        warn "$cn: Release dosyası indirilemedi ($base): $(tr '\n' ' ' < "$err")"
        return 1
    fi

    # amd64 paket dizini: .xz, .gz ya da duz (Release'te hangisi listeliyse)
    for ext in xz gz ""; do
        want="main/binary-amd64/Packages${ext:+.$ext}"
        sum=$(release_sha256 "$dir/Release" "$want")
        [[ -n $sum ]] && break
    done
    [[ -n $sum ]] || { warn "$cn: Release içinde main/binary-amd64/Packages yok"; return 1; }
    curl -fsSL --retry 2 -o "$dir/Packages.dl" "$base/$want" 2>"$err" \
        || { warn "$cn: $want indirilemedi: $(tr '\n' ' ' < "$err")"; return 1; }
    echo "$sum  $dir/Packages.dl" | sha256sum -c --quiet - 2>/dev/null \
        || { warn "$cn: $want sağlama toplamı uyuşmuyor"; return 1; }
    case $ext in
        xz) xz -dc "$dir/Packages.dl" > "$dir/Packages" ;;
        gz) gzip -dc "$dir/Packages.dl" > "$dir/Packages" ;;
        *)  cp "$dir/Packages.dl" "$dir/Packages" ;;
    esac
    WH_INDEX="$dir/Packages"
}

# release_sha256 RELEASE_DOSYASI YOL -> o YOL'un SHA256 degeri
release_sha256() {
    awk -v w="$2" '
        /^SHA256:/ { f = 1; next }
        /^[^ ]/    { f = 0 }
        f && $3 == w { print $1; exit }' "$1"
}

# pkg_info PAKET PACKAGES_DOSYASI -> "surum dosya sha256" (en yuksek surum)
pkg_info() {
    awk -v want="$1" 'BEGIN { RS = ""; FS = "\n" }
        {
            p = ""; v = ""; f = ""; s = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /)       p = substr($i, 10)
                else if ($i ~ /^Version: /)  v = substr($i, 10)
                else if ($i ~ /^Filename: /) f = substr($i, 11)
                else if ($i ~ /^SHA256: /)   s = substr($i, 9)
            }
            if (p == want) print v, f, s
        }' "$2" | sort -V -k1,1 | tail -n1
}

# version_ge A B -> A >= B (sayisal "11.19" bicimi)
version_ge() { [[ $(printf '%s\n' "$2" "$1" | sort -V | head -n1) == "$2" ]]; }

# surum_sayisi "11.19~resolute-1" -> 11.19
deb_upstream() { local v=$1; v=${v#*:}; [[ $v =~ ^([0-9]+\.[0-9]+) ]] && echo "${BASH_REMATCH[1]}"; }

# ---- adimlar ----------------------------------------------------------------
preflight() {
    [[ $EUID -ne 0 ]] || die "Normal kullanıcıyla çalıştır, root ile değil"
    [[ $(uname -m) == x86_64 ]] || die "Yalnızca x86_64"
    [[ -f $SCRIPT_DIR/src/csp_popups.cpp ]] || die "src/csp_popups.cpp yok - klasörün tamamını kopyala"
    command -v apt-get >/dev/null || die "apt-get bulunamadı - bu betik Ubuntu/Debian içindir"
    mkdir -p "$BASE" "$CACHE" "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"
}

install_deps() {
    say "apt ile bağımlılıklar kuruluyor (sudo şifresi sorulabilir)"
    sudo apt-get update
    sudo apt-get install -y "${APT_PACKAGES[@]}"
}

check_tools() {
    local t missing=()
    for t in curl xz tar x86_64-w64-mingw32-g++ x86_64-w64-mingw32-gcc patch winetricks cabextract gpg gpgv dpkg-deb gcc; do
        command -v "$t" >/dev/null || missing+=("$t")
    done
    ((${#missing[@]} == 0)) || die "eksik araçlar: ${missing[*]} (--skip-deps olmadan çalıştır)"
}

# Gecko MSI'lari runner'in share/wine/gecko klasorune: wineboot sessizce kurar
place_gecko() {
    local dir=$1/share/wine/gecko arch
    mkdir -p "$dir"
    for arch in x86 x86_64; do
        fetch "$GECKO_URL/wine-gecko-${GECKO_VERSION}-${arch}.msi" "$CACHE/wine-gecko-${GECKO_VERSION}-${arch}.msi"
        cp -f "$CACHE/wine-gecko-${GECKO_VERSION}-${arch}.msi" "$dir/"
    done
}

# runner'in calistigini, staging surumunu ve eksik kutuphaneleri denetle
verify_runner() {
    local root=$1 version missing lib
    [[ -x $root/bin/wine ]] || die "$root/bin/wine yok (WoW64 derlemesi gerekli)"
    [[ -x $root/bin/winegcc && -d $root/include/wine ]] || die "winegcc / include/wine yok (geliştirme dosyaları gerekli)"
    version=$("$root/bin/wine" --version) || die "açılan wine çalışmıyor"
    [[ $version == *Staging* ]] || die "$version bir staging derlemesi değil"
    version=${version#wine-}; version=${version%% *}
    version_ge "$version" "$MIN_WINE_VERSION" || die "wine-staging $version çok eski ($MIN_WINE_VERSION veya üstü gerekli)"
    # eksik paylasilan kutuphaneler
    missing=""
    for lib in "$root"/lib*/wine/x86_64-unix/ntdll.so "$root"/lib*/wine/x86_64-unix/winex11.so; do
        [[ -f $lib ]] || continue
        missing+=$(ldd "$lib" 2>/dev/null | awk '/not found/ { print $1 }')$'\n'
    done
    missing=$(printf '%s' "$missing" | sort -u | sed '/^$/d')
    if [[ -n $missing ]]; then
        warn "Wine'ın şu kütüphaneleri sistemde bulunamadı:"; printf '    %s\n' $missing >&2
        warn "Gerekirse apt ile ilgili paketleri kur (sudo apt install ... ) ve betiği tekrar çalıştır."
    fi
}

install_wine_from_dir() {
    local src=$1 tmp="$BASE/wine.new"
    [[ -d $src ]] || die "Runner klasörü yok: $src"
    rm -rf "$tmp"; cp -a "$src" "$tmp"
    place_gecko "$tmp"
    verify_runner "$tmp"
    rm -rf "$WINE_DIR"; mv "$tmp" "$WINE_DIR"
    say "Wine runner: $("$WINE_DIR/bin/wine" --version) (elle verilen: $src)"
}

# WineHQ'nun imzali .deb'lerini sisteme kurmadan ac
install_wine_from_winehq() {
    . /etc/os-release
    local cn WH_INDEX="" candidates=("${VERSION_CODENAME:-}" resolute noble) tried=""
    for cn in "${candidates[@]}"; do
        [[ -n $cn && $tried != *" $cn "* ]] || continue
        tried+=" $cn "
        say "WineHQ dizini deneniyor: $cn"
        if winehq_index "$cn"; then
            [[ $cn == "${VERSION_CODENAME:-}" ]] || warn "WineHQ'da '${VERSION_CODENAME:-?}' için depo yok, '$cn' paketleri kullanılacak"
            break
        fi
        WH_INDEX=""
    done
    [[ -n $WH_INDEX ]] || die "WineHQ dizinine ulaşılamadı. Elle bir wine-staging >= $MIN_WINE_VERSION (wow64) indirip --wine-dir DIZIN ile ver."

    say "WineHQ dizinindeki wine-staging paketleri:"
    { grep -h '^Package: wine-staging' "$WH_INDEX" | sort -u | sed 's/^Package: /    /'; } >&2 || true

    local name info ver file sum deb debs=() upstream
    for name in wine-staging wine-staging-amd64 wine-staging-dev; do
        info=$(pkg_info "$name" "$WH_INDEX")
        if [[ -z $info ]]; then
            [[ $name != wine-staging ]] || die "WineHQ dizininde 'wine-staging' paketi yok. --wine-dir ile kendi runner'ını ver."
            warn "'$name' paketi bu dizinde yok, atlanıyor (gerekirse sonraki adımlar uyarır)"
            continue
        fi
        read -r ver file sum <<<"$info"
        if [[ $name == wine-staging ]]; then
            upstream=$(deb_upstream "$ver")
            [[ -n $upstream ]] || die "WineHQ sürümü okunamadı: $ver"
            version_ge "$upstream" "$MIN_WINE_VERSION" \
                || die "WineHQ'daki wine-staging $upstream, gereken $MIN_WINE_VERSION'dan eski. --wine-dir ile daha yeni bir runner ver."
            say "WineHQ: wine-staging $ver"
        fi
        deb="$CACHE/${file##*/}"
        if [[ ! -s $deb ]] || ! echo "$sum  $deb" | sha256sum -c --quiet - 2>/dev/null; then
            rm -f "$deb"
            fetch "$WINEHQ_URL/ubuntu/$file" "$deb"
            check_sha256 "$deb" "$sum"
        fi
        debs+=("$deb")
    done

    say "Paketler açılıyor"
    local tmp="$BASE/wine.new"
    rm -rf "$tmp" "$BASE/wine.x"; mkdir -p "$BASE/wine.x"
    for deb in "${debs[@]}"; do dpkg-deb -x "$deb" "$BASE/wine.x"; done
    [[ -d $BASE/wine.x/opt/wine-staging ]] || die "paket yapısı beklenmedik (opt/wine-staging yok)"
    mv "$BASE/wine.x/opt/wine-staging" "$tmp"
    rm -rf "$BASE/wine.x"
    if ! find "$tmp" -type d -name i386-windows | grep -q .; then
        die "Bu WineHQ paketi WoW64 değil (i386-windows yok). --wine-dir ile bir 'wow64' staging derlemesi ver."
    fi
    place_gecko "$tmp"
    verify_runner "$tmp"
    rm -rf "$WINE_DIR"; mv "$tmp" "$WINE_DIR"
    say "Wine runner: $("$WINE_DIR/bin/wine" --version)"
}

install_wine() {
    if [[ -n ${WINE_RUNNER:-} ]]; then install_wine_from_dir "$WINE_RUNNER"
    else install_wine_from_winehq; fi
}

build_shim() {
    local dir="$CACHE/dcomp"
    mkdir -p "$dir"
    fetch "$DCOMP_SRC_URL/dcomp_csp.cpp" "$dir/dcomp_csp.cpp"
    fetch "$DCOMP_SRC_URL/dcomp.def"     "$dir/dcomp.def"
    fetch "$DCOMP_PATCH_URL"             "$dir/dcomp-csp-linux.patch"
    check_sha256 "$dir/dcomp_csp.cpp"         "$DCOMP_CPP_SHA256"
    check_sha256 "$dir/dcomp.def"             "$DCOMP_DEF_SHA256"
    check_sha256 "$dir/dcomp-csp-linux.patch" "$DCOMP_PATCH_SHA256"

    say "DirectComposition shim derleniyor"
    local build="$dir/build"
    rm -rf "$build"; mkdir -p "$build"
    cp "$dir/dcomp_csp.cpp" "$dir/dcomp.def" "$build/"
    patch -s -p1 -d "$build" dcomp_csp.cpp < "$dir/dcomp-csp-linux.patch"
    # src/csp_popups.cpp: CSP menulerini pencere yoneticisinden uzak tutar
    x86_64-w64-mingw32-g++ -shared -static -O2 -std=c++17 -w \
        -o "$build/dcomp.dll" "$build/dcomp_csp.cpp" "$SCRIPT_DIR/src/csp_popups.cpp" "$build/dcomp.def" \
        -lole32 -lgdi32 -luser32 -ldxgi -ld3d11 -luuid
    install -m644 "$build/dcomp.dll" "$SHIM"
}

# XInput2 Wintab: wintab32.dll (PE, mingw) + XWinTabHelper.dll.so (native, bu runner'in winegcc'siyle)
build_wintab() {
    local dir="$CACHE/wintab" entry name sum url
    mkdir -p "$dir"
    for entry in "${WINTAB_SHA256[@]}"; do
        name=${entry% *}; sum=${entry#* }
        case $name in XWinTabHelper.*) url=$WINTAB_HELPER_URL ;; *) url=$WINTAB_DLL_URL ;; esac
        fetch "$url/$name" "$dir/$name"
        check_sha256 "$dir/$name" "$sum"
    done

    say "XInput2 Wintab derleniyor (kalem basıncı)"
    local build="$dir/build"
    rm -rf "$build"; mkdir -p "$build"
    for entry in "${WINTAB_SHA256[@]}"; do cp "$dir/${entry% *}" "$build/"; done
    (cd "$build" &&
        x86_64-w64-mingw32-gcc -shared -O2 -w -o wintab32.dll WinTab.c wintab32.def -luser32 -lgdi32 &&
        "$WINE_DIR/bin/winegcc" -shared -O2 -w -o XWinTabHelper.dll.so XWinTabHelper.c XWinTabHelper.dll.spec \
            -lxcb -lxcb-xinput)
    mkdir -p "$BASE/wintab"
    install -m644 "$build/wintab32.dll" "$build/LICENSE" "$BASE/wintab/"
    install -m755 "$build/XWinTabHelper.dll.so" "$BASE/wintab/"
}

# Wintab dosyalarini CLIPStudioPaint.exe'nin yanina koy, yalnizca o program icin native yap
install_wintab() {
    local paint="$CELSYS_DIR/CLIP STUDIO PAINT"
    [[ -d $paint ]] || return 0
    cp -f "$BASE/wintab/wintab32.dll" "$BASE/wintab/XWinTabHelper.dll.so" "$paint/"
    cp -f "$BASE/wintab/LICENSE" "$paint/LICENSE-XWinTab.txt"
    wine_run reg add 'HKCU\Software\Wine\AppDefaults\CLIPStudioPaint.exe\DllOverrides' \
        /v wintab32 /d native /f >/dev/null
}

# Windows "Documents" (CSP'nin varsayilan kayit yeri) -> ~/Documents yerine ev dizini
link_documents_to_home() {
    local docs="$PREFIX/drive_c/users/$USER/Documents"
    [[ $(readlink "$docs" 2>/dev/null) == "$HOME" ]] && return 0
    if [[ -L $docs || ! -e $docs ]]; then
        rm -f "$docs"
    elif ! rmdir "$docs" 2>/dev/null; then
        warn "$docs boş olmayan bir klasör, dokunmuyorum"
        return 0
    fi
    ln -s "$HOME" "$docs"
}

init_prefix() {
    wine_env
    if [[ ! -f $PREFIX/system.reg ]]; then
        say "Wine prefix oluşturuluyor: $PREFIX"
        wine_run wineboot -i
        wine_wait
    fi
    say "Prefix ayarlanıyor"
    wine_run reg add 'HKCU\Software\Wine' /v Version /d win10 /f >/dev/null
    wine_run reg add 'HKCU\Software\Wine\DllOverrides' /v dcomp /d 'native,builtin' /f >/dev/null
    wine_run reg add 'HKCU\Software\Wine\DllOverrides' /v winemenubuilder.exe /d '' /f >/dev/null
    # arayuz olcegi: CSP, Windows DPI'yi izler (96 = %100). CSP_DPI ile ver; yoksa X11 DPI'si (varsa)
    local dpi=${CSP_DPI:-}
    if [[ -z $dpi ]] && command -v xrdb >/dev/null; then
        dpi=$(xrdb -query 2>/dev/null | awk '/^Xft.dpi:/ { printf "%d", $2 }')
    fi
    if [[ $dpi =~ ^[0-9]+$ ]]; then
        wine_run reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null
    fi
    wine_wait
    install -m644 "$SHIM" "$PREFIX/drive_c/windows/system32/dcomp.dll"
    link_documents_to_home

    if ! grep -q corefonts "$PREFIX/winetricks.log" 2>/dev/null; then
        say "Çekirdek yazı tipleri kuruluyor (winetricks)"
        winetricks -q corefonts
        wine_wait
    fi
}

install_webview2() {
    wine_env
    if compgen -G "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/*/msedgewebview2.exe" >/dev/null; then
        say "WebView2 zaten kurulu"
    else
        local exe="$CACHE/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
        fetch "$WEBVIEW2_URL" "$exe"
        echo "$WEBVIEW2_MD5  $exe" | md5sum -c --quiet - || die "WebView2 yükleyicisinin sağlama toplamı uyuşmuyor"
        say "Microsoft Edge WebView2 kuruluyor (birkaç dakika, pencere açılmaz)"
        wine_run "$exe" /silent /install || true
        local i
        for ((i = 0; i < 120; i++)); do
            compgen -G "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/*/msedgewebview2.exe" >/dev/null && break
            sleep 5
        done
        # yukleyici "MicrosoftEdgeUpdate.exe /c" islemini acik birakir; kapat
        sleep 10
        wine_run taskkill /f /im MicrosoftEdgeUpdate.exe >/dev/null 2>&1 || true
        timeout 60 "$WINE_DIR/bin/wineserver" -w || "$WINE_DIR/bin/wineserver" -k || true
        compgen -G "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/*/msedgewebview2.exe" >/dev/null \
            || die "WebView2 kurulumu başarısız"
    fi
    # WebView2'yi test edilen surumde tut: EdgeUpdate her acilista baslamasin
    local svc
    for svc in edgeupdate edgeupdatem; do
        wine_run reg add "HKLM\\System\\CurrentControlSet\\Services\\$svc" /v Start /t REG_DWORD /d 4 /f >/dev/null 2>&1 || true
    done
    wine_wait
}

install_csp() {
    wine_env
    if [[ -f "$CELSYS_DIR/CLIP STUDIO PAINT/CLIPStudioPaint.exe" ]]; then
        say "Clip Studio Paint zaten kurulu (sıfırdan kurmak için $PREFIX klasörünü sil)"
    else
        local exe=${CSP_INSTALLER:-$CACHE/CSP_${CSP_VERSION}w_setup.exe}
        [[ -n ${CSP_INSTALLER:-} ]] || fetch "$CSP_URL" "$exe"
        [[ -f $exe ]] || die "yükleyici bulunamadı: $exe"
        say "Clip Studio Paint yükleyicisi açılıyor - varsayılan klasörle ilerle."
        say "Son sayfada 'CLIP STUDIO PAINT'i başlat' seçeneği varsa İŞARETİNİ KALDIR."
        wine_run "$exe" || true
        wine_wait
        [[ -f "$CELSYS_DIR/CLIP STUDIO PAINT/CLIPStudioPaint.exe" ]] || die "CLIPStudioPaint.exe bulunamadı - kurulum tamamlandı mı?"
    fi
    # uygulama klasorlerindeki shim kopyalari system32'dekinden once yuklenir
    local d
    for d in "CLIP STUDIO PAINT" "CLIP STUDIO"; do
        if [[ -d "$CELSYS_DIR/$d" ]]; then install -m644 "$SHIM" "$CELSYS_DIR/$d/dcomp.dll"; fi
    done
    install_wintab
}

write_csp_scale() {
    cat > "$BIN_DIR/csp-scale" <<'EOF'
#!/usr/bin/env bash
# csp-scale - Clip Studio Paint 5 arayuz olcegini goster/degistir (prefix'in Wine DPI'si)
#   csp-scale        mevcut olcegi gosterir
#   csp-scale 150    %150 yapar (100-300)
set -euo pipefail
BASE=${CSP_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/csp5}
export WINEPREFIX="$BASE/prefix" WINEDEBUG=-all
WINE="$BASE/wine/bin/wine"
KEY='HKCU\Control Panel\Desktop'
[[ -x $WINE && -d $WINEPREFIX ]] || { echo "Clip Studio Paint $BASE içinde kurulu değil" >&2; exit 1; }
if (($# == 0)); then
    raw=$("$WINE" reg query "$KEY" /v LogPixels 2>/dev/null | awk '/LogPixels/ { print $NF }' || true)
    dpi=$(printf '%d' "${raw:-96}" 2>/dev/null || echo 96)
    echo "Mevcut ölçek: $((dpi * 100 / 96)) % (DPI $dpi)"
    echo "Değiştirmek için: ${0##*/} <yüzde>   örn. ${0##*/} 150"
    exit 0
fi
percent=${1%\%}
if [[ ! $percent =~ ^[0-9]+$ ]] || ((percent < 100 || percent > 300)); then
    echo "Kullanım: ${0##*/} [yüzde]   (100-300)" >&2; exit 1
fi
dpi=$((percent * 96 / 100))
"$WINE" reg add "$KEY" /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null
echo "Ölçek %$percent yapıldı (DPI $dpi)."
pgrep -f 'CLIPStudioPaint\.exe' >/dev/null && echo "Clip Studio Paint açık: uygulamak için yeniden başlat."
exit 0
EOF
    chmod +x "$BIN_DIR/csp-scale"
}

install_launcher() {
    say "Başlatıcı oluşturuluyor: $LAUNCHER"
    cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# Clip Studio Paint 5'i baslat (csp5 kurucusu uretti). '--hub' CLIP STUDIO'yu (materyaller) acar.
BASE="$BASE"
export WINEPREFIX="\$BASE/prefix" WINEDEBUG=\${WINEDEBUG:--all}
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox --in-process-gpu --disable-gpu-vsync --no-first-run --disable-sync --disable-extensions --disable-features=msEdgeSidebar"
WINE="\$BASE/wine/bin/wine"
APP="\$WINEPREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5"

# prefix guncellemesi stub dcomp.dll'i geri getirebilir - shim'i yerine koy
cmp -s "\$BASE/dcomp.dll" "\$WINEPREFIX/drive_c/windows/system32/dcomp.dll" \\
    || cp "\$BASE/dcomp.dll" "\$WINEPREFIX/drive_c/windows/system32/dcomp.dll"

if [[ \${1:-} == --hub ]]; then
    shift; cd "\$APP/CLIP STUDIO" && exec "\$WINE" CLIPStudio.exe "\$@"
fi

# Linux dosya yollarini (dosya yoneticisinden) Windows yoluna cevir
args=()
for a in "\$@"; do
    if [[ -e \$a ]]; then args+=("\$("\$WINE" winepath -w "\$a" 2>/dev/null)"); else args+=("\$a"); fi
done
cd "\$APP/CLIP STUDIO PAINT" && exec "\$WINE" CLIPStudioPaint.exe "\${args[@]}"
EOF
    chmod +x "$LAUNCHER"
    write_csp_scale

    # tarayicidaki "Giris yap -> Open app" baglantisi (clipstudio:// ve clipstudiopaint://):
    # Wine'in kendi kayit defteri baglantiyi dogru exe'ye verir
    cat > "$URL_HANDLER" <<EOF
#!/usr/bin/env bash
export WINEPREFIX="$BASE/prefix" WINEDEBUG=-all
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox --in-process-gpu --disable-gpu-vsync --no-first-run --disable-sync --disable-extensions --disable-features=msEdgeSidebar"
exec "$BASE/wine/bin/wine" start "\$1"
EOF
    chmod +x "$URL_HANDLER"

    local icon=applications-graphics png
    if command -v wrestool >/dev/null && command -v icotool >/dev/null; then
        local tmp; tmp=$(mktemp -d)
        if wrestool -x -t 14 "$CELSYS_DIR/CLIP STUDIO PAINT/CLIPStudioPaint.exe" > "$tmp/csp.ico" 2>/dev/null \
           && icotool -x -o "$tmp" "$tmp/csp.ico" 2>/dev/null; then
            png=$(ls -S "$tmp"/*.png 2>/dev/null | head -n1)
            if [[ -n $png ]]; then
                install -m644 "$png" "$ICON_DIR/clip-studio-paint.png"
                icon=clip-studio-paint
            fi
        fi
        rm -rf "$tmp"
    fi

    cat > "$APPS_DIR/clip-studio-paint.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CLIP STUDIO PAINT 5
Comment=Çizim ve boyama (Wine ile)
Exec="$LAUNCHER" %f
Icon=$icon
Categories=Graphics;2DGraphics;RasterGraphics;
StartupWMClass=clipstudiopaint.exe
Actions=Hub;

[Desktop Action Hub]
Name=CLIP STUDIO (merkez / materyaller)
Exec="$LAUNCHER" --hub
EOF
    cat > "$APPS_DIR/clipstudio-url-v5.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CLIP STUDIO 5 giriş yöneticisi
Exec="$URL_HANDLER" %u
MimeType=x-scheme-handler/clipstudio;x-scheme-handler/clipstudiopaint;
NoDisplay=true
Terminal=false
EOF
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    xdg-mime default clipstudio-url-v5.desktop x-scheme-handler/clipstudio 2>/dev/null || true
    xdg-mime default clipstudio-url-v5.desktop x-scheme-handler/clipstudiopaint 2>/dev/null || true
}

uninstall_all() {
    # CSP_HOME yanlislikla ev dizini ya da kok olarak verilirse silme
    case $BASE in
        /|"$HOME"|"$HOME/"|"$HOME/.wine-csp"|"$HOME/.local"|"$HOME/.local/share")
            die "Güvenlik: $BASE silinmez. CSP_HOME'u kontrol et." ;;
    esac
    [[ -d $BASE/prefix || -d $BASE/wine ]] || warn "$BASE içinde csp5 kurulumu görünmüyor, yine de temizleniyor"
    say "csp5 kaldırılıyor ($BASE). 4.1.0 kurulumun (~/.wine-csp) ETKİLENMEZ."
    rm -rf "$BASE"
    rm -f "$LAUNCHER" "$URL_HANDLER" "$BIN_DIR/csp-scale" \
          "$APPS_DIR/clip-studio-paint.desktop" "$APPS_DIR/clipstudio-url-v5.desktop" \
          "$ICON_DIR/clip-studio-paint.png"
    if [[ -f $APPS_DIR/clipstudio-url.desktop ]]; then
        xdg-mime default clipstudio-url.desktop x-scheme-handler/clipstudio 2>/dev/null || true
        xdg-mime default clipstudio-url.desktop x-scheme-handler/clipstudiopaint 2>/dev/null || true
        say "Giriş bağlantıları eski (4.1.0) işleyiciye geri verildi."
    fi
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    say "İndirme önbelleği: $CACHE (istersen elle sil)."
}

usage() {
    cat <<EOF
Kullanım: $0 [seçenekler]
  --csp-installer DOSYA  CSP $CSP_VERSION'i indirmek yerine yerel CSP_xxxw_setup.exe kullan
  --skip-deps            apt'yi çalıştırma (bağımlılıklar kurulu)
  --wine-dir DIZIN       WineHQ yerine kendi wine-staging (>= $MIN_WINE_VERSION, wow64, winegcc'li) klasörünü kullan
  --update-wine          yalnızca Wine runner'ını yenile ve prefix'i güncelle
  --uninstall            csp5'i kaldır (4.1.0'a dokunmaz)
  -h, --help             bu yardım
Ortam: CSP_HOME (kurulum dizini, varsayılan $BASE), CSP_VERSION (varsayılan $CSP_VERSION),
       CSP_DPI (arayüz ölçeği, 96 = %100; verilmezse X11 DPI'si)
EOF
}

main() {
    local skip_deps=0 update_wine=0 do_uninstall=0
    while (($#)); do
        case $1 in
            --csp-installer) [[ -n ${2:-} ]] || die "--csp-installer bir dosya ister"; CSP_INSTALLER=$(realpath "$2"); shift 2 ;;
            --wine-dir) [[ -n ${2:-} ]] || die "--wine-dir bir klasör ister"; WINE_RUNNER=$(realpath "$2"); shift 2 ;;
            --skip-deps) skip_deps=1; shift ;;
            --update-wine) update_wine=1; shift ;;
            --uninstall) do_uninstall=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) usage; die "bilinmeyen seçenek: $1" ;;
        esac
    done

    if ((do_uninstall)); then uninstall_all; exit 0; fi

    preflight
    ((skip_deps)) || install_deps
    check_tools

    if ((update_wine)); then
        install_wine
        wine_env; wine_run wineboot -u; wine_wait
        install -m644 "$SHIM" "$PREFIX/drive_c/windows/system32/dcomp.dll"
        link_documents_to_home
        build_wintab   # yerel yardımcı, çalıştığı Wine'a karşı derlenir
        install_wintab
        wine_wait
        say "Wine runner güncellendi."
        exit 0
    fi

    install_wine
    build_shim
    build_wintab
    init_prefix
    install_webview2
    install_csp
    install_launcher
    say "Bitti. Uygulama menüsünden başlat ya da çalıştır: $LAUNCHER"
    say "Giriş bağlantıları artık csp5'e yönlendiriliyor (4.1.0 işleyicisinin yerine)."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
