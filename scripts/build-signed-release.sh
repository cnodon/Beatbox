#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}

show_help() {
    cat <<'EOF'
Build, Developer ID sign, notarize, staple, and package Beatbox.

Required environment variables:
  DEVELOPMENT_TEAM       Apple Developer team ID
  SIGNING_IDENTITY       Exact Developer ID Application identity
  RELEASE_VERSION        CFBundleShortVersionString, for example 1.2.3
  RELEASE_BUILD_NUMBER   Positive integer CFBundleVersion
  NOTARY_KEY_PATH        Path to an App Store Connect API private key
  NOTARY_KEY_ID          App Store Connect API key ID
  NOTARY_ISSUER_ID       App Store Connect API issuer ID

Optional environment variables:
  OUTPUT_DIR             Artifact directory (default: .build/release)
  SKIP_NOTARIZATION=1    Build a signed local test artifact without notarizing

The script never reads credentials from repository files. It accepts the
notarization key by path so CI can materialize it in RUNNER_TEMP.
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    show_help
    exit 0
fi

require_environment_variable() {
    local variable_name=$1
    if [[ -z ${(P)variable_name:-} ]]; then
        print -u2 "Missing required environment variable: ${variable_name}"
        exit 64
    fi
}

require_environment_variable DEVELOPMENT_TEAM
require_environment_variable SIGNING_IDENTITY
require_environment_variable RELEASE_VERSION
require_environment_variable RELEASE_BUILD_NUMBER

if [[ ! ${RELEASE_VERSION} =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "RELEASE_VERSION must use the numeric major.minor.patch format."
    exit 64
fi

if [[ ! ${RELEASE_BUILD_NUMBER} =~ '^[1-9][0-9]*$' ]]; then
    print -u2 "RELEASE_BUILD_NUMBER must be a positive integer."
    exit 64
fi

skip_notarization=${SKIP_NOTARIZATION:-0}
if [[ ${skip_notarization} != 0 && ${skip_notarization} != 1 ]]; then
    print -u2 "SKIP_NOTARIZATION must be 0 or 1."
    exit 64
fi

if [[ ${skip_notarization} == 0 ]]; then
    require_environment_variable NOTARY_KEY_PATH
    require_environment_variable NOTARY_KEY_ID
    require_environment_variable NOTARY_ISSUER_ID

    if [[ ! -f ${NOTARY_KEY_PATH} ]]; then
        print -u2 "NOTARY_KEY_PATH does not point to a file: ${NOTARY_KEY_PATH}"
        exit 66
    fi
fi

if ! security find-identity -v -p codesigning | grep -F -q -- "${SIGNING_IDENTITY}"; then
    print -u2 "Developer ID identity is unavailable in the active keychains: ${SIGNING_IDENTITY}"
    exit 69
fi

output_dir=${OUTPUT_DIR:-${project_dir}/.build/release}
output_dir=${output_dir:A}

if [[ ${output_dir} == / || ${output_dir} == ${project_dir} ]]; then
    print -u2 "Refusing unsafe OUTPUT_DIR: ${output_dir}"
    exit 64
fi

mkdir -p "${output_dir}"

product_name="Beatbox-${RELEASE_VERSION}"
xcarchive_path="${output_dir}/Beatbox.xcarchive"
app_path="${output_dir}/Beatbox.app"
release_archive="${output_dir}/${product_name}.zip"
checksum_path="${release_archive}.sha256"
dsym_archive="${output_dir}/${product_name}.dSYM.zip"
notary_result="${output_dir}/notarization.json"
notary_log="${output_dir}/notarization-log.json"

# Each path is a fixed child of the validated artifact directory.
/bin/rm -rf -- "${xcarchive_path}" "${app_path}"
/bin/rm -f -- "${release_archive}" "${checksum_path}" "${dsym_archive}" "${notary_result}" "${notary_log}"

xcodebuild \
    -project "${project_dir}/Beatbox.xcodeproj" \
    -scheme Beatbox \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${xcarchive_path}" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    MARKETING_VERSION="${RELEASE_VERSION}" \
    CURRENT_PROJECT_VERSION="${RELEASE_BUILD_NUMBER}" \
    archive

archived_app="${xcarchive_path}/Products/Applications/Beatbox.app"
if [[ ! -d ${archived_app} ]]; then
    print -u2 "Archive did not contain Beatbox.app at the expected path."
    exit 70
fi

ditto "${archived_app}" "${app_path}"

actual_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${app_path}/Contents/Info.plist")
actual_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${app_path}/Contents/Info.plist")
if [[ ${actual_version} != ${RELEASE_VERSION} || ${actual_build} != ${RELEASE_BUILD_NUMBER} ]]; then
    print -u2 "Bundle version mismatch: expected ${RELEASE_VERSION} (${RELEASE_BUILD_NUMBER}), got ${actual_version} (${actual_build})."
    exit 70
fi

codesign --verify --deep --strict --verbose=2 "${app_path}"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${release_archive}"

if [[ ${skip_notarization} == 0 ]]; then
    xcrun notarytool submit "${release_archive}" \
        --key "${NOTARY_KEY_PATH}" \
        --key-id "${NOTARY_KEY_ID}" \
        --issuer "${NOTARY_ISSUER_ID}" \
        --wait \
        --output-format json > "${notary_result}"

    notary_status=$(/usr/bin/plutil -extract status raw "${notary_result}")
    notary_submission_id=$(/usr/bin/plutil -extract id raw "${notary_result}")
    if [[ ${notary_status} != Accepted ]]; then
        xcrun notarytool log "${notary_submission_id}" \
            --key "${NOTARY_KEY_PATH}" \
            --key-id "${NOTARY_KEY_ID}" \
            --issuer "${NOTARY_ISSUER_ID}" \
            "${notary_log}" || true
        print -u2 "Apple notarization failed with status: ${notary_status}"
        print -u2 "Submission details: ${notary_result}"
        print -u2 "Notarization log: ${notary_log}"
        exit 70
    fi

    xcrun stapler staple "${app_path}"
    xcrun stapler validate "${app_path}"
    spctl --assess --type execute --verbose=4 "${app_path}"

    # Rebuild the distributable archive after stapling the ticket.
    /bin/rm -f -- "${release_archive}"
    ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${release_archive}"
fi

archived_dsym="${xcarchive_path}/dSYMs/Beatbox.app.dSYM"
if [[ -d ${archived_dsym} ]]; then
    ditto -c -k --sequesterRsrc --keepParent "${archived_dsym}" "${dsym_archive}"
fi

(
    cd "${output_dir}"
    shasum -a 256 "${release_archive:t}" > "${checksum_path:t}"
)

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    {
        print "app_path=${app_path}"
        print "release_archive=${release_archive}"
        print "checksum_path=${checksum_path}"
        print "dsym_archive=${dsym_archive}"
    } >> "${GITHUB_OUTPUT}"
fi

print "Signed app: ${app_path}"
print "Release archive: ${release_archive}"
print "SHA-256 checksum: ${checksum_path}"
if [[ -f ${dsym_archive} ]]; then
    print "Debug symbols: ${dsym_archive}"
fi
