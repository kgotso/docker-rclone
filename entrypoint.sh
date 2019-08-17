#!/bin/sh

set -e

# Announce version
echo "INFO: Running $(rclone --version | head -n 1)"

# Make sure sync/copy command is ok
if [ "$(echo "$RCLONE_CMD" | tr '[:lower:]' '[:upper:]')" != "SYNC" ] && [ "$(echo "$RCLONE_CMD" | tr '[:lower:]' '[:upper:]')" != "COPY" ] && [ "$(echo "$RCLONE_CMD" | tr '[:lower:]' '[:upper:]')" != "MOVE" ]
then
  echo "WARNING: rclone command '$RCLONE_CMD' is not supported by this container, please use sync/copy/move. Stopping."
  exit 1
fi

# Make sure dir command is ok
if [ "$(echo "$RCLONE_DIR_CMD" | tr '[:lower:]' '[:upper:]')" != "LS" ] && [ "$(echo "$RCLONE_DIR_CMD" | tr '[:lower:]' '[:upper:]')" != "LSF" ]
then
  echo "WARNING: rclone directory command '$RCLONE_DIR_CMD' is not supported by this container, please use ls or lsf. Stopping."
  exit 1
fi

# Re-write cron shortcut
case "$(echo "$CRON" | tr '[:lower:]' '[:upper:]')" in
    *@YEARLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 1 1 *" && CRONS="0 0 1 1 *";;
    *@ANNUALLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 1 1 *" && CRONS="0 0 1 1 *";;
    *@MONTHLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 1 * *" && CRONS="0 0 1 * * ";;
    *@WEEKLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 * * 0" && CRONS="0 0 * * 0";;
    *@DAILY* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 * * *" && CRONS="0 0 * * *";;
    *@MIDNIGHT* ) echo "INFO: Cron shortcut $CRON re-written to 0 0 * * *" && CRONS="0 0 * * *";;
    *@HOURLY* ) echo "INFO: Cron shortcut $CRON re-written to 0 * * * *" && CRONS="0 * * * *";;
    *@* ) echo "WARNING: Cron shortcut $CRON is not supported. Stopping." && exit 1;;
    * ) CRONS=$CRON;;
esac

# Set time zone if passed in
if [ ! -z "$TZ" ]
then
  cp /usr/share/zoneinfo/$TZ /etc/localtime
  echo $TZ > /etc/timezone
fi

chmod u+x /clear.sh
rm -f /tmp/sync.pid

if [ ! -z "$SYNC_TEMP" ] 
then
  SYNC_TEMP=SYNC_DEST
fi

# Check for source and destination ; launch config if missing
if [ -z "$SYNC_SRC" ] || [ -z "$SYNC_DEST" ]
then
  echo "INFO: No SYNC_SRC and SYNC_DEST found. Starting rclone config"
  rclone config $RCLONE_OPTS
  echo "INFO: Define SYNC_SRC and SYNC_DEST to start sync process."
else
  # SYNC_SRC and SYNC_DEST setup
  # run sync either once or in cron depending on CRON

  #Create fail URL if CHECK_URL is populated but FAIL_URL is not 
  if [ ! -z "$CHECK_URL" ] && [ -z "$FAIL_URL" ]
  then
    FAIL_URL="${CHECK_URL}/fail"
  fi

  if [ -z "$CRONS" ]
  then
    echo "INFO: No CRON setting found. Running sync once."
    echo "INFO: Add CRON=\"0 0 * * *\" to perform sync every midnight"
    /sync.sh
  else
    if [ -z "$FORCE_SYNC" ]
    then
      echo "INFO: Add FORCE_SYNC=1 to perform a sync upon boot"
    else
      /sync.sh
    fi

    # Setup cron schedule
    crontab -d
    echo "$CRONS /sync.sh >>/tmp/sync.log 2>&1" > /tmp/crontab.tmp
    if [ -z "$CRON_ABORT" ]
    then
      echo "INFO: Add CRON_ABORT=\"0 6 * * *\" to cancel outstanding sync at 6am"
    else
      echo "$CRON_ABORT /sync-abort.sh >>/tmp/sync.log 2>&1" >> /tmp/crontab.tmp
    fi
    echo "$CRON_CLEAR /clear.sh >>/tmp/sync.log 2>&1" >> /tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp

    # Start cron
    echo "INFO: Starting crond ..."
    touch /tmp/sync.log
    touch /tmp/crond.log
    crond -b -l 0 -L /tmp/crond.log
    echo "INFO: crond started"
    tail -F /tmp/crond.log /tmp/sync.log
  fi
fi
