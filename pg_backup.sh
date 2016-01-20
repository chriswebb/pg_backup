#!/bin/bash
 
###########################
####### LOAD CONFIG #######
###########################
 
while [ $# -gt 0 ]; do
    case $1 in
        -kHD)
            DEFAULT_HOUR_OF_DAY_TO_KEEP"$2"
            shift 2
            ;;
        -kDW)
            DEFAULT_DAY_OF_WEEK_TO_KEEP="$2"
            shift 2
            ;;
        -kD)
            DEFAULT_DAYS_TO_KEEP="$2"
            shift 2
            ;;
        -kW)
            DEFAULT_WEEKS_TO_KEEP="$2"
            shift 2
            ;;
        -kH)
            DEFAULT_HOURS_TO_KEEP="$2"
            shift 2
            ;;
        -kM)
            DEFAULT_MONTHS_TO_KEEP="$2"
            shift 2
            ;;
        -u)
            DEFAULT_USERNAME="$2"
            shift 2
            ;;
        -h)
            DEFAULT_HOSTNAME="$2"
            shift 2
            ;;
        -o)
            DEFAULT_BACKUP_DIR="$2"
            shift 2
            ;;
        -s)
            DEFAULT_SCHEMA_ONLY_LIST="$2"
            shift 2
            ;;
        -p)
            DEFAULT_ENABLE_PLAIN_BACKUPS="true"
            shift 1
            ;;
        -C)
            DEFAULT_ENABLE_CUSTOM_BACKUPS="true"
            shift 1
            ;;
        -r)
            RECURRING="true"
            shift 1
            ;;
        -R)
            RECURRING="true"
            shift 1
            ;;
        -q)
            QUIET="true"
            shift 1
            ;;
        -d)
            DIRECTORIES="true"
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
 
if [ -r ${CONFIG_FILE_PATH} ] ; then
    source "${CONFIG_FILE_PATH}"
fi 
 
###################################
#### PRE-INITIALISATION CHECKS ####
###################################
 
# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ] ; then
    echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
    exit 1
fi
 
###########################
### INITIALISE DEFAULTS ###
###########################
 
if [ $DEFAULT_HOSTNAME ]; then
    HOSTNAME="$DEFAULT_HOSTNAME"
fi

if [ ! $HOSTNAME ]; then
    LOCALONLY="true"
fi;

if [ $DEFAULT_USERNAME ]; then
    USERNAME="$DEFAULT_USERNAME"
fi

if [ ! $USERNAME ]; then
    USERNAME="postgres"
fi;

if [ $DEFAULT_BACKUP_DIR ]; then
    BACKUP_DIR="$DEFAULT_BACKUP_DIR"
fi

if [ $DEFAULT_SCHEMA_ONLY_LIST ]; then
    SCHEMA_ONLY_LIST="$DEFAULT_SCHEMA_ONLY_LIST"
fi

if [ $DEFAULT_ENABLE_CUSTOM_BACKUPS ]; then
    ENABLE_CUSTOM_BACKUPS="$DEFAULT_ENABLE_CUSTOM_BACKUPS"
fi

if [ $DEFAULT_ENABLE_PLAIN_BACKUPS ]; then
    ENABLE_PLAIN_BACKUPS="$DEFAULT_ENABLE_PLAIN_BACKUPS"
fi

if [ $DEFAULT_DAY_OF_WEEK_TO_KEEP ]; then
    DAY_OF_WEEK_TO_KEEP="$DEFAULT_DAY_OF_WEEK_TO_KEEP"
fi

if [ $DEFAULT_DAYS_TO_KEEP ]; then
    DAYS_TO_KEEP="$DEFAULT_DAYS_TO_KEEP"
fi

if [ $DEFAULT_WEEKS_TO_KEEP ]; then
    WEEKS_TO_KEEP="$DEFAULT_WEEKS_TO_KEEP"
fi

if [ $DEFAULT_MONTHS_TO_KEEP ]; then
    MONTHS_TO_KEEP="$DEFAULT_MONTHS_TO_KEEP"
fi

if [ $DEFAULT_HOUR_OF_DAY_TO_KEEP ]; then
    HOUR_OF_DAY_TO_KEEP="$DEFAULT_HOUR_OF_DAY_TO_KEEP"
fi

if [ $DEFAULT_HOURS_TO_KEEP ]; then
    HOURS_TO_KEEP="$DEFAULT_HOURS_TO_KEEP"
fi

###################################
#### PRE-BACKUP CHECKS ####
###################################
 
 
# Check Required Variables

