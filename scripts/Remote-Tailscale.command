#!/bin/zsh
# Publishes Vox's phone remote on your tailnet with HTTPS (voice works on iPhone):
#   https://<this-mac>.<tailnet>.ts.net  ->  http://127.0.0.1:7788
# Only devices signed in to YOUR Tailscale account can reach it, and the pairing code is still required.
TS=""
for p in /Applications/Tailscale.app/Contents/MacOS/Tailscale /opt/homebrew/bin/tailscale /usr/local/bin/tailscale; do
  [[ -x "$p" ]] && TS="$p" && break
done
if [[ -z "$TS" ]]; then
  echo "Tailscale isn't installed. Get it from https://tailscale.com/download (Mac and phone), sign in, then run this again."
  read -k 1 "?Press any key to close."; exit 1
fi
echo "Turning on Tailscale Serve for port 7788…"
echo "(If it prints a login.tailscale.com link and waits: open it, click Enable HTTPS, and this finishes by itself.)"
"$TS" serve --bg 7788
echo
"$TS" serve status
echo
echo "Now open Vox → Settings → Phone and scan the QR code with your phone."
echo "To turn it off later: $TS serve --https=443 off"
read -k 1 "?Press any key to close."
