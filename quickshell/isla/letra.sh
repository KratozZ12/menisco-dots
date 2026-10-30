#!/bin/sh
# Busca la letra sincronizada de una cancion y escribe {"syncedLyrics": "..."} (nada si no hay).
# Uso: letra.sh TITULO ARTISTA DURACION_EN_SEGUNDOS [NETEASE: 1 | 0]
# Fuentes, en orden: LRCLIB y NetEase (si no se apago). Publicas, sin cuenta ni clave.
t=$1 a=$2 d=${3:-0} netease=${4:-1}

# jq: de una lista con "duration" en segundos, la mas cercana a $d (si se sabe la duracion,
# solo se aceptan las que difieren menos de 15 s, para no tomar versiones en vivo o remezclas)
cerca='map(select($d <= 0 or ((.dur - $d) | fabs) <= 15)) | min_by(((.dur - $d) | fabs))'

r=$(curl -sfG --max-time 6 'https://lrclib.net/api/search' \
        --data-urlencode "track_name=$t" --data-urlencode "artist_name=$a" |
    jq -c --argjson d "$d" "[.[] | select(.syncedLyrics != null and .duration != null) | . + {dur: .duration}] | $cerca // empty")
[ -n "$r" ] && { echo "$r"; exit; }
[ "$netease" = 1 ] || exit 0

B=https://music.163.com
id=$(curl -sfG --max-time 6 "$B/api/search/get" --data-urlencode "s=$t $a" -d type=1 -d limit=8 \
        -H "Referer: $B" -A "Mozilla/5.0" |
    jq -r --arg t "$t" --argjson d "$d" '
        def n: ascii_downcase | gsub("[\\p{P}\\p{S}\\p{Z}]"; "");
        (($t | n)) as $y |
        [.result.songs[]? | . + {dur: (.duration / 1000)} | (.name | n) as $x
            | select($x != "" and ($x == $y or ($y | contains($x)) or ($x | contains($y))))]
        | '"$cerca"' | .id // empty')
[ -n "$id" ] || exit 0
curl -sfG --max-time 6 "$B/api/song/lyric" -d "id=$id" -d lv=1 -H "Referer: $B" -A "Mozilla/5.0" |
    jq -c '{syncedLyrics: (.lrc.lyric // "")}'
