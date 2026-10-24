#!/usr/bin/env bash
set -eu

HOST=${1:-gitlocal}

if ! command -v apache2 >/dev/null 2>&1; then
  echo "== instalando apache2 + openssl =="
  apt-get update -qq
  apt-get install -y -qq apache2 openssl >/dev/null
fi

echo "== gerando cert auto-assinado para $HOST =="
mkdir -p /etc/ssl/gitlocal
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /etc/ssl/gitlocal/server.key \
  -out /etc/ssl/gitlocal/server.crt \
  -subj "/CN=$HOST" \
  -addext "subjectAltName=DNS:$HOST,DNS:localhost,IP:127.0.0.1" 2>/dev/null

cp /etc/ssl/gitlocal/server.crt /usr/local/share/ca-certificates/gitlocal.crt
update-ca-certificates >/dev/null 2>&1
grep -q "$HOST" /etc/hosts || echo "127.0.0.1 $HOST" >> /etc/hosts

echo "== configurando apache como git http-backend =="
mkdir -p /srv/git
a2enmod cgi ssl alias env >/dev/null 2>&1
cat > /etc/apache2/sites-available/gitlocal.conf <<EOF
Listen 443
<VirtualHost *:443>
  ServerName $HOST
  SSLEngine on
  SSLCertificateFile /etc/ssl/gitlocal/server.crt
  SSLCertificateKeyFile /etc/ssl/gitlocal/server.key

  SetEnv GIT_PROJECT_ROOT /srv/git
  SetEnv GIT_HTTP_EXPORT_ALL
  ScriptAlias / /usr/lib/git-core/git-http-backend/

  <Directory "/usr/lib/git-core">
    Require all granted
  </Directory>
</VirtualHost>
EOF
if grep -q "Listen 443" /etc/apache2/ports.conf; then
  sed -i '/^Listen 443$/d' /etc/apache2/sites-available/gitlocal.conf
fi
a2dissite 000-default >/dev/null 2>&1 || true
a2ensite gitlocal >/dev/null 2>&1
apache2ctl -k graceful 2>/dev/null || apache2ctl start 2>/dev/null || service apache2 restart

sleep 2
echo "== apache rodando? =="
pgrep -a apache2 | head -2 || echo "  apache2 NAO subiu"
