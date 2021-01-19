{
  description = "inNative's LLVM fork";

  outputs = { self, nixpkgs }: let
    supportedSystems = [ "x86_64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

    llvmSystemTarget.aarch64-linux = "AArch64";
    llvmSystemTarget.i686-linux = "X86";
    llvmSystemTarget.x86_64-linux = "X86";
  in {

    overlay = pkgs: pkgsSuper: {

      lld_innative = pkgs.llvmPackages_innative.lld;
      lldb_innative = pkgs.llvmPackages_innative.lldb;
      llvm-manpages_innative = pkgs.llvmPackages_innative.llvm-manpages;
      llvm_innative = pkgs.llvmPackages_innative.llvm;

      llvm-wasm_innative = pkgs.llvm_innative.override {
        minimizeSize = true;
        enablePolly = false;
        llvmTargets = [ llvmSystemTarget.${pkgs.stdenv.targetPlatform.system} "WebAssembly" ];
      };

      # based on LLVM 10
      llvmPackages_innative = pkgs.recurseIntoAttrs (pkgs.callPackage (import ./nix self) {
        inherit (pkgs.stdenvAdapters) overrideCC;
        buildLlvmTools = pkgs.buildPackages.llvmPackages_innative.tools;
        targetLlvmLibraries = pkgs.targetPackages.llvmPackages_innative.libraries;
      });

    };

    packages = forAllSystems (system:
      let systemPackages = (import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      }); in {
        lld = systemPackages.lld_innative;
        llvm = systemPackages.llvm_innative;
        llvm-wasm = systemPackages.llvm-wasm_innative;
      }
    );

    defaultPackage = forAllSystems (system:
      self.packages.${system}.llvm-wasm
    );

  };
}
