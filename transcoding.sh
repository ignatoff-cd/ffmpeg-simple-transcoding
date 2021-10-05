#!/usr/local/bin/bash

input_file=$1

for i in "$@"; do
  case $i in
  -h | --help)
    echo "usage: ffmpeg_transcode.sh FILENAME_PATH  --bitrate=BITRATE_INT --scale=HEIGHT_INT:WIDTH_INT --output=RESULT_FILENAME_PATH"
    exit
    shift
    ;;
  --bitrate=*)
    VBRATE="${i#*=}"
    shift
    ;;
  --scale=*)
    VSCALE="${i#*=}"
    shift
    ;;
  --output=*)
    RESULT_FILENAME_PATH="${i#*=}"
    shift
    ;;
  --debug)
    DEBUG=1
    shift
    ;;
  esac
done

if test ! -f "${input_file}"; then
  echo "ERROR. Bad input file path"
  exit
fi

ffmpeg=$(which ffmpeg)
ffprobe=$(which ffprobe)
VCODEC="libx264"
ABRATE="128k"
ASAMPLING="48k"
TEMP_DIR=$(mktemp -d /tmp/ffmpeg.XXXXXXXXX)
LOGFILE="${TEMP_DIR}/pass-log-file"
TMPFILE="${TEMP_DIR}/ffmpeg-pass-1"
TMP_SILENCE_FILE="${TEMP_DIR}/ffmpeg-silence"
TMP_CHECK_AUDIO="${TEMP_DIR}/ffmpeg-check-audio"
TMP_PROBE_ERROR="${TEMP_DIR}/ffmpeg-probe-error"
LOUDNORM="-af loudnorm=I=-16:TP=-1:LRA=13"
LOUDNORM_PARAMS=":print_format=json"
LOUDNORM_OFF=0

if [[ ! ${VBRATE} ]]; then
  echo 'ERROR. undefined --bitrate opt'
  exit
fi
if [[ ! ${VSCALE} ]]; then
  echo 'ERROR. undefined --scale opt'
  exit
fi
if [[ ! ${RESULT_FILENAME_PATH} ]]; then
  echo 'ERROR. undefined --output opt'
  exit
fi

# get probe error and exit if exists
$ffprobe ${input_file} -loglevel 24 2>${TMP_PROBE_ERROR}
probe_errors=$(wc -l "${TMP_PROBE_ERROR}" | awk '{print $1}')
if [[ ${probe_errors} -gt 0 ]]; then
  echo -en "ERROR: " && cat "${TMP_PROBE_ERROR}"
  exit
fi

# get file info
finfo=$($ffprobe -v error -select_streams v:0 -show_entries format=bit_rate,duration -show_entries stream=width,height -of default=noprint_wrappers=1 ${input_file} | tr -s '\n' ',')
width=$(echo $finfo | cut -f1 -d ',' | cut -f2 -d'=')
height=$(echo $finfo | cut -f2 -d ',' | cut -f2 -d'=')
bitrate=$(echo $finfo | cut -f4 -d ',' | cut -f2 -d'=')
duration=$(echo $finfo | cut -f3 -d ',' | cut -f2 -d'=')
size=$(du -h ${input_file} | cut -f1)

if [[ ${DEBUG} -eq 1 ]]; then
  yes "*" | head -n 80 | tr -d '\n'
  echo
  echo "INPUT fileinfo: scale=${width}x${height}, bitrate=$((bitrate / 1000))kb/s, duration: ${duration%.*}sec, size: ${size}"
  yes "*" | head -n 80 | tr -d '\n'
  echo
fi

# check audio stream is exists OR soundless audio stream
$ffprobe -i ${input_file} -show_streams -select_streams a -loglevel error >"${TMP_CHECK_AUDIO}"
a_lines=$(wc -l "${TMP_CHECK_AUDIO}" | awk '{print $1}')
if [[ $a_lines -eq 0 ]]; then
  LOUDNORM_OFF=1
  LOUDNORM=
  LOUDNORM_PARAMS=
  if [[ ${DEBUG} -eq 1 ]]; then echo "DEBUG. LOUDNORM OFF"; fi
