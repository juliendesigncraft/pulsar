#!/bin/zsh
# Ricompila SwiftTerm come libreria statica in lib/ (80 s circa). Serve solo se cambia il compilatore o la versione.
set -e
cd "$(dirname "$0")"
mkdir -p lib
swiftc -parse-as-library -O -module-name SwiftTerm -emit-module -emit-module-path lib/SwiftTerm.swiftmodule \
  -emit-library -static -o lib/libSwiftTerm.a $(find Sources -name '*.swift') BuildInfo.swift
echo "✅ lib/libSwiftTerm.a"
