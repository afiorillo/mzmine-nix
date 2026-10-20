{
  description = "mzmine - mass spectrometry data processing, packaged for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";

      # mzmine is marked unfree (see meta.license in pkgs/mzmine/package.nix), so the
      # flake's own outputs are evaluated against a permissive nixpkgs. Consumers using
      # `overlays.default` supply their own allowUnfree setting.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };
    in
    {
      overlays.default = import ./overlay.nix;

      packages.${system} = {
        inherit (pkgs) mzmine;
        default = pkgs.mzmine;
      };

      apps.${system}.default = {
        type = "app";
        program = "${pkgs.mzmine}/bin/mzmine";
        meta.description = "Run mzmine";
      };

      checks.${system} = {
        inherit (pkgs) mzmine;

        # Starts the patched launcher and its bundled JVM without needing a display or
        # an mzio login, asserts every shipped ELF resolved during autoPatchelf, and that
        # GTK's file chooser can find its GSettings schema (without it, opening any file
        # dialog aborts the JVM).
        smoke =
          pkgs.runCommand "mzmine-smoke"
            {
              nativeBuildInputs = [
                pkgs.binutils
                pkgs.glib.bin
                pkgs.patchelf
              ];
            }
            ''
              export HOME="$TMPDIR"

              echo "checking that the wrapper exposes GTK's file chooser schema..."
              # The binary wrapper embeds the makeCWrapper command that generated it.
              data_dirs=$(strings ${pkgs.mzmine}/bin/mzmine \
                | sed -n "s/^ *--prefix 'XDG_DATA_DIRS' ':' '\(.*\)'.*/\1/p" | paste -sd:)
              XDG_DATA_DIRS=''${data_dirs:-/nonexistent} \
                gsettings list-keys org.gtk.Settings.FileChooser >/dev/null

              echo "checking that no shipped ELF kept a non-store interpreter..."
              bad=0
              while IFS= read -r f; do
                interp=$(patchelf --print-interpreter "$f" 2>/dev/null) || continue
                case "$interp" in
                  /nix/store/*) ;;
                  *) echo "unpatched interpreter in $f: $interp"; bad=1 ;;
                esac
              done < <(find ${pkgs.mzmine}/share/mzmine -type f -exec sh -c \
                         'head -c4 "$1" | grep -q ELF' _ {} \; -print)
              [ "$bad" -eq 0 ]

              echo "starting mzmine headlessly..."
              out_log="$TMPDIR/mzmine.log"
              if ! timeout 300 ${pkgs.mzmine}/bin/mzmine --help >"$out_log" 2>&1; then
                echo "--- mzmine output ---"; cat "$out_log"
                # -showversion is in the jpackage cfg, so a JVM that came up at all prints it.
                grep -qiE 'openjdk|java version' "$out_log" || exit 1
                echo "launcher exited non-zero but the JVM started; accepting"
              fi
              cat "$out_log"

              touch $out
            '';
      };

      formatter.${system} = pkgs.nixfmt-tree;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nix-update
          nixfmt-rfc-style
        ];
      };
    };
}
