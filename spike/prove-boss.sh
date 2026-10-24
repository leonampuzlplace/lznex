#!/usr/bin/env bash
# prove-boss.sh — prova empirica do fluxo de empacotamento:
#   1. fork do Zeos com boss.json + tag semver instala limpo (4 paths, nao ~40)
#   2. lznex depende do zeos; consumidor depende so do lznex e recebe os dois
#      (dependencia transitiva)
#   3. o unit path injetado realmente compila codigo que usa Zeos
set -u

HOST=gitlocal
GITROOT=/srv/git

publish() {  # publish <nome> <dir-de-origem>
  local name="$1" src="$2"
  rm -rf "$GITROOT/$name" /tmp/pub-$name
  cp -a "$src" /tmp/pub-$name
  cd /tmp/pub-$name
  rm -rf .git
  git init -q
  git config user.email spike@local
  git config user.name spike
  git add -A
  git commit -qm "release"
  git tag "v$3"
  git tag "$3"
  cd /
  git clone -q --bare /tmp/pub-$name "$GITROOT/$name"
  git --git-dir="$GITROOT/$name" update-server-info
  # O apache roda como www-data; sem isso o git recusa com "dubious ownership"
  # e o git-http-backend devolve 500.
  chown -R www-data:www-data "$GITROOT/$name"
  chmod -R a+rX "$GITROOT/$name"
  git config --system --add safe.directory "$GITROOT/$name" 2>/dev/null || true
}

mklpi() {  # mklpi <arquivo.lpi> <main.lpr>
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>
    <PathDelim Value="/"/>
    <General><Flags><MainUnitHasCreateFormStatements Value="False"/><CompatibilityMode Value="True"/></Flags></General>
    <BuildModes Count="1"><Item1 Name="Release" Default="True"/></BuildModes>
    <Units Count="1"><Unit0><Filename Value="$2"/><IsPartOfProject Value="True"/></Unit0></Units>
  </ProjectOptions>
  <CompilerOptions>
    <Version Value="11"/>
    <PathDelim Value="/"/>
    <Target><Filename Value="bin/App"/></Target>
    <SearchPaths>
      <IncludeFiles Value=""/>
      <OtherUnitFiles Value=""/>
      <UnitOutputDirectory Value="lib"/>
    </SearchPaths>
    <Other><CustomOptions Value="-dUseCThreads"/></Other>
  </CompilerOptions>
</CONFIG>
EOF
}

paths() {  # paths <arquivo.lpi>
  grep -o 'OtherUnitFiles Value="[^"]*"' "$1" | head -1 \
    | sed 's/OtherUnitFiles Value="//; s/"$//' | tr ';' '\n' | grep -c .
}
showpaths() {
  grep -o 'OtherUnitFiles Value="[^"]*"' "$1" | head -1 \
    | sed 's/OtherUnitFiles Value="//; s/"$//' | tr ';' '\n' | sed 's/^/    /'
}

echo "################ 1. publicando o fork do Zeos com boss.json ################"
rm -rf /tmp/zeosfork
cp -a /opt/zeos /tmp/zeosfork
cat > /tmp/zeosfork/boss.json <<'JSON'
{
  "name": "zeoslib",
  "description": "ZeosLib 8.0.0-stable com boss.json (mainsrc nas 4 pastas de DBC)",
  "version": "8.0.0",
  "homepage": "https://zeoslib.sourceforge.io",
  "mainsrc": "src/core;src/parsesql;src/plain;src/dbc",
  "projects": [],
  "dependencies": {}
}
JSON
publish zeoslib /tmp/zeosfork 8.0.0
echo "publicado: https://$HOST/zeoslib  tags: $(git --git-dir=$GITROOT/zeoslib tag | tr '\n' ' ')"
echo

echo "################ 2. consumidor direto do Zeos ################"
rm -rf /tmp/c1 && mkdir -p /tmp/c1/src && cd /tmp/c1
cat > src/App.lpr <<'EOF'
program App;
{$MODE DELPHI}{$H+}
uses SysUtils, ZDbcIntfs, ZDbcMySql;
begin
  Writeln('units do Zeos resolvidas pelo unit path do Boss');
