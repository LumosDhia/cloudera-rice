# cloudera-rice

One script that restyles the Cloudera QuickStart VM 5.12 (CentOS 6.7, GNOME 2) from the
host over SSH. It sets a wallpaper, a dark navy theme, Papirus-Dark icons, a matching
terminal and prompt, a tiny system-info tool, and a 125% UI scale.

![The restyled VM](screenshot.jpg)

## Usage

Start the VM, find its address with `ip a` inside it, then on the host:

```bash
./cloudera-rice.sh 192.168.159.161
./cloudera-rice.sh 192.168.159.161 --yum           # also fix yum and install htop
./cloudera-rice.sh 192.168.159.161 --no-icons      # skip the 33 MB icon copy
./cloudera-rice.sh 192.168.159.161 --wallpaper ~/Pictures/other.jpg
```

The script logs in as `cloudera` with password `cloudera` (override with `VM_USER` and
`VM_PASS`). It is safe to run again. After a run, reopen terminals and apps to see the new
theme everywhere.

Needs on the host: OpenSSH 8.4 or newer, `python3`, `curl`, `tar`. `python3-pil` is
optional and only used to recolour two desktop icons. The Papirus icons are copied from
`/usr/share/icons/Papirus` and `/usr/share/icons/Papirus-Dark` on the host, so install
`papirus-icon-theme` there first or pass `--no-icons`.
