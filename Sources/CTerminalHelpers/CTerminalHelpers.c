#include "CTerminalHelpers.h"
#include <sys/ioctl.h>

int terminal_set_winsize(int fd, const struct winsize *ws) {
  return ioctl(fd, TIOCSWINSZ, ws);
}
