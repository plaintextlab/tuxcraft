/* tuxcraft dwm: BreadOnPenguins' build (github.com/BreadOnPenguins/dwm, her patches and look),
 * with tuxcraft's keybindings: the same keys as the i3 session (~/.config/tuxcraft/wm/common.conf
 * and ~/.config/i3/config), so Super+K (tux-keys) is right in both.
 *
 * Her patches: bartoggle, bulkill, colorbar, fixmultimon, focusfullscreen, focusmaster-return,
 * focusmonmouse, hide_vacant_tags, preventfocusshift, restartsig, spawntag, stacker, statuscmd,
 * sticky, swallow, vanitygaps, xrdb. tuxcraft adds (dwm.c, "tuxcraft" comments): i3-style
 * back-and-forth tags, next/previous occupied tag, scratchpad, resize mode, float-all, move a
 * tag to the other monitor, bottom-stack and deck layouts, case-insensitive rules with floating
 * size, focus on _NET_ACTIVE_WINDOW, EWMH desktops, tags kept across restarts, a bar font from
 * Xresources, and commands from scripts (tux-dwm cmd ...).
 *
 * Colours and the bar font come from ~/.Xresources (tux-theme writes dwm.* there), so
 * tux-theme / tux-font re-theme dwm like everything else. Rebuild after editing: tux-dwm build.
 */

/* appearance (her values) */
static unsigned int borderpx        = 1;        /* border pixel of windows */
static unsigned int snap            = 32;       /* snap pixel */
/* system tray (dwm's systray patch): right of the status text, on the focused monitor */
static const unsigned int systraypinning = 0;   /* 0: sloppy systray follows selected monitor, >0: pin systray to monitor X */
static const unsigned int systrayonleft = 0;    /* 0: systray in the right corner, >0: systray on left of status text */
static const unsigned int systrayspacing = 6;   /* systray spacing */
static const int systraypinningfailfirst = 1;   /* 1: if pinning fails, display systray on the first monitor, False: display systray on the last monitor*/
static const int showsystray        = 1;        /* 0 means no systray */
/* Her systray diff also carries an external-panel patch (a window titled panel[0] gets no border
 * and no focus). tuxcraft runs no such panel: a title no window has keeps that part asleep. */
static const char *panel[]          = { "tuxcraft-no-external-panel" };
static const unsigned int refreshrate = 240;    /* tuxcraft: moves and resizes by mouse redraw up to this many times
                                                 * a second (stock dwm: 60, choppy on a 120/144 Hz screen) */
static const unsigned int gappih    = 20;       /* horiz inner gap between windows */
static const unsigned int gappiv    = 20;       /* vert inner gap between windows */
static const unsigned int gappoh    = 20;       /* horiz outer gap between windows and screen edge */
static const unsigned int gappov    = 30;       /* vert outer gap between windows and screen edge */
static       int smartgaps          = 0;        /* 1 means no outer gap when there is only one window */
static const int swallowfloating    = 0;        /* 1 means swallow floating windows by default */
static int showbar                  = 1;        /* 0 means no bar */
static const int showtitle          = 1;        /* 0 means no title */
static const int showtags           = 1;        /* 0 means no tags */
static const int showlayout         = 1;        /* 0 means no layout indicator */
static const int showstatus         = 1;        /* 0 means no status bar */
static const int showfloating       = 0;        /* 0 means no floating indicator */
static int topbar                   = 1;        /* 0 means bottom bar */
/* The bar font (dwm.font in ~/.Xresources, from tux-font) and the icon font (dwm.iconfont): the
 * full-size Symbols Nerd Font, not the "Mono" one, which shrinks every icon into one narrow cell. */
static char font[128]               = "JetBrainsMono Nerd Font:size=11";
static char iconfont[128]           = "Symbols Nerd Font:size=11";
static const char *fonts[]          = { font, iconfont, "Noto Color Emoji:pixelsize=14:antialias=true:autohint=true" };
static char dmenufont[]             = "monospace:size=11";

