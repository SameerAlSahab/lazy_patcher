#!/bin/bash
# Lazy Framework & APK Patcher with Android 14 Support

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APKTOOL_JAR="${SCRIPT_DIR}/external/apktool/apktool.jar"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validate arguments
if [[ $# -lt 1 ]]; then
    echo -e "${RED}ERROR: Missing ROM directory argument${NC}"
    echo "Usage: $0 <rom_directory>"
    exit 1
fi

ROM_DIR="$1"
if [[ ! -d "$ROM_DIR" ]]; then
    echo -e "${RED}ERROR: ROM directory not found: $ROM_DIR${NC}"
    exit 1
fi

# Verify required files
verify_paths() {
    echo -e "${GREEN}[+] Verifying paths...${NC}"

    # Check apktool
    if [[ ! -f "$APKTOOL_JAR" ]]; then
        echo -e "${RED}ERROR: apktool.jar not found at: $APKTOOL_JAR${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Found apktool.jar${NC}"

    # Check for JARs/APKs to patch
    mapfile -t ALL_JARS < <(find "$ROM_DIR/system/system/framework" -maxdepth 1 -type f -name "*.jar")
    mapfile -t ALL_APKS < <(find "$ROM_DIR/system/system/app" -maxdepth 1 -type f -name "*.apk")
    if [[ ${#ALL_JARS[@]} -eq 0 && ${#ALL_APKS[@]} -eq 0 ]]; then
        echo -e "${RED}ERROR: No JAR or APK files found to patch.${NC}"
        exit 1
    fi

    # Report found files and patches
    for jarpath in "${ALL_JARS[@]}"; do
        jar=$(basename "$jarpath" .jar)
        patch_dir="${SCRIPT_DIR}/patches/${jar}"
        echo -e "${GREEN}✓ Found $jar.jar in ROM${NC}"
        if [[ -d "$patch_dir" ]]; then
            patch_count=$(find "$patch_dir" -name '*.patch' | wc -l)
            echo -e "${GREEN}✓ Found ${patch_count} patches for ${jar}${NC}"
        else
            echo -e "${YELLOW}⚠️ No patches found for ${jar}${NC}"
        fi
    done
    for apkpath in "${ALL_APKS[@]}"; do
        apk=$(basename "$apkpath" .apk)
        patch_dir="${SCRIPT_DIR}/patches/${apk}"
        echo -e "${GREEN}✓ Found $apk.apk in ROM${NC}"
        if [[ -d "$patch_dir" ]]; then
            patch_count=$(find "$patch_dir" -name '*.patch' | wc -l)
            echo -e "${GREEN}✓ Found ${patch_count} patches for ${apk}${NC}"
        else
            echo -e "${YELLOW}⚠️ No patches found for ${apk}${NC}"
        fi
    done
}

apply_patches() {
    local work_dir="$1"
    local patch_dir="$2"
    local file_name="$3"

    echo -e "${GREEN}[+] Applying patches for ${file_name}...${NC}"
    local applied=0
    local skipped=0

    for patch in "${patch_dir}"/*.patch; do
        [[ -f "$patch" ]] || continue
        patch_name=$(basename "$patch")
        # Dry-run first
        if patch --dry-run -d "$work_dir" -p1 < "$patch" >/dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Applying ${patch_name}...${NC}"
            if ! patch -d "$work_dir" -p1 < "$patch"; then
                echo -e "${RED}  ❌ ERROR: Failed to apply ${patch_name} after dry-run passed!${NC}"
                return 1
            fi
            ((applied++))
        else
            echo -e "${YELLOW}  ⚠️ Skipping ${patch_name} (dry-run failed)${NC}"
            ((skipped++))
        fi
    done

    echo -e "${GREEN}✓ Applied ${applied} patches for ${file_name} (skipped ${skipped})${NC}"
    return 0
}

process_jar() {
    local jar_path="$1"
    local jar_name=$(basename "$jar_path" .jar)
    local work_dir="${ROM_DIR}/system/system/framework/${jar_name}_work"
    local patch_dir="${SCRIPT_DIR}/patches/${jar_name}"

    echo -e "\n${GREEN}===== Processing ${jar_name}.jar =====${NC}"

    # Clean working directory
    echo -e "${YELLOW}[*] Cleaning workspace...${NC}"
    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    # Decompile JAR
    echo -e "${GREEN}[+] Decompiling ${jar_name}.jar...${NC}"
    java -jar "$APKTOOL_JAR" d \
        -f \
        -b \
        -o "$work_dir" \
        "$jar_path" || {
            echo -e "${RED}ERROR: Decompilation failed for ${jar_name}.jar${NC}"
            return 1
        }

    # Android 14 workaround (framework only)
    if [[ "$jar_name" == "framework" ]]; then
        echo -e "${GREEN}[+] Checking for Android 14 resources...${NC}"
        if unzip -l "$jar_path" | grep -q "debian.mime.types"; then
            echo -e "${YELLOW}[*] Found Android 14 resources, extracting...${NC}"
            mkdir -p "${work_dir}/unknown"
            unzip -q "$jar_path" "res/*" -d "${work_dir}/unknown" || {
                echo -e "${RED}ERROR: Failed to extract Android 14 resources${NC}"
                return 1
            }
        fi
    fi

    # Apply patches if directory exists
    if [[ -d "$patch_dir" ]]; then
        apply_patches "$work_dir" "$patch_dir" "$jar_name" || return 1
    else
        echo -e "${YELLOW}⚠️ No patches found for ${jar_name}${NC}"
    fi

    # Rebuild JAR
    echo -e "${GREEN}[+] Rebuilding ${jar_name}.jar...${NC}"
    java -jar "$APKTOOL_JAR" b \
        -c \
        -p res \
        --use-aapt2 \
        "$work_dir" \
        -o "${work_dir}/dist/${jar_name}.jar" || {
            echo -e "${RED}ERROR: Rebuild failed for ${jar_name}.jar${NC}"
            return 1
        }

    # Reintegrate Android 14 resources (framework only)
    if [[ "$jar_name" == "framework" && -d "${work_dir}/unknown" ]]; then
        echo -e "${GREEN}[+] Reintegrating Android 14 resources...${NC}"
        (
            cd "${work_dir}/unknown"
            zip -qr "${work_dir}/dist/${jar_name}.jar" . || {
                echo -e "${RED}ERROR: Failed to add Android 14 resources${NC}"
                return 1
            }
        )
    fi

    # Replace original JAR
    echo -e "${GREEN}[+] Replacing original ${jar_name}.jar...${NC}"
    mv "${work_dir}/dist/${jar_name}.jar" "$jar_path" || {
        echo -e "${RED}ERROR: Failed to replace ${jar_name}.jar${NC}"
        return 1
    }

    # Cleanup
    rm -rf "$work_dir"
    echo -e "${GREEN}[✓] ${jar_name}.jar successfully patched!${NC}"
    return 0
}

process_apk() {
    local apk_path="$1"
    local apk_name=$(basename "$apk_path" .apk)
    local work_dir="${ROM_DIR}/system/system/app/${apk_name}_work"
    local patch_dir="${SCRIPT_DIR}/patches/${apk_name}"

    echo -e "\n${GREEN}===== Processing ${apk_name}.apk =====${NC}"

    # Clean working directory
    echo -e "${YELLOW}[*] Cleaning workspace...${NC}"
    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    # Decompile APK
    echo -e "${GREEN}[+] Decompiling ${apk_name}.apk...${NC}"
    java -jar "$APKTOOL_JAR" d \
        -f \
        -b \
        -o "$work_dir" \
        "$apk_path" || {
            echo -e "${RED}ERROR: Decompilation failed for ${apk_name}.apk${NC}"
            return 1
        }

    # Apply patches if directory exists
    if [[ -d "$patch_dir" ]]; then
        apply_patches "$work_dir" "$patch_dir" "$apk_name" || return 1
    else
        echo -e "${YELLOW}⚠️ No patches found for ${apk_name}${NC}"
    fi

    # Rebuild APK
    echo -e "${GREEN}[+] Rebuilding ${apk_name}.apk...${NC}"
    java -jar "$APKTOOL_JAR" b \
        -c \
        -p res \
        --use-aapt2 \
        "$work_dir" \
        -o "${work_dir}/dist/${apk_name}.apk" || {
            echo -e "${RED}ERROR: Rebuild failed for ${apk_name}.apk${NC}"
            return 1
        }

    # Replace original APK
    echo -e "${GREEN}[+] Replacing original ${apk_name}.apk...${NC}"
    mv "${work_dir}/dist/${apk_name}.apk" "$apk_path" || {
        echo -e "${RED}ERROR: Failed to replace ${apk_name}.apk${NC}"
        return 1
    }

    # Cleanup
    rm -rf "$work_dir"
    echo -e "${GREEN}[✓] ${apk_name}.apk successfully patched!${NC}"
    return 0
}

main() {
    verify_paths

    local total=0
    local success=0

    # Patch all JARs
    mapfile -t ALL_JARS < <(find "$ROM_DIR/system/system/framework" -maxdepth 1 -type f -name "*.jar")
    for jar_path in "${ALL_JARS[@]}"; do
        ((total++))
        process_jar "$jar_path" && ((success++))
    done

    # Patch all APKs
    mapfile -t ALL_APKS < <(find "$ROM_DIR/system/system/app" -maxdepth 1 -type f -name "*.apk")
    for apk_path in "${ALL_APKS[@]}"; do
        ((total++))
        process_apk "$apk_path" && ((success++))
    done

  260|     if [[ $total -eq 0 ]]; then
261|         echo -e "\n${YELLOW}[!] No patchable files were found!${NC}"
262|         exit 0
263|     elif [[ $success -eq $total ]]; then
264|         echo -e "\n${GREEN}[✓] All files successfully patched!${NC}"
265|         exit 0
266|     elif [[ $success -gt 0 ]]; then
267|         echo -e "\n${YELLOW}[!] $success/$total files patched successfully (some failed)${NC}"
268|         exit 1
269|     else
270|         echo -e "\n${RED}[❌] No files were patched!${NC}"
271|         exit 1
272|     fi }

main "$@"
