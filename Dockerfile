FROM ubuntu:24.04

RUN cat << '__EOF_INIT_BASH__' > /root/init.bash
set -e
set -o pipefail
umask 0077

# update system
apt update
apt upgrade -y
apt install p7zip-full rsync ripgrep git curl tmux sudo less procps -y

# create users
ROOT_PASSWD=$(openssl rand -base64 48)
useradd -m -s /bin/bash -aG sudo user
echo "user:${ROOT_PASSWD}" | chpasswd
passwd -l root

# setup xray
useradd --system --no-create-home --home-dir /opt/xray --shell /usr/sbin/nologin xray
curl -fLO https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
mkdir /opt/xray
7z x Xray-linux-64.zip -o/opt/xray
XRAY_PATH="$(openssl rand -hex 16)"
OVIS_UUID="$(/opt/xray/xray uuid)"
eval "$(sudo /opt/xray/xray x25519 | awk -F': *' '
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
chmod 0440 /opt/xray/*
chmod 0550 /opt/xray/xray
chmod 0550 /opt/xray
chown -R root:xray /opt/xray
pushd /opt/xray
nohup sudo --user=xray /opt/xray/xray run -c /opt/xray/config.json >/dev/null 2>&1 &
popd

# Setup ovis
pushd /home/user
sudo --user=user mkdir -p /home/user/.config/herdr/plugins/config/devswha.ovis/
OVIS_TOKEN=$(openssl rand -hex 32)
echo "OVIS_TOKEN=${OVIS_TOKEN}" > /home/user/.config/herdr/plugins/config/devswha.ovis/.env
chmod 0440 /home/user/.config/herdr/plugins/config/devswha.ovis/.env
chown root:user /home/user/.config/herdr/plugins/config/devswha.ovis/.env
curl -fsSL https://ovis.sh/install.sh | sudo --user=user OVIS_RUNTIME=herdr sh
#nohup sudo --user=user /home/user/.local/bin/herdr server >/dev/null 2>&1 &
popd

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
Root: "${ROOT_PASSWD}"
__EOF__

# Finalize
apt autoclean -y && apt autoremove -y
rm -rf /root/* && rm -rf /root/.*
wait
__EOF_INIT_BASH__

ENTRYPOINT ["bash", "/root/init.bash"]
