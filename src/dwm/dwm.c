/* See LICENSE file for copyright and license details.
 *
 * dynamic window manager is designed like any other X client as well. It is
 * driven through handling X events. In contrast to other X clients, a window
 * manager selects for SubstructureRedirectMask on the root window, to receive
 * events about window (dis-)appearance. Only one X connection at a time is
 * allowed to select for this event mask.
 *
 * The event handlers of dwm are organized in an array which is accessed
 * whenever a new event has been fetched. This allows event dispatching
 * in O(1) time.
 *
 * Each child of the root window is called a client, except windows which have
 * set the override_redirect flag. Clients are organized in a linked client
 * list on each monitor, the focus history is remembered through a stack list
 * on each monitor. Each client contains a bit array to indicate the tags of a
 * client.
 *
 * Keys and tagging rules are organized as arrays and defined in config.h.
 *
 * To understand everything else, start reading main().
 */
#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h> /* strncasecmp */
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <poll.h>
#include <time.h>
#ifdef TUXSWIPE
#include <fcntl.h>
#include <math.h>
#include <stdint.h>
#include <libinput.h>
#include <libudev.h>
#endif
#include <X11/cursorfont.h>
#include <X11/keysym.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xproto.h>
#include <X11/Xresource.h>
#include <X11/Xutil.h>
#ifdef XINERAMA
#include <X11/extensions/Xinerama.h>
#endif /* XINERAMA - multihead */
#include <X11/Xft/Xft.h>
#include <X11/Xlib-xcb.h>
#include <xcb/res.h>
#ifdef __OpenBSD__
#include <sys/sysctl.h>
#include <kvm.h>
#endif /* __OpenBSD */

#include "drw.h"
#include "util.h"

/* macros */
#define BUTTONMASK              (ButtonPressMask|ButtonReleaseMask)
#define CLEANMASK(mask)         (mask & ~(numlockmask|LockMask) & (ShiftMask|ControlMask|Mod1Mask|Mod2Mask|Mod3Mask|Mod4Mask|Mod5Mask))
#define GETINC(X)               ((X) - 2000)
#define INC(X)                  ((X) + 2000)
#define INTERSECT(x,y,w,h,m)    (MAX(0, MIN((x)+(w),(m)->wx+(m)->ww) - MAX((x),(m)->wx)) \
                               * MAX(0, MIN((y)+(h),(m)->wy+(m)->wh) - MAX((y),(m)->wy)))
#define ISINC(X)                ((X) > 1000 && (X) < 3000)
#define ISVISIBLE(C)            ((C->tags & C->mon->tagset[C->mon->seltags]) || C->issticky)
#define PREVSEL                 3000
#define MOD(N,M)                ((N)%(M) < 0 ? (N)%(M) + (M) : (N)%(M))
#define MOUSEMASK               (BUTTONMASK|PointerMotionMask)
#define WIDTH(X)                ((X)->w + 2 * (X)->bw)
#define HEIGHT(X)               ((X)->h + 2 * (X)->bw)
#define TAGMASK                 ((1 << LENGTH(tags)) - 1)
#define SPTAG                   (1 << LENGTH(tags)) /* tuxcraft: the hidden scratchpad tag */
#define TEXTW(X)                (drw_fontset_getwidth(drw, (X)) + lrpad)
#define XRDB_LOAD_COLOR(R,V)    if (XrmGetResource(xrdb, R, NULL, &type, &value) == True) { \
                                  if (value.addr != NULL && strnlen(value.addr, 8) == 7 && value.addr[0] == '#') { \
                                    int i = 1; \
                                    for (; i <= 6; i++) { \
                                      if (value.addr[i] < 48) break; \
                                      if (value.addr[i] > 57 && value.addr[i] < 65) break; \
                                      if (value.addr[i] > 70 && value.addr[i] < 97) break; \
                                      if (value.addr[i] > 102) break; \
                                    } \
                                    if (i == 7) { \
                                      strncpy(V, value.addr, 7); \
                                      V[7] = '\0'; \
                                    } \
                                  } \
                                }
#define TRUNC(X,A,B)            (MAX((A), MIN((X), (B))))

/* systray (dwm's systray patch, from BreadOnPenguins' dwm-systray.diff) */
#define SYSTEM_TRAY_REQUEST_DOCK    0
/* XEMBED messages */
#define XEMBED_EMBEDDED_NOTIFY      0
#define XEMBED_WINDOW_ACTIVATE      1
#define XEMBED_FOCUS_IN             4
#define XEMBED_MODALITY_ON         10
#define XEMBED_MAPPED              (1 << 0)
#define XEMBED_WINDOW_DEACTIVATE    2
#define VERSION_MAJOR               0
#define VERSION_MINOR               0
#define XEMBED_EMBEDDED_VERSION (VERSION_MAJOR << 16) | VERSION_MINOR


/* enums */
enum { CurNormal, CurResize, CurMove, CurLast }; /* cursor */
enum { SchemeNorm, SchemeSel, SchemeStatus, SchemeTagsSel, SchemeTagsNorm, SchemeInfoSel, SchemeInfoNorm }; /* color schemes */
enum { NetSupported, NetWMName, NetWMState, NetWMCheck,
       NetSystemTray, NetSystemTrayOP, NetSystemTrayOrientation, NetSystemTrayOrientationHorz,
       NetWMFullscreen, NetWMSticky, NetActiveWindow, NetWMWindowType,
       NetWMWindowTypeDialog, NetClientList, NetWMWindowTypeDock, NetWMWindowTypeMenu,
       NetWMWindowTypeNotification,
       NetNumberOfDesktops, NetCurrentDesktop, NetDesktopNames, NetWMDesktop, NetLast };
enum { Manager, Xembed, XembedInfo, XLast }; /* Xembed atoms */ /* EWMH atoms (extended window manager hints) */
enum { WMProtocols, WMDelete, WMState, WMTakeFocus, WMLast }; /* default atoms */
enum { ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle,
       ClkClientWin, ClkRootWin, ClkLast }; /* clicks */

typedef union {
	int i; /* integer argument */
	unsigned int ui; /* unsigned integer */
	float f; /* float */
	const void *v; /* generic pointer */
} Arg;

typedef struct { /* mouse button interactions */
	unsigned int click; /* where the click happened */
	unsigned int mask; /* modifier keys */
	unsigned int button; /* the mouse button used */
	void (*func)(const Arg *arg); /* a pointer to the function that should be executed */
	const Arg arg; /* argument to pass into the function */
} Button;

typedef struct Monitor Monitor;
typedef struct Client Client;
struct Client { /* a window that dwm is managing */
	char name[256]; /* window's title as shown in bar */
	float mina, maxa; /* min and max aspect ratios when resizing windows */
	int x, y, w, h; /* current pos of window */
	int oldx, oldy, oldw, oldh; /* prev pos of window */
	int basew, baseh, incw, inch, maxw, maxh, minw, minh, hintsvalid; /* size hints */
	int bw, oldbw; /* current and prev border widths */
	unsigned int tags; /* bitmasks for which tags window is visible on */
	int isfixed, isfloating, isurgent, neverfocus, oldstate, isfullscreen, issticky, isterminal, noswallow; /* window states */
	int isscratch; /* tuxcraft: sent to the scratchpad (Super+Shift+minus) */
	float cfact;   /* tuxcraft: share of its column (cfacts; 1 = equal), set by Super + right drag */
	int order;     /* tuxcraft: place in the tiling before a restart (-1: none), see sortclients() */
	int hidden;    /* tuxcraft: moved off screen (its tag is not shown); _TUX_DWM_HIDDEN is set */
	int glide;     /* tuxcraft: came back with its tag, _TUX_DWM_GLIDE is set until it next moves */
	int leaving;   /* tuxcraft: sliding out with its tag (leaveframe), from lx0 to lx1, then parked */
	int lx0, lx1, lpark;
	int still;     /* tuxcraft: being moved or resized by hand, _TUX_DWM_STILL is set (no animation) */
	long desktop; /* tuxcraft: last _NET_WM_DESKTOP written */
	pid_t pid; /* pid of application in window - useful for swallowing */
	Client *next; /* next client, in the linked list of all clients */
	Client *snext; /* next in the STACK */
	Client *swallowing; /* points to the client this one is swallowing (swallow patch) */
	Monitor *mon; /* the monitor this client is on */
	Window win; /* X11 win id */
};

typedef struct { /* key press interactions */
	unsigned int mod;
	KeySym keysym;
	void (*func)(const Arg *);
	const Arg arg;
} Key;

typedef struct { /* layouts */
	const char *symbol;
	void (*arrange)(Monitor *);
} Layout;

#define PERTAGSLOTS 32 /* tags (at most 31, see NumTags) + one for several tags at once */
struct Monitor {
	char ltsymbol[16];
	float mfact;
	int nmaster;
	int num;
	int by;               /* bar geometry */
	int mx, my, mw, mh;   /* screen size */
	int wx, wy, ww, wh;   /* window area  */
	int gappih;           /* horizontal gap between windows */
	int gappiv;           /* vertical gap between windows */
	int gappoh;           /* horizontal outer gaps */
	int gappov;           /* vertical outer gaps */
	unsigned int seltags;
	unsigned int sellt;
	unsigned int tagset[2];
	int showbar;
	int showtitle;
	int showtags;
	int showlayout;
	int showstatus;
	int showfloating;
	int topbar;
	Client *clients;
	Client *sel;
	Client *stack;
	Client *tagmarked[32];
	Monitor *next;
	Window barwin;
	const Layout *lt[2];
	/* tuxcraft: every tag keeps its own layout, master size and master count (dwm's pertag
	 * patch, by tag index; the last slot is for several tags viewed at once). Saved in
	 * ~/.local/state/tuxcraft/dwm-layouts, so restarts and new logins keep them too. */
	unsigned int ptlt[PERTAGSLOTS][2];
	unsigned int ptsellt[PERTAGSLOTS];
	float ptmfact[PERTAGSLOTS];
	int ptnmaster[PERTAGSLOTS];
};

typedef struct {
	const char *class;
	const char *instance;
	const char *title;
	unsigned int tags;
	int isfloating;
	int isterminal;
	int noswallow;
	int issticky;  /* tuxcraft: on every tag */
	int w, h;      /* tuxcraft: floating size in pixels (0 = the window's own); floats are centred */
	int monitor;
} Rule;

typedef struct Systray   Systray;
struct Systray {
	Window win;
	Client *icons;
};

/* function declarations */
static void applyrules(Client *c);
static int applysizehints(Client *c, int *x, int *y, int *w, int *h, int interact);
static void arrange(Monitor *m);
static void arrangemon(Monitor *m);
static void attach(Client *c);
static void attachstack(Client *c);
static void buttonpress(XEvent *e);
static void checkotherwm(void);
static void cleanup(void);
static void cleanupmon(Monitor *mon);
static void clientmessage(XEvent *e);
static void configure(Client *c);
static void configurenotify(XEvent *e);
static void configurerequest(XEvent *e);
static Monitor *createmon(void);
static void destroynotify(XEvent *e);
static void detach(Client *c);
static void detachstack(Client *c);
static Monitor *dirtomon(int dir);
static void drawbar(Monitor *m);
static void drawbars(void);
static void enternotify(XEvent *e);
static void expose(XEvent *e);
static void focus(Client *c);
static void focusin(XEvent *e);
static void focusmaster(const Arg *arg);
static void focusmon(const Arg *arg);
static void focusstack(const Arg *arg);
static Atom getatomprop(Client *c, Atom prop);
static int getrootptr(int *x, int *y);
static long getstate(Window w);
static unsigned int getsystraywidth();
static pid_t getstatusbarpid(void);
static void sigstatusbar(const Arg *arg);
static int gettextprop(Window w, Atom atom, char *text, unsigned int size);
static void grabbuttons(Client *c, int focused);
static void grabkeys(void);
static int ispanel(Client *c);
static int ispopup(Client *c);
static void incnmaster(const Arg *arg);
static void keypress(XEvent *e);
static void killthis(Client *c);
static void killclient(const Arg *arg);
static void loadxrdb(void);
static void manage(Window w, XWindowAttributes *wa);
static void mappingnotify(XEvent *e);
static void maprequest(XEvent *e);
static void monocle(Monitor *m);
static void motionnotify(XEvent *e);
static void movemouse(const Arg *arg);
static Client *nexttiled(Client *c);
static void pop(Client *c);
static void propertynotify(XEvent *e);
static void pushstack(const Arg *arg);
static void quit(const Arg *arg);
static Monitor *recttomon(int x, int y, int w, int h);
static void removesystrayicon(Client *i);
static void resize(Client *c, int x, int y, int w, int h, int interact);
static void resizebarwin(Monitor *m);
static void resizeclient(Client *c, int x, int y, int w, int h);
static void resizemouse(const Arg *arg);
static int rsbegin(Client *c);
static void rsstep(int dx, int dy);
static void rsend(void);
static void stillmark(Client *c, int on);
static void resizerequest(XEvent *e);
static void restack(Monitor *m);
static void run(void);
static void scan(void);
static int sendevent(Window w, Atom proto, int m, long d0, long d1, long d2, long d3, long d4);
static void sendmon(Client *c, Monitor *m);
static void setclientstate(Client *c, long state);
static void setfocus(Client *c);
static void setfullscreen(Client *c, int fullscreen);
static void setsticky(Client *c, int sticky);
static void setlayout(const Arg *arg);
static void setmfact(const Arg *arg);
static void setup(void);
static void seturgent(Client *c, int urg);
static void showhide(Client *c);
static void spawn(const Arg *arg);
static Monitor *systraytomon(Monitor *m);
static void spawntag(const Arg *arg);
static void sighup(int unused);
static void sigterm(int unused);
static int stackpos(const Arg *arg);
static void tag(const Arg *arg);
static void tagmon(const Arg *arg);
static void togglebar(const Arg *arg);
static void togglebarcolor(const Arg *arg);
static void togglebartags(const Arg *arg);
static void togglebartitle(const Arg *arg);
static void togglebarlt(const Arg *arg);
static void togglebarstatus(const Arg *arg);
static void togglebarfloat(const Arg *arg);
static void togglefloating(const Arg *arg);
static void togglefullscreen(const Arg *arg);
static void togglesticky(const Arg *arg);
static void toggletag(const Arg *arg);
static void toggleview(const Arg *arg);
static void unfocus(Client *c, int setfocus);
static void unmanage(Client *c, int destroyed);
static void unmapnotify(XEvent *e);
static void updatebarpos(Monitor *m);
static void updatebars(void);
static void updateclientlist(void);
static int updategeom(void);
static void updatenumlockmask(void);
static void updatesizehints(Client *c);
static void updatestatus(void);
static void updatesystray(void);
static void updatesystrayicongeom(Client *i, int w, int h);
static void updatesystrayiconstate(Client *i, XPropertyEvent *ev);
static void updatetitle(Client *c);
static void updatewindowtype(Client *c);
static void updatewmhints(Client *c);
static void view(const Arg *arg);
static Client *wintoclient(Window w);
static Monitor *wintomon(Window w);
static Client *wintosystrayicon(Window w);
static int xerror(Display *dpy, XErrorEvent *ee);
static int xerrordummy(Display *dpy, XErrorEvent *ee);
static int xerrorstart(Display *dpy, XErrorEvent *ee);
static void xrdb(const Arg *arg);
static void zoom(const Arg *arg);

/* tuxcraft additions: i3-style behaviour for tuxcraft's shared keybindings */
static void viewtag(const Arg *arg);
static void shiftviewocc(const Arg *arg);
static void setlayoutidx(const Arg *arg);
static void pertagload(Monitor *m, unsigned int ts);
static void movetiled(Client *c);
static void sortclients(void);
static void pertagkeep(Monitor *m);
static void pertagsave(void);
static void pertagread(void);
static void togglesplit(const Arg *arg);
static void togglefloatall(const Arg *arg);
static void scratchhide(const Arg *arg);
static void scratchshow(const Arg *arg);
static void movetagsmon(const Arg *arg);
static void resizemode(const Arg *arg);
static void resizedir(const Arg *arg);
static void tuxcmd(const char *cmd);
static void swipeinit(void);
static void swipecleanup(void);
static void swipeabort(void);
static int swipebusy(void);
static void leavestart(void);
static void updatedesktops(void);
static void savestate(void);
static int casestr(const char *hay, const char *needle);

static pid_t getparentprocess(pid_t p);
static int isdescprocess(pid_t p, pid_t c);
static Client *swallowingclient(Window w);
static Client *termforwin(const Client *c);
static pid_t winpid(Window w);

/* variables */
static Systray *systray = NULL;
static const char broken[] = "broken";
static char stext[1024]; /* tuxcraft: room for glyphs (4 bytes each) and a song title */
static int statusw;
static int statussig;
static pid_t statuspid = -1;
static int keymode = 0; /* tuxcraft: 1 = resize mode (Super+R) */
static Atom tuxcmdatom, tuxtagsatom, tuxviewatom, tuxhiddenatom, tuxglideatom, tuxstillatom;
static int leavenone; /* tuxcraft: park leaving windows at once (a touchpad drag already moved them) */
static int screen;
static int sw, sh;           /* X display screen geometry width, height */
static int bh;               /* bar height */
static int lrpad;            /* sum of left and right padding for text */
static int (*xerrorxlib)(Display *, XErrorEvent *);
static int renderop = -1; /* tuxcraft: the RENDER extension's request code (xerror) */
static unsigned int numlockmask = 0;
static void (*handler[LASTEvent]) (XEvent *) = { /* maps X event type to matching function */
	[ButtonPress] = buttonpress, /* mouse button */
	[ClientMessage] = clientmessage, /* messages sent from windows, like fullscreen toggle */
	[ConfigureRequest] = configurerequest, /* window (client) asks to change geometry */
	[ConfigureNotify] = configurenotify, /* root window geom changes */
	[DestroyNotify] = destroynotify, /* window closed - removes client from dwm */
	[EnterNotify] = enternotify, /* mouse enters a window */
	[Expose] = expose, /* a part of the window needs to be redrawn */
	[FocusIn] = focusin,
	[KeyPress] = keypress, /* keyboard */
	[MappingNotify] = mappingnotify, /* keyboard mapping change */
	[MapRequest] = maprequest, /* a new window needs to be mapped */
	[MotionNotify] = motionnotify, /* mouse movement */
	[PropertyNotify] = propertynotify, /* window property changes */
	[ResizeRequest] = resizerequest,
	[UnmapNotify] = unmapnotify /* window needs to be unmapped */
};
static Atom wmatom[WMLast], netatom[NetLast], xatom[XLast];
static int restart = 0;
static int running = 1;
static Cur *cursor[CurLast];
static Clr **scheme;
static Display *dpy;
static Drw *drw;
static Monitor *mons, *selmon;
static Window root, wmcheckwin;

static xcb_connection_t *xcon;

/* configuration, allows nested code to access above variables */
#include "config.h"

/* compile-time check if all tags fit into an unsigned int bit array. */
struct NumTags { char limitexceeded[LENGTH(tags) > 30 ? -1 : 1]; }; /* one bit is left for the scratchpad */

/* function implementations */
void
applyrules(Client *c)
{
	const char *class, *instance;
	unsigned int i;
	const Rule *r;
	Monitor *m;
	XClassHint ch = { NULL, NULL };

	/* rule matching */
	c->isfloating = 0;
	c->tags = 0;
	XGetClassHint(dpy, c->win, &ch);
	class    = ch.res_class ? ch.res_class : broken;
	instance = ch.res_name  ? ch.res_name  : broken;

	for (i = 0; i < LENGTH(rules); i++) {
		r = &rules[i];
		if ((!r->title || casestr(c->name, r->title))
		&& (!r->class || casestr(class, r->class))
		&& (!r->instance || casestr(instance, r->instance)))
		{
			c->isterminal = r->isterminal;
			c->noswallow  = r->noswallow;
			if (r->isfloating)
				c->isfloating = 1;
			if (r->issticky)
				c->issticky = 1;
			if (r->w > 0 && r->h > 0) {
				c->w = r->w;
				c->h = r->h;
			}
			c->tags |= r->tags;
			for (m = mons; m && m->num != r->monitor; m = m->next);
			if (m)
				c->mon = m;
		}
	}
	if (ch.res_class)
		XFree(ch.res_class);
	if (ch.res_name)
		XFree(ch.res_name);
	c->tags = c->tags & TAGMASK ? c->tags & TAGMASK : c->mon->tagset[c->mon->seltags];
	if (c->isfloating) { /* tuxcraft: floating rules open centred, like i3's "move position center" */
		c->x = c->mon->wx + (c->mon->ww - WIDTH(c)) / 2;
		c->y = c->mon->wy + (c->mon->wh - HEIGHT(c)) / 2;
	}
}

int
applysizehints(Client *c, int *x, int *y, int *w, int *h, int interact)
{
	int baseismin;
	Monitor *m = c->mon;

	/* set minimum possible */
	*w = MAX(1, *w);
	*h = MAX(1, *h);
	if (interact) {
		if (*x > sw)
			*x = sw - WIDTH(c);
		if (*y > sh)
			*y = sh - HEIGHT(c);
		if (*x + *w + 2 * c->bw < 0)
			*x = 0;
		if (*y + *h + 2 * c->bw < 0)
			*y = 0;
	} else {
		if (*x >= m->wx + m->ww)
			*x = m->wx + m->ww - WIDTH(c);
		if (*y >= m->wy + m->wh)
			*y = m->wy + m->wh - HEIGHT(c);
		if (*x + *w + 2 * c->bw <= m->wx)
			*x = m->wx;
		if (*y + *h + 2 * c->bw <= m->wy)
			*y = m->wy;
	}
	if (*h < bh)
		*h = bh;
	if (*w < bh)
		*w = bh;
	if (resizehints || c->isfloating || !c->mon->lt[c->mon->sellt]->arrange) {
		if (!c->hintsvalid)
			updatesizehints(c);
		/* see last two sentences in ICCCM 4.1.2.3 */
		baseismin = c->basew == c->minw && c->baseh == c->minh;
		if (!baseismin) { /* temporarily remove base dimensions */
			*w -= c->basew;
			*h -= c->baseh;
		}
		/* adjust for aspect limits */
		if (c->mina > 0 && c->maxa > 0) {
			if (c->maxa < (float)*w / *h)
				*w = *h * c->maxa + 0.5;
			else if (c->mina < (float)*h / *w)
				*h = *w * c->mina + 0.5;
		}
		if (baseismin) { /* increment calculation requires this */
			*w -= c->basew;
			*h -= c->baseh;
		}
		/* adjust for increment value */
		if (c->incw)
			*w -= *w % c->incw;
		if (c->inch)
			*h -= *h % c->inch;
		/* restore base dimensions */
		*w = MAX(*w + c->basew, c->minw);
		*h = MAX(*h + c->baseh, c->minh);
		if (c->maxw)
			*w = MIN(*w, c->maxw);
		if (c->maxh)
			*h = MIN(*h, c->maxh);
	}
	return *x != c->x || *y != c->y || *w != c->w || *h != c->h;
}

