#ifndef C_TERMINAL_HELPERS_H
#define C_TERMINAL_HELPERS_H

#include <sys/ioctl.h>

int terminal_set_winsize(int fd, const struct winsize *ws);

#endif
