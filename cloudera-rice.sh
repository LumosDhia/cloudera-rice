#!/bin/bash
# cloudera-rice.sh
#
# Restyle the Cloudera QuickStart VM 5.12 (CentOS 6.7, GNOME 2) from the host over SSH.
# Everything is applied remotely; nothing is installed on the host.
#
#   ./cloudera-rice.sh <vm-ip> [--wallpaper URL|FILE] [--no-icons] [--yum]
#
# What it changes on the VM:
#   - wallpaper (zoom) and the system lock on it (Cloudera pins one in a mandatory gconf source)
#   - DarkBlue GTK2 theme (clearlooks engine, the VM has no murrine) and Metacity theme
#     with a navy title bar and round buttons on the right, coloured from the wallpaper
#   - Papirus-Dark icons, copied from the host (needs /usr/share/icons/Papirus{,-Dark})
#   - terminal colours, a blue prompt, and "minifetch" (a ~1 KB neofetch replacement)
#   - 125% UI: font DPI 120, panels 30 px, Nautilus icon zoom "large"
#   - the two black desktop glyphs (Kerberos lock, Parcels gift) recoloured light blue
#   - --yum: fix yum (CentOS 6 cannot do modern HTTPS) via a small HTTP proxy on the host,
#     then install htop
#
# The VM user is cloudera / cloudera and has passwordless sudo. Override with VM_USER and
# VM_PASS. Needs OpenSSH 8.4+ on the host (SSH_ASKPASS_REQUIRE), python3, curl, tar, and
# optionally python3-pil for the icon recolour. Safe to re-run.
set -uo pipefail

VM="${1:-}"; [ -n "$VM" ] && shift
WALL="https://w.wallhaven.cc/full/gw/wallhaven-gwdpz7.jpg"
ICONS=1; YUM=0
while [ $# -gt 0 ]; do
    case "$1" in
        --wallpaper) WALL="${2:?--wallpaper needs a value}"; shift ;;
        --no-icons)  ICONS=0 ;;
        --yum)       YUM=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$VM" ] || { echo "usage: $0 <vm-ip> [--wallpaper URL|FILE] [--no-icons] [--yum]" >&2; exit 2; }

