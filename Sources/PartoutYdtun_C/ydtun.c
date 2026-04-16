/*
 * SPDX-FileCopyrightText: 2026 Davide De Rosa
 *
 * SPDX-License-Identifier: GPL-3.0
 *
 * C bridging layer for ydtun Rust library.
 * The Rust library (libydtun.a) is statically linked via SwiftPM.
 */

#include "ydtun/ydtun.h"

/* Rust FFI symbols from ydtun's capi.rs */
extern void ydtun_set_log_callback(pp_ydtun_log_fn callback);
extern int ydtun_start(const char *args);
extern void ydtun_stop(void);
extern int ydtun_is_running(void);

void pp_ydtun_set_log_callback(pp_ydtun_log_fn callback) {
    ydtun_set_log_callback(callback);
}

int pp_ydtun_start(const char *args) {
    return ydtun_start(args);
}

void pp_ydtun_stop(void) {
    ydtun_stop();
}

int pp_ydtun_is_running(void) {
    return ydtun_is_running();
}
