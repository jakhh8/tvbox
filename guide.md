## Step 1
unplug 5tb
boot archiso

verify the internal drive is name /dev/sda (lsblk -f) and which is usb
potentially update userconfig

mkdir -p /mnt/usb
mount /dev/sda1 OR ACTUAL /mnt/usb

check where user_configuration.json is stored
run the archinstaller with this user_config (archinstall --config path/to/user_configuration.json)

setup user/passwd

mount /dev/sda1 OR ACTUAL /mnt/usb
cp /mnt/usb/setup-tvbox.sh /mnt/home/<username>/

unplug usb

reboot


## Step 2
log in (potentially through ssh)
plug in 5tb drive in usb3.0

run setup-tvbox.sh


## Step 3
run this command to check gluetun setup
```
docker exec gluetun wget -qO- https://ipinfo.io
```

open http://tvbox:8080
find password ```docker logs qbittorrent | grep password```
set permanent password

go to ipleak.net torrent address detection click activate
paste magnet link into qbittorrent

check on website if tis protonvpn ip


lock qbittorrent to vpn
settings -> advanced -> network interface = tun0
save


wire up *arr
prowlarr: http://tvbox:9696
sonarr: http://tvbox:8989
radarr: http://tvbox:7878
romarr: http://tvbox:6868
complete first-run auth setup in each

add qbittorrent as download client in sonarr radarr romarr
settings -> download clients -> + -> qbittorrent
host: gluetun
port: 8080
user/passwd: qbittorrent creds

click test then save


set root folders
settings -> media management -> add root folder -> /tv  /movies  /roms


sync indexers via prowlarr
indexers -> add indexer
settings -> apps -> + add sonarr radarr romarr (using their domains?) with their api keys found in settings -> general


add network drive
windows explorer -> this pc -> map network drive -> \\tvbox\Media -> connect using different creds -> login with username + samba password


configure kodi and moonlight on tv
kodi -> media -> library -> videos -> add videos -> browse -> root filesystem -> /mnt/media/movies
same for tv, but set content type to tv show

enable hw accel
settings -> player -> videos -> allow hardware accelleration -> vaapi

select moonlight from flex launcher
enter 4 digit pin for pc