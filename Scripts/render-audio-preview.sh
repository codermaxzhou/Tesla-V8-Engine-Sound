#!/bin/bash
# Render the existing demo through the real AVAudioEngine graph without hardware.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_root="$(mktemp -d /tmp/VirtualV8AudioPreview.XXXXXX)"
trap 'rm -rf "$preview_root"' EXIT
asset_path="${1:-$project_root/VirtualV8/Audio/V8_62_NA}"
output_path="${2:-$project_root/AudioPreview/v8-demo.wav}"
mkdir -p "$preview_root/Sources/Preview" "$(dirname "$output_path")"
for module in Models Engine Transmission Simulation Settings Logging Audio Sensors Input; do
    cp "$project_root/VirtualV8/$module/"*.swift "$preview_root/Sources/Preview/"
done
cp -R "$project_root/VirtualV8/Audio/Lexus_LFA" "$project_root/VirtualV8/Audio/Lamborghini_Murcielago" "$project_root/VirtualV8/Audio/Porsche_996_GT3" "$project_root/VirtualV8/Audio/Mazda_RX7_FD" "$project_root/VirtualV8/Audio/Ferrari_F355" "$project_root/VirtualV8/Audio/Porsche_Carrera_GT" "$project_root/VirtualV8/Audio/AMG_GTR" "$project_root/VirtualV8/Audio/Supra_2JZ" "$project_root/VirtualV8/Audio/BMW_S65" "$project_root/VirtualV8/Audio/V8_62_NA" "$preview_root/Sources/Preview/"
cp "$project_root/Scripts/RenderAudioPreview.swift" "$preview_root/Sources/Preview/"
cat > "$preview_root/Package.swift" <<'PACKAGE'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "VirtualV8AudioPreview", platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Preview", resources: [.copy("V8_62_NA"), .copy("BMW_S65"), .copy("Supra_2JZ"), .copy("AMG_GTR"), .copy("Lexus_LFA"), .copy("Lamborghini_Murcielago"), .copy("Porsche_996_GT3"), .copy("Mazda_RX7_FD"), .copy("Ferrari_F355"), .copy("Porsche_Carrera_GT")])])
PACKAGE
swift run --package-path "$preview_root" Preview "$asset_path" "$output_path" "${3:-0.5}" "${4:-american-62}"
