#!/bin/bash
#
# doc_gen.sh v1.2
# Генерация .md с описанием методов заданной схемы
# Оригинальная версия файла: https://github.com/LeKovr/dbrpc/blob/master/doc_gen.sh
# (c) 2016 Tender.Pro, Алексей Коврижкин, jean@tender.pro
#
# Use:
# -- local docs
# bash doc_gen.sh  > doc_sample.md
#
# -- local docs with query echo
# DEBUG=1 bash doc_gen.sh  > doc_sample.md
#
# -- docs for demo api
# APP_SITE=api.iac.it.tender.pro bash doc_gen.sh > API_upd.md
#
# TODO:
# * [ ] Если в описании результата имя поля = '-', заменять на имя функции

# Filter index by nsp
NSP=$1

[[ "$APP_SITE" ]] || . .config

# name for docs
H=http://$APP_SITE

# name for calls
[[ "$RPC_URL" ]] || RPC_URL=rpc
HOST=$H/$RPC_URL

# prefix added to argument names
AP="a_"
#AP=""

toc() {
  local mtd=$1
  def=$(echo $data | jq -r ".result | .[] | select(.code==\"$mtd\")") # "
  anno=$(echo $def | jq -r .anno)

  echo "* [$mtd](#$mtd) - $anno"
}

describe() {
  local mtd=$1
  echo "Describe method $mtd..." >&2

  def=$(echo $data | jq -r ".result | .[] | select(.code==\"$mtd\")") # "
  anno=$(echo $def | jq -r .anno)
  exam=$(echo $def | jq -r .sample)
cat <<EOF

## $mtd

$anno

### Аргументы

Имя | Тип | По умолчанию | Обязателен | Описание
----|-----|--------------|------------|---------
EOF
  local hdr
  local cmd="curl -gs $HOST/func_args?${AP}code=$mtd"
  local data=$($cmd)
  [[ $DEBUG ]] && echo $cmd >&2 && echo $data >&2
  while read a ; do
    echo $a
  done < <(echo $data | jq -r '.result | .[] | " \(.arg) | \(.type) | \(.["def_val"] //= "" | .["def_val"]) | \(.["required"]) | \(.anno)"')
cat <<EOF

### Результат

Имя | Тип | Описание
----|-----|---------
EOF

  cmd="curl -gs $HOST/func_result?${AP}code=$mtd"
  data=$($cmd)
  [[ $DEBUG ]] && echo $cmd >&2 && echo $data >&2
  while read a ; do
    echo $a
  done < <(echo $data | jq -r '.result | .[] | select(.arg != null) | " \(.arg) | \(.type) | \(.anno) "')

  local result
  if [[ "$exam" != "null" ]] ; then


cat <<EOF

### Пример вызова

\`\`\`
H=$H/$RPC_URL
Q='$exam'
curl -gsd "\$Q" -H "Content-type: application/json" \$H/$mtd | jq '.[0:2]'
EOF
    result=$(curl -gsd "$exam" -H "Content-type: application/json" $HOST/$mtd | jq '.[0:2]')
cat <<EOF
\`\`\`
\`\`\`json
$result
\`\`\`

EOF
  fi
}

cat <<EOF

# Методы API $NSP

EOF

echo "Working with $HOST..." >&2

cmd="curl -gs $HOST/index"
[[ "$NSP" ]] && cmd=${cmd}?a_nsp=$NSP

data=$($cmd)
[[ $DEBUG ]] && echo $cmd >&2 && echo $data >&2

while read a ; do
  toc $a
done < <(echo $data | jq -r '.result | .[] | .code')

while read a ; do
  describe $a
done < <(echo $data | jq -r '.result | .[] | .code')

D=$(date -R)
cat <<EOF

---

Generated by [doc_gen.sh](https://github.com/LeKovr/apitools/blob/master/doc_gen.sh)

$D
EOF