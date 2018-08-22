#!/bin/bash
#
# apiscript.sh v1.1
# Генерация .md с описанием вызовов методов API по сценарию
# Source: https://github.com/LeKovr/apitools
# Copyright (c) 2017 Alexey Kovrizhkin ak@elfire.ru
#
# Use:
# 
# bash apiscript.sh samples.sc > samples.md
#

# -------------------------------------------------------------------------------

SCRIPT=$1
shift

[[ "$SCRIPT" ]] || {
  echo "usage: $0 <script>"
  exit
}

# Суффикс добавляется к алиасам пользователей и компаний для уникальности
KEY=$1
[[ "$KEY" ]] || KEY=""

CONFIG=${CONFIG:-.config}

# TOKEN берем из БД: select * from wsd.auth_token;
#TOKEN=55d79928-911a-4d4e-a6f3-4e2a377fcbba

# хост сервера АПИ
#APP_SITE="30502.zen.lan"

. $CONFIG

# Непустое значение включает отладочный вывод
DEBUG=""
# Непустое значение включает вывод даты
DATETIME=""

# Непустое значение включает вывод токена
TKN=""

# -------------------------------------------------------------------------------

declare -A DATA
API=http://$APP_SITE/rpc
CTYPE="Content-type: application/json"

# -------------------------------------------------------------------------------

. $SCRIPT

# -------------------------------------------------------------------------------

toc() {
  local new_key=$1
  shift
  if [[ "$new_key" == "=" ]] ; then
    local code=$1
    shift
    echo "* $start. [$code](#${start}-$code) $@"
    (( start++ ))

  fi
}

# -------------------------------------------------------------------------------

parse_token() {
  local key=$1

  # trim suffix
  local t12=${key%.*}

  # trim prefix
  local t2=${t12#*.}

  [[ "$t2" == "null" ]] && {
    >&2 echo "Error: empty token"
    exit
  }
  # TODO: base64 writes to STDERR
  if [[ "$DATETIME" ]] ; then
    echo -n "$t2" | base64 --d 2>/dev/null | jq -S '.exp = 0'
  else
    echo -n "$t2" | base64 --d 2>/dev/null | sed  's/\(".\{10\}T.\{14\}"\)/"2006-01-02T15:04:05+00:00"/g' | jq -S '.exp = 0'
  fi
}

# -------------------------------------------------------------------------------

process() {
  local new_key=$1
  shift
  local use_key=$1
  shift

  if [[ "$new_key" == "=" ]] ; then
    # заголовок
    echo -e "\n## $start. $use_key\n\n$@\n"
    (( start++ ))
    return
  elif [[ "$new_key" == "." ]] ; then
    # вывести текст без изменений
    echo $use_key $@
    return
  elif [[ "$new_key" == ".sleep" ]] ; then
    # сделать паузу
    >&2 echo "sleep $use_key"
    sleep $use_key
    return
  fi

  local method=$1
  shift
  local args=$@

  # парсим первый аргyмент команды
  # формат: XX{;XX}, где XX может иметь видa
  # AA - из хэша результата поле .token поместить в переменную AA
  # +AA - в строке аргументов заменить строку =AA= на значение переменной AA
  # AA=BB - из массива результата взять  первый хэш и из него поле .BB поместить в переменную AA
  # hide - не показывать результат вызова метода

  OIFS=$IFS
  IFS=';'
  vars=$new_key
  new_key="-"
  hide_res=""
  for x in $vars
  do
    [[ "$DEBUG" ]] && echo "arg1: $x"
    if [[ "$x" == +* ]] ; then
      # переменная в аргументах
      # trim prefix
      local name=${x#+}
      args="${args/=$name=/${DATA[$name]}}"
      [[ "$DEBUG" ]] && echo ">> $name -> $args"
    elif [[ "$x" == "hide" ]] ; then
      hide_res=1
    else
      new_key=$x
    fi
  done

  IFS=$OIFS

  local auth=""
  if [[ "$use_key" != "-" ]] ; then
    # если задан второй аргумент - использовать значение этой переменной как токен авторизации
    [[ "$DEBUG" ]] && echo ">> Use key: $use_key - ${DATA[$use_key]}"
    auth="-H \"Authorization: Bearer xxxx.xxxx.xxxx\""
    resp=$(curl -sd "$args" -H "Authorization: Bearer ${DATA[$use_key]}" -H "$CTYPE" $API/$method)
  else
    # если не задан - запрос без авторизации
    resp=$(curl -sd "$args" $auth -H "$CTYPE" $API/$method)
  fi

  local args_modif_tkn=""
  if [[ "$TKN" ]] ; then
    args_modif_tkn=$args
  else
    args_modif_tkn=$(echo "$args" | sed 's/\("a_token":".*"\)/"a_token":"abcdefgh-1234-1234-1234-abcdefgh1234"/g')
  fi

cat <<EOF

\`\`\`
CALL=$API/$method
Q='$args_modif_tkn'
curl -gsd "\$Q" -H "Content-type: application/json" $auth \$CALL | jq '.'
\`\`\`
EOF

    [[ "$DEBUG" ]] && echo "$resp"
  if [[ "$DATETIME" ]] ; then
    result=$(echo "$resp" | jq -S '.' || echo "ERROR: $resp")
  else 
    result=$(echo "$resp" | sed  's/\(".\{10\}T.\{14\}"\)/"2006-01-02T15:04:05+00:00"/g' | jq -S '.'  || echo "ERROR: $resp")
  fi
  if [[ "$new_key" == *=* ]] ; then
    # забрать в массив элемент из хэша результата
    # trim suffix
    local dest=${new_key%=*}
    # trim prefix
    local src=${new_key#*=}
    DATA[$dest]=$(echo "$resp" | jq -r ".[] | .$src")
    [[ "$DEBUG" ]] && echo ">> $dest = $src (${DATA[$dest]})"
    new_key="-"
  fi

  if [[ "$new_key" != "-" ]] ; then
    # забрать в массив токен
    DATA[$new_key]=$(echo $resp| jq -r '.token')
    [[ "$DEBUG" ]] && echo ">> Save key: $new_key - ${DATA[$new_key]}"
cat <<EOF
\`\`\`json
{
  "token": "xxxx.xxxx.xxxx"
}
\`\`\`

Token payload:
\`\`\`json
EOF

parse_token ${DATA[$new_key]}

echo "\`\`\`"
elif [[ "$hide_res" == "" ]] ; then
cat <<EOF
\`\`\`json
$result
\`\`\`

EOF

  fi


}
# -------------------------------------------------------------------------------

run() {

  echo -e "\n# $TITLE\n\n"

  local start=1
  while IFS= read -r line ; do
    # Skip comments
    q=${line%%#*} # remove endline comments
    [ -n "${q##+([[:space:]])}" ] || continue # ignore line if contains only spaces

    toc $q
  done <<< "$Q"
  start=1

  while IFS= read -r line ; do
    # Skip comments
    q=${line%%#*} # remove endline comments
    [ -n "${q##+([[:space:]])}" ] || continue # ignore line if contains only spaces

    process $q # >> $OUT
  done <<< "$Q"
D=$(date -R)
cat <<EOF

---

Generated by [apiscript.sh](https://github.com/LeKovr/apitools/blob/master/apiscript.sh)

$D
EOF

}

# -------------------------------------------------------------------------------

run