else
# detect silence
  $ffmpeg -i ${input_file} -af silencedetect=noise=0.0001 -f null /dev/null 2>"${TMP_SILENCE_FILE}"
  silence_duration=$(cat ${TMP_SILENCE_FILE} | grep silence_duration | cut -f2 -d'|' | cut -f2 -d':' | tr -d ' ')
  int_duration=$(echo "$duration" | awk '{printf "%.0f", $1}')
  int_silence_duration=$(echo "$silence_duration" | awk '{printf "%.0f", $1}')
  if [[ ${DEBUG} -eq 1 ]]; then echo "DEBUG. duration:$int_duration <> silence: ${int_silence_duration}"; fi
  diff=$((int_duration - int_silence_duration))
  if [[ "${diff#-}" -lt 2 ]]; then
    LOUDNORM_OFF=1
    LOUDNORM=
    LOUDNORM_PARAMS=

    if [[ ${DEBUG} -eq 1 ]]; then echo "DEBUG. LOUDNORM OFF"; fi
  fi
fi

# generate command
SCALE="scale=${VSCALE}"
BITRATE="${VBRATE}k"
start=$(date +%s)
COMMAND="-hide_banner -c:v ${VCODEC} -passlogfile ${LOGFILE} -vf ${SCALE} -b:v ${BITRATE} -bufsize 4M -b:a ${ABRATE} -movflags +faststart -ar ${ASAMPLING}"

if [[ ${DEBUG} -eq 1 ]]; then
  echo "DEBUG. output fileinfo: scale=${VSCALE}, bitrate=${VBRATE}kb/s"
  echo "DEBUG. output filename: ${RESULT_FILENAME_PATH}"
fi

if [[ ${DEBUG} -eq 1 ]]; then echo 'DEBUG. TWO PASS CODING START'; fi
# start pass 1
$ffmpeg -y -i ${input_file} ${COMMAND} ${LOUDNORM}${LOUDNORM_PARAMS} -vsync cfr -pass 1 -f null /dev/null 2>${TMPFILE}

# exit if error
err=$(cat ${TMPFILE} | grep -i error -B 2)
if [[ $err ]]; then
  echo "ERROR. $err"
  exit
fi

pass1=$(date +%s)
runtime=$((pass1 - start))
if [[ ${DEBUG} -eq 1 ]]; then echo "DEBUG. PASS-1 done - ${runtime}sec"; fi

# get loudnorn params
if [[ ${LOUDNORM_OFF} -eq 0 ]]; then
  LOUDNORM_PARAMS=$(cat ${TMPFILE} | sed -n '/Parsed_loudnorm/,/}/p' | tail -n+3 | head -n+10 | tr -d '",' | while IFS='' read -r line || [[ -n "$line" ]]; do
    val=$(echo "${line}" | tr -d '[:space:]' | cut -f2 -d':')
    case $(echo "${line}" | tr -d '[:space:]' | cut -f1 -d':') in
    "input_i")
      l_param="${l_param}:measured_I=${val}"
      ;;
    "input_tp")
      l_param="${l_param}:measured_TP=${val}"
      ;;
    "input_lra")
      l_param="${l_param}:measured_LRA=${val}"
      ;;
    "input_thresh")
      l_param="${l_param}:measured_thresh=${val}"
      ;;
    "target_offset")
      l_param="${l_param}:offset=${val}:linear=true"
      ;;
    esac
    echo "${l_param}"
  done | tail -1)
fi
if [[ ${DEBUG} -eq 1 ]]; then echo "DEBUG. LOUDNORM_PARAMS = ${LOUDNORM_PARAMS}"; fi

# start pass 2
$ffmpeg -v error -y -i ${input_file} ${COMMAND} ${LOUDNORM}${LOUDNORM_PARAMS} -pass 2 ${RESULT_FILENAME_PATH}

pass2=$(date +%s)
runtime=$((pass2 - start))
p2time=$((pass2 - pass1))

if [[ ${DEBUG} -eq 1 ]]; then
  echo "DEBUG. PASS-2 done - ${runtime}sec (${p2time}sec)"
fi

rm -rf "${TEMP_DIR}"

echo 'Done'
