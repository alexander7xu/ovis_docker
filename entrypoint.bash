#!/bin/bash
set -e
set -o pipefail
umask 0077
cd /root

# update system
apt update
apt upgrade -y
apt install p7zip-full rsync ripgrep git curl tmux vim less procps -y

# create users
useradd -m -s /bin/bash user
passwd -l root
echo "user:$(openssl rand -base64 48)" | chpasswd

# setup xray
useradd --system --create-home --home-dir /opt/xray --shell /usr/sbin/nologin xray
curl -fLO https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
7z x Xray-linux-64.zip -o/opt/xray
XRAY_PATH="$(openssl rand -hex 16)"
OVIS_UUID="$(/opt/xray/xray uuid)"
eval "$(/opt/xray/xray x25519 | awk -F': *' '
  /^PrivateKey:/ {print "XRAY_KEY=\"" $2 "\""}
  /^Password \(PublicKey\):/ {print "XRAY_PAS=\"" $2 "\""}
')"
cat << __EOF__ > /opt/xray/config.json
{
    // "log": {"loglevel": "info"},
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "${OVIS_UUID}", "email": "ovis"}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "xhttpSettings": {"path": "${XRAY_PATH}"},
                "security": "reality",
                "realitySettings": {
                    "target": "music.apple.com:443",
                    "serverNames": ["music.apple.com"],
                    "privateKey": "${XRAY_KEY}",
                    "shortIds": ["0d000721"]
                }
            }
        }
    ],
    "outbounds": [
        {
            "tag": "block",
            "protocol": "blackhole",
            "settings": {}
        },
        {
            "tag": "ovis",
            "protocol": "freedom",
            "settings": {
                "redirect": "127.0.0.1:0",
                "finalRules": [{
                    "action": "allow",
                    "network": "tcp",
                    "ip": ["127.0.0.1/32"],
                    "port": "7317"
                }]
            }
        }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "user": ["ovis"],
                "domain": ["full:ovis.invalid"],
                "port": "7317",
                "network": "tcp",
                "outboundTag": "ovis"
            },
            {
                "ip": [
                    "geoip:private",
                    "169.254.0.0/16",
                    "fe80::/10"
                ],
                "outboundTag": "block",
                "ruleTag": "block_other_private_targets"
            }
        ]
    }
}
__EOF__
chown -R root:xray /opt/xray
chmod -R 0440 /opt/xray
chmod 0550 /opt/xray
chmod 0550 /opt/xray/xray

# Setup ovis
useradd --system --create-home --home-dir /opt/ovis --shell /usr/sbin/nologin ovis
mkdir -p /run/ovis
chown user:ovis /run/ovis
chmod 2710 /run/ovis
runuser -u user -- /usr/bin/tmux -f /dev/null -S /run/ovis/tmux.sock \
    start-server \; \
    set-option -s exit-empty off \; \
    set-option -g destroy-unattached on \; \
    server-access -w ovis
runuser -u user -- chmod 0660 /run/ovis/tmux.sock
chown root:ovis /run/ovis
chmod 0555 /run/ovis
cat << '__EOF__' > /opt/ovis/user-shell
#!/bin/sh
exec /usr/bin/tmux -N -S /run/ovis/tmux.sock new-session -E -c /home/user /bin/bash -l
__EOF__
chown root:ovis /opt/ovis/user-shell
chmod 0550 /opt/ovis/user-shell
OVIS_PLUGIN_DIR=/opt/ovis/.config/herdr/plugins/config/devswha.ovis
runuser -u ovis -- mkdir -p "$OVIS_PLUGIN_DIR"
OVIS_TOKEN=$(openssl rand -hex 32)
echo "OVIS_TOKEN=${OVIS_TOKEN}" > "$OVIS_PLUGIN_DIR/.env"
chown root:ovis "$OVIS_PLUGIN_DIR/.env"
chmod 0440 "$OVIS_PLUGIN_DIR/.env"
(
    cd /opt/ovis
    curl -fsSL https://ovis.sh/install.sh |
        runuser -u ovis -- env \
            HOME=/opt/ovis \
            SHELL=/opt/ovis/user-shell \
            OVIS_RUNTIME=herdr \
            sh -s -- --no-service
)
chown root:ovis /opt/ovis
chmod 0550 /opt/ovis

# Hint
cat << __EOF__
[INFO] Beg Clash Config
  - name: ovis
    type: vless
    server: 
    port: 
    uuid: ${OVIS_UUID}
    encryption: none
    network: xhttp
    tls: true
    flow: ""
    servername: music.apple.com
    client-fingerprint: chrome
    xhttp-opts:
      host: music.apple.com
      path: /${XRAY_PATH}
    reality-opts:
      public-key: ${XRAY_PAS}
      short-id: 0d000721
      support-x25519mlkem768: true
[INFO] End Clash Config
Visit: http://ovis.invalid:7317/#auth=${OVIS_TOKEN}
__EOF__

# Finalize
apt autoclean -y
apt autoremove -y
rm -rf /root/*
rm -rf /root/.*
cd /opt/xray
exec runuser -u xray -- /opt/xray/xray run -c /opt/xray/config.json
