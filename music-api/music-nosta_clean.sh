#!/bin/bash

# Nosta CLI - Music management tool
# Requires: curl, jq, mpv, ffmpeg (optional)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

API_BASE="https://nosta-server.onrender.com"
API_VERSION="/api/v1"
APP_SECRET="nosta_v2_jwt_enforced_2026"

TOKEN_FILE="$HOME/.nosta_token"
USER_FILE="$HOME/.nosta_user"
CONFIG_DIR="$HOME/.nosta"
TEMP_DIR="/tmp/nosta_uploads"
CACHE_DIR="$HOME/.nosta/cache"

init() {
    mkdir -p "$CONFIG_DIR" "$TEMP_DIR" "$CACHE_DIR"
    check_dependencies
    clear
    print_header
}

check_dependencies() {
    local missing=()

    for cmd in curl jq mpv; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED} Missing dependencies: ${missing[*]}${NC}"
        echo -e "${YELLOW} Install with:${NC}"
        echo -e "  ${BLUE}sudo pacman -S ${missing[*]}${NC}"
        exit 1
    fi
}

validate_json_response() {
    local response="$1"
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        print_error "Invalid JSON response from server"
        echo -e "${DIM}$(echo "$response" | head -c 300)${NC}"
        return 1
    fi
    return 0
}

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_valid_id() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

sanitize_input() {
    echo "$1" | sed 's/[^a-zA-Z0-9 _-]//g' | cut -c1-100
}

