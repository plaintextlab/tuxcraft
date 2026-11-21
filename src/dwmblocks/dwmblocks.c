#include<stdlib.h>
#include<stdio.h>
#include<string.h>
#include<unistd.h>
#include<signal.h>
#ifndef NO_X
#include<X11/Xlib.h>
#endif
#ifdef __OpenBSD__
#define SIGPLUS			SIGUSR1+1
#define SIGMINUS		SIGUSR1-1
#else
#define SIGPLUS			SIGRTMIN
#define SIGMINUS		SIGRTMIN
#endif
#define LENGTH(X)               (sizeof(X) / sizeof (X[0]))
#define CMDLENGTH		120 /* tuxcraft: glyphs are 4 bytes each, and a song title */
#define MIN( a, b ) ( ( a < b) ? a : b )
#define STATUSLENGTH (LENGTH(blocks) * CMDLENGTH + 1)

typedef struct {
	char* icon;
	char* command;
	unsigned int interval;
	unsigned int signal;
	unsigned int joined; /* tuxcraft: 1 = no delimiter after this block (the music buttons) */
} Block;
#ifndef __OpenBSD__
void dummysighandler(int num);
#endif
void sighandler(int num);
void buttonhandler(int sig, siginfo_t *si, void *ucontext);
void getcmds(int time);
void getsigcmds(unsigned int signal);
void setupsignals();
void sighandler(int signum);
int getstatus(char *str, char *last);
void statusloop();
void termhandler();
void pstdout();
#ifndef NO_X
void setroot();
static void (*writestatus) () = setroot;
static int setupX();
static Display *dpy;
static int screen;
static Window root;
#else
static void (*writestatus) () = pstdout;
#endif


#include "blocks.h"

static char statusbar[LENGTH(blocks)][CMDLENGTH] = {0};
static char statusstr[2][STATUSLENGTH];
static int statusContinue = 1;
static int returnStatus = 0;

//opens process *cmd and stores output in *output
void getcmd(const Block *block, char *output)
{
	//make sure status is same until output is ready
	char tempstatus[CMDLENGTH] = {0};
	/* statuscmd: the block's signal number goes first, so dwm knows which block a click hit */
	int s = block->signal ? 1 : 0;
	if (s)
		tempstatus[0] = block->signal;
	strcpy(tempstatus + s, block->icon);
	FILE *cmdf = popen(block->command, "r");
	if (!cmdf)
		return;
	int i = strlen(block->icon) + s;
	fgets(tempstatus+i, CMDLENGTH-i-delimLen, cmdf);
	i = strlen(tempstatus);
	if (i > s && tempstatus[i-1] == '\n') /* tuxcraft: an empty line is nothing too */
		tempstatus[--i] = '\0';
	if (i == s) /* the command printed nothing: hide the block, its signal byte too */
		i = 0, tempstatus[0] = '\0';
	//if block and command output are both not empty
	if (i != 0) {
		//only chop off newline if one is present at the end
		i = tempstatus[i-1] == '\n' ? i-1 : i;
		if (block->joined) {
			tempstatus[i++] = ' ';
			tempstatus[i] = '\0';
		} else if (delim[0] != '\0') {
			strncpy(tempstatus+i, delim, delimLen);
		}
		else
			tempstatus[i++] = '\0';
	}
	strcpy(output, tempstatus);
	pclose(cmdf);
}

void getcmds(int time)
{
	const Block* current;
	for (unsigned int i = 0; i < LENGTH(blocks); i++) {
		current = blocks + i;
		if ((current->interval != 0 && time % current->interval == 0) || time == -1)
			getcmd(current,statusbar[i]);
	}
}

void getsigcmds(unsigned int signal)
{
	const Block *current;
	for (unsigned int i = 0; i < LENGTH(blocks); i++) {
		current = blocks + i;
		if (current->signal == signal)
			getcmd(current,statusbar[i]);
	}
}

