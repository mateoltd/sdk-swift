#!/usr/bin/env bash
set -euo pipefail

source_xcframework="${1:-}"
output_zip="${2:-}"

if [[ ! -d "$source_xcframework" || -z "$output_zip" ]]; then
    echo "Usage: $0 SOURCE_XCFRAMEWORK OUTPUT_ZIP" >&2
    exit 2
fi

for command_name in find jq lipo plutil sort touch xcrun zip; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "XCFramework archive failed: missing $command_name" >&2
        exit 1
    }
done

source_xcframework="$(cd "$(dirname "$source_xcframework")" && pwd)/$(basename "$source_xcframework")"
output_directory="$(mkdir -p "$(dirname "$output_zip")" && cd "$(dirname "$output_zip")" && pwd)"
output_zip="$output_directory/$(basename "$output_zip")"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/bitwarden-xcframework.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

cp -R "$source_xcframework" "$temporary_directory/BitwardenFFI.xcframework"
xcframework="$temporary_directory/BitwardenFFI.xcframework"

device_library="$xcframework/ios-arm64/libbitwarden_uniffi.a"
candidate_simulator_directory="$xcframework/ios-arm64_x86_64-simulator"
simulator_directory="$xcframework/ios-arm64-simulator"
[[ -f "$device_library" ]] || {
    echo "XCFramework archive failed: missing arm64 device library" >&2
    exit 1
}
[[ -f "$candidate_simulator_directory/libbitwarden_uniffi.a" ]] || {
    echo "XCFramework archive failed: missing candidate simulator library" >&2
    exit 1
}

lipo "$candidate_simulator_directory/libbitwarden_uniffi.a" \
    -thin arm64 \
    -output "$temporary_directory/simulator-arm64.a"
mv "$candidate_simulator_directory" "$simulator_directory"
mv "$temporary_directory/simulator-arm64.a" \
    "$simulator_directory/libbitwarden_uniffi.a"

# The maintained distribution is arm64-only. Remove debug and local symbols while preserving
# every externally defined symbol needed by static linking.
xcrun strip -S -x "$device_library"
xcrun strip -S -x "$simulator_directory/libbitwarden_uniffi.a"
xcrun ranlib -D "$device_library"
xcrun ranlib -D "$simulator_directory/libbitwarden_uniffi.a"

plutil -convert json -o "$temporary_directory/Info.json" "$xcframework/Info.plist"
jq -S '
    .AvailableLibraries |= (
        map(
            if .SupportedPlatformVariant == "simulator" then
                .LibraryIdentifier = "ios-arm64-simulator"
                | .LibraryPath = "libbitwarden_uniffi.a"
                | .HeadersPath = "Headers"
                | .SupportedArchitectures = ["arm64"]
            else . end
        )
        | map(.SupportedArchitectures |= sort)
        | sort_by(.LibraryIdentifier)
    )
' "$temporary_directory/Info.json" >"$temporary_directory/Info.canonical.json"
plutil -convert xml1 -o "$xcframework/Info.plist" "$temporary_directory/Info.canonical.json"

find "$xcframework" -type d -exec chmod 0755 {} +
find "$xcframework" -type f -exec chmod 0644 {} +
find "$xcframework" -exec touch -h -t 198001010000 {} +

archive="$temporary_directory/BitwardenFFI.xcframework.zip"
(
    cd "$temporary_directory"
    find BitwardenFFI.xcframework \( -type f -o -type l \) -print \
        | LC_ALL=C sort \
        | COPYFILE_DISABLE=1 zip -X -q -9 -y "$archive" -@
)

mv "$archive" "$output_zip"
echo "Created deterministic XCFramework archive at $output_zip"