void
arrange(Monitor *m) /* if a specific monitor *m is given, it arranges that one. if NULL, it loops thru all */
{
	XEvent ev; /* declares a generic X event */
	swipeabort(); /* tuxcraft: a touchpad drag between tags stops where it is */
	if (m)
		showhide(m->stack); /* show visible windows and hide others */
	else for (m = mons; m; m = m->next)
		showhide(m->stack);
	if (m) { /* if *m is a single monitor */
		arrangemon(m); /* applies the current layout to windows (tile, spiral, etc)*/
		restack(m); /* proper stacking order --> focused window on top */
	} else { /* else if *m was NULL */
		for (m = mons; m; m = m->next) /* loop through all monitors */
			arrangemon(m); /* apply layout to each monitor */
		XSync(dpy, False); /* ensure X server processed all commands (cleaning up) */
		while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
	}
	updatedesktops();
}

void
arrangemon(Monitor *m)
{ /* applies current layout to window on monitor *m */
	strncpy(m->ltsymbol, m->lt[m->sellt]->symbol, sizeof m->ltsymbol); /* copies layout symbol string to show in bar */
	if (m->lt[m->sellt]->arrange) /* if the layout has an associated arrange func, call it (ex. tile() )*/
		m->lt[m->sellt]->arrange(m);
}

void
attach(Client *c)
{
	c->next = c->mon->clients;
	c->mon->clients = c;
}

void
attachstack(Client *c)
{
	c->snext = c->mon->stack;
	c->mon->stack = c;
}

void
swallow(Client *p, Client *c)
{

	if (c->noswallow || c->isterminal)
		return;
	if (c->noswallow && !swallowfloating && c->isfloating)
		return;

	detach(c);
	detachstack(c);

	setclientstate(c, WithdrawnState);
	XUnmapWindow(dpy, p->win);

	p->swallowing = c;
	c->mon = p->mon;

	Window w = p->win;
	p->win = c->win;
	c->win = w;
	updatetitle(p);
	XMoveResizeWindow(dpy, p->win, p->x, p->y, p->w, p->h);
	arrange(p->mon);
	configure(p);
	updateclientlist();
}

void
unswallow(Client *c)
{
	c->win = c->swallowing->win;

	free(c->swallowing);
	c->swallowing = NULL;

	/* unfullscreen the client */
	setfullscreen(c, 0);
	updatetitle(c);
	arrange(c->mon);
	XMapWindow(dpy, c->win);
	XMoveResizeWindow(dpy, c->win, c->x, c->y, c->w, c->h);
	setclientstate(c, NormalState);
	focus(NULL);
	arrange(c->mon);
}

/* tuxcraft: colours in the status text. "^c#rrggbb^" draws what follows in that colour, "^d^"
 * goes back to the bar's own (tux-dwmbar colours the block icons with the theme's palette). */
static int
statuscolor(const char *name, Clr *c)
{
	static struct { char name[8]; Clr clr; } cache[32];
	static unsigned int n;
	unsigned int i;

	for (i = 0; i < n; i++)
		if (!strcmp(cache[i].name, name)) {
			*c = cache[i].clr;
			return 1;
		}
	if (n == LENGTH(cache) || !XftColorAllocName(dpy, DefaultVisual(dpy, screen),
	    DefaultColormap(dpy, screen), name, &cache[n].clr))
		return 0;
	strcpy(cache[n].name, name);
	*c = cache[n++].clr;
	return 1;
}

/* The width of one block's text without its colour markers; draws it at x too when draw is set.
 * The pieces are drawn right to left: an icon is often wider than its advance, and drawing the
 * piece after it (which fills its own background) would cut off the icon's right edge. */
static int
statustext(char *text, int x, int draw)
{
	struct { char *s; int len, x, w; Clr fg; } seg[64];
	char *s = text, *e, *end = NULL, ch, name[8];
	int w = 0, n = 0, i;
	Clr fg = scheme[SchemeStatus][ColFg], scm[3];

	while (*s && n < (int)LENGTH(seg)) {
		for (e = s; *e; e++) /* a piece runs to the next marker; a lone "^" is just text */
			if (*e == '^' && (end = strchr(e + 1, '^'))
			&& ((e[1] == 'c' && e[2] == '#' && end - e == 9) || (e[1] == 'd' && end == e + 2)))
				break;
		if (e > s) {
			ch = *e;
			*e = '\0';
			seg[n].s = s;
			seg[n].len = e - s;
			seg[n].x = w;
			seg[n].w = TEXTW(s) - lrpad;
			seg[n].fg = fg;
			w += seg[n++].w;
			*e = ch;
		}
		if (!*e)
			break;
		fg = scheme[SchemeStatus][ColFg];
		if (e[1] == 'c') {
			memcpy(name, e + 2, 7);
			name[7] = '\0';
			statuscolor(name, &fg);
		}
		s = end + 1;
	}
	if (!draw)
		return w;
	memcpy(scm, scheme[SchemeStatus], sizeof scm);
	drw_setscheme(drw, scm);
	for (i = n - 1; i >= 0; i--) {
		ch = seg[i].s[seg[i].len];
		seg[i].s[seg[i].len] = '\0';
		scm[ColFg] = seg[i].fg;
		drw_text(drw, x + seg[i].x, 0, seg[i].w, bh, 0, seg[i].s, 0);
		seg[i].s[seg[i].len] = ch;
	}
	drw_setscheme(drw, scheme[SchemeStatus]);
	return w;
}

void
buttonpress(XEvent *e)
{ /* handles clickable areas on the bar */
	unsigned int i, x, click;
	Arg arg = {0};
	Client *c;
	Monitor *m;
	XButtonPressedEvent *ev = &e->xbutton;
	char *text, *s, ch;

	click = ClkRootWin;
	/* focus monitor if necessary */
	if ((m = wintomon(ev->window)) && m != selmon) {
		unfocus(selmon->sel, 1);
		selmon = m;
		focus(NULL);
	}
	if (ev->window == selmon->barwin) {
		i = x = 0;
		unsigned int occ = 0;
		for(c = m->clients; c; c=c->next)
			occ |= c->tags == TAGMASK ? 0 : c->tags;
		do {
			/* do not reserve space for vacant tags */
			if (!(occ & 1 << i || m->tagset[m->seltags] & 1 << i))
				continue;
		    if (selmon->showtags)
				x += TEXTW(tags[i]);
		} while (ev->x >= x && ++i < LENGTH(tags));
		if (i < LENGTH(tags) && selmon->showtags) {
			click = ClkTagBar;
			arg.ui = 1 << i;
		} else if (ev->x < x + TEXTW(selmon->ltsymbol) && selmon->showlayout)
			click = ClkLtSymbol;
		else if (ev->x > selmon->ww - statusw - getsystraywidth() && selmon->showstatus) {
			x = selmon->ww - statusw - getsystraywidth();
			click = ClkStatusText;
			statussig = 0; /* statuscmd stuff */
			for (text = s = stext; *s && x <= ev->x; s++) { /* loop through to determine which block was clicked */
				if ((unsigned char)(*s) < ' ') { /* sig delim, if block boundaries are off check this */
					ch = *s; /* measure width */
					*s = '\0';
					x += statustext(text, 0, 0); /* debug test try (lrpad / 2) */
					*s = ch;
					text = s + 1; /* move text to next char after delim */
					if (x >= ev->x) /* check click pos */
						break;
					statussig = ch; /* save control char as sig # */
						}
				}
		} else
			click = ClkWinTitle;
	}
		if ((c = wintoclient(ev->window))) {
		focus(c);
		restack(selmon);
		XAllowEvents(dpy, ReplayPointer, CurrentTime);
		click = ClkClientWin;
	}
	for (i = 0; i < LENGTH(buttons); i++)
		if (click == buttons[i].click && buttons[i].func && buttons[i].button == ev->button
		&& CLEANMASK(buttons[i].mask) == CLEANMASK(ev->state))
			buttons[i].func(click == ClkTagBar && buttons[i].arg.i == 0 ? &arg : &buttons[i].arg);
}

void
checkotherwm(void)
{
	xerrorxlib = XSetErrorHandler(xerrorstart);
	/* this causes an error if some other window manager is running */
	XSelectInput(dpy, DefaultRootWindow(dpy), SubstructureRedirectMask);
	XSync(dpy, False);
	XSetErrorHandler(xerror);
	XSync(dpy, False);
}

void
cleanup(void)
{ /* called when dwm exits normally or thru restart */
	Arg a = {.ui = ~0}; /* switches to viewing all windows before shutdown */
	Layout foo = { "", NULL }; /* switches layout to NULL so no more layout logic is ran */
	Monitor *m;
	size_t i;

	swipecleanup();
	view(&a);
	selmon->lt[selmon->sellt] = &foo;
	for (m = mons; m; m = m->next) /* loop through every monitor */
		while (m->stack) /* call unmanage on every client window in the stack */
			unmanage(m->stack, 0);
	XUngrabKey(dpy, AnyKey, AnyModifier, root); /* releases all X keybindings */
	while (mons)
		cleanupmon(mons);

	if (showsystray) {
		XUnmapWindow(dpy, systray->win);
		XDestroyWindow(dpy, systray->win);
		free(systray);
	}

	for (i = 0; i < CurLast; i++)
		drw_cur_free(drw, cursor[i]);
	for (i = 0; i < LENGTH(colors); i++)
		free(scheme[i]);
	free(scheme);
	XDestroyWindow(dpy, wmcheckwin);
	drw_free(drw);
	XSync(dpy, False); /* flushes all X requests */
	XSetInputFocus(dpy, PointerRoot, RevertToPointerRoot, CurrentTime); /* reverts keyboard focus to root win */
	XDeleteProperty(dpy, root, netatom[NetActiveWindow]);
}

void
cleanupmon(Monitor *mon)
{
	Monitor *m;

	if (mon == mons)
		mons = mons->next;
	else {
		for (m = mons; m && m->next != mon; m = m->next);
		m->next = mon->next;
	}
	XUnmapWindow(dpy, mon->barwin); /* hides statusbar associated w/ monitor */
	XDestroyWindow(dpy, mon->barwin); /* deletes bar window from X server entirely */
	free(mon); /* free memory */
}

void
clientmessage(XEvent *e)
{
	XWindowAttributes wa;
	XSetWindowAttributes swa;
	XClientMessageEvent *cme = &e->xclient;
	Client *c = wintoclient(cme->window);

	if (showsystray && cme->window == systray->win && cme->message_type == netatom[NetSystemTrayOP]) {
		/* add systray icons */
		if (cme->data.l[1] == SYSTEM_TRAY_REQUEST_DOCK) {
			if (!(c = (Client *)calloc(1, sizeof(Client))))
				die("fatal: could not malloc() %u bytes\n", sizeof(Client));
			if (!(c->win = cme->data.l[2])) {
				free(c);
				return;
			}
			c->mon = selmon;
			c->next = systray->icons;
			systray->icons = c;
			if (!XGetWindowAttributes(dpy, c->win, &wa)) {
				/* use sane defaults */
				wa.width = bh;
				wa.height = bh;
				wa.border_width = 0;
			}
			c->x = c->oldx = c->y = c->oldy = 0;
			c->w = c->oldw = wa.width;
			c->h = c->oldh = wa.height;
			c->oldbw = wa.border_width;
			c->bw = 0;
			c->isfloating = True;
			/* reuse tags field as mapped status */
			c->tags = 1;
			updatesizehints(c);
			updatesystrayicongeom(c, wa.width, wa.height);
			XAddToSaveSet(dpy, c->win);
			XSelectInput(dpy, c->win, StructureNotifyMask | PropertyChangeMask | ResizeRedirectMask);
			XReparentWindow(dpy, c->win, systray->win, 0, 0);
			/* use parents background color */
			swa.background_pixel  = scheme[SchemeNorm][ColBg].pixel;
			XChangeWindowAttributes(dpy, c->win, CWBackPixel, &swa);
			sendevent(c->win, netatom[Xembed], StructureNotifyMask, CurrentTime, XEMBED_EMBEDDED_NOTIFY, 0 , systray->win, XEMBED_EMBEDDED_VERSION);
			/* FIXME not sure if I have to send these events, too */
			sendevent(c->win, netatom[Xembed], StructureNotifyMask, CurrentTime, XEMBED_FOCUS_IN, 0 , systray->win, XEMBED_EMBEDDED_VERSION);
			sendevent(c->win, netatom[Xembed], StructureNotifyMask, CurrentTime, XEMBED_WINDOW_ACTIVATE, 0 , systray->win, XEMBED_EMBEDDED_VERSION);
			sendevent(c->win, netatom[Xembed], StructureNotifyMask, CurrentTime, XEMBED_MODALITY_ON, 0 , systray->win, XEMBED_EMBEDDED_VERSION);
			XSync(dpy, False);
			resizebarwin(selmon);
			updatesystray();
			setclientstate(c, NormalState);
		}
		return;
	}


	if (!c)
		return;
	if (cme->message_type == netatom[NetWMState]) {
		if (cme->data.l[1] == netatom[NetWMFullscreen]
		|| cme->data.l[2] == netatom[NetWMFullscreen])
			setfullscreen(c, (cme->data.l[0] == 1
				|| (cme->data.l[1] == 2 && !c->isfullscreen)));

		if (cme->data.l[1] == netatom[NetWMSticky]
				|| cme->data.l[2] == netatom[NetWMSticky])
			setsticky(c, (cme->data.l[0] == 1 || (cme->data.l[0] == 2 && !c->issticky)));
	} else if (cme->message_type == netatom[NetActiveWindow]) {
		/* tuxcraft: go to the window's tag and focus it (rofi -show window, xdotool, apps) */
		if (c->isscratch && !ISVISIBLE(c)) {
			c->tags = c->mon->tagset[c->mon->seltags];
		} else if (!ISVISIBLE(c)) {
			Arg a = {.ui = c->tags & TAGMASK};
			if (c->mon != selmon) {
				unfocus(selmon->sel, 0);
				selmon = c->mon;
			}
			if (a.ui)
				view(&a);
		}
		if (c->mon != selmon) {
			unfocus(selmon->sel, 0);
			selmon = c->mon;
		}
		focus(c);
		arrange(c->mon);
	}
}

void
configure(Client *c)
{
	XConfigureEvent ce;

	ce.type = ConfigureNotify;
	ce.display = dpy;
	ce.event = c->win;
	ce.window = c->win;
	ce.x = c->x;
	ce.y = c->y;
	ce.width = c->w;
	ce.height = c->h;
	ce.border_width = c->bw;
	ce.above = None;
	ce.override_redirect = False;
	XSendEvent(dpy, c->win, False, StructureNotifyMask, (XEvent *)&ce);
}

void
configurenotify(XEvent *e)
{
	Monitor *m;
	Client *c;
	XConfigureEvent *ev = &e->xconfigure;
	int dirty;

	/* TODO: updategeom handling sucks, needs to be simplified */
	if (ev->window == root) {
		dirty = (sw != ev->width || sh != ev->height);
		sw = ev->width;
		sh = ev->height;
		if (updategeom() || dirty) {
			drw_resize(drw, sw, bh);
			updatebars();
			for (m = mons; m; m = m->next) {
				for (c = m->clients; c; c = c->next)
					if (c->isfullscreen)
						resizeclient(c, m->mx, m->my, m->mw, m->mh);
				resizebarwin(m);
			}
			focus(NULL);
			arrange(NULL);
		}
	}
}

void
configurerequest(XEvent *e)
{
	Client *c;
	Monitor *m;
	XConfigureRequestEvent *ev = &e->xconfigurerequest;
	XWindowChanges wc;

	if ((c = wintoclient(ev->window))) {
		if (ev->value_mask & CWBorderWidth)
			c->bw = ev->border_width;
		else if (c->isfloating || !selmon->lt[selmon->sellt]->arrange) {
			m = c->mon;
			if (ev->value_mask & CWX) {
				c->oldx = c->x;
				c->x = m->mx + ev->x;
			}
			if (ev->value_mask & CWY) {
				c->oldy = c->y;
				c->y = m->my + ev->y;
			}
			if (ev->value_mask & CWWidth) {
				c->oldw = c->w;
				c->w = ev->width;
			}
			if (ev->value_mask & CWHeight) {
				c->oldh = c->h;
				c->h = ev->height;
			}
			if ((c->x + c->w) > m->mx + m->mw && c->isfloating)
				c->x = m->mx + (m->mw / 2 - WIDTH(c) / 2); /* center in x direction */
			if ((c->y + c->h) > m->my + m->mh && c->isfloating)
				c->y = m->my + (m->mh / 2 - HEIGHT(c) / 2); /* center in y direction */
			if ((ev->value_mask & (CWX|CWY)) && !(ev->value_mask & (CWWidth|CWHeight)))
				configure(c);
			if (ISVISIBLE(c))
				XMoveResizeWindow(dpy, c->win, c->x, c->y, c->w, c->h);
		} else
			configure(c);
	} else {
		wc.x = ev->x;
		wc.y = ev->y;
		wc.width = ev->width;
		wc.height = ev->height;
		wc.border_width = ev->border_width;
		wc.sibling = ev->above;
		wc.stack_mode = ev->detail;
		XConfigureWindow(dpy, ev->window, ev->value_mask, &wc);
	}
	XSync(dpy, False);
}

Monitor *
createmon(void)
{
	Monitor *m;

	m = ecalloc(1, sizeof(Monitor));
	m->tagset[0] = m->tagset[1] = 1;
	m->mfact = mfact;
	m->nmaster = nmaster;
	m->showbar = showbar;
	m->showtitle = showtitle;
	m->showtags = showtags;
	m->showlayout = showlayout;
	m->showstatus = showstatus;
	m->showfloating = showfloating;
	m->topbar = topbar;
	m->gappih = gappih;
	m->gappiv = gappiv;
	m->gappoh = gappoh;
	m->gappov = gappov;
	m->lt[0] = &layouts[0];
	m->lt[1] = &layouts[1 % LENGTH(layouts)];
	strncpy(m->ltsymbol, layouts[0].symbol, sizeof m->ltsymbol);
	for (int s = 0; s < PERTAGSLOTS; s++) {
		m->ptlt[s][0] = 0;
		m->ptlt[s][1] = 1 % LENGTH(layouts);
		m->ptsellt[s] = 0;
		m->ptmfact[s] = mfact;
		m->ptnmaster[s] = nmaster;
	}
	return m;
}

void
destroynotify(XEvent *e)
{
	Client *c;
	XDestroyWindowEvent *ev = &e->xdestroywindow;

	if ((c = wintoclient(ev->window)))
		unmanage(c, 1);

	else if ((c = wintosystrayicon(ev->window))) {
		removesystrayicon(c);
		resizebarwin(selmon);
		updatesystray();
	}

	else if ((c = swallowingclient(ev->window)))
		unmanage(c->swallowing, 1);
}

void
detach(Client *c)
{
	Client **tc;

	for (int i = 1; i < LENGTH(tags); i++)
		if (c == c->mon->tagmarked[i])
			c->mon->tagmarked[i] = NULL;

	for (tc = &c->mon->clients; *tc && *tc != c; tc = &(*tc)->next);
	*tc = c->next;
}

void
detachstack(Client *c)
{
	Client **tc, *t;

	for (tc = &c->mon->stack; *tc && *tc != c; tc = &(*tc)->snext);
	*tc = c->snext;

	if (c == c->mon->sel) {
		for (t = c->mon->stack; t && !ISVISIBLE(t); t = t->snext);
		c->mon->sel = t;
	}
}

Monitor *
dirtomon(int dir)
{
	Monitor *m = NULL;

	if (dir > 0) {
		if (!(m = selmon->next))
			m = mons;
	} else if (selmon == mons)
		for (m = mons; m->next; m = m->next);
	else
		for (m = mons; m->next != selmon; m = m->next);
	return m;
}