VM_USER="${VM_USER:-cloudera}"; VM_PASS="${VM_PASS:-cloudera}"
WORK="$(mktemp -d)"; PROXY_PID=""
cleanup() { [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

printf '#!/bin/sh\necho "%s"\n' "$VM_PASS" > "$WORK/askpass"; chmod 700 "$WORK/askpass"

# Old sshd on the VM: allow ssh-rsa and the legacy DH group.
vm() {
    SSH_ASKPASS="$WORK/askpass" SSH_ASKPASS_REQUIRE=force setsid -w ssh \
        -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no -o HostKeyAlgorithms=+ssh-rsa \
        -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 \
        "$VM_USER@$VM" "$@"
}
say() { printf '\n==> %s\n' "$*"; }

vm true || { echo "ERROR: cannot ssh to $VM_USER@$VM" >&2; exit 1; }

# ---------------------------------------------------------------- wallpaper
say "wallpaper"
if [ -f "$WALL" ]; then cp "$WALL" "$WORK/wall.jpg"
else curl -fsSL -o "$WORK/wall.jpg" "$WALL" || { echo "ERROR: wallpaper download failed" >&2; exit 1; }; fi
vm 'mkdir -p ~/Pictures && cat > ~/Pictures/wallpaper.jpg' < "$WORK/wall.jpg"

# -------------------------------------------------------------- GTK2 theme
say "GTK2 theme (DarkBlue)"
vm 'mkdir -p ~/.themes/DarkBlue/gtk-2.0 && cat > ~/.themes/DarkBlue/gtk-2.0/gtkrc' <<'EOF'
gtk-color-scheme = "bg_color:#16213f\nfg_color:#cfe0ff\nbase_color:#0e1a3a\ntext_color:#e6efff\nselected_bg_color:#5a86e0\nselected_fg_color:#ffffff\ntooltip_bg_color:#0e1a3a\ntooltip_fg_color:#cfe0ff"
include "/usr/share/themes/Clearlooks/gtk-2.0/gtkrc"
style "dark" {
  bg[NORMAL]="#16213f"   bg[PRELIGHT]="#22305a"  bg[ACTIVE]="#0e1a3a"
  bg[SELECTED]="#5a86e0" bg[INSENSITIVE]="#16213f"
  fg[NORMAL]="#cfe0ff"   fg[PRELIGHT]="#ffffff"  fg[ACTIVE]="#cfe0ff"
  fg[SELECTED]="#ffffff" fg[INSENSITIVE]="#7f8fbf"
  base[NORMAL]="#0e1a3a" base[INSENSITIVE]="#16213f" base[SELECTED]="#5a86e0"
  text[NORMAL]="#e6efff" text[SELECTED]="#ffffff" text[INSENSITIVE]="#7f8fbf"
}
class "GtkWidget" style "dark"
widget_class "*<GtkMenu>" style "dark"
widget_class "*<GtkMenuItem>" style "dark"
widget_class "*<GtkMenuBar>" style "dark"
widget_class "*<GtkButton>" style "dark"
widget_class "*<GtkToggleButton>" style "dark"
widget_class "*Panel*" style "dark"
EOF

# ---------------------------------------------------------- Metacity theme
say "Metacity theme (navy title bar, round buttons on the right)"
python3 -I - <<'PY' | vm 'mkdir -p ~/.themes/DarkBlue/metacity-1 && cat > ~/.themes/DarkBlue/metacity-1/metacity-theme-1.xml'
def mix(h, t, a):
    r = [int(h[i:i+2], 16) for i in (1, 3, 5)]
    return "#%02x%02x%02x" % tuple(round(c + (t - c) * a) for c in r)
# Colours sampled by eye from the wallpaper: window glow, snow, scarf.
BTN = {"close": "#d2604c", "minimize": "#eba867", "maximize": "#8fb2ea"}
INACT, BG, EDGE = "#34406a", "#16213f", "#2c3d70"
x = ['<?xml version="1.0"?>', '<metacity_theme>',
     '<info><name>DarkBlue</name><author>aram</author><copyright>none</copyright><date>2026</date>'
     '<description>Navy titlebar, wallpaper-coloured round buttons</description></info>',
     '<frame_geometry name="normal" title_scale="medium" rounded_top_left="true" rounded_top_right="true">',
     '<distance name="left_width" value="1"/><distance name="right_width" value="1"/><distance name="bottom_height" value="1"/>',
     '<distance name="left_titlebar_edge" value="10"/><distance name="right_titlebar_edge" value="10"/>',
     '<distance name="button_width" value="16"/><distance name="button_height" value="16"/>',
     '<distance name="title_vertical_pad" value="10"/>',
     '<border name="title_border" left="0" right="0" top="0" bottom="0"/>',
     '<border name="button_border" left="0" right="0" top="0" bottom="0"/>', '</frame_geometry>',
     '<frame_geometry name="max" parent="normal" rounded_top_left="false" rounded_top_right="false">',
     '<distance name="left_width" value="0"/><distance name="right_width" value="0"/><distance name="bottom_height" value="0"/>',
     '</frame_geometry>',
     '<draw_ops name="menu_i"><icon x="0" y="0" width="width" height="height"/></draw_ops>']
circ = lambda c: ('<arc color="%s" x="0" y="0" width="width-1" height="height-1" '
                  'start_angle="0" extent_angle="360" filled="true"/>' % c)
for foc in "fu":
    for fn, col in BTN.items():
        b = col if foc == "f" else INACT
        for st, c in (("n", b), ("p", mix(b, 0, .2)), ("h", mix(b, 255, .25))):
            x.append('<draw_ops name="%s_%s_%s">%s</draw_ops>' % (fn, st, foc, circ(c)))
for foc in "fu":
    tc = "#cdd6f4" if foc == "f" else "#7f8fbf"
    x.append('<draw_ops name="bg_%s"><rectangle color="%s" x="0" y="0" width="width" height="height" filled="true"/>'
             '<rectangle color="%s" x="0" y="0" width="width-1" height="height-1" filled="false"/></draw_ops>' % (foc, BG, EDGE))
    x.append('<draw_ops name="title_%s"><title color="%s" x="(width - title_width) / 2" '
             'y="(height - title_height) / 2"/></draw_ops>' % (foc, tc))
    for geo in ("normal", "max"):
        x.append('<frame_style name="%s_%s" geometry="%s">' % (geo, foc, geo))
        x.append('<piece position="entire_background" draw_ops="bg_%s"/><piece position="title" draw_ops="title_%s"/>' % (foc, foc))
        for fn in list(BTN) + ["menu"]:          # metacity insists on a menu button
            for st, sn in (("n", "normal"), ("p", "pressed"), ("h", "prelight")):
                d = "menu_i" if fn == "menu" else "%s_%s_%s" % (fn, st, foc)
                x.append('<button function="%s" state="%s" draw_ops="%s"/>' % (fn, sn, d))
        x.append('</frame_style>')
x.append('<frame_style_set name="s">')
for foc, fy in (("f", "yes"), ("u", "no")):
    for rs in ("none", "vertical", "horizontal", "both"):
        x.append('<frame focus="%s" state="normal" resize="%s" style="normal_%s"/>' % (fy, rs, foc))
    x.append('<frame focus="%s" state="maximized" style="max_%s"/><frame focus="%s" state="shaded" style="normal_%s"/>'
             '<frame focus="%s" state="maximized_and_shaded" style="max_%s"/>' % (fy, foc, fy, foc, fy, foc))
x.append('</frame_style_set>')
x += ['<window type="%s" style_set="s"/>' % t for t in ("normal", "dialog", "modal_dialog", "menu", "utility", "border")]
x.append('</metacity_theme>')
print("\n".join(x))
PY

# ------------------------------------------------------------------ icons
if [ "$ICONS" -eq 1 ]; then
    say "Papirus-Dark icons"
    if [ -d /usr/share/icons/Papirus ] && [ -d /usr/share/icons/Papirus-Dark ]; then
        tar czf - -C /usr/share/icons Papirus Papirus-Dark | vm 'mkdir -p ~/.icons && tar xzf - -C ~/.icons'
    else
        echo "skip: Papirus not found in /usr/share/icons on the host"
    fi
fi

# ------------------------------------------------- recolour the black glyphs
say "desktop glyphs"
for n in glyphicons_203_lock@2x glyphicons_069_gift@2x; do
    vm "cd ~/Documents/img && cp -n $n.png $n.orig.png && cat $n.orig.png" > "$WORK/$n.png" 2>/dev/null
    if python3 -I -c "
from PIL import Image
im = Image.open('$WORK/$n.png').convert('RGBA')
out = Image.new('RGBA', im.size, (169, 193, 240, 255)); out.putalpha(im.split()[3])
out.save('$WORK/new_$n.png')" 2>/dev/null; then
        vm "cat > ~/Documents/img/$n.png" < "$WORK/new_$n.png"
    else
        echo "skip $n (python3-pil missing or file not found)"
    fi
done

# ------------------------------------------------------------- minifetch
say "minifetch"
vm 'sudo tee /usr/local/bin/minifetch >/dev/null && sudo chmod 755 /usr/local/bin/minifetch' <<'EOF'
#!/bin/bash
# minifetch - tiny system info, blue palette
c1=$'\e[38;5;75m'; c2=$'\e[38;5;111m'; d=$'\e[38;5;245m'; r=$'\e[0m'
u=$(awk '{s=int($1);printf "%dd %dh %dm",s/86400,s%86400/3600,s%3600/60}' /proc/uptime)
cpu=$(awk -F: '/model name/{gsub(/^ +| +$|\(R\)|\(TM\)|CPU /,"",$2);print $2;exit}' /proc/cpuinfo)
mem=$(free -m | awk '/Mem:/{printf "%d / %d MiB",$3-$6-$7,$2}')
os=$(cat /etc/redhat-release)
logo=("$c1   ▄▄▄▄▄▄   " "$c1  █$c2▀▀▀▀$c1▀▀█  " "$c1  █$c2 ▄▄ $c1  █  " "$c2  █$c1 ▀▀ $c2  █  " "$c2  ▀█▄▄▄▄█▀  " "$c2   ▀▀▀▀▀▀   ")
info=("$c1$USER$d@$c2$HOSTNAME" "${d}────────────────" "${c1}os     ${r}$os" "${c1}kernel ${r}$(uname -r)" "${c1}uptime ${r}$u" "${c1}cpu    ${r}$cpu" "${c1}mem    ${r}$mem")
echo
for i in 0 1 2 3 4 5 6; do printf '  %s  %s%s\n' "${logo[$i]:-            }" "${info[$i]}" "$r"; done
printf '\n  '; for n in 75 111 179 167 140 80 252; do printf '\e[48;5;%sm   ' $n; done; printf '%s\n\n' "$r"
EOF

# ------------------------------------------------------------ yum + htop
if [ "$YUM" -eq 1 ]; then
    say "yum fix via host proxy, then htop"
    HOSTIP="$(ip route get "$VM" | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
    cat > "$WORK/yumproxy.py" <<'EOF'
import sys, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
MAP = {"/centos/": "https://vault.centos.org/6.10/",
       "/epel/": "https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/"}
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        for p, up in MAP.items():
            if self.path.startswith(p):
                url = up + self.path[len(p):]; break
        else:
            self.send_error(404); return
        try:
            r = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "yumproxy"}), timeout=60)
        except urllib.error.HTTPError as e:
            self.send_error(e.code); return
        except Exception:
            self.send_error(502); return
        self.send_response(200)
        for h in ("Content-Length", "Content-Type", "Last-Modified"):
            if r.headers.get(h): self.send_header(h, r.headers[h])
        self.end_headers()
        while (b := r.read(65536)): self.wfile.write(b)
    def log_message(self, *a): pass
