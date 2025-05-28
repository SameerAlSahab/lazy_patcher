#!/bin/bash
# lazy_patcher.sh - Enhanced Version with Directory Handling Fix

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path Configuration (relative to project root)
PROJECT_ROOT="$SCRIPT_DIR"  
APKTOOL_JAR="$PROJECT_ROOT/external/apktool/apktool.jar"
ROM_FOLDER="$1"  

# Validate ROM directory
if [[ -z "$ROM_FOLDER" || ! -d "$ROM_FOLDER" ]]; then
    echo -e "\033[0;31mERROR: ROM directory not specified or invalid!\033[0m"
    echo "Usage: $0 <rom_directory>"
    exit 1
fi

# Define JARs to process
JARS=(
    "framework"
    "services"
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Verify all paths exist
verify_paths() {
    echo -e "${GREEN}[+] Verifying paths...${NC}"
    
    # Check apktool
    if [ ! -f "$APKTOOL_JAR" ]; then
        echo -e "${RED}ERROR: apktool.jar not found at:${NC}"
        echo -e "  ${YELLOW}$APKTOOL_JAR${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Found apktool.jar${NC}"

    # Check ROM jars
    for jar in "${JARS[@]}"; do
        jar_path="$ROM_FOLDER/system/system/framework/$jar.jar"
        patches_dir="$PROJECT_ROOT/patches/$jar.jar"
        
        if [ ! -f "$jar_path" ]; then
            echo -e "${YELLOW}WARNING: $jar.jar not found in ROM directory!${NC}"
            echo -e "  ${YELLOW}Expected: $jar_path${NC}"
            continue
        fi
        
        if [ ! -d "$patches_dir" ]; then
            echo -e "${YELLOW}WARNING: Patches directory not found:${NC}"
            echo -e "  ${YELLOW}$patches_dir${NC}"
            continue
        fi
        
        echo -e "${GREEN}✓ Found $jar.jar and $(ls "$patches_dir"/*.patch 2>/dev/null | wc -w) patches${NC}"
    done
}

# Patch application with dry-run validation
apply_patches() {
    local work_dir="$1"
    local patches_dir="$2"
    local jar_name="$3"
    
    echo -e "${GREEN}[+] Applying patches for $jar_name...${NC}"
    local applied=0
    local skipped=0
    
    for patch in "$patches_dir"/*.patch; do
        [[ -f "$patch" ]] || continue  # Skip if no patches
        
        patch_name=$(basename "$patch")
        
        # First try dry-run
        if patch --dry-run -d "$work_dir" -p1 < "$patch" >/dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Applying $patch_name...${NC}"
            if ! patch -d "$work_dir" -p1 < "$patch"; then
                echo -e "${RED}  ❌ ERROR: Failed to apply $patch_name after dry-run passed!${NC}"
                return 1
            fi
            ((applied++))
        else
            echo -e "${YELLOW}  ⚠️ Skipping $patch_name (dry-run failed)${NC}"
            ((skipped++))
        fi
    done
    
    if [[ $applied -eq 0 && $skipped -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ No patches applied for $jar_name (all skipped)${NC}"
    else
        echo -e "${GREEN}✓ Applied $applied/$((applied+skipped)) patches for $jar_name${NC}"
    fi
    return 0
}

# Process a JAR file
process_jar() {
    local jar_name="$1"
    local rom_jar="$ROM_FOLDER/system/system/framework/$jar_name.jar"
    local work_dir="$ROM_FOLDER/system/system/framework/${jar_name}edit"
    local patches_dir="$PROJECT_ROOT/resources/patches/$jar_name.jar"
    
    # Skip if JAR doesn't exist
    if [ ! -f "$rom_jar" ]; then
        echo -e "${YELLOW}⚠️ Skipping $jar_name.jar - not found in ROM${NC}"
        return 0
    fi
    
    # Skip if no patches directory
    if [ ! -d "$patches_dir" ]; then
        echo -e "${YELLOW}⚠️ Skipping $jar_name.jar - no patches directory${NC}"
        return 0
    fi
    
    echo -e "\n${GREEN}===== Processing $jar_name.jar =====${NC}"
    
    # Clean working directory
    echo -e "${YELLOW}[*] Cleaning working directory...${NC}"
    rm -rf "$work_dir"
    
    # Decompile JAR
    echo -e "${GREEN}[+] Decompiling $jar_name.jar...${NC}"
    java -jar "$APKTOOL_JAR" d \
        -api 34 \
        -f \  # Force overwrite existing directory
        -b \
        -o "$work_dir" \
        "$rom_jar" || {
            echo -e "${RED}ERROR: Decompilation failed for $jar_name.jar${NC}"
            return 1
        }

    # Android 14 workaround (only for framework.jar)
    if [[ "$jar_name" == "framework" ]]; then
        echo -e "${GREEN}[+] Checking for Android 14 resources...${NC}"
        if unzip -l "$rom_jar" | grep -q "debian.mime.types"; then
            echo -e "${YELLOW}[*] Found Android 14 resources, extracting...${NC}"
            mkdir -p "$work_dir/unknown"
            unzip -q "$rom_jar" "res/*" -d "$work_dir/unknown" || {
                echo -e "${RED}ERROR: Failed to extract Android 14 resources${NC}"
                return 1
            }
        fi
    fi

    # Apply patches
    apply_patches "$work_dir" "$patches_dir" "$jar_name" || return 1

    # Rebuild JAR
    echo -e "${GREEN}[+] Rebuilding $jar_name.jar...${NC}"
    java -jar "$APKTOOL_JAR" b \
        -c \
        -p res \
        --use-aapt2 \
        "$work_dir" \
        -o "$work_dir/dist/$jar_name.jar" || {
            echo -e "${RED}ERROR: Rebuild failed for $jar_name.jar${NC}"
            return 1
        }

    # Reintegrate Android 14 resources (framework.jar only)
    if [[ "$jar_name" == "framework" && -d "$work_dir/unknown" ]]; then
        echo -e "${GREEN}[+] Reintegrating Android 14 resources...${NC}"
        (
            cd "$work_dir/unknown"
            zip -qr "$work_dir/dist/$jar_name.jar" . || {
                echo -e "${RED}ERROR: Failed to add Android 14 resources${NC}"
                return 1
            }
        )
    fi

    # Replace original JAR
    echo -e "${GREEN}[+] Replacing original $jar_name.jar...${NC}"
    mv "$work_dir/dist/$jar_name.jar" "$rom_jar" || {
        echo -e "${RED}ERROR: Failed to replace $jar_name.jar${NC}"
        return 1
    }

    # Cleanup
    rm -rf "$work_dir"
    echo -e "${GREEN}[✓] $jar_name.jar successfully patched!${NC}"
    return 0
}

# Main process
main() {
    verify_paths
    
    local success=0
    local total=${#JARS[@]}
    
    for jar in "${JARS[@]}"; do
        process_jar "$jar" && ((success++)) || true
    done

    if [[ $success -gt 0 ]]; then
        echo -e "\n${GREEN}[✓] $success/$total JARs successfully patched!${NC}"
    else
        echo -e "\n${RED}❌ No JARs were patched!${NC}"
        exit 1
    fi
}

# Execute
main