extract_metadata() {
    local audio_file="$1"
    local title=""
    local artist=""
    local cover_file=""

    if command -v ffmpeg &> /dev/null; then
        title=$(ffprobe -v quiet -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
        if [ -z "$title" ]; then
            title=$(basename "$audio_file" | sed 's/\.[^.]*$//' | sed 's/[_\-]/ /g')
        fi

        artist=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
        if [ -z "$artist" ]; then
            local filename=$(basename "$audio_file" | sed 's/\.[^.]*$//')
            if [[ "$filename" =~ ^[^-]+\ -\ (.+)$ ]] || [[ "$filename" =~ ^(.+)\ -\ (.+)$ ]]; then
                artist=$(echo "$filename" | sed 's/ - .*//')
            else
                artist="Unknown Artist"
            fi
        fi

        cover_file="$TEMP_DIR/cover_$(date +%s)_$$.jpg"
        ffmpeg -i "$audio_file" -an -vcodec copy "$cover_file" 2>/dev/null
        if [ ! -f "$cover_file" ] || [ ! -s "$cover_file" ]; then
            rm -f "$cover_file"
            cover_file=""
        fi
    else
        title=$(basename "$audio_file" | sed 's/\.[^.]*$//' | sed 's/[_\-]/ /g')
        artist="Unknown Artist"
        cover_file=""
    fi

    echo "$title|$artist|$cover_file"
}

extract_artist_from_file() {
    local audio_file="$1"
    local artist=""

    if command -v ffmpeg &> /dev/null; then
        artist=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
    fi

    if [ -z "$artist" ]; then
        local filename=$(basename "$audio_file" | sed 's/\.[^.]*$//')
        if [[ "$filename" =~ ^[^-]+\ -\ (.+)$ ]] || [[ "$filename" =~ ^(.+)\ -\ (.+)$ ]]; then
            artist=$(echo "$filename" | sed 's/ - .*//')
        else
            artist="Unknown Artist"
        fi
    fi

    echo "$artist"
}

extract_title_from_file() {
    local audio_file="$1"
    local title=""

    if command -v ffmpeg &> /dev/null; then
        title=$(ffprobe -v quiet -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
    fi

    if [ -z "$title" ]; then
        title=$(basename "$audio_file" | sed 's/\.[^.]*$//' | sed 's/[_\-]/ /g')
    fi

    echo "$title"
}

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "  NOSTA MUSIC MANAGER"
    echo "  Terminal Interface v3.6.0"
    echo -e "${NC}"
}

print_menu() {
    echo -e "${CYAN}${BOLD}  MAIN MENU${NC}"
    echo "  1) List All Songs"
    echo "  2) Search Songs"
    echo "  3) Upload Song(s)"
    echo "  4) Edit Song"
    echo "  5) Delete Song"
    echo "  6) Delete Multiple Songs"
    echo "  7) View Favorites"
    echo "  8) User Profile"
    echo "  9) Statistics"
    echo "  10) Now Playing"
    echo "  11) Update Artists (from server)"
    echo "  12) Update Artists (from local folder)"
    echo "  0) Logout & Exit"
    echo -ne "${BOLD}Enter choice: ${NC}"
}

print_subheader() {
    echo -e "
${MAGENTA}${BOLD}  $1${NC}
"
}

print_error() {
    echo -e "${RED}[ERR] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

print_progress() {
    echo -ne "${CYAN}... $1${NC}"
}

display_image_kitty() {
    local url="$1"
    local max_width="${2:-400}"
    local max_height="${3:-400}"

    if [ -z "$url" ] || [ "$url" = "null" ]; then
        echo -e "${DIM}  No image${NC}"
        return 1
    fi

    if [ "$TERM" != "xterm-kitty" ] && [ -z "$KITTY_WINDOW_ID" ]; then
        echo -e "${DIM}   URL: $url${NC}"
        return 0
    fi

    local temp_file="$TEMP_DIR/img_$(date +%s)_$$"

    if [[ "$url" == http* ]]; then
        curl -s -L -o "$temp_file" "$url" 2>/dev/null
    else
        temp_file="$url"
    fi

    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        kitty +kitten icat --align left --place "${max_width}x${max_height}@0x0" "$temp_file" 2>/dev/null
        if [[ "$url" == http* ]]; then
            rm -f "$temp_file"
        fi
        return 0
    fi

    echo -e "${DIM}   URL: $url${NC}"
    return 0
}

display_user_avatar_kitty() {
    local user=$(get_user_info)
    local avatar=$(echo "$user" | jq -r '.avatarURL // ""' 2>/dev/null)

    if [ -n "$avatar" ] && [ "$avatar" != "null" ]; then
        echo -e "${BLUE}${BOLD} Avatar:${NC}"
        display_image_kitty "$avatar" 300 300
        echo
    fi
}

display_song_cover_kitty() {
    local cover_url="$1"
    if [ -n "$cover_url" ] && [ "$cover_url" != "null" ]; then
        echo -e "${BLUE}${BOLD} Cover Art:${NC}"
        display_image_kitty "$cover_url" 400 400
        echo
    fi
}

display_user_info() {
    local user=$(get_user_info)
    local username=$(echo "$user" | jq -r '.username // "Unknown"' 2>/dev/null)
    local name=$(echo "$user" | jq -r '.name // "Unknown"' 2>/dev/null)
    local email=$(echo "$user" | jq -r '.email // "Unknown"' 2>/dev/null)
    local role=$(echo "$user" | jq -r '.role // "Normal"' 2>/dev/null)
    local avatar=$(echo "$user" | jq -r '.avatarURL // ""' 2>/dev/null)
    echo -e "
${CYAN}${BOLD}  USER PROFILE${NC}"
    display_user_avatar_kitty
    echo -e "${WHITE}${BOLD}Name:${NC}     $name"
    echo -e "${WHITE}${BOLD}Username:${NC}  $username"
    echo -e "${WHITE}${BOLD}Email:${NC}     $email"
    if [ "$role" = "VIP" ]; then
        echo -e "${WHITE}${BOLD}Role:${NC}     ${GREEN}${BOLD}VIP${NC}"
    else
        echo -e "${WHITE}${BOLD}Role:${NC}     Normal"
    fi
    echo
}

login() {
    print_subheader " LOGIN"

    echo -ne "${BOLD}${WHITE} Email: ${NC}"
    read -r email

    echo -ne "${BOLD}${WHITE} Password: ${NC}"
    read -rs password
    echo

    if [ -z "$email" ] || [ -z "$password" ]; then
        print_error "Email and password are required"
        return 1
    fi

    print_progress "Authenticating..."

    local response=$(curl -s -X POST "${API_BASE}/api/auth/login" \
        -H "Content-Type: application/json" \
        -H "X-App-Secret: ${APP_SECRET}" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")

    if [ $? -ne 0 ]; then
        print_error "Failed to connect to server"
        return 1
    fi

    if ! validate_json_response "$response"; then
        return 1
    fi

    local token=$(echo "$response" | jq -r '.token // ""')
    local user=$(echo "$response" | jq -r '.user // ""')

    if [ -z "$token" ] || [ "$token" = "null" ]; then
        print_error "Invalid credentials"
        return 1
    fi

    echo "$token" > "$TOKEN_FILE"
    echo "$user" > "$USER_FILE"

    print_success "Login successful!"
    display_user_info
    return 0
}

check_auth() {
    if [ ! -f "$TOKEN_FILE" ]; then
        print_warning "You are not logged in"
        echo -ne "${BLUE} Login now? (y/n): ${NC}"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            login
        else
            return 1
        fi
    fi

    local token=$(cat "$TOKEN_FILE" 2>/dev/null)
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        print_error "Invalid token. Please login."
        rm -f "$TOKEN_FILE" "$USER_FILE"
        login
        return $?
    fi

    return 0
}

get_token() {
    cat "$TOKEN_FILE" 2>/dev/null || echo ""
}

get_user_info() {
    cat "$USER_FILE" 2>/dev/null || echo "{}"
}

logout() {
    rm -f "$TOKEN_FILE" "$USER_FILE"
    print_success "Logged out successfully"
}

MPV_PID=""
CURRENT_SONG=""
CURRENT_SONG_ID=""

play_song() {
    local song_id="$1"
    local title="$2"
    local artist="$3"

    stop_song

    local token=$(get_token)
    local stream_url="${API_BASE}${API_VERSION}/songs/${song_id}/stream"

    print_info "Loading: $title - $artist"

    mpv --no-video --term-osd-bar --term-osd=force \
        --msg-level=all=no \
        --cache=yes --cache-secs=30 \
        --http-header-fields="Authorization: Bearer ${token}" \
        --http-header-fields="X-App-Secret: ${APP_SECRET}" \
        "$stream_url" &

    MPV_PID=$!
    CURRENT_SONG="$title - $artist"
    CURRENT_SONG_ID="$song_id"

    print_success "  Now Playing: $title - $artist"
}

stop_song() {
    if [ -n "$MPV_PID" ] && kill -0 "$MPV_PID" 2>/dev/null; then
        kill "$MPV_PID" 2>/dev/null
        wait "$MPV_PID" 2>/dev/null
        MPV_PID=""
        CURRENT_SONG=""
        CURRENT_SONG_ID=""
        print_info "⏹  Stopped"
    fi
}

show_now_playing() {
    if [ -n "$CURRENT_SONG" ]; then
        echo -e "\n${GREEN}${BOLD}  NOW PLAYING${NC}"
        echo -e "${WHITE}$CURRENT_SONG${NC}"
        echo -e "${DIM}ID: $CURRENT_SONG_ID${NC}"

        if [ -n "$CURRENT_SONG_ID" ]; then
            local token=$(get_token)
            local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs/${CURRENT_SONG_ID}" \
                -H "Authorization: Bearer ${token}" \
                -H "X-App-Secret: ${APP_SECRET}")
            
            if validate_json_response "$response"; then
                local cover=$(echo "$response" | jq -r '.coverArtUrl // ""' 2>/dev/null)
                if [ -n "$cover" ] && [ "$cover" != "null" ]; then
                    display_song_cover_kitty "$cover"
                fi
            fi
        fi
    else
        print_warning "No song playing"
    fi
    echo
    read -p "Press Enter to continue..."
}

extract_cover_art() {
    local audio_file="$1"
    local cover_file="$TEMP_DIR/cover_$(date +%s)_$$.jpg"

    if command -v ffmpeg &> /dev/null; then
        ffmpeg -i "$audio_file" -an -vcodec copy "$cover_file" 2>/dev/null
        if [ -f "$cover_file" ] && [ -s "$cover_file" ]; then
            echo "$cover_file"
            return 0
        fi
        rm -f "$cover_file"
    fi

    if command -v exiftool &> /dev/null; then
        exiftool -ThumbnailImage -b "$audio_file" > "$cover_file" 2>/dev/null
        if [ -f "$cover_file" ] && [ -s "$cover_file" ]; then
            echo "$cover_file"
            return 0
        fi
        rm -f "$cover_file"
    fi

    return 1
}

upload_single_file() {
    echo -e "\n${BLUE} Select audio file:${NC}"
    echo -ne "${BOLD}${WHITE} File path: ${NC}"
    read -r file_path

    if [ ! -f "$file_path" ]; then
        print_error "File not found"
        return 1
    fi

    echo -e "\n${BLUE} Extracting metadata...${NC}"
    local metadata=$(extract_metadata "$file_path")
    local auto_title=$(echo "$metadata" | cut -d'|' -f1)
    local auto_artist=$(echo "$metadata" | cut -d'|' -f2)
    local cover_file=$(echo "$metadata" | cut -d'|' -f3)

    echo -e "${GREEN} Detected Title: ${WHITE}$auto_title${NC}"
    echo -e "${GREEN} Detected Artist: ${WHITE}$auto_artist${NC}"

    echo -ne "${BOLD}${WHITE} Title (press Enter to keep detected): ${NC}"
    read -r title
    [ -z "$title" ] && title="$auto_title"

    echo -ne "${BOLD}${WHITE} Artist (press Enter to keep detected): ${NC}"
    read -r artist
    [ -z "$artist" ] && artist="$auto_artist"

    echo -ne "${BOLD}${WHITE} Make public? (y/n): ${NC}"
    read -r is_public
    local public_flag="false"
    [[ "$is_public" =~ ^[Yy]$ ]] && public_flag="true"

    if [ -f "$cover_file" ] && [ -s "$cover_file" ]; then
        echo -e "${GREEN} Cover art found!${NC}"
    else
        echo -e "${YELLOW}  No cover art found${NC}"
        cover_file=""
    fi

    local token=$(get_token)
    local file_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null || echo "0")
    local file_size_mb=$(echo "scale=2; $file_size / 1048576" | bc 2>/dev/null || echo "0")

    echo -e "\n${BLUE} File size: ${WHITE}${file_size_mb} MB${NC}"
    echo -ne "${CYAN}⏳ Uploading...${NC}"

    local start_time=$(date +%s.%N 2>/dev/null || date +%s)

    local curl_args=(-s -X POST "${API_BASE}${API_VERSION}/songs/upload")
    curl_args+=(-H "Authorization: Bearer ${token}")
    curl_args+=(-H "X-App-Secret: ${APP_SECRET}")
    curl_args+=(-F "audio=@$file_path")
    curl_args+=(-F "title=$title")
    curl_args+=(-F "artist=$artist")
    curl_args+=(-F "isPublic=$public_flag")

    if [ -n "$cover_file" ] && [ -f "$cover_file" ]; then
        curl_args+=(-F "cover=@$cover_file")
    fi

    local response=$(curl "${curl_args[@]}" 2>&1)

    local end_time=$(date +%s.%N 2>/dev/null || date +%s)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null | cut -d. -f1)
    [ -z "$duration" ] && duration=1

    if [ -n "$cover_file" ] && [ -f "$cover_file" ]; then
        rm -f "$cover_file"
    fi

    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        local song_id=$(echo "$response" | jq -r '.id')
        local speed=$(echo "scale=2; $file_size_mb / $duration" | bc 2>/dev/null || echo "0")
        echo -e "\r${GREEN} Upload successful!${NC}"
        echo -e "${BLUE}⏱  Time: ${WHITE}${duration}s${NC}  ${BLUE} Speed: ${WHITE}${speed} MB/s${NC}"
        echo -e "${BLUE} Song ID: ${WHITE}$song_id${NC}"
    else
        echo -e "\r${RED} Upload failed${NC}"
        echo "$response" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "$response"
    fi

    echo
    read -p "Press Enter to continue..."
}

upload_folder() {
    echo -e "\n${BLUE} Select folder containing audio files:${NC}"
    echo -ne "${BOLD}${WHITE} Folder path: ${NC}"
    read -r folder_path

    if [ ! -d "$folder_path" ]; then
        print_error "Folder not found"
        return 1
    fi

    local audio_files=()
    while IFS= read -r -d '' file; do
        audio_files+=("$file")
    done < <(find "$folder_path" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.flac" -o -iname "*.m4a" -o -iname "*.aac" -o -iname "*.wma" \) -print0 2>/dev/null)

    local total_files=${#audio_files[@]}

    if [ $total_files -eq 0 ]; then
        print_warning "No audio files found"
        return 0
    fi

    echo -e "${GREEN} Found ${total_files} audio files${NC}"

    local total_size=0
    for file in "${audio_files[@]}"; do
        local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        total_size=$((total_size + size))
    done
    local total_size_mb=$(echo "scale=2; $total_size / 1048576" | bc 2>/dev/null || echo "0")

    echo -e "${BLUE} Total size: ${WHITE}${total_size_mb} MB${NC}"
    echo -ne "${BLUE}Continue with upload? (y/n): ${NC}"
    read -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return 0
    fi

    local success_count=0
    local fail_count=0
    local start_time=$(date +%s)

    for ((i=0; i<total_files; i++)); do
        local file="${audio_files[$i]}"
        local filename=$(basename "$file")
        local file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        local file_size_mb=$(echo "scale=2; $file_size / 1048576" | bc 2>/dev/null || echo "0")

        echo -e "\n${BLUE}[$((i+1))/${total_files}]${NC} ${WHITE}$filename${NC} (${file_size_mb} MB)"

        local metadata=$(extract_metadata "$file")
        local title=$(echo "$metadata" | cut -d'|' -f1)
        local artist=$(echo "$metadata" | cut -d'|' -f2)
        local cover_file=$(echo "$metadata" | cut -d'|' -f3)

        local token=$(get_token)
        local file_start=$(date +%s)

        echo -ne "${CYAN}⏳ Uploading...${NC}"

        local curl_args=(-s -X POST "${API_BASE}${API_VERSION}/songs/upload")
        curl_args+=(-H "Authorization: Bearer ${token}")
        curl_args+=(-H "X-App-Secret: ${APP_SECRET}")
        curl_args+=(-F "audio=@$file")
        curl_args+=(-F "title=$title")
        curl_args+=(-F "artist=$artist")
        curl_args+=(-F "isPublic=true")

        if [ -n "$cover_file" ] && [ -f "$cover_file" ]; then
            curl_args+=(-F "cover=@$cover_file")
        fi

        local response=$(curl "${curl_args[@]}" 2>&1)

        if [ -n "$cover_file" ] && [ -f "$cover_file" ]; then
            rm -f "$cover_file"
        fi

        local file_end=$(date +%s)
        local file_duration=$((file_end - file_start))
        [ $file_duration -lt 1 ] && file_duration=1

        if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
            local song_id=$(echo "$response" | jq -r '.id')
            success_count=$((success_count + 1))
            local speed=$(echo "scale=2; $file_size_mb / $file_duration" | bc 2>/dev/null || echo "0")
            echo -e "\r${GREEN} Uploaded: $title - $artist${NC}"
            echo -e "${DIM}   ⏱  ${file_duration}s |  ${speed} MB/s |  ${song_id:0:8}${NC}"
        else
            fail_count=$((fail_count + 1))
            local err=$(echo "$response" | jq -r '.message // "Unknown"' 2>/dev/null)
            echo -e "\r${RED} Failed: $title${NC}"
            [ -n "$err" ] && [ "$err" != "null" ] && echo -e "${DIM}   Error: $err${NC}"
        fi
    done

    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    [ $total_duration -lt 1 ] && total_duration=1

    echo -e "\n${GREEN}${BOLD}${NC}"
    echo -e "${GREEN}${BOLD}   UPLOAD COMPLETE${NC}"
    echo -e "${GREEN}${BOLD}${NC}"
    echo -e "${GREEN} Success: ${success_count}${NC}"
    echo -e "${RED} Failed: ${fail_count}${NC}"
    echo -e "${BLUE}⏱  Total time: ${WHITE}${total_duration}s${NC}"

    if [ $success_count -gt 0 ]; then
        local avg_speed=$(echo "scale=2; $total_size_mb / $total_duration" | bc 2>/dev/null || echo "0")
        echo -e "${BLUE} Average speed: ${WHITE}${avg_speed} MB/s${NC}"
    fi

    echo
    read -p "Press Enter to continue..."
}

upload_song() {
    print_subheader " UPLOAD SONG(S)"

    if ! check_auth; then
        return 1
    fi

    echo -e "${YELLOW}Choose upload option:${NC}"
    echo -e "${GREEN}  1)${NC} Upload single file"
    echo -e "${GREEN}  2)${NC} Upload all songs from folder"
    echo -ne "${BOLD}${CYAN} Enter choice: ${NC}"
    read -r upload_choice

    case $upload_choice in
        1) upload_single_file ;;
        2) upload_folder ;;
        *) print_error "Invalid choice" ;;
    esac
}

