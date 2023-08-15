# Installing a VM on Freebox

Throughout this list, `jcdubacq` is my non-root login. Replace with the most appropriate for you.

1. Download the iso for architecture arm64 (not amd64, nor i386)
2. Since the setup only allows English locale, go for English, pretend you are in NYC. We will change that later. However, select the correct keymap (fr, for me).
3. Whole disk. This is a virtual machine on a set-top box. I used QCOW2 during creation because I/O performance is not an absolute goal, ease of management may come in handy later.
4. Setting up users is a mandatory step, but later we will remove password access and instead use SSH key access.
5. Task selection: only SSH server. Standard utilities will be added as needed.
6. Reboot
7. `dpkg-reconfigure locales` and select the correct ones (I always leave US locale, for tests).
8. Configure the network with the new MAC address (`ip a`), then renew the DHCP lease (`ifdown enp0s3; ifup enp0s3`). Also, because of a bug, `apt install ethtool; ethtool -K enp0s3 tx off rx off`. 
9. Setup [sudo](https://xkcd.com/149/) and review settings (`adduser jcdubacq sudo` and `%sudo	ALL=(ALL:ALL) NOPASSWD: ALL` for my personal taste).
10. Test ssh connection as normal user. `mkdir ~/.ssh;touch ~/.ssh/authorized_keys; chmod 700 ~/.ssh` and set up `authorized_keys` by copying a public key into it. Logout, and test connection is now with key exchange. Then issue `sudo passwd -l jcdubacq` (obviously, your own account). Test connection again. `sudo passwd -l root` can also be done, once you are confident SSH conection and sudo is working.
11. Because I like it this way: I uncomment the following lines in `/etc/adduser.conf`:
```
USERGROUPS=no
USERS_GID=100
USERS_GROUP=users
```
and I issue `usermod -g jcdubacq ; delgroup jcdubacq` to remove the notion of user groups.
11. Manuals: `apt install man; service man-db start` as root.
12. Timezone: edit `/etc/timezone` as root
13. Some utilities: `apt install bind9-host wget bash-completion rsync` and add `[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion to /root/.bashrc if you like it. While editing bashrc, you may want to append this standard snippet:
```sh
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac
```
14. Set up upgrades: `apt install unattended-upgrades`
15. Enjoy (your empty system)!
