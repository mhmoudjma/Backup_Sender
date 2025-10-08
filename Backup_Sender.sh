#!/bin/bash
RESET="\e[0m"
BOLD="\e[1m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
BLUE="\e[1;34m"
CYAN="\e[1;36m"
MAGENTA="\e[1;35m"
WHITE="\e[1;37m"
RED="\e[1;31m"


clear
for i in {1..3}; do
    echo -e "${GREEN}"
    figlet "BACKUP SENDER"
    echo -e "${RESET}"
    sleep 0.6
    clear
    sleep 0.3
done
echo -e "${RESET}"

# ==================================
# دالة تحميل التوكن
# ==================================
load_token() {
    local env_file="./token.env"
    if [ ! -f "$env_file" ]; then
        echo "token file not exist: $env_file"
        return 1
    fi
    source "$env_file"
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        echo "BOT_TOKEN or CHAT_ID missing in $env_file"
        return 2
    fi
    return 0
}

# ==================================
# تنظيف المسار
# ==================================
normalize_path() {
    local p="$1"
    p="${p%\"}"
    p="${p#\"}"
    p="${p%\'}"
    p="${p#\'}"
    p="${p#file://}"
    p="$(echo -n "$p" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    printf "%s" "$p"
}

# ==================================
# دالة التشفير
# ==================================
encrypt() {
    local input="$1"
    local method=""
    local outpath=""
    local keys_dir="./keys"
    local keylog="./keys.log"
    local timestamp
    timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
    local temp_tar="" remove_temp_tar=0

    if [ -z "$input" ]; then
        printf >&2 "Error: input path is required.\n"
        return 1
    fi

    if [ ! -e "$input" ]; then
        printf >&2 "Error: path does not exist: %s\n" "$input"
        return 2
    fi

    printf >&2 "\nChoose encryption method:\n"
    printf >&2 "  1) gpg (AES-256) [recommended]\n"
    printf >&2 "  2) openssl-gcm (AES-256-GCM)\n"
    printf >&2 "  3) openssl-cbc (AES-256-CBC + pbkdf2)\n"
    printf >&2 "Enter 1, 2 or 3 (default 1): "
    read -r choice

    case "${choice:-1}" in
        1) method="gpg" ;;
        2) method="openssl-gcm" ;;
        3) method="openssl-cbc" ;;
        *) method="gpg" ;;
    esac

    if [ -d "$input" ]; then
        temp_tar="/tmp/$(basename "$input")_${timestamp}.tar"
        printf >&2 "Creating tar archive: %s\n" "$temp_tar"
        if ! tar -cf "$temp_tar" -C "$(dirname "$input")" "$(basename "$input")"; then
            printf >&2 "Failed to create tar archive.\n"
            return 3
        fi
        input="$temp_tar"
        remove_temp_tar=1
    fi

    local pass
    if command -v openssl >/dev/null 2>&1; then
        pass="$(openssl rand -base64 32)"
    else
        pass="$(head -c 32 /dev/urandom | base64)"
    fi

    outpath="${input}.${method}.${timestamp}.enc"
    mkdir -p "$keys_dir"

    case "$method" in
        gpg)
            gpg --symmetric --cipher-algo AES256 --batch --yes \
                --passphrase "$pass" --pinentry-mode loopback \
                -o "$outpath" "$input" || { echo "gpg encryption failed"; return 11; }
            ;;
        openssl-gcm)
            openssl enc -aes-256-gcm -pbkdf2 -iter 200000 -salt \
                -in "$input" -out "$outpath" -pass pass:"$pass" \
                || { echo "OpenSSL GCM encryption failed"; return 13; }
            ;;
        openssl-cbc)
            openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
                -in "$input" -out "$outpath" -pass pass:"$pass" \
                || { echo "OpenSSL CBC encryption failed"; return 15; }
            ;;
    esac

    local keyfile="${keys_dir}/key_$(basename "$outpath")_${timestamp}.txt"
    printf '%s\n' "$pass" > "$keyfile"
    chmod 600 "$keyfile"
    printf '%s\t%s\t%s\t%s\n' "$timestamp" "$method" "$outpath" "$keyfile" >> "$keylog"

    if [ "$remove_temp_tar" -eq 1 ]; then rm -f "$temp_tar"; fi

    printf >&2 "\n=========================\n"
    printf >&2 "Encryption complete.\nEncrypted file: %s\nKey file: %s\nMethod: %s\nTimestamp: %s\n=========================\n\n" \
        "$outpath" "$keyfile" "$method" "$timestamp"

    printf '%s' "$outpath"
}

# ==================================
# دالة الإرسال للتلغرام
# ==================================
to_telegram() {
    local file_path="$1"
    echo "[Telegram] Sending: $file_path"

    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F chat_id="${CHAT_ID}" \
        -F document=@"${file_path}")

    if [[ "$response" == 2* ]]; then
        echo "[Telegram] ✅ Successfully sent (HTTP $response)"
    else
        echo "[Telegram] ❌ Failed to send (HTTP $response)"
    fi
}

