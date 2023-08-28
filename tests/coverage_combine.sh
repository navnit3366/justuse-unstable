#!/system/bin/sh


IFS=$'\n';
  cov_dbs=($( find "$( pwd )" -type f -exec file -npsNzF\|  "{}" +  | grep --line-buffered -E 'SQLite ' | grep -vFe "coverage2.db" | cut -d\| -f1 | xargs -d $'\n' md5sum | seen_new -e '$1' -c 'substr($0, length($1)+3)' )); 
IFS=$'\n';
  tables=($( sqlite3 "${cov_dbs[0]}" '.schema' | sed -r -e '
      \~^.*CREATE TABLE[\t ]*([\t ]+IF NOT EXISTS|)[\t ]+(['"'"'"]?)([a-zA-Z0-9_.]+)\2($|[^a-zA-Z0-9_.].*)$~{ s~~\3~p;
  };d'; ));   ntbls=${#tables[@]};
  ndbs=${#cov_dbs[@]};
  dbidx=-1; 
while (( ++dbidx < ndbs )); do
  db="${cov_dbs[dbidx]}"; 
echo "Reading from $db ..." 1>&2; (( dbidx == 0 )) && sqlite3 "$db" '.schema' | sed -r -e '
      s~(^|$|['"'"'"\t\r\n ;])--.*$~\1~;' | tr -s '\t\r\n ' ' ' | tr -s ';' '\n' | grep -Eie 'CREATE TABLE' | trim | add_suffix ';' | tee ./0_0__schema.sql 1>&2;
  tblidx=-1;
  ntbls=${#tables[@]}; 
while (( ++tblidx < ntbls )); do
  tbl="${tables[tblidx]}"; 
echo -E "  - Load data from table $tbl" 1>&2;  { echo -nE "INSERT OR IGNORE INTO $tbl ";
  sqlite3 "${db}" -tabs "select * from $tbl" -separator $'\xf8' -newline $'\f' | sed -r -e '
      s~'"'"'~\xf9~g;   :a s~(\xf8|^)([^\n\xf8]*)($|\xf8)~'"'"'\n    '"'"'\2'"'"',\n    \3~g; ta;
  s~\f~'"'"',\n), (\n    '"'"'~g; ta;
  s~(^|\n +\xf8)([^\n\xf8]+[^'"'"'\\\n\xf8])\n +'"'"'~\n    '"'"'\2'"'"',\n    ~g; ta;
  s~\xf8~'"'"'~g;
  s~, *\([^()a-zA-Z0-9_]*$~;\n~;
  s~^[^\n]*\n~VALUES (\n~;
  s~\xf9~'"'"' + "'"'"'" + '"'"'~g; ' | sed -r -e '\~^ +'"'"'(.*)'"'"' *$~{ N; \~\n +'"'"'~{ s~~,&~;
  }; }; \~^    +'"'"'[\t\r ]*$~{ d; ' -e '    ;
  };  ' | tr -s '\n' '\v' | sed -r -e ':a s~,([\t\n\v\r ]*)(;|$|\))~\1\2~g; ta;' | tr -s '\v' '\n';
  } > "${dbidx}_${tblidx}_${tbl}.sql";  
grep -qFe "VALUES" --text -hs -- "${dbidx}_${tblidx}_${tbl}.sql" || rm -vf -- "${dbidx}_${tblidx}_${tbl}.sql" 1>&2; 
done; 
done;  
rm coverage2.db; 
for f in ./0_*.sql ./[1-9]*.sql; do
  [ -f "$f" ] || continue
  fn="${f##*/}";
  nme="${fn%.*}";
  tbl="${nme##*[0-9]_}";
  sqlite3 coverage2.db -init "$f" "; VACUUM; REINDEX;"; 
  echo "[ $? ] $f"; 
done
sqlite3 coverage2.db "VACUUM;
  DELETE FROM coverage_schema; 
insert into coverage_schema VALUES (7); VACUUM; REINDEX; "
cat coverage2.db > .coverage

