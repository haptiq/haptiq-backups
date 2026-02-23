# Haptiq Backups

A bash script for creating encrypted WordPress backups using restic and storing them on remote storage.

## What it does

- Exports WordPress databases using WP-CLI
- Creates encrypted backups of site files and database dumps
- Stores backups on remote storage using restic
- Handles backup scheduling with cron-like syntax
- Removes old backups based on retention policies
- Cross-platform compatible (macOS/Linux)

## Installation

### Requirements

Environments may vary, a lot. Ideally you have SSH access to the system where the backup script should be periodically executed and the ability to install tools.

- SSH access
- Ability to install `restic` and `wp-cli`
- Ability to execute commands/scripts
- Ability to create cronjobs to automate backups

### Step by step

1. Install dependencies:
   - [restic](https://restic.net/)
   - [WP-CLI](https://wp-cli.org/)

2. Clone this repository:
   ```bash
   git clone https://github.com/haptiq/haptiq-backups.git
   cd haptiq-backups
   ```

3. Make the script executable:
   ```bash
   chmod +x haptiq-backups.sh
   ```

## Configuration

Create `.env` files in `~/.config/haptiq-backups/` for each site you want to backup. See [example.com.env](example.com.env) for a complete configuration example.

## Usage

Run manually:
```bash
./haptiq-backups.sh
```

Or add to crontab for automatic execution:
```bash
# Check every 5 minutes
*/5 * * * * /path/to/haptiq-backups.sh
```

The script compares the last backup time with the scheduled time from each site's configuration and only runs backups when they're due. This allows you to run the script frequently without creating unnecessary backups.

## License

GNU General Public License v3 (https://www.gnu.org/licenses/gpl-3.0.html)

## Get In Touch

[![Haptiq Studio – Get In Touch](http://media.haptiq.studio/haptiq-github-banner.jpg)](https://haptiq.studio/)
