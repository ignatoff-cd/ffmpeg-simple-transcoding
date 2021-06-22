#!/usr/local/bin/bash

input_file=$1

for i in "$@"
do
case $i in
    -h|--help)
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
LOGFILE=$(mktemp /tmp/ffmpeg.XXXXXXXXX)
TMPFILE=$(mktemp /tmp/ffmpeg-pass-1.XXXXXXXXX)
LOUDNORM="-af loudnorm=I=-16:TP=-1:LRA=13"
LOUDNORM_PARAMS=":print_format=json"

if [[ ! ${VBRATE} ]]; then echo 'ERROR. undefined --bitrate opt';exit; fi
if [[ ! ${VSCALE} ]]; then echo 'ERROR. undefined --scale opt';exit; fi
if [[ ! ${RESULT_FILENAME_PATH} ]]; then echo 'ERROR. undefined --output opt';exit; fi

if [[ ${DEBUG} -eq 1 ]]; then
  # shellcheck disable=SC2006
  finfo=`$ffprobe -v error -select_streams v:0 -show_entries format=bit_rate,duration -show_entries stream=width,height -of default=noprint_wrappers=1 ${input_file} |tr -s '\n' ','`
  width=$(echo $finfo | cut -f1 -d ',' | cut -f2 -d'=')
  height=$(echo $finfo | cut -f2 -d ',' | cut -f2 -d'=')
  bitrate=$(echo $finfo | cut -f4 -d ',' | cut -f2 -d'=')
  duration=$(echo $finfo | cut -f3 -d ',' | cut -f2 -d'=')
  size=$(du -h ${input_file} |cut -f1)
  yes "*"  |head -n 80|tr -d '\n'
  echo
  echo "INPUT fileinfo: scale=${width}x${height}, bitrate=$((bitrate/1000))kb/s, duration: ${duration%.*}sec, size: ${size}"
  yes "*"  |head -n 80|tr -d '\n'
  echo
fi

if [[ ${DEBUG} -eq 1 ]]; then echo 'DEBUG. TWO PASS CODING START'; fi
		SCALE="scale=${VSCALE}"
		BITRATE="${VBRATE}k"
		start=$(date +%s)
		COMMAND="-c:v ${VCODEC} -passlogfile ${LOGFILE} -vf ${SCALE} -b:v ${BITRATE} -bufsize 4M -b:a ${ABRATE} -movflags +faststart -ar ${ASAMPLING}"

    if [[ ${DEBUG} -eq 1 ]]; then
      echo "DEBUG. output fileinfo: scale=${VSCALE}, bitrate=${VBRATE}kb/s"
      echo "DEBUG. output filename: ${RESULT_FILENAME_PATH}"
    fi

    # pass 1
		$ffmpeg -y -i ${input_file} ${COMMAND} ${LOUDNORM}${LOUDNORM_PARAMS} -vsync cfr -pass 1 -f null /dev/null 2> ${TMPFILE}

		pass1=$(date +%s)
		runtime=$((pass1 -start))
    if [[ ${DEBUG} -eq 1 ]]; then echo "DEBUG. PASS-1 done - ${runtime}sec"; fi

		# shellcheck disable=SC2006
		LOUDNORM_PARAMS=`cat ${TMPFILE} |sed -n  '/Parsed_loudnorm/,/}/p' | tail -n+3 |head -n+10| tr -d '",' | while IFS='' read -r line || [[ -n "$line" ]]; do
			val=$(echo "${line}" | tr -d '[:space:]' | cut -f2 -d':')
			case $(echo "${line}" | tr -d '[:space:]'  | cut -f1 -d':') in
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
		done | tail -1`

    # debug message
    if [[ ${DEBUG} -eq 1 ]]; then echo "DEBUG. LOUDNORM_PARAMS = ${LOUDNORM_PARAMS}"; fi

    # pass 2
		$ffmpeg -v error -y -i ${input_file} ${COMMAND} ${LOUDNORM}${LOUDNORM_PARAMS} -pass 2 ${RESULT_FILENAME_PATH}

		pass2=`date +%s`
		runtime=$((pass2-start))
		p2time=$((pass2-pass1))

    if [[ ${DEBUG} -eq 1 ]]; then
      echo "DEBUG. PASS-2 done - ${runtime}sec (${p2time}sec)";
     fi

    rm ${LOGFILE} ${TMPFILE}

    echo 'Done'