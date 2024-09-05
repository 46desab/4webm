#!/bin/bash
#
# RDEPEND: ffmpeg, gawk, sed, grep, bc
#
# 4webm: A simple webm converter script using ffmpeg
#
####################################################

############
# DEFAULTS #
############

AUDIO=false
AUDIOPTS="-an"
AUDIOADJ="0"
ARAT="0"
BOARD="g"
LIBCV="libvpx-vp9"
LIBCA="libopus"
MARGIN="0"
QUALITY="good"
SPEED="1"
EXTRARG=""

Help() {
cat <<EOF

Simple 4chan webm script. Arguments with a "*" are required. Numbers, when specified, should always be positive integers incl. 0.

Arguments:
	-i INPUT FILE*	Specifies the input file to be used, output file name will be "inputfilename_DATE_TIME.webm"
				EXAMPLE:	-i inputfilename.mp4

	-a AUDIO	Toggles audio and allows for a bitrate specification. Can only be used in conjunction with boards: /wsg/ and /gif/.
				DEFAULT:	OFF: No audio
						ON: 96kbps
				EXAMPLE:	-a, -a 128

	-b BOARD	Selects the intended board. Max. file size, duration and audio will be determined by this.
				DEFAULT:	Limit of 4096KiB and no audio.
				EXAMPLE:	-b wsg

	-l LEGACY	Changes the codices to VP8 and VORBIS. Only enable for compatibility purposes. Audio is still controlled
			via "-a".
				DEFAULT:        OFF: VP9 + OPUS
							ON: VP8 + VORBIS
				EXAMPLE:        -l

	-m MARGIN	Reduces the calculated max. permissible bitrate by X kbps. Can be used to reduce file sizes.
				DEFAULT:        0
				EXAMPLE:        -m 3

	-q QUALITY	Specifies the -quality setting of libvpx-vp9. Better quality means higher compression but also longer
			encoding times.
				DEFAULT:	good
				EXAMPLE:	-q best

	-s/-e START/END	Specifies start/end times. Similar to ffmpeg's "-ss" and "-to", requires same syntax. Used to determine
			duration and bitrates.
				DEFAULT: (full input media length)
				EXAMPLE:	-s 00:00:03.210
						-e 00:00:04.169
						-s 00:01:01.200 -e 00:01:06.199

	-v SPEED	Specifies the -speed setting of libvpx-vp9. Lower speed mean higher compression but also longer
			encoding times.
				DEFAULT:	1
				EXAMPLE:	-v 2

	-x EXTRA	Specifies additional ffmpeg parameters. Needs to be delimited by " ".  Can be used to scale, crop, filter etc.
			Please refer to the ffmpeg manual for more information.
				DEFAULT:	No additional options
				EXAMPLE:	-x "-vf scale=-1:720 -aspect 16:9"

	FULL EXAMPLE: $ bash. 4webm.sh -i input.mp4 -b wsg -a 64 -m 1 -q best -v 0 -x "-vf eq=saturation=1.1"

EOF
}

################
# CALC. OUTPUT #
################

MediaInfo() {
echo "==================================================================================================================="
echo "INPUT FILE:			$INFILE"
echo "OUTPUT FILE:			${OUTFILE}.webm"
echo "SELECTED BOARD:			/$BOARD/"
echo "AUDIO:				$AUDIO"
if [[ $AUDIO == true ]]
then
    echo "AUDIO CODEC:			$LIBCA"
    echo "AUDIO BITRATE: 			${AUDIOADJ} kbps"
fi
echo "VIDEO DURATION:			$DURATION s"
echo "VIDEO CODEC:			$LIBCV"
echo "CURRENT TOTAL BITRATE:		$CRAT kbps"
echo "MAX. PERMISSIBLE BITRATE:	$NOMINAL kbps"
echo "SELECTED VIDEO BITRATE:		$BITRATE kbps"
echo "==================================================================================================================="
}

#####################
# HANDOFF TO FFMPEG #
#####################

Encode() {
ffmpeg -i "$INFILE" $STARG $ETARG -c:v $LIBCV -b:v "${BITRATE}K" -pass 1 -quality good -speed 4 -an -f rawvideo -y /dev/null
ffmpeg -i "$INFILE" $STARG $ETARG -c:v $LIBCV -b:v "${BITRATE}K" -pass 2 -quality $QUALITY -speed $SPEED $EXTRARG $AUDIOPTS -row-mt 1 -map_metadata -1 -y "${OUTFILE}.webm"
}

