#!/bin/bash
# This script updates JDK path references in WebLogic DOMAIN_HOME configuration 
# files, and can also report or update the JAVA_HOME property used by Oracle 
# Universal Installer (OUI).
#
# Designed for Oracle WebLogic Server and Oracle Fusion Middleware environments 
# where coordinated JDK path updates are needed.
#
# Version 2.2.8

# Procedure Outline: How this script involved in WebLogic Server JDK Replacement
#
# 1. Adjust the definitions of NEW_JDK_STRING and OLD_JDK_STRING in "User Specific Definition" section of this script to match your actual JAVA_HOME locations.
#
# 2. (Optional) List configuration files containing OLD_JDK_STRING under ORACLE_HOME (OUI: Oracle Universal Installer) and DOMAIN_HOME, using '-l' option:
#    - For OUI:    ./change-wls-java_home.sh -o -l [-v]
#    - For DOMAIN: ./change-wls-java_home.sh -d -l [-v]
#
# 3. Disable SAFE_MODE by setting SAFE_MODE=0 in "User Specific Definition" section (default: SAFE_MODE=1 for safeguard).
#
# 4. Backup the current OUI JAVA_HOME property before making any changes:
#    - ./change-wls-java_home.sh -o -b
#
# 5. Install or update the new JDK binary/package.
#    - Ensure the new JDK is correctly installed and accessible at NEW_JDK_STRING.
#    - (Optional) Update system $JAVA_HOME environment variable (e.g., edit /etc/profile). You may need to log out and back in for this change to take effect.
#
# 6. Update the OUI JAVA_HOME property to the new JDK path:
#    - ./change-wls-java_home.sh -o -u
#
# 7. Update DOMAIN_HOME configuration files to reference the new JDK path:
#    - ./change-wls-java_home.sh -d
#
# 8. (Optional) Verify the old JDK path strings are gone by listing files or properties again using the '-l' option. You can also confirm files referencing the new JDK path by using '-t <NEW_JDK_STRING>'.
#
# See the help contents for further details and usage options.

### --- User Specific Definition Section - Begin ---
# JAVA_HOME strings
NEW_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_451-oracle-x64
OLD_JDK_STRING=/usr/lib/jvm/jdk-1.8.0_411-oracle-x64

# SAFE_MODE: Prevent any accidental modification during testing or dry runs ---
# !!! WARNING !!!
# SAFE_MODE is enabled by default to prevent accidental modification of the Middleware environment.
# Set SAFE_MODE=0 **only after** you have reviewed and tested this script in your environment.
SAFE_MODE=1
### --- User Specific Definition Section - End ---

MYBASENAME=$(basename "$0")
LIST_ONLY=0
VERBOSE_LIST=0
AUTO_YES_ALL=0
DO_DOMAIN=0
DO_OUI=0
OUI_BACKUP=0
OUI_UPDATE=0
TEST_JDK_STRING=""

show_help() {
   cat <<EOM
Usage: $MYBASENAME [OPTION]
  -d: Domain mode. Update JAVA_HOME references in DOMAIN_HOME.
  -o: OUI mode. Must be coupled with one of -b or -u.
      -b: Backup current JAVA_HOME property to OLD_JAVA_HOME (OUI only).
      -u: Update JAVA_HOME property to new value (OUI only).
      -b and -u are mutually exclusive.
  -l: List-only mode. List matching files and exit without modification.
  -v: Verbose list-only mode. Print matching lines with filenames. Use together
      with -l or -t ; -v alone has no effect.
  -t <JDK_STRING>: Temporarily sets OLD_JDK_STRING to <JDK_STRING> for testing.
      No files are modified, as this option always implies -l (list-only) option.
      Use to check for files or configuration referencing a specific JDK path.
      Useful when e.g.: Find files containing NEW_JDK_STRING before or after migration.
                        Multiple JDK versions/releases are installed.
  -h: Show this help.

Note: Either -d or -o is required. They are mutually exclusive.
      In OUI mode (-o), you must choose either -b or -u (not both).
      Example: $MYBASENAME -o -b      # Backup old JAVA_HOME property (OUI)
               $MYBASENAME -o -u      # Update only (OUI)
               $MYBASENAME -d         # Domain operation

Note: Environment variables DOMAIN_HOME and/or ORACLE_HOME must be defined,
depending on the processing options.

Note: The ORACLE_HOME listing and property update features depend on Oracle's
official scripts (setProperty.sh/getProperty.sh). Backup of OLD_JAVA_HOME must
be performed while the old JDK is still present and valid in the filesystem.

Note: If you use the ORACLE_HOME listing feature (-o + -l) shortly after updating
JAVA_HOME (-o + -u), some files may still show the old JAVA_HOME path. This is normal
and not a cause for concern. These files are typically updated later by WebLogic
Server processes or related operations.

*** WARNING: SAFE_MODE is enabled by default ***
    This prevents any modification of the Middleware environment.
    To allow actual changes, set SAFE_MODE=0 at the top of this script
    only after review and testing.
EOM
}

