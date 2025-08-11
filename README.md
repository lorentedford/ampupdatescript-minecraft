AMP Minecraft Server Update Script
This script automates the process of updating Spigot/Paper servers, BungeeCord, and various plugins for Minecraft networks managed by CubeCoders' AMP (Application Management Panel).
🚨 Disclaimer: Use at Your Own Risk 🚨
This script is provided "as is" without warranty of any kind, express or implied. The author (lorentedford) assumes no liability for any damages, data loss, or other issues that may arise from its use.
By using this script, you agree that you are solely responsible for:
Backing up your servers and data before running the script.
Verifying the script's configuration to ensure it matches your server setup.
Understanding the commands being executed and their potential impact on your system.
Always test in a non-production environment first.
Features
Automated Server Updates: Updates Spigot/Paper to the latest specified version.
BungeeCord Updates: Fetches the latest stable BungeeCord.jar.
Automated Plugin Updates: Downloads the latest versions of popular plugins from official sources (Modrinth, GitHub).
Premium Plugin System: A secure "dropbox" system to update premium plugins you've purchased without storing credentials.
Smart & Safe:
Only builds Spigot if a recent version doesn't already exist.
Only updates plugins on servers where they are already installed.
Respects .jar.disabled files, keeping them disabled after an update.
Forcefully stops servers and cleans up lock files to prevent startup issues.
Highly Configurable: Easily control which plugins and servers are managed.
1. Prerequisites & Setup
This script is designed for Debian/Ubuntu-based systems. Before running it, you must have the required tools installed.
Update your package list:
sudo apt-get update


Install required packages:
sudo apt-get install -y default-jdk curl wget jq unzip procps


Ensure AMP is installed:
This script relies on ampinstmgr. Please make sure AMP is installed correctly by following the official guide at cubecoders.com/AMPInstall.
Download the Script:
Place the update-amp-script.sh file in a convenient location, such as /home/amp/Minecraft/.
Make the script executable:
chmod +x ./update-amp-script.sh


2. Configuration
Open the update-amp-script.sh file in a text editor. All configuration is done at the top of the file.
Server Configuration
SPIGOT_VERSION: Set the Minecraft version you want to build (e.g., "1.21.8").
AMP_INSTANCES_ARRAY: List the exact names of all AMP instances you want the script to manage.
BUNGEE_INSTANCE_NAME: The specific name of your BungeeCord instance.
SPIGOT_SERVERS_ARRAY: A list of just your Spigot/Paper server instances (everything except BungeeCord).
Plugin Control
The script can update the following plugins automatically. You can easily enable or disable updates for each group.
General Plugins: WorldEdit, WorldGuard, ViaVersion, ViaBackwards.
EssentialsX: The full EssentialsX suite.
GriefPrevention: For specific servers.
Premium Plugins: For plugins you upload manually.
To disable updates for a group, change its setting from true to false:
UPDATE_ESSENTIALSX="false"
UPDATE_GRIEFPREVENTION="false"
UPDATE_PREMIUM_PLUGINS="false"


To disable updates for an individual plugin like WorldGuard, place a # in front of its name in both the MODRINTH_PLUGINS and MODRINTH_GLOBS lists.
Premium Plugin Workflow
This script uses a secure "dropbox" system for premium plugins.
Download: When you get an update for a premium plugin, download the new .jar from its source.
Upload: Place the downloaded .jar file into the /home/amp/Minecraft/PremiumPlugins/ folder.
Run the Script: The script will automatically detect the plugin's name, find which of your servers have it, and perform a safe update. The processed JAR is then moved to an archived subfolder.
3. Usage
After configuring the script, simply run it from your terminal:
./update-amp-script.sh


The script will provide detailed log messages for each step of the process.