/* default colors used if xrdb is not loaded (Nord, like hers) */
static char normbgcolor[]           = "#2e3440";
static char normbordercolor[]       = "#4c566a";
static char normfgcolor[]           = "#d8dee9";
static char selfgcolor[]            = "#eceff4";
static char selbordercolor[]        = "#a3be8c";
static char selbgcolor[]            = "#b48ead";
static char *colors[][3] = {
       /*               fg           bg           border   */
		[SchemeNorm] = { normfgcolor, normbgcolor, normbordercolor },
		[SchemeSel]  = { selbgcolor,  selfgcolor,  selbordercolor  },
		/* for bar --> {text, background, null} */
		[SchemeStatus]  = { normfgcolor, normbgcolor,  normbgcolor  }, /* status R */
		[SchemeTagsSel]  = { normfgcolor, normbgcolor,  normbgcolor  }, /* tag L selected */
		[SchemeTagsNorm]  = { selbordercolor, normbgcolor,  normbgcolor  }, /* tag L unselected */
		[SchemeInfoSel]  = { normfgcolor, normbgcolor,  normbgcolor  }, /* info M selected */
		[SchemeInfoNorm]  = { normfgcolor, normbgcolor,  normbgcolor  }, /* info M unselected */
};

/* tagging: ten, like i3's workspaces 1-10 (Super+0 = 10) */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" };

static const Rule rules[] = {
	/* xprop(1): WM_CLASS(STRING) = instance, class; WM_NAME(STRING) = title
	 * Matching ignores case and finds the text anywhere, like i3's (?i) regexes.
	 * Floating windows open centred; w/h = their size (0 = their own).
	 * class       instance title            tags     float term noswal sticky  w     h    mon */
	{ "kitty",     NULL,    NULL,            0,       0,    1,   0,     0,      0,    0,   -1 },
	{ "Alacritty", NULL,    NULL,            0,       0,    1,   0,     0,      0,    0,   -1 },
	{ "tux-float", NULL,    NULL,            0,       1,    0,   1,     0,      1100, 700, -1 },
	{ "tux-float-big", NULL, NULL,           0,       1,    0,   1,     0,      1400, 860, -1 },
	{ "mpv",       NULL,    NULL,            0,       1,    0,   0,     0,      0,    0,   -1 },
	{ "imv",       NULL,    NULL,            0,       1,    0,   0,     0,      0,    0,   -1 },
	{ "feh",       NULL,    NULL,            0,       1,    0,   0,     0,      1280, 720, -1 },
	{ NULL,        "tux-wallpaper", NULL,    0,       1,    0,   1,     0,      1400, 860, -1 }, /* the wallpaper thumbnails (nsxiv) */
	{ "pavucontrol", NULL,  NULL,            0,       1,    0,   0,     0,      0,    0,   -1 },
	{ "blueman-manager", NULL, NULL,         0,       1,    0,   0,     0,      0,    0,   -1 },
	{ "nm-connection-editor", NULL, NULL,    0,       1,    0,   0,     0,      0,    0,   -1 },
	{ "arandr",    NULL,    NULL,            0,       1,    0,   0,     0,      0,    0,   -1 },
	{ "qalculate", NULL,    NULL,            0,       1,    0,   0,     0,      0,    0,   -1 },
	{ "webapp-",   NULL,    NULL,            0,       1,    0,   0,     0,      1280, 720, -1 },
	{ NULL,        NULL,    ".exe",          0,       1,    0,   0,     0,      0,    0,   -1 },
	{ NULL,        NULL,    "Webcam Preview", 0,      1,    0,   0,     1,      0,    0,   -1 },
	{ "KeePassXC", NULL,    NULL,            0,       1,    0,   0,     0,      0,    0,   -1 },
	{ NULL,        NULL,    "Event Tester",  0,       0,    0,   1,     0,      0,    0,   -1 }, /* xev */
	/* workspace assignments (same as i3) */
	{ "firefox",   NULL,    NULL,            1 << 1,  0,    0,   0,     0,      0,    0,   -1 },
	{ "chromium",  NULL,    NULL,            1 << 1,  0,    0,   0,     0,      0,    0,   -1 },
	{ "brave",     NULL,    NULL,            1 << 1,  0,    0,   0,     0,      0,    0,   -1 },
	{ "steam",     NULL,    NULL,            1 << 4,  0,    0,   0,     0,      0,    0,   -1 },
	{ "lutris",    NULL,    NULL,            1 << 4,  0,    0,   0,     0,      0,    0,   -1 },
	{ "resolve",   NULL,    NULL,            1 << 3,  0,    0,   0,     0,      0,    0,   -1 },
	{ "kdenlive",  NULL,    NULL,            1 << 3,  0,    0,   0,     0,      0,    0,   -1 },
	{ "qBittorrent", NULL,  NULL,            1 << 7,  0,    0,   0,     0,      0,    0,   -1 },
};

