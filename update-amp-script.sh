#!/bin/bash

# Filename: update-amp-script.sh
# Notes: Don't forget to chmod +x ./update-amp-script.sh
# This script automates updates for Amp panel users and select plugins.

# --- Author & Credits ---
#
# Created by Loren Tedford
# Website: https://lorentedford.com
#
# This script was originally developed for the Ltcraft.net Minecraft Network.
# Join the server at: mc.Ltcraft.net
#
# Collaboratively developed with Google Gemini.
#
# -------------------------------------------------------------------------

# --- Prerequisites & Setup ---
#
# Before running this script, ensure your system has all the necessary tools.
# This script is designed for Debian/Ubuntu-based systems.
#
# 1. Update your package list:
#    sudo apt-get update
#
# 2. Install required packages:
#    sudo apt-get install -y default-jdk curl wget jq unzip procps
#
# 3. Ensure AMP is installed:
#    This script relies on 'ampinstmgr'. Please make sure AMP is installed
#    correctly by following the official guide at https://cubecoders.com/AMPInstall
#
# 4. Make the script executable:
#    chmod +x ./update-amp-script.sh
#
# -------------------------------------------------------------------------

# --- Automatic Plugin Update Control ---
#
# This script automatically updates the following plugins. You can control which ones are updated below.
#
# Disabled Plugin Handling:
# If you rename a plugin from ".jar" to ".jar.disabled" on a server to temporarily disable it,
# this script will respect that. When it updates the plugin, it will download the new version
# and automatically save it as ".jar.disabled", keeping it disabled for you.
#
# To DISABLE updates for EssentialsX, GriefPrevention, or your Premium Plugins,
# simply change their setting from "true" to "false".
#
UPDATE_ESSENTIALSX="true"
UPDATE_GRIEFPREVENTION="true"
UPDATE_PREMIUM_PLUGINS="true"

# To DISABLE updates for an individual plugin in the list below (WorldEdit, WorldGuard, etc.),
# add a '#' at the beginning of its line in BOTH the MODRINTH_PLUGINS and MODRINTH_GLOBS lists.
#
MODRINTH_PLUGINS=(
    "worldedit"
    "worldguard"
    "viaversion"
    "viabackwards"
)
MODRINTH_GLOBS=(
    "WorldEdit*.jar"
    "WorldGuard*.jar"
    "ViaVersion*.jar"
    "ViaBackwards*.jar"
)
#
# -------------------------------------------------------------------------


# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipelines fail if any command fails, not just the last one.
set -o pipefail
# Ensure globs that don't match expand to nothing, not the glob itself.
shopt -s nullglob
# Make all file searching (globbing) case-insensitive.
shopt -s nocaseglob


# --- Configuration Variables ---
SPIGOT_VERSION="1.21.8"      # Desired Spigot/Minecraft version
GEYSERMC_VERSION="latest"    # Desired GeyserMC version
FLOODGATE_VERSION="latest"   # Desired Floodgate version

# --- Server Configuration ---
AMP_INSTANCES_ARRAY=("creative01" "Lobby01" "Ltcraft01" "mark01" "survival01" "factionspvp01" "Bungeecord01")
BUNGEE_INSTANCE_NAME="Bungeecord01"
SPIGOT_SERVERS_ARRAY=("creative01" "Lobby01" "Ltcraft01" "mark01" "survival01" "factionspvp01")
ESSENTIALS_SERVERS_ARRAY=("creative01" "Lobby01" "Ltcraft01" "mark01" "survival01" "factionspvp01")
GRIEFPREVENTION_SERVERS_ARRAY=("Ltcraft01")

# --- System Paths ---
MINECRAFT_HOME="/home/amp/Minecraft"
BUILDTOOLS_DIR="${MINECRAFT_HOME}"
PLUGIN_DOWNLOAD_DIR="${MINECRAFT_HOME}/PluginUpdates"
PREMIUM_PLUGIN_DIR="${MINECRAFT_HOME}/PremiumPlugins" # Your upload folder for premium plugins
BUNGEE_DOWNLOAD_DIR="${MINECRAFT_HOME}/BungeeCord"
GEYSER_DOWNLOAD_DIR="${MINECRAFT_HOME}/GeyserMC"
AMP_DATA_DIR="/home/amp/.ampdata"
AMP_INSTANCES_DIR="${AMP_DATA_DIR}/instances"

# --- Helper Functions ---

