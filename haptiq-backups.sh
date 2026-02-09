#!/bin/bash

# =============================================================
#
# Haptiq Backups
#
# Creates encrypted WordPress backups using restic and stores
# them on an external storage server.
#
# Version: 0.1.0
#
# =============================================================


# =============================================================
# Set default variables
# =============================================================
SCRIPT_VERSION="0.1.0"
PATH=$PATH:~/bin:/usr/local/bin:/usr/bin:/bin:/opt/share/bin
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITES="$HOME/.config/haptiq-backups"


# =============================================================
# Fix hostnames to be consistent
#
# Fixes issue where hostnames differ on macOS, depending
# on the connected network and other variables.
# =============================================================
if command -v scutil &> /dev/null; then
	# macOS: use LocalHostName, which is consistent
	HOSTNAME=$(scutil --get LocalHostName)
else
	# Linux etc: use the standard hostname
	HOSTNAME=$(hostname)
fi
export RESTIC_HOST="$HOSTNAME"


# =============================================================
# Detect GNU vs BSD date for cross-platform compatibility
# =============================================================
if date -d "2021-01-01" >/dev/null 2>&1; then
	IS_GNU_DATE=true
else
	IS_GNU_DATE=false
fi


# =============================================================
# Get current timestamp for date calculations
# =============================================================
now=$(date +%s)


# =============================================================
# Cross-platform date wrapper function
#
# Usage: 
#   date_compat "@timestamp" "+%Y-%m-%d"     – Convert timestamp to date
#   date_compat "2023-12-25" "+%s"           – Convert date string to timestamp  
#   date_compat "2023-12-25 10:30:00" "+%s"  – Convert datetime string to timestamp
#   date_compat "+%-m"                       – Get current month without leading zero
# =============================================================
date_compat() {
	local input="$1"
	local format="$2"
	
	if $IS_GNU_DATE; then
		if [[ "$input" == +* ]]; then
			# Format-only call (no input date)
			date "$input"
		else
			# Input date provided
			date -d "$input" "$format"
		fi
	else
		# BSD date (macOS)
		if [[ "$input" == +* ]]; then
			# Format-only call - handle %-m, %-d, %-H, %-M format specifiers
			local fmt="$input"
			if [[ "$fmt" == *"%-m"* ]]; then
				date +%m | sed 's/^0*//'
			elif [[ "$fmt" == *"%-d"* ]]; then
				date +%d | sed 's/^0*//'
			elif [[ "$fmt" == *"%-H"* ]]; then
				date +%H | sed 's/^0*//'
			elif [[ "$fmt" == *"%-M"* ]]; then
				date +%M | sed 's/^0*//'
			else
				date "$fmt"
			fi
		elif [[ "$input" == @* ]]; then
			# Timestamp input (@1234567890)
			local timestamp="${input#@}"
			if [[ "$format" == *"%-"* ]]; then
				# Handle %-m, %-d format specifiers
				if [[ "$format" == *"%-m"* ]]; then
					date -r "$timestamp" +%m | sed 's/^0*//'
				elif [[ "$format" == *"%-d"* ]]; then
					date -r "$timestamp" +%d | sed 's/^0*//'
				else
					date -r "$timestamp" "$format"
				fi
			else
				date -r "$timestamp" "$format"
			fi
		else
			# Date string input
			if [[ "$input" == *" "* ]]; then
				# DateTime format: "2023-12-25 10:30:00"
				date -j -f "%Y-%m-%d %H:%M:%S" "$input" "$format" 2>/dev/null
			else
				# Date format: "2023-12-25"
				date -j -f "%Y-%m-%d" "$input" "$format" 2>/dev/null
			fi
		fi
	fi
}