void
drawbar(Monitor *m) /* take a pointer to the monitor we want to draw the bar on */
{
	int x, w, tw = 0, stw = 0; /* x pos, width, text width, and systray width */
	int boxs = drw->fonts->h / 9; /* the little square box for indicators */
	int boxw = drw->fonts->h / 6 + 2;
	unsigned int i, occ = 0, urg = 0; /* track which tags are in use and which are urgent */
	Client *c; /* pointer to iterate over list of windows on this monitor */

	if (!m->showbar) /* if the bar is hidden, do not draw it */
		return;

	if(showsystray && m == systraytomon(m) && !systrayonleft)
		stw = getsystraywidth();

	/* draw status first so it can be overdrawn by tags later */
	if (m == selmon && selmon->showstatus) { /* status is only drawn on selected monitor */
		char *text, *s, ch;
		drw_setscheme(drw, scheme[SchemeStatus]); /* set the colorscheme used by the drawing context */
		x = 0; /* keep track of horiz pos whil drawing */
		for (text = s = stext; *s; s++) { /* this loop handles the dwmblocks clickable blocks */
			if ((unsigned char)(*s) < ' ') { /* ctrl chars (ASCII < 32) are used to separate click events */
				ch = *s;
				*s = '\0';
				x += statustext(text, m->ww - statusw + x - stw, 1);
				*s = ch;
				text = s + 1;
			}
		}
		x += statustext(text, m->ww - statusw + x - stw, 1);
		drw_rect(drw, m->ww - statusw + x - stw, 0, 2, bh, 1, 1); /* 2px extra right padding */
		tw = statusw;
	}

	resizebarwin(m);

	for (c = m->clients; c; c = c->next) { /* drawing tag indicators */
		// preven tshowing the panel as active application
		if (ispanel(c))
			continue;
		occ |= c->tags == TAGMASK ? 0 : c->tags; /* if a client has all tags, skip it */
		if (c->isurgent && selmon->showtags)
			urg |= c->tags;
	}
	x = 0;
	for (i = 0; i < LENGTH(tags); i++) { /* loop over each tag */
		if(!(occ & 1 << i || m->tagset[m->seltags] & 1 << i)) /* do not draw vacant tags */
			continue;
		if (selmon->showtags) {
				w = TEXTW(tags[i]);
				drw_setscheme(drw, scheme[m->tagset[m->seltags] & 1 << i ? SchemeTagsSel : SchemeTagsNorm]);
				drw_text(drw, x, 0, w, bh, lrpad / 2, tags[i], urg & 1 << i);
				if (occ & 1 << i && selmon->showfloating) /* if tag has a win and showfloating is enabled, draw the floating indicator */
				drw_rect(drw, x + boxs, boxs, boxw, boxw,
						m == selmon && selmon->sel && selmon->sel->tags & 1 << i,
						urg & 1 << i);
				x += w; /* move cursor to the right to prepare for drawing next tag */
		}
    }
	
	/* draw layout indicator if selmon->showlayout */
	if (selmon->showlayout) {
		/* tuxcraft: "resize" while resize mode (Super+R) is on, like i3's mode indicator */
		const char *lt = keymode && m == selmon ? "resize" : m->ltsymbol;
		w = TEXTW(lt);
		drw_setscheme(drw, scheme[keymode && m == selmon ? SchemeSel : SchemeTagsNorm]);
		x = drw_text(drw, x, 0, w, bh, lrpad / 2, lt, 0);
	}


	if ((w = m->ww - tw - stw - x) > bh) {
		if (m->sel && selmon->showtitle) {
			drw_setscheme(drw, scheme[m == selmon ? SchemeInfoSel : SchemeInfoNorm]);
			drw_text(drw, x, 0, w, bh, lrpad / 2, m->sel->name, 0);
			if (m->sel->isfloating && selmon->showfloating)
				drw_rect(drw, x + boxs, boxs, boxw, boxw, m->sel->isfixed, 0);
		} else {
			drw_setscheme(drw, scheme[SchemeInfoNorm]);
			drw_rect(drw, x, 0, w, bh, 1, 1);
		}
	}
	drw_map(drw, m->barwin, 0, 0, m->ww - stw, bh);
}

void
drawbars(void)
{ /* loop through every monitor to redraw statusbar */
	Monitor *m;

	for (m = mons; m; m = m->next)
		drawbar(m);
}

void
enternotify(XEvent *e)
{
	Client *c;
	Monitor *m;
	XCrossingEvent *ev = &e->xcrossing;

	if (swipebusy()) /* tuxcraft: windows slide under the pointer during a touchpad drag */
		return;
	if ((c = wintoclient(ev->window)) && c->leaving) /* tuxcraft: sliding out with its tag */
		return;
	if ((ev->mode != NotifyNormal || ev->detail == NotifyInferior) && ev->window != root)
		return;
	c = wintoclient(ev->window);
	m = c ? c->mon : wintomon(ev->window);
	if (m != selmon) {
		unfocus(selmon->sel, 1);
		selmon = m;
	} else if (!c || c == selmon->sel)
		return;
	focus(c);
}

void
expose(XEvent *e)
{
	Monitor *m;
	XExposeEvent *ev = &e->xexpose;

	if (ev->count == 0 && (m = wintomon(ev->window))) {
		drawbar(m);
		if (m == selmon)
			updatesystray();
	}
}

void
focus(Client *c)
{ /* handling when focus shifts to a different client */
	if (!c || !ISVISIBLE(c)) /* if the target client c isn't visible, */
		for (c = selmon->stack; c && !ISVISIBLE(c); c = c->snext); /* search the stack for the next visible one to focus */
	if (selmon->sel && selmon->sel != c) /* if there's a selected window that is not c, */
		unfocus(selmon->sel, 0); /* unfocus it */
	if (c) {
		if (c->mon != selmon) /* if the new client c is on a different monitor, */
			selmon = c->mon; /* switch selmon (selected monitor) to that monitor */
		if (c->isurgent) /* if urgent state was marked, */
			seturgent(c, 0); /* clear urgent state */
		// prevents the pnel getting focus when tag switching:
		if (!ispanel(c)) {
		    detachstack(c);
		    attachstack(c); /* move c to top of the stack */
		    grabbuttons(c, 1);
		    XSetWindowBorder(dpy, c->win, scheme[SchemeSel][ColBorder].pixel);
		    setfocus(c); /* inform X11 that c now has input focus */
		}
	} else {
		XSetInputFocus(dpy, selmon->barwin, RevertToPointerRoot, CurrentTime);
		XDeleteProperty(dpy, root, netatom[NetActiveWindow]);
	}
	if(selmon->sel && selmon->sel->isfullscreen){ /* if previous client was fullscreen, toggle off and then back for the new */
		togglefullscreen(NULL);
		selmon->sel = c;
		togglefullscreen(NULL);
	}else{
		selmon->sel = c;
	}
	drawbars(); /* redraw statusbar */
}

/* there are some broken focus acquiring clients needing extra handling */
void
focusin(XEvent *e)
{ /* when a window receives focus */
	XFocusChangeEvent *ev = &e->xfocus;

	if (selmon->sel && ev->window != selmon->sel->win)
		setfocus(selmon->sel);
}

void
focusmaster(const Arg *arg)
{
	Client *master;

	if (selmon->nmaster > 1)
		return;
	if (!selmon->sel || (selmon->sel->isfullscreen && lockfullscreen))
		return;

	master = nexttiled(selmon->clients);

	if (!master)
		return;

	int i;
	for (i = 0; !(selmon->tagset[selmon->seltags] & 1 << i); i++);
	i++;

	if (selmon->sel == master) {
		if (selmon->tagmarked[i] && ISVISIBLE(selmon->tagmarked[i]))
			focus(selmon->tagmarked[i]);
	} else {
		selmon->tagmarked[i] = selmon->sel;
		focus(master);
	}
}

void
focusmon(const Arg *arg)
{
	Monitor *m;

	if (!mons->next)
		return;
	if ((m = dirtomon(arg->i)) == selmon)
		return;
	unfocus(selmon->sel, 0);
	XWarpPointer(dpy, None, m->barwin, 0, 0, 0, 0, m->mw / 2, m->mh / 2);
	selmon = m;
	focus(NULL);
}

int focussed_panel = 0; // helper for focusstack, avoids loops when panel is the only client
void
focusstack(const Arg *arg)
{
	int i = stackpos(arg);
	Client *c, *p;
 
	if(i < 0)
		return;
	for(p = NULL, c = selmon->clients; c && (i || !ISVISIBLE(c));
	    i -= ISVISIBLE(c) ? 1 : 0, p = c, c = c->next);
	focus(c ? c : p);
	restack(selmon);

	if (ispanel(c) && focussed_panel == 0) {
	    focussed_panel = 1;
	    focusstack(arg);
	    focussed_panel = 0;
	}
}

Atom
getatomprop(Client *c, Atom prop)
{
	int di;
	unsigned long dl;
	unsigned char *p = NULL;
	Atom da, atom = None;

	/* FIXME getatomprop should return the number of items and a pointer to
	 * the stored data instead of this workaround */
	Atom req = XA_ATOM;
	if (prop == xatom[XembedInfo])
		req = xatom[XembedInfo];

	if (XGetWindowProperty(dpy, c->win, prop, 0L, sizeof atom, False, req,
		&da, &di, &dl, &dl, &p) == Success && p) {
		atom = *(Atom *)p;
		if (da == xatom[XembedInfo] && dl == 2)
			atom = ((Atom *)p)[1];
		XFree(p);
	}
	return atom;
}



unsigned int
getsystraywidth()
{
	unsigned int w = 0;
	Client *i;
	if(showsystray)
		for(i = systray->icons; i; w += i->w + systrayspacing, i = i->next) ;
	return w ? w + systrayspacing : 1;
}


int
getrootptr(int *x, int *y)
{
	int di;
	unsigned int dui;
	Window dummy;

	return XQueryPointer(dpy, root, &dummy, &dummy, x, y, &di, &di, &dui);
}

long
getstate(Window w)
{
	int format;
	long result = -1;
	unsigned char *p = NULL;
	unsigned long n, extra;
	Atom real;

	if (XGetWindowProperty(dpy, w, wmatom[WMState], 0L, 2L, False, wmatom[WMState],
		&real, &format, &n, &extra, (unsigned char **)&p) != Success)
		return -1;
	if (n != 0)
		result = *p;
	XFree(p);
	return result;
}

int
gettextprop(Window w, Atom atom, char *text, unsigned int size)
{
	char **list = NULL;
	int n;
	XTextProperty name;

	if (!text || size == 0)
		return 0;
	text[0] = '\0';
	if (!XGetTextProperty(dpy, w, &name, atom) || !name.nitems)
		return 0;
	if (name.encoding == XA_STRING) {
		strncpy(text, (char *)name.value, size - 1);
	} else if (XmbTextPropertyToTextList(dpy, &name, &list, &n) >= Success && n > 0 && *list) {
		strncpy(text, *list, size - 1);
		XFreeStringList(list);
	}
	text[size - 1] = '\0';
	XFree(name.value);
	return 1;
}

void
grabbuttons(Client *c, int focused)
{
	updatenumlockmask();
	{
		unsigned int i, j;
		unsigned int modifiers[] = { 0, LockMask, numlockmask, numlockmask|LockMask };
		XUngrabButton(dpy, AnyButton, AnyModifier, c->win);
		if (!focused)
			XGrabButton(dpy, AnyButton, AnyModifier, c->win, False,
				BUTTONMASK, GrabModeSync, GrabModeSync, None, None);
		for (i = 0; i < LENGTH(buttons); i++)
			if (buttons[i].click == ClkClientWin)
				for (j = 0; j < LENGTH(modifiers); j++)
					XGrabButton(dpy, buttons[i].button,
						buttons[i].mask | modifiers[j],
						c->win, False, BUTTONMASK,
						GrabModeAsync, GrabModeSync, None, None);
	}
}

void
grabkeys(void)
{
	updatenumlockmask();
	{
		unsigned int i, j, k;
		unsigned int modifiers[] = { 0, LockMask, numlockmask, numlockmask|LockMask };
		int start, end, skip;
		KeySym *syms;
		const Key *kt = keymode ? resizekeys : keys; /* tuxcraft: resize mode has its own keys */
		unsigned int nkt = keymode ? LENGTH(resizekeys) : LENGTH(keys);

		XUngrabKey(dpy, AnyKey, AnyModifier, root);
		XDisplayKeycodes(dpy, &start, &end);
		syms = XGetKeyboardMapping(dpy, start, end - start + 1, &skip);
		if (!syms)
			return;
		for (k = start; k <= end; k++)
			for (i = 0; i < nkt; i++)
				/* skip modifier codes, we do that ourselves */
				if (kt[i].keysym == syms[(k - start) * skip])
					for (j = 0; j < LENGTH(modifiers); j++)
						XGrabKey(dpy, k,
							 kt[i].mod | modifiers[j],
							 root, True,
							 GrabModeAsync, GrabModeAsync);
		XFree(syms);
	}
}

int
ispanel(Client *c) {
    return c && !strcmp(c->name, panel[0]);
}

int
ispopup(Client *c) {
	Atom wtype = getatomprop(c, netatom[NetWMWindowType]);
	return (wtype == netatom[NetWMWindowTypeDialog] ||
		 wtype == netatom[NetWMWindowTypeNotification] ||
		 wtype == netatom[NetWMWindowTypeMenu]);
}

void
incnmaster(const Arg *arg)
{
	selmon->nmaster = MAX(selmon->nmaster + arg->i, 0);
	pertagkeep(selmon);
	pertagsave();
	arrange(selmon);
}

#ifdef XINERAMA
static int
isuniquegeom(XineramaScreenInfo *unique, size_t n, XineramaScreenInfo *info)
{
	while (n--)
		if (unique[n].x_org == info->x_org && unique[n].y_org == info->y_org
		&& unique[n].width == info->width && unique[n].height == info->height)
			return 0;
	return 1;
}
#endif /* XINERAMA */

void
keypress(XEvent *e) /* receives a keyboard press XEvent from X11 */
{
	unsigned int i; /* will loop over keybinds */
	KeySym keysym; /* symbolic name, like XK_b or XK_space */
	XKeyEvent *ev; /* pointer to the key event data */

	ev = &e->xkey; /* grabs the XKeyEvent from XEvent */
	keysym = XKeycodeToKeysym(dpy, (KeyCode)ev->keycode, 0); /* translates raw keycode into symbolic keysym */
	const Key *kt = keymode ? resizekeys : keys; /* tuxcraft: resize mode has its own keys */
	unsigned int nkt = keymode ? LENGTH(resizekeys) : LENGTH(keys);
	for (i = 0; i < nkt; i++) /* loop thru all binds in keys[] (config.h) */
		if (keysym == kt[i].keysym
		&& CLEANMASK(kt[i].mod) == CLEANMASK(ev->state)
		&& kt[i].func) { /* check that a pointer function exists */
			kt[i].func(&(kt[i].arg)); /* if the pressed key matches a bind, call the function associated w/ that bind */
			break; /* the function may have switched key tables */
		}
}

void
killthis(Client *c) {
	if (!sendevent(selmon->sel->win, wmatom[WMDelete], NoEventMask, wmatom[WMDelete], CurrentTime, 0 , 0, 0)) {
		XGrabServer(dpy);
		XSetErrorHandler(xerrordummy);
		XSetCloseDownMode(dpy, DestroyAll);
		XKillClient(dpy, c->win);
		XSync(dpy, False);
		XSetErrorHandler(xerror);
		XUngrabServer(dpy);
	}
}

void
killclient(const Arg *arg)
{
    Client *c;

	if (!selmon->sel)
		return;

    if (!arg->ui || arg->ui == 0) {
        killthis(selmon->sel);
        return;
    }

    for (c = selmon->clients; c; c = c->next) {
        if (!ISVISIBLE(c) || (arg->ui == 1 && c == selmon->sel))
            continue;
        killthis(c);
    }
}

void
loadxrdb(void)
{
  Display *display;
  char * resm;
  XrmDatabase xrdb;
  char *type;
  XrmValue value;

  display = XOpenDisplay(NULL);

  if (display != NULL) {
    resm = XResourceManagerString(display);

    if (resm != NULL) {
      xrdb = XrmGetStringDatabase(resm);

      if (xrdb != NULL) {
        XRDB_LOAD_COLOR("dwm.normbordercolor", normbordercolor);
        XRDB_LOAD_COLOR("dwm.normbgcolor", normbgcolor);
        XRDB_LOAD_COLOR("dwm.normfgcolor", normfgcolor);
        XRDB_LOAD_COLOR("dwm.selbordercolor", selbordercolor);
        XRDB_LOAD_COLOR("dwm.selbgcolor", selbgcolor);
        XRDB_LOAD_COLOR("dwm.selfgcolor", selfgcolor);
        /* tuxcraft: bar font from tux-theme / tux-font (read at start and restart) */
        if (XrmGetResource(xrdb, "dwm.font", NULL, &type, &value) == True && value.addr && *value.addr) {
          strncpy(font, value.addr, sizeof font - 1);
          font[sizeof font - 1] = '\0';
        }
        if (XrmGetResource(xrdb, "dwm.iconfont", NULL, &type, &value) == True && value.addr && *value.addr) {
          strncpy(iconfont, value.addr, sizeof iconfont - 1);
          iconfont[sizeof iconfont - 1] = '\0';
        }
      }
    }
    XCloseDisplay(display);
  }
}

void
manage(Window w, XWindowAttributes *wa)
{ /* after a window is passed from maprequest, manage determines how to treat it and add it to the stack */
	Client *c, *t = NULL, *term = NULL;
	Window trans = None;
	XWindowChanges wc;

	c = ecalloc(1, sizeof(Client)); /* allocate and initialize a new Client struct to represent the window */
	c->win = w;
	c->pid = winpid(w); /* pid used for things like swallowing */
	/* geometry using XWindowAttributes */
	c->x = c->oldx = wa->x;
	c->y = c->oldy = wa->y;
	c->w = c->oldw = wa->width;
	c->h = c->oldh = wa->height;
	c->oldbw = wa->border_width;

	updatetitle(c); /* grabs title */
	if (XGetTransientForHint(dpy, w, &trans) && (t = wintoclient(trans))) { /* if transient, it inherits tags+mon of parent */
		c->mon = t->mon;
		c->tags = t->tags;
		c->cfact = 1.0;
		c->order = -1;
	} else {
		c->mon = selmon; /* assigns to selected monitor */
		c->cfact = 1.0;
		c->order = -1;
		term = termforwin(c); /* tries to find a terminal for swallowing */
		applyrules(c); /* apply any matching tag rules from config.h */
		{ /* tuxcraft: a restart (Super+Shift+R, theme change) keeps each window on its tag,
		   * its monitor, its place in the tiling and its share of the column (savestate()) */
			Atom type; int fmt; unsigned long n, after; unsigned char *p = NULL;
			if (XGetWindowProperty(dpy, w, tuxtagsatom, 0, 5, True, XA_CARDINAL, &type, &fmt,
			    &n, &after, &p) == Success && p) {
				if (n == 5) {
					long *v = (long *)p;
					Monitor *om;
					for (om = mons; om && om->num != v[4]; om = om->next);
					if (om)
						c->mon = om;
					c->order = (int)v[2];
					if (v[3] > 0)
						c->cfact = MAX(0.1, MIN(10.0, v[3] / 1000.0));
				}
				if (n >= 2) {
					long *v = (long *)p;
					if (v[0] & (TAGMASK | SPTAG)) {
						c->tags = v[0] & (TAGMASK | SPTAG);
						c->isscratch = (c->tags & SPTAG) != 0;
					}
					c->isfloating = (v[1] & 1) || c->isscratch;
					c->issticky = (v[1] & 2) != 0;
				}
				XFree(p);
			}
		}
	}
	c->desktop = -2;
	XDeleteProperty(dpy, w, tuxhiddenatom); /* left from before a restart */
	XDeleteProperty(dpy, w, tuxglideatom);
	XDeleteProperty(dpy, w, tuxstillatom);
		/* ensure window fits to visible bounds of monitor */
	if (c->x + WIDTH(c) > c->mon->wx + c->mon->ww)
		c->x = c->mon->wx + c->mon->ww - WIDTH(c);
	if (c->y + HEIGHT(c) > c->mon->wy + c->mon->wh)
		c->y = c->mon->wy + c->mon->wh - HEIGHT(c);
	c->x = MAX(c->x, c->mon->wx);
	c->y = MAX(c->y, c->mon->wy);
	c->bw = borderpx;

    // no border - even when active
    if (ispanel(c)) c->bw = c->oldbw = 0;
	wc.border_width = c->bw;
	XConfigureWindow(dpy, w, CWBorderWidth, &wc);
	XSetWindowBorder(dpy, w, scheme[SchemeNorm][ColBorder].pixel);
	configure(c); /* propagates border_width, if size doesn't change */
	updatewindowtype(c);
	updatesizehints(c);
	updatewmhints(c);
	XSelectInput(dpy, w, EnterWindowMask|FocusChangeMask|PropertyChangeMask|StructureNotifyMask);
	grabbuttons(c, 0);
	if (!c->isfloating)
		c->isfloating = c->oldstate = trans != None || c->isfixed;
	if (c->isfloating)
		XRaiseWindow(dpy, c->win);
	attach(c); /* add to the monitor's client list */
	attachstack(c); /* add it to the stack */
	XChangeProperty(dpy, root, netatom[NetClientList], XA_WINDOW, 32, PropModeAppend, /* add to X11 client list */
		(unsigned char *) &(c->win), 1);
	XMoveResizeWindow(dpy, c->win, c->x + 2 * sw, c->y, c->w, c->h); /* some windows require this */
	setclientstate(c, NormalState);
	//if(selmon->sel && selmon->sel->isfullscreen && !c->isfloating) /* if a fullscreen window was focused, toggle fullscreen */
	//	setfullscreen(selmon->sel, 0);
	if (c->mon == selmon)
		unfocus(selmon->sel, 0); /* unfocus other monitor if new window is on current monitor */
	c->mon->sel = c;
	arrange(c->mon); /* recalc based on layout */
	XMapWindow(dpy, c->win);
	if (term)
		swallow(term, c); /* if new window is child of a terminal, replace terminal (swallow) */
	focus(NULL); /* focus the client */
}

void
mappingnotify(XEvent *e)
{ /* keyboard mapping change */
	XMappingEvent *ev = &e->xmapping;

	XRefreshKeyboardMapping(ev);
	if (ev->request == MappingKeyboard)
		grabkeys();
}

void
maprequest(XEvent *e)
{ /* window requests map */
	static XWindowAttributes wa; /* wa will now hold window attributes */
	XMapRequestEvent *ev = &e->xmaprequest;

	Client *i;
	if ((i = wintosystrayicon(ev->window))) {
		sendevent(i->win, netatom[Xembed], StructureNotifyMask, CurrentTime, XEMBED_WINDOW_ACTIVATE, 0, systray->win, XEMBED_EMBEDDED_VERSION);
		resizebarwin(selmon);
		updatesystray();
	}

	if (!XGetWindowAttributes(dpy, ev->window, &wa) || wa.override_redirect)
		return; /* gets window geom and data */
	if (!wintoclient(ev->window)) /* if window is not already managed by dwm */
		manage(ev->window, &wa); /* call manage to start managing it */
}