#include "vanitygaps.c"

/* layout(s) */
static const float mfact     = 0.55; /* factor of master area size [0.05..0.95] */
static const int nmaster     = 1;    /* number of clients in master area */
static const int resizehints = 0;    /* 1 means respect size hints in tiled resizals (0: no gaps between terminals) */
static const int lockfullscreen = 0; /* 1 will force focus on the fullscreen window */
enum { LayoutTile, LayoutBstack, LayoutDeck, LayoutMonocle, LayoutSpiral, LayoutDwindle, LayoutFloat };
static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "",      tile },    /* first entry is default; i3 "split h". No symbol: the bar shows none until you switch layout, as hers */
	{ "󱡗",      bstack },  /* i3 "split v": master on top */
	{ "󱏋",      deck },    /* i3 "layout stacking" */
	{ "",      monocle }, /* i3 "layout tabbed": one window at a time */
	{ "󰫣",      spiral },
	{ "󰫥",      dwindle },
	{ "󰇥",      NULL },    /* no layout function means floating behavior */
};
/* names for tux-dwm layout / tux-dwm cmd layout NAME (same order as layouts[]) */
static const char *layoutnames[] = { "tile", "bstack", "deck", "monocle", "spiral", "dwindle", "float" };

/* key definitions */
#define MODKEY Mod4Mask /* Super ($mod in i3) */
#define ALTKEY Mod1Mask /* Alt ($alt in i3) */
#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      viewtag,        {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} },

/* helper for spawning shell commands in the pre dwm-5.0 fashion (i3's exec does the same) */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

#define STATUSBAR "dwmblocks" /* statuscmd: a click on a status block signals dwmblocks (button = value) */
#define TERM "tux-term"
#define FLOAT TERM " --class tux-float -e "
#define FLOATBIG TERM " --class tux-float-big -e "

/* commands */
static char dmenumon[2] = "0"; /* component of dmenucmd, manipulated in spawn() */
static const char *dmenucmd[] = { "dmenu_run", "-m", dmenumon, "-fn", dmenufont, "-nb", normbgcolor, "-nf", normfgcolor, "-sb", selbordercolor, "-sf", selfgcolor, NULL };
static const char *termcmd[]  = { TERM, NULL };
static const Arg tagexec[] = { /* spawn a terminal when a tag is middle-clicked */
	{ .v = termcmd }, { .v = termcmd }, { .v = termcmd }, { .v = termcmd }, { .v = termcmd },
	{ .v = termcmd }, { .v = termcmd }, { .v = termcmd }, { .v = termcmd }, { .v = termcmd },
	{ .v = termcmd },
};

#include <X11/XF86keysym.h>

