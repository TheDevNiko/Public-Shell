#!/usr/bin/env bash

wget https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-musl.tar.gz

tar -xvzf realm-x86_64-unknown-linux-musl.tar.gz
rm -f realm-x86_64-unknown-linux-musl.tar.gz
mv realm /usr/bin/realm
chmod +x /usr/bin/realm
mkdir /etc/realm

cat > /etc/systemd/system/realm@.service <<EOF
[Unit]
Description=Mithril Cable Network
After=network.target
[Service]
Type=simple
LimitCPU=infinity
LimitFSIZE=infinity
LimitDATA=infinity
LimitSTACK=infinity
LimitCORE=infinity
LimitRSS=infinity
LimitNOFILE=infinity
LimitAS=infinity
LimitNPROC=infinity
LimitMEMLOCK=infinity
LimitLOCKS=infinity
LimitSIGPENDING=infinity
LimitMSGQUEUE=infinity
LimitRTPRIO=infinity
LimitRTTIME=infinity
ExecStart=/usr/bin/realm -c /etc/realm/%i.toml
Restart=always
RestartSec=4
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload