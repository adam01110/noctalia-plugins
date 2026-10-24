{inputs, ...}: {
  imports = [inputs.treefmt-nix.flakeModule];

  perSystem = {pkgs, ...}: {
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

      settings.formatter.albedo-luau = {
        command = "${pkgs.stylua}/bin/stylua";
        options = ["--config-path" "${../../albedo-monitor/.stylua.toml}"];
        includes = [
          # keep-sorted start
          "albedo-monitor/*.luau"
          "tests/albedo.luau"
          # keep-sorted end
        ];
      };

      settings.formatter.noctaproton-luau = {
        command = "${pkgs.stylua}/bin/stylua";
        options = ["--config-path" "${../../noctaproton-vpn/.stylua.toml}"];
        includes = ["noctaproton-vpn/*.luau" "tests/noctaproton.luau"];
      };

      projectRootFile = "flake.nix";
    };
  };
}
