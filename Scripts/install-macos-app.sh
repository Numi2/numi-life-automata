#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
destination="${NUMI_INSTALL_DIR:-$HOME/Applications}"
open_after_install=true

while (( $# > 0 )); do
    case "$1" in
        --no-open)
            open_after_install=false
            ;;
        --install-dir)
            if (( $# < 2 )); then
                print -u2 "error: --install-dir requires a directory"
                exit 2
            fi
            destination="$2"
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: ./Scripts/install-macos-app.sh [--no-open] [--install-dir DIRECTORY]

Builds, signs, and installs Numi Automata as a normal macOS application.
The default destination is ~/Applications.
EOF
            exit 0
            ;;
        *)
            print -u2 "error: unknown option: $1"
            exit 2
            ;;
    esac
    shift
done

app_name="Numi Automata.app"
executable_name="NumiAutomata"
resource_bundle_name="NumiAutomata_NumiAutomata.bundle"
bundle_identifier="${NUMI_BUNDLE_IDENTIFIER:-com.numi.automata}"
marketing_version="${NUMI_MARKETING_VERSION:-1.0}"
build_number="${NUMI_BUILD_NUMBER:-2}"
deployment_target="${NUMI_DEPLOYMENT_TARGET:-26.0}"
installed_app="$destination/$app_name"
temporary_root="$(mktemp -d -t numi-automata-install)"
staged_app="$temporary_root/$app_name"
iconset="$temporary_root/NumiAutomata.iconset"
square_icon="$temporary_root/NumiAutomata-square.png"

trap 'rm -rf "$temporary_root"' EXIT

print "Building Numi Automata (release)..."
cd "$root"
./Scripts/build-metal4-assets.sh
if [[ ! -s Sources/AutogenesisMetal/Shaders/Replicator.metallib ]]; then
    print -u2 "error: ahead-of-time Metal 4 shader library was not produced"
    exit 1
fi
if [[ ! -s Sources/AutogenesisMetal/Shaders/Replicator.mtl4archive ]]; then
    print -u2 "error: ahead-of-time Metal 4 pipeline archive was not produced"
    exit 1
fi
swift build -c release --product "$executable_name" --jobs 4
binary_directory="$(swift build -c release --show-bin-path)"

if [[ ! -x "$binary_directory/$executable_name" ]]; then
    print -u2 "error: release executable was not produced"
    exit 1
fi

if [[ ! -d "$binary_directory/$resource_bundle_name" ]]; then
    print -u2 "error: SwiftPM resource bundle was not produced"
    exit 1
fi

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$iconset"
cp "$root/Packaging/Info.plist" "$staged_app/Contents/Info.plist"
cp "$root/Packaging/PrivacyInfo.xcprivacy" \
    "$staged_app/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$binary_directory/$executable_name" "$staged_app/Contents/MacOS/$executable_name"
ditto "$binary_directory/$resource_bundle_name" \
    "$staged_app/Contents/Resources/$resource_bundle_name"

# SwiftPM does not expand the Xcode build-setting placeholders in the shared
# release plist. Resolve them before LaunchServices registers the local app.
plutil -replace CFBundleExecutable -string "$executable_name" \
    "$staged_app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_identifier" \
    "$staged_app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$marketing_version" \
    "$staged_app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" \
    "$staged_app/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "$deployment_target" \
    "$staged_app/Contents/Info.plist"
plutil -remove CFBundleIconName "$staged_app/Contents/Info.plist" 2>/dev/null || true
plutil -insert CFBundleIconFile -string "NumiAutomata.icns" \
    "$staged_app/Contents/Info.plist"

icon_source="$root/Packaging/AppIcon-master.png"
icon_width="$(sips -g pixelWidth "$icon_source" | awk '/pixelWidth/ { print $2 }')"
icon_height="$(sips -g pixelHeight "$icon_source" | awk '/pixelHeight/ { print $2 }')"
if (( icon_width < icon_height )); then
    icon_side="$icon_width"
else
    icon_side="$icon_height"
fi

sips --cropToHeightWidth "$icon_side" "$icon_side" "$icon_source" \
    --out "$square_icon" >/dev/null
sips -z 16 16 "$square_icon" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$square_icon" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$square_icon" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$square_icon" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$square_icon" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$square_icon" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$square_icon" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$square_icon" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$square_icon" --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$square_icon" --out "$iconset/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset" -o "$staged_app/Contents/Resources/NumiAutomata.icns"

plutil -lint "$staged_app/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$staged_app" >/dev/null
codesign --verify --deep --strict "$staged_app"

if pgrep -x "$executable_name" >/dev/null; then
    print "Closing the running Numi Automata instance..."
    pkill -TERM -x "$executable_name" || true
    for _ in {1..50}; do
        pgrep -x "$executable_name" >/dev/null || break
        sleep 0.1
    done
    if pgrep -x "$executable_name" >/dev/null; then
        print -u2 "error: Numi Automata is still running; close it and rerun the installer"
        exit 1
    fi
fi

mkdir -p "$destination"
rm -rf "$installed_app"
ditto "$staged_app" "$installed_app"

launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$launch_services" ]]; then
    "$launch_services" -f "$installed_app"
fi

print "Installed: $installed_app"
if $open_after_install; then
    open "$installed_app"
    print "Opened Numi Automata. Close the window or press Command-Q to quit."
fi
