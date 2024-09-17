#!/bin/bash
#
# RDEPEND: ffmpeg, gawk, sed, grep, bc, date
#
# 4webm: A simple webm converter script using ffmpeg
#
####################################################

set -o errexit

############
# DEFAULTS #
############

AUDIO="false"
AUDIOPTS="-an"
AUDIOADJ="0"
ARAT="0"
BOARD="g"
LIBCV="libvpx-vp9"
LIBCA="libopus"
MARGIN="0"
QUALITY="good"
EXTRARG=""
LOWLIMIT="10"
OVERHEAD="3"

Help() {
cat <<EOF

Simple 4chan webm script.

Arguments:
	-i INPUT FILE $( tput setaf 1 )(REQUIRED!)$( tput sgr 0 ) Specifies the input file to be used, output file name will be "inputfilename_DATE_TIME.webm"
				EXAMPLE:	-i inputfilename.mp4

	-a AUDIO	Toggles audio and allows for a bitrate specification. Can only be used in conjunction with boards: /wsg/,/wsr/,/gif/.
				DEFAULT:	OFF (no audio)
				EXAMPLE:	-a, -a 128

	-b BOARD	Selects the intended board. Max. file size, duration and audio will be determined by this.
				DEFAULT:	Limit of 4096KiB and no audio.
				EXAMPLE:	-b wsg

	-l LEGACY	Changes the codices to VP8 and VORBIS. Only enable for compatibility purposes. Audio is still controlled
			via "-a".
				DEFAULT:        OFF (VP9 + OPUS)
				EXAMPLE:        -l

	-m MARGIN	Adjusts the calculated max. permissible bitrate by X kbps. Can be used to increase quality or to decrease file sizes.
				DEFAULT:        0
				EXAMPLE:        -m 3, -m -14.08

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
				DEFAULT:	<720p --> 1, >=720p --> 2
				EXAMPLE:	-v 2

	-x EXTRA	Specifies additional ffmpeg parameters. Needs to be delimited by " ".  Can be used to scale, crop, filter etc. (pass filter arguments only using -vf).
			Please refer to the ffmpeg manual for more information.
				DEFAULT:	No additional options
				EXAMPLE:	-x "-vf scale=-1:720 -aspect 16:9"

	FULL EXAMPLE: $ bash 4webm.sh -i input.mp4 -b wsg -a 64 -m 1 -q best -v 0 -x "-vf eq=saturation=1.1,crop=200:100:100:0"

EOF
}

BitrateCalc() {
NOMINAL=$( echo "scale=2; ($1 * 2^20 * 0.008 / $DURATION)" | bc )
}

Proceed() {
echo -n "Proceed? [$( tput setaf 2 )y$( tput sgr 0 )/$(tput setaf 1 )n$( tput sgr 0 )]: "
read -r AFFIRM

if [[ $AFFIRM == y ]] && [[ $1 == fix ]]
then
    echo -e "\nRe-encoding audio"
    Reencode
elif [[ $AFFIRM == y ]] && [[ -z $1 ]]
then
    echo -e "\nEncoding"
    Encode
else
    echo -e "\nExiting..."
    exit
fi
}

########################
# OUTPUT FILE ANALYSIS #
########################

