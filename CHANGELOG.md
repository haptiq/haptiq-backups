# Changelog

## [0.2.0] - 2026-03-04

### Added
- **Added centralised log function** — all output now goes through a dedicated `log()` function that prepends timestamps to every message, replacing `echo` calls throughout the script.
- **Log file output** — logs are written to a dedicated log file by default now. Existing cronjobs should be updated to remove any output redirection (e.g. `>> /path/to/log`), as the script handles this itself going forward.
- **LICENSE file** — added an explicit license file.
- **CHANGELOG file** — added changelog file.

### Changed
- Script file is now **executable by default** (`chmod +x`), so no manual permission change should be needed after cloning or downloading.
- README expanded with additional licensing and usage information.

### Fixed
- **Stale lock file handling** — a stale lock file could previously block execution for subsequent sites in the queue. This has been fixed and stale locks are now detected and cleaned up properly.

## [0.1.0] - Initial release

- Initial release of Haptiq Backups
- Per-site configuration via `.env` files.
- Scheduled backup intervals configurable per site with cron-like syntax