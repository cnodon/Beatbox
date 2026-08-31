#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
package_resolved="${project_dir}/Beatbox.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

show_help() {
    cat <<'EOF'
Download and verify the official Sparkle tools matching Package.resolved.

Optional environment variables:
  SPARKLE_VERSION     Must match the resolved application dependency
  SPARKLE_TOOLS_DIR   Destination (default: .build/sparkle/<version>)

The checksum is intentionally pinned in this script. When updating Sparkle,
update Package.resolved and the official release checksum here together.
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    show_help
    exit 0
fi

if [[ ! -f ${package_resolved} ]]; then
    print -u2 "Package.resolved is missing: ${package_resolved}"
    exit 66
fi

resolved_version=$(jq -er '.pins[] | select(.identity == "sparkle") | .state.version' "${package_resolved}")
sparkle_version=${SPARKLE_VERSION:-${resolved_version}}
if [[ ${sparkle_version} != ${resolved_version} ]]; then
    print -u2 "SPARKLE_VERSION ${sparkle_version} does not match Package.resolved ${resolved_version}."
    exit 65
fi

case ${sparkle_version} in
    2.9.6)
        sparkle_sha256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
        ;;
    *)
        print -u2 "No audited checksum is configured for Sparkle ${sparkle_version}."
        print -u2 "Add the digest from Sparkle's official GitHub Release before publishing."
        exit 65
        ;;
esac

sparkle_url="https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz"
tools_dir=${SPARKLE_TOOLS_DIR:-${project_dir}/.build/sparkle/${sparkle_version}}
tools_dir=${tools_dir:A}

find_sparkle_tool() {
    local tool_name=$1
    local matches

    if [[ -x ${tools_dir}/bin/${tool_name} ]]; then
        print -r -- "${tools_dir}/bin/${tool_name}"
        return
    fi

    matches=("${tools_dir}"/**/bin/"${tool_name}"(N*))
    if (( ${#matches} != 1 )); then
        return 1
    fi
    print -r -- "${matches[1]}"
}

if [[ -d ${tools_dir} ]]; then
    generate_appcast_path=$(find_sparkle_tool generate_appcast || true)
    sign_update_path=$(find_sparkle_tool sign_update || true)
    if [[ -n ${generate_appcast_path} && -n ${sign_update_path} ]]; then
        print "Sparkle ${sparkle_version} tools already available: ${tools_dir}"
        if [[ -n ${GITHUB_OUTPUT:-} ]]; then
            {
                print "tools_dir=${tools_dir}"
                print "generate_appcast_path=${generate_appcast_path}"
                print "sign_update_path=${sign_update_path}"
            } >> "${GITHUB_OUTPUT}"
        fi
        exit 0
    fi
    print -u2 "Sparkle destination exists but is incomplete: ${tools_dir}"
    exit 73
fi

mkdir -p "${tools_dir:h}"
temporary_dir=$(mktemp -d "${tools_dir:h}/.sparkle-download.XXXXXX")
trap '/bin/rm -rf -- "${temporary_dir}"' EXIT
download_path="${temporary_dir}/Sparkle-${sparkle_version}.tar.xz"
extract_path="${temporary_dir}/distribution"

curl --fail --location --silent --show-error \
    --retry 3 \
    --proto '=https' \
    --tlsv1.2 \
    "${sparkle_url}" \
    --output "${download_path}"

actual_sha256=$(shasum -a 256 "${download_path}" | awk '{print $1}')
if [[ ${actual_sha256} != ${sparkle_sha256} ]]; then
    print -u2 "Sparkle archive checksum mismatch."
    print -u2 "Expected: ${sparkle_sha256}"
    print -u2 "Actual:   ${actual_sha256}"
    exit 65
fi

mkdir "${extract_path}"
tar -xJf "${download_path}" -C "${extract_path}"
mv "${extract_path}" "${tools_dir}"

generate_appcast_path=$(find_sparkle_tool generate_appcast || true)
sign_update_path=$(find_sparkle_tool sign_update || true)
if [[ -z ${generate_appcast_path} || -z ${sign_update_path} ]]; then
    print -u2 "The verified Sparkle distribution is missing required command-line tools."
    exit 70
fi

print "Sparkle ${sparkle_version} tools: ${tools_dir}"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    {
        print "tools_dir=${tools_dir}"
        print "generate_appcast_path=${generate_appcast_path}"
        print "sign_update_path=${sign_update_path}"
    } >> "${GITHUB_OUTPUT}"
fi