ThreadingHTTPServer((sys.argv[1], int(sys.argv[2])), H).serve_forever()
EOF
    python3 -I "$WORK/yumproxy.py" "$HOSTIP" 8765 & PROXY_PID=$!
    sleep 1
    vm "HOSTIP=$HOSTIP bash -s" <<'EOF'
cd /etc/yum.repos.d
sudo mkdir -p /root/yum.repos.bak && sudo cp -n *.repo /root/yum.repos.bak/
sudo tee CentOS-Base.repo >/dev/null <<R
[base]
name=CentOS-6 Base
baseurl=http://$HOSTIP:8765/centos/os/x86_64/
gpgcheck=0
[updates]
name=CentOS-6 Updates
baseurl=http://$HOSTIP:8765/centos/updates/x86_64/
gpgcheck=0
[extras]
name=CentOS-6 Extras
baseurl=http://$HOSTIP:8765/centos/extras/x86_64/
gpgcheck=0
R
sudo tee epel.repo >/dev/null <<R
[epel]
name=EPEL 6 archive
baseurl=http://$HOSTIP:8765/epel/
gpgcheck=0
R
# the dead vendor repos would otherwise abort every yum run
for f in cloudera-*.repo vmware-tools.repo; do
    [ -f "$f" ] && sudo sed -i '/^skip_if_unavailable/d; /^\[.*\]/a skip_if_unavailable=1' "$f"
