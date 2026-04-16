/* SPDX-FileCopyrightText: 2026 Davide De Rosa
 *
 * SPDX-License-Identifier: GPL-3.0
 */

#pragma once

/**
 * Log callback type. Called from ydtun with log messages.
 * level: 0=error, 1=warn, 2=info, 3=debug, 4=trace
 * message: null-terminated UTF-8 string (valid only during the call)
 */
typedef void (*pp_ydtun_log_fn)(int level, const char *message);

/**
 * Set log callback. Must be called before pp_ydtun_start().
 * If not set, logs go to stderr.
 */
void pp_ydtun_set_log_callback(pp_ydtun_log_fn callback);

/**
 * Start ydtun with space-separated CLI arguments.
 * Example: "--no-color --mode port-forward --pf-listen 127.0.0.1:12345 --telemost-urls https://..."
 * Returns 0 on success, negative on error.
 */
int pp_ydtun_start(const char *args);

/**
 * Stop the running ydtun instance.
 */
void pp_ydtun_stop(void);

/**
 * Returns 1 if ydtun is running, 0 otherwise.
 */
int pp_ydtun_is_running(void);
