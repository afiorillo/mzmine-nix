{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  dpkg,
  copyDesktopItems,
  makeDesktopItem,
  nix-update-script,

  alsa-lib,
  atk,
  cairo,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  icu,
  libGL,
  libbsd,
  openssl,
  pango,
  xdg-utils,
  xorg,
  zlib,
}:

let
  # Libraries needed by the JavaFX natives that `NativeLibLoader` unpacks from
  # javafx-*.jar into ~/.openjfx/cache at runtime. Those copies are never seen by
  # autoPatchelfHook, so they have to be resolvable via LD_LIBRARY_PATH:
  #   libglassgtk3.so       -> gtk3, gdk3, pango, pangocairo, atk, cairo(-gobject),
  #                            gdk-pixbuf, gio/gobject/glib/gthread, libXtst
  #   libprism_es2.so       -> libX11, libXxf86vm, libGL
  #   libjavafx_font_pango  -> pangoft2, pango, gobject, glib, fontconfig, freetype
  # The self-contained .NET runtimes in lib/external_tools (ThermoRawFileParser,
  # SCIEX Wiff2) dlopen ICU, OpenSSL and zlib.
  # The rest mirrors the upstream .deb's own Depends: field.
  runtimeLibs = [
    alsa-lib
    atk
    cairo
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    icu
    libGL
    libbsd
    openssl
    pango
    stdenv.cc.cc.lib
    xorg.libX11
    xorg.libXau
    xorg.libXdmcp
    xorg.libXext
    xorg.libXi
    xorg.libXrender
    xorg.libXtst
    xorg.libXxf86vm
    xorg.libxcb
    zlib
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "mzmine";
  version = "4.10.90";

  src = fetchurl {
    url = "https://github.com/mzmine/mzmine/releases/download/v${finalAttrs.version}/mzmine_${finalAttrs.version}_amd64.deb";
    hash = "sha256-Wi25uw3WNcI0/8NTWT/cg7M2czi0+tmSYvk5pVScFBw=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    dpkg
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  # Baked into the RPATH of the shipped ELFs (launcher + bundled JDK 26 runtime).
  runtimeDependencies = runtimeLibs;

  # CoreCLR's LTTng tracing provider; the runtime loads it only when available.
  autoPatchelfIgnoreMissingDeps = [ "liblttng-ust.so.0" ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  # Never touch the vendored JRE or the jars.
  dontStrip = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/mzmine"
    cp -r opt/mzmine/. "$out/share/mzmine/"

    install -Dm644 opt/mzmine/lib/mzmine.png \
      "$out/share/icons/hicolor/128x128/apps/mzmine.png"

    # The shipped lib/mzmine-mzmine.desktop hardcodes /opt/mzmine paths; we ship our own.
    rm -f "$out/share/mzmine/lib/mzmine-mzmine.desktop"

    makeWrapper "$out/share/mzmine/bin/mzmine" "$out/bin/mzmine" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
      --prefix PATH : "${lib.makeBinPath [ xdg-utils ]}"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "mzmine";
      desktopName = "mzmine";
      comment = "Mass spectrometry data processing";
      exec = "mzmine %F";
      icon = "mzmine";
      categories = [
        "Science"
        "Chemistry"
        "Education"
      ];
      startupWMClass = "mzmine";
    })
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Framework for processing, visualization and analysis of mass spectrometry data";
    longDescription = ''
      mzmine is a software for mass spectrometry data processing, covering the whole
      workflow for liquid chromatography (LC), gas chromatography (GC), ion mobility
      spectrometry (IMS) and MS imaging.

      This package repackages the official upstream Linux build, which ships its own
      jlink'd JDK 26 runtime. It is the mzio "Pro" distribution and asks you to sign in
      with an mzio account on first launch; that is upstream behaviour, not a packaging
      artifact.
    '';
    homepage = "https://mzmine.github.io";
    downloadPage = "https://github.com/mzmine/mzmine/releases";
    changelog = "https://github.com/mzmine/mzmine/releases/tag/v${finalAttrs.version}";
    # mzmine's own sources are MIT, but the distributed application image bundles
    # closed-source io.mzio components (user management, licensing) whose terms are
    # free for academic use only.
    license = with lib.licenses; [
      mit
      unfreeRedistributable
    ];
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    mainProgram = "mzmine";
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
})