list_songs() {
    print_subheader " LIST ALL SONGS"

    if ! check_auth; then
        return 1
    fi

    local token=$(get_token)
    local page=1
    local limit=200

    print_progress "Loading songs..."

    local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs?page=${page}&limit=${limit}" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}")

    if [ $? -ne 0 ]; then
        print_error "Failed to fetch songs"
        return 1
    fi

    if ! validate_json_response "$response"; then
        print_error "Invalid response from server"
        read -p "Press Enter to continue..."
        return 1
    fi

    local songs=$(echo "$response" | jq -r '.data // []')
    local total=$(echo "$response" | jq -r '.pagination.totalItems // 0' 2>/dev/null)

    if [ -z "$songs" ] || [ "$songs" = "null" ]; then
        print_error "No songs found"
        read -p "Press Enter to continue..."
        return 1
    fi

    local count=$(echo "$songs" | jq '. | length' 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        print_warning "No songs found"
        echo
        read -p "Press Enter to continue..."
        return 0
    fi

    echo -e "\n${CYAN}${BOLD}${NC}"
    echo -e "${CYAN}${BOLD}${NC} ${WHITE}${BOLD}#  ID      TITLE                    ARTIST        DUR   PUB  FAV${NC} ${CYAN}${BOLD}${NC}"
    echo -e "${CYAN}${BOLD}${NC}"

    local i=0
    while IFS=$'\t' read -r id title artist duration isPublic isFavorite; do
        i=$((i + 1))
        
        local duration_str="--:--"
        if [ "$duration" -gt 0 ] 2>/dev/null; then
            duration_str=$(printf "%02d:%02d" $((duration/60)) $((duration%60)))
        fi

        local pub_icon=""
        [ "$isPublic" = "true" ] && pub_icon=""
        local fav_icon="  "
        [ "$isFavorite" = "true" ] && fav_icon=""

        title=$(echo "$title" | cut -c1-22)
        artist=$(echo "$artist" | cut -c1-13)
        id=$(echo "$id" | cut -c1-6)

        printf "${CYAN}${NC} ${WHITE}%2d${NC} ${BLUE}%-6s${NC} ${GREEN}%-22s${NC} ${YELLOW}%-13s${NC} ${MAGENTA}%5s${NC} ${CYAN}%2s${NC} ${YELLOW}%2s${NC} ${CYAN}${NC}\n" \
            "$i" "$id" "$title" "$artist" "$duration_str" "$pub_icon" "$fav_icon"
    done < <(echo "$songs" | jq -r '.[] | [.id, .title, .artist, .duration, .isPublic, .isFavorite] | @tsv')

    echo -e "${CYAN}${BOLD}${NC}"
    echo -e "\n${BLUE} Total: ${total} songs${NC}"

    echo -e "\n${YELLOW}Options:${NC}"
    echo -e "${GREEN}  p)${NC}   Play song"
    echo -e "${GREEN}  i)${NC}  Show cover art"
    echo -e "${GREEN}  Enter)${NC} Back to menu"
    echo -ne "${BOLD}${CYAN} Choice: ${NC}"
    read -r action

    case "$action" in
        [Pp])
            echo -ne "${BOLD}${WHITE} Enter song number: ${NC}"
            read -r song_num
            
            if ! is_number "$song_num"; then
                print_error "Invalid number"
            elif [ "$song_num" -ge 1 ] && [ "$song_num" -le "$count" ]; then
                local idx=$((song_num - 1))
                local song=$(echo "$songs" | jq -r ".[$idx]")
                local sid=$(echo "$song" | jq -r '.id')
                local stitle=$(echo "$song" | jq -r '.title')
                local sartist=$(echo "$song" | jq -r '.artist')
                play_song "$sid" "$stitle" "$sartist"
            else
                print_error "Number out of range (1-$count)"
            fi
            ;;
        [Ii])
            echo -ne "${BOLD}${WHITE} Enter song number: ${NC}"
            read -r song_num
            
            if ! is_number "$song_num"; then
                print_error "Invalid number"
            elif [ "$song_num" -ge 1 ] && [ "$song_num" -le "$count" ]; then
                local idx=$((song_num - 1))
                local song=$(echo "$songs" | jq -r ".[$idx]")
                local cover=$(echo "$song" | jq -r '.coverArtUrl // ""')
                if [ -n "$cover" ] && [ "$cover" != "null" ]; then
                    display_song_cover_kitty "$cover"
                else
                    print_warning "No cover art"
                fi
            else
                print_error "Number out of range (1-$count)"
            fi
            ;;
    esac

    echo
    read -p "Press Enter to continue..."
}