void
monocle(Monitor *m)
{
	unsigned int n = 0;
	Client *c;

	for (c = m->clients; c; c = c->next)
		if (ISVISIBLE(c))
			n++;
	if (n > 0) /* override layout symbol */
		snprintf(m->ltsymbol, sizeof m->ltsymbol, "[%d]", n);
	for (c = nexttiled(m->clients); c; c = nexttiled(c->next))
		resize(c, m->wx, m->wy, m->ww - 2 * c->bw, m->wh - 2 * c->bw, 0);
}

void
motionnotify(XEvent *e)
{
	static Monitor *mon = NULL;
	Monitor *m;
	XMotionEvent *ev = &e->xmotion;

	if (ev->window != root)
		return;
	if ((m = recttomon(ev->x_root, ev->y_root, 1, 1)) != mon && mon) {
		unfocus(selmon->sel, 1);
		selmon = m;
		focus(NULL);
	}
	mon = m;
}

void
movemouse(const Arg *arg)
{
	int x, y, ocx, ocy, nx, ny;
	Client *c;
	Monitor *m;
	XEvent ev;
	Time lasttime = 0;

	if (!(c = selmon->sel))
		return;
	if (c->isfullscreen) /* no support moving fullscreen windows by mouse */
		return;
	/* tuxcraft: Super + drag on a tiled window keeps it tiled and moves it to another place in
	 * the tiling (arg->i 0); Super + Shift + drag (arg->i 1) floats it and moves it freely. */
	if (!arg->i && !c->isfloating && selmon->lt[selmon->sellt]->arrange) {
		movetiled(c);
		return;
	}
	restack(selmon);
	ocx = c->x;
	ocy = c->y;
	if (XGrabPointer(dpy, root, False, MOUSEMASK, GrabModeAsync, GrabModeAsync,
		None, cursor[CurMove]->cursor, CurrentTime) != GrabSuccess)
		return;
	if (!getrootptr(&x, &y))
		return;
	stillmark(c, 1);
	do {
		XMaskEvent(dpy, MOUSEMASK|ExposureMask|SubstructureRedirectMask, &ev);
		switch(ev.type) {
		case ConfigureRequest:
		case Expose:
		case MapRequest:
			handler[ev.type](&ev);
			break;
		case MotionNotify:
			if ((ev.xmotion.time - lasttime) <= (1000 / refreshrate))
				continue;
			lasttime = ev.xmotion.time;

			nx = ocx + (ev.xmotion.x - x);
			ny = ocy + (ev.xmotion.y - y);
			if (abs(selmon->wx - nx) < snap)
				nx = selmon->wx;
			else if (abs((selmon->wx + selmon->ww) - (nx + WIDTH(c))) < snap)
				nx = selmon->wx + selmon->ww - WIDTH(c);
			if (abs(selmon->wy - ny) < snap)
				ny = selmon->wy;
			else if (abs((selmon->wy + selmon->wh) - (ny + HEIGHT(c))) < snap)
				ny = selmon->wy + selmon->wh - HEIGHT(c);
			if (!c->isfloating && selmon->lt[selmon->sellt]->arrange
			&& (abs(nx - c->x) > snap || abs(ny - c->y) > snap))
				togglefloating(NULL);
			if (!selmon->lt[selmon->sellt]->arrange || c->isfloating)
				resize(c, nx, ny, c->w, c->h, 1);
			break;
		}
	} while (ev.type != ButtonRelease);
	XUngrabPointer(dpy, CurrentTime);
	stillmark(c, 0);
	if ((m = recttomon(c->x, c->y, c->w, c->h)) != selmon) {
		sendmon(c, m);
		selmon = m;
		focus(NULL);
	}
}

/* tuxcraft: put c just before t in its monitor's client list (the tiling order). */
static void
insertbefore(Client *c, Client *t)
{
	Client **tc;

	for (tc = &t->mon->clients; *tc && *tc != t; tc = &(*tc)->next);
	c->next = t;
	*tc = c;
}

/* tuxcraft: Super + drag on a tiled window. While the pointer is over another tiled window, c
 * takes its place in the tiling (the windows in between move up one). Let go over another
 * monitor: c goes there. Nothing floats. */
static void
movetiled(Client *c)
{
	Client *t, *last = NULL, *i;
	Monitor *m;
	XEvent ev;
	Time lasttime = 0;
	int px, py, after;

	if (XGrabPointer(dpy, root, False, MOUSEMASK, GrabModeAsync, GrabModeAsync,
		None, cursor[CurMove]->cursor, CurrentTime) != GrabSuccess)
		return;
	do {
		XMaskEvent(dpy, MOUSEMASK|ExposureMask|SubstructureRedirectMask, &ev);
		switch(ev.type) {
		case ConfigureRequest:
		case Expose:
		case MapRequest:
			handler[ev.type](&ev);
			break;
		case MotionNotify:
			if ((ev.xmotion.time - lasttime) <= (1000 / refreshrate))
				continue;
			lasttime = ev.xmotion.time;
			px = ev.xmotion.x_root;
			py = ev.xmotion.y_root;
			if (px >= c->x && px < c->x + WIDTH(c) && py >= c->y && py < c->y + HEIGHT(c)) {
				last = NULL; /* back over itself: the next window it reaches moves it again */
				continue;
			}
			for (t = nexttiled(c->mon->clients); t; t = nexttiled(t->next))
				if (t != c && px >= t->x && px < t->x + WIDTH(t) && py >= t->y && py < t->y + HEIGHT(t))
					break;
			if (!t || t == last)
				continue;
			last = t;
			/* moving down the list (t after c): c goes after t, else before it */
			for (after = 0, i = c->next; i; i = i->next)
				if (i == t) { after = 1; break; }
			detach(c);
			if (after) {
				c->next = t->next;
				t->next = c;
			} else
				insertbefore(c, t);
			arrange(c->mon);
			break;
		}
	} while (ev.type != ButtonRelease);
	XUngrabPointer(dpy, CurrentTime);
	if ((m = recttomon(ev.xbutton.x_root, ev.xbutton.y_root, 1, 1)) != c->mon) {
		sendmon(c, m);
		selmon = m;
		focus(NULL);
	}
}

Client *
nexttiled(Client *c)
{
	for (; c && (c->isfloating || !ISVISIBLE(c)); c = c->next);
	return c;
}

void
pop(Client *c)
{
	int i;
	for (i = 0; !(selmon->tagset[selmon->seltags] & 1 << i); i++);
	i++;

	c->mon->tagmarked[i] = nexttiled(c->mon->clients);
	detach(c);
	attach(c);
	focus(c);
	arrange(c->mon);
}

void
propertynotify(XEvent *e)
{
	Client *c;
	Window trans;
	XPropertyEvent *ev = &e->xproperty;

	if ((c = wintosystrayicon(ev->window))) {
		if (ev->atom == XA_WM_NORMAL_HINTS) {
			updatesizehints(c);
			updatesystrayicongeom(c, c->w, c->h);
		}
		else
			updatesystrayiconstate(c, ev);
		resizebarwin(selmon);
		updatesystray();
	}

	if ((ev->window == root) && (ev->atom == XA_WM_NAME))
		updatestatus();
	else if (ev->window == root && ev->atom == XA_RESOURCE_MANAGER) {
		/* tuxcraft: X resources (re)loaded (xrdb -merge: login, tux-theme, tux-font). New
		 * colours apply at once; a new font needs a restart, which keeps the windows' tags. */
		char oldfont[sizeof font], oldicon[sizeof iconfont];
		Monitor *m;
		Client *cl;
		strcpy(oldfont, font);
		strcpy(oldicon, iconfont);
		loadxrdb();
		if (strcmp(oldfont, font) || strcmp(oldicon, iconfont)) {
			Arg a = {.i = 1};
			quit(&a);
		} else {
			xrdb(NULL);
			for (m = mons; m; m = m->next)
				for (cl = m->clients; cl; cl = cl->next)
					XSetWindowBorder(dpy, cl->win, scheme[cl == selmon->sel ? SchemeSel : SchemeNorm][ColBorder].pixel);
		}
	}
	else if (ev->window == root && ev->atom == tuxcmdatom && ev->state == PropertyNewValue) {
		char cmd[256];
		if (gettextprop(root, tuxcmdatom, cmd, sizeof cmd)) {
			XDeleteProperty(dpy, root, tuxcmdatom);
			tuxcmd(cmd);
		}
	}
	else if (ev->state == PropertyDelete)
		return; /* ignore */
	else if ((c = wintoclient(ev->window))) {
		switch(ev->atom) {
		default: break;
		case XA_WM_TRANSIENT_FOR:
			if (!c->isfloating && (XGetTransientForHint(dpy, c->win, &trans)) &&
				(c->isfloating = (wintoclient(trans)) != NULL))
				arrange(c->mon);
			break;
		case XA_WM_NORMAL_HINTS:
			c->hintsvalid = 0;
			break;
		case XA_WM_HINTS:
			updatewmhints(c);
			drawbars();
			break;
		}
		if (ev->atom == XA_WM_NAME || ev->atom == netatom[NetWMName]) {
			updatetitle(c);
			if (c == c->mon->sel && selmon->showtitle)
				drawbar(c->mon);
		}
		if (ev->atom == netatom[NetWMWindowType])
			updatewindowtype(c);
	}
}

void
pushstack(const Arg *arg) {
	int i = stackpos(arg);
	Client *sel = selmon->sel, *c, *p;

	if(i < 0)
		return;
	else if(i == 0) {
		detach(sel);
		attach(sel);
	}
	else {
		for(p = NULL, c = selmon->clients; c; p = c, c = c->next)
			if(!(i -= (ISVISIBLE(c) && c != sel)))
				break;
		c = c ? c : p;
		detach(sel);
		sel->next = c->next;
		c->next = sel;
	}
	arrange(selmon);
}

void
quit(const Arg *arg)
{
	if(arg->i) restart = 1;
	running = 0;
}

Monitor *
recttomon(int x, int y, int w, int h)
{
	Monitor *m, *r = selmon;
	int a, area = 0;

	for (m = mons; m; m = m->next)
		if ((a = INTERSECT(x, y, w, h, m)) > area) {
			area = a;
			r = m;
		}
	return r;
}

void
removesystrayicon(Client *i)
{
	Client **ii;

	if (!showsystray || !i)
		return;
	for (ii = &systray->icons; *ii && *ii != i; ii = &(*ii)->next);
	if (ii)
		*ii = i->next;
	free(i);
}

void
resize(Client *c, int x, int y, int w, int h, int interact)
{
	if (ispanel(c) || applysizehints(c, &x, &y, &w, &h, interact))
		resizeclient(c, x, y, w, h);
}

void
resizebarwin(Monitor *m) {
	unsigned int w = m->ww;
	if (showsystray && m == systraytomon(m) && !systrayonleft)
		w -= getsystraywidth();
	XMoveResizeWindow(dpy, m->barwin, m->wx, m->by, w, bh);
}

void
resizeclient(Client *c, int x, int y, int w, int h)
{
	XWindowChanges wc;

	c->oldx = c->x; c->x = wc.x = x;
	c->oldy = c->y; c->y = wc.y = y;
	c->oldw = c->w; c->w = wc.width = w;
	c->oldh = c->h; c->h = wc.height = h;
	wc.border_width = c->bw;
    // nail it to no border & y=0:
    if (ispanel(c)) c->y = c->oldy = c->bw = wc.y = wc.border_width = 0;
	if (c->glide) { /* tuxcraft: a move of its own now, not its tag coming back (showhide) */
		XDeleteProperty(dpy, c->win, tuxglideatom);
		c->glide = 0;
	}
	c->leaving = 0; /* moved or resized by dwm: no more sliding out */
	XConfigureWindow(dpy, c->win, CWX|CWY|CWWidth|CWHeight|CWBorderWidth, &wc);
	configure(c);
	XSync(dpy, False);
}

void
resizerequest(XEvent *e)
{
	XResizeRequestEvent *ev = &e->xresizerequest;
	Client *i;

	if ((i = wintosystrayicon(ev->window))) {
		updatesystrayicongeom(i, ev->width, ev->height);
		resizebarwin(selmon);
		updatesystray();
	}
}

/* tuxcraft: one resize, by the mouse (Super + right drag, resizemouse) or the touchpad (Super
 * + two-finger drag, tfscroll): rsbegin() looks at the window, rsstep() follows the distance
 * moved since the start, rsend() finishes. */
static struct {
	Client *c;
	int tiled, vert, colfacts, n, idx, cols, last, span, total, w0, h0;
	float mf0, othercf;
} rs;

/* While a window is moved or resized by hand it changes every frame, and picom would start its
 * move animation (dwm.conf) again at each one: the content and the see-through background
 * flicker. _TUX_DWM_STILL switches that off for the windows that move, until the hand lets go. */
static void
stillmark(Client *c, int on)
{
	long one = 1;

	if (!c || c->still == on)
		return;
	c->still = on;
	if (on)
		XChangeProperty(dpy, c->win, tuxstillatom, XA_CARDINAL, 32, PropModeReplace,
			(unsigned char *)&one, 1);
	else
		XDeleteProperty(dpy, c->win, tuxstillatom);
}

static void
stillall(Monitor *m, int on) /* a tiled resize moves its neighbours too */
{
	Client *c;

	for (c = m->clients; c; c = c->next)
		if (on ? ISVISIBLE(c) : c->still)
			stillmark(c, on);
}

static int
rsbegin(Client *c)
{
	Client *t;
	int i = 0;

	memset(&rs, 0, sizeof rs);
	if (!c || c->isfullscreen) /* no support resizing fullscreen windows by mouse */
		return 0;
	rs.c = c;
	restack(selmon);
	if (!c->isfloating && selmon->lt[selmon->sellt]->arrange) {
		/* tuxcraft: like i3, Super + right drag on a tiled window resizes it in place, without
		 * making it float. The border between the master and the other windows follows the mouse
		 * one way (left-right; up-down in the bottom-stack layout), the window's border with its
		 * neighbour in the same column follows it the other way (its cfact). Nothing to resize
		 * in monocle, as in i3's tabbed layout. */
		void (*lt)(Monitor *) = selmon->lt[selmon->sellt]->arrange;
		rs.tiled = 1;
		rs.vert = lt == bstack;
		rs.colfacts = lt == tile || lt == bstack || lt == deck;
		rs.mf0 = selmon->mfact;
		rs.idx = -1;
		if (lt == monocle)
			return 0;
		for (t = nexttiled(selmon->clients); t; t = nexttiled(t->next), i++, rs.n++)
			if (t == c)
				rs.idx = i;
		if (rs.idx < 0)
			return 0;
		/* the window's column: masters or the others; drag its far border unless it is the
		 * last one there, then the near one (as i3 moves the border closest to the window) */
		if (rs.idx < selmon->nmaster) { rs.cols = MIN(rs.n, selmon->nmaster); rs.last = rs.idx == rs.cols - 1; }
		else { rs.cols = rs.n - selmon->nmaster; rs.last = rs.idx == rs.n - 1; }
		if (lt == deck && rs.idx >= selmon->nmaster)
			rs.cols = 1;   /* the deck's stack shows one window at a time */
		rs.span = rs.vert ? c->w : c->h;
		stillall(selmon, 1);
		/* the column's other windows: their factors and the room the column has, so the border
		 * can follow the mouse exactly */
		for (i = 0, t = nexttiled(selmon->clients); t; t = nexttiled(t->next), i++)
			if ((rs.idx < selmon->nmaster) == (i < selmon->nmaster)) {
				rs.total += rs.vert ? t->w : t->h;
				if (t != c)
					rs.othercf += t->cfact;
			}
		return 1;
	}
	rs.w0 = c->w;
	rs.h0 = c->h;
	stillmark(c, 1);
	return 1;
}

static void
rsstep(int dx, int dy)
{
	Client *c = rs.c;
	int nw, nh;
	float f;

	if (!c)
		return;
	if (rs.tiled) {
		/* the master / stack border */
		if (rs.n > selmon->nmaster && selmon->nmaster > 0) {
			f = rs.mf0 + (rs.vert ? (float)dy / selmon->wh : (float)dx / selmon->ww);
			selmon->mfact = MAX(0.05, MIN(0.95, f));
		}
		/* the border with the neighbour in the column */
		if (rs.colfacts && rs.cols > 1 && rs.span > 0 && rs.othercf > 0) {
			int d = rs.vert ? dx : dy;
			int want = rs.span + (rs.last ? -d : d);
			want = MAX(bh, MIN(rs.total - bh * (rs.cols - 1), want));
			/* share of the column = want / total -> factor against the others' factors */
			f = rs.othercf * want / (float)MAX(1, rs.total - want);
			c->cfact = MAX(0.1, MIN(10.0, f));
		}
		arrange(selmon);
		return;
	}
	nw = MAX(rs.w0 + dx, 1);
	nh = MAX(rs.h0 + dy, 1);
	if (c->mon->wx + nw >= selmon->wx && c->mon->wx + nw <= selmon->wx + selmon->ww
	&& c->mon->wy + nh >= selmon->wy && c->mon->wy + nh <= selmon->wy + selmon->wh)
	{
		if (!c->isfloating && selmon->lt[selmon->sellt]->arrange
		&& (abs(nw - c->w) > snap || abs(nh - c->h) > snap))
			togglefloating(NULL);
	}
	if (!selmon->lt[selmon->sellt]->arrange || c->isfloating)
		resize(c, c->x, c->y, nw, nh, 1);
}

static void
rsend(void)
{
	Client *c = rs.c;
	Monitor *m;

	rs.c = NULL;
	if (!c)
		return;
	if (rs.tiled) { /* the master size may have moved: keep it for this tag */
		pertagkeep(selmon);
		pertagsave();
	}
	stillall(c->mon, 0);
	if (rs.tiled)
		return;
	if ((m = recttomon(c->x, c->y, c->w, c->h)) != selmon) {
		sendmon(c, m);
		selmon = m;
		focus(NULL);
	}
}

void
resizemouse(const Arg *arg)
{
	int x0, y0;
	Client *c;
	XEvent ev;
	Time lasttime = 0;

	if (!rsbegin(selmon->sel))
		return;
	c = rs.c;
	if (XGrabPointer(dpy, root, False, MOUSEMASK, GrabModeAsync, GrabModeAsync,
		None, cursor[CurResize]->cursor, CurrentTime) != GrabSuccess) {
		rsend();
		return;
	}
	if (!rs.tiled) /* the pointer to the corner it drags */
		XWarpPointer(dpy, None, c->win, 0, 0, 0, 0, c->w + c->bw - 1, c->h + c->bw - 1);
	if (!getrootptr(&x0, &y0)) {
		XUngrabPointer(dpy, CurrentTime);
		rsend();
		return;
	}
	do {
		XMaskEvent(dpy, MOUSEMASK|ExposureMask|SubstructureRedirectMask, &ev);
		switch(ev.type) {
		case ConfigureRequest:
		case Expose:
		case MapRequest:
			handler[ev.type](&ev);
			break;
		case MotionNotify:
			if ((ev.xmotion.time - lasttime) <= (1000 / refreshrate))
				continue;
			lasttime = ev.xmotion.time;
			rsstep(ev.xmotion.x_root - x0, ev.xmotion.y_root - y0);
			break;
		}
	} while (ev.type != ButtonRelease);
	if (!rs.tiled)
		XWarpPointer(dpy, None, c->win, 0, 0, 0, 0, c->w + c->bw - 1, c->h + c->bw - 1);
	XUngrabPointer(dpy, CurrentTime);
	while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
	rsend();
}

void
restack(Monitor *m)
{
	Client *c;
	XEvent ev;
	XWindowChanges wc;

	drawbar(m);
	if (!m->sel)
		return;
	if (m->sel->isfloating || !m->lt[m->sellt]->arrange)
		XRaiseWindow(dpy, m->sel->win);
	if (m->lt[m->sellt]->arrange) {
		wc.stack_mode = Below;
		wc.sibling = m->barwin;
		for (c = m->stack; c; c = c->snext)
			if (!c->isfloating && ISVISIBLE(c)) {
				XConfigureWindow(dpy, c->win, CWSibling|CWStackMode, &wc);
				wc.sibling = c->win;
			}
	}
	XSync(dpy, False);
	while (XCheckMaskEvent(dpy, EnterWindowMask, &ev));
}

/* tuxcraft: touchpad swipe between tags that follows the fingers, as on macOS. dwm reads the
 * touchpad itself through libinput (the input group is enough), next to X, which still gets
 * every event: 2- and 3-finger gestures, taps and scrolling are not touched. While a 4-finger
 * swipe goes sideways, this tag's windows slide with the fingers and the next or previous
 * occupied tag slides in from its side (no wrap: at the first or last tag it gives a little
 * and springs back). Let go past SWIPECOMMIT of the screen, or with a flick, and it finishes
 * the move; otherwise it slides back. All the windows involved carry _TUX_DWM_HIDDEN meanwhile,
 * so picom does not animate the moves itself. _TUX_DWM_SWIPE on the root window (the finger
 * count) tells tux-gestures that dwm does left and right, so it only handles up. Built only
 * when libinput's and libudev's headers are there (config.mk); without them dwm has no swipe
 * and tux-gestures presses Super+Tab instead. */
#ifdef TUXSWIPE
#ifndef SWIPEFINGERS
#define SWIPEFINGERS 4      /* fingers for the swipe */
#endif
#ifndef SWIPEDIST
#define SWIPEDIST 1500.0    /* finger travel (libinput's units) for one screen width */
#endif
#ifndef SWIPECOMMIT
#define SWIPECOMMIT 0.3     /* let go past this part of the screen: the move finishes */
#endif
#ifndef SWIPEFRAME
#define SWIPEFRAME 6        /* ms between frames while a drag is on (about 165 Hz) */
#endif

