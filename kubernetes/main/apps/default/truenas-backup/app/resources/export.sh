#! /bin/sh

echo "Fetching TrueNAS version..."

TRUENAS_VERSION=$(wget \
    -q \
    -O - \
    --header "Authorization: Bearer $TRUENAS_API_KEY" \
    "$TRUENAS_HOST/api/v2.0/system/version" \
    | tr -d '"'
)

if [ $? -ne 0 ]; then
    echo "Failed to get TrueNAS version"
    exit 1
fi

OUTPUT_DIR="${1:-$PWD}"
OUTPUT_FILE="$OUTPUT_DIR/$TRUENAS_VERSION-$(date +"%Y%m%d%H%M%S").tar"

echo "Exporting TrueNAS configuration to $OUTPUT_FILE..."
wget \
    -q \
    --post-data "" \
    -O "$OUTPUT_DIR/$TRUENAS_VERSION-$(date +"%Y%m%d%H%M%S").tar" \
    --header "Authorization: Bearer $TRUENAS_API_KEY" \
    "$TRUENAS_HOST/api/v2.0/config/save?secret_seed=true&root_authorized_keys=true"

if [ $? -ne 0 ]; then
    echo "Failed to export TrueNAS configuration"
    exit 1
fi

echo "Export complete..."
