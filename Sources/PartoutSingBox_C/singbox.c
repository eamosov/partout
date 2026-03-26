/*
 * SPDX-FileCopyrightText: 2026 Davide De Rosa
 *
 * SPDX-License-Identifier: GPL-3.0
 *
 * C bridging layer for sing-box Go library.
 * The Go library (libsingbox.a / sing-box-apple xcframework)
 * is statically linked via SwiftPM on Apple platforms.
 */

#include "singbox/singbox.h"
#include "sing_box.h"

int pp_singbox_start(const char *config_json) {
    return sing_box_start(config_json);
}

void pp_singbox_stop(void) {
    sing_box_stop();
}

int pp_singbox_is_running(void) {
    return sing_box_is_running();
}

const char *pp_singbox_version(void) {
    return sing_box_version();
}