enum { SwipeIdle, SwipeWait, SwipeIgnore, SwipeDrag, SwipeAnim };
static struct libinput *li;
static struct udev *lidev;
static int lipads;          /* touchpads libinput reports (gesture capable) */
static Atom tuxswipeatom;
static struct {
	int state, commit;
	Monitor *m;
	unsigned int cur, prev, next, shown, laid; /* tagsets; prev/next 0: none that way */
	double fx, fy, off, vel, from, to; /* finger travel, offset shown (px), px per ms */
	double goal;                        /* offset the fingers ask for */
	int placed;                         /* offset last sent to X */
	uint64_t t;                         /* time of the last update (usec) */
	struct timespec t0, tf;             /* animation start, last frame */
	double dur;                         /* animation length (ms) */
} sg;

static int
liopen(const char *path, int flags, void *data)
{
	int fd = open(path, flags | O_CLOEXEC);
	(void)data;
	return fd < 0 ? -errno : fd;
}

static void
liclose(int fd, void *data)
{
	(void)data;
	close(fd);
}

static const struct libinput_interface liiface = { liopen, liclose };

static void
swipeprop(void)
{
	long n = SWIPEFINGERS;
	if (li && lipads > 0)
		XChangeProperty(dpy, root, tuxswipeatom, XA_CARDINAL, 32, PropModeReplace,
			(unsigned char *)&n, 1);
	else
		XDeleteProperty(dpy, root, tuxswipeatom);
}

static void
swipemark(Client *c, int on)
{
	long one = 1;
	if (on)
		XChangeProperty(dpy, c->win, tuxhiddenatom, XA_CARDINAL, 32, PropModeReplace,
			(unsigned char *)&one, 1);
	else
		XDeleteProperty(dpy, c->win, tuxhiddenatom);
}

/* where showhide() parks a hidden window: off the left edge for lower tags, right for higher */
static int
swipepark(Client *c)
{
	unsigned int cur = c->mon->tagset[c->mon->seltags];
	return (c->tags & -c->tags) < (cur & -cur) ? WIDTH(c) * -2 : sw + WIDTH(c);
}

/* move the windows of this tag by the offset, and those of the tag coming in beside them */
static void
swipeplace(void)
{
	Monitor *m = sg.m;
	Client *c;
	int o = (int)sg.off, oo = o < 0 ? o + m->mw : o - m->mw;
	unsigned int other = o < 0 ? sg.next : o > 0 ? sg.prev : 0;

	if (!(other & sg.laid)) /* not laid out yet (the frames still lag on the other side) */
		other = 0;
	for (c = m->clients; c; c = c->next) {
		if (c->issticky || c->isscratch)
			continue;
		if (c->tags & sg.cur)
			XMoveWindow(dpy, c->win, c->x + o, c->y);
		else if (other && (c->tags & other))
			XMoveWindow(dpy, c->win, c->x + oo, c->y);
		else if (sg.shown && (c->tags & sg.shown))
			XMoveWindow(dpy, c->win, swipepark(c), c->y); /* the other side went out of view */
	}
	sg.shown = other;
}

/* lay out a tag that is about to come in, without showing it: its windows are tiled where
 * they will be and placed beside the screen in the same server grab, so picom never sees
 * them in between */
static void
swipelayout(unsigned int tags)
{
	Monitor *m = sg.m;
	unsigned int save = m->tagset[m->seltags];

	if (!tags || (sg.laid & tags))
		return;
	sg.laid |= tags;
	XGrabServer(dpy);
	m->tagset[m->seltags] = tags;
	pertagload(m, tags); /* that tag's own layout */
	arrangemon(m);
	m->tagset[m->seltags] = save;
	pertagload(m, save);
	sg.shown = 0;
	swipeplace();
	XUngrabServer(dpy);
	XFlush(dpy);
}

static double
swipesince(struct timespec *a)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (t.tv_sec - a->tv_sec) * 1e3 + (t.tv_nsec - a->tv_nsec) / 1e6;
}

/* one frame: every window of both tags moves in one server grab, so picom never draws a
 * frame with some moved and some not */
static void
swipeshow(void)
{
	if ((int)sg.off == sg.placed)
		return;
	sg.placed = (int)sg.off;
	XGrabServer(dpy);
	swipeplace();
	XUngrabServer(dpy);
	XFlush(dpy);
}

static void
swipestart(void)
{
	Monitor *m = selmon;
	Client *c;
	unsigned int occ = 0, cur = m->tagset[m->seltags], i, n = LENGTH(tags);

	for (c = m->clients; c; c = c->next)
		if (!c->issticky && !c->isscratch)
			occ |= c->tags & TAGMASK;
	sg.m = m;
	sg.cur = cur;
	sg.prev = sg.next = sg.shown = sg.laid = 0;
	for (i = 0; i < n; i++) /* first occupied tag below the lowest one shown */
		if (cur & 1 << i)
			break;
	while (i-- > 0)
		if (occ & 1 << i) {
			sg.prev = 1 << i;
			break;
		}
	for (i = n; i-- > 0;) /* first occupied tag above the highest one shown */
		if (cur & 1 << i)
			break;
	for (i++; i < n; i++)
		if (occ & 1 << i) {
			sg.next = 1 << i;
			break;
		}
	for (c = m->clients; c; c = c->next)
		if (!c->issticky && !c->isscratch && (c->tags & cur))
			swipemark(c, 1);
	sg.state = SwipeDrag;
}

/* the drag is over: either show the tag that came in, or put everything back */
static void
swipefinish(void)
{
	Monitor *m = sg.m;
	Client *c;
	XEvent ev;
	unsigned int target = sg.off < 0 ? sg.next : sg.prev;

	sg.state = SwipeIdle;
	if (sg.commit && target) {
		/* the windows are where view() puts them: it unmarks the new tag's, parks the old
		 * (off screen already, so no sliding out) */
		Arg a = {.ui = target};
		leavenone = 1;
		view(&a);
		leavenone = 0;
	} else {
		for (c = m->clients; c; c = c->next)
			if (!c->issticky && !c->isscratch && (c->tags & sg.cur)) {
				XMoveWindow(dpy, c->win, c->x, c->y);
				swipemark(c, 0);
			}
		arrange(m); /* parks the tag that peeked in again */
	}
	XSync(dpy, False);
	while (XCheckMaskEvent(dpy, EnterWindowMask, &ev)); /* windows slid under the pointer */
}

static int
swipebusy(void)
{
	return sg.state == SwipeDrag || sg.state == SwipeAnim;
}

/* something else rearranges (a new window, a key): drop the drag where it is */
static void
swipeabort(void)
{
	Client *c;

	if (sg.state != SwipeDrag && sg.state != SwipeAnim)
		return;
	sg.state = SwipeIdle;
	for (c = sg.m->clients; c; c = c->next)
		if (!c->issticky && !c->isscratch && (c->tags & sg.cur) && !c->hidden)
			swipemark(c, 0);
}

/* the frame clock (run() calls this every SWIPEFRAME ms during a drag): the touchpad reports
 * at its own uneven rate, so the windows follow the fingers smoothly at the screen's pace
 * instead of jumping at each report, then glide to the end once the fingers let go */
static void
swipeframe(void)
{
	double dt = swipesince(&sg.tf), p, e;

	if (dt < SWIPEFRAME - 0.5)
		return;
	clock_gettime(CLOCK_MONOTONIC, &sg.tf);
	if (sg.state == SwipeDrag) {
		sg.off += (sg.goal - sg.off) * (1 - exp(-dt / 12.0));
		if (fabs(sg.goal - sg.off) < 0.5)
			sg.off = sg.goal;
		swipeshow();
		return;
	}
	p = swipesince(&sg.t0) / sg.dur;
	if (p > 1)
		p = 1;
	e = 1 - (1 - p) * (1 - p) * (1 - p); /* ease out */
	sg.off = sg.from + (sg.to - sg.from) * e;
	swipeshow();
	if (p >= 1)
		swipefinish();
}

static int
swipewait(void)
{
	double left;

	if (sg.state != SwipeDrag && sg.state != SwipeAnim)
		return -1;
	left = SWIPEFRAME - swipesince(&sg.tf);
	return left > 0 ? (int)left + 1 : 0;
}

static void
swipemove(double dx, double dy, uint64_t t)
{
	Monitor *m;
	double raw, off, dt, v;
	unsigned int other;

	if (sg.state == SwipeWait) {
		sg.fx += dx;
		sg.fy += dy;
		if (fabs(sg.fx) + fabs(sg.fy) < 15)
			return;
		if (fabs(sg.fy) > fabs(sg.fx)) { /* up or down: tux-gestures' */
			sg.state = SwipeIgnore;
			return;
		}
		swipestart();
		dx = sg.fx;
		sg.fx = 0;
		sg.off = sg.goal = sg.vel = 0;
		sg.placed = 0;
		sg.t = t;
		clock_gettime(CLOCK_MONOTONIC, &sg.tf);
	} else if (sg.state != SwipeDrag)
		return;
	m = sg.m;
	sg.fx += dx;
	raw = sg.fx * m->mw / SWIPEDIST;
	if (raw < -m->mw)
		raw = -m->mw;
	if (raw > m->mw)
		raw = m->mw;
	other = raw < 0 ? sg.next : sg.prev;
	off = other ? raw : raw / 4; /* nothing that way: it only gives a little */
	if (!other && fabs(off) > m->mw / 16.0)
		off = off < 0 ? -m->mw / 16.0 : m->mw / 16.0;
	dt = ((double)t - (double)sg.t) / 1e3;
	if (dt > 0) {
		v = (off - sg.goal) / dt;
		sg.vel = sg.vel * 0.5 + v * 0.5;
	}
	sg.t = t;
	sg.goal = off;
	swipelayout(other); /* lays out the tag coming in, the first time it shows */
}

static void
swipeend(int cancelled)
{
	Monitor *m = sg.m;
	unsigned int target;
	double left;

	if (sg.state != SwipeDrag) {
		if (sg.state != SwipeAnim)
			sg.state = SwipeIdle;
		return;
	}
	/* judged by where the fingers ended (goal), glides on from where the frames have got to */
	target = sg.goal < 0 ? sg.next : sg.prev;
	sg.commit = !cancelled && target && sg.goal != 0
		&& (fabs(sg.goal) > m->mw * SWIPECOMMIT                /* far enough */
		    || (sg.vel * sg.goal > 0 && fabs(sg.vel) > 0.6)); /* or a flick that way */
	if (sg.vel * sg.goal < 0 && fabs(sg.vel) > 0.6)
		sg.commit = 0;                                        /* flicked back */
	sg.from = sg.off;
	sg.to = sg.commit ? (sg.goal < 0 ? -m->mw : m->mw) : 0;
	left = fabs(sg.to - sg.from) / m->mw;
	sg.dur = 90 + 160 * left;
	clock_gettime(CLOCK_MONOTONIC, &sg.t0);
	sg.state = SwipeAnim;
}

/* tuxcraft: Super + two-finger drag on the touchpad does what Super + right drag does with the
 * mouse (rsbegin/rsstep/rsend): on a tiled window the splits follow the fingers, a floating one
 * is resized from its bottom-right corner. The window under the pointer takes the focus first,
 * as a click would. Super must be down when the fingers start; the scroll that X also sends is
 * kept from the window by the Super + wheel buttons in config.h. */
#ifndef TFRESIZE
#define TFRESIZE 1.5        /* pixels per unit of two-finger travel */
#endif
static struct {
	int state;              /* 0 idle, 1 resizing, 2 not ours until the fingers stop */
	double x, y;
	struct timespec t;      /* last step */
} tf;

static void
tfscroll(double dx, double dy, int stop)
{
	Window r, ch;
	int rx, ry, wx, wy;
	unsigned int mask;
	Client *c;
	struct timespec now;
	double ms;

	if (stop) {
		if (tf.state == 1) {
			rsstep((int)tf.x, (int)tf.y); /* where the fingers ended */
			rsend();
		}
		tf.state = 0;
		return;
	}
	if (tf.state == 0) {
		tf.state = 2;
		if (sg.state != SwipeIdle)
			return;
		if (!XQueryPointer(dpy, root, &r, &ch, &rx, &ry, &wx, &wy, &mask) || !(mask & MODKEY))
			return;
		if (!(c = wintoclient(ch)) || c->leaving)
			return;
		if (c->mon != selmon || c != selmon->sel) {
			selmon = c->mon;
			focus(c);
		}
		if (!rsbegin(c))
			return;
		tf.state = 1;
		tf.x = tf.y = 0;
		tf.t.tv_sec = tf.t.tv_nsec = 0;
	}
	if (tf.state != 1)
		return;
	tf.x += dx * TFRESIZE;
	tf.y += dy * TFRESIZE;
	clock_gettime(CLOCK_MONOTONIC, &now);
	ms = (now.tv_sec - tf.t.tv_sec) * 1e3 + (now.tv_nsec - tf.t.tv_nsec) / 1e6;
	if (ms < 1000.0 / refreshrate) /* as the mouse: no more redraws than the screen shows */
		return;
	tf.t = now;
	rsstep((int)tf.x, (int)tf.y);
}

static void
swipeevents(void)
{
	struct libinput_event *e;
	struct libinput_event_gesture *g;
	struct libinput_device *d;
	int gest;

	libinput_dispatch(li);
	while ((e = libinput_get_event(li))) {
		switch (libinput_event_get_type(e)) {
		case LIBINPUT_EVENT_DEVICE_ADDED:
			d = libinput_event_get_device(e);
			if (libinput_device_has_capability(d, LIBINPUT_DEVICE_CAP_GESTURE)) {
				lipads++;
				swipeprop();
			} else /* keyboards, mice: not needed here (X still gets them) */
				libinput_device_config_send_events_set_mode(d, LIBINPUT_CONFIG_SEND_EVENTS_DISABLED);
			break;
		case LIBINPUT_EVENT_DEVICE_REMOVED:
			d = libinput_event_get_device(e);
			gest = libinput_device_has_capability(d, LIBINPUT_DEVICE_CAP_GESTURE);
			if (gest && --lipads <= 0) {
				lipads = 0;
				swipeprop();
			}
			break;
		case LIBINPUT_EVENT_POINTER_SCROLL_FINGER: {
			struct libinput_event_pointer *pe = libinput_event_get_pointer_event(e);
			int hx = libinput_event_pointer_has_axis(pe, LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL);
			int hy = libinput_event_pointer_has_axis(pe, LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL);
			double x = hx ? libinput_event_pointer_get_scroll_value(pe, LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL) : 0;
			double y = hy ? libinput_event_pointer_get_scroll_value(pe, LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL) : 0;
			tfscroll(x, y, x == 0 && y == 0); /* both 0: the fingers stopped or lifted */
			break;
		}
		case LIBINPUT_EVENT_GESTURE_SWIPE_BEGIN:
			g = libinput_event_get_gesture_event(e);
			if (sg.state == SwipeIdle && libinput_event_gesture_get_finger_count(g) == SWIPEFINGERS) {
				sg.state = SwipeWait;
				sg.fx = sg.fy = 0;
			}
			break;
		case LIBINPUT_EVENT_GESTURE_SWIPE_UPDATE:
			g = libinput_event_get_gesture_event(e);
			swipemove(libinput_event_gesture_get_dx(g), libinput_event_gesture_get_dy(g),
				libinput_event_gesture_get_time_usec(g));
			break;
		case LIBINPUT_EVENT_GESTURE_SWIPE_END:
			g = libinput_event_get_gesture_event(e);
			swipeend(libinput_event_gesture_get_cancelled(g));
			break;
		default:
			break;
		}
		libinput_event_destroy(e);
	}
}

static void
swipeinit(void)
{
	tuxswipeatom = XInternAtom(dpy, "_TUX_DWM_SWIPE", False);
	if (!(lidev = udev_new()))
		return;
	if (!(li = libinput_udev_create_context(&liiface, NULL, lidev))
	|| libinput_udev_assign_seat(li, "seat0") != 0) {
		if (li)
			libinput_unref(li);
		li = NULL;
		udev_unref(lidev);
		lidev = NULL;
		return;
	}
	swipeevents(); /* the devices there now */
	if (!lipads) { /* no touchpad (a desktop): no reason to read the mouse and keyboard */
		libinput_unref(li);
		li = NULL;
		udev_unref(lidev);
		lidev = NULL;
	}
	swipeprop();
}

static void
swipecleanup(void)
{
	if (li)
		libinput_unref(li);
	if (lidev)
		udev_unref(lidev);
	li = NULL;
	lidev = NULL;
	if (tuxswipeatom)
		XDeleteProperty(dpy, root, tuxswipeatom);
}
#else
static void swipeinit(void) {}
static void swipecleanup(void) {}
static void swipeabort(void) {}
static int swipebusy(void) { return 0; }
#endif

/* tuxcraft: windows leaving with their tag slide out to their side (showhide starts it), moved
 * by dwm on its frame clock: picom does not draw a window whose real place is off screen. */
#ifndef LEAVEMS
#define LEAVEMS 140.0       /* how long the old tag takes to slide out (ms), as picom's glide in */
#endif
static int leaveanim;
static struct timespec leavet0, leavetf;

static double
leavesince(struct timespec *a)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (t.tv_sec - a->tv_sec) * 1e3 + (t.tv_nsec - a->tv_nsec) / 1e6;
}

static void
leavestart(void)
{
	if (leaveanim)
		return; /* already running: this window joins in (a tag of several windows) */
	leaveanim = 1;
	clock_gettime(CLOCK_MONOTONIC, &leavet0);
	leavetf.tv_sec = 0;
	leavetf.tv_nsec = 0;
}

static int
leavewait(void)
{
	double left;

	if (!leaveanim)
		return -1;
	left = 6 - leavesince(&leavetf);
	return left > 0 ? (int)left + 1 : 0;
}

static void
leaveframe(void)
{
	double p, e;
	Monitor *m;
	Client *c;
	int any = 0;

	if (!leaveanim || leavesince(&leavetf) < 5.5)
		return;
	clock_gettime(CLOCK_MONOTONIC, &leavetf);
	p = leavesince(&leavet0) / LEAVEMS;
	if (p > 1)
		p = 1;
	e = 1 - (1 - p) * (1 - p) * (1 - p); /* ease out */
	XGrabServer(dpy);
	for (m = mons; m; m = m->next)
		for (c = m->clients; c; c = c->next) {
			if (!c->leaving)
				continue;
			if (p >= 1) {
				c->leaving = 0;
				XMoveWindow(dpy, c->win, c->lpark, c->y);
			} else {
				XMoveWindow(dpy, c->win, c->lx0 + (int)((c->lx1 - c->lx0) * e), c->y);
				any = 1;
			}
		}
	XUngrabServer(dpy);
	XFlush(dpy);
	leaveanim = any;
}

void
run(void)
{
	XEvent ev; /* store any type of X11 event received - keypress, mouse, etc. */
	/* tuxcraft: wait for X and the touchpad (libinput) at once, and tick the frames of a
	 * touchpad drag and of a tag sliding out */
	struct pollfd pfd[2];
	int n, wait, lw;

	XSync(dpy, False);
	while (running) {
		while (running && XPending(dpy)) { /* XPending also sends what is queued */
			XNextEvent(dpy, &ev);
			if (handler[ev.type])
				handler[ev.type](&ev);
		}
		if (!running)
			break;
		pfd[0].fd = ConnectionNumber(dpy);
		pfd[0].events = POLLIN;
		n = 1;
		wait = -1;
#ifdef TUXSWIPE
		if (li) {
			pfd[1].fd = libinput_get_fd(li);
			pfd[1].events = POLLIN;
			pfd[1].revents = 0;
			n = 2;
		}
		wait = swipewait();
#endif
		lw = leavewait();
		if (lw >= 0 && (wait < 0 || lw < wait))
			wait = lw;
		if (poll(pfd, n, wait) < 0 && errno != EINTR)
			die("dwm: poll:");
#ifdef TUXSWIPE
		if (n == 2 && (pfd[1].revents & POLLIN))
			swipeevents();
		if (sg.state == SwipeDrag || sg.state == SwipeAnim)
			swipeframe();
#endif
		leaveframe();
	}
}

void
scan(void)
{
	unsigned int i, num;
	Window d1, d2, *wins = NULL;
	XWindowAttributes wa;

	if (XQueryTree(dpy, root, &d1, &d2, &wins, &num)) {
		for (i = 0; i < num; i++) {
			if (!XGetWindowAttributes(dpy, wins[i], &wa)
			|| wa.override_redirect || XGetTransientForHint(dpy, wins[i], &d1))
				continue;
			if (wa.map_state == IsViewable || getstate(wins[i]) == IconicState)
				manage(wins[i], &wa);
		}
		for (i = 0; i < num; i++) { /* now the transients */
			if (!XGetWindowAttributes(dpy, wins[i], &wa))
				continue;
			if (XGetTransientForHint(dpy, wins[i], &d1)
			&& (wa.map_state == IsViewable || getstate(wins[i]) == IconicState))
				manage(wins[i], &wa);
		}
		if (wins)
			XFree(wins);
	}
}

void
sendmon(Client *c, Monitor *m)
{
	if (c->mon == m)
		return;
	unfocus(c, 1);
	detach(c);
	detachstack(c);
	c->mon = m;
	c->tags = m->tagset[m->seltags]; /* assign tags of target monitor */
	attach(c);
	attachstack(c);
	focus(NULL);
	arrange(NULL);
}

void
setclientstate(Client *c, long state)
{
	long data[] = { state, None };

	XChangeProperty(dpy, c->win, wmatom[WMState], wmatom[WMState], 32,
		PropModeReplace, (unsigned char *)data, 2);
}

