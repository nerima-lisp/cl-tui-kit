{
  description = "A generic, composable Common Lisp terminal UI toolkit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sibling libraries are consumed as source trees and built by the local
    # lispDerivation graph. This keeps one ASDF source identity per dependency
    # and avoids importing a sibling's unrelated flake inputs.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      flake = false;
    };

    # These integrations keep terminal-size and UTF-8 support in optional ASDF
    # systems. Their transitive runtime dependencies are listed below as
    # source-only inputs so the packaged registry matches the ASDF graph.
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.6.1";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      flake = false;
    };
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.0.0";
      flake = false;
    };
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };
    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      flake = false;
    };
    # Structural Lisp inspection and formatting are development tools only.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.6.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-weave,
      cl-tty-kit,
      cl-concurrent-kit,
      cl-boundary-kit,
      cl-date-kit,
      cl-host-kit,
      cl-codec-kit,
      paredit-cli,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
      ];

      clCodecKit =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-codec-kit";
          lispSystem = "cl-codec-kit";
          version = ctx.cl.fromAsdSystem "${cl-codec-kit}/cl-codec-kit.asd";
          src = cl-codec-kit;
        };

      clHostKit =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-host-kit";
          lispSystem = "cl-host-kit";
          version = ctx.cl.fromAsdSystem "${cl-host-kit}/cl-host-kit.asd";
          src = cl-host-kit;
        };

      clBoundaryKit =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-boundary-kit";
          lispSystem = "cl-boundary-kit";
          version = ctx.cl.fromAsdSystem "${cl-boundary-kit}/cl-boundary-kit.asd";
          src = cl-boundary-kit;
          lispDependencies = [ (clHostKit ctx) ];
        };

      clDateKit =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-date-kit";
          lispSystem = "cl-date-kit";
          version = ctx.cl.fromAsdSystem "${cl-date-kit}/cl-date-kit.asd";
          src = cl-date-kit;
        };

      clConcurrentKit =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-concurrent-kit";
          lispSystem = "cl-concurrent-kit";
          version = ctx.cl.fromAsdSystem "${cl-concurrent-kit}/cl-concurrent-kit.asd";
          src = cl-concurrent-kit;
          lispDependencies = [
            (clBoundaryKit ctx)
            (clDateKit ctx)
          ];
        };

      clTtyKit =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-tty-kit";
          lispSystem = "cl-tty-kit";
          version = ctx.cl.fromAsdSystem "${cl-tty-kit}/cl-tty-kit.asd";
          src = cl-tty-kit;
          lispDependencies = [
            (clCodecKit ctx)
            (clConcurrentKit ctx)
          ];
        };

      clWeave =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-weave";
          lispSystem = "cl-weave";
          version = ctx.cl.fromAsdSystem "${cl-weave}/cl-weave.asd";
          src = cl-weave;
        };
    in
    cl-nix-forge.lib.${nixpkgs.lib.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-tui-kit";
      asd = ./cl-tui-kit.asd;
      root = ./.;
      docs.root = ./docs;

      meta = {
        description = "A generic, composable Common Lisp terminal UI toolkit";
        homepage = "https://github.com/nerima-lisp/cl-tui-kit";
        license = nixpkgs.lib.licenses.mit;
        # Matches `systems` above (line 75): claim only what is actually
        # built and checked, not every Unix nixpkgs happens to support.
        platforms = systems;
      };

      # The umbrella system stays pure. These entries make the optional tty
      # and codec systems loadable in the packaged closure while retaining the
      # exact nested ASDF dependency graph in each sibling derivation.
      lispDependencies = ctx: [
        (clHostKit ctx)
        (clTtyKit ctx)
        (clCodecKit ctx)
      ];

      lispCheckDependencies = ctx: [ (clWeave ctx) ];
      timeoutSeconds = 120;
      devShellPackages = ctx: [ paredit-cli.packages.${ctx.system}.default ];
      treefmt.evalModule = treefmt-nix.lib.evalModule;
    };
}