search_songs() {
    print_subheader " SEARCH SONGS"

    if ! check_auth; then
        return 1
    fi

    echo -ne "${BOLD}${WHITE} Enter search query: ${NC}"
    read -r query

    if [ -z "$query" ]; then
        print_error "Search query required"
        return 1
    fi

    query=$(sanitize_input "$query")

    local token=$(get_token)

    local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs/search" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}" \
        --data-urlencode "q=${query}" \
        --data-urlencode "limit=2000")

    if ! validate_json_response "$response"; then
        print_error "Invalid response from server"
        echo -e "${DIM}Server response: $(echo "$response" | head -c 200)${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi

    if ! echo "$response" | jq -e '.results' >/dev/null 2>&1; then
        print_error "Unexpected response format"
        read -p "Press Enter to continue..."
        return 1
    fi

    local results=$(echo "$response" | jq -r '.results // []')
    local total=$(echo "$response" | jq -r '.total // 0' 2>/dev/null)

    echo -e "\n${GREEN} Found ${total} results${NC}\n"

    if [ "$total" -eq 0 ]; then
        print_warning "No results for \"$query\""
        echo
        read -p "Press Enter to continue..."
        return 0
    fi

    local count=$(echo "$results" | jq '. | length' 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        print_warning "No results found"
        read -p "Press Enter to continue..."
        return 0
    fi

    echo -e "${CYAN}${BOLD}${NC}"
    echo -e "${CYAN}${BOLD}${NC} ${WHITE}${BOLD}#  TITLE                    ARTIST        DURATION${NC} ${CYAN}${BOLD}${NC}"
    echo -e "${CYAN}${BOLD}${NC}"

    for ((i=0; i<count; i++)); do
        local song=$(echo "$results" | jq -r ".[$i]")
        local title=$(echo "$song" | jq -r '.title // "Untitled"' | cut -c1-24)
        local artist=$(echo "$song" | jq -r '.artist // "Unknown"' | cut -c1-14)
        local duration=$(echo "$song" | jq -r '.duration // 0')

        local duration_str="--:--"
        if [ "$duration" -gt 0 ]; then
            duration_str=$(printf "%02d:%02d" $((duration/60)) $((duration%60)))
        fi

        local num=$((i + 1))
        printf "${CYAN}${NC} ${WHITE}%2d${NC}  ${GREEN}%-24s${NC} ${YELLOW}%-14s${NC} ${MAGENTA}%5s${NC} ${CYAN}${NC}\n" \
            "$num" "$title" "$artist" "$duration_str"
    done

    echo -e "${CYAN}${BOLD}${NC}"

    echo -e "\n${YELLOW}Options:${NC}"
    echo -e "${GREEN}  p)${NC}   Play song"
    echo -e "${GREEN}  i)${NC}  Show cover art"
    echo -e "${GREEN}  Enter)${NC} Back to menu"
    echo -ne "${BOLD}${CYAN} Choice: ${NC}"
    read -r action

    case "$action" in
        [Pp])
            echo -ne "${BOLD}${WHITE} Enter song number: ${NC}"
            read -r song_num
            
            if ! is_number "$song_num"; then
                print_error "Invalid number"
            elif [ "$song_num" -ge 1 ] && [ "$song_num" -le "$count" ]; then
                local idx=$((song_num - 1))
                local song=$(echo "$results" | jq -r ".[$idx]")
                local sid=$(echo "$song" | jq -r '.id')
                local stitle=$(echo "$song" | jq -r '.title')
                local sartist=$(echo "$song" | jq -r '.artist')
                play_song "$sid" "$stitle" "$sartist"
            else
                print_error "Number out of range (1-$count)"
            fi
            ;;
        [Ii])
            echo -ne "${BOLD}${WHITE} Enter song number: ${NC}"
            read -r song_num
            
            if ! is_number "$song_num"; then
                print_error "Invalid number"
            elif [ "$song_num" -ge 1 ] && [ "$song_num" -le "$count" ]; then
                local idx=$((song_num - 1))
                local song=$(echo "$results" | jq -r ".[$idx]")
                local cover=$(echo "$song" | jq -r '.coverArtUrl // ""')
                if [ -n "$cover" ] && [ "$cover" != "null" ]; then
                    display_song_cover_kitty "$cover"
                else
                    print_warning "No cover art"
                fi
            else
                print_error "Number out of range (1-$count)"
            fi
            ;;
    esac

    echo
    read -p "Press Enter to continue..."
}

