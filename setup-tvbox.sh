#!/usr/bin/env bash
set -euo pipefail

echo "=== HP 8300 USDT HTPC + Docker Post-Install Setup ==="

# 1. Install external drive filesystem tools & Flex Launcher
echo "[1/7] Installing NTFS/exFAT drivers and Flex Launcher..."
sudo pacman -S --needed --noconfirm ntfs-3g exfatprogs curl
curl -LO https://github.com
sudo pacman -U --noconfirm flex-launcher-2.2-1-x86_64.pkg.tar.zst
rm -f flex-launcher-2.2-1-x86_64.pkg.tar.zst

# 2. Detect and mount external drive to /mnt/media
echo ""
echo "[2/7] Available partitions:"
lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINT
echo ""
read -rp "Enter the UUID of your external media partition (or leave blank to skip): " EXT_UUID

sudo mkdir -p /mnt/media
if [[ -n "$EXT_UUID" ]]; then
    EXT_FSTYPE=$(blkid -U "$EXT_UUID" | xargs lsblk -no FSTYPE)
    if [[ "$EXT_FSTYPE" == "ext4" ]]; then
        FSTAB_LINE="UUID=$EXT_UUID  /mnt/media  ext4  defaults,noatime,nofail  0  2"
    elif [[ "$EXT_FSTYPE" == "ntfs" ]]; then
        FSTAB_LINE="UUID=$EXT_UUID  /mnt/media  ntfs-3g  uid=1000,gid=1000,dmask=022,fmask=133,nofail  0  0"
    elif [[ "$EXT_FSTYPE" == "exfat" ]]; then
        FSTAB_LINE="UUID=$EXT_UUID  /mnt/media  exfat  uid=1000,gid=1000,dmask=022,fmask=133,nofail  0  0"
    else
        echo "Unsupported or unknown filesystem ($EXT_FSTYPE). Skipping fstab."
        FSTAB_LINE=""
    fi

    if [[ -n "$FSTAB_LINE" ]] && ! grep -q "$EXT_UUID" /etc/fstab; then
        echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
        sudo systemctl daemon-reload
        sudo mount -a
    fi
fi

sudo mkdir -p /mnt/media/{movies,tv,roms,downloads}
sudo chown -R "$USER":"$USER" /mnt/media

# 3. Make Docker wait for /mnt/media before starting
echo "[3/7] Configuring Docker mount dependency..."
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/wait-for-media.conf > /dev/null << 'EOF'
[Unit]
RequiresMountsFor=/mnt/media
EOF
sudo systemctl daemon-reload
sudo usermod -aG docker "$USER"

# 4. Configure Openbox & TTY1 Autologin (No Greeter)
echo "[4/7] Configuring autologin directly into Openbox + Flex Launcher..."
mkdir -p ~/.config/openbox
cat << 'EOF' > ~/.config/openbox/autostart
xset s off -dpms &
flex-launcher &
EOF

cp /etc/xdg/openbox/rc.xml ~/.config/openbox/rc.xml
python3 - << 'EOF'
with open("/home/" + __import__("os").environ["USER"] + "/.config/openbox/rc.xml", "r") as f:
    xml = f.read()

old_bind = """  <keybind key="A-F4">
    <action name="Close"/>
  </keybind>"""

new_bind = """  <keybind key="A-F4">
    <action name="If">
      <query target="focus">
        <title type="regex">^(?!Flex Launcher).*$</title>
      </query>
      <then>
        <action name="Close"/>
      </then>
    </action>
  </keybind>"""

if old_bind in xml:
    xml = xml.replace(old_bind, new_bind, 1)
    with open("/home/" + __import__("os").environ["USER"] + "/.config/openbox/rc.xml", "w") as f:
        f.write(xml)
EOF

echo "exec openbox-session" > ~/.xinitrc

if ! grep -q "exec startx" ~/.bash_profile 2>/dev/null; then
cat << 'EOF' >> ~/.bash_profile
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  exec startx
fi
EOF
fi

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $USER %I \$TERM
EOF

