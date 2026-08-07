#!/system/bin/sh

ACTIVITY="com.roblox.client.startup.ActivitySplash"

STATUS_BAR_HEIGHT=20
HEADER_HEIGHT=36
LAUNCH_DELAY=5

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_status() { printf "${CYAN}[*]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[+]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[!]${NC} %s\n" "$1"; }

clean_and_inject_window_keys() {
    xml_file="$1"
    left="$2"
    top="$3"
    right="$4"
    bottom="$5"

    # 1. Fully unlock file permissions and attributes
    chattr -i "$xml_file" >/dev/null 2>&1
    chmod 666 "$xml_file" >/dev/null 2>&1

    # 2. Remove all old app_cloner window keys to prevent stale/corrupted entries
    sed -i '/name="app_cloner_.*window_/d' "$xml_file" >/dev/null 2>&1

    # 3. Build clean XML block
    prefixes="app_cloner_current_window app_cloner_initial_window app_cloner_window app_cloner_default_window app_cloner_last_window app_cloner_saved_window app_cloner_freeform_window"
    
    xml_block=""
    for prefix in $prefixes; do
        xml_block="${xml_block}  <int name=\"${prefix}_left\" value=\"${left}\" \/>\n"
        xml_block="${xml_block}  <int name=\"${prefix}_top\" value=\"${top}\" \/>\n"
        xml_block="${xml_block}  <int name=\"${prefix}_right\" value=\"${right}\" \/>\n"
        xml_block="${xml_block}  <int name=\"${prefix}_bottom\" value=\"${bottom}\" \/>\n"
    done

    # 4. Inject fresh keys right before </map>
    sed -i "s|<\/map>|${xml_block}<\/map>|g" "$xml_file" >/dev/null 2>&1

    # 5. Lock file as read-only (444)
    chmod 444 "$xml_file" >/dev/null 2>&1
}

ARG_SELECTION="$1"
ARG_ORIENT="$2"

# 1. SCANNING PACKAGES (100% AUTOMATIC COMPONENT DETECTION FOR ALL CLONES)
log_status "Memindai aplikasi Roblox..."

# Method A: Query dumpsys package for any package containing Roblox ActivitySplash
PKGS_A=$(dumpsys package 2>/dev/null | grep -B 3 "com.roblox.client.startup.ActivitySplash" | grep -o 'Package \[[^]]*\]' | cut -d'[' -f2 | tr -d ']' | sort -u)

# Method B: Query pm list packages for roblox, clone, or sultan keywords
PKGS_B=$(pm list packages 2>/dev/null | grep -E -i "roblox|clone|sultan" | cut -d':' -f2 | sort -u)

# Combine and deduplicate packages
ALL_CLONES=$(echo "$PKGS_A $PKGS_B" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

if [ -z "$ALL_CLONES" ]; then
    log_error "Tidak ada aplikasi Roblox ditemukan!"
    exit 1
fi

set -- $ALL_CLONES
ARRAY_CLONES="$@"
TOTAL_FOUND=$#

# 2. SELECTION MENU WITH STRICT INPUT VALIDATION
printf "${YELLOW}Ditemukan %s Aplikasi:${NC}\n" "$TOTAL_FOUND"
printf "---------------------------------------------------\n"
i=1
for pkg in $ARRAY_CLONES; do
    printf "  [%2d] %s\n" "$i" "$pkg"
    i=$((i+1))
done
printf "---------------------------------------------------\n"

read_input_safe() {
    prompt_msg="$1"
    printf "%b" "$prompt_msg" >&2
    
    input_val=""
    if [ -c /dev/tty ]; then
        read input_val </dev/tty 2>/dev/null
    fi
    
    if [ -z "$input_val" ]; then
        if ! read input_val 2>/dev/null; then
            echo "EOF_DETECTED"
            return 1
        fi
    fi
    echo "$input_val"
    return 0
}

SELECTED_PACKAGES=""
while [ -z "$SELECTED_PACKAGES" ]; do
    if [ -n "$ARG_SELECTION" ]; then
        USER_INPUT="$ARG_SELECTION"
    else
        USER_INPUT=$(read_input_safe "${CYAN}Pilih nomor (contoh: 1,3,5) atau 'all': ${NC}")
        if [ "$USER_INPUT" = "EOF_DETECTED" ] || [ -z "$USER_INPUT" ]; then
            log_status "Deteksi Pipe/Non-Interactive (curl | sh). Menggunakan default: 'all'"
            USER_INPUT="all"
        fi
    fi
    
    USER_INPUT_CLEAN=$(echo "$USER_INPUT" | tr -d ' \r\t')

    if [ "$USER_INPUT_CLEAN" = "all" ] || [ "$USER_INPUT_CLEAN" = "ALL" ]; then
        SELECTED_PACKAGES=$ARRAY_CLONES
    else
        USER_CHOICE=$(echo "$USER_INPUT_CLEAN" | tr ',' ' ')
        VALID=1
        TMP_SELECTION=""
        
        for num in $USER_CHOICE; do
            num_clean=$(echo "$num" | tr -cd '0-9')
            if [ -n "$num_clean" ]; then
                if [ "$num_clean" -ge 1 ] && [ "$num_clean" -le "$TOTAL_FOUND" ]; then
                    val=$(echo "$ARRAY_CLONES" | awk -v n="$num_clean" '{print $n}')
                    [ -n "$val" ] && TMP_SELECTION="$TMP_SELECTION $val"
                else
                    VALID=0
                    break
                fi
            else
                VALID=0
                break
            fi
        done
        
        if [ "$VALID" -eq 1 ] && [ -n "$TMP_SELECTION" ]; then
            SELECTED_PACKAGES=$TMP_SELECTION
        else
            log_error "Input tidak valid!"
            ARG_SELECTION=""
        fi
    fi
done

COUNT=0
for p in $SELECTED_PACKAGES; do COUNT=$((COUNT+1)); done

# 3. MANDATORY ORIENTATION SELECTION
ORIENT_CHOICE=""
while [ -z "$ORIENT_CHOICE" ]; do
    if [ -n "$ARG_ORIENT" ]; then
        ORIENT_INPUT="$ARG_ORIENT"
    else
        ORIENT_INPUT=$(read_input_safe "${CYAN}Pilih Orientasi Layar [H] Horizontal / [V] Vertical: ${NC}")
        if [ "$ORIENT_INPUT" = "EOF_DETECTED" ] || [ -z "$ORIENT_INPUT" ]; then
            log_status "Deteksi Pipe/Non-Interactive (curl | sh). Menggunakan default: 'H'"
            ORIENT_INPUT="H"
        fi
    fi
    
    INPUT_CLEAN=$(echo "$ORIENT_INPUT" | tr -d ' \r\t' | tr '[:lower:]' '[:upper:]')

    if [ "$INPUT_CLEAN" = "H" ] || [ "$INPUT_CLEAN" = "V" ]; then
        ORIENT_CHOICE=$INPUT_CLEAN
    else
        log_error "Input tidak valid!"
        ARG_ORIENT=""
    fi
done

RAW_SIZE=$(wm size | awk '{print $3}')
DIM1=$(echo "$RAW_SIZE" | cut -d'x' -f1)
DIM2=$(echo "$RAW_SIZE" | cut -d'x' -f2)

if [ "$DIM1" -gt "$DIM2" ]; then
    MAX_DIM=$DIM1
    MIN_DIM=$DIM2
else
    MAX_DIM=$DIM2
    MIN_DIM=$DIM1
fi

if [ "$ORIENT_CHOICE" = "V" ]; then
    MODE_NAME="VERTICAL (Portrait)"
    W=$MIN_DIM
    H=$MAX_DIM

    case $COUNT in
        2) COLS=1; ROWS=2 ;;
        3) COLS=1; ROWS=3 ;;
        4) COLS=2; ROWS=2 ;;
        5|6) COLS=2; ROWS=3 ;;
        7|8) COLS=2; ROWS=4 ;;
        9|10) COLS=2; ROWS=5 ;;
        *)
            COLS=2
            ROWS=$(((COUNT + COLS - 1) / COLS))
            ;;
    esac