update_artists() {
    print_subheader " UPDATE ARTISTS FROM SERVER"

    if ! check_auth; then
        return 1
    fi

    if ! command -v ffmpeg &> /dev/null; then
        print_error "ffmpeg is required for this feature"
        echo -e "${YELLOW} Install with: sudo pacman -S ffmpeg${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi

    local token=$(get_token)
    
    print_progress "Fetching songs without artist..."

    local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs?limit=200" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}")

    if ! validate_json_response "$response"; then
        print_error "Failed to fetch songs"
        return 1
    fi

    local songs=$(echo "$response" | jq -r '.data[] | select(.artist == "Unknown Artist" or .artist == "")')
    local count=$(echo "$songs" | jq -s 'length')

    if [ "$count" -eq 0 ]; then
        print_success "No songs need artist update!"
        echo
        read -p "Press Enter to continue..."
        return 0
    fi

    echo -e "\n${YELLOW} Found ${count} songs with 'Unknown Artist'${NC}"
    echo -e "${BLUE} Downloading and extracting artist from audio files...${NC}\n"

    local updated=0
    local failed=0
    local skipped=0
    local temp_dir="/tmp/nosta_artist_extract"
    mkdir -p "$temp_dir"

    local total=$count
    local current=0

    while IFS= read -r song; do
        current=$((current + 1))
        local id=$(echo "$song" | jq -r '.id')
        local title=$(echo "$song" | jq -r '.title')
        local current_artist=$(echo "$song" | jq -r '.artist')
        local isPublic=$(echo "$song" | jq -r '.isPublic')
        local new_artist=""

        echo -e "\n${CYAN}[${current}/${total}]${NC} ${DIM}$id${NC} → \"${WHITE}$title${NC}\""

        local temp_file="$temp_dir/${id}.mp3"
        print_progress "Downloading with redirect follow..."

        curl -s -L -o "$temp_file" "${API_BASE}${API_VERSION}/songs/${id}/stream" \
            -H "Authorization: Bearer ${token}" \
            -H "X-App-Secret: ${APP_SECRET}" \
            -H "User-Agent: Mozilla/5.0" \
            --max-time 120

        if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
            echo -e "\r${RED} Failed to download (file empty or not found)${NC}"
            failed=$((failed + 1))
            continue
        fi

        print_progress "Extracting metadata with ffprobe..."

        new_artist=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$temp_file" 2>/dev/null)
        
        if [ -z "$new_artist" ]; then
            if [[ "$title" =~ ^[[:space:]]*([^-–]+)[-–][[:space:]]*(.+)$ ]]; then
                new_artist=$(echo "$title" | sed -E 's/^[[:space:]]*([^-–]+)[-–].*$/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            else
                new_artist="Unknown Artist"
            fi
        fi

        new_artist=$(echo "$new_artist" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 100)
        if [ -z "$new_artist" ] || [ "$new_artist" = "$title" ]; then
            new_artist="Unknown Artist"
        fi

        rm -f "$temp_file"

        echo -e "\r   ${YELLOW}Artist:${NC} \"$current_artist\" → \"${GREEN}$new_artist${NC}\""

        if [ "$new_artist" != "$current_artist" ] && [ "$new_artist" != "Unknown Artist" ]; then
            local update_data=$(jq -n \
                --arg title "$title" \
                --arg artist "$new_artist" \
                --argjson isPublic "$isPublic" \
                '{title: $title, artist: $artist, isPublic: $isPublic}')

            local update_response=$(curl -s -X PUT "${API_BASE}${API_VERSION}/songs/${id}" \
                -H "Authorization: Bearer ${token}" \
                -H "X-App-Secret: ${APP_SECRET}" \
                -H "Content-Type: application/json" \
                -d "$update_data")

            if echo "$update_response" | jq -e '.id' >/dev/null 2>&1; then
                updated=$((updated + 1))
                echo -e "   ${GREEN} Updated${NC}"
            else
                failed=$((failed + 1))
                local err=$(echo "$update_response" | jq -r '.message // "Unknown error"' 2>/dev/null)
                echo -e "   ${RED} Failed: $err${NC}"
            fi
        else
            skipped=$((skipped + 1))
            echo -e "   ${DIM}⏭  No change needed${NC}"
        fi

    done < <(echo "$songs" | jq -c '.')

    rm -rf "$temp_dir"

    echo -e "\n${GREEN}${BOLD}${NC}"
    echo -e "${GREEN}${BOLD}   UPDATE COMPLETE${NC}"
    echo -e "${GREEN}${BOLD}${NC}"
    echo -e "${GREEN} Updated: $updated${NC}"
    echo -e "${RED} Failed: $failed${NC}"
    echo -e "${DIM}⏭  Skipped: $skipped${NC}"
    echo -e "${BLUE} Total processed: $count${NC}"

    echo
    read -p "Press Enter to continue..."
}

