#
# скрипт для проверки скорости ответа серверов
#
# Пример вызова:
#
#    bash bench.sh 3 "грушевый сок"
#
# ------------------------------------------------------------------------------

# номер страницы
# повторный запуск с тем же значением отработает из кеша
OFF=$1
shift

# фраза для поиска
TEXT=$1

[[ "$OFF" ]] || OFF="0"
# ------------------------------------------------------------------------------
tm() {
  local name=$1
  shift
  echo -n "  $name" >&2
  printf '%*.*s' 0 $((25 - ${#name})) ".........................." >&2
  /usr/bin/time -f " %e" "$@"
}

# ------------------------------------------------------------------------------
call() {
  local h=$1
  local u=$2
  local id=$3
  local name=$4
  local q="$5"
  echo "$name ($q)" >  bench${id}_${h}.dat
  tm $name curl -gsd "$q" -H "Content-type: application/json" $u/$name >> bench${id}_${h}.dat
}

# ------------------------------------------------------------------------------
test() {
  local h=$1
  local u=$2
  echo "$h..."

  Q='{"a_q":"'$TEXT'","a_cat":"","a_area":"area.ru","off":'"$OFF}"
  call $h $u 1 ru_search2 "$Q"

  Q='{"a_q":"'$TEXT'","a_cat":"","a_area":"","off":'"$OFF}"
  call $h $u 2 ru_search2_stat "$Q"

  # категорий текущего уровня мало, поэтому уменьшим размер страницы
  Q='{"a_q":"'$TEXT'","a_cat":"","a_area":"area.ru","lim":1,"off":'"$OFF}"
  call $h $u 3 ru_search2_facet_area "$Q"

  # тут считаем кол-во, результат - одно число, смещения по страницам нет
  Q='{"a_q":"'$TEXT'","a_cat":"","a_area":"area.ru"}'
  call $h $u 4 ru_search2_count "$Q"

}

# ------------------------------------------------------------------------------

test master http://api.iac.it.tender.pro/rpc

test iac http://iac.tender.pro/rpc

#test tp1 http://tp1.jast.ru/rpc