else
    MODE_NAME="HORIZONTAL (Landscape)"
    W=$MAX_DIM
    H=$MIN_DIM

    case $COUNT in
        2) COLS=2; ROWS=1 ;;
        3) COLS=3; ROWS=1 ;;
        4) COLS=2; ROWS=2 ;;
        5|6) COLS=3; ROWS=2 ;;
        7|8|9) COLS=3; ROWS=3 ;;
        10|11|12) COLS=4; ROWS=3 ;;
        *)
            COLS=4
            ROWS=$(((COUNT + COLS - 1) / COLS))
            ;;
    esac
fi

SW=$W; SH=$H

TOTAL_HEADERS=$((ROWS * HEADER_HEIGHT))
USABLE_GAME_H=$((SH - STATUS_BAR_HEIGHT - TOTAL_HEADERS))

GW=$((SW / COLS))
GH=$((USABLE_GAME_H / ROWS))

log_status "Mode Grid: ${MODE_NAME} ${ROWS}x${COLS} (${COUNT} Aplikasi)"

# 4. LIGHTWEIGHT EXECUTION
idx=0
for PKG in $SELECTED_PACKAGES; do
    PREF_DIR="/data/data/$PKG/shared_prefs"
    PREF="$PREF_DIR/${PKG}_preferences.xml"
    
    row=$((idx / COLS))
    col=$((idx % COLS))
    
    HEADER_OFFSET=$(((row + 1) * HEADER_HEIGHT))
    
    L=$((col * GW))
    T=$((STATUS_BAR_HEIGHT + (row * GH) + HEADER_OFFSET))
    R=$(((col == COLS - 1) ? SW : (L + GW)))
    B=$(((row == ROWS - 1) ? SH : (T + GH)))

    printf "${GREEN}[%d/%d]${NC} Setup Grid Layout -> %s\n" "$((idx+1))" "$COUNT" "$PKG"
    
    am force-stop "$PKG" >/dev/null 2>&1
    
    mkdir -p "$PREF_DIR" >/dev/null 2>&1
    if [ ! -f "$PREF" ]; then
        echo '<?xml version="1.0" encoding="utf-8" standalone="yes"?>' > "$PREF"
        echo '<map>' >> "$PREF"
        echo '</map>' >> "$PREF"
    fi

    # Clean old entries & inject exact grid window coordinates
    clean_and_inject_window_keys "$PREF" "$L" "$T" "$R" "$B"

    am start --user 0 -n "$PKG/$ACTIVITY" >/dev/null 2>&1
    log_status "Jeda 5 detik..."
    sleep "$LAUNCH_DELAY"

    idx=$((idx+1))
done

echo "---------------------------------------------------"
log_success "SELESAI! ${COUNT} aplikasi terbuka di Grid ${MODE_NAME}."