# 5. Configure Flex Launcher
echo "[5/7] Setting up Flex Launcher config..."
mkdir -p ~/.config/flex-launcher
cp -rn /usr/share/flex-launcher/* ~/.config/flex-launcher/
cat << 'EOF' > ~/.config/flex-launcher/config.ini
[General]
Fullscreen = true
FPSLimit = 60
VSync = true
OnLaunch = Blank
OnExit = Quit
IdleTimeout = 0
MouseSelect = true
WrapEntries = true
ResetOnBack = true
AutoHideCursor = true
CursorTimeout = 3

[Layout]
MaxButtons = 5
IconSize=240
IconSpacing=45
VCenter=22%
Font = /usr/share/flex-launcher/assets/fonts/OpenSans-Regular.ttf
FontSize = 24
FontColor = #E5E5EA
Background = ~/setup/images/tvbox-background.png
Highlight = /usr/share/flex-launcher/assets/highlights/rounded.png
HighlightPadding = 12
TitleEnabled = false
ClockEnabled = true
ClockFont = /usr/share/flex-launcher/assets/fonts/OpenSans-Regular.ttf
ClockFontSize = 28
ClockColor = #8E8E93
ClockFormat = 24

[Main]
Title = TVBox

Entry1Title = YouTube
Entry1Icon = ~/setup/images/tvbox-youtube-tile.png
Entry1Cmd = firefox --kiosk https://youtube.com

Entry2Title = ES-DE
Entry2Icon = ~/setup/images/tvbox-es-de-tile.png
Entry2Cmd = moonlight-qt stream "desktop" "ES-DE"

Entry3Title = Steam
Entry3Icon = ~/setup/images/tvbox-steam-tile.png
Entry3Cmd = moonlight-qt stream "desktop" "Steam Big Picture"

Entry4Title = Kodi
Entry4Icon = ~/setup/images/tvbox-kodi-tile.png
Entry4Cmd = kodi

Entry5Title = Settings
Entry5Icon = ~/setup/images/tvbox-settings-tile.png
Entry5Cmd = submenu Settings

[Settings]
Title = Settings

Entry1Title = Moonlight
Entry1Icon = ~/setup/images/tvbox-moonlight-tile.png
Entry1Cmd = moonlight-qt

Entry2Title = Reboot
Entry2Icon = ~/setup/images/tvbox-restart-tile.png
Entry2Cmd = systemctl reboot

Entry3Title = Shutdown
Entry3Icon = ~/setup/images/tvbox-power-tile.png
Entry3Cmd = systemctl poweroff
EOF

# 6. Configure Samba Network Share
echo "[6/7] Configuring Samba share for /mnt/media..."
sudo tee /etc/samba/smb.conf > /dev/null << 'EOF'
[global]
   workgroup = WORKGROUP
   server string = TV Box
   server role = standalone server
   log file = /var/log/samba/log.%m
   max log size = 50
   security = user
   map to guest = Bad User
   min protocol = SMB2

[Media]
   path = /mnt/media
   browseable = yes
   writable = yes
   guest ok = no
   valid users = @users
   force group = users
   create mask = 0664
   directory mask = 0775
EOF

sudo usermod -aG users "$USER"
echo "Set a Samba network password for $USER:"
sudo smbpasswd -a "$USER"
sudo systemctl enable --now smb nmb

# 7. Deploy Docker Stack (Gluetun + qBittorrent + *arr + ROMarr)
echo "[7/7] Setting up Docker stack in /opt/tvbox..."
sudo mkdir -p /opt/tvbox
sudo chown -R "$USER":"$USER" /opt/tvbox

read -rp "Paste your ProtonVPN WireGuard Private Key: " PROTON_KEY

cat << EOF > /opt/tvbox/.env
PROTON_WG_PRIVATE_KEY=$PROTON_KEY
PROTON_COUNTRY=Denmark
MEDIA_ROOT=/mnt/media
EOF

cat << 'EOF' > /opt/tvbox/docker-compose.yml
services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - ./config/gluetun:/gluetun
    environment:
      - VPN_SERVICE_PROVIDER=protonvpn
      - VPN_TYPE=wireguard
      - WIREGUARD_PRIVATE_KEY=${PROTON_WG_PRIVATE_KEY}
      - SERVER_COUNTRIES=${PROTON_COUNTRY:-Denmark}
      - VPN_PORT_FORWARDING=on
      - TZ=Europe/Copenhagen
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Copenhagen
      - WEBUI_PORT=8080
    volumes:
      - ./config/qbittorrent:/config
      - ${MEDIA_ROOT}/downloads:/downloads
    restart: unless-stopped

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Copenhagen
    volumes:
      - ./config/prowlarr:/config
    ports:
      - "9696:9696"
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Copenhagen
    volumes:
      - ./config/sonarr:/config
      - ${MEDIA_ROOT}/tv:/tv
      - ${MEDIA_ROOT}/downloads:/downloads
    ports:
      - "8989:8989"
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Copenhagen
    volumes:
      - ./config/radarr:/config
      - ${MEDIA_ROOT}/movies:/movies
      - ${MEDIA_ROOT}/downloads:/downloads
    ports:
      - "7878:7878"
    restart: unless-stopped

  romarr:
    image: ghcr.io/blizzhacker/romarr:latest
    container_name: romarr
    environment:
      - PUID=1000
      - PGID=1000
      - UMASK=002
      - TZ=Europe/Copenhagen
      - LIBRARY_KIND=folder
      - LIBRARY_PATH=/roms
    volumes:
      - ./config/romarr:/config
      - ${MEDIA_ROOT}/roms:/roms
      - ${MEDIA_ROOT}/downloads:/downloads
    ports:
      - "6868:6868"
    restart: unless-stopped
EOF

cd /opt/htpc && sudo docker compose up -d

echo ""
echo "=== Setup Complete! ==="
echo "Web UIs available at http://tvbox.local (or your HP 8300 IP):"
echo "  - qBittorrent (via ProtonVPN): :8080"
echo "  - Prowlarr:                    :9696"
echo "  - Sonarr:                      :8989"
echo "  - Radarr:                      :7878"
echo "  - ROMarr:                      :6868"
echo "  - Samba Network Share:         \\\\tvbox\\Media"
echo ""
read -rp "Press Enter to reboot into Flex Launcher..."
sudo reboot
