#!/usr/bin/env bash
# Bring up a headless virtual desktop you can view from a browser:
#   TigerVNC (Xvnc on :1, port 5901) + openbox + noVNC/websockify (port 6080)
#
# RViz2 renders into this display via Mesa software GL (no GPU/Xorg needed).
# Run this ONLY on a plain ROS image. If you rented an image that already ships
# a VNC desktop (e.g. tiryoh/ros2-desktop-vnc:humble), SKIP this script.
#
#   VNC_PASSWORD=secret bash deploy/start-desktop.sh
#
set -uo pipefail

VNC_PW="${VNC_PASSWORD:-nova5vnc}"
GEOM="${VNC_GEOMETRY:-1600x900}"
WEB_PORT="${NOVNC_PORT:-6080}"

mkdir -p "$HOME/.vnc"
# Build a VNC password file if a vncpasswd tool exists. Some images ship a
# vncserver but not vncpasswd; in that case we fall back to no-auth below.
# Safe because access is only ever over the SSH tunnel (encrypted, localhost).
SECTYPE="None"
# (a) Preferred: a real vncpasswd-style tool, if the image ships one.
VNCPASSWD_BIN=""
for c in vncpasswd tigervncpasswd turbovncpasswd; do command -v "$c" >/dev/null 2>&1 && { VNCPASSWD_BIN="$c"; break; }; done
if [ -n "$VNCPASSWD_BIN" ]; then
  echo "$VNC_PW" | "$VNCPASSWD_BIN" -f > "$HOME/.vnc/passwd"
  chmod 600 "$HOME/.vnc/passwd"
  [ -s "$HOME/.vnc/passwd" ] && SECTYPE="VncAuth"
fi
# (b) Fallback: Ubuntu's TigerVNC ships NO vncpasswd binary. The ~/.vnc/passwd
#     format is just the 8-byte (null-padded/truncated) password DES-ECB
#     encrypted with VNC's fixed key (bit-reversed: E84AD660C4721AE0). openssl
#     can produce it — DES lives in the "legacy" provider on OpenSSL 3.x.
if [ "$SECTYPE" = "None" ] && command -v openssl >/dev/null 2>&1; then
  if printf '%s\0\0\0\0\0\0\0\0' "$VNC_PW" | head -c 8 \
       | openssl enc -des-ecb -nopad -K E84AD660C4721AE0 -provider legacy -provider default \
       > "$HOME/.vnc/passwd" 2>/dev/null && [ -s "$HOME/.vnc/passwd" ]; then
    chmod 600 "$HOME/.vnc/passwd"
    SECTYPE="VncAuth"
  fi
fi
if [ "$SECTYPE" = "None" ]; then
  echo ">> NOTE: couldn't build a VNC password file — starting with -SecurityTypes None"
  echo "   (still safe: you only reach it through the encrypted SSH tunnel)."
fi

# Minimal session: openbox window manager + software GL.
cat > "$HOME/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export LIBGL_ALWAYS_SOFTWARE=1
[ -x /usr/bin/dbus-launch ] && eval "$(dbus-launch --sh-syntax)"
tint2 &
# The WM MUST stay in the foreground: with TigerVNC's xinit, Xvnc is torn down
# the instant xstartup exits, so a backgrounded `openbox-session &` would kill
# the desktop within seconds. `exec` keeps it as the long-lived session leader.
exec openbox-session
EOF
chmod +x "$HOME/.vnc/xstartup"

# Restart cleanly.
vncserver -kill :1 >/dev/null 2>&1 || true
vncserver :1 -geometry "$GEOM" -depth 24 -localhost no -SecurityTypes "$SECTYPE"

# noVNC web bridge: 6080 (http) -> 5901 (vnc).
NOVNC_WEB=/usr/share/novnc
[ -d "$NOVNC_WEB" ] || NOVNC_WEB=/usr/lib/novnc
pkill -f "websockify.*:${WEB_PORT}" >/dev/null 2>&1 || true
pkill -f "websockify.* ${WEB_PORT} " >/dev/null 2>&1 || true
websockify -D --web="$NOVNC_WEB" "$WEB_PORT" localhost:5901

echo
echo ">> Desktop ready."
echo "   VNC display :1 (5901), noVNC web on :${WEB_PORT}"
echo "   Open in a browser:  http://<server-ip>:<external-port-for-${WEB_PORT}>/vnc.html"
if [ "$SECTYPE" = "VncAuth" ]; then echo "   VNC password: ${VNC_PW}"; else echo "   VNC auth: none (SSH-tunnel only)"; fi