OutfileAnalysis() {

if [[ $( echo "$OUTSIZE > $FILESIZE" | bc -l ) -eq 1 ]]
then
    DELTA=$( echo "$OUTSIZE - $FILESIZE" | bc  )
    BitrateCalc $DELTA
    echo -e "$( tput setaf 1 )\nLIMIT ERROR: $( tput sgr 0 )The output file size is: $OUTSIZE MiB, which is larger than the max. permissible filesize of $FILESIZE MiB"

    if [[ $AUDIO == true ]] && [[ $( echo "$AUDIOADJ > 34" | bc -l ) -eq 1 ]]
    then
        AUDIOADJ=$( echo "scale=2; $AUDIOADJ - $NOMINAL - 1" | bc )
        AUDIOPTS="-c:a $LIBCA -b:a ${AUDIOADJ}K"
        echo "Re-encoding audio at $AUDIOADJ kbps to reduce the file size:"
        Proceed fix
        OutfileSize "${OUTFILEFIXED}_reencode.webm"
    else
        MARGIN=$( echo "scale=2; $MARGIN + $NOMINAL + 1" | bc )
        echo "Rerunning with \"-m $MARGIN \" may bring the file size back to within limits."
    fi    
    exit
fi

echo -e "\nThe output file size is: $( tput setaf 2 )$OUTSIZE MiB$( tput sgr 0 )"

DELTA=$( echo "$FILESIZE - $OUTSIZE" | bc  )
BitrateCalc $DELTA
MARGIN=$( echo "scale=2; $MARGIN - $NOMINAL + 1" | bc)

if [[ $( echo "$NOMINAL < $LOWLIMIT" | bc -l ) -eq 1 ]] || [[ $( echo "($BITRATE + $NOMINAL) > $CRAT" | bc -l ) -eq 1 ]]
then
    exit
else
    echo "It may be possible to increase quality while staying within limits by setting \"-m $MARGIN \"."
fi
}

OutfileSize() {
OUTSIZE=$( ls -l | grep "$1" | awk '{print $5}' )
OUTSIZE=$( echo "scale=10; $OUTSIZE/(2^20)" | bc)
OutfileAnalysis
}

#####################
# HANDOFF TO FFMPEG #
#####################

Encode() {
echo "Pass 1/2:"
ffmpeg -hide_banner -loglevel error -stats -i "$INFILE" $STARG $ETARG -c:v $LIBCV -b:v "${BITRATE}K" -pass 1 -quality good -speed 4 $EXTRARG -an -f rawvideo -y /dev/null
echo "Pass 2/2:"
ffmpeg -hide_banner -loglevel error -stats -i "$INFILE" $STARG $ETARG -c:v $LIBCV -b:v "${BITRATE}K" -pass 2 -quality $QUALITY -speed $SPEED $EXTRARG $AUDIOPTS -row-mt 1 -map_metadata -1 -y "${OUTFILE}.webm"
rm ffmpeg2pass-0.log
}

Reencode() {
echo "Pass 1/1:"
ffmpeg -hide_banner -loglevel error -stats -i "${OUTFILE}.webm" -i "$INFILE" -c:v copy $AUDIOPTS -map 0:v:0 -map 1:a:0 -y "${OUTFILE}_reencode.webm"
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
	  b) BOARD="$OPTARG";;
	  e) ETIME=true
	      END="$OPTARG";;
	  i) INFILE="$OPTARG";;
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

if [[ $AUDIO == true ]] && [[ $BOARD == wsg || $BOARD == gif || $BOARD == wsr ]]
then
    AUDIOPTS="-c:a $LIBCA -b:a ${AUDIOADJ}K"
    ARAT=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*fltp, //p' | sed 's/\( kb\/s\ (default)\)$//' )
    if [[ -z $ARAT ]]
    then
    	ARAT="128"
    fi
elif [[ $AUDIO == true ]] && [[ $BOARD != wsg || $BOARD != gif || $BOARD != wsr ]]
then
    echo "$( tput setaf 1 )LIMIT ERROR: $( tput sgr 0 )The selected board does not support audio. Please deselect the audio flag \"-a\" or choose a board with audio compatibility."
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
    echo "$( tput setaf 1 )LIMIT ERROR: $( tput sgr 0 )The duration of the input medium exceeds the max. permissible duration ($MAXDUR s) for your selected board."
    echo "Specify a different board or cut the video file."
    exit
fi

#######################
# BITRATE CALCULATION #
#######################

VRAT=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*bitrate: //p' | sed 's/\( kb\/s\)$//' )
CRAT=$( echo "$VRAT + $ARAT" | bc )
BitrateCalc $FILESIZE
NRATE=$( echo "$NOMINAL - $AUDIOADJ" | bc )