# ==================================
# دالة النفق
# ==================================
temporary_tunnel() {
    local enc_path="$1"
    echo "[Tunnel] Do you want to enable temporary secure tunnel? (y/n)"
    read -rp "> " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        echo "[Tunnel] Skipping tunnel creation."
        to_telegram "$enc_path"
        return
    fi

    if ! command -v socat >/dev/null 2>&1; then
        echo "[Tunnel] socat not found. Sending without tunnel."
        to_telegram "$enc_path"
        return
    fi

    local local_port=8443
    local target_host="api.telegram.org"
    local target_port=443

    echo "[Tunnel] Creating tunnel..."
    socat TCP-LISTEN:${local_port},reuseaddr,fork TCP:${target_host}:${target_port} >/dev/null 2>&1 &
    local tunnel_pid=$!
    sleep 1

    if ! lsof -i TCP:"$local_port" >/dev/null 2>&1; then
        echo "[Tunnel] Failed to create tunnel. Sending without tunnel."
        to_telegram "$enc_path"
        return
    fi

    echo "[Tunnel] ✅ Tunnel active on localhost:${local_port}"
    to_telegram "$enc_path"
    kill "$tunnel_pid" >/dev/null 2>&1
    echo "[Tunnel] ✅ Tunnel closed."
}

# ==================================
# دالة فك التشفير
# ==================================
decrypt_file() {
    local encrypted_file
    local key_file

    read -e -p "Enter encrypted file path: " encrypted_file
    encrypted_file="$(normalize_path "$encrypted_file")"

    if [ ! -f "$encrypted_file" ]; then
        echo "[ERROR] Encrypted file not found."
        read -p "Press Enter to return to menu..."
        return 1
    fi

    read -e -p "Enter key file path: " key_file
    key_file="$(normalize_path "$key_file")"

    if [ ! -f "$key_file" ]; then
        echo "[ERROR] Key file not found."
        read -p "Press Enter to return to menu..."
        return 2
    fi

    local decrypted_file="${encrypted_file%.enc}.dec"
    local methods=("gpg" "openssl-gcm" "openssl-cbc")
    local success=0

    for method in "${methods[@]}"; do
        echo "[INFO] Trying method: $method"
        case "$method" in
            gpg)
                gpg --batch --yes --passphrase-file "$key_file" --pinentry-mode loopback \
                    -o "$decrypted_file" -d "$encrypted_file" && success=1
                ;;
            openssl-gcm)
                openssl enc -aes-256-gcm -pbkdf2 -iter 200000 -salt \
                    -in "$encrypted_file" -out "$decrypted_file" -pass file:"$key_file" && success=1
                ;;
            openssl-cbc)
                openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
                    -in "$encrypted_file" -out "$decrypted_file" -pass file:"$key_file" && success=1
                ;;
        esac
        if [ $success -eq 1 ]; then
            echo "[SUCCESS] File decrypted with method: $method"
            echo "[SUCCESS] Decrypted file: $decrypted_file"
            read -p "Press Enter to return to menu..."
            return 0
        fi
    done

    echo "[ERROR] Decryption failed with all methods."
    read -p "Press Enter to return to menu..."
    return 3
}
# ==================================
# Display Main Banner
# ==================================
display_main_banner() {
    clear
    printf "${CYAN}${BOLD}"
    figlet -f slant "Backup Sender"
    printf "${RESET}\n"

    printf "${MAGENTA}==================================================${RESET}\n"
    printf "${GREEN}${BOLD}       Secure & Fast Backup Tool                 ${RESET}\n"
    printf "${MAGENTA}==================================================${RESET}\n"
}

display_menu() {
    printf "${YELLOW}${BOLD}Select an option:${RESET}\n"
    printf "${BLUE} 1)${WHITE} Periodic Copy (with encryption) 🔒\n"
    printf "${BLUE} 2)${WHITE} Instant Copy (without encryption) 📤\n"
    printf "${BLUE} 3)${WHITE} Decrypt File 🗝️\n"
    printf "${BLUE} q)${WHITE} Quit 🚪\n"
    printf "${MAGENTA}--------------------------------------------------${RESET}\n"
    printf "${CYAN}Your choice: ${RESET}"
}
 
# ==================================
# Main Loop
# ==================================
   load_token

    while true; do
    display_main_banner
    display_menu
    read -r option
    case $option in
        1)
            clear
            echo -e "${YELLOW}"
            echo "    _______  "
            echo "   /      / /"
            echo "  / FILE / /"
            echo " /______/ /"
            echo "(______( /"
            echo " ------  "
            echo -e "${RESET}"

            read -e -p "Drag the file or folder (or paste path) and press Enter: " file
            clean_path="$(normalize_path "$file")"
            encrypted_path="$(encrypt "$clean_path")"
            if [ -n "$encrypted_path" ]; then
                temporary_tunnel "$encrypted_path"
            else
                echo "❌ Encryption failed."
            fi
            ;;
        2)
            clear
            echo -e "${BLUE}"
            echo "    _______  "
            echo "   /      / /"
            echo "  / FILE / /"
            echo " /______/ /"
            echo "(______( /"
            echo " ------  "
            echo -e "${RESET}"
             read -e -p "Drag the file or folder (or paste path) and press Enter: " file
    clean_path="$(normalize_path "$file")"

           if [ ! -f "$clean_path" ] && [ ! -d "$clean_path" ]; then
           echo "❌ File or folder not found."
           sleep 1
           continue
    	   fi

    	   temporary_tunnel "$clean_path"
            ;;
        3) 
	    clear
            echo -e "${GREEN}"
            echo "     _______  "
            echo "   /         / /"
            echo "  / DECRYPT / /"
            echo " /_________/ /"
            echo "(_________( /"
            echo " ------  "
            echo -e "${RESET}"
            decrypt_file
            ;;
        q|Q)
            echo "bye."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            sleep 1
            ;;
    esac
done
