# fix for screen readers (from Arch's releng profile)
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# tuxcraft: start the installer on the first console. Other consoles (Alt+F2...) are plain shells.
if [[ $(tty) == /dev/tty1 && -z ${TUXCRAFT_STARTED:-} ]]; then
    export TUXCRAFT_STARTED=1
    /usr/local/bin/tuxcraft-live
fi