log_message() {
  echo "[INFO] $1" >&2
}

log_error() {
  echo "[ERROR] $1" >&2
}

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "CRITICAL: Required command '$1' is not installed. Please install it. Exiting."
    exit 1
  fi
  log_message "Command '$1' found."
}

download_file() {
  local url="$1"
  local output_file="$2"
  local is_critical_str="${3:-true}"
  local is_critical=false
  if [ "$is_critical_str" = "true" ]; then is_critical=true; fi

  mkdir -p "$(dirname "$output_file")"
  
  if command -v curl >/dev/null 2>&1; then
    curl -f -L -s -o "$output_file" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --fail "$url" -O "$output_file"
  else
    log_error "CRITICAL: Neither curl nor wget is available. Cannot download files. Exiting."
    exit 1
  fi

  if [ $? -ne 0 ]; then
    if $is_critical; then
      log_error "CRITICAL: Download failed for URL: $url. Exiting."
      exit 1
    else
      log_message "Warning: Failed to download optional file from $url. Skipping."
      rm -f "$output_file"
      return 1
    fi
  else
    log_message "Successfully downloaded: $(basename "$output_file")"
    return 0
  fi
}

# --- Plugin Update Functions ---

get_modrinth_download_info() {
    local project_slug="$1"
    local mc_version="$2"
    local loaders="%5B%22spigot%22,%22paper%22,%22purpur%22%5D"
    local game_versions="%5B%22${mc_version}%22%5D"
    local api_url="https://api.modrinth.com/v2/project/${project_slug}/version?loaders=${loaders}&game_versions=${game_versions}"

    log_message "Querying Modrinth for latest '$project_slug' compatible with MC $mc_version..."
    
    local response
    response=$(curl -s -f -L "$api_url")
    if [ $? -ne 0 ] || [ -z "$response" ] || [ "$response" = "[]" ]; then
        log_error "Warning: Could not find a compatible version of '$project_slug' for MC $mc_version on Modrinth. Skipping."
        echo ""
        return
    fi

    local download_url filename
    download_url=$(echo "$response" | jq -r '.[0].files[0].url')
    filename=$(echo "$response" | jq -r '.[0].files[0].filename')

    if [ -z "$download_url" ] || [ -z "$filename" ] || [ "$download_url" = "null" ] || [ "$filename" = "null" ]; then
        log_error "Warning: Could not parse download info for '$project_slug'. Skipping."
        echo ""
    else
        echo "${download_url}|${filename}"
    fi
}