int
sendevent(Window w, Atom proto, int mask, long d0, long d1, long d2, long d3, long d4)
{
	int n;
	Atom *protocols, mt;
	int exists = 0;
	XEvent ev;

	if (proto == wmatom[WMTakeFocus] || proto == wmatom[WMDelete]) {
		mt = wmatom[WMProtocols];
		if (XGetWMProtocols(dpy, w, &protocols, &n)) {
			while (!exists && n--)
				exists = protocols[n] == proto;
			XFree(protocols);
		}
	}
	else {
		exists = True;
		mt = proto;
	}

	if (exists) {
		ev.type = ClientMessage;
		ev.xclient.window = w;
		ev.xclient.message_type = mt;		
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = d0;
		ev.xclient.data.l[1] = d1;
		ev.xclient.data.l[2] = d2;
		ev.xclient.data.l[3] = d3;
		ev.xclient.data.l[4] = d4;
		XSendEvent(dpy, w, False, mask, &ev);		
	}
	return exists;
}

void
setfocus(Client *c)
{
	if (!c->neverfocus) {
		XSetInputFocus(dpy, c->win, RevertToPointerRoot, CurrentTime);
		XChangeProperty(dpy, root, netatom[NetActiveWindow],
			XA_WINDOW, 32, PropModeReplace,
			(unsigned char *) &(c->win), 1);
	}
	sendevent(c->win, wmatom[WMTakeFocus], NoEventMask, wmatom[WMTakeFocus], CurrentTime, 0, 0, 0);
}

void
setfullscreen(Client *c, int fullscreen)
{
	if (ispopup(c))
		return;

	if (fullscreen && !c->isfullscreen) {
		XChangeProperty(dpy, c->win, netatom[NetWMState], XA_ATOM, 32,
			PropModeReplace, (unsigned char*)&netatom[NetWMFullscreen], 1);
		c->isfullscreen = 1;
		c->oldstate = c->isfloating;
		c->oldbw = c->bw;
		c->bw = 0;
		c->isfloating = 1;
		resizeclient(c, c->mon->mx, c->mon->my, c->mon->mw, c->mon->mh);
		XRaiseWindow(dpy, c->win);
	} else if (!fullscreen && c->isfullscreen){
		XChangeProperty(dpy, c->win, netatom[NetWMState], XA_ATOM, 32,
			PropModeReplace, (unsigned char*)0, 0);
		c->isfullscreen = 0;
		c->isfloating = c->oldstate;
		c->bw = c->oldbw;
		c->x = c->oldx;
		c->y = c->oldy;
		c->w = c->oldw;
		c->h = c->oldh;
		resizeclient(c, c->x, c->y, c->w, c->h);
		arrange(c->mon);
	}
}



void
	 setsticky(Client *c, int sticky)
	 {

		 if(sticky && !c->issticky) {
			 XChangeProperty(dpy, c->win, netatom[NetWMState], XA_ATOM, 32,
					 PropModeReplace, (unsigned char *) &netatom[NetWMSticky], 1);
			 c->issticky = 1;
		 } else if(!sticky && c->issticky){
			 XChangeProperty(dpy, c->win, netatom[NetWMState], XA_ATOM, 32,
					 PropModeReplace, (unsigned char *)0, 0);
			 c->issticky = 0;
			 arrange(c->mon);
		 }
	 }


void
setlayout(const Arg *arg)
{
	if (!arg || !arg->v || arg->v != selmon->lt[selmon->sellt])
		selmon->sellt ^= 1;
	if (arg && arg->v)
		selmon->lt[selmon->sellt] = (Layout *)arg->v;
	strncpy(selmon->ltsymbol, selmon->lt[selmon->sellt]->symbol, sizeof selmon->ltsymbol);
	pertagkeep(selmon);
	pertagsave();
	if (selmon->sel)
		arrange(selmon);
	else
		drawbar(selmon);
}

/* arg > 1.0 will set mfact absolutely */
void
setmfact(const Arg *arg)
{
	float f;

	if (!arg || !selmon->lt[selmon->sellt]->arrange)
		return;
	f = arg->f < 1.0 ? arg->f + selmon->mfact : arg->f - 1.0;
	if (f < 0.05 || f > 0.95)
		return;
	selmon->mfact = f;
	pertagkeep(selmon);
	pertagsave();
	arrange(selmon);
}

void
setup(void)
{
	int i;
	XSetWindowAttributes wa;
	Atom utf8string;
	struct sigaction sa;

	/* do not transform children into zombies when they terminate */
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_NOCLDSTOP | SA_NOCLDWAIT | SA_RESTART;
	sa.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &sa, NULL);

	/* clean up any zombies (inherited from .xinitrc etc) immediately */
	while (waitpid(-1, NULL, WNOHANG) > 0);

	signal(SIGHUP, sighup);
	signal(SIGTERM, sigterm);

	/* init screen */
	screen = DefaultScreen(dpy); /* gets the default screen number from the display (dpy) */
	sw = DisplayWidth(dpy, screen);
	sh = DisplayHeight(dpy, screen);
	root = RootWindow(dpy, screen); /* dwm attaches to the root window so it can recieve global events */
	drw = drw_create(dpy, screen, root, sw, sh); /* a drawing context for rendering the UI (like the bar) */
	{ /* tuxcraft: RENDER draws the bar's text (Xft); see xerror */
		int ev, er;
		if (!XQueryExtension(dpy, "RENDER", &renderop, &ev, &er))
			renderop = -1;
	}
	if (!drw_fontset_create(drw, fonts, LENGTH(fonts)))
		die("no fonts could be loaded.");
	lrpad = drw->fonts->h; /* sets lrpad to the height of the font, for correct spacing in bar */
	bh = drw->fonts->h + 2;
	updategeom(); /* setting up monitor geometry, if using multiple monitors, creates a linked list of monitor structs */
	/* init X11 atoms */
	/* this is asking the X server for an atom (a unique integer) corresponding to each string */
	/* if it exists already, the atom ID is returned */
	utf8string = XInternAtom(dpy, "UTF8_STRING", False);
	wmatom[WMProtocols] = XInternAtom(dpy, "WM_PROTOCOLS", False);
	wmatom[WMDelete] = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
	wmatom[WMState] = XInternAtom(dpy, "WM_STATE", False);
	wmatom[WMTakeFocus] = XInternAtom(dpy, "WM_TAKE_FOCUS", False);
	netatom[NetActiveWindow] = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
	netatom[NetSupported] = XInternAtom(dpy, "_NET_SUPPORTED", False);
	netatom[NetSystemTray] = XInternAtom(dpy, "_NET_SYSTEM_TRAY_S0", False);
	netatom[NetSystemTrayOP] = XInternAtom(dpy, "_NET_SYSTEM_TRAY_OPCODE", False);
	netatom[NetSystemTrayOrientation] = XInternAtom(dpy, "_NET_SYSTEM_TRAY_ORIENTATION", False);
	netatom[NetSystemTrayOrientationHorz] = XInternAtom(dpy, "_NET_SYSTEM_TRAY_ORIENTATION_HORZ", False);	
	netatom[NetWMName] = XInternAtom(dpy, "_NET_WM_NAME", False);
	netatom[NetWMState] = XInternAtom(dpy, "_NET_WM_STATE", False);
	netatom[NetWMCheck] = XInternAtom(dpy, "_NET_SUPPORTING_WM_CHECK", False);
	netatom[NetWMFullscreen] = XInternAtom(dpy, "_NET_WM_STATE_FULLSCREEN", False);
	netatom[NetWMSticky] = XInternAtom(dpy, "_NET_WM_STATE_STICKY", False);
	netatom[NetWMWindowType] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
	netatom[NetWMWindowTypeDialog] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DIALOG", False);
	netatom[NetWMWindowTypeDock] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
	netatom[NetWMWindowTypeMenu] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_MENU", False);
	netatom[NetWMWindowTypeNotification] = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_NOTIFICATION", False);
	netatom[NetClientList] = XInternAtom(dpy, "_NET_CLIENT_LIST", False);
	xatom[Manager] = XInternAtom(dpy, "MANAGER", False);
	xatom[Xembed] = XInternAtom(dpy, "_XEMBED", False);
	xatom[XembedInfo] = XInternAtom(dpy, "_XEMBED_INFO", False);
	netatom[NetNumberOfDesktops] = XInternAtom(dpy, "_NET_NUMBER_OF_DESKTOPS", False);
	netatom[NetCurrentDesktop] = XInternAtom(dpy, "_NET_CURRENT_DESKTOP", False);
	netatom[NetDesktopNames] = XInternAtom(dpy, "_NET_DESKTOP_NAMES", False);
	netatom[NetWMDesktop] = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
	tuxcmdatom = XInternAtom(dpy, "_TUX_DWM_CMD", False);
	tuxtagsatom = XInternAtom(dpy, "_TUX_DWM_TAGS", False);
	tuxviewatom = XInternAtom(dpy, "_TUX_DWM_VIEW", False);
	tuxhiddenatom = XInternAtom(dpy, "_TUX_DWM_HIDDEN", False);
	tuxglideatom = XInternAtom(dpy, "_TUX_DWM_GLIDE", False);
	tuxstillatom = XInternAtom(dpy, "_TUX_DWM_STILL", False);
	/* init cursors */
	cursor[CurNormal] = drw_cur_create(drw, XC_left_ptr);
	cursor[CurResize] = drw_cur_create(drw, XC_sizing);
	cursor[CurMove] = drw_cur_create(drw, XC_fleur);
	/* init appearance */
	scheme = ecalloc(LENGTH(colors), sizeof(Clr *)); /* allocates memory to set up colorschemes */
	for (i = 0; i < LENGTH(colors); i++)
		scheme[i] = drw_scm_create(drw, colors[i], 3); /* each scheme[i] corresponds to a SchemeNorm, SchemeSel, etc */
	/* init system tray */
	updatesystray();	
	/* init bars */
	updatebars(); /* creates a bar window for each monitor */
	updatestatus(); /* renders the status text */
	/* supporting window for NetWMCheck */
	wmcheckwin = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0); /* a dummy window created so applications can detect the WM */
	/* setting X11 properties so applications know that dwm is the window manager, and supports EWMH hints */
	XChangeProperty(dpy, wmcheckwin, netatom[NetWMCheck], XA_WINDOW, 32,
		PropModeReplace, (unsigned char *) &wmcheckwin, 1);
	XChangeProperty(dpy, wmcheckwin, netatom[NetWMName], utf8string, 8,
		PropModeReplace, (unsigned char *) "dwm", 3);
	XChangeProperty(dpy, root, netatom[NetWMCheck], XA_WINDOW, 32,
		PropModeReplace, (unsigned char *) &wmcheckwin, 1);
	/* EWMH support per view */
	XChangeProperty(dpy, root, netatom[NetSupported], XA_ATOM, 32,
		PropModeReplace, (unsigned char *) netatom, NetLast);
	XDeleteProperty(dpy, root, netatom[NetClientList]);
	XDeleteProperty(dpy, root, tuxcmdatom);
	{ /* tuxcraft: workspaces for pagers and window switchers (rofi -show window) */
		long n = LENGTH(tags);
		char names[LENGTH(tags) * 8];
		size_t len = 0;
		XChangeProperty(dpy, root, netatom[NetNumberOfDesktops], XA_CARDINAL, 32,
			PropModeReplace, (unsigned char *)&n, 1);
		for (i = 0; i < (int)LENGTH(tags); i++) {
			size_t l = strlen(tags[i]);
			if (len + l + 1 > sizeof names)
				break;
			memcpy(names + len, tags[i], l + 1);
			len += l + 1;
		}
		XChangeProperty(dpy, root, netatom[NetDesktopNames], utf8string, 8,
			PropModeReplace, (unsigned char *)names, len);
	}
	/* select events */
	wa.cursor = cursor[CurNormal]->cursor;
	wa.event_mask = SubstructureRedirectMask|SubstructureNotifyMask
		|ButtonPressMask|PointerMotionMask|EnterWindowMask
		|LeaveWindowMask|StructureNotifyMask|PropertyChangeMask; /* X11 events that dwm will listen for */
	XChangeWindowAttributes(dpy, root, CWEventMask|CWCursor, &wa); /* applies the event mask and cursor to the root window */
	XSelectInput(dpy, root, wa.event_mask);
	grabkeys(); /* register the keybinds in config.h */
	swipeinit(); /* tuxcraft: touchpad swipe between tags */
	focus(NULL); /* focus needs to start cleanly */
}

void
seturgent(Client *c, int urg)
{
	XWMHints *wmh;

	c->isurgent = urg;
	if (!(wmh = XGetWMHints(dpy, c->win)))
		return;
	wmh->flags = urg ? (wmh->flags | XUrgencyHint) : (wmh->flags & ~XUrgencyHint);
	XSetWMHints(dpy, c->win, wmh);
	XFree(wmh);
}

void
showhide(Client *c)
{
	if (!c)
		return;
	/* tuxcraft: dwm hides a window by moving it off screen. _TUX_DWM_HIDDEN is on it while it
	 * is hidden (set before it leaves), so picom's "geometry" animation (dwm.conf) neither
	 * slides it out nor moves it across the screen when it is parked on the other side.
	 * Windows of lower tags wait off the left edge, those of higher tags off the right edge,
	 * and the mark comes off before a window comes back: picom then glides it in from its
	 * side, so the next tag slides in from the right and the previous one from the left, the
	 * way the fingers move on the touchpad (tux-gestures). A window coming back also gets
	 * _TUX_DWM_GLIDE, set before the move and taken off only at its next move or resize
	 * (resizeclient), so picom can give a tag switch a plain glide and tiling its own
	 * animation; marks taken off in the same breath as a move would race picom. A window
	 * leaving with its tag slides out to its side while the new tag glides in, moved by dwm
	 * itself (leaveframe): picom does not draw a window whose real place is off screen, so
	 * it cannot animate one going there. */
	if (ISVISIBLE(c)) {
		/* show clients top down */
		c->leaving = 0; /* back before it had slid out: glides in from where it is */
		if (c->hidden) {
			long one = 1;
			XChangeProperty(dpy, c->win, tuxglideatom, XA_CARDINAL, 32, PropModeReplace,
				(unsigned char *)&one, 1);
			c->glide = 1;
			XDeleteProperty(dpy, c->win, tuxhiddenatom);
			c->hidden = 0;
		}
		XMoveWindow(dpy, c->win, c->x, c->y);
		if ((!c->mon->lt[c->mon->sellt]->arrange || c->isfloating) && !c->isfullscreen)
			resize(c, c->x, c->y, c->w, c->h, 0);
		showhide(c->snext);
	} else {
		/* hide clients bottom up */
		showhide(c->snext);
		if (c->glide) {
			XDeleteProperty(dpy, c->win, tuxglideatom);
			c->glide = 0;
		}
		/* lowest tag of the window against the lowest tag shown */
		unsigned int cur = c->mon->tagset[c->mon->seltags];
		int left = (c->tags & -c->tags) < (cur & -cur);
		int park = left ? WIDTH(c) * -2 : sw + WIDTH(c);
		if (!c->hidden) {
			long one = 1;
			XChangeProperty(dpy, c->win, tuxhiddenatom, XA_CARDINAL, 32, PropModeReplace,
				(unsigned char *)&one, 1);
			c->hidden = 1;
			if (!leavenone && !c->isfullscreen && c->x < c->mon->mx + c->mon->mw
			&& c->x + WIDTH(c) > c->mon->mx) {
				/* on screen: slide out to its side first (leaveframe), then park */
				c->leaving = 1;
				c->lx0 = c->x;
				c->lx1 = left ? c->mon->mx - WIDTH(c) : c->mon->mx + c->mon->mw;
				c->lpark = park;
				leavestart();
				return;
			}
		} else if (c->leaving) {
			c->lpark = park; /* still sliding out: its slide decides, it parks at the end */
			return;
		}
		XMoveWindow(dpy, c->win, park, c->y);
	}
}


pid_t
getstatusbarpid(void)
{
	char buf[32], *str = buf, *c;
	FILE *fp;

	if (statuspid > 0) {
		snprintf(buf, sizeof(buf), "/proc/%u/cmdline", statuspid);
		if ((fp = fopen(buf, "r"))) {
			fgets(buf, sizeof(buf), fp);
			while ((c = strchr(str, '/')))
				str = c + 1;
			fclose(fp);
			if (!strcmp(str, STATUSBAR))
				return statuspid;
		}
	}

	/* tuxcraft: pgrep on every distro (pidof is not always installed), this user's only */
	if (!(fp = popen("pgrep -o -x -U \"$(id -u)\" "STATUSBAR, "r")))
		return -1;


	fgets(buf, sizeof(buf), fp);
	pclose(fp);
	return strtol(buf, NULL, 10);
}

void
sigstatusbar(const Arg *arg)
{
	union sigval sv;

	if (!statussig)
		return;
	sv.sival_int = arg->i;
	if ((statuspid = getstatusbarpid()) <= 0)
		return;

	sigqueue(statuspid, SIGRTMIN+statussig, sv);
}


void
sighup(int unused)
{
	Arg a = {.i = 1};
	quit(&a);
}

void
sigterm(int unused)
{
	Arg a = {.i = 0};
	quit(&a);
}

void
spawn(const Arg *arg)
{ /* runs shell commands, ie. launching programs from keybinds */
	struct sigaction sa;

	if (arg->v == dmenucmd)
		dmenumon[0] = '0' + selmon->num;
	if (fork() == 0) {
		if (dpy)
			close(ConnectionNumber(dpy));
		setsid();

		sigemptyset(&sa.sa_mask);
		sa.sa_flags = 0;
		sa.sa_handler = SIG_DFL;
		sigaction(SIGCHLD, &sa, NULL);

		execvp(((char **)arg->v)[0], (char **)arg->v);
		die("dwm: execvp '%s' failed:", ((char **)arg->v)[0]);
	}
}

int
stackpos(const Arg *arg) {
	int n, i;
	Client *c, *l;

	if(!selmon->clients)
		return -1;

	if(arg->i == PREVSEL) {
		for(l = selmon->stack; l && (!ISVISIBLE(l) || l == selmon->sel); l = l->snext);
		if(!l)
			return -1;
		for(i = 0, c = selmon->clients; c != l; i += ISVISIBLE(c) ? 1 : 0, c = c->next);
		return i;
	}
	else if(ISINC(arg->i)) {
		if(!selmon->sel)
			return -1;
		for(i = 0, c = selmon->clients; c != selmon->sel; i += ISVISIBLE(c) ? 1 : 0, c = c->next);
		for(n = i; c; n += ISVISIBLE(c) ? 1 : 0, c = c->next);
		return MOD(i + GETINC(arg->i), n);
	}
	else if(arg->i < 0) {
		for(i = 0, c = selmon->clients; c; i += ISVISIBLE(c) ? 1 : 0, c = c->next);
		return MAX(i + arg->i, 0);
	}
	else
		return arg->i;
}

void
tag(const Arg *arg)
{
	if (selmon->sel && arg->ui & TAGMASK) {
		selmon->sel->tags = arg->ui & TAGMASK;
		selmon->sel->isscratch = 0;
		focus(NULL);
		arrange(selmon);
	}
}

void
spawntag(const Arg *arg)
{
	if (arg->ui & TAGMASK) {
		for (int i = LENGTH(tags); i >= 0; i--) {
			if (arg->ui & 1<<i) {
				spawn(&tagexec[i]);
				return;
			}
		}
	}
}

void
tagmon(const Arg *arg)
{
	if (!selmon->sel || !mons->next)
		return;
	sendmon(selmon->sel, dirtomon(arg->i));
}


/* layouts no longer needed here because of vanitygaps.c */

/*
void
tile(Monitor *m)
{
	unsigned int i, n, h, mw, my, ty;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), n++);
	if (n == 0)
		return;

	if (n > m->nmaster)
		mw = m->nmaster ? m->ww * m->mfact : 0;
	else
		mw = m->ww;
	for (i = my = ty = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++)
		if (i < m->nmaster) {
			h = (m->wh - my) / (MIN(n, m->nmaster) - i);
			resize(c, m->wx, m->wy + my, mw - (2*c->bw), h - (2*c->bw), 0);
			if (my + HEIGHT(c) < m->wh)
				my += HEIGHT(c);
		} else {
			h = (m->wh - ty) / (n - i);
			resize(c, m->wx + mw, m->wy + ty, m->ww - mw - (2*c->bw), h - (2*c->bw), 0);
			if (ty + HEIGHT(c) < m->wh)
				ty += HEIGHT(c);
		}
}
*/

/*
void
spiral(Monitor *m)
// spiral layout for use with fullgaps, mostly works
// every iteration splits remaining space in half, altering direction
// even splits horiz, odd splits vert
// final window takes remaining area
{
	unsigned int i, n;
	int nx, ny, nw, nh;
	Client *c;

	for (n = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), n++); // loop all tiled windows
	if (n == 0) // if no tiles then exit
		return;

	nx = m->wx + m->gap->gappx; // set geometry while respecting gaps
	ny = m->wy + m->gap->gappx;
	nw = m->ww - 2 * m->gap->gappx; // double for inner gaps
	nh = m->wh - 2 * m->gap->gappx;

	for (i = 0, c = nexttiled(m->clients); c; c = nexttiled(c->next), i++) {
		if (i == n - 1) { // give the final window all remaining space
			resize(c, nx, ny, nw - 2 * c->bw, nh - 2 * c->bw, 0); // adjust size for client's border
		} else if (i % 2) { // odd indexed windows get top half (vertically)
			resize(c, nx, ny, nw - 2 * c->bw, nh / 2 - m->gap->gappx - 2 * c->bw, 0); // resize to half height minus inner gap
			ny += nh / 2 + m->gap->gappx; // move ny to next available vert space
			nh -= nh / 2 + m->gap->gappx; // reduce nh accordingly
		} else { // now deal with even index --> left half horizontally
			resize(c, nx, ny, nw / 2 - m->gap->gappx - 2 * c->bw, nh - 2 * c->bw, 0); // same logic as w/ the odds
			nx += nw / 2 + m->gap->gappx;
			nw -= nw / 2 + m->gap->gappx;
		}
	}
}
*/

