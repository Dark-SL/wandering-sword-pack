#!/usr/bin/env bash
# Wandering Sword - one-command server setup for a fresh Ubuntu machine (made for Oracle Cloud "Always Free").
#
#   curl -fsSL https://raw.githubusercontent.com/Dark-SL/wandering-sword-pack/main/server/setup.sh | bash
#
# Installs Java 21, NeoForge 21.1.267, the Wandering Sword modpack and the playit.gg tunnel; runs the server as a
# service that restarts on crash; checks GitHub for new mod versions every 3 minutes; backs the world up daily.
set -euo pipefail

PACK_URL="https://raw.githubusercontent.com/Dark-SL/wandering-sword-pack/main"
NEOFORGE="21.1.267"
DIR="/opt/wandering-sword"
SVC_USER="minecraft"

ask() { local reply; read -r -p "$1" reply < /dev/tty; echo "$reply"; }

echo "=== Wandering Sword server setup ==="
echo "Minecraft servers require you to accept the Minecraft EULA: https://aka.ms/MinecraftEULA"
[[ "$(ask 'Do you accept the Minecraft EULA? [y/N] ')" =~ ^[Yy] ]] || { echo "Setup stopped: the EULA was not accepted."; exit 1; }
OP_NAME="$(ask 'Your Minecraft username (you will be made server operator; blank to skip): ')"

echo "--- installing Java 21 and tools"
sudo apt-get update -y
sudo apt-get install -y openjdk-21-jre-headless curl python3 gnupg

echo "--- installing the playit.gg tunnel agent"
curl -fsSL https://playit-cloud.github.io/ppa/key.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/playit.gpg > /dev/null
echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" | sudo tee /etc/apt/sources.list.d/playit-cloud.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y playit

echo "--- creating the server in $DIR"
id "$SVC_USER" &>/dev/null || sudo useradd --system --home "$DIR" --shell /usr/sbin/nologin "$SVC_USER"
sudo mkdir -p "$DIR" "$DIR/backups"
cd "$DIR"
sudo curl -fsSL -o neoforge-installer.jar "https://maven.neoforged.net/releases/net/neoforged/neoforge/$NEOFORGE/neoforge-$NEOFORGE-installer.jar"
sudo java -jar neoforge-installer.jar --installServer > /dev/null
sudo rm -f neoforge-installer.jar neoforge-installer.jar.log
sudo curl -fsSL -o packwiz-installer-bootstrap.jar https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar
sudo curl -fsSL -o update-check.py "$PACK_URL/server/update-check.py"
echo "eula=true" | sudo tee eula.txt > /dev/null

# memory: 70% of the machine, between 2 and 12 GB
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
HEAP=$(( MEM_MB * 70 / 100 )); (( HEAP > 12288 )) && HEAP=12288; (( HEAP < 2048 )) && HEAP=2048
echo "-Xms1G -Xmx${HEAP}M -XX:+UseG1GC -XX:MaxGCPauseMillis=100" | sudo tee user_jvm_args.txt > /dev/null

RCON_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)
if [ ! -f server.properties ]; then
  sudo tee server.properties > /dev/null <<EOF
motd=§6Wandering Sword §7- drift between worlds
difficulty=normal
max-players=20
view-distance=10
simulation-distance=8
spawn-protection=0
enable-rcon=true
rcon.port=25575
rcon.password=$RCON_PASS
server-ip=
server-port=25565
EOF
fi
[ -n "$OP_NAME" ] && echo "$OP_NAME" | sudo tee pending-op.txt > /dev/null
sudo chown -R "$SVC_USER":"$SVC_USER" "$DIR"

echo "--- installing services"
sudo tee /etc/systemd/system/wandering-sword.service > /dev/null <<EOF
[Unit]
Description=Wandering Sword Minecraft server
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
WorkingDirectory=$DIR
# pull the newest modpack from GitHub before every start
ExecStartPre=/usr/bin/java -jar $DIR/packwiz-installer-bootstrap.jar -g -s server $PACK_URL/pack.toml
ExecStart=/bin/bash $DIR/run.sh nogui
Restart=always
RestartSec=10
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/wandering-sword-update.service > /dev/null <<EOF
[Unit]
Description=Check GitHub for a new Wandering Sword version

[Service]
Type=oneshot
User=$SVC_USER
WorkingDirectory=$DIR
ExecStart=/usr/bin/python3 $DIR/update-check.py $PACK_URL/pack.toml
EOF

sudo tee /etc/systemd/system/wandering-sword-update.timer > /dev/null <<EOF
[Unit]
Description=Check for Wandering Sword updates every 3 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=3min

[Install]
WantedBy=timers.target
EOF

# the update checker may restart the server
echo "$SVC_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart wandering-sword" | sudo tee /etc/sudoers.d/wandering-sword > /dev/null

# daily world backup at 05:00, keep the last 7
sudo tee /etc/cron.d/wandering-sword-backup > /dev/null <<EOF
0 5 * * * $SVC_USER cd $DIR && tar -czf backups/world-\$(date +\%F).tar.gz world && ls -1t backups/world-*.tar.gz | tail -n +8 | xargs -r rm --
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now wandering-sword.service wandering-sword-update.timer
sudo systemctl enable --now playit

echo
echo "=== Done. The server is starting (first start takes a few minutes). ==="
echo "Next: link the tunnel to your playit.gg account. Open the link below in your browser:"
sleep 5
sudo journalctl -u playit --no-pager -n 100 | grep -o 'https://playit.gg/claim/[A-Za-z0-9]*' | tail -n 1 || true
echo "(If no link appeared, run:  sudo playit  and open the link it prints.)"
echo "In the playit.gg dashboard add a tunnel: type 'Minecraft Java', local address 127.0.0.1, port 25565."
echo "Server log:   sudo journalctl -u wandering-sword -f"
