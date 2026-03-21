#!/usr/bin/env bash
# fix_igraph_libomp.sh
# Patches libigraph in the pixi env to use the conda libomp.dylib by
# absolute path, bypassing the rpath conflict with Julia's LLVMOpenMP_jll.
# Re-run this any time `pixi install` recreates the conda environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIXI_LIB="${SCRIPT_DIR}/.CondaPkg/.pixi/envs/default/lib"
LIBIGRAPH="${PIXI_LIB}/libigraph.4.0.1.dylib"
LIBOMP="${PIXI_LIB}/libomp.dylib"

if [[ ! -f "$LIBIGRAPH" ]]; then
  echo "ERROR: libigraph not found at $LIBIGRAPH" >&2
  exit 1
fi
if [[ ! -f "$LIBOMP" ]]; then
  echo "ERROR: libomp.dylib not found at $LIBOMP" >&2
  exit 1
fi

echo "Patching: $LIBIGRAPH"
echo "       -> $LIBOMP"
install_name_tool -change @rpath/libomp.dylib "$LIBOMP" "$LIBIGRAPH"
echo "Re-signing with ad-hoc signature (required after install_name_tool)..."
codesign --force --sign - "$LIBIGRAPH"
echo "Done. Verify with:"
echo "  otool -L $LIBIGRAPH | grep omp"