# =============================================================
# Setup Restic Repository
#
# Makes sure the restic repository exists on the backup
# storage server, and if not, initializes a new one.
# =============================================================
setup_restic_repository() {
	echo "Checking restic repository setup for $SITE_DOMAIN..."
	
	# Check if repository exists and is accessible
	echo "Checking restic repository at $RESTIC_REPOSITORY_REMOTE"
	if restic cat config --repo="$RESTIC_REPOSITORY_REMOTE" &>/dev/null; then
		echo "Restic repository exists and is accessible"
		return 0
	else
		# More specific error handling (optional)
		echo "Repository check failed - could be:"
		echo "  - Repository doesn't exist"
		echo "  - Wrong password (RESTIC_PASSWORD)"
		echo "  - Connection issues"
		echo "Attempting to initialize..."
	fi

	# Repository doesn't exist - initialize it
	if restic init --repo="$RESTIC_REPOSITORY_REMOTE"; then
		echo "Backup Repository initialized for $SITE_DOMAIN"
		return 0
	else
		echo "Error: Failed to initialize restic repository for $SITE_DOMAIN"
		return 1
	fi
}


# =============================================================
# Export the database using WP-CLI
# =============================================================
export_db() {
	echo "Exporting database"
	wp db export "/tmp/$SITE_DOMAIN.sql" --path="$SITE_PATH" --add-drop-table --single-transaction
}


# =============================================================
# Run backup
# =============================================================
run_backup() {
	echo "Processing $SITE_DOMAIN backup"
	
	if ! setup_restic_repository; then
		echo "Error: Could not set up restic repository for $SITE_DOMAIN"
		echo "Skipping backup for this site"
		echo "------"
		return 1
	fi

	# Create database export
	echo "Exporting database for $SITE_DOMAIN"
	if ! export_db; then
		echo "Error: Database export failed for $SITE_DOMAIN"
		echo "Skipping backup for this site"
		echo "------"
		return 1
	fi

	# Run the backup (this will backup both the site files & exported database)
	if restic backup "$SITE_PATH" "/tmp/$SITE_DOMAIN.sql" --repo="$RESTIC_REPOSITORY_REMOTE" --tag "v=$SCRIPT_VERSION"; then
		echo "Backup for $SITE_DOMAIN completed successfully"
	else
		echo "Error: Backup failed for $SITE_DOMAIN"
		return 1
	fi

	# Remove the exported database file
	if rm "/tmp/$SITE_DOMAIN.sql"; then
		echo "Temporary database dump file for $SITE_DOMAIN removed"
	else
		echo "Warning: Could not remove temporary database dump file for $SITE_DOMAIN"
	fi

	echo "Backup for $SITE_DOMAIN completed."
	echo "------"

	return 0
}


# =============================================================
# Remove old backups
#
# Deletes old backups according to the retention rules
# =============================================================
remove_old_backups() {
	echo "Processing old backups for $SITE_DOMAIN"

	# Use config values if set, otherwise use defaults
	KEEP_YEARLY="${KEEP_YEARLY:-}"
	KEEP_MONTHLY="${KEEP_MONTHLY:-3}"
	KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
	KEEP_DAILY="${KEEP_DAILY:-7}"
	KEEP_HOURLY="${KEEP_HOURLY:-24}"
	KEEP_LAST="${KEEP_LAST:-10}"

	# Build the restic keep arguments
	KEEP_ARGS=""
	[[ -n "$KEEP_YEARLY" ]] && KEEP_ARGS="$KEEP_ARGS --keep-yearly $KEEP_YEARLY"
	[[ -n "$KEEP_MONTHLY" ]] && KEEP_ARGS="$KEEP_ARGS --keep-monthly $KEEP_MONTHLY"
	[[ -n "$KEEP_WEEKLY" ]] && KEEP_ARGS="$KEEP_ARGS --keep-weekly $KEEP_WEEKLY"
	[[ -n "$KEEP_DAILY" ]] && KEEP_ARGS="$KEEP_ARGS --keep-daily $KEEP_DAILY"
	[[ -n "$KEEP_HOURLY" ]] && KEEP_ARGS="$KEEP_ARGS --keep-hourly $KEEP_HOURLY"
	[[ -n "$KEEP_LAST" ]] && KEEP_ARGS="$KEEP_ARGS --keep-last $KEEP_LAST"
	
	restic forget --repo="$RESTIC_REPOSITORY_REMOTE" --prune $KEEP_ARGS
	
	echo "Old backups have been removed"
	
	# Clean up old cache directories
	echo "Cleaning up old cache directories..."
	restic cache --cleanup --repo="$RESTIC_REPOSITORY_REMOTE" 2>/dev/null || true
}