update_plugin_on_instances() {
    local old_jar_glob="$1"
    local new_jar_path="$2"
    local -n instances_to_check=$3

    if [ ! -f "$new_jar_path" ]; then
        log_message "Skipping update for '$(basename "$new_jar_path")' as it was not downloaded."
        return
    fi

    log_message "Searching for and updating '$old_jar_glob' on specified instances (respecting .disabled files)..."
    for instance_name in "${instances_to_check[@]}"; do
        local instance_plugin_dir="${AMP_INSTANCES_DIR}/${instance_name}/Minecraft/plugins"
        if [ ! -d "$instance_plugin_dir" ]; then continue; fi

        local disabled_glob="${old_jar_glob}.disabled"
        local disabled_jars=("$instance_plugin_dir"/$disabled_glob)
        local enabled_jars=("$instance_plugin_dir"/$old_jar_glob)
        local new_filename
        new_filename=$(basename "$new_jar_path")

        if [ ${#disabled_jars[@]} -gt 0 ] && [ -e "${disabled_jars[0]}" ]; then
            log_message "  -> Found DISABLED plugin on '$instance_name'. Updating and keeping it disabled."
            rm -f "${disabled_jars[@]}"
            cp "$new_jar_path" "${instance_plugin_dir}/${new_filename}.disabled"
        
        elif [ ${#enabled_jars[@]} -gt 0 ] && [ -e "${enabled_jars[0]}" ]; then
            log_message "  -> Found ENABLED plugin on '$instance_name'. Updating."
            rm -f "${enabled_jars[@]}"
            cp "$new_jar_path" "${instance_plugin_dir}/${new_filename}"
        fi
    done
}

# --- Main Script Logic ---

log_message "--- Starting AMP & Plugin Update Script ---"
check_command "java"; check_command "curl"; check_command "wget"; check_command "ampinstmgr"; check_command "jq"; check_command "find"; check_command "pkill"; check_command "unzip"

log_message "--- Cleaning up old files and directories ---"
rm -rf "${BUILDTOOLS_DIR}/BuildData" "${BUILDTOOLS_DIR}/Bukkit" "${BUILDTOOLS_DIR}/CraftBukkit" "${BUILDTOOLS_DIR}/apache-maven-3.6.0" "${BUILDTOOLS_DIR}/spigot" "${BUILDTOOLS_DIR}/work"
rm -f  "${BUILDTOOLS_DIR}/BuildTools.log.txt"
rm -rf "${BUNGEE_DOWNLOAD_DIR:?}/"*
rm -rf "${GEYSER_DOWNLOAD_DIR:?}/"*
rm -rf "${PLUGIN_DOWNLOAD_DIR:?}/"*
mkdir -p "$PLUGIN_DOWNLOAD_DIR"
mkdir -p "$PREMIUM_PLUGIN_DIR"

log_message "--- Stopping all AMP instances before updates ---"
ampinstmgr --StopAllInstances
log_message "Waiting 30 seconds for instances to stop gracefully..."
sleep 30

log_message "Forcefully terminating any remaining Java processes owned by user 'amp'..."
pkill -u amp java || true
log_message "Force kill command sent."

log_message "Cleaning up any stale session.lock files..."
for instance_name in "${SPIGOT_SERVERS_ARRAY[@]}"; do
    lock_file="${AMP_INSTANCES_DIR}/${instance_name}/Minecraft/world/session.lock"
    if [ -f "$lock_file" ]; then
        log_message "  -> Found and removed stale lock file for '$instance_name'."
        rm -f "$lock_file"
    fi
done

log_message "--- Updating Spigot ---"
SPIGOT_JAR_NAME="spigot-${SPIGOT_VERSION}.jar"
SPIGOT_JAR_PATH="${BUILDTOOLS_DIR}/${SPIGOT_JAR_NAME}"
log_message "Checking for existing Spigot build for version $SPIGOT_VERSION..."
if [ -f "$SPIGOT_JAR_PATH" ] && [ -n "$(find "$SPIGOT_JAR_PATH" -mmin -60)" ]; then
    log_message "✅ Recent Spigot JAR found. Skipping build."
else
    log_message "Spigot JAR is missing or outdated. Proceeding with build..."
    if [ ! -f "${BUILDTOOLS_DIR}/BuildTools.jar" ]; then
        download_file "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" "${BUILDTOOLS_DIR}/BuildTools.jar"
    fi
    log_message "Building Spigot version $SPIGOT_VERSION... This may take a while."
    cd "$BUILDTOOLS_DIR"
    java -jar BuildTools.jar --rev "$SPIGOT_VERSION"
fi
if [ -f "$SPIGOT_JAR_PATH" ]; then
  log_message "Copying Spigot JAR to backend instances..."
  for instance in "${SPIGOT_SERVERS_ARRAY[@]}"; do
    cp -f "$SPIGOT_JAR_PATH" "${AMP_INSTANCES_DIR}/${instance}/Minecraft/${SPIGOT_JAR_NAME}"
  done
else
  log_error "CRITICAL: Spigot JAR $SPIGOT_JAR_PATH not found. Exiting."; exit 1
fi

log_message "--- Updating BungeeCord ---"
LATEST_BUILD_NUM_URL="https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/buildNumber"
LATEST_BUILD_NUM_FILE="${BUNGEE_DOWNLOAD_DIR}/latest_build.txt"
if download_file "$LATEST_BUILD_NUM_URL" "$LATEST_BUILD_NUM_FILE"; then
    BUNGEECORD_TARGET_BUILD=$(<"$LATEST_BUILD_NUM_FILE")
    BUNGEECORD_CORE_URL="https://ci.md-5.net/job/BungeeCord/${BUNGEECORD_TARGET_BUILD}/artifact/bootstrap/target/BungeeCord.jar"
    BUNGEECORD_CORE_JAR_PATH="${BUNGEE_DOWNLOAD_DIR}/BungeeCord.jar"
    log_message "Downloading main BungeeCord.jar (modules are included)..."
    if download_file "$BUNGEECORD_CORE_URL" "$BUNGEECORD_CORE_JAR_PATH"; then
        cp -f "$BUNGEECORD_CORE_JAR_PATH" "${AMP_INSTANCES_DIR}/${BUNGEE_INSTANCE_NAME}/Minecraft/BungeeCord.jar"
    fi
else
    log_error "Warning: Could not determine latest BungeeCord build number. Skipping update."
fi

log_message "--- Updating Plugins ---"
MAJOR_MC_VERSION=$(echo "$SPIGOT_VERSION" | cut -d'.' -f1-2)

# Update standard plugins from Modrinth
log_message "Updating general Spigot plugins from Modrinth..."
for i in "${!MODRINTH_PLUGINS[@]}"; do
    slug="${MODRINTH_PLUGINS[i]}"; glob="${MODRINTH_GLOBS[i]}"
    download_info=$(get_modrinth_download_info "$slug" "$MAJOR_MC_VERSION")
    if [[ "$download_info" == *"|"* ]]; then
        url=$(echo "$download_info" | cut -d'|' -f1); filename=$(echo "$download_info" | cut -d'|' -f2)
        if download_file "$url" "${PLUGIN_DOWNLOAD_DIR}/${filename}"; then
            update_plugin_on_instances "$glob" "${PLUGIN_DOWNLOAD_DIR}/${filename}" SPIGOT_SERVERS_ARRAY
        fi
    fi
done

# Update EssentialsX suite if enabled
if [ "$UPDATE_ESSENTIALSX" = "true" ]; then
    log_message "Updating EssentialsX suite from official GitHub Releases..."
    ESS_API_URL="https://api.github.com/repos/EssentialsX/Essentials/releases/latest"
    ess_response=$(curl -s -f -L "$ESS_API_URL") || { log_error "Warning: Could not connect to GitHub API for EssentialsX. Skipping."; }
    if [ -n "$ess_response" ]; then
        assets_info=$(echo "$ess_response" | jq -r '.assets[] | select(.name | (endswith(".jar") and (contains("javadoc") | not) and (contains("sources") | not))) | "\(.name)|\(.browser_download_url)"')
        if [ -z "$assets_info" ]; then
            log_error "Warning: Could not find any EssentialsX JARs in the latest GitHub release. Skipping."
        else
            new_ess_jars=()
            while IFS='|' read -r filename download_url; do
                if [ -z "$filename" ]; then continue; fi
                log_message "Downloading new EssentialsX asset: $filename"
                if download_file "$download_url" "${PLUGIN_DOWNLOAD_DIR}/${filename}" "false"; then
                    new_ess_jars+=("${PLUGIN_DOWNLOAD_DIR}/${filename}")
                fi
            done <<< "$assets_info"
            if [ ${#new_ess_jars[@]} -gt 0 ]; then
                log_message "Replacing EssentialsX suite on specified instances..."
                for instance_name in "${ESSENTIALS_SERVERS_ARRAY[@]}"; do
                    instance_plugin_dir="${AMP_INSTANCES_DIR}/${instance_name}/Minecraft/plugins"
                    if [ ! -d "$instance_plugin_dir" ]; then continue; fi
                    old_jars=("$instance_plugin_dir"/[Ee]ssentials[Xx]*.jar)
                    if [ ${#old_jars[@]} -gt 0 ] && [ -e "${old_jars[0]}" ]; then
                        log_message "  -> Found old EssentialsX files on '$instance_name'. Performing full replacement."
                        rm -f "$instance_plugin_dir"/[Ee]ssentials[Xx]*.jar
                        cp "${new_ess_jars[@]}" "$instance_plugin_dir/"
                    fi
                done
            fi
        fi
    fi
else
    log_message "Skipping EssentialsX update because it is disabled in the configuration."
fi

# Update GriefPrevention if enabled
if [ "$UPDATE_GRIEFPREVENTION" = "true" ]; then
    log_message "Updating GriefPrevention..."
    gp_slug="griefprevention"
    gp_glob="GriefPrevention*.jar"
    gp_download_info=$(get_modrinth_download_info "$gp_slug" "$MAJOR_MC_VERSION")
    if [[ "$gp_download_info" == *"|"* ]]; then
        url=$(echo "$gp_download_info" | cut -d'|' -f1); filename=$(echo "$gp_download_info" | cut -d'|' -f2)
        if download_file "$url" "${PLUGIN_DOWNLOAD_DIR}/${filename}"; then
            update_plugin_on_instances "$gp_glob" "${PLUGIN_DOWNLOAD_DIR}/${filename}" GRIEFPREVENTION_SERVERS_ARRAY
        fi
    fi
else
    log_message "Skipping GriefPrevention update because it is disabled in the configuration."
fi

# Update Premium Plugins if enabled
if [ "$UPDATE_PREMIUM_PLUGINS" = "true" ]; then
    log_message "--- Updating Premium Plugins from Local Folder ---"
    PREMIUM_ARCHIVE_DIR="${PREMIUM_PLUGIN_DIR}/archived"
    mkdir -p "$PREMIUM_ARCHIVE_DIR"

    premium_jars=("$PREMIUM_PLUGIN_DIR"/*.jar)
    if [ ${#premium_jars[@]} -gt 0 ] && [ -e "${premium_jars[0]}" ]; then
        log_message "Found new premium plugins to process..."
        for new_jar_path in "${premium_jars[@]}"; do
            log_message "Processing: $(basename "$new_jar_path")"
            plugin_name=$(unzip -p "$new_jar_path" plugin.yml 2>/dev/null | grep '^name:' | cut -d' ' -f2 | tr -d '\r')
            if [ -z "$plugin_name" ]; then
                log_error "  -> Could not determine plugin name from $(basename "$new_jar_path"). Skipping."
                continue
            fi
            log_message "  -> Detected plugin name: $plugin_name"
            old_jar_glob="${plugin_name}*.jar"
            update_plugin_on_instances "$old_jar_glob" "$new_jar_path" SPIGOT_SERVERS_ARRAY
            log_message "  -> Archiving processed premium plugin..."
            mv "$new_jar_path" "$PREMIUM_ARCHIVE_DIR/"
        done
    else
        log_message "No new premium plugins found in $PREMIUM_PLUGIN_DIR."
    fi
else
    log_message "Skipping premium plugins update because it is disabled in the configuration."
fi


# Geyser & Floodgate
log_message "--- Updating GeyserMC and Floodgate ---"
download_file "https://download.geysermc.org/v2/projects/geyser/versions/${GEYSERMC_VERSION}/builds/latest/downloads/bungeecord" "${GEYSER_DOWNLOAD_DIR}/Geyser-BungeeCord.jar"
download_file "https://download.geysermc.org/v2/projects/floodgate/versions/${FLOODGATE_VERSION}/builds/latest/downloads/bungee" "${GEYSER_DOWNLOAD_DIR}/floodgate-bungee.jar"
download_file "https://download.geysermc.org/v2/projects/floodgate/versions/${FLOODGATE_VERSION}/builds/latest/downloads/spigot" "${GEYSER_DOWNLOAD_DIR}/floodgate-spigot.jar"
cp -f "${GEYSER_DOWNLOAD_DIR}/Geyser-BungeeCord.jar" "${AMP_INSTANCES_DIR}/${BUNGEE_INSTANCE_NAME}/Minecraft/plugins/"
cp -f "${GEYSER_DOWNLOAD_DIR}/floodgate-bungee.jar" "${AMP_INSTANCES_DIR}/${BUNGEE_INSTANCE_NAME}/Minecraft/plugins/"
update_plugin_on_instances "floodgate-spigot*.jar" "${GEYSER_DOWNLOAD_DIR}/floodgate-spigot.jar" SPIGOT_SERVERS_ARRAY
FLOODGATE_KEY_PATH_ON_BUNGEE="${AMP_INSTANCES_DIR}/${BUNGEE_INSTANCE_NAME}/Minecraft/plugins/floodgate/key.pem"
if [ -f "$FLOODGATE_KEY_PATH_ON_BUNGEE" ]; then update_plugin_on_instances "key.pem" "$FLOODGATE_KEY_PATH_ON_BUNGEE" SPIGOT_SERVERS_ARRAY; fi

# Final AMP Steps
log_message "--- Finalizing Update ---"
log_message "Stopping all instances again before final upgrade..."
ampinstmgr --StopAllInstances
sleep 10
log_message "Upgrading all AMP instances..."
ampinstmgr --UpgradeAll
sleep 5
log_message "Attempting to start all instances..."
if ampinstmgr --StartAllInstances; then
    log_message "✅ All instances have been instructed to start. Please check the AMP panel for their status."
else
    log_error "The command to start all instances failed. Please check AMP logs and start them manually."
fi

log_message "-----------------------------------------------------"
log_message "Update Script Completed!"
log_message "All servers have been updated and started."
log_message "-----------------------------------------------------"
exit 0
