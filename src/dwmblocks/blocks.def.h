/* tuxcraft dwmblocks: the same blocks as tuxcraft's polybar, in BreadOnPenguins' style (glyph +
 * value, " | " between blocks). Each block is "tux-dwmbar NAME" (bin/tux-dwmbar); a click runs it
 * again with BLOCK_BUTTON set (1 left, 2 middle, 3 right, 4/5 scroll), with polybar's actions.
 * The signal numbers are what dwm sends on a click and what "pkill -RTMIN+N dwmblocks" updates;
 * tux-dwmbar uses the same numbers. Rebuild after editing: tux-dwm build. */
static const Block blocks[] = {
	/*Icon*/	/*Command*/			/*Update Interval*/	/*Update Signal*/
	{"",		"tux-dwmbar music",		2,		1},
	{"",		"tux-dwmbar cpu",		2,		2},
	{"",		"tux-dwmbar memory",		3,		3},
	{"",		"tux-dwmbar gpu",		3,		4},
	{"",		"tux-dwmbar updates",		60,		5},	/* cached; refreshed in the background every 30 min */
	{"",		"tux-dwmbar bluetooth",		10,		6},
	{"",		"tux-dwmbar volume",		2,		7},
	{"",		"tux-dwmbar network",		5,		8},
	{"",		"tux-dwmbar battery",		15,		9},
	{"",		"tux-dwmbar power",		5,		11},	/* (10 is a newline: kept free) */
	{"",		"tux-dwmbar record",		2,		12},
	{"",		"tux-dwmbar clock",		1,		13},
};

//sets delimiter between status commands. NULL character ('\0') means no delimiter.
static char delim[] = "  |  ";   /* her bar: a wide gap around each "|" */
static unsigned int delimLen = 5;