void setupsignals()
{
#ifndef __OpenBSD__
	    /* initialize all real time signals with dummy handler */
    for (int i = SIGRTMIN; i <= SIGRTMAX; i++)
        signal(i, dummysighandler);
#endif

	struct sigaction sa = {0};
	sa.sa_sigaction = buttonhandler;
	sa.sa_flags = SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	for (unsigned int i = 0; i < LENGTH(blocks); i++) {
		if (blocks[i].signal > 0)
			sigaction(SIGMINUS+blocks[i].signal, &sa, NULL);
	}
	signal(SIGCHLD, SIG_IGN); /* click commands: no zombies */

}

int getstatus(char *str, char *last)
{
	strcpy(last, str);
	str[0] = '\0';
	for (unsigned int i = 0; i < LENGTH(blocks); i++)
		strcat(str, statusbar[i]);
	str[strlen(str)-strlen(delim)] = '\0';
	return strcmp(str, last);//0 if they are the same
}

#ifndef NO_X
void setroot()
{
	if (!getstatus(statusstr[0], statusstr[1]))//Only set root if text has changed.
		return;
	XStoreName(dpy, root, statusstr[0]);
	XFlush(dpy);
}

int setupX()
{
	dpy = XOpenDisplay(NULL);
	if (!dpy) {
		fprintf(stderr, "dwmblocks: Failed to open display\n");
		return 0;
	}
	screen = DefaultScreen(dpy);
	root = RootWindow(dpy, screen);
	return 1;
}
#endif

void pstdout()
{
	if (!getstatus(statusstr[0], statusstr[1]))//Only write out if text has changed.
		return;
	printf("%s\n",statusstr[0]);
	fflush(stdout);
}


void statusloop()
{
	setupsignals();
	int i = 0;
	getcmds(-1);
	while (1) {
		getcmds(i++);
		writestatus();
		if (!statusContinue)
			break;
		sleep(1.0);
	}
}

#ifndef __OpenBSD__
/* this signal handler should do nothing */
void dummysighandler(int signum)
{
    return;
}
#endif

void sighandler(int signum)
{
	getsigcmds(signum-SIGPLUS);
	writestatus();
}

/* statuscmd: dwm sends the block's signal with the mouse button as its value (sigqueue). Run the
 * block's command with BLOCK_BUTTON set, as dwmblocks' statuscmd patch does; a plain signal
 * (pkill -RTMIN+N dwmblocks) just updates the block. */
void buttonhandler(int sig, siginfo_t *si, void *ucontext)
{
	int button = si->si_code == SI_QUEUE ? si->si_value.sival_int : 0;

	sig -= SIGPLUS;
	if (button <= 0) {
		getsigcmds(sig);
		writestatus();
		return;
	}
	for (unsigned int i = 0; i < LENGTH(blocks); i++) {
		if (blocks[i].signal != (unsigned int)sig)
			continue;
		if (fork() == 0) {
			char b[12];
			snprintf(b, sizeof b, "%d", button);
			setenv("BLOCK_BUTTON", b, 1);
			setsid();
			if (!freopen("/dev/null", "w", stdout)) /* the click's own output is not shown */
				_exit(1);
			execl("/bin/sh", "sh", "-c", blocks[i].command, (char *)NULL);
			_exit(127);
		}
		break;
	}
}

void termhandler()
{
	statusContinue = 0;
}

int main(int argc, char** argv)
{
	for (int i = 0; i < argc; i++) {//Handle command line arguments
		if (!strcmp("-d",argv[i]))
			strncpy(delim, argv[++i], delimLen);
		else if (!strcmp("-p",argv[i]))
			writestatus = pstdout;
	}
#ifndef NO_X
	if (!setupX())
		return 1;
#endif
	delimLen = MIN(delimLen, strlen(delim));
	delim[delimLen++] = '\0';
	signal(SIGTERM, termhandler);
	signal(SIGINT, termhandler);
	statusloop();
#ifndef NO_X
	XCloseDisplay(dpy);
#endif
	return 0;
}
