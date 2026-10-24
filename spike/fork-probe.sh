#!/usr/bin/env bash
set -u

FORK=/opt/zeos-fork
BARE=/opt/zeos-fork.git

echo "############ montando o fork local ############"
rm -rf "$FORK" "$BARE"
cp -a /opt/zeos "$FORK"

cat > "$FORK/boss.json" <<'JSON'
{
  "name": "zeoslib",
  "description": "ZeosLib 8.0 com boss.json para unit path limpo",
  "version": "8.0.0",
  "homepage": "https://zeoslib.sourceforge.io",
  "mainsrc": "src/core;src/parsesql;src/plain;src/dbc",
  "projects": [],
  "dependencies": {}
}
JSON

cd "$FORK"
git init -q
git config user.email spike@local
git config user.name spike
git add -A
git commit -qm "zeos 8.0.0-stable + boss.json"
git tag v8.0.0
git tag 8.0.0
cd /
git clone -q --bare "$FORK" "$BARE"
echo "fork pronto. tags:"
git --git-dir="$BARE" tag | sed 's/^/  /'
echo

echo "############ descobrindo a URL que o Boss monta ############"
mkdir -p /tmp/urltest && cd /tmp/urltest
cat > boss.json <<'JSON'
{
  "name": "urltest",
  "version": "1.0.0",
  "mainsrc": "src/",
  "projects": [],
  "dependencies": { "exemplo.invalido/nao/existe": "^1.0.0" }
}
JSON
boss install 2>&1 | grep -oE '(https?|git|ssh)://[^ "]*|exemplo[^ "]*' | head -5 | sed 's/^/  /'
echo

echo "############ testando formas de coordenada local ############"
for coord in "$BARE" "file://$BARE" "$FORK"; do
  echo "--- coordenada: $coord"
  rm -rf /tmp/ft && mkdir -p /tmp/ft/src && cd /tmp/ft
  cat > src/P.lpr <<'EOF'
program P; begin end.
EOF
  cat > P.lpi <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>
    <PathDelim Value="/"/>
    <BuildModes Count="1"><Item1 Name="Release" Default="True"/></BuildModes>
    <Units Count="1"><Unit0><Filename Value="src/P.lpr"/><IsPartOfProject Value="True"/></Unit0></Units>
  </ProjectOptions>
  <CompilerOptions>
    <Version Value="11"/>
    <PathDelim Value="/"/>
    <Target><Filename Value="bin/P"/></Target>
    <SearchPaths><OtherUnitFiles Value=""/></SearchPaths>
  </CompilerOptions>
</CONFIG>
EOF
  python3 - "$coord" <<'PY'
import json, sys
json.dump({
  "name": "ft", "version": "1.0.0", "mainsrc": "src/", "projects": ["P.lpi"],
  "dependencies": { sys.argv[1]: "^8.0.0" }
}, open("boss.json", "w"), indent=2)
PY
  out=$(boss install 2>&1)
  if echo "$out" | grep -q 'Installation completed successfully'; then
    echo "  >>> FUNCIONOU"
    echo "  modules/: $(ls -1 modules/ 2>/dev/null | tr '\n' ' ')"
    echo "  OtherUnitFiles:"
    grep -o 'OtherUnitFiles Value="[^"]*"' P.lpi | sed 's/OtherUnitFiles Value="//; s/"$//' \
      | tr ';' '\n' | grep -c . | sed 's/^/    paths: /'
    grep -o 'OtherUnitFiles Value="[^"]*"' P.lpi | sed 's/OtherUnitFiles Value="//; s/"$//' \
      | tr ';' '\n' | sed 's/^/    /'
    echo "  lock: $(cat boss-lock.json 2>/dev/null | tr -d '\n\t ' | head -c 300)"
    break
  else
    echo "  falhou: $(echo "$out" | grep -oE 'Installation failed.*' | head -1 | cut -c1-160)"
  fi
done
