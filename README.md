# mzmine-nix

Nix packaging for [mzmine](https://github.com/mzmine/mzmine) — a framework for processing,
visualization and analysis of mass spectrometry data.

Installable straight from this repository today; the derivation is written so it can be
lifted into nixpkgs later with minimal changes.

**Platform:** `x86_64-linux` only — that is the only Linux build upstream publishes.

## Install

mzmine is marked **unfree** (see [Licensing](#licensing)). `flake.nix` and `default.nix`
each instantiate nixpkgs with `config.allowUnfree = true`, so installing from this
repository works as-is. The overlay is the exception: it is governed by *your* nixpkgs
config, so allow mzmine there yourself.

### Try it without installing

```sh
nix run github:afiorillo/mzmine-nix
```

### Imperative install

```sh
nix profile install github:afiorillo/mzmine-nix#mzmine
```

### NixOS / home-manager, via the overlay

```nix
{
  inputs.mzmine-nix.url = "github:afiorillo/mzmine-nix";

  # in your configuration:
  nixpkgs.overlays = [ inputs.mzmine-nix.overlays.default ];

  # allow just this one unfree package rather than all of them
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "mzmine" ];

  environment.systemPackages = [ pkgs.mzmine ];
}
```

### Without flakes

Builds against your `<nixpkgs>` channel rather than the pinned `flake.lock`.

```sh
nix-build -A mzmine
./result/bin/mzmine
```

## Usage

`mzmine` launches the GUI. The same binary is the headless batch tool:

```sh
mzmine --help
mzmine -batch batch.xml -input "data/*.mzML" -output results/
mzmine --login          # sign in to an mzio account
```

On first launch mzmine asks you to sign in with an mzio account. That is upstream
behaviour, not a packaging artifact. Configuration and user files land in `~/.mzmine`.

## How this is packaged

Upstream ships prebuilt [jpackage](https://docs.oracle.com/en/java/javase/26/jpackage/)
app-images with their own jlink'd JDK 26 runtime embedded. This package repackages the
official `mzmine_<version>_amd64.deb` rather than building from source, because a source
build would require closed-source `io.mzio:*` jars vendored as binaries in the upstream
repo, build-time network downloads that bypass Gradle's dependency graph
(ThermoRawFileParser, SCIEX Clearcore), and proprietary vendor blobs in `external_tools/` —
and still would not reproduce the released product.

Two things are needed to make the image run on NixOS:

1. **`autoPatchelfHook`** over the ~74 shipped ELF files (the launcher,
   `libapplauncher.so`, the whole bundled JDK runtime, and the self-contained .NET
   runtimes of ThermoRawFileParser and SCIEX Wiff2 in `external_tools/`), which otherwise
   expect `/lib64/ld-linux-x86-64.so.2`. CoreCLR's optional LTTng tracing provider
   (`liblttng-ust.so.0`) is left unresolved.
2. **An `LD_LIBRARY_PATH` wrapper.** JavaFX's native libraries are not files on disk — they
   live *inside* `javafx-graphics-*.jar`, `javafx-web-*.jar` and `javafx-media-*.jar`, and
   `NativeLibLoader` extracts them at runtime into `~/.openjfx/cache/`. Those copies never
   pass through `autoPatchelfHook`, so their dependencies (gtk3, pango, cairo, gdk-pixbuf,
   libGL, fontconfig, freetype, libXtst, libXxf86vm, …) have to be resolvable at runtime.
   The .NET runtimes `dlopen` ICU, OpenSSL and zlib, which the same path provides.

## Licensing

mzmine's own sources are MIT. The distributed application image, however, is the mzio
"Pro" build (`mzminepro-*.jar`, main class `io.mzio.mzminepro.MZmineProCore`) and bundles
closed-source `io.mzio` user-management and licensing components whose terms are free for
academic use only. The package is therefore marked:

```nix
license = with lib.licenses; [ mit unfreeRedistributable ];
sourceProvenance = with lib.sourceTypes; [ binaryBytecode binaryNativeCode ];
```

Check upstream's terms yourself before using mzmine commercially.

## Development

```sh
nix develop            # nix-update + nixfmt
nix build .#mzmine -L
nix flake check -L     # includes a headless smoke test
nix fmt
```

To bump to a new upstream release:

```sh
nix run nixpkgs#nix-update -- --flake mzmine
```

CI builds every push and opens an automated PR when a new mzmine release appears.

### Optional: binary cache

CI can push to [Cachix](https://cachix.org) so users do not refetch the ~300 MB upstream
`.deb`. Create a cache named `mzmine-nix`, add its `CACHIX_AUTH_TOKEN` as a repository
secret, and add the cache to `flake.nix`:

```nix
nixConfig = {
  extra-substituters = [ "https://mzmine-nix.cachix.org" ];
  extra-trusted-public-keys = [ "mzmine-nix.cachix.org-1:<key>" ];
};
```

## Status

- Builds cleanly with zero unsatisfied `autoPatchelf` dependencies.
- `mzmine --help` runs headlessly and exits 0.
- GUI verified: JavaFX selects the hardware `ES2` (OpenGL) prism pipeline and the GTK3
  glass toolkit loads.
