{
  description = "Customized Noctalia plugins";

  inputs = {
    # keep-sorted start block=yes newline_separated=yes
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # keep-sorted end
  };

  outputs = inputs @ {
    # keep-sorted start
    flake-parts,
    self,
    # keep-sorted end
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.treefmt-nix.flakeModule];
      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      flake.lib.source = self.outPath;

      perSystem = _: {
        treefmt = {
          programs = {
            # keep-sorted start
            alejandra.enable = true;
            deadnix.enable = true;
            nixf-diagnose.enable = true;
            statix.enable = true;
            # keep-sorted end

            # keep-sorted start
            yamlfmt.enable = true;
            yamllint.enable = true;
            # keep-sorted end

            # keep-sorted start
            biome.enable = true;
            keep-sorted.enable = true;
            rumdl-format.enable = true;
            stylua.enable = true;
            taplo.enable = true;
            # keep-sorted end
          };

          projectRootFile = "flake.nix";
        };
      };
    };
}