while getopts "ab:e:i:lm:q:s:v:x:h" OPTS; do
      case "$OPTS" in
	  a) AUDIO=true
		 eval NEXTOPT=${!OPTIND}
		 if [[ -n $NEXTOPT ]] && [[ $NEXTOPT != -* ]]
		 then
		     OPTIND=$((OPTIND + 1))
		     AUDIOADJ=$NEXTOPT
		 else
			 level=1
			 AUDIOADJ="96"
		 fi;;
	  i) INFILE="$OPTARG";;
	  b) BOARD="$OPTARG";;
	  e) ETIME=true
	     END="$OPTARG";;
	  l) LIBCV="libvpx"
		 LIBCA="libvorbis";;
	  m) MARGIN="$OPTARG";;
	  q) QUALITY="$OPTARG";;
	  s) STIME=true
		 START="$OPTARG";;
	  v) SPEED="$OPTARG";;
	  x) EXTRARG="$OPTARG";;
	  h) Help
		 exit 1;;
	  ?) Help
		 exit 1;;
	  :) Help
		 exit 1;;
      esac
done


OUTFILE="$( echo "$INFILE" | sed 's/\(\.\w\{3,4\}\)$//' )""_$( date +%F_%T )"
OUTFILEFIXED=$( echo "$OUTFILE" | sed 's/\[/\\\[/g' | sed 's/\]/\\\]/g' )

##########################
# BOARD LIMITS AND AUDIO #
##########################

if [[ $BOARD == wsg ]]
then
    FILESIZE="6"
    MAXDUR="300"
elif [[ $BOARD == b ]] || [[ $BOARD == bant ]]
then
    FILESIZE="2"
    MAXDUR="120"
else
    FILESIZE="4"
    MAXDUR="120"
fi

if [[ $AUDIO == true ]] && [[ (( $BOARD == wsg || $BOARD == gif )) ]]
then
    AUDIOPTS="-c:a $LIBCA -b:a ${AUDIOADJ}K"
    ARAT=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*fltp, //p' | sed 's/\( kb\/s\ (default)\)$//' )
    if [[ -z $ARAT ]]
    then
    	ARAT="128"
    fi
elif [[ $AUDIO == true ]] && [[ (( $BOARD != wsg || $BOARD != gif )) ]]
then
    echo "The selected board does not support audio. Please deselect the audio flag \"-a\" or choose a board with audio compatibility."
    exit
fi

##################
# DURATION CHECK #
##################

if [[ $STIME == true ]] && [[ $ETIME == true ]]
then
    S=$( echo "$START" | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    E=$( echo "$END" | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    DURATION=$( echo "$E - $S" | bc )
    STARG="-ss $START"
    ETARG="-to $END"
elif [[ $STIME == true ]] && [[ $ETIME != true ]]
then
    S=$( echo "$START" | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    E=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*Duration: //p' | sed -n 's/\(,.*\)$//p' | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    DURATION=$( echo "$E - $S" | bc )
    STARG="-ss $START"
    ETARG=""
elif [[ $STIME != true ]] && [[ $ETIME == true ]]
then
    S="0"
    E=$( echo "$END" | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    DURATION=$( echo "$E - $S" | bc )
    STARG=""
    ETARG="-to $END"
else
    DURATION=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*Duration: //p' | sed -n 's/\(,.*\)$//p' | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
fi

if [[ $( echo "$DURATION > $MAXDUR" | bc -l ) -eq 1 ]]
then
    echo "The duration of the input medium exceeds the max. permissible duration ($MAXDUR s) for your selected board."
    echo "Specify a different board or cut the video file."
    exit
fi

#######################
# BITRATE CALCULATION #
#######################

VRAT=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*bitrate: //p' | sed 's/\( kb\/s\)$//' )
CRAT=$( echo "$VRAT + $ARAT" | bc )
NOMINAL=$( echo "scale=2; ($FILESIZE * 2^20 * 0.008 / $DURATION) - $AUDIOADJ" | bc )

if [[ $( echo "$NOMINAL < $CRAT" | bc -l ) -eq 1 ]]
then
    BITRATE=$( echo "$NOMINAL - $MARGIN - 3" | bc )
else
    BITRATE=$( echo "$CRAT - $MARGIN" | bc )
fi

MediaInfo

echo -n "Proceed? [y/n]: "
read -r AFFIRM

if [[ $AFFIRM == y ]]
then
    echo "Encoding..."
    Encode
else
    echo "Exiting..."
    exit
fi

######################
# OUTPUT FILE ANALYSIS #
######################

OUTSIZE=$( ls -l | grep "${OUTFILEFIXED}.webm" | awk {'print $5'} )
OUTSIZE=$( echo "scale=10; $OUTSIZE/(2^20)" | bc)

if [[ $( echo "$OUTSIZE > $FILESIZE" | bc -l ) -eq 1 ]]
then
    echo "The output file size is: $OUTSIZE MiB, which is larger than the max. permissible filesize of $FILESIZE MiB"
    echo "Please rerun the script using a higher margin (\"-m X\") or change the target board."
    exit
fi

echo "The output file size is: $OUTSIZE MiB"