void
togglebar(const Arg *arg)
{
	selmon->showbar = !selmon->showbar;
	updatebarpos(selmon);
	resizebarwin(selmon);
	if (showsystray) {
		XWindowChanges wc;
		if (!selmon->showbar)
			wc.y = -bh;
		else if (selmon->showbar) {
			wc.y = 0;
			if (!selmon->topbar)
				wc.y = selmon->mh - bh;
		}
		XConfigureWindow(dpy, systray->win, CWY, &wc);
	}	
	arrange(selmon);
}

void
togglebarcolor(const Arg *arg)
{ /* this really needs to be integrated with the other toggle bar stuff */
	Clr tmp;
	tmp = scheme[SchemeTagsNorm][ColBorder];
	scheme[SchemeTagsNorm][ColBorder] = scheme[SchemeTagsNorm][ColBg];
	scheme[SchemeTagsNorm][ColBg] = tmp;
	tmp = scheme[SchemeTagsSel][ColFg];
	scheme[SchemeTagsSel][ColFg] = scheme[SchemeTagsSel][ColBg];
	scheme[SchemeTagsSel][ColBg] = tmp;
	tmp = scheme[SchemeSel][ColFg];
	scheme[SchemeSel][ColFg] = scheme[SchemeSel][ColBg];
	scheme[SchemeSel][ColBg] = tmp;
	arrange(selmon);
}

void
togglebartags(const Arg *arg)
{
    selmon->showtags = !selmon->showtags;
	arrange(selmon);
}

void
togglebartitle(const Arg *arg)
{
    selmon->showtitle = !selmon->showtitle;
	arrange(selmon);
}

void
togglebarlt(const Arg *arg)
{
    selmon->showlayout = !selmon->showlayout;
	arrange(selmon);
}

void
togglebarstatus(const Arg *arg)
{
    selmon->showstatus = !selmon->showstatus;
	arrange(selmon);
}

void
togglebarfloat(const Arg *arg)
{
    selmon->showfloating = !selmon->showfloating;
	arrange(selmon);
}

void
togglefloating(const Arg *arg)
{
	if (!selmon->sel)
		return;
	if (selmon->sel->isfullscreen) /* no support for fullscreen windows */
		return;
	selmon->sel->isfloating = !selmon->sel->isfloating || selmon->sel->isfixed;
	if (selmon->sel->isfloating)
		resize(selmon->sel, selmon->sel->x, selmon->sel->y,
			selmon->sel->w, selmon->sel->h, 0);
	arrange(selmon);
}

void
togglesticky(const Arg *arg)
{
	if (!selmon->sel)
		return;
	setsticky(selmon->sel, !selmon->sel->issticky);
	arrange(selmon);
}

void
togglefullscreen(const Arg *arg)
{
	if (selmon->sel){
		setfullscreen(selmon->sel, !selmon->sel->isfullscreen);
	}
}

void
toggletag(const Arg *arg)
{
	unsigned int newtags;

	if (!selmon->sel)
		return;
	newtags = selmon->sel->tags ^ (arg->ui & TAGMASK);
	if (newtags) {
		selmon->sel->tags = newtags;
		focus(NULL);
		arrange(selmon);
	}
}

void
toggleview(const Arg *arg)
{
	unsigned int newtagset = selmon->tagset[selmon->seltags] ^ (arg->ui & TAGMASK);

	if (newtagset) {
		selmon->tagset[selmon->seltags] = newtagset;
		pertagload(selmon, newtagset);
		focus(NULL);
		arrange(selmon);
	}
}

void
unfocus(Client *c, int setfocus)
{
	if (!c)
		return;
	grabbuttons(c, 0);
	XSetWindowBorder(dpy, c->win, scheme[SchemeNorm][ColBorder].pixel);
	if (setfocus) {
		XSetInputFocus(dpy, root, RevertToPointerRoot, CurrentTime);
		XDeleteProperty(dpy, root, netatom[NetActiveWindow]);
	}
}

void
unmanage(Client *c, int destroyed)
{ /* removing a window from dwm's control */
	Monitor *m = c->mon;
	XWindowChanges wc;
	int fullscreen = (selmon->sel == c && selmon->sel->isfullscreen)?1:0;

	if (c->swallowing) { /* handle swallowing first */
		unswallow(c);
		return;
	}

	Client *s = swallowingclient(c->win);
	if (s) { /* if a window c is being swallowed, it's reversed */
		free(s->swallowing);
		s->swallowing = NULL;
		arrange(m);
		focus(NULL);
		return;
	}

	detach(c); /* remove c from the monitor's client list */
	detachstack(c); /* remove c from the stacking order */
	if (!destroyed) { /* restore X11 properties if not destroyed */
		wc.border_width = c->oldbw;
		XGrabServer(dpy); /* avoid race conditions */
		XSetErrorHandler(xerrordummy);
		XSelectInput(dpy, c->win, NoEventMask);
		XConfigureWindow(dpy, c->win, CWBorderWidth, &wc); /* restore border */
		XDeleteProperty(dpy, c->win, tuxhiddenatom);
		XDeleteProperty(dpy, c->win, tuxglideatom);
		XDeleteProperty(dpy, c->win, tuxstillatom);
		XUngrabButton(dpy, AnyButton, AnyModifier, c->win);
		setclientstate(c, WithdrawnState);
		XSync(dpy, False);
		XSetErrorHandler(xerror);
		XUngrabServer(dpy);
	}
	free(c); /* free memory */

	if (!s) { /* recalcs layout now that c is gone */
		arrange(m);
		focus(NULL);
	if(fullscreen){ /* if fullscreen, toggle it off */
		togglefullscreen(NULL);
	}
		updateclientlist(); /* update EWMH property */
	}
}

void
unmapnotify(XEvent *e)
{
	Client *c;
	XUnmapEvent *ev = &e->xunmap;

	if ((c = wintoclient(ev->window))) {
		if (ev->send_event)
			setclientstate(c, WithdrawnState);
		else
			unmanage(c, 0);
	}
	else if ((c = wintosystrayicon(ev->window))) {
		/* KLUDGE! sometimes icons occasionally unmap their windows, but do
		 * _not_ destroy them. We map those windows back */
		XMapRaised(dpy, c->win);
		updatesystray();
	}	
}

void
updatebars(void)
{
	unsigned int w;	
	Monitor *m;
	XSetWindowAttributes wa = {
		.override_redirect = True,
		.background_pixmap = ParentRelative,
		.event_mask = ButtonPressMask|ExposureMask
	};
	XClassHint ch = {"dwm", "dwm"};
	for (m = mons; m; m = m->next) {
		if (m->barwin)
			continue;
		w = m->ww;
		if (showsystray && m == systraytomon(m))
			w -= getsystraywidth();
		m->barwin = XCreateWindow(dpy, root, m->wx, m->by, w, bh, 0, DefaultDepth(dpy, screen),
				CopyFromParent, DefaultVisual(dpy, screen),
				CWOverrideRedirect|CWBackPixmap|CWEventMask, &wa);
		XDefineCursor(dpy, m->barwin, cursor[CurNormal]->cursor);
		if (showsystray && m == systraytomon(m))
			XMapRaised(dpy, systray->win);	
		XMapRaised(dpy, m->barwin);
		XSetClassHint(dpy, m->barwin, &ch);
	}
}

void
updatebarpos(Monitor *m)
{
	m->wy = m->my;
	m->wh = m->mh;
	if (m->showbar) {
		m->wh -= bh;
		m->by = m->topbar ? m->wy : m->wy + m->wh;
		m->wy = m->topbar ? m->wy + bh : m->wy;
	} else
		m->by = -bh;
}

void
updateclientlist(void)
{
	Client *c;
	Monitor *m;

	XDeleteProperty(dpy, root, netatom[NetClientList]);
	for (m = mons; m; m = m->next)
		for (c = m->clients; c; c = c->next)
			XChangeProperty(dpy, root, netatom[NetClientList],
				XA_WINDOW, 32, PropModeAppend,
				(unsigned char *) &(c->win), 1);
}

int
updategeom(void)
{
	int dirty = 0;

#ifdef XINERAMA
	if (XineramaIsActive(dpy)) {
		int i, j, n, nn;
		Client *c;
		Monitor *m;
		XineramaScreenInfo *info = XineramaQueryScreens(dpy, &nn);
		XineramaScreenInfo *unique = NULL;

		for (n = 0, m = mons; m; m = m->next, n++);
		/* only consider unique geometries as separate screens */
		unique = ecalloc(nn, sizeof(XineramaScreenInfo));
		for (i = 0, j = 0; i < nn; i++)
			if (isuniquegeom(unique, j, &info[i]))
				memcpy(&unique[j++], &info[i], sizeof(XineramaScreenInfo));
		XFree(info);
		nn = j;

		/* new monitors if nn > n */
		for (i = n; i < nn; i++) {
			for (m = mons; m && m->next; m = m->next);
			if (m)
				m->next = createmon();
			else
				mons = createmon();
		}
		for (i = 0, m = mons; i < nn && m; m = m->next, i++)
			if (i >= n
			|| unique[i].x_org != m->mx || unique[i].y_org != m->my
			|| unique[i].width != m->mw || unique[i].height != m->mh)
			{
				dirty = 1;
				m->num = i;
				m->mx = m->wx = unique[i].x_org;
				m->my = m->wy = unique[i].y_org;
				m->mw = m->ww = unique[i].width;
				m->mh = m->wh = unique[i].height;
				updatebarpos(m);
			}
		/* removed monitors if n > nn */
		for (i = nn; i < n; i++) {
			for (m = mons; m && m->next; m = m->next);
			while ((c = m->clients)) {
				dirty = 1;
				m->clients = c->next;
				detachstack(c);
				c->mon = mons;
				attach(c);
				attachstack(c);
			}
			if (m == selmon)
				selmon = mons;
			cleanupmon(m);
		}
		free(unique);
	} else
#endif /* XINERAMA */
	{ /* default monitor setup */
		if (!mons)
			mons = createmon();
		if (mons->mw != sw || mons->mh != sh) {
			dirty = 1;
			mons->mw = mons->ww = sw;
			mons->mh = mons->wh = sh;
			updatebarpos(mons);
		}
	}
	if (dirty) {
		selmon = mons;
		selmon = wintomon(root);
		pertagread(); /* new or changed monitors: their saved layouts per tag */
	}
	return dirty;
}

void
updatenumlockmask(void)
{
	unsigned int i, j;
	XModifierKeymap *modmap;

	numlockmask = 0;
	modmap = XGetModifierMapping(dpy);
	for (i = 0; i < 8; i++)
		for (j = 0; j < modmap->max_keypermod; j++)
			if (modmap->modifiermap[i * modmap->max_keypermod + j]
				== XKeysymToKeycode(dpy, XK_Num_Lock))
				numlockmask = (1 << i);
	XFreeModifiermap(modmap);
}

void
updatesizehints(Client *c)
{
	long msize;
	XSizeHints size;

	if (!XGetWMNormalHints(dpy, c->win, &size, &msize))
		/* size is uninitialized, ensure that size.flags aren't used */
		size.flags = PSize;
	if (size.flags & PBaseSize) {
		c->basew = size.base_width;
		c->baseh = size.base_height;
	} else if (size.flags & PMinSize) {
		c->basew = size.min_width;
		c->baseh = size.min_height;
	} else
		c->basew = c->baseh = 0;
	if (size.flags & PResizeInc) {
		c->incw = size.width_inc;
		c->inch = size.height_inc;
	} else
		c->incw = c->inch = 0;
	if (size.flags & PMaxSize) {
		c->maxw = size.max_width;
		c->maxh = size.max_height;
	} else
		c->maxw = c->maxh = 0;
	if (size.flags & PMinSize) {
		c->minw = size.min_width;
		c->minh = size.min_height;
	} else if (size.flags & PBaseSize) {
		c->minw = size.base_width;
		c->minh = size.base_height;
	} else
		c->minw = c->minh = 0;
	if (size.flags & PAspect) {
		c->mina = (float)size.min_aspect.y / size.min_aspect.x;
		c->maxa = (float)size.max_aspect.x / size.max_aspect.y;
	} else
		c->maxa = c->mina = 0.0;
	c->isfixed = (c->maxw && c->maxh && c->maxw == c->minw && c->maxh == c->minh);
	c->hintsvalid = 1;
}

void
updatestatus(void)
{
	if (!gettextprop(root, XA_WM_NAME, stext, sizeof(stext)) && selmon->showstatus) {
		strcpy(stext, ""); // no shining of dwm version thru pnel, when transparent
		statusw = TEXTW(stext) - lrpad + 2;
	} else {
		char *text, *s, ch;

		statusw  = 0;
		for (text = s = stext; *s; s++) {
			if ((unsigned char)(*s) < ' ') {
				ch = *s;
				*s = '\0';
				statusw += statustext(text, 0, 0);
				*s = ch;
				text = s + 1;
			}
		}
		statusw += statustext(text, 0, 0) + 2;

	}
	drawbar(selmon);
	updatesystray();
}


void
updatesystrayicongeom(Client *i, int w, int h)
{
	if (i) {
		i->h = bh;
		if (w == h)
			i->w = bh;
		else if (h == bh)
			i->w = w;
		else
			i->w = (int) ((float)bh * ((float)w / (float)h));
		applysizehints(i, &(i->x), &(i->y), &(i->w), &(i->h), False);
		/* force icons into the systray dimensions if they don't want to */
		if (i->h > bh) {
			if (i->w == i->h)
				i->w = bh;
			else
				i->w = (int) ((float)bh * ((float)i->w / (float)i->h));
			i->h = bh;
		}
	}
}

void
updatesystrayiconstate(Client *i, XPropertyEvent *ev)
{
	long flags;
	int code = 0;

	if (!showsystray || !i || ev->atom != xatom[XembedInfo] ||
			!(flags = getatomprop(i, xatom[XembedInfo])))
		return;

	if (flags & XEMBED_MAPPED && !i->tags) {
		i->tags = 1;
		code = XEMBED_WINDOW_ACTIVATE;
		XMapRaised(dpy, i->win);
		setclientstate(i, NormalState);
	}
	else if (!(flags & XEMBED_MAPPED) && i->tags) {
		i->tags = 0;
		code = XEMBED_WINDOW_DEACTIVATE;
		XUnmapWindow(dpy, i->win);
		setclientstate(i, WithdrawnState);
	}
	else
		return;
	sendevent(i->win, xatom[Xembed], StructureNotifyMask, CurrentTime, code, 0,
			systray->win, XEMBED_EMBEDDED_VERSION);
}

void
updatesystray(void)
{
	XSetWindowAttributes wa;
	XWindowChanges wc;
	Client *i;
	Monitor *m = systraytomon(NULL);
	unsigned int x = m->mx + m->mw;
	unsigned int sw = TEXTW(stext) - lrpad + systrayspacing;
	unsigned int w = 1;

	if (!showsystray)
		return;
	if (systrayonleft)
		x -= sw + lrpad / 2;
	if (!systray) {
		/* init systray */
		if (!(systray = (Systray *)calloc(1, sizeof(Systray))))
			die("fatal: could not malloc() %u bytes\n", sizeof(Systray));
		systray->win = XCreateSimpleWindow(dpy, root, x, m->by, w, bh, 0, 0, scheme[SchemeSel][ColBg].pixel);
		wa.event_mask        = ButtonPressMask | ExposureMask;
		wa.override_redirect = True;
		wa.background_pixel  = scheme[SchemeNorm][ColBg].pixel;
		XSelectInput(dpy, systray->win, SubstructureNotifyMask);
		XChangeProperty(dpy, systray->win, netatom[NetSystemTrayOrientation], XA_CARDINAL, 32,
				PropModeReplace, (unsigned char *)&netatom[NetSystemTrayOrientationHorz], 1);
		XChangeWindowAttributes(dpy, systray->win, CWEventMask|CWOverrideRedirect|CWBackPixel, &wa);
		XMapRaised(dpy, systray->win);
		XSetSelectionOwner(dpy, netatom[NetSystemTray], systray->win, CurrentTime);
		if (XGetSelectionOwner(dpy, netatom[NetSystemTray]) == systray->win) {
			sendevent(root, xatom[Manager], StructureNotifyMask, CurrentTime, netatom[NetSystemTray], systray->win, 0, 0);
			XSync(dpy, False);
		}
		else {
			fprintf(stderr, "dwm: unable to obtain system tray.\n");
			free(systray);
			systray = NULL;
			return;
		}
	}
	for (w = 0, i = systray->icons; i; i = i->next) {
		/* make sure the background color stays the same */
		wa.background_pixel  = scheme[SchemeNorm][ColBg].pixel;
		XChangeWindowAttributes(dpy, i->win, CWBackPixel, &wa);
		XMapRaised(dpy, i->win);
		w += systrayspacing;
		i->x = w;
		XMoveResizeWindow(dpy, i->win, i->x, 0, i->w, i->h);
		w += i->w;
		if (i->mon != m)
			i->mon = m;
	}
	w = w ? w + systrayspacing : 1;
	x -= w;
	XMoveResizeWindow(dpy, systray->win, x, m->by, w, bh);
	wc.x = x; wc.y = m->by; wc.width = w; wc.height = bh;
	wc.stack_mode = Above; wc.sibling = m->barwin;
	XConfigureWindow(dpy, systray->win, CWX|CWY|CWWidth|CWHeight|CWSibling|CWStackMode, &wc);
	XMapWindow(dpy, systray->win);
	XMapSubwindows(dpy, systray->win);
	/* redraw background */
	XSetForeground(dpy, drw->gc, scheme[SchemeNorm][ColBg].pixel);
	XFillRectangle(dpy, systray->win, drw->gc, 0, 0, w, bh);
	XSync(dpy, False);
}

void
updatetitle(Client *c)
{
	if (!gettextprop(c->win, netatom[NetWMName], c->name, sizeof c->name))
		gettextprop(c->win, XA_WM_NAME, c->name, sizeof c->name);
	if (c->name[0] == '\0') /* hack to mark broken clients */
		strcpy(c->name, broken);
}

void
updatewindowtype(Client *c)
{
	Atom state = getatomprop(c, netatom[NetWMState]);
	
	int is_popup = ispopup(c);
	if (!c->isfullscreen && state == netatom[NetWMFullscreen] && !is_popup)
		setfullscreen(c, 1);
	if (state == netatom[NetWMSticky]) {
		setsticky(c, 1);
	}
	if (is_popup) {
		c->isfloating = 1;
	}
}

void
updatewmhints(Client *c)
{
	XWMHints *wmh;

	if ((wmh = XGetWMHints(dpy, c->win))) {
		if (c == selmon->sel && wmh->flags & XUrgencyHint) {
			wmh->flags &= ~XUrgencyHint;
			XSetWMHints(dpy, c->win, wmh);
		} else
			c->isurgent = (wmh->flags & XUrgencyHint) ? 1 : 0;
		if (wmh->flags & InputHint)
			c->neverfocus = !wmh->input;
		else
			c->neverfocus = 0;
		XFree(wmh);
	}
}

void
view(const Arg *arg)
{
	if ((arg->ui & TAGMASK) == selmon->tagset[selmon->seltags])
		return;
	selmon->seltags ^= 1; /* toggle sel tagset */
	if (arg->ui & TAGMASK)
		selmon->tagset[selmon->seltags] = arg->ui & TAGMASK;
	pertagload(selmon, selmon->tagset[selmon->seltags]);
	focus(NULL);
	arrange(selmon);
}

pid_t
winpid(Window w)
{

	pid_t result = 0;

#ifdef __linux__
	xcb_res_client_id_spec_t spec = {0};
	spec.client = w;
	spec.mask = XCB_RES_CLIENT_ID_MASK_LOCAL_CLIENT_PID;

	xcb_generic_error_t *e = NULL;
	xcb_res_query_client_ids_cookie_t c = xcb_res_query_client_ids(xcon, 1, &spec);
	xcb_res_query_client_ids_reply_t *r = xcb_res_query_client_ids_reply(xcon, c, &e);

	if (!r)
		return (pid_t)0;

	xcb_res_client_id_value_iterator_t i = xcb_res_query_client_ids_ids_iterator(r);
	for (; i.rem; xcb_res_client_id_value_next(&i)) {
		spec = i.data->spec;
		if (spec.mask & XCB_RES_CLIENT_ID_MASK_LOCAL_CLIENT_PID) {
			uint32_t *t = xcb_res_client_id_value_value(i.data);
			result = *t;
			break;
		}
	}

	free(r);

	if (result == (pid_t)-1)
		result = 0;

#endif /* __linux__ */

#if defined(__OpenBSD__) || defined(__FreeBSD__)
        Atom type;
        int format;
        unsigned long len, bytes;
        unsigned char *prop;
        pid_t ret;

        if (XGetWindowProperty(dpy, w, XInternAtom(dpy, "_NET_WM_PID", 0), 0, 1, False, AnyPropertyType, &type, &format, &len, &bytes, &prop) != Success || !prop)
               return 0;

        ret = *(pid_t*)prop;
        XFree(prop);
        result = ret;

#endif /* __OpenBSD__ */
	return result;
}

pid_t
getparentprocess(pid_t p)
{
	unsigned int v = 0;

#ifdef __linux__
	FILE *f;
	char buf[256];
	snprintf(buf, sizeof(buf) - 1, "/proc/%u/stat", (unsigned)p);

	if (!(f = fopen(buf, "r")))
		return 0;

	fscanf(f, "%*u %*s %*c %u", &v);
	fclose(f);
#endif /* __linux__*/

#ifdef __FreeBSD__
    FILE *f;
	char buf[256];
	snprintf(buf, sizeof(buf) - 1, "/proc/%u/status", (unsigned)p);

    if (!(f = fopen(buf, "r")))
		return 0;

	fscanf(f, "%*s %*u %u", &v);
	fclose(f);
#endif

#ifdef __OpenBSD__
	int n;
	kvm_t *kd;
	struct kinfo_proc *kp;

	kd = kvm_openfiles(NULL, NULL, NULL, KVM_NO_FILES, NULL);
	if (!kd)
		return 0;

	kp = kvm_getprocs(kd, KERN_PROC_PID, p, sizeof(*kp), &n);
	v = kp->p_ppid;
#endif /* __OpenBSD__ */

	return (pid_t)v;
}

