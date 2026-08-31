#!/bin/zsh

set -euo pipefail

show_help() {
    cat <<'EOF'
Generate and verify a Sparkle appcast for one Beatbox update archive.

Required environment variables:
  SPARKLE_TOOLS_DIR          Verified Sparkle distribution directory
  SPARKLE_EDDSA_PRIVATE_KEY  Private key exported by Sparkle generate_keys -x
  RELEASE_ARCHIVE            Notarized and stapled Beatbox zip archive
  DOWNLOAD_URL_PREFIX        Public release asset directory URL, ending in /
  RELEASE_PAGE_URL           Human-readable release page URL
  APPCAST_OUTPUT             Destination appcast.xml path

Optional environment variables:
  GENERATE_APPCAST_PATH      Explicit generate_appcast executable
  SIGN_UPDATE_PATH           Explicit sign_update executable

The private key is streamed to Sparkle over standard input and is never written
to disk by this script.
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

for variable_name in \
    SPARKLE_TOOLS_DIR \
    SPARKLE_EDDSA_PRIVATE_KEY \
    RELEASE_ARCHIVE \
    DOWNLOAD_URL_PREFIX \
    RELEASE_PAGE_URL \
    APPCAST_OUTPUT; do
    require_environment_variable "${variable_name}"
done

find_unique_tool() {
    local tool_name=$1
    local explicit_path=$2
    local matches

    if [[ -n ${explicit_path} ]]; then
        print -r -- "${explicit_path}"
        return
    fi

    if [[ -x ${SPARKLE_TOOLS_DIR}/bin/${tool_name} ]]; then
        print -r -- "${SPARKLE_TOOLS_DIR}/bin/${tool_name}"
        return
    fi

    matches=("${SPARKLE_TOOLS_DIR}"/**/bin/"${tool_name}"(N*))
    if (( ${#matches} != 1 )); then
        print -u2 "Expected exactly one ${tool_name} under ${SPARKLE_TOOLS_DIR}; found ${#matches}."
        return 1
    fi
    print -r -- "${matches[1]}"
}

generate_appcast=$(find_unique_tool generate_appcast "${GENERATE_APPCAST_PATH:-}")
sign_update=$(find_unique_tool sign_update "${SIGN_UPDATE_PATH:-}")

if [[ ! -x ${generate_appcast} || ! -x ${sign_update} ]]; then
    print -u2 "Sparkle tools are missing or not executable."
    exit 69
fi

if [[ ! -f ${RELEASE_ARCHIVE} ]]; then
    print -u2 "Release archive does not exist: ${RELEASE_ARCHIVE}"
    exit 66
fi

if [[ ${DOWNLOAD_URL_PREFIX} != https://* || ${DOWNLOAD_URL_PREFIX} != */ ]]; then
    print -u2 "DOWNLOAD_URL_PREFIX must be an HTTPS URL ending in /."
    exit 64
fi

if [[ ${RELEASE_PAGE_URL} != https://* ]]; then
    print -u2 "RELEASE_PAGE_URL must use HTTPS."
    exit 64
fi

appcast_output=${APPCAST_OUTPUT:A}
mkdir -p "${appcast_output:h}"
temporary_dir=$(mktemp -d "${appcast_output:h}/.appcast.XXXXXX")
trap '/bin/rm -rf -- "${temporary_dir}"' EXIT
updates_dir="${temporary_dir}/updates"
generated_appcast="${temporary_dir}/appcast.xml"
mkdir "${updates_dir}"
ditto "${RELEASE_ARCHIVE}" "${updates_dir}/${RELEASE_ARCHIVE:t}"

printf '%s\n' "${SPARKLE_EDDSA_PRIVATE_KEY}" | \
    "${generate_appcast}" \
        --ed-key-file - \
        --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
        --link "${RELEASE_PAGE_URL}" \
        --maximum-deltas 0 \
        -o "${generated_appcast}" \
        "${updates_dir}"

xmllint --noout "${generated_appcast}"

expected_signature=$(printf '%s\n' "${SPARKLE_EDDSA_PRIVATE_KEY}" | \
    "${sign_update}" --ed-key-file - -p "${RELEASE_ARCHIVE}")
if ! grep -F -q -- "${expected_signature}" "${generated_appcast}"; then
    print -u2 "The generated appcast did not contain the expected Sparkle EdDSA signature."
    exit 65
fi
unset expected_signature

ditto "${generated_appcast}" "${appcast_output}"
print "Sparkle appcast: ${appcast_output}"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    print "appcast_path=${appcast_output}" >> "${GITHUB_OUTPUT}"
fi
