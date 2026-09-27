#include "hack.h"

/* The app asks for a player name instead of using the device account. */
boolean whoami(void) { return FALSE; }

extern void NHCopyText(const char *);
void port_insert_pastebuf(char *text) { NHCopyText(text); }