done
sudo yum clean all >/dev/null
sudo yum -y install htop </dev/null 2>&1 | tail -3
EOF
    echo "note: yum works only while this proxy runs on the host (it stops when this script ends)."
fi

# ----------------------------------------------- settings on the VM itself
say "applying settings"
vm 'bash -s' <<'EOF'
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' < /proc/$(pgrep -u "$(id -un)" -x gnome-session | head -1)/environ | grep ^DBUS_SESSION | cut -d= -f2-)
G="gconftool-2 --type"

# Cloudera pins the wallpaper in a mandatory source; repoint it (backup kept once).
F=/etc/gconf/gconf.xml.mandatory/desktop/gnome/background/%gconf.xml
if [ -f "$F" ]; then
    sudo cp -n "$F" "$F.bak"
    sudo sed -i "s|<stringvalue>/[^<]*</stringvalue>|<stringvalue>$HOME/Pictures/wallpaper.jpg</stringvalue>|" "$F"
    gconftool-2 --shutdown; sleep 2
else
    $G string --set /desktop/gnome/background/picture_filename "$HOME/Pictures/wallpaper.jpg"
fi
$G string --set /desktop/gnome/background/picture_options zoom
$G string --set /desktop/gnome/background/primary_color "#1c2f6b"

# themes, icons, 125% scale
$G string --set /desktop/gnome/interface/gtk_theme DarkBlue
$G string --set /desktop/gnome/interface/icon_theme Papirus-Dark
$G string --set /apps/metacity/general/theme DarkBlue
$G string --set /apps/metacity/general/button_layout ":minimize,maximize,close"
$G float  --set /desktop/gnome/font_rendering/dpi 120
for p in top_panel bottom_panel; do $G int --set /apps/panel/toplevels/$p/size 30; done
$G string --set /apps/nautilus/icon_view/default_zoom_level large