/* Same keys as tuxcraft's i3 config; the comments name the i3 command each one stands for. */
static const Key keys[] = {
	/* modifier                     key                       function        argument */
	{ MODKEY,                       XK_Return,                spawn,          {.v = termcmd } },
	{ MODKEY,                       XK_d,                     spawn,          SHCMD("tux-dwm run") },            /* app launcher (her dmenu) */
	{ MODKEY,                       XK_space,                 spawn,          SHCMD("tux-dwm overview") },       /* tags and their windows */
	{ MODKEY,                       XK_o,                     spawn,          SHCMD("rofi -show window -show-icons") },
	{ MODKEY,                       XK_q,                     killclient,     {0} },
	{ ALTKEY,                       XK_F4,                    killclient,     {0} },
	{ MODKEY,                       XK_b,                     spawn,          SHCMD("tux-open browser") },
	{ MODKEY|ShiftMask,             XK_b,                     spawn,          SHCMD("tux-open browser-private") },
	{ MODKEY,                       XK_e,                     spawn,          SHCMD("thunar") },
	{ MODKEY|ShiftMask,             XK_e,                     spawn,          SHCMD("thunar /media") },
	{ MODKEY,                       XK_m,                     spawn,          SHCMD(FLOATBIG "tux-music player") },
	{ MODKEY|ShiftMask,             XK_m,                     spawn,          SHCMD(FLOAT "cava") },
	{ MODKEY,                       XK_t,                     spawn,          SHCMD(FLOAT "tux-notes") },
	{ MODKEY|ShiftMask,             XK_t,                     spawn,          SHCMD(FLOAT "tux-notes --new") },
	{ MODKEY,                       XK_c,                     spawn,          SHCMD(FLOAT "qalc") },
	{ MODKEY,                       XK_v,                     spawn,          SHCMD("tux-clip") },
	{ MODKEY,                       XK_z,                     spawn,          SHCMD("tux-recent files") },
	{ MODKEY|ShiftMask,             XK_z,                     spawn,          SHCMD("tux-recent apps") },
	{ MODKEY,                       XK_k,                     spawn,          SHCMD("tux-keys") },
	{ MODKEY,                       XK_Escape,                spawn,          SHCMD("tux-control") },
	{ MODKEY|ShiftMask,             XK_l,                     spawn,          SHCMD("tux-power") },
	{ MODKEY,                       XK_l,                     spawn,          SHCMD("tux-lock") },
	{ MODKEY|ALTKEY,                XK_l,                     spawn,          SHCMD("tux-lock --see-through") },
	/* system TUIs (floating) */
	{ MODKEY|ControlMask,           XK_n,                     spawn,          SHCMD(FLOAT "tux-net") },
	{ MODKEY|ControlMask,           XK_b,                     spawn,          SHCMD(FLOAT "bluetui") },
	{ MODKEY|ControlMask,           XK_a,                     spawn,          SHCMD(FLOAT "tux-mixer") },
	{ MODKEY|ControlMask,           XK_m,                     spawn,          SHCMD(FLOATBIG "btop") },
	{ MODKEY,                       XK_u,                     spawn,          SHCMD(FLOATBIG "sysup --pause") },
	{ MODKEY|ControlMask,           XK_t,                     spawn,          SHCMD("tux-theme --menu") },
	{ MODKEY|ControlMask,           XK_f,                     spawn,          SHCMD("tux-font --menu") },
	{ MODKEY|ControlMask,           XK_w,                     spawn,          SHCMD("tux-wallpaper --menu") },
	{ MODKEY|ShiftMask,             XK_w,                     spawn,          SHCMD("tux-wallpaper random") },
	/* audio / media / brightness */
	{ MODKEY,                       XK_p,                     spawn,          SHCMD("tux-audio output") },
	{ MODKEY|ShiftMask,             XK_p,                     spawn,          SHCMD("tux-audio input") },
	{ 0,                            XF86XK_AudioRaiseVolume,  spawn,          SHCMD("tux-osd volume up") },
	{ 0,                            XF86XK_AudioLowerVolume,  spawn,          SHCMD("tux-osd volume down") },
	{ 0,                            XF86XK_AudioMute,         spawn,          SHCMD("tux-osd volume mute") },
	{ 0,                            XF86XK_AudioMicMute,      spawn,          SHCMD("tux-osd mic mute") },
	{ 0,                            XF86XK_AudioPlay,         spawn,          SHCMD("tux-nowplaying ctl play-pause") },
	{ 0,                            XF86XK_AudioNext,         spawn,          SHCMD("tux-nowplaying ctl next") },
	{ 0,                            XF86XK_AudioPrev,         spawn,          SHCMD("tux-nowplaying ctl previous") },
	{ 0,                            XF86XK_AudioStop,         spawn,          SHCMD("tux-nowplaying ctl stop") },
	{ 0,                            XF86XK_MonBrightnessUp,   spawn,          SHCMD("tux-osd brightness up") },
	{ 0,                            XF86XK_MonBrightnessDown, spawn,          SHCMD("tux-osd brightness down") },
	{ MODKEY|ALTKEY,                XK_Up,                    spawn,          SHCMD("tux-osd brightness up") },
	{ MODKEY|ALTKEY,                XK_Down,                  spawn,          SHCMD("tux-osd brightness down") },
	{ MODKEY|ALTKEY,                XK_Right,                 spawn,          SHCMD("tux-osd contrast up") },
	{ MODKEY|ALTKEY,                XK_Left,                  spawn,          SHCMD("tux-osd contrast down") },
	{ MODKEY,                       XK_F1,                    spawn,          SHCMD("tux-osd brightness set 0") },
	{ MODKEY,                       XK_F2,                    spawn,          SHCMD("tux-osd brightness set 10") },
	{ MODKEY,                       XK_F3,                    spawn,          SHCMD("tux-osd brightness set 20") },
	{ MODKEY,                       XK_F4,                    spawn,          SHCMD("tux-osd brightness set 30") },
	{ MODKEY,                       XK_F5,                    spawn,          SHCMD("tux-osd brightness set 40") },
	{ MODKEY,                       XK_F6,                    spawn,          SHCMD("tux-osd brightness set 50") },
	{ MODKEY,                       XK_F7,                    spawn,          SHCMD("tux-osd brightness set 60") },
	{ MODKEY,                       XK_F8,                    spawn,          SHCMD("tux-osd brightness set 70") },
	{ MODKEY,                       XK_F9,                    spawn,          SHCMD("tux-osd brightness set 80") },
	{ MODKEY,                       XK_F10,                   spawn,          SHCMD("tux-osd brightness set 90") },
	{ MODKEY,                       XK_F11,                   spawn,          SHCMD("tux-osd brightness set 100") },
	{ 0,                            XK_KP_Up,                 spawn,          SHCMD("tux-osd volume up") },
	{ 0,                            XK_KP_Down,               spawn,          SHCMD("tux-osd volume down") },
	{ 0,                            XK_KP_Insert,             spawn,          SHCMD("tux-osd volume mute") },
	{ 0,                            XK_KP_Left,               spawn,          SHCMD("tux-nowplaying ctl previous") },
	{ 0,                            XK_KP_Begin,              spawn,          SHCMD("tux-nowplaying ctl play-pause") },
	{ 0,                            XK_KP_Right,              spawn,          SHCMD("tux-nowplaying ctl next") },
	{ MODKEY,                       XK_n,                     spawn,          SHCMD("tux-nightlight on") },
	{ MODKEY|ShiftMask,             XK_n,                     spawn,          SHCMD("tux-nightlight off") },
	{ MODKEY,                       XK_Delete,                spawn,          SHCMD("tux-powerprofile") },
	/* screenshots */
	{ 0,                            XK_Print,                 spawn,          SHCMD("tux-capture region") },
	{ ShiftMask,                    XK_Print,                 spawn,          SHCMD("tux-capture screen") },
	{ MODKEY,                       XK_Print,                 spawn,          SHCMD("tux-capture menu") },
	{ MODKEY|ShiftMask,             XK_Print,                 spawn,          SHCMD("tux-capture toggle") },
	/* windows. dwm keeps one list per tag (master first), so Left/Up = previous, Right/Down = next */
	{ MODKEY,                       XK_Left,                  focusstack,     {.i = INC(-1) } }, /* focus left */
	{ MODKEY,                       XK_Up,                    focusstack,     {.i = INC(-1) } }, /* focus up */
	{ MODKEY,                       XK_Right,                 focusstack,     {.i = INC(+1) } }, /* focus right */
	{ MODKEY,                       XK_Down,                  focusstack,     {.i = INC(+1) } }, /* focus down */
	{ MODKEY|ShiftMask,             XK_Left,                  pushstack,      {.i = INC(-1) } }, /* move left */
	{ MODKEY|ShiftMask,             XK_Up,                    pushstack,      {.i = INC(-1) } }, /* move up */
	{ MODKEY|ShiftMask,             XK_Right,                 pushstack,      {.i = INC(+1) } }, /* move right */
	{ MODKEY|ShiftMask,             XK_Down,                  pushstack,      {.i = INC(+1) } }, /* move down */
	{ MODKEY|ShiftMask,             XK_h,                     setlayoutidx,   {.i = LayoutTile } },    /* split h */
	{ MODKEY|ShiftMask,             XK_v,                     setlayoutidx,   {.i = LayoutBstack } },  /* split v */
	{ MODKEY,                       XK_f,                     togglefullscreen, {0} },
	{ MODKEY,                       XK_s,                     setlayoutidx,   {.i = LayoutDeck } },    /* layout stacking */
	{ MODKEY,                       XK_w,                     setlayoutidx,   {.i = LayoutMonocle } }, /* layout tabbed */
	{ MODKEY,                       XK_x,                     togglesplit,    {0} },                   /* layout toggle split */
	{ MODKEY|ControlMask,           XK_l,                     spawn,          SHCMD("tux-dwm layout") },
	{ MODKEY|ShiftMask,             XK_space,                 togglefloating, {0} },
	{ MODKEY|ALTKEY,                XK_space,                 togglefloatall, {0} },
	{ MODKEY,                       XK_a,                     spawn,          SHCMD("tux-webapps") },
	{ MODKEY|ShiftMask,             XK_s,                     togglesticky,   {0} },
	{ MODKEY|ShiftMask,             XK_minus,                 scratchhide,    {0} },
	{ MODKEY,                       XK_minus,                 scratchshow,    {0} },
	{ MODKEY,                       XK_r,                     resizemode,     {.i = 1 } },
	/* workspaces = tags */
	TAGKEYS(                        XK_1,                      0)
	TAGKEYS(                        XK_2,                      1)
	TAGKEYS(                        XK_3,                      2)
	TAGKEYS(                        XK_4,                      3)
	TAGKEYS(                        XK_5,                      4)
	TAGKEYS(                        XK_6,                      5)
	TAGKEYS(                        XK_7,                      6)
	TAGKEYS(                        XK_8,                      7)
	TAGKEYS(                        XK_9,                      8)
	TAGKEYS(                        XK_0,                      9)
	{ MODKEY,                       XK_Tab,                   shiftviewocc,   {.i = +1 } }, /* workspace next */
	{ MODKEY|ShiftMask,             XK_Tab,                   shiftviewocc,   {.i = -1 } }, /* workspace prev */
	{ ALTKEY,                       XK_Tab,                   view,           {0} },        /* last tag */
	{ ALTKEY|ShiftMask,             XK_Tab,                   view,           {0} },
	{ MODKEY|ALTKEY,                XK_Tab,                   focusstack,     {.i = INC(+1) } }, /* focus next */
	{ MODKEY|ALTKEY|ShiftMask,      XK_Tab,                   focusstack,     {.i = INC(-1) } }, /* focus prev */
	{ MODKEY|ControlMask,           XK_Left,                  movetagsmon,    {.i = -1 } }, /* move workspace to output left */
	{ MODKEY|ControlMask,           XK_Right,                 movetagsmon,    {.i = +1 } },
	{ MODKEY|ShiftMask,             XK_r,                     quit,           {1} },        /* restart in place (i3: restart) */
	{ MODKEY|ShiftMask,             XK_q,                     spawn,          SHCMD("xkill") },
};

