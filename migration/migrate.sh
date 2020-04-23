#!/bin/bash
cwd=$(pwd)
cd "$(dirname "$0")"

# init source and target db properties
source migrate.properties

# init common variables
m=migrate
i=init
#f=force
d=db-use
g=git
lh=last-hash
lc=comment-by-last-hash
c=comment-by-hash

killAllSessions="select count(*) from (select pg_terminate_backend(pid) as status from pg_stat_activity where pid in (select pid from pg_stat_activity where pid != pg_backend_pid() and datname = '"$trg_dbname"')) t where status;"
sql="select max(version)::int + 1 from flyway_schema_history;"

# git commands
git_get_hash="git rev-parse HEAD"

# define name of dir/file
errorlog=$tmpdir/errors.log
path_changed_sql=$tmpdir/changed.sql
dump_source_file=$tmpdir/dump_db_source.ddl
dump_init_file=$sqldir/init.sql
dump_target_file=$tmpdir/dump_db_target.ddl
flyway_folder=$sqldir
dump_init_file=$flyway_folder/init.sql

# ---  FUNCTIONS DEFINE  --------------------------

function clearDependsFolder() {
   if [ ! -d "$tmpdir" ]; then # if dir not exists then...
      mkdir $tmpdir
      echo "make folder "$tmpdir"..."
   else
      echo "clear "$tmpdir"..."
      rm -f $tmpdir/*
   fi

   if [ ! -d "$sqldir" ]; then
      mkdir $sqldir
      echo "make folder "$sqldir"..."
   else 
      rm -f $sqldir/*
      echo "clear "$sqldir"..."
   fi
}

# ---

function executeFlyway() {
#-configFiles=conf/flyway.conf
result=`flyway -baselineOnMigrate=true -url=jdbc:postgresql://$trg_host:$trg_port/$trg_dbname -user=$trg_username -password=$trg_password -locations=filesystem:"$sqldir" -outputFile="$tmpdir"/flyway.log migrate 2> "$errorlog"`
if [[ 0 -ne $? ]]; then  # catch any errors
    echo "Something went wrong; error log follows:"
    cat "$errorlog"
    exit 1
else
    echo "$result"
fi
}

function executeSQL_TRG_DB() {
    result=`psql -XA -h $trg_host -p $trg_port -U $trg_username -d $1 -t -c "$2" 2>"$3"`
    if [[ 0 -ne $? ]]; then
       echo "Something went wrong; error log follows:"
       cat "$errorlog"
       exit 1
    fi
    echo  "$result"
}

function executeSQL_init_trg_db() {
    result=`psql -h $trg_host -p $trg_port -U $trg_username -d $trg_dbdefault -f $1 2> $2`
    if [[ 0 -ne $? ]]; then
       echo "Something went wrong; error log follows:"
       cat "$errorlog"
       exit 1
    fi
    echo  "$result"
}

function makeDiff() {
   result=`java -jar $diff_pgdb $diff_pgdb_arg_exclude_tables $diff_pgdb_exclude_tables $diff_pgdb_create_file_storage_functions $diff_pgdb_default_path_storage --ignore-start-with --drop-if-exists $1 $2 > $3 2> $4`
   if [[ 0 -ne $? ]]; then
       echo "Something went wrong; error log follows:"
       cat "$errorlog"
       exit 1
    fi
    echo  "$result"
}

function pullDump() {
   result=`pg_dump  -sOC -f $1 -h $2 -p $3 -U $4 -d $5 --no-acl --schema-only 2> $6`
   if [[ 0 -ne $? ]]; then
       echo "Something went wrong; error log follows:"
       cat "$errorlog"
       exit 1
   else
       echo "$result"
   fi
}

function gitGetLastHashCommit() {
   local hashCommit=$($git_get_hash)
   if [[ 0 -ne $? ]]; then
       echo "Something went wrong; error log follows:"
       exit 1
   else
       echo "$hashCommit"
   fi
}

function gitGetCommentByHashCommit() {
   local comment=`git log $1 -n 1`
   if [[ 0 -ne $? ]]; then
       echo "Something went wrong; error log follows:"
       exit 1
   else
       echo "$comment"
   fi
}

# ----------------------------------------------

# check parameters
pass_params=0
if [ $# -eq 0 ]; then
  echo "ERROR: empty parameters"
  pass_params=-1
elif [ "$1" == "$g" ]; then
  if [ "$2" == "$lh" ] || [ "$2" == "$lc" ]; then
     pass_params=1
  elif [ "$2" == "$c" ]; then 
     if [ -n "$3" ]; then
        pass_params=1
     else
        echo "ERROR: for "$g" parameter can use "$c" and third parameter must be a hash like a \"c4d2635e67c41j77c23787bdc934e3e03c642d8c\""
        pass_params=-1 
     fi
  else
     echo "ERROR: together with parameter "$g" can use only \""$lh"\" or \""$lc"\" paramteres"
     pass_params=-1
  fi
elif [ "$1" != "$i" ] && [ "$1" != "$m" ]; then 
  echo "ERROR: paramter "$1" is unknown"
  pass_params=-1
elif [ "$1" == "$i" ] && [ -z "$2" ] || [ "$1" == "$m" ] && [ -z "$2" ]; then
  pass_params=1
elif [ -z "$2" ] && [ "$2" != "$d" ]; then
  echo "ERROR: second parameter "$2" is unknown or must be defined"
  pass_params=-1
else 
  pass_params=1
fi

if [ "$pass_params" != 1 ]; then
#echo -e "\n"
echo -e "\e[1mHOW TO USAGE:\e[0m"
echo -e "\e[1mNAME\e[0m"
echo -e "migrate.sh - for migrate db"
echo -e "\e[1mSYNOPSIS\e[0m"
echo -e "migrate.sh [COMMAND] [OPTION] [ARGUMENTS]"
echo -e "\e[1mDESCRIPTION COMMADS\e[0m"
echo -e ""$i" - pull dump of source db to local file"
echo -e ""$i" "$d" - pull dump of source db to local file then drop target db then apply dump to target db"
echo -e ""$m" - create alter script"
echo -e ""$m" "$d" - create alter script based on diff of source and target db"
echo -e ""$m" pathFile - to try to apply of alter script to target db"
echo -e ""$g" "$lh" - get last short hash from git repo"
echo -e ""$g" "$lc" - get last comment by last hash from git repo"
echo -e ""$g" "$c" c4d2635e67c41j77c23787bdc934e3e03c642d8c - get comment by hash from git repo"
exit 1
fi

START_DATE="$(date '+%Y-%m-%d %H:%M:%S')";
start_time="$(date -u +%s)"
echo "start at "$START_DATE""

while [[ $# -gt 0 ]] ;
do
    opt="$1";
    shift;              #expose next argument
    case "$opt" in
        ""$i"" )
	   COMMAND="$opt"
       OPT=`echo $1 | awk '{print tolower($0)}'` # to lower case
	   break;;
	""$m"" )
	   COMMAND="$opt"
	   OPT=$1
 	   break;;
    ""$g"" )
       COMMAND="$opt"
       OPT=$1
       arg3=$2
       break;;
    *) echo >&2 "Invalid option: $@"; exit 1;;
   esac
done

# -----------------------------------------------

# INIT DB
if [ "$COMMAND" == "$i" ]; then

echo "$i..."

# clear temp and sql folder
clearDependsFolder

# get dump source db
echo "get dump..."
result=$(pullDump $dump_target_file $src_host $src_port $src_username $src_dbname $errorlog)
echo "dumped: "$result""

# for ddl script change by hands of developer
if [ ! -f "$path_changed_sql" ]; then
    cp $dump_target_file $path_changed_sql
    echo "copied dump to "$path_changed_sql" for ddl script change by hands of developer"
fi

mv $dump_target_file $dump_init_file
echo "moved dump to "$dump_init_file""

if [ "$OPT" == "$d" ]; then

  echo "kill all sessions of target db "$trg_dbname"..."
  _count=$(executeSQL_TRG_DB $trg_dbname "$killAllSessions" "$errorlog")
  echo "killed was "$_count""

  echo "drop tagret db if exists..."
  result=$(executeSQL_TRG_DB $trg_dbdefault "DROP DATABASE IF EXISTS \""$trg_dbname"\";" "$errorlog")
  echo "database was dropped "$result""

  echo "init target db..."
  result=$(executeSQL_init_trg_db $dump_init_file "$errorlog")
  echo "target db was initialized successfully"
fi

echo "inited success"

fi

# -----------------------------------------------

# MIGRATE DB
if [ "$COMMAND" == "$m" ]; then

  echo "migrate..."

  if [ -z "$OPT" ]; then #  diff make by hands of developer

     if [ ! -f "$path_changed_sql" ]; then # if not exists file
        echo "use "$i" command before executing "$m" command"
        exit 1
     fi

     lastHash="$flyway_default_artifact_name"

     #echo "get next number version at flyway"
     #ver=$(executeSQL_TRG_DB $trg_dbname "$sql" "$errorlog")
     #diff_file=$flyway_folder/V$ver$lastHash$flyway_ext
     diff_file=$flyway_folder/"$lastHash""$flyway_ext"

     echo "prepare diff file "$diff_file
     result=$(makeDiff $dump_init_file $path_changed_sql $diff_file $errorlog)
     echo "created diff "$diff_file" successfully "$result""

  elif [ "$OPT" == "$d"  ]; then # make diff ddl script use target and source db only

     echo "db make diff"
     # get dump source db
     echo "get dump source db..."
     result=$(pullDump $dump_source_file $src_host $src_port $src_username $src_dbname $errorlog)
     echo "dumped source: "$result""

     # get dump source db
     echo "get dump target db..."
     result=$(pullDump $dump_target_file $trg_host $trg_port $trg_username $trg_dbname $errorlog)
     echo "dumped target: "$result""

     lastHash="$flyway_default_artifact_name"

     diff_file=$flyway_folder/"$lastHash""$flyway_ext"

     echo "prepare diff file "$diff_file
     result=$(makeDiff $dump_source_file $dump_target_file $diff_file $errorlog)
     echo "created diff "$diff_file" successfully "$result""

  else # just have to rename ddl script file, replace name to hash last commit of git
     echo "apply alter script "$OPT"..."

     # try get hash last commit
     lastHash=$(gitGetLastHashCommit)
     if [ -z "$lastHash" ]; then
        lastHash="__"$flyway_default_artifact_name
     else 
        lastHash="__"$lastHash
     fi
     
     # init if not exists flyway_table
     echo "execute flyway..."
     result=$(executeFlyway)

     echo "get next number version from table flyway of target db"
     ver=$(executeSQL_TRG_DB $trg_dbname "$sql" "$errorlog")
     diff_file=$flyway_folder/V$ver$lastHash$flyway_ext

     cp $OPT $diff_file
     if [[ 0 -ne $? ]]; then
       echo "Something went wrong; error log follows:"
       exit 1
     fi

     echo "execute flyway..."
     result=$(executeFlyway)
     echo "$result"
  fi

fi

# git command
if [ "$COMMAND" == "$g" ];then

  if [ "$OPT" == "$lh" ]; then
     echo "last hash: $(gitGetLastHashCommit)"
  elif [ "$OPT" == "$lc" ]; then
     echo "last comment: $(gitGetLastHashCommit) | $(gitGetCommentByHashCommit)"
  elif [ "$OPT" == "$c" ]; then
     comment=$(gitGetCommentByHashCommit $arg3)
     echo "comment by hash: $comment"
  fi

fi

END_DATE="$(date '+%Y-%m-%d %H:%M:%S')";
end_time="$(date -u +%s)"

echo "end at "$END_DATE""

elapsed="$(($end_time-$start_time))"
echo "Total of $elapsed seconds elapsed for process"