update_artists_local() {
    print_subheader " UPDATE ARTISTS FROM LOCAL FOLDER"

    if ! check_auth; then
        return 1
    fi

    if ! command -v ffmpeg &> /dev/null; then
        print_error "ffmpeg is required for this feature"
        echo -e "${YELLOW} Install with: sudo pacman -S ffmpeg${NC}"
        read -p "Press Enter to continue..."
        return 1
    fi

    echo -ne "${BOLD}${WHITE} Enter folder path containing audio files: ${NC}"
    read -r folder_path

    if [ ! -d "$folder_path" ]; then
        print_error "Folder not found"
        read -p "Press Enter to continue..."
        return 1
    fi

    local token=$(get_token)
    
    print_progress "Fetching songs from server..."

    local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs?limit=200" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}")

    if ! validate_json_response "$response"; then
        print_error "Failed to fetch songs"
        return 1
    fi

    local songs=$(echo "$response" | jq -r '.data[] | select(.artist == "Unknown Artist" or .artist == "")')
    local count=$(echo "$songs" | jq -s 'length')

    if [ "$count" -eq 0 ]; then
        print_success "No songs need artist update!"
        echo
        read -p "Press Enter to continue..."
        return 0
    fi

    echo -e "\n${YELLOW} Found ${count} songs with 'Unknown Artist' on server${NC}"
    echo -e "${BLUE} Searching in: ${WHITE}$folder_path${NC}"
    echo -e "${BLUE} Scanning local files...${NC}\n"

    local temp_file_list="/tmp/nosta_local_files.txt"
    find "$folder_path" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.flac" -o -iname "*.m4a" -o -iname "*.aac" -o -iname "*.wma" \) > "$temp_file_list"

    local total_files=$(wc -l < "$temp_file_list")
    echo -e "${GREEN} Found ${total_files} audio files locally${NC}\n"

    local updated=0
    local failed=0
    local skipped=0
    local not_found=0

    local total=$count
    local current=0

    while IFS= read -r song; do
        current=$((current + 1))
        local id=$(echo "$song" | jq -r '.id')
        local title=$(echo "$song" | jq -r '.title')
        local current_artist=$(echo "$song" | jq -r '.artist')
        local isPublic=$(echo "$song" | jq -r '.isPublic')
        local new_artist=""
        local found_file=""

        echo -e "\n${CYAN}[${current}/${total}]${NC} ${DIM}$id${NC} → \"${WHITE}$title${NC}\""

        local search_title=$(echo "$title" | sed 's/^[0-9]*\.\s*//' | sed 's/\s\+/ /g' | sed 's/^\s*//;s/\s*$//')
        
        found_file=$(grep -i -F "$search_title" "$temp_file_list" | head -1)
        
        if [ -z "$found_file" ]; then
            local short_title=$(echo "$search_title" | cut -c1-20)
            found_file=$(grep -i -F "$short_title" "$temp_file_list" | head -1)
        fi

        if [ -z "$found_file" ]; then
            local clean_title=$(echo "$search_title" | sed 's/\(slowed\|reverb\|remix\|sped\|up\|instrumental\|version\)//gi' | sed 's/\s\+/ /g')
            found_file=$(grep -i -F "$clean_title" "$temp_file_list" | head -1)
        fi

        if [ -z "$found_file" ]; then
            echo -e "   ${RED} File not found locally${NC}"
            not_found=$((not_found + 1))
            continue
        fi

        echo -e "   ${DIM} Found: $(basename "$found_file")${NC}"

        new_artist=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$found_file" 2>/dev/null)
        
        if [ -z "$new_artist" ]; then
            if [[ "$title" =~ ^[[:space:]]*([^-–]+)[-–][[:space:]]*(.+)$ ]]; then
                new_artist=$(echo "$title" | sed -E 's/^[[:space:]]*([^-–]+)[-–].*$/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            else
                new_artist="Unknown Artist"
            fi
        fi

        new_artist=$(echo "$new_artist" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 100)
        if [ -z "$new_artist" ] || [ "$new_artist" = "$title" ]; then
            new_artist="Unknown Artist"
        fi

        echo -e "   ${YELLOW}Artist:${NC} \"$current_artist\" → \"${GREEN}$new_artist${NC}\""

        if [ "$new_artist" != "$current_artist" ] && [ "$new_artist" != "Unknown Artist" ]; then
            local update_data=$(jq -n \
                --arg title "$title" \
                --arg artist "$new_artist" \
                --argjson isPublic "$isPublic" \
                '{title: $title, artist: $artist, isPublic: $isPublic}')

            local update_response=$(curl -s -X PUT "${API_BASE}${API_VERSION}/songs/${id}" \
                -H "Authorization: Bearer ${token}" \
                -H "X-App-Secret: ${APP_SECRET}" \
                -H "Content-Type: application/json" \
                -d "$update_data")

            if echo "$update_response" | jq -e '.id' >/dev/null 2>&1; then
                updated=$((updated + 1))
                echo -e "   ${GREEN} Updated${NC}"
            else
                failed=$((failed + 1))
                local err=$(echo "$update_response" | jq -r '.message // "Unknown error"' 2>/dev/null)
                echo -e "   ${RED} Failed: $err${NC}"
            fi
        else
            skipped=$((skipped + 1))
            echo -e "   ${DIM}⏭  No change needed${NC}"
        fi

    done < <(echo "$songs" | jq -c '.')

    rm -f "$temp_file_list"

    echo -e "\n${GREEN}${BOLD}${NC}"
    echo -e "${GREEN}${BOLD}   UPDATE COMPLETE${NC}"
    echo -e "${GREEN}${BOLD}${NC}"
    echo -e "${GREEN} Updated: $updated${NC}"
    echo -e "${RED} Failed: $failed${NC}"
    echo -e "${DIM}⏭  Skipped: $skipped${NC}"
    echo -e "${YELLOW} Not found locally: $not_found${NC}"
    echo -e "${BLUE} Total processed: $count${NC}"

    echo
    read -p "Press Enter to continue..."
}