end.
EOF
mklpi App.lpi src/App.lpr
cat > boss.json <<JSON
{
  "name": "consumidor-zeos",
  "version": "1.0.0",
  "mainsrc": "src/",
  "projects": ["App.lpi"],
  "dependencies": { "$HOST/zeoslib": "^8.0.0" }
}
JSON
out=$(boss install 2>&1)
if echo "$out" | grep -q 'completed successfully'; then
  echo "  boss install: OK"
  echo "  modules/: $(ls -1 modules/ | tr '\n' ' ')"
  echo "  paths injetados: $(paths App.lpi)"
  showpaths App.lpi
  echo "  lock: $(python3 -c 'import json;d=json.load(open("boss-lock.json"));print(json.dumps(d["installedModules"]))' 2>/dev/null)"
else
  echo "  boss install FALHOU:"
  echo "$out" | grep -oE 'Installation failed.*' | head -1 | cut -c1-200 | sed 's/^/    /'
fi
echo
echo "  -- compila de verdade com esses paths? --"
mkdir -p bin lib
if lazbuild App.lpi > /tmp/lb1.log 2>&1; then
  echo "  lazbuild: OK -> $(./bin/App)"
else
  echo "  lazbuild FALHOU:"
  grep -Ei 'fatal|error' /tmp/lb1.log | head -5 | sed 's/^/    /'
fi
echo

echo "################ 3. publicando um 'lznex' que depende do Zeos ################"
rm -rf /tmp/lznexpkg && mkdir -p /tmp/lznexpkg/src
cat > /tmp/lznexpkg/src/FakeLzNex.pas <<'EOF'
unit FakeLzNex;
{$MODE DELPHI}{$H+}
interface
// Ping — stub so para provar que a unit do pacote foi resolvida.
function Ping: string;
implementation
uses SysUtils, ZDbcIntfs;
function Ping: string;
begin
  Result := 'lznex ok (e enxerga o Zeos: ' + BoolToStr(DriverManager <> nil, True) + ')';
end;
end.
EOF
cat > /tmp/lznexpkg/boss.json <<JSON
{
  "name": "lznex",
  "description": "stub do LzNex para provar dependencia transitiva",
  "version": "1.0.0",
  "mainsrc": "src/",
  "projects": [],
  "dependencies": { "$HOST/zeoslib": "^8.0.0" }
}
JSON
publish lznex /tmp/lznexpkg 1.0.0
echo "publicado: https://$HOST/lznex"
echo

echo "################ 4. consumidor que declara SO o lznex (transitiva) ################"
rm -rf /tmp/c2 && mkdir -p /tmp/c2/src && cd /tmp/c2
cat > src/App.lpr <<'EOF'
program App;
{$MODE DELPHI}{$H+}
uses SysUtils, FakeLzNex;
begin
  Writeln(Ping);
end.
EOF
mklpi App.lpi src/App.lpr
cat > boss.json <<JSON
{
  "name": "consumidor-lznex",
  "version": "1.0.0",
  "mainsrc": "src/",
  "projects": ["App.lpi"],
  "dependencies": { "$HOST/lznex": "^1.0.0" }
}
JSON
out=$(boss install 2>&1)
if echo "$out" | grep -q 'completed successfully'; then
  echo "  boss install: OK"
  echo "  modules/: $(ls -1 modules/ | tr '\n' ' ')"
  echo "  paths injetados: $(paths App.lpi)"
  showpaths App.lpi
else
  echo "  boss install FALHOU:"
  echo "$out" | grep -oE 'Installation failed.*' | head -1 | cut -c1-200 | sed 's/^/    /'
fi
echo
echo "  -- compila usando a unit do pacote + o Zeos transitivo? --"
mkdir -p bin lib
if lazbuild App.lpi > /tmp/lb2.log 2>&1; then
  echo "  lazbuild: OK -> $(./bin/App)"
else
  echo "  lazbuild FALHOU:"
  grep -Ei 'fatal|error' /tmp/lb2.log | head -8 | sed 's/^/    /'
fi