if [ $RECURRING ]; then
    if [ ! $DAY_OF_WEEK_TO_KEEP ]; then
        ${ECHO} "The day of week to keep is not defined." 1>&2
        exit 1;        
    elif [ $DAY_OF_WEEK_TO_KEEP -gt 7 ] || [ $DAY_OF_WEEK_TO_KEEP -lt 1 ]; then
        ${ECHO} "The day of week to keep \"$DAY_OF_WEEK_TO_KEEP\" is not valid value.  It must be from 1 to 7." 1>&2
        exit 1;        
    fi

    if [ ! $DAYS_TO_KEEP ]; then
        ${ECHO} "Number of days to keep is not defined." 1>&2
        exit 1;        
    fi

    if [ ! $WEEKS_TO_KEEP ]; then
        ${ECHO} "Number of weeks to keep is not defined." 1>&2
        exit 1;        
    fi
    
    if [ ! $MONTHS_TO_KEEP ]; then
        ${ECHO} "Number of months to keep is not defined." 1>&2
        exit 1;        
    fi

    if [ $HOURLY ]; then
        if [ ! $HOURS_TO_KEEP ]; then
            ${ECHO} "Number of hours to keep is not defined." 1>&2
            exit 1;        
        fi
        
        if [ ! $HOUR_OF_DAY_TO_KEEP ]; then
            ${ECHO} "The hour of day to keep is not defined." 1>&2
            exit 1;            
        elif [ $HOUR_OF_DAY_TO_KEEP -gt 23 ] || [ $HOUR_OF_DAY_TO_KEEP -lt 0 ]; then
            ${ECHO} "The hour of day to keep \"$HOUR_OF_DAY_TO_KEEP\" is not valid value.  It must be from 0 to 23." 1>&2
            exit 1;        
        fi
    fi 
fi
 
###########################
#### START THE BACKUPS ####
###########################
 
function perform_backups()
{
    SUFFIX=$1
    
    if [ $HOURLY ]; then
        DATE_TO_ADD=`date +\%Y-\%m-\%d_\%H-\%M-\%S`
    else
        DATE_TO_ADD=`date +\%Y-\%m-\%d`
    fi
    
    if [ ! $DIRECTORIES ] || [ ! $RECURRING ]; then
        if [ $RECURRING ]; then
            SUFFIX="-$SUFFIX"
        fi
        FINAL_BACKUP_DIR="$BACKUP_DIR$DATE_TO_ADD$SUFFIX/"    
    else
        FINAL_BACKUP_DIR="$BACKUP_DIR$SUFFIX/$DATE_TO_ADD/"    
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

if [ ! $RECURRING ]; then
    perform_backups ""
    exit 0;
fi
 
# MONTHLY BACKUPS
 
DAY_OF_MONTH=`date +%d`
EXPIRED_DAYS=`expr $((($MONTHS_TO_KEEP * 30) + 1))`
 
if [ $DAY_OF_MONTH -eq 1 ]; then

    # Delete weekly directories $WEEKS_TO_KEEP days old or more    
    if [ $DIRECTORIES ]; then
        if [ -d $BACKUP_DIR"monthly" ]; then
            find $BACKUP_DIR"monthly" -maxdepth 1 -mtime +$EXPIRED_DAYS -exec rm -rf '{}' ';'
        fi
    else
        find $BACKUP_DIR -maxdepth 1 -mtime +$EXPIRED_DAYS -name "*-monthly" -exec rm -rf '{}' ';'
    fi
 
    perform_backups "monthly" 
    if [ ! $DIRECTORIES ]; then
        exit 0;
    fi
fi
 
# WEEKLY BACKUPS
 
DAY_OF_WEEK=`date +%u` #1-7 (Monday-Sunday)
EXPIRED_DAYS=`expr $((($WEEKS_TO_KEEP * 7) + 1))`
 
if [ $DAY_OF_WEEK = $DAY_OF_WEEK_TO_KEEP ]; then

    # Delete weekly directories $WEEKS_TO_KEEP days old or more
    if [ $DIRECTORIES ]; then
        if [ -d $BACKUP_DIR"weekly" ]; then
            find $BACKUP_DIR"weekly" -maxdepth 1 -mtime +$EXPIRED_DAYS -exec rm -rf '{}' ';'
        fi
    else
        find $BACKUP_DIR -maxdepth 1 -mtime +$EXPIRED_DAYS -name "*-weekly" -exec rm -rf '{}' ';'
    fi
    
    perform_backups "weekly"     
    if [ ! $DIRECTORIES ]; then
        exit 0;
    fi
fi

# DAILY BACKUPS
 
HOUR_OF_DAY=`date +%-H` #0-24
if [ $HOUR_OF_DAY = $HOUR_OF_DAY_TO_KEEP ] || [ ! $HOURLY ]; then

    # Delete daily backups $DAYS_TO_KEEP days old or more
    if [ $DIRECTORIES ]; then
        if [ -d $BACKUP_DIR"daily" ]; then
            find $BACKUP_DIR"daily" -maxdepth 1 -mtime +$DAYS_TO_KEEP -exec rm -rf '{}' ';'
        fi
    else
        find $BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP -name "*-daily" -exec rm -rf '{}' ';'
    fi

    perform_backups "daily" 
    if [ ! $DIRECTORIES ]; then
        exit 0;
    fi
fi

# HOURLY BACKUPS
 
HOURS_TO_KEEP=`expr $(($HOURS_TO_KEEP * 60))`

# Delete hourly backups $HOURS_TO_KEEP hours old or more
if [ $DIRECTORIES ]; then
    if [ -d $BACKUP_DIR"hourly" ]; then
        find $BACKUP_DIR"hourly" -maxdepth 1 -mmin +$HOURS_TO_KEEP -exec rm -rf '{}' ';'
    fi
else
    find $BACKUP_DIR -maxdepth 1 -mmin +$HOURS_TO_KEEP -name "*-hourly" -exec rm -rf '{}' ';'
fi
 
perform_backups "hourly"
exit 0;