edit_song() {
    print_subheader " EDIT SONG"

    if ! check_auth; then
        return 1
    fi

    echo -ne "${BOLD}${WHITE} Enter song ID to edit: ${NC}"
    read -r song_id

    if [ -z "$song_id" ]; then
        print_error "Song ID required"
        return 1
    fi

    if ! is_valid_id "$song_id"; then
        print_error "Invalid song ID format"
        return 1
    fi

    local token=$(get_token)

    local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs/${song_id}" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}")

    if ! validate_json_response "$response"; then
        print_error "Song not found or invalid response"
        return 1
    fi

    if [ "$(echo "$response" | jq -r '.id' 2>/dev/null)" = "null" ]; then
        print_error "Song not found"
        return 1
    fi

    local old_title=$(echo "$response" | jq -r '.title // ""' 2>/dev/null)
    local old_artist=$(echo "$response" | jq -r '.artist // ""' 2>/dev/null)
    local old_public=$(echo "$response" | jq -r '.isPublic // "false"' 2>/dev/null)
    local old_file_url=$(echo "$response" | jq -r '.fileUrl // ""' 2>/dev/null)
    local old_cover_url=$(echo "$response" | jq -r '.coverArtUrl // ""' 2>/dev/null)

    echo -e "\n${CYAN}Current Song Info:${NC}"
    echo -e "  Title: ${WHITE}$old_title${NC}"
    echo -e "  Artist: ${WHITE}$old_artist${NC}"
    echo -e "  Public: ${WHITE}$old_public${NC}"
    echo -e "  File URL: ${DIM}${old_file_url:0:50}...${NC}"

    echo -e "\n${YELLOW}Choose edit option:${NC}"
    echo -e "${GREEN}  1)${NC} Replace with new audio file (keeps same ID)"
    echo -e "${GREEN}  2)${NC} Edit metadata only (title, artist, public)"
    echo -ne "${BOLD}${CYAN} Enter choice: ${NC}"
    read -r edit_choice

    case $edit_choice in
        1)
            echo -e "\n${BLUE} Select new audio file:${NC}"
            echo -ne "${BOLD}${WHITE} File path: ${NC}"
            read -r new_file

            if [ ! -f "$new_file" ]; then
                print_error "File not found"
                return 1
            fi

            echo -e "\n${BLUE} Extracting metadata from new file...${NC}"
            local metadata=$(extract_metadata "$new_file")
            local auto_title=$(echo "$metadata" | cut -d'|' -f1)
            local auto_artist=$(echo "$metadata" | cut -d'|' -f2)
            local cover_file=$(echo "$metadata" | cut -d'|' -f3)

            echo -e "${GREEN} Detected Title: ${WHITE}$auto_title${NC}"
            echo -e "${GREEN} Detected Artist: ${WHITE}$auto_artist${NC}"

            echo -ne "${BOLD}${WHITE} Title (press Enter to keep detected): ${NC}"
            read -r new_title
            [ -z "$new_title" ] && new_title="$auto_title"

            echo -ne "${BOLD}${WHITE} Artist (press Enter to keep detected): ${NC}"
            read -r new_artist
            [ -z "$new_artist" ] && new_artist="$auto_artist"

            echo -ne "${BOLD}${WHITE} Make public? (y/n, press Enter to keep current: $old_public): ${NC}"
            read -r is_public_input
            if [ -n "$is_public_input" ]; then
                [[ "$is_public_input" =~ ^[Yy]$ ]] && new_public="true" || new_public="false"
            else
                new_public="$old_public"
            fi

            echo -e "\n${RED} Deleting old song...${NC}"
            local delete_response=$(curl -s -X DELETE "${API_BASE}${API_VERSION}/songs/${song_id}" \
                -H "Authorization: Bearer ${token}" \
                -H "X-App-Secret: ${APP_SECRET}" \
                -w "\n%{http_code}")

            local http_code=$(echo "$delete_response" | tail -n1)

            if [ "$http_code" != "204" ] && [ "$http_code" != "200" ]; then
                print_error "Failed to delete old song (HTTP $http_code)"
                return 1
            fi

            print_success "Old song deleted"

            echo -e "\n${CYAN}⏳ Uploading new file...${NC}"

            local curl_args=(-s -X POST "${API_BASE}${API_VERSION}/songs/upload")
            curl_args+=(-H "Authorization: Bearer ${token}")
            curl_args+=(-H "X-App-Secret: ${APP_SECRET}")
            curl_args+=(-F "audio=@$new_file")
            curl_args+=(-F "title=$new_title")
            curl_args+=(-F "artist=$new_artist")
            curl_args+=(-F "isPublic=$new_public")

            if [ -n "$cover_file" ] && [ -f "$cover_file" ]; then
                curl_args+=(-F "cover=@$cover_file")
            fi

            local upload_response=$(curl "${curl_args[@]}" 2>&1)

            if [ -n "$cover_file" ] && [ -f "$cover_file" ]; then
                rm -f "$cover_file"
            fi

            if echo "$upload_response" | jq -e '.id' >/dev/null 2>&1; then
                local new_id=$(echo "$upload_response" | jq -r '.id')
                print_success "Song replaced successfully!"
                echo -e "${BLUE} New song ID: ${WHITE}$new_id${NC}"
                echo -e "${YELLOW}  Note: The ID has changed. The old ID is no longer valid.${NC}"
            else
                print_error "Upload failed"
                echo "$upload_response" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "$upload_response"
            fi
            ;;

        2)
            echo -e "\n${BLUE}Enter new values (leave empty to keep current):${NC}"

            echo -ne "${BOLD}${WHITE} Title (current: $old_title): ${NC}"
            read -r new_title
            [ -z "$new_title" ] && new_title="$old_title"

            echo -ne "${BOLD}${WHITE} Artist (current: $old_artist): ${NC}"
            read -r new_artist
            [ -z "$new_artist" ] && new_artist="$old_artist"

            echo -ne "${BOLD}${WHITE} Make public? (y/n, current: $old_public): ${NC}"
            read -r is_public_input
            if [ -n "$is_public_input" ]; then
                [[ "$is_public_input" =~ ^[Yy]$ ]] && new_public="true" || new_public="false"
            else
                new_public="$old_public"
            fi

            local update_data=$(jq -n \
                --arg title "$new_title" \
                --arg artist "$new_artist" \
                --argjson isPublic "$new_public" \
                '{title: $title, artist: $artist, isPublic: $isPublic}')

            local update_response=$(curl -s -X PUT "${API_BASE}${API_VERSION}/songs/${song_id}" \
                -H "Authorization: Bearer ${token}" \
                -H "X-App-Secret: ${APP_SECRET}" \
                -H "Content-Type: application/json" \
                -d "$update_data")

            if ! validate_json_response "$update_response"; then
                print_error "Update failed - invalid response"
                echo "$update_response" | head -c 200
            elif [ "$(echo "$update_response" | jq -r '.id' 2>/dev/null)" != "null" ]; then
                print_success "Song updated successfully!"
                echo -e "${BLUE} Song ID: ${WHITE}$song_id${NC}"
                echo -e "${GREEN}Title: ${WHITE}$new_title${NC}"
                echo -e "${GREEN}Artist: ${WHITE}$new_artist${NC}"
            else
                print_error "Update failed"
                echo "$update_response" | jq -r '.message // "Unknown error"' 2>/dev/null
            fi
            ;;

        *)
            print_error "Invalid choice"
            ;;
    esac

    echo
    read -p "Press Enter to continue..."
}

delete_song() {
    print_subheader " DELETE SONG"

    if ! check_auth; then
        return 1
    fi

    echo -ne "${BOLD}${WHITE} Enter song ID: ${NC}"
    read -r song_id

    if [ -z "$song_id" ]; then
        print_error "Song ID required"
        return 1
    fi

    if ! is_valid_id "$song_id"; then
        print_error "Invalid song ID format"
        return 1
    fi

    echo -e "${RED}  Delete song: ${BOLD}$song_id${NC}${RED}?${NC}"
    echo -ne "${BOLD}${YELLOW}Type 'YES' to confirm: ${NC}"
    read -r confirm

    if [ "$confirm" != "YES" ]; then
        print_warning "Cancelled"
        return 0
    fi

    local token=$(get_token)

    local response=$(curl -s -X DELETE "${API_BASE}${API_VERSION}/songs/${song_id}" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}" \
        -w "\n%{http_code}")

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        print_success "Song deleted!"
    else
        print_error "Failed to delete (HTTP $http_code)"
    fi

    echo
    read -p "Press Enter to continue..."
}