if [[ $( echo "$NRATE < $CRAT" | bc -l ) -eq 1 ]]
then
    BITRATE=$( echo "$NRATE - $MARGIN - $OVERHEAD" | bc )
else
    BITRATE=$( echo "$CRAT - $MARGIN" | bc )
fi

####################
# RESOLUTION CHECK #
####################

RES=$( ffprobe "$INFILE" 2>&1 | grep -o -E [0-9]\{2,4\}x[0-9]\{2,4\} )
#FRATE=$( ffprobe "$INFILE" 2>&1 | grep -o -E "[0-9]+(.[0-9]+)? fps" | sed 's/\( fps.*\)$//' )
HRES=$( echo "$RES" | awk -F x '{print $1}' )
VRES=$( echo "$RES" | awk -F x '{print $2}' )

if [[ -n $EXTRARG ]]
then
    SELHRES=$( echo $EXTRARG | grep -o -E \\-vf.*scale=-?[0-9]+:-?[0-9]+ | sed 's/-vf.*scale=//' | awk -F : '{print ($1)}' )
    SELVRES=$( echo $EXTRARG | grep -o -E \\-vf.*scale=-?[0-9]+:-?[0-9]+ | sed 's/-vf.*scale=//' | awk -F : '{print ($2)}' )

    if [[ -n $SELHRES ]] && [[ $( echo "$SELHRES > 2048" | bc -l ) -eq 1 || $(echo "$SELVRES > 2048" | bc -l ) -eq 1 ]]
    then
        echo "$( tput setaf 1 )LIMIT ERROR: $( tput sgr 0 )The selected horizontal/vertical video resolution exceeds 2048p."
        exit
    fi

    HCROP=$( echo $EXTRARG | grep -o -E \\-vf.*crop=[0-9]+:[0-9]+ | sed 's/-vf.*crop=//' | awk -F : '{print ($1)}' )
    VCROP=$( echo $EXTRARG | grep -o -E \\-vf.*crop=[0-9]+:[0-9]+ | sed 's/-vf.*crop=//' | awk -F : '{print ($2)}' )

    if  [[ -n $HCROP ]] && [[ $( echo "$HCROP > 2048" | bc -l ) -eq 1 || $(echo "$VCROP > 2048" | bc -l ) -eq 1 ]]
    then
        echo "$( tput setaf 1 )LIMIT ERROR: $( tput sgr 0 )The cropped horizontal/vertical video resolution exceeds 2048p."
        exit
    fi
fi

if [[ $( echo "$HRES > 2048" | bc -l ) -eq 1 || $( echo "$VRES > 2048" | bc -l ) -eq 1 ]]
then
    echo "$( tput setaf 1 )LIMIT ERROR: $( tput sgr 0 )The horizontal/vertical video resolution exceeds 2048p. Please scale/crop the video"
    exit
fi

if [[ -n $SELHRES ]]
then
    HRES="$SELHRES"
    VRES="$SELVRES"
elif [[ -n $HCROP ]]
then
    HRES="$HCROP"
    VRES="$VCROP"
fi

if [[ -z $SPEED && $( echo "$VRES >= 720" | bc -l ) -eq 1 ]]
then
    SPEED="2"
elif [[ -z $SPEED ]]
then
    SPEED="1"
fi

################
# CALC. OUTPUT #
################

tput setaf 6
echo "========================================================================================================="
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
echo "SELECTED RESOLUTION:		$HRES x $VRES"
echo "CURRENT TOTAL BITRATE:		$CRAT kbps"
echo "MAX. PERMISSIBLE BITRATE:	$NOMINAL kbps"
echo "SELECTED VIDEO BITRATE:		$BITRATE kbps"
if [[ -n $EXTRARG ]]
then
    echo "FFMPEG ARGUMENTS:		$EXTRARG"
fi
echo "========================================================================================================="
tput sgr 0

Proceed

OutfileSize "${OUTFILEFIXED}.webm"
