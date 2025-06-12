#!/bin/bash
# Lazy Framework Patcher with Fixed Android Resource Handling

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APKTOOL_JAR="${SCRIPT_DIR}/external/apktool/apktool.jar"
JARS=("framework" "services" "samsungkeystoreutils" "knoxsdk")

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
    
    # Check jars
    for jar in "${JARS[@]}"; do
        jar_path="${ROM_DIR}/system/system/framework/${jar}.jar"
        patch_dir="${SCRIPT_DIR}/patches/${jar}"
        
        if [[ -f "$jar_path" ]]; then
            echo -e "${GREEN}✓ Found ${jar}.jar in ROM${NC}"
        fi
        
        if [[ -d "$patch_dir" ]]; then
            patch_count=$(find "$patch_dir" -name '*.patch' | wc -l)
            echo -e "${GREEN}✓ Found ${patch_count} patches for ${jar}${NC}"
        fi
    done
}

# Apply patches with validation
apply_patches() {
    local work_dir="$1"
    local patch_dir="$2"
    local jar_name="$3"
    
    echo -e "${GREEN}[+] Applying patches for ${jar_name}...${NC}"
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
    
    echo -e "${GREEN}✓ Applied ${applied} patches for ${jar_name} (skipped ${skipped})${NC}"
    return 0
}

# Process a single JAR
process_jar() {
    local jar_name="$1"
    local jar_path="${ROM_DIR}/system/system/framework/${jar_name}.jar"
    local work_dir="${ROM_DIR}/system/system/framework/${jar_name}_work"
    local patch_dir="${SCRIPT_DIR}/patches/${jar_name}"
    
    # Skip if JAR doesn't exist
    if [[ ! -f "$jar_path" ]]; then
        echo -e "${YELLOW}⚠️ Skipping ${jar_name}.jar - not found in ROM${NC}"
        return 0
    fi
    
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

    # Android 14+ workaround (framework only)
    if [[ "$jar_name" == "framework" ]]; then
        echo -e "${GREEN}[+] Checking for Android 14+ resources...${NC}"
        if unzip -l "$jar_path" | grep -q "debian.mime.types"; then
            echo -e "${YELLOW}[*] Found Android 14+ resources, extracting...${NC}"
            mkdir -p "${work_dir}/unknown"
            unzip -q "$jar_path" "res/*" -d "${work_dir}/unknown" || {
                echo -e "${RED}ERROR: Failed to extract Android 14+ resources${NC}"
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

    # FIXED: Android 14+ resource reintegration
    if [[ "$jar_name" == "framework" && -d "${work_dir}/unknown" ]]; then
        echo -e "${GREEN}[+] Reintegrating Android 14+ resources...${NC}"
        
        # Create temporary working directory
        TEMP_DIR="${work_dir}/temp_reintegration"
        mkdir -p "$TEMP_DIR"
        
        # Move to temporary directory
        cd "$TEMP_DIR" || {
            echo -e "${RED}ERROR: Failed to enter temporary directory${NC}"
            return 1
        }
        
        # FIX: Look for resources in the correct location
        if [[ -d "${work_dir}/unknown/res" ]]; then
            mkdir -p "res"
            cp -r "${work_dir}/unknown/res"/* "res/" 2>/dev/null || true
        fi
        
        # Also include other files if they exist
        if [[ -d "${work_dir}/unknown" ]]; then
            find "${work_dir}/unknown" -mindepth 1 -maxdepth 1 ! -name "res" -exec cp -r {} . \;
        fi
        
        # Add resources to JAR (only if they exist)
        if [[ $(ls -A "$TEMP_DIR" 2>/dev/null) ]]; then
            zip -qr "${work_dir}/dist/${jar_name}.jar" . || {
                echo -e "${RED}ERROR: Failed to add Android 14+ resources${NC}"
                return 1
            }
        else
            echo -e "${YELLOW}⚠️ No Android 14+ resources found to reintegrate${NC}"
        fi
        
        # Clean up
        cd - >/dev/null || true
        rm -rf "$TEMP_DIR"
    fi

    # Replace original JAR
    echo -e "${GREEN}[+] Replacing original ${jar_name}.jar...${NC}"
    mkdir -p "$(dirname "$jar_path")"
    mv "${work_dir}/dist/${jar_name}.jar" "$jar_path" || {
        echo -e "${RED}ERROR: Failed to replace ${jar_name}.jar${NC}"
        return 1
    }

    # Cleanup
    rm -rf "$work_dir"
    echo -e "${GREEN}[✓] ${jar_name}.jar successfully patched!${NC}"
    return 0
}

# Main execution
main() {
    verify_paths
    
    local success=0
    local total=0
    
    for jar in "${JARS[@]}"; do
        if [[ -f "${ROM_DIR}/system/system/framework/${jar}.jar" ]]; then
            ((total++))
            process_jar "$jar" && ((success++)) || {
                echo -e "${YELLOW}⚠️ Partial success: Continuing with next JAR${NC}"
                continue
            }
        fi
    done
    
    if [[ $success -eq $total ]]; then
        echo -e "\n${GREEN}[✓] All JARs successfully patched!${NC}"
    elif [[ $success -gt 0 ]]; then
        echo -e "\n${YELLOW}[!] $success/$total JARs patched successfully${NC}"
    else
        echo -e "\n${RED}[❌] No JARs were patched!${NC}"
        exit 1
    fi
}

# Start processing
main
