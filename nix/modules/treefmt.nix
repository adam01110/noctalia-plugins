{inputs, ...}: {
  imports = [inputs.treefmt-nix.flakeModule];

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
}
