# dwm version
VERSION = 6.5

# Customize below to fit your system

# paths
PREFIX = /usr/local
MANPREFIX = ${PREFIX}/share/man

OS := $(shell uname)
ifeq ($(OS), FreeBSD)
X11INC = /usr/local/include
X11LIB = /usr/local/lib
else
X11INC = /usr/X11R6/include
X11LIB = /usr/X11R6/lib
endif

# Xinerama, comment if you don't want it
XINERAMALIBS  = -lXinerama
XINERAMAFLAGS = -DXINERAMA

# freetype
FREETYPELIBS = -lfontconfig -lXft
ifeq ($(OS), FreeBSD)
FREETYPEINC = ${X11INC}/freetype2
else
FREETYPEINC = /usr/include/freetype2
endif
# OpenBSD (uncomment)
#FREETYPEINC = ${X11INC}/freetype2
#MANPREFIX = ${PREFIX}/man
#KVMLIB = -lkvm

# includes and libs
# tuxcraft: touchpad swipe between tags that follows the fingers. Needs libinput's and
# libudev's headers (Void: libinput-devel eudev-libudev-devel, Debian: libinput-dev libudev-dev,
# Arch: libinput); without them dwm builds without it.
ifeq ($(shell pkg-config --exists libinput libudev 2>/dev/null && echo y),y)
SWIPEFLAGS = -DTUXSWIPE $(shell pkg-config --cflags libinput libudev)
SWIPELIBS = $(shell pkg-config --libs libinput libudev) -lm
endif

INCS = -I${X11INC} -I${FREETYPEINC}
LIBS = -L${X11LIB} -lX11 ${XINERAMALIBS} ${FREETYPELIBS} -lX11-xcb -lxcb -lxcb-res ${KVMLIB} ${SWIPELIBS}

# flags
CPPFLAGS = -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -DVERSION=\"${VERSION}\" ${XINERAMAFLAGS} ${SWIPEFLAGS}
#CFLAGS   = -g -std=c99 -pedantic -Wall -O0 ${INCS} ${CPPFLAGS}
# tuxcraft: her bar and gap toggles are kept although no key uses them (tux-dwm cmd bar|gaps)
CFLAGS   = -std=c99 -pedantic -Wall -Wno-deprecated-declarations -Wno-unused-function -Os ${INCS} ${CPPFLAGS}
LDFLAGS  = ${LIBS}

# Solaris
#CFLAGS = -fast ${INCS} -DVERSION=\"${VERSION}\"
#LDFLAGS = ${LIBS}

# compiler and linker
CC = cc
