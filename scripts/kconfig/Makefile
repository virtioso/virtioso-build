# SPDX-License-Identifier: GPL-2.0
# Standalone Kconfig Makefile for virtioso-build
# Based on Linux kernel scripts/kconfig/Makefile

CC ?= gcc
HOSTCC ?= $(CC)
CFLAGS ?= -O2 -Wall
HOSTCFLAGS := $(CFLAGS) -I../include

# Check for ncurses
NCURSES_CFLAGS := $(shell pkg-config --cflags ncurses 2>/dev/null || echo "-D_GNU_SOURCE")
NCURSES_LIBS := $(shell pkg-config --libs ncurses 2>/dev/null || echo "-lncurses")

# Common objects
common-objs := confdata.o expr.o lexer.lex.o menu.o parser.tab.o \
               preprocess.o symbol.o util.o

# conf (non-interactive config tool)
conf-objs := conf.o $(common-objs)

# mconf (menuconfig)
lxdialog-objs := lxdialog/checklist.o lxdialog/inputbox.o lxdialog/menubox.o \
                 lxdialog/textbox.o lxdialog/util.o lxdialog/yesno.o
mconf-objs := mconf.o mnconf-common.o $(lxdialog-objs) $(common-objs)

.PHONY: all clean

all: conf mconf

conf: $(conf-objs)
	$(HOSTCC) -o $@ $^

mconf: CFLAGS += $(NCURSES_CFLAGS)
mconf: $(mconf-objs)
	$(HOSTCC) -o $@ $^ $(NCURSES_LIBS)

# Compile rules
%.o: %.c
	$(HOSTCC) $(HOSTCFLAGS) -c -o $@ $<

lxdialog/%.o: lxdialog/%.c
	$(HOSTCC) $(HOSTCFLAGS) $(NCURSES_CFLAGS) -c -o $@ $<

# Dependencies (simplified)
$(common-objs): lkc.h lkc_proto.h expr.h internal.h
conf.o: lkc.h
mconf.o: lkc.h mnconf-common.h
mnconf-common.o: mnconf-common.h lkc.h
$(lxdialog-objs): lxdialog/dialog.h

clean:
	rm -f conf mconf *.o lxdialog/*.o