# Option parsing
while getopts "dovbult:h" opt; do
  case $opt in
    d) DO_DOMAIN=1 ;;
    o) DO_OUI=1 ;;
    b) OUI_BACKUP=1 ;;
    u) OUI_UPDATE=1 ;;
    l) LIST_ONLY=1 ;;
    v) VERBOSE_LIST=1 ;;
    t) TEST_JDK_STRING="$OPTARG"; LIST_ONLY=1 ;;
    h|*) show_help; exit 0 ;;
  esac
done

# --- SAFE_MODE ENFORCEMENT ---
if [ "$SAFE_MODE" = "1" ]; then
    LIST_ONLY=1
    NEW_JDK_STRING="$OLD_JDK_STRING"
    echo "Warning: Script is running in SAFE_MODE. No modifications will be made."
    echo "NEW_JDK_STRING set to OLD_JDK_STRING ('$OLD_JDK_STRING') to prevent unintended changes."
    echo
fi

# --- Option validation ---
if [ $DO_DOMAIN -eq 1 ] && [ $DO_OUI -eq 1 ]; then
    echo "Error: -d and -o are mutually exclusive. Choose one."
    show_help
    exit 2
fi
if [ $DO_DOMAIN -eq 0 ] && [ $DO_OUI -eq 0 ]; then
    echo "Error: You must specify either -d (DOMAIN) or -o (OUI) mode."
    show_help
    exit 2
fi

if [ $DO_OUI -eq 1 ]; then
    if [ $OUI_BACKUP -eq 1 ] && [ $OUI_UPDATE -eq 1 ]; then
        echo "Error: -b and -u are mutually exclusive in OUI mode."
        show_help
        exit 2
    fi
    if [ $LIST_ONLY -eq 0 ] && [ $OUI_BACKUP -eq 0 ] && [ $OUI_UPDATE -eq 0 ]; then
        echo "Error: In OUI mode you must specify either -b (backup), -u (update), or -l (list)."
        show_help
        exit 2
    fi
fi

if [ $LIST_ONLY -eq 1 ] && [ $DO_OUI -eq 1 ]; then
    if [ $OUI_BACKUP -eq 1 ] || [ $OUI_UPDATE -eq 1 ]; then
        OUI_BACKUP=0
        OUI_UPDATE=0
        echo "List-only (-l) mode selected: OUI backup/update will NOT be performed."
    fi
fi

# --- Environment variable checks ---
if [ $DO_DOMAIN -eq 1 ] && [ -z "$DOMAIN_HOME" ]; then
    echo "Environment variable DOMAIN_HOME must be defined."
    exit 2
fi

if [ $DO_OUI -eq 1 ]; then
    if [ -z "$ORACLE_HOME" ]; then
        echo "Environment variable ORACLE_HOME must be defined."
        exit 2
    fi
    OUI_BIN="$ORACLE_HOME/oui/bin"
    if [ ! -x "$OUI_BIN/getProperty.sh" ]; then
        echo "'$OUI_BIN/getProperty.sh' not found or not executable; Make sure Oracle WebLogic Server is properly installed."
        exit 2
    fi
fi

# --- Shared/active search variable ---
if [ -n "$TEST_JDK_STRING" ]; then
    SEARCH_JDK_STRING="$TEST_JDK_STRING"
    target_label="TEST"
else
    SEARCH_JDK_STRING="$OLD_JDK_STRING"
    target_label="OLD"
fi