delete_multiple_songs() {
    print_subheader " DELETE MULTIPLE SONGS"

    if ! check_auth; then
        return 1
    fi

    echo -e "${BLUE}Enter song IDs (space-separated) or 'all'${NC}"
    echo -ne "${BOLD}${WHITE} Song IDs: ${NC}"
    read -r song_ids_input

    if [ -z "$song_ids_input" ]; then
        print_error "No IDs provided"
        return 1
    fi

    if [ "$song_ids_input" = "all" ]; then
        echo -e "${RED}${BOLD}  DELETE ALL SONGS!${NC}"
        echo -ne "${BOLD}${YELLOW}Type 'DELETE ALL': ${NC}"
        read -r confirm
        if [ "$confirm" != "DELETE ALL" ]; then
            print_warning "Cancelled"
            return 0
        fi

        local token=$(get_token)
        local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs?limit=1000" \
            -H "Authorization: Bearer ${token}" \
            -H "X-App-Secret: ${APP_SECRET}")

        if ! validate_json_response "$response"; then
            print_error "Failed to fetch songs"
            return 1
        fi

        song_ids_input=$(echo "$response" | jq -r '.data[].id' 2>/dev/null | tr '\n' ' ')
        if [ -z "$song_ids_input" ]; then
            print_error "No songs found"
            return 1
        fi
    fi

    read -ra song_ids <<< "$song_ids_input"
    local total=${#song_ids[@]}

    echo -e "${RED}  Delete ${total} song(s)?${NC}"
    echo -ne "${BOLD}${YELLOW}Type 'YES': ${NC}"
    read -r confirm

    if [ "$confirm" != "YES" ]; then
        print_warning "Cancelled"
        return 0
    fi

    local token=$(get_token)
    local success=0
    local failed=0

    for song_id in "${song_ids[@]}"; do
        if ! is_valid_id "$song_id"; then
            echo -e "${RED} Invalid ID: $song_id${NC}"
            failed=$((failed + 1))
            continue
        fi

        local response=$(curl -s -X DELETE "${API_BASE}${API_VERSION}/songs/${song_id}" \
            -H "Authorization: Bearer ${token}" \
            -H "X-App-Secret: ${APP_SECRET}" \
            -w "\n%{http_code}")

        local http_code=$(echo "$response" | tail -n1)

        if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
            success=$((success + 1))
            echo -e "${GREEN} Deleted: $song_id${NC}"
        else
            failed=$((failed + 1))
            echo -e "${RED} Failed: $song_id${NC}"
        fi
    done

    echo -e "\n${GREEN} Success: $success${NC}"
    echo -e "${RED} Failed: $failed${NC}"
    echo
    read -p "Press Enter to continue..."
}

view_favorites() {
    print_subheader " FAVORITE SONGS"

    if ! check_auth; then
        return 1
    fi

    local token=$(get_token)

    local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs/favorites" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}")

    if ! validate_json_response "$response"; then
        print_error "Invalid response from server"
        read -p "Press Enter to continue..."
        return 1
    fi

    local songs=$(echo "$response" | jq -r '.data // []')
    local total=$(echo "$response" | jq -r '.total // 0' 2>/dev/null)

    echo -e "\n${GREEN} Favorite Songs: ${total}${NC}\n"

    if [ "$total" -eq 0 ]; then
        print_warning "No favorites yet"
        echo
        read -p "Press Enter to continue..."
        return 0
    fi

    local count=$(echo "$songs" | jq '. | length' 2>/dev/null || echo "0")

    echo -e "${CYAN}${BOLD}${NC}"
    echo -e "${CYAN}${BOLD}${NC} ${WHITE}${BOLD}#  TITLE                    ARTIST        DURATION${NC} ${CYAN}${BOLD}${NC}"
    echo -e "${CYAN}${BOLD}${NC}"

    for ((i=0; i<count; i++)); do
        local song=$(echo "$songs" | jq -r ".[$i]")
        local title=$(echo "$song" | jq -r '.title // "Untitled"' | cut -c1-24)
        local artist=$(echo "$song" | jq -r '.artist // "Unknown"' | cut -c1-14)
        local duration=$(echo "$song" | jq -r '.duration // 0')

        local duration_str="--:--"
        if [ "$duration" -gt 0 ]; then
            duration_str=$(printf "%02d:%02d" $((duration/60)) $((duration%60)))
        fi

        local num=$((i + 1))
        printf "${CYAN}${NC} ${WHITE}%2d${NC}  ${GREEN}%-24s${NC} ${YELLOW}%-14s${NC} ${MAGENTA}%5s${NC} ${CYAN}${NC}\n" \
            "$num" "$title" "$artist" "$duration_str"
    done

    echo -e "${CYAN}${BOLD}${NC}"

    echo -e "\n${YELLOW}Options:${NC}"
    echo -e "${GREEN}  p)${NC}   Play song"
    echo -e "${GREEN}  Enter)${NC} Back to menu"
    echo -ne "${BOLD}${CYAN} Choice: ${NC}"
    read -r action

    case "$action" in
        [Pp])
            echo -ne "${BOLD}${WHITE} Enter song number: ${NC}"
            read -r song_num
            
            if ! is_number "$song_num"; then
                print_error "Invalid number"
            elif [ "$song_num" -ge 1 ] && [ "$song_num" -le "$count" ]; then
                local idx=$((song_num - 1))
                local song=$(echo "$songs" | jq -r ".[$idx]")
                local sid=$(echo "$song" | jq -r '.id')
                local stitle=$(echo "$song" | jq -r '.title')
                local sartist=$(echo "$song" | jq -r '.artist')
                play_song "$sid" "$stitle" "$sartist"
            else
                print_error "Number out of range (1-$count)"
            fi
            ;;
    esac

    echo
    read -p "Press Enter to continue..."
}

show_stats() {
    print_subheader " STATISTICS"

    if ! check_auth; then
        return 1
    fi

    local token=$(get_token)

    local response=$(curl -s -X GET "${API_BASE}${API_VERSION}/songs?limit=1" \
        -H "Authorization: Bearer ${token}" \
        -H "X-App-Secret: ${APP_SECRET}")

    if ! validate_json_response "$response"; then
        print_error "Invalid response from server"
        read -p "Press Enter to continue..."
        return 1
    fi

    local total=$(echo "$response" | jq -r '.pagination.totalItems // 0' 2>/dev/null)
    local total_pages=$(echo "$response" | jq -r '.pagination.totalPages // 1' 2>/dev/null)

    local user=$(get_user_info)
    local username=$(echo "$user" | jq -r '.username // "Unknown"' 2>/dev/null)
    local role=$(echo "$user" | jq -r '.role // "Normal"' 2>/dev/null)
    local is_vip=$(echo "$user" | jq -r '.isVIP // false' 2>/dev/null)

    echo -e "\n${CYAN}${BOLD}${NC}"
    echo -e "${CYAN}${BOLD}   SYSTEM STATISTICS${NC}"
    echo -e "${CYAN}${BOLD}${NC}"
    echo -e "${WHITE}${BOLD}Total Songs:${NC} ${GREEN}${BOLD}$total${NC}"
    echo -e "${WHITE}${BOLD}Total Pages:${NC} ${BLUE}$total_pages${NC}"
    echo -e "\n${WHITE}${BOLD}User Info:${NC}"
    echo -e "  Username: ${GREEN}$username${NC}"
    echo -e "  Role: ${YELLOW}$role${NC}"
    [ "$is_vip" = "true" ] && echo -e "  ${GREEN} VIP User${NC}"
    echo -e "\n${CYAN}${BOLD}${NC}"
    echo
    read -p "Press Enter to continue..."
}

show_logo() {
    echo -e "${CYAN}"
    echo "  NOSTA MUSIC MANAGER"
    echo -e "${NC}"
}

main_menu() {
    while true; do
        clear
        show_logo

        if [ -f "$USER_FILE" ] && [ -s "$USER_FILE" ]; then
            local user=$(get_user_info)
            local username=$(echo "$user" | jq -r '.username // "Guest"' 2>/dev/null)
            local role=$(echo "$user" | jq -r '.role // "Normal"' 2>/dev/null)

            echo -e "${GREEN} Logged in as: ${WHITE}${BOLD}$username${NC} ${YELLOW}[$role]${NC}"
            if [ -n "$CURRENT_SONG" ]; then
                echo -e "${MAGENTA}  $CURRENT_SONG${NC}"
            fi
        else
            echo -e "${YELLOW} Not logged in${NC}"
        fi

        print_menu
        read -r choice

        case $choice in
            1) list_songs ;;
            2) search_songs ;;
            3) upload_song ;;
            4) edit_song ;;
            5) delete_song ;;
            6) delete_multiple_songs ;;
            7) view_favorites ;;
            8)
                clear
                display_user_info
                read -p "Press Enter to continue..."
                ;;
            9) show_stats ;;
            10) show_now_playing ;;
            11) update_artists ;;
            12) update_artists_local ;;
            0)
                stop_song
                logout
                echo -e "${GREEN} Goodbye!${NC}"
                exit 0
                ;;
            *) print_error "Invalid choice" ;;
        esac
    done
}

main() {
    init

    if [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
        echo -e "${GREEN} Already logged in${NC}"
        sleep 1
    else
        echo -e "${YELLOW}  No active session${NC}"
        echo -ne "${BLUE} Login now? (y/n): ${NC}"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            clear
            login
        fi
    fi

    main_menu
}

main "$@"