/* Resize mode (Super+R), like i3's mode "resize" */
static const Key resizekeys[] = {
	{ 0,                            XK_Left,                  resizedir,      {.i = 0 } },
	{ 0,                            XK_Down,                  resizedir,      {.i = 1 } },
	{ 0,                            XK_Up,                    resizedir,      {.i = 2 } },
	{ 0,                            XK_Right,                 resizedir,      {.i = 3 } },
	{ 0,                            XK_Return,                resizemode,     {.i = 0 } },
	{ 0,                            XK_Escape,                resizemode,     {.i = 0 } },
	{ MODKEY,                       XK_r,                     resizemode,     {.i = 0 } },
};

/* button definitions */
/* click can be ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle, ClkClientWin, or ClkRootWin */
static const Button buttons[] = {
	/* click                event mask      button          function        argument */
	{ ClkLtSymbol,          0,              Button1,        spawn,          SHCMD("tux-dwm layout") },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {0} },
	{ ClkWinTitle,          0,              Button2,        zoom,           {0} },
	{ ClkStatusText,        0,              Button1,        sigstatusbar,   {.i = 1} },
	{ ClkStatusText,        0,              Button2,        sigstatusbar,   {.i = 2} },
	{ ClkStatusText,        0,              Button3,        sigstatusbar,   {.i = 3} },
	{ ClkStatusText,        0,              Button4,        sigstatusbar,   {.i = 4} },
	{ ClkStatusText,        0,              Button5,        sigstatusbar,   {.i = 5} },
	/* Super + drag: move, Super + right drag: resize (i3: floating_modifier $mod). On a tiled window
	 * right drag moves the split, as in i3; on a floating one it resizes the window. */
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button2,        spawntag,       {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            0,              Button4,        shiftviewocc,   {.i = -1} },
	{ ClkTagBar,            0,              Button5,        shiftviewocc,   {.i = +1} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