# Function: Find files containing a given string under a root directory, excluding specified subdirectories or directory paths.
find_files() {
    # Usage: find_files <search_root> <search_string> [exclude_dir_pattern ...]
    local search_root="$1"
    local search_string="$2"
    shift 2
    local excludes=("$@")

    local prune_expr=()
    for ex in "${excludes[@]}"; do
        if [[ "$ex" == */* ]]; then
            prune_expr+=( -path "$search_root/$ex" -prune -o )
        else
            prune_expr+=( -name "$ex" -prune -o )
        fi
    done

    if [ "$VERBOSE_LIST" = "1" ]; then
        find "$search_root" "${prune_expr[@]}" -type f -print \
            | xargs grep -Fn --color=auto "$search_string" 2>/dev/null \
            | grep -Ev '\.(log|out)$'
    else
        find "$search_root" "${prune_expr[@]}" -type f -print \
            | xargs grep -Fl --color=auto "$search_string" 2>/dev/null \
            | grep -Ev '\.(log|out)$'
    fi
}

# Function: Escape the old/new JDK strings for Perl regex and replacement (DOMAIN_HOME)
escape_perl_regex() {
    printf '%s' "$1" | perl -pe 's/([\[\]\(\)\{\}\^\$\.\|\?\*\+\\\/])/\\$1/g'
}
escape_perl_replace() {
    printf '%s' "$1" | perl -pe 's/([\\\$\@])/\\$1/g'
}

if [ $DO_DOMAIN -eq 1 ]; then
    if [ -z "$TEST_JDK_STRING" ]; then
        PERL_DOMAIN_OLD=$(escape_perl_regex "$OLD_JDK_STRING")
        PERL_DOMAIN_NEW=$(escape_perl_replace "$NEW_JDK_STRING")
    fi
fi

# Function: replace string in DOMAIN_HOME files
replace_domain_string() {
    if [ $AUTO_YES_ALL -eq 1 ]; then
        echo "processing '$1'"
        perl -pi -e "s%$PERL_DOMAIN_OLD%$PERL_DOMAIN_NEW%g;" "$1"
        return
    fi

    local ACK
    echo "string found in '$1'"
    read -t 10 -p "Do you want me to proceed? ([y]/n): " ACK </dev/tty
    : ${ACK:=y}

    if [ "$ACK" = "y" ] || [ "$ACK" = "Y" ]; then
        echo -e "processing '$1'\n"
        perl -pi -e "s%$PERL_DOMAIN_OLD%$PERL_DOMAIN_NEW%g;" "$1"
    else
        echo -e "skipped\n"
    fi
}

# --- MAIN LOGIC ---

# DOMAIN mode
if [ $DO_DOMAIN -eq 1 ]; then
    echo "Processing DOMAIN_HOME: $DOMAIN_HOME"
    echo "${target_label}_JDK_STRING: $SEARCH_JDK_STRING"
    if [ -z "$TEST_JDK_STRING" ]; then
        echo -n "NEW_JDK_STRING: $NEW_JDK_STRING"
        if [ "$SAFE_MODE" = "1" ]; then
            echo " (SAFE_MODE)"
        else
            echo
        fi
    fi

    file_list_domain=$(find_files "$DOMAIN_HOME" "$SEARCH_JDK_STRING" "logs" "tmp" "adr")
    if [ $LIST_ONLY -eq 1 ]; then
        if [ $VERBOSE_LIST -eq 1 ]; then
            echo "Listing files and matching lines containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in DOMAIN_HOME"
        else
            echo "Listing files containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in DOMAIN_HOME"
        fi
        echo "-----------------------------------------------------------------------"
        if [ -z "$file_list_domain" ]; then
            echo "No matching files found."
        else
            echo "$file_list_domain"
        fi
        echo "-----------------------------------------------------------------------"
        exit 0
    else
        echo "Starting replacement of JAVA_HOME string..."

        file_count=$(echo "$file_list_domain" | grep -c .)
        if [ "$file_count" -ge 2 ]; then
            read -t 15 -p "Do you want me to process all $file_count matched files without further confirmation? ([y]/n): " BATCH_ACK </dev/tty
            : ${BATCH_ACK:=n}
            if [ "$BATCH_ACK" = "y" ] || [ "$BATCH_ACK" = "Y" ]; then
                AUTO_YES_ALL=1
            fi
        fi

        while read -r FNAME; do
            [ -z "$FNAME" ] && continue
            if [ ! -f "$FNAME" ]; then
                echo "No such file '$FNAME'"
                continue
            fi
            replace_domain_string "$FNAME"
        done <<< "$file_list_domain"
        exit 0
    fi
fi

# OUI mode
if [ $DO_OUI -eq 1 ]; then
    echo "Processing ORACLE_HOME: $ORACLE_HOME"
    echo "${target_label}_JDK_STRING: $SEARCH_JDK_STRING"
    if [ -z "$TEST_JDK_STRING" ]; then
        echo -n "NEW_JDK_STRING: $NEW_JDK_STRING"
        if [ "$SAFE_MODE" = "1" ]; then
            echo " (SAFE_MODE)"
        else
            echo
        fi
    fi

    file_list_oracle=$(find_files "$ORACLE_HOME" "$SEARCH_JDK_STRING" ".patch_storage" "logs" "tmp" "inventory/backup")
    if [ $LIST_ONLY -eq 1 ]; then
        CURRENT_OUI_JAVA_HOME=$("$OUI_BIN/getProperty.sh" OLD_JAVA_HOME 2>/dev/null)
        echo "Current OUI JAVA_HOME property: $CURRENT_OUI_JAVA_HOME"
        echo

        if [ $VERBOSE_LIST -eq 1 ]; then
            echo "Listing files and matching lines containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in ORACLE_HOME"
        else
            echo "Listing files containing ${target_label}_JDK_STRING ('$SEARCH_JDK_STRING') in ORACLE_HOME"
        fi
        echo "-----------------------------------------------------------------------"
        if [ -z "$file_list_oracle" ]; then
            echo "No matching files found."
        else
            echo "$file_list_oracle"
        fi
        echo "-----------------------------------------------------------------------"
        exit 0
    fi

    if [ $OUI_BACKUP -eq 1 ]; then
        echo "Starting OUI Backup phase of current JAVA_HOME property..."
        if [ ! -d "$OLD_JDK_STRING" ] || [ ! -x "$OLD_JDK_STRING/bin/java" ]; then
            echo "Warning: The OLD_JDK_STRING directory ('$OLD_JDK_STRING') is missing or does not contain an executable bin/java."
            echo "Main cause may be that you already replaced or removed the old JDK before backing up this OUI property."
            read -t 15 -p "Continue with backup anyway? (y/[n]): " ACK </dev/tty
            : ${ACK:=n}
            if [ "$ACK" != "y" ] && [ "$ACK" != "Y" ]; then
                echo "Backup aborted."
                exit 1
            fi
        fi

        echo "Backing up current JAVA_HOME to OLD_JAVA_HOME property..."
        "$OUI_BIN/setProperty.sh" -name OLD_JAVA_HOME -value "$OLD_JDK_STRING"
        RESULT_OLD_JAVA_HOME=$("$OUI_BIN/getProperty.sh" OLD_JAVA_HOME 2>/dev/null)
        if [ "$RESULT_OLD_JAVA_HOME" != "$OLD_JDK_STRING" ]; then
            echo "Error: Failed to back up to OLD_JAVA_HOME property in OUI."
            echo "Expected: '$OLD_JDK_STRING'"
            echo "Actual:   '$RESULT_OLD_JAVA_HOME'"
            exit 1
        fi
        echo "OUI JAVA_HOME backup done."
        exit 0
    fi

    if [ $OUI_UPDATE -eq 1 ]; then
        echo "Starting Update phase of OUI property..."
        # Check if OUI backup exists and matches OLD_JDK_STRING
        OLD_OUI_JDK_STRING=$("$OUI_BIN/getProperty.sh" OLD_JAVA_HOME 2>/dev/null)
        if [ -z "$OLD_OUI_JDK_STRING" ] || [ "$OLD_OUI_JDK_STRING" != "$OLD_JDK_STRING" ]; then
            read -t 15 -p "OUI backup (OLD_JAVA_HOME) not found or does not match OLD_JDK_STRING. Continue with update? (y/[n]): " ACK </dev/tty
            : ${ACK:=n}
            if [ "$ACK" != "y" ] && [ "$ACK" != "Y" ]; then
                echo "Update aborted. Please make a backup first using -o -b."
                exit 1
            fi
        fi

        echo "Updating JAVA_HOME property..."
        "$OUI_BIN/setProperty.sh" -name JAVA_HOME -value "$NEW_JDK_STRING"
        RESULT_OUI_JDK_STRING=$("$OUI_BIN/getProperty.sh" JAVA_HOME 2>/dev/null)
        if [ "$RESULT_OUI_JDK_STRING" != "$NEW_JDK_STRING" ]; then
            echo "Error: JAVA_HOME property in OUI was not updated as expected."
            echo "Expected: '$NEW_JDK_STRING'"
            echo "Actual:   '$RESULT_OUI_JDK_STRING'"
            exit 1
        fi
        echo "OUI JAVA_HOME updated."
        exit 0
    fi
fi