# terminal colours
P=/apps/gnome-terminal/profiles/Default
$G bool   --set $P/use_theme_colors false
$G string --set $P/background_color "#0e1a3a"
$G string --set $P/foreground_color "#cfe0ff"
$G string --set $P/bold_color "#ffffff"
$G string --set $P/palette "#1a2547:#e0644f:#7fb8a0:#e8b86a:#5a86e0:#9a7fd8:#6cc1d9:#cfe0ff:#3a4a7a:#f08a76:#9fd8bf:#f5d08a:#82a8f5:#b9a0ee:#8fd8ec:#ffffff"
$G bool   --set $P/use_system_font false
$G string --set $P/font "DejaVu Sans Mono 11"
$G string --set $P/background_type transparent
$G float  --set $P/background_darkness 0.88

# prompt + minifetch on interactive shells only (a banner over plain ssh/scp breaks transfers)
grep -q 'rice-prompt' ~/.bashrc || cat >> ~/.bashrc <<'EOT'
# rice-prompt
PS1='\[\e[38;5;75m\]\u\[\e[38;5;245m\]@\[\e[38;5;111m\]\h \[\e[38;5;179m\]\w\[\e[0m\] \[\e[38;5;167m\]❯\[\e[0m\] '
alias ls='ls --color=auto' ll='ls -lah'
# minifetch
alias neofetch=minifetch
[[ $- == *i* ]] && [ -z "$MINIFETCH_DONE" ] && { export MINIFETCH_DONE=1; minifetch; }
EOT

# reload: panel respawns on its own; metacity and nautilus are restarted by hand
pkill -u "$(id -un)" gnome-panel
setsid nohup metacity --replace >/dev/null 2>&1 </dev/null &
pkill -9 -u "$(id -un)" nautilus; sleep 2
setsid nohup nautilus --no-default-window >/dev/null 2>&1 </dev/null &
sleep 3
echo done
EOF

say "finished. Reopen terminals and apps to pick up the new theme."