# =============================================================
# Get the date of last schedule
#
# Calculates when the last backup should have run based on
# the provided cron-like schedule.
# =============================================================
get_last_schedule_time() {

	# Parse our cron-like schedule fields
	set -f # disables glob expansion to avoid conflicts with * characters
	set -- $SCHEDULE
	set +f
	local min_field="$1"
	local hour_field="$2"
	local day_field="$3"
	local month_field="$4"
	local weekday_field="$5"

	# Current date components
	local today_year=$( date +%Y )
	local today_month=$( date_compat "+%-m" )
	local today_day=$( date_compat "+%-d" )
	local today_weekday=$( date +%w )

	# Variables for our target date
	local target_year="$today_year"
	local target_month="$today_month"
	local target_day="$today_day"

	# STEP 1: Check Weekday
	local weekday_target_date=""
	if [ "$weekday_field" != "*" ]; then
		local target_weekday="$weekday_field"
		local days_back
		
		echo "DEBUG: target_weekday='$target_weekday'" >&2
		echo "DEBUG: today_weekday='$today_weekday'" >&2
		echo "DEBUG: weekday_field='$weekday_field'" >&2
		if [ "$target_weekday" -eq "$today_weekday" ]; then
			days_back=0
		else
			days_back=$(( (today_weekday - target_weekday + 7) % 7 ))
		fi
		
		# Calculate the weekday target date
		local days_back_seconds=$((days_back * 86400))
		local target_ts=$((now - days_back_seconds))
		weekday_target_date=$(date_compat "@$target_ts" "+%Y-%m-%d")
		local weekday_year=$(date_compat "$weekday_target_date" "+%Y")
		local weekday_month=$(date_compat "$weekday_target_date" "+%-m")
		local weekday_day=$(date_compat "$weekday_target_date" "+%-d")
	fi

	# STEP 2: Check Month
	if [ "$month_field" = "*" ]; then
		target_month="$today_month"
	else
		target_month="$month_field"
	fi

	# STEP 3: Check Day
	if [ "$day_field" = "*" ]; then
		target_day="$today_day"
	else
		target_day="$day_field"
	fi

	# STEP 4: Join together last_schedule target date
	# Build the date string
	local target_date_str="${target_year}-${target_month}-${target_day}"
	
	local target_date_str=$(printf "%04d-%02d-%02d" "$target_year" "$target_month" "$target_day")
	local today_date=$(date +%Y-%m-%d)

	# String comparison works because YYYY-MM-DD is sortable
	if [[ "$target_date_str" > "$today_date" ]]; then
		target_year=$((target_year - 1))
		target_date_str=$(printf "%04d-%02d-%02d" "$target_year" "$target_month" "$target_day")
	fi

	# STEP 5: Check which is the newest (weekday vs date-based)
	local final_date
	if [ -n "$weekday_target_date" ]; then
		# We have both a weekday constraint and date constraint
		local weekday_ts=$(date_compat "$weekday_target_date" "+%s")
		target_date=$(date_compat "$target_date_str" "+%s")
		
		# Use the one that is most recent
		if [ "$weekday_ts" -ge "$target_date" ]; then
			final_date="$weekday_target_date"
		else
			final_date="$target_date_str"
		fi
	else
		final_date="$target_date_str"
	fi

	# Now add the time component (hour:minute)
	local target_hour="$hour_field"
	local target_min="$min_field"
	
	# Handle wildcards and step values for time
	if [ "$target_hour" = "*" ]; then
		target_hour=$(date_compat "@$now" "+%-H")
	fi

	if [ "$target_min" = "*" ]; then
		target_min=$(date_compat "@$now" "+%-M")
	elif [[ "$target_min" =~ ^\*/([0-9]+)$ ]]; then
		# Handle */15 style
		local step="${BASH_REMATCH[1]}"
		local now_min=$(date_compat "@$now" "+%-M")
		target_min=$(( (now_min / step) * step ))
	fi

	# Build final timestamp
	local final_datetime="${final_date} ${target_hour}:${target_min}:00"
	local final_ts=$(date_compat "$final_datetime" "+%s")
	
	# If the calculated time is in the future, we need to go back
	if [ "$final_ts" -gt "$now" ]; then
		# Go back based on the schedule pattern
		if [ "$weekday_field" != "*" ]; then
			# Weekly schedule - go back 7 days
			final_ts=$((final_ts - 604800))  # 7 days in seconds
		elif [ "$day_field" != "*" ]; then
			# Monthly schedule - go back ~1 month (30 days)
			final_ts=$((final_ts - 2592000))  # 30 days in seconds
		else
			# Daily schedule - go back 1 day
			final_ts=$((final_ts - 86400))  # 1 day in seconds
		fi
	fi
	
	echo "$final_ts"
}