int
isdescprocess(pid_t p, pid_t c)
{
	while (p != c && c != 0)
		c = getparentprocess(c);

	return (int)c;
}

Client *
termforwin(const Client *w)
{
	Client *c;
	Monitor *m;

	if (!w->pid || w->isterminal)
		return NULL;

	for (m = mons; m; m = m->next) {
		for (c = m->clients; c; c = c->next) {
			if (c->isterminal && !c->swallowing && c->pid && isdescprocess(c->pid, w->pid))
				return c;
		}
	}

	return NULL;
}

Client *
swallowingclient(Window w)
{
	Client *c;
	Monitor *m;

	for (m = mons; m; m = m->next) {
		for (c = m->clients; c; c = c->next) {
			if (c->swallowing && c->swallowing->win == w)
				return c;
		}
	}

	return NULL;
}

Client *
wintoclient(Window w)
{
	Client *c;
	Monitor *m;

	for (m = mons; m; m = m->next)
		for (c = m->clients; c; c = c->next)
			if (c->win == w)
				return c;
	return NULL;
}

Client *
wintosystrayicon(Window w) {
	Client *i = NULL;

	if (!showsystray || !w)
		return i;
	for (i = systray->icons; i && i->win != w; i = i->next) ;
	return i;
}

Monitor *
wintomon(Window w)
{ /* move window w to monitor m */
	int x, y;
	Client *c;
	Monitor *m;

	if (w == root && getrootptr(&x, &y))
		return recttomon(x, y, 1, 1);
	for (m = mons; m; m = m->next)
		if (w == m->barwin)
			return m;
	if ((c = wintoclient(w)))
		return c->mon;
	return selmon;
}

Monitor *
systraytomon(Monitor *m) {
	Monitor *t;
	int i, n;
	if(!systraypinning) {
		if(!m)
			return selmon;
		return m == selmon ? m : NULL;
	}
	for(n = 1, t = mons; t && t->next; n++, t = t->next) ;
	for(i = 1, t = mons; t && t->next && i < systraypinning; i++, t = t->next) ;
	if(systraypinningfailfirst && n < systraypinning)
		return mons;
	return t;
}

/* There's no way to check accesses to destroyed windows, thus those cases are
 * ignored (especially on UnmapNotify's). Other types of errors call Xlibs
 * default error handler, which may call exit. */
int
xerror(Display *dpy, XErrorEvent *ee)
{
	if (ee->error_code == BadWindow
	|| (ee->request_code == X_SetInputFocus && ee->error_code == BadMatch)
	|| (ee->request_code == X_PolyText8 && ee->error_code == BadDrawable)
	|| (ee->request_code == X_PolyText8 && ee->error_code == BadDrawable)
	|| (ee->request_code == X_PolyFillRectangle && ee->error_code == BadDrawable)
	|| (ee->request_code == X_PolySegment && ee->error_code == BadDrawable)
	|| (ee->request_code == X_ConfigureWindow && ee->error_code == BadMatch)
	|| (ee->request_code == X_GrabButton && ee->error_code == BadAccess)
	|| (ee->request_code == X_GrabKey && ee->error_code == BadAccess)
	|| (ee->request_code == X_CopyArea && ee->error_code == BadDrawable))
		return 0;
	/* tuxcraft: a glyph the X server refuses (BadLength from RenderAddGlyphs: a colour glyph
	 * too big for one request, from a fallback font for a character in a window title) is
	 * simply not drawn. RENDER only draws text and pictures, so none of its errors is worth
	 * ending dwm, and with it the session, over. */
	if (renderop >= 0 && ee->request_code == renderop) {
		fprintf(stderr, "dwm: ignored RENDER error (minor request %d, error %d)\n",
			ee->minor_code, ee->error_code);
		return 0;
	}
	fprintf(stderr, "dwm: fatal error: request code=%d, error code=%d\n",
		ee->request_code, ee->error_code);
	return xerrorxlib(dpy, ee); /* may call exit */
}

int
xerrordummy(Display *dpy, XErrorEvent *ee)
{
	return 0;
}

/* Startup Error handler to check if another window manager
 * is already running. */
int
xerrorstart(Display *dpy, XErrorEvent *ee)
{
	die("dwm: another window manager is already running");
	return -1;
}

void
xrdb(const Arg *arg)
{ /* load xresource database colors */
  loadxrdb();
  int i;
  for (i = 0; i < LENGTH(colors); i++)
                scheme[i] = drw_scm_create(drw, colors[i], 3);
  focus(NULL);
  arrange(NULL);
}

void
zoom(const Arg *arg)
{
	Client *c = selmon->sel;

	if (!selmon->lt[selmon->sellt]->arrange || !c || c->isfloating)
		return;
	if (c == nexttiled(selmon->clients) && !(c = nexttiled(c->next)))
		return;
	pop(c);
}



/* ------------------------------------------------------------------------------------------
 * tuxcraft additions. tuxcraft's keybindings are written for i3 (~/.config/tuxcraft/wm/common.conf);
 * these give dwm the same behaviour where dwm has none of its own.
 * ---------------------------------------------------------------------------------------- */

/* strstr, ignoring case: rules match like i3's (?i) regexes */
int
casestr(const char *hay, const char *needle)
{
	size_t n = strlen(needle);

	for (; *hay; hay++)
		if (!strncasecmp(hay, needle, n))
			return 1;
	return !n;
}

/* Super+N: go to tag N; pressing it again goes back (i3: workspace_auto_back_and_forth) */
void
viewtag(const Arg *arg)
{
	if ((arg->ui & TAGMASK) == selmon->tagset[selmon->seltags]) {
		Arg a = {0};
		view(&a);
	} else
		view(arg);
}

/* Super+Tab / Super+Shift+Tab: next / previous tag that has windows (i3: workspace next / prev) */
void
shiftviewocc(const Arg *arg)
{
	unsigned int occ = 0, cur = selmon->tagset[selmon->seltags], i, n = LENGTH(tags);
	int start = 0, j;
	Client *c;

	for (c = selmon->clients; c; c = c->next)
		occ |= c->tags & TAGMASK;
	occ |= cur;
	for (i = 0; i < n; i++)
		if (cur & 1 << i) {
			start = i;
			if (arg->i > 0)
				continue; /* forward: start from the highest shown tag */
			break;
		}
	for (j = 1; j < (int)n; j++) {
		i = (unsigned int)((start + arg->i * j) % (int)n + (int)n) % n;
		if (occ & 1 << i) {
			Arg a = {.ui = 1 << i};
			view(&a);
			return;
		}
	}
}

/* ---- tuxcraft: layouts per tag ---- */
static unsigned int
pertagslot(unsigned int ts)
{
	ts &= TAGMASK;
	if (ts && !(ts & (ts - 1)))
		return (unsigned int)__builtin_ctz(ts); /* one tag: its index */
	return PERTAGSLOTS - 1;                       /* several tags at once */
}

/* The layout, master size and master count kept for tags, into the monitor. */
static void
pertagload(Monitor *m, unsigned int ts)
{
	unsigned int s = pertagslot(ts);

	m->lt[0] = &layouts[m->ptlt[s][0] % LENGTH(layouts)];
	m->lt[1] = &layouts[m->ptlt[s][1] % LENGTH(layouts)];
	m->sellt = m->ptsellt[s] & 1;
	m->mfact = m->ptmfact[s];
	m->nmaster = m->ptnmaster[s];
	strncpy(m->ltsymbol, m->lt[m->sellt]->symbol, sizeof m->ltsymbol);
}

/* The monitor's current layout, master size and count: kept for the tag(s) it shows. */
static void
pertagkeep(Monitor *m)
{
	unsigned int s = pertagslot(m->tagset[m->seltags]), i;

	for (i = 0; i < 2; i++)
		if (m->lt[i] >= layouts && m->lt[i] < layouts + LENGTH(layouts))
			m->ptlt[s][i] = (unsigned int)(m->lt[i] - layouts);
	m->ptsellt[s] = m->sellt;
	m->ptmfact[s] = m->mfact;
	m->ptnmaster[s] = m->nmaster;
}

static int
pertagpath(char *buf, size_t n, int mkdirs)
{
	const char *state = getenv("XDG_STATE_HOME"), *home = getenv("HOME");
	char dir[PATH_MAX];

	if (state && *state)
		snprintf(dir, sizeof dir, "%s", state);
	else if (home && *home)
		snprintf(dir, sizeof dir, "%s/.local/state", home);
	else
		return 0;
	if (mkdirs)
		mkdir(dir, 0755);
	strncat(dir, "/tuxcraft", sizeof dir - strlen(dir) - 1);
	if (mkdirs)
		mkdir(dir, 0755);
	return snprintf(buf, n, "%s/dwm-layouts", dir) < (int)n;
}

/* Every monitor's layouts per tag, into the state file: "monitor slot layout0 layout1 sellt
 * mfact nmaster" per line (layouts by their index in layouts[]). */
static void
pertagsave(void)
{
	char path[PATH_MAX], tmp[PATH_MAX + 8];
	Monitor *m;
	FILE *f;
	int s;

	if (!pertagpath(path, sizeof path, 1))
		return;
	snprintf(tmp, sizeof tmp, "%s.tmp", path);
	if (!(f = fopen(tmp, "w")))
		return;
	for (m = mons; m; m = m->next)
		for (s = 0; s < PERTAGSLOTS; s++)
			fprintf(f, "%d %d %u %u %u %.4f %d\n", m->num, s, m->ptlt[s][0], m->ptlt[s][1],
			        m->ptsellt[s], m->ptmfact[s], m->ptnmaster[s]);
	if (fclose(f) == 0)
		rename(tmp, path);
	else
		unlink(tmp);
}

/* The state file into the monitors, and each monitor's current tag's layout applied. */
static void
pertagread(void)
{
	char path[PATH_MAX], line[128];
	unsigned int l0, l1, sl;
	int mon, s, nm;
	float mf;
	Monitor *m;
	FILE *f;

	if (pertagpath(path, sizeof path, 0) && (f = fopen(path, "r"))) {
		while (fgets(line, sizeof line, f)) {
			if (sscanf(line, "%d %d %u %u %u %f %d", &mon, &s, &l0, &l1, &sl, &mf, &nm) != 7
			|| s < 0 || s >= PERTAGSLOTS || l0 >= LENGTH(layouts) || l1 >= LENGTH(layouts)
			|| mf < 0.05 || mf > 0.95 || nm < 0)
				continue;
			for (m = mons; m && m->num != mon; m = m->next);
			if (!m)
				continue;
			m->ptlt[s][0] = l0;
			m->ptlt[s][1] = l1;
			m->ptsellt[s] = sl & 1;
			m->ptmfact[s] = mf;
			m->ptnmaster[s] = nm;
		}
		fclose(f);
	}
	for (m = mons; m; m = m->next)
		pertagload(m, m->tagset[m->seltags]);
}

void
setlayoutidx(const Arg *arg)
{
	Arg a = {.v = &layouts[arg->i]};
	setlayout(&a);
}

/* Super+X: toggle the split direction (i3: layout toggle split) = tile <-> bottom stack */
void
togglesplit(const Arg *arg)
{
	Arg a = {.v = &layouts[selmon->lt[selmon->sellt] == &layouts[LayoutBstack] ? LayoutTile : LayoutBstack]};
	setlayout(&a);
}

/* Super+Alt+Space: float every window on this tag, or tile them all when all float already */
void
togglefloatall(const Arg *arg)
{
	Client *c;
	int anytiled = 0;

	for (c = selmon->clients; c; c = c->next)
		if (ISVISIBLE(c) && !c->isfloating && !c->isfullscreen)
			anytiled = 1;
	for (c = selmon->clients; c; c = c->next)
		if (ISVISIBLE(c) && !c->isfullscreen && !c->isfixed)
			c->isfloating = anytiled;
	arrange(selmon);
}

/* Super+Shift+minus: hide the window in the scratchpad (i3: move scratchpad) */
void
scratchhide(const Arg *arg)
{
	Client *c = selmon->sel;

	if (!c)
		return;
	if (!c->isfloating) /* a tiled window comes back as a floating one of a sensible size */
		resizeclient(c, c->x, c->y, c->mon->ww * 0.6, c->mon->wh * 0.65);
	c->isscratch = 1;
	c->issticky = 0;
	c->isfloating = 1;
	c->tags = SPTAG;
	focus(NULL);
	arrange(selmon);
}

/* Super+minus: show the next scratchpad window here, or hide the one that is focused
 * (i3: scratchpad show) */
void
scratchshow(const Arg *arg)
{
	Client *c, *sel = selmon->sel;
	Monitor *m;

	if (sel && sel->isscratch) {
		sel->tags = SPTAG;
		focus(NULL);
		arrange(selmon);
		return;
	}
	for (m = mons; m; m = m->next)
		for (c = m->clients; c; c = c->next)
			if (c->isscratch && c->tags == SPTAG) {
				if (c->mon != selmon) {
					detach(c);
					detachstack(c);
					c->mon = selmon;
					attach(c);
					attachstack(c);
				}
				c->tags = selmon->tagset[selmon->seltags];
				c->isfloating = 1;
				c->x = selmon->wx + (selmon->ww - WIDTH(c)) / 2;
				c->y = selmon->wy + (selmon->wh - HEIGHT(c)) / 2;
				focus(c);
				arrange(selmon);
				return;
			}
}

/* Super+Ctrl+Left/Right: move every window of this tag to the other monitor and follow them
 * (i3: move workspace to output) */
void
movetagsmon(const Arg *arg)
{
	Monitor *m;
	Client *c, *next;

	if (!mons->next || (m = dirtomon(arg->i)) == selmon)
		return;
	for (c = selmon->clients; c; c = next) {
		next = c->next;
		if (ISVISIBLE(c) && !c->issticky)
			sendmon(c, m);
	}
	focusmon(arg);
}

/* Super+R: resize mode (i3: mode "resize"). Arrows resize, Enter / Esc / Super+R leave. */
void
resizemode(const Arg *arg)
{
	keymode = arg->i;
	grabkeys();
	drawbars();
}

/* In resize mode: arrows. Floating windows grow / shrink by 20 px; tiled ones move the
 * master / stack border (Left, Up shrink the master; Right, Down grow it). */
void
resizedir(const Arg *arg)
{
	Client *c = selmon->sel;
	int step = 20;

	if (!c)
		return;
	if (c->isfloating || !selmon->lt[selmon->sellt]->arrange) {
		switch (arg->i) {
		case 0: resize(c, c->x, c->y, MAX(c->w - step, bh), c->h, 1); break; /* Left */
		case 1: resize(c, c->x, c->y, c->w, c->h + step, 1); break;           /* Down */
		case 2: resize(c, c->x, c->y, c->w, MAX(c->h - step, bh), 1); break; /* Up */
		case 3: resize(c, c->x, c->y, c->w + step, c->h, 1); break;           /* Right */
		}
	} else {
		Arg a = {.f = (arg->i == 0 || arg->i == 2) ? -0.05 : +0.05};
		setmfact(&a);
	}
}

/* Commands from scripts (tux-dwm cmd ...): the _TUX_DWM_CMD property on the root window.
 *   view N | layout NAME | sticky | floatall | bar | gaps | restart | quit | xrdb */
void
tuxcmd(const char *cmd)
{
	unsigned int i;
	Arg a = {0};

	if (!strncmp(cmd, "view ", 5)) {
		i = (unsigned int)atoi(cmd + 5);
		if (i >= 1 && i <= LENGTH(tags)) {
			a.ui = 1 << (i - 1);
			view(&a);
		}
	} else if (!strncmp(cmd, "layout ", 7)) {
		for (i = 0; i < LENGTH(layoutnames); i++)
			if (!strcmp(cmd + 7, layoutnames[i])) {
				a.v = &layouts[i];
				setlayout(&a);
			}
	} else if (!strcmp(cmd, "sticky")) {
		togglesticky(&a);
	} else if (!strcmp(cmd, "floatall")) {
		togglefloatall(&a);
	} else if (!strcmp(cmd, "restart")) {
		a.i = 1;
		quit(&a);
	} else if (!strcmp(cmd, "quit")) {
		quit(&a);
	} else if (!strcmp(cmd, "xrdb")) {
		xrdb(&a);
	} else if (!strcmp(cmd, "bar")) {
		togglebar(&a);
	} else if (!strcmp(cmd, "gaps")) {
		togglegaps(&a);
	}
}

/* EWMH: _NET_CURRENT_DESKTOP and each window's _NET_WM_DESKTOP (first tag; sticky and
 * scratchpad windows: all desktops), for window switchers and tux-dwm. */
void
updatedesktops(void)
{
	Monitor *m;
	Client *c;
	long d;
	unsigned int i, t;

	if (!selmon)
		return;
	t = selmon->tagset[selmon->seltags];
	for (d = 0, i = 0; i < LENGTH(tags); i++)
		if (t & 1 << i) {
			d = i;
			break;
		}
	XChangeProperty(dpy, root, netatom[NetCurrentDesktop], XA_CARDINAL, 32,
		PropModeReplace, (unsigned char *)&d, 1);
	for (m = mons; m; m = m->next)
		for (c = m->clients; c; c = c->next) {
			d = 0xFFFFFFFF;
			if (!c->issticky && !c->isscratch)
				for (i = 0; i < LENGTH(tags); i++)
					if (c->tags & 1 << i) {
						d = i;
						break;
					}
			if (d == c->desktop)
				continue;
			c->desktop = d;
			XChangeProperty(dpy, c->win, netatom[NetWMDesktop], XA_CARDINAL, 32,
				PropModeReplace, (unsigned char *)&d, 1);
		}
}

/* tuxcraft: after a restart, put each monitor's windows back in the order they had (scan()
 * takes them in stacking order, so master and stack would come back shuffled). Windows with
 * no saved place (new ones) go first, as a new window would. */
static void
sortclients(void)
{
	Monitor *m;
	Client *c, **v, **tail;
	int n, i, j;

	for (m = mons; m; m = m->next) {
		for (n = 0, c = m->clients; c; c = c->next, n++);
		if (n < 2)
			continue;
		v = ecalloc(n, sizeof *v);
		for (i = 0, c = m->clients; c; c = c->next)
			v[i++] = c;
		for (i = 1; i < n; i++) /* insertion sort, stable */
			for (j = i; j > 0 && v[j - 1]->order > v[j]->order; j--) {
				c = v[j]; v[j] = v[j - 1]; v[j - 1] = c;
			}
		tail = &m->clients;
		for (i = 0; i < n; i++) {
			*tail = v[i];
			tail = &v[i]->next;
		}
		*tail = NULL;
		free(v);
	}
}

/* Before a restart: each window's tags, float/sticky state, monitor, place in the tiling and
 * column share, and the shown tags. manage(), sortclients() and main() read them back. */
void
savestate(void)
{
	Monitor *m;
	Client *c;
	long v[5];
	int i;

	for (m = mons; m; m = m->next)
		for (c = m->clients, i = 0; c; c = c->next, i++) {
			v[0] = c->tags;
			v[1] = (c->isfloating && !c->isfullscreen ? 1 : 0) | (c->issticky ? 2 : 0);
			v[2] = i;                          /* place in the tiling order */
			v[3] = (long)(c->cfact * 1000.0 + 0.5);
			v[4] = m->num;
			XChangeProperty(dpy, c->win, tuxtagsatom, XA_CARDINAL, 32,
				PropModeReplace, (unsigned char *)v, 5);
		}
	v[0] = selmon->tagset[selmon->seltags];
	XChangeProperty(dpy, root, tuxviewatom, XA_CARDINAL, 32,
		PropModeReplace, (unsigned char *)v, 1);
	XSync(dpy, False);
}

int
main(int argc, char *argv[])
{
	if (argc == 2 && !strcmp("-v", argv[1]))
		die("dwm-"VERSION);
	else if (argc != 1)
		die("usage: dwm [-v]");
	if (!setlocale(LC_CTYPE, "") || !XSupportsLocale())
		fputs("warning: no locale support\n", stderr);
	if (!(dpy = XOpenDisplay(NULL)))
		die("dwm: cannot open display");
	if (!(xcon = XGetXCBConnection(dpy)))
		die("dwm: cannot get xcb connection\n");
	checkotherwm(); /* see if any other WMs are running */
        XrmInitialize();
        loadxrdb(); /* added by xrdb patch */
	setup(); /* initialize everything needed to start dwm */
#ifdef __OpenBSD__
	if (pledge("stdio rpath proc exec ps", NULL) == -1)
		die("pledge");
#endif /* __OpenBSD__ */
	scan(); /* see if other applications are already running */
	sortclients(); /* tuxcraft: after a restart, every window back in its place in the tiling */
	{ /* tuxcraft: after a restart, show the tags that were shown before */
		Atom type; int fmt; unsigned long n, after; unsigned char *p = NULL;
		if (XGetWindowProperty(dpy, root, tuxviewatom, 0, 1, True, XA_CARDINAL, &type, &fmt,
		    &n, &after, &p) == Success && p) {
			Arg a = {.ui = n == 1 ? (unsigned int)((long *)p)[0] & TAGMASK : 0};
			XFree(p);
			if (a.ui)
				view(&a);
		}
		arrange(NULL);
	}
	run(); /* main event loop of dwm -->
* continuously listens to events from the X server (window changes, key presses, mouse) 
* and sends them to the correct event handler */
	if (restart) {
		savestate(); /* tuxcraft: windows keep their tags across the restart */
		execvp(argv[0], argv);
	}
	cleanup();
	XCloseDisplay(dpy);
	return EXIT_SUCCESS;
}
