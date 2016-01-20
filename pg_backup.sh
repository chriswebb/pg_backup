#!/bin/bash
 
###########################
####### LOAD CONFIG #######
###########################
 
while [ $# -gt 0 ]; do
    case $1 in
        -q)
            QUIET="true"
            shift 1
            ;;
        -H)
            HOURLY="true"
            shift 1
            ;;
        -c)
            CONFIG_FILE_PATH="$2"
            shift 2
            ;;
        *)
            ${ECHO} "Unknown Option \"$1\"" 1>&2
            exit 2
            ;;
    esac
done
 
if [ -z $CONFIG_FILE_PATH ] ; then
    SCRIPTPATH=$(cd ${0%/*} && pwd -P)
    CONFIG_FILE_PATH="${SCRIPTPATH}/pg_backup.config"
fi
 
if [ ! -r ${CONFIG_FILE_PATH} ] ; then
    echo "Could not load config file from ${CONFIG_FILE_PATH}" 1>&2
    exit 1
fi
 
source "${CONFIG_FILE_PATH}"
 
###########################
#### PRE-BACKUP CHECKS ####
###########################
 
# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ] ; then
    echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
    exit 1
fi
 
 
###########################
### INITIALISE DEFAULTS ###
###########################
 
if [ ! $HOSTNAME ]; then
    LOCALONLY="true"
fi;
 
if [ ! $USERNAME ]; then
    USERNAME="postgres"
fi;
 
 
###########################
#### START THE BACKUPS ####
###########################
 
function perform_backups()
{
    SUFFIX=$1

    if [ $HOURLY ]; then
        FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d_\%H-\%M-\%S`$SUFFIX/"
    else
        FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`$SUFFIX/"
    fi

    CURRENT_TIMESTAMP=`date +\%Y\%m\%d\%H\%M\%S`

    if [ ! $QUIET ]; then
        echo "Making backup directory in $FINAL_BACKUP_DIR"
    fi
 
    if ! mkdir -p $FINAL_BACKUP_DIR; then
        echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" 1>&2
        exit 1;
    fi
 
 
    ###########################
    ### SCHEMA-ONLY BACKUPS ###
    ###########################
 
    for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }; do
        SCHEMA_ONLY_CLAUSE="$SCHEMA_ONLY_CLAUSE or datname ~ '$SCHEMA_ONLY_DB'"
    done
 
    SCHEMA_ONLY_QUERY="select datname from pg_database where false $SCHEMA_ONLY_CLAUSE order by datname;"
 
    if [ ! $QUIET ]; then
        echo -e "\n\nPerforming schema-only backups"
        echo -e "--------------------------------------------\n"
    fi;
 
    if [ $LOCALONLY ]; then
        SCHEMA_ONLY_DB_LIST=`psql -At -c "$SCHEMA_ONLY_QUERY" postgres`
    else
        SCHEMA_ONLY_DB_LIST=`psql -h "$HOSTNAME" -U "$USERNAME" -At -c "$SCHEMA_ONLY_QUERY" postgres`
    fi;
 
    if [ ! $QUIET ]; then
        echo -e "The following databases were matched for schema-only backup:\n${SCHEMA_ONLY_DB_LIST}\n"
    fi
 
    for DATABASE in $SCHEMA_ONLY_DB_LIST; do
        if [ ! $QUIET ]; then
            echo "Schema-only backup of $DATABASE"
        fi
        
        if [ $LOCALONLY ] && ! pg_dump -Fp -s "$DATABASE" | gzip > $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA-$CURRENT_TIMESTAMP.sql.gz.in_progress; then
            echo "[!!ERROR!!] Failed to backup local database schema of $DATABASE" 1>&2
        elif [ ! $LOCALONLY ] && ! pg_dump -Fp -s -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" | gzip > $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA-$CURRENT_TIMESTAMP.sql.gz.in_progress; then
            echo "[!!ERROR!!] Failed to backup database schema of $DATABASE" 1>&2
        else
            mv $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA-$CURRENT_TIMESTAMP.sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE"_SCHEMA-$CURRENT_TIMESTAMP.sql.gz
        fi
    done
 
 
    ###########################
    ###### FULL BACKUPS #######
    ###########################
 
    for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ };    do
        EXCLUDE_SCHEMA_ONLY_CLAUSE="$EXCLUDE_SCHEMA_ONLY_CLAUSE and datname !~ '$SCHEMA_ONLY_DB'"
    done
 
    FULL_BACKUP_QUERY="select datname from pg_database where not datistemplate and datallowconn $EXCLUDE_SCHEMA_ONLY_CLAUSE order by datname;"
 
    if [ ! $QUIET ]; then
        echo -e "\n\nPerforming full backups"
        echo -e "--------------------------------------------\n"
    fi
 
    if [ $LOCALONLY ]; then
        DATABASES=`psql -At -c "$FULL_BACKUP_QUERY" postgres`
    else
        DATABASES=`psql -h "$HOSTNAME" -U "$USERNAME" -At -c "$FULL_BACKUP_QUERY" postgres`
    fi

    for DATABASE in $DATABASES; do
        if [ $ENABLE_PLAIN_BACKUPS = "yes" ]; then
            if [ ! $QUIET ]; then
                echo "Plain backup of $DATABASE"
            fi;
 
            if [ $LOCALONLY ] && ! pg_dump -Fp "$DATABASE" | gzip > $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.sql.gz.in_progress; then
                echo "[!!ERROR!!] Failed to produce local plain backup database $DATABASE" 1>&2
            elif [ ! $LOCALONLY ] && ! pg_dump -Fp -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" | gzip > $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.sql.gz.in_progress; then
                echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
            else
                mv $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.sql.gz
            fi;
        fi;
 
        if [ $ENABLE_CUSTOM_BACKUPS = "yes" ]; then
            if [ ! $QUIET ]; then
                echo "Custom backup of $DATABASE"
            fi
 
            if [ $LOCALONLY ] && ! pg_dump -Fc "$DATABASE" -f $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.custom.in_progress; then
                echo "[!!ERROR!!] Failed to produce local custom backup database $DATABASE"
            elif [ ! $LOCALONLY ] && ! pg_dump -Fc -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" -f $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.custom.in_progress; then
                echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE"
            else
                mv $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.custom.in_progress $FINAL_BACKUP_DIR"$DATABASE"-$CURRENT_TIMESTAMP.custom
            fi
        fi
    done
 
    if [ ! $QUIET ]; then
        echo -e "\nAll database backups complete!"
    fi
}
 
# MONTHLY BACKUPS
 
DAY_OF_MONTH=`date +%d`
 
if [ $DAY_OF_MONTH -eq 1 ]; then
    # Delete all expired monthly directories
    find $BACKUP_DIR -maxdepth 1 -name "*-monthly" -exec rm -rf '{}' ';'
 
    perform_backups "-monthly"
 
    exit 0;
fi
 
# WEEKLY BACKUPS
 
DAY_OF_WEEK=`date +%u` #1-7 (Monday-Sunday)
EXPIRED_DAYS=`expr $((($WEEKS_TO_KEEP * 7) + 1))`
 
if [ $DAY_OF_WEEK = $DAY_OF_WEEK_TO_KEEP ]; then
    # Delete all expired weekly directories
    find $BACKUP_DIR -maxdepth 1 -mtime +$EXPIRED_DAYS -name "*-weekly" -exec rm -rf '{}' ';'
 
    perform_backups "-weekly"
 
    exit 0;
fi
 


HOUR_OF_DAY=`date +%H` #0-24
if [ $HOUR_OF_DAY = $HOUR_OF_DAY_TO_KEEP ] || [ ! $HOURLY ]; then
    # Delete daily backups $DAYS_TO_KEEP days old or more
    find $BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP -name "*-daily" -exec rm -rf '{}' ';'

    perform_backups "-daily"
 
    exit 0;
fi



# HOURLY BACKUPS
 
HOURS_TO_KEEP=`expr $(($HOURS_TO_KEEP * 60))`

# Delete hourly backups $HOURS_TO_KEEP days old or more
find $BACKUP_DIR -maxdepth 1 -mmin +$HOURS_TO_KEEP -name "*-hourly" -exec rm -rf '{}' ';'
 
perform_backups "-hourly"
