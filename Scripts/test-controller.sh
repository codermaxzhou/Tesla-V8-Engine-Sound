#!/bin/bash
# Run the same controller tests on macOS when no iOS simulator runtime is installed.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/VirtualV8ControllerTests.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/Sources/VirtualV8" "$test_root/Tests/VirtualV8Tests"
for module in Models Engine Transmission Simulation Settings Logging Audio Sensors Input; do
    cp "$project_root/VirtualV8/$module/"*.swift "$test_root/Sources/VirtualV8/"
done
cp -R "$project_root/VirtualV8/Audio/Lexus_LFA" "$project_root/VirtualV8/Audio/Lamborghini_Murcielago" "$project_root/VirtualV8/Audio/Porsche_996_GT3" "$project_root/VirtualV8/Audio/Mazda_RX7_FD" "$project_root/VirtualV8/Audio/Ferrari_F355" "$project_root/VirtualV8/Audio/Porsche_Carrera_GT" "$project_root/VirtualV8/Audio/AMG_GTR" "$project_root/VirtualV8/Audio/Supra_2JZ" "$project_root/VirtualV8/Audio/BMW_S65" "$project_root/VirtualV8/Audio/V8_62_NA" "$test_root/Sources/VirtualV8/"
cp "$project_root/VirtualV8Tests/"*.swift "$test_root/Tests/VirtualV8Tests/"
cat > "$test_root/Package.swift" <<'PACKAGE'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "VirtualV8ControllerValidation",
    platforms: [.macOS(.v14)],
    products: [.library(name: "VirtualV8", targets: ["VirtualV8"])],
    targets: [
        .target(name: "VirtualV8", resources: [.copy("V8_62_NA"), .copy("BMW_S65"), .copy("Supra_2JZ"), .copy("AMG_GTR"), .copy("Lexus_LFA"), .copy("Lamborghini_Murcielago"), .copy("Porsche_996_GT3"), .copy("Mazda_RX7_FD"), .copy("Ferrari_F355"), .copy("Porsche_Carrera_GT")]),
        .testTarget(name: "VirtualV8Tests", dependencies: ["VirtualV8"])
    ]
)
PACKAGE
swift test --package-path "$test_root"
