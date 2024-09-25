#!/bin/bash
#
# RDEPEND: ffmpeg, SvtVp9EncApp, gawk, sed, grep, bc, date
#
# 4webm: A simple webm converter script using ffmpeg, SVT-VP9 compatible
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
DIR=${0%/*}
SVTDIR="$DIR/SVT-VP9"

Help() {
cat <<EOF

Simple 4chan webm script.

Arguments:
	-i INPUT FILE $( tput setaf 1 )(REQUIRED!)$( tput sgr 0 ) Specifies the input file to be used, output file name will be "inputfilename_DATE_TIME.webm"
				EXAMPLE:	-i inputfilename.mp4

	-a AUDIO	Toggles audio and allows for a bitrate specification (optional). Can only be used in conjunction with boards: /wsg/,/wsr/,/gif/.
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

        -o OUTPUT FILE Specifies the output file name. If not set, output file name will default to "input_DATE_TIME.webm". Unicode characters are supported,
	   	       but the file name needs to be delimited by " ".
        	                DEFAULT:       (default name)
				EXAMPLE:       -o output_file_name

	-q QUALITY	Specifies the -quality setting of libvpx-vp9. Better quality means higher compression but also longer
			encoding times.
				DEFAULT:	good
				EXAMPLE:	-q best

	-s/-e START/END	Specifies start/end times. Similar to ffmpeg's "-ss" and "-to", requires same syntax. Used to determine
			duration and bitrates.
				DEFAULT:	(full input media length)
				EXAMPLE:	-s 00:00:03.210
						-e 00:00:04.169
						-s 00:01:01.200 -e 00:01:06.199

	-t SVT-VP9	Switches the VP9 encoder from libvpx-vp9 to SVT-VP9. Requires SvtVp9EncApp in \$PATH. Ensure enough disk space is available for 
			raw data.
				DEFAULT:	OFF
				EXAMPLE:	-t

	-v SPEED	Specifies the -speed for libvpx-vp9 or -enc-mode for SVT-VP9. Lower speed mean higher compression but also longer
			encoding times. (libvpx-vp9 range: 0-5, SVT-VP9 range: 0-9)
				DEFAULT:	<720p --> 1, >=720p --> 2
				EXAMPLE:	-v 2

	-x EXTRA	Specifies additional ffmpeg parameters. Needs to be delimited by " ". Can be used to scale, crop, filter etc. 
			(pass filter arguments only using -vf). Please refer to the ffmpeg manual for more information.
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
    AudioEncode "${OUTFILE}.webm"
elif [[ $AFFIRM == y ]] && [[ $1 == svt-vp9 ]]
then
    echo -e "\nEncoding"
    SvtVp9Encode
elif [[ $AFFIRM == y ]] && [[ $1 == libvpx-vp9 ]]
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
    MARGIN=$( echo "scale=2; $MARGIN + $NOMINAL + 1" | bc )

    if [[ $AUDIO == true ]]
    then
        AUDIOADJ=$( echo "scale=2; $AUDIOADJ - $NOMINAL - 1" | bc )
        AUDIOPTS="-c:a $LIBCA -b:a ${AUDIOADJ}K"
	if [[ $( echo "$AUDIOADJ > 32" | bc -l ) -eq 1 ]]
	then
            echo "Re-encode audio at $AUDIOADJ kbps to reduce the file size?"
            Proceed fix
            OutfileSize "${OUTFILEFIXED}_reencode.webm"
	else
	    echo "Audio re-encode not possible as the resulting audio bitrate would drop below the threshold of 32 kbps. Rerun with \"-m $MARGIN\"."
	    exit
	fi
    else
        echo "Rerunning with \"-m $MARGIN \" may bring the file size back to within limits."
        exit
    fi
fi

echo -e "\nThe output file size is: $( tput setaf 2 )$OUTSIZE MiB$( tput sgr 0 )"

DELTA=$( echo "$FILESIZE - $OUTSIZE" | bc  )
BitrateCalc $DELTA
MARGIN=$( echo "scale=2; $MARGIN - $NOMINAL + 1" | bc)

if [[ $( echo "$NOMINAL < $LOWLIMIT" | bc -l ) -eq 1 ]]
then
    exit
else
    echo "It may be possible to increase quality while staying within limits by setting \"-m $MARGIN \"."
    if [[ $LIBCV == "svt-vp9" ]]
    then
	echo "This is advisable for SVT-VP9 encoded media, if the output file size is significantly below limits."
    fi
fi
}

OutfileSize() {
OUTSIZE=$( ls -l | grep "$1" | awk '{print $5}' )
OUTSIZE=$( echo "scale=10; $OUTSIZE/(2^20)" | bc)
OutfileAnalysis
}

#############
# ENCODING #
#############

Encode() {
echo "Pass 1/2:"
ffmpeg -hide_banner -loglevel error -stats -i "$INFILE" $STARG $ETARG -c:v $LIBCV -b:v "${BITRATE}K" -pass 1 -quality good -speed 4 $EXTRARG -an -f rawvideo -y /dev/null
echo "Pass 2/2:"
ffmpeg -hide_banner -loglevel error -stats -i "$INFILE" $STARG $ETARG -c:v $LIBCV -b:v "${BITRATE}K" -pass 2 -quality $QUALITY -speed $SPEED $EXTRARG $AUDIOPTS -row-mt 1 -map_metadata -1 -y "${OUTFILE}.webm"
rm ffmpeg2pass-0.log
OutfileSize "${OUTFILEFIXED}.webm"
}

AudioEncode() {
echo "Pass 1/1:"
ffmpeg -hide_banner -loglevel error -stats -i "$1" -i "$INFILE" -map 0:v:0 -c:v copy -map 1:a:0 $AUDIOPTS -shortest -map_metadata -1 -y "${OUTFILE}_reencode.webm"
}

SvtVp9Encode() {
BITRATE=$( echo "$BITRATE * 1000" | bc )
KEYSPACE="7"
NUM=$( echo "$FRATE * 100" | bc )
DENOM="100"

#SVT-VP9 is behaving weirdly (or I can't get it running right), but
#it's a very valuable tool to have, so I'm still leaving it as an option.
#In any case, keyframe spacing and the resulting GOP size causes all
#sorts of issues. Hardcoding it to a low value seems to fix it for now.

echo -e "\nDemuxing, Stage 1/2:"
ffmpeg -hide_banner -loglevel error -stats -i "$INFILE" $STARG $ETARG $EXTRARG -pix_fmt yuv420p -f rawvideo -y raw.yuv
echo -e "\nEncoding, Stage 2/2:"
$SVTDIR/SvtVp9EncApp -i raw.yuv -w $HRES -h $VRES -intra-period $KEYSPACE -fps-num $NUM -fps-denom $DENOM -rc 1 -tbr $BITRATE -min-qp 0 -max-qp 60 -tune 0 -enc-mode $SPEED -b "${OUTFILE}.ivf"

if [[ $AUDIO == true ]]
then
    echo -e "\nMuxing audio 1/1:"
    AudioEncode "${OUTFILE}.ivf"
    OutfileSize "${OUTFILEFIXED}_reencode.webm"
else
    ffmpeg -i "${OUTFILE}.ivf" -c:v copy -map_metadata -1 -y "${OUTFILE}.webm"
    OutfileSize "${OUTFILEFIXED}.webm"
fi

rm "${OUTFILE}.ivf"
rm raw.yuv
}

while getopts "ab:e:i:lm:o:q:s:tv:x:h" OPTS; do
    case "$OPTS" in
	a) AUDIO=true
	   eval NEXTOPT=${!OPTIND}
	   if [[ -n $NEXTOPT ]] && [[ $NEXTOPT != -* ]]
	   then
	       OPTIND=$((OPTIND + 1))
	       AUDIOADJ=$NEXTOPT
	   else
	       AUDIOADJ="96"
	   fi;;
	b) BOARD="$OPTARG";;
	e) END="$OPTARG";;
	i) INFILE="$OPTARG";;
	l) LIBCV="libvpx"
	   LIBCA="libvorbis";;
	m) MARGIN="$OPTARG";;
	o) OUTFILE="$OPTARG";;
	q) QUALITY="$OPTARG";;
	s) START="$OPTARG";;
	t) OVERHEAD="5"
	   LIBCV="svt-vp9";;
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

if [[ -z $OUTFILE ]]
then
    OUTFILE="$( echo "$INFILE" | sed 's/\(\.\w\{3,4\}\)$//' )""_$( date +%F_%T )"
fi

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

if [[ -n $START ]] && [[ -n $END ]]
then
    S=$( echo "$START" | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    E=$( echo "$END" | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    DURATION=$( echo "$E - $S" | bc )
    STARG="-ss $START"
    ETARG="-to $END"
elif [[ -n $START ]] && [[ -z $END ]]
then
    S=$( echo "$START" | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    E=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*Duration: //p' | sed -n 's/\(,.*\)$//p' | awk -F : '{print ($1*3600) + ($2*60) + $3}' )
    DURATION=$( echo "$E - $S" | bc )
    STARG="-ss $START"
    ETARG=""
elif [[ -z $START ]] && [[ -n $END ]]
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

CRAT=$( ffprobe "$INFILE" 2>&1 | sed -n 's/^.*bitrate: //p' | sed 's/\( kb\/s\)$//' )
BitrateCalc $FILESIZE
NRATE=$( echo "$NOMINAL - $AUDIOADJ" | bc )

if [[ $( echo "$NOMINAL < $CRAT" | bc -l ) -eq 1 ]]
then
    BITRATE=$( echo "$NRATE - $MARGIN - $OVERHEAD" | bc )
else
    BITRATE=$( echo "$CRAT - $MARGIN" | bc )
fi

####################
# RESOLUTION CHECK #
####################

RES=$( ffprobe "$INFILE" 2>&1 | grep -o -E [0-9]\{2,4\}x[0-9]\{2,4\} )
HRES=$( echo "$RES" | awk -F x '{print $1}' )
VRES=$( echo "$RES" | awk -F x '{print $2}' )

FRATE=$( ffprobe "$INFILE" 2>&1 | grep -o -E "[0-9]+(.[0-9]+)? tbr" | sed 's/\( tbr.*\)$//' )
if [[ -z $FRATE ]]
then
    FRATE=$( ffprobe "$INFILE" 2>&1 | grep -o -E "[0-9]+(.[0-9]+)? fps" | sed 's/\( fps.*\)$//' )
fi


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
cat << EOF
===================================================================================================
INPUT FILE:			$INFILE
OUTPUT FILE:			${OUTFILE}.webm
SELECTED BOARD:			/$BOARD/
AUDIO:				$AUDIO
EOF
if [[ $AUDIO == true ]]
then
    echo "AUDIO CODEC:			$LIBCA"
    echo "AUDIO BITRATE: 			${AUDIOADJ} kbps"
fi
cat <<EOF
VIDEO DURATION:			$DURATION s
VIDEO CODEC:			$LIBCV
SELECTED RESOLUTION:		$HRES x $VRES
VIDEO FRAMERATE:		$FRATE fps
CURRENT TOTAL BITRATE:		$CRAT kbps
MAX. PERMISSIBLE BITRATE:	$NOMINAL kbps
SELECTED VIDEO BITRATE:		$BITRATE kbps
EOF
if [[ -n $EXTRARG ]]
then
    echo "FFMPEG ARGUMENTS:		$EXTRARG"
fi
cat <<EOF
===================================================================================================
EOF
tput sgr 0

Proceed $LIBCV
