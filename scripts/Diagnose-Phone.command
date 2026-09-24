#!/bin/zsh
# Checks everything the phone remote needs, writes .logs/phone.log. Never prints the pairing code.
cd "$(dirname "$0")/.."
mkdir -p .logs
LOG=.logs/phone.log
TS=""
for p in /Applications/Tailscale.app/Contents/MacOS/Tailscale /opt/homebrew/bin/tailscale /usr/local/bin/tailscale; do [[ -x "$p" ]] && TS="$p" && break; done
{
  echo "== $(date)  macOS $(sw_vers -productVersion)"
  echo "-- Vox running?"; ps -axo pid,command | grep -i "Vox.app/Contents/MacOS/Vox" | grep -v grep || echo "Vox is NOT running"
  echo "-- phone setting"; echo "remoteEnabled=$(defaults read com.mattathiasa.vox remoteEnabled 2>/dev/null || echo unset) remoteAllowLAN=$(defaults read com.mattathiasa.vox remoteAllowLAN 2>/dev/null || echo unset)"
  echo "-- listening on 7788"; lsof -nP -iTCP:7788 -sTCP:LISTEN 2>/dev/null || echo "nothing is listening on 7788"
  echo "-- local checks"
  curl -s -m 3 -w "  ping [%{http_code}]\n" http://127.0.0.1:7788/api/ping || echo "  ping: no answer"
  curl -s -m 3 -o /dev/null -w "  web page [%{http_code}]\n" http://127.0.0.1:7788/
  curl -s -m 3 -o /dev/null -w "  state without code [%{http_code}] (401 expected)\n" http://127.0.0.1:7788/api/state
  echo "-- Wi-Fi"
  for dev in en0 en1; do ip=$(ipconfig getifaddr $dev 2>/dev/null); [[ -n "$ip" ]] && { echo "  $dev $ip"; curl -s -m 3 -o /dev/null -w "  via $ip:7788 [%{http_code}]\n" http://$ip:7788/api/ping || echo "  via $ip:7788 refused"; }; done
  echo "-- macOS firewall"; /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1 | sed 's/^/  /'
  echo "-- Tailscale"
  if [[ -z "$TS" ]]; then echo "  Tailscale is NOT installed"; else
    "$TS" version 2>&1 | head -1
    "$TS" status --json 2>/dev/null | python3 -c 'import sys,json
d=json.load(sys.stdin); s=d.get("Self",{})
print("  backend:", d.get("BackendState"), "| me:", s.get("DNSName"), "| online:", s.get("Online"))
peers=[(p.get("HostName"), p.get("OS"), p.get("Online")) for p in d.get("Peer",{}).values()]
print("  devices:", peers)' 2>&1 || echo "  tailscale status failed"
    echo "  serve:"; "$TS" serve status 2>&1 | sed 's/^/    /'
    NAME=$("$TS" status --json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))' 2>/dev/null)
    [[ -n "$NAME" ]] && curl -s -m 10 -w "  https://$NAME/api/ping [%{http_code}]\n" "https://$NAME/api/ping" || echo "  https ping failed"
  fi
  echo "-- done"
} > "$LOG" 2>&1
cat "$LOG"
echo; echo "Saved to $LOG. Tell Claude it's done. You can close this window."
