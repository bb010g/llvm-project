llvm-project:
{ lowPrio, newScope, pkgs, stdenv, cmake, gccForLibs
, libxml2, python3, isl, overrideCC, wrapCCWith, wrapBintoolsWith
, buildPackages
, buildLlvmTools # tools, but from the previous stage, for cross
, targetLlvmLibraries # libraries, but from the next stage, for cross
}:

let
  release_version = "10.0.0";
  # differentiating these (variables) is important for RCs
  # version = release_version + "-${stdenv.lib.substring 0 8 llvm-project.lastModifiedDate}.${llvm-project.shortRev or "dirty"}";
  version = release_version;
  targetConfig = stdenv.targetPlatform.config;

  fetch = name: llvm-project + "/${name}";

  clang-tools-extra_src = fetch "clang-tools-extra";

  tools = stdenv.lib.makeExtensible (tools: let
    callPackage = newScope (tools // { inherit stdenv cmake libxml2 python3 isl release_version version fetch; });
    mkExtraBuildCommands = cc: ''
      rsrc="$out/resource-root"
      mkdir "$rsrc"
      ln -s "${cc}/lib/clang/${release_version}/include" "$rsrc"
      ln -s "${targetLlvmLibraries.compiler-rt.out}/lib" "$rsrc/lib"
      echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
    '' + stdenv.lib.optionalString (stdenv.targetPlatform.isLinux && !(stdenv.targetPlatform.useLLVM or false)) ''
      echo "--gcc-toolchain=${gccForLibs}" >> $out/nix-support/cc-cflags
    '';
  in {

    llvm = callPackage ./llvm.nix { };

    clang-unwrapped = callPackage ./clang {
      inherit (tools) lld;
      inherit clang-tools-extra_src;
    };

    # disabled until recommonmark supports sphinx 3
    #Llvm-manpages = lowPrio (tools.llvm.override {
    #  enableManpages = true;
    #  python3 = pkgs.python3;  # don't use python-boot
    #});

    clang-manpages = lowPrio (tools.clang-unwrapped.override {
      enableManpages = true;
      python3 = pkgs.python3;  # don't use python-boot
    });

    # disabled until recommonmark supports sphinx 3
    # lldb-manpages = lowPrio (tools.lldb.override {
    #   enableManpages = true;
    #   python3 = pkgs.python3;  # don't use python-boot
    # });

    libclang = tools.clang-unwrapped.lib;

    clang = if stdenv.cc.isGNU then tools.libstdcxxClang else tools.libcxxClang;

    libstdcxxClang = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      # libstdcxx is taken from gcc in an ad-hoc way in cc-wrapper.
      libcxx = null;
      extraPackages = [
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = mkExtraBuildCommands cc;
    };

    libcxxClang = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = targetLlvmLibraries.libcxx;
      extraPackages = [
        targetLlvmLibraries.libcxxabi
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = mkExtraBuildCommands cc;
    };

    lld = callPackage ./lld.nix {};

    lldb = callPackage ./lldb.nix {};

    # Below, is the LLVM bootstrapping logic. It handles building a
    # fully LLVM toolchain from scratch. No GCC toolchain should be
    # pulled in. As a consequence, it is very quick to build different
    # targets provided by LLVM and we can also build for what GCC
    # doesn’t support like LLVM. Probably we should move to some other
    # file.

    bintools = callPackage ./bintools.nix {};

    lldClang = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = targetLlvmLibraries.libcxx;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
      };
      extraPackages = [
        targetLlvmLibraries.libcxxabi
        targetLlvmLibraries.compiler-rt
      ] ++ stdenv.lib.optionals (!stdenv.targetPlatform.isWasm) [
        targetLlvmLibraries.libunwind
      ];
      extraBuildCommands = ''
        echo "-rtlib=compiler-rt -Wno-unused-command-line-argument" >> $out/nix-support/cc-cflags
        echo "-B${targetLlvmLibraries.compiler-rt}/lib" >> $out/nix-support/cc-cflags
      '' + stdenv.lib.optionalString (!stdenv.targetPlatform.isWasm) ''
        echo "--unwindlib=libunwind" >> $out/nix-support/cc-cflags
      '' + stdenv.lib.optionalString stdenv.targetPlatform.isWasm ''
        echo "-fno-exceptions" >> $out/nix-support/cc-cflags
      '' + mkExtraBuildCommands cc;
    };

    lldClangNoLibcxx = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = null;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
      };
      extraPackages = [
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = ''
        echo "-rtlib=compiler-rt" >> $out/nix-support/cc-cflags
        echo "-B${targetLlvmLibraries.compiler-rt}/lib" >> $out/nix-support/cc-cflags
        echo "-nostdlib++" >> $out/nix-support/cc-cflags
      '' + mkExtraBuildCommands cc;
    };

    lldClangNoLibc = wrapCCWith rec {
      cc = tools.clang-unwrapped;
      libcxx = null;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
        libc = null;
      };
      extraPackages = [
        targetLlvmLibraries.compiler-rt
      ];
      extraBuildCommands = ''
        echo "-rtlib=compiler-rt" >> $out/nix-support/cc-cflags
        echo "-B${targetLlvmLibraries.compiler-rt}/lib" >> $out/nix-support/cc-cflags
      '' + mkExtraBuildCommands cc;
    };

    lldClangNoCompilerRt = wrapCCWith {
      cc = tools.clang-unwrapped;
      libcxx = null;
      bintools = wrapBintoolsWith {
        inherit (tools) bintools;
        libc = null;
      };
      extraPackages = [ ];
      extraBuildCommands = ''
        echo "-nostartfiles" >> $out/nix-support/cc-cflags
      '';
    };

  });

  libraries = stdenv.lib.makeExtensible (libraries: let
    callPackage = newScope (libraries // buildLlvmTools // { inherit stdenv cmake libxml2 python3 isl release_version version fetch; });
  in {

    compiler-rt = callPackage ./compiler-rt.nix ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoCompilerRt;
      }));

    stdenv = overrideCC stdenv buildLlvmTools.clang;

    libcxxStdenv = overrideCC stdenv buildLlvmTools.libcxxClang;

    libcxx = callPackage ./libc++ ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoLibcxx;
      }));

    libcxxabi = callPackage ./libc++abi.nix ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoLibcxx;
        libunwind = libraries.libunwind;
      }));

    openmp = callPackage ./openmp.nix {};

    libunwind = callPackage ./libunwind.nix ({} //
      (stdenv.lib.optionalAttrs (stdenv.hostPlatform.useLLVM or false) {
        stdenv = overrideCC stdenv buildLlvmTools.lldClangNoLibcxx;
      }));

  });

in { inherit tools libraries; } // libraries // tools