# =============================================================
# Check if the backup should run now
# 
# Compares time of last backup with time of last schedule
# to theck if there was a backup since last schedule.
# =============================================================
should_run_backup() {
	# Check last backup lockfile
	local last_backup_file="/tmp/.last_backup-${SITE_DOMAIN}"
	
	# Get last scheduled time
	local last_schedule=$(get_last_schedule_time "$SCHEDULE")
	
	# Get last actual backup time from lockfile if available
	local last_backup
	if [ -f "$last_backup_file" ]; then
		last_backup=$(cat "$last_backup_file")
	else
		# Get last backup time from restic, if no lockfile was found
		local restic_output=$(restic snapshots --repo="$RESTIC_REPOSITORY_REMOTE" --latest 1)
		local restic_time=""
		
		# Extract datetime from restic output (format: YYYY-MM-DD HH:MM:SS)
		if [[ "$restic_output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
			restic_time="${BASH_REMATCH[0]}"
			
			# Convert to timestamp
			if $IS_GNU_DATE; then
				last_backup=$(date -d "$restic_time" +%s 2>/dev/null)
			else
				# BSD date
				last_backup=$(date -j -f "%Y-%m-%d %H:%M:%S" "$restic_time" +%s 2>/dev/null)
			fi
		fi

		# If still not found, use epoch 0
		last_backup="${last_backup:-0}"
		
		# Write lockfile to cache the result
		echo "$last_backup" > "$last_backup_file"
	fi
	
	# Safety check for empty values
	if [[ -z "$last_schedule" || -z "$last_backup" ]]; then
		echo "Error: Empty timestamp values - last_schedule='$last_schedule' last_backup='$last_backup'"
		return 1
	fi
	
	# Check if the last scheduled time is after the last backup
	if [ "$last_schedule" -gt "$last_backup" ]; then
		echo "Backup is overdue! Running now..."
		
		# Check restic lockfile to avoid multiple backups running at once
		local LOCKS=$(restic list locks --repo="$RESTIC_REPOSITORY_REMOTE" --quiet)
		if [ -n "$LOCKS" ]; then
			echo "A backup for $SITE_DOMAIN is already running. Skipping."
			exit 1
		fi

		return 0
	else
		echo "Backup is up to date. Skipping."
		return 1
	fi
}


# ===================================================
# Main Execution of the script
#
# Actually runs the whole script, looping through all site backups
# ===================================================
if [[ ! -d "$SITES" ]]; then
	echo "Error: Sites directory '$SITES' not found"
	exit 1
fi

for SITE in "$SITES"/*.env; do

	if [[ ! -f "$SITE" ]]; then
		echo "No .env files found in $SITES"
		break
	fi
	
	echo "Loading configuration from $(basename "$SITE")..."

	# Source environment file first, so all functions can access variables
	set -a
	source "$SITE"
	set +a

	# Check if required variables are set
	if [[ -z "$SITE_DOMAIN" || -z "$SITE_PATH" || -z "$RESTIC_REPOSITORY_REMOTE" ]]; then
		echo "Error: Missing required variables in $(basename "$SITE")"
		echo "Skipping this site..."
		continue
	fi

	# Check if backup should run for this site, and then run it
	if should_run_backup; then
		if run_backup; then
			last_backup_file="/tmp/.last_backup-${SITE_DOMAIN}"
			date +%s > "$last_backup_file"
			remove_old_backups
		fi
	fi
done

echo "All backups completed!"