/* SPDX-FileCopyrightText: 2026 Davide De Rosa
 *
 * SPDX-License-Identifier: GPL-3.0
 */

#pragma once

/**
 * Start sing-box with a JSON configuration.
 * Returns 0 on success, non-zero on error.
 */
int pp_singbox_start(const char *config_json);

/**
 * Stop the running sing-box instance.
 */
void pp_singbox_stop(void);

/**
 * Returns 1 if sing-box is running, 0 otherwise.
 */
int pp_singbox_is_running(void);

/**
 * Returns the sing-box version string.
 */
const char *pp_singbox_version(void);
