# 4webm (SVT-VP9 experimental version) 

4webm: A simple 4chan .webm conversion script using ffmpeg and SvtVp9EncApp. A precompiled static binary (for linux x86-64) is supplied in the folder SVT-VP9 with its accompanying license and notices. These binaries are supplied as is.

The binaries are compiled with AVX2 support. If AVX2 isn't supported on your system, it may be advisable to recompile SVT-VP9 locally. Please check [the official SVT-VP9 repository](https://github.com/OpenVisualCloud/SVT-VP9) for more information.

## "Installation"

Just chuck the files into a dedicated script folder (ideally in `$PATH`) or have them in any folder that contains media to be converted. It may be necessary to run `$ chmod u+s SvtVp9EncApp` in order to avoid running this script with sudo.

## Usage

The absolute minimum command required to transcode media into 4chan compatible webms is:

```bash
$ ./4webm.sh -i input.mp4
```
 The output file name will always be `inputfilename_DATE_TIME.webm`. If a different max. file size, duration and audio compatibility is desired, specify a board and enable the audio flag:

```bash
$ ./4webm.sh -i input.mp4 -b wsg -a
```
A "complete" example:

```bash
$ ./4webm.sh -i input.mp4 -b wsg -a 128 -m 10 -q best -v 0 -s 00:00:10.500 -e 00:01:19.690 -x "-vf eq=saturation=1.1,scale=-1:720 -aspect 16:9"
```

Flags:
* **(REQUIRED)** `-i input.mp4` specifies the **input file**
* `-b wsg` specifies **/wsg/** as the target board. Leaving this flag out will default the board setting to **/g/** (which shares the same limits with basically 90% of all boards).
* `-a 128` enables **audio** and sets the desired audio bitrate to **128** kb/s. Without specifying a bitrate, it defaults it to 96 kb/s
* `-m 10` sets the video bitrate **margin** to **10** kb/s, this margin is subsequently subtracted[^1] from the calculated bitrate and can be used to decrease file sizes, e.g., if the script failed to produce a webm within board limits (which is rare, but can happen) or to increase quality if the script produced a file that's significantly below limits
* `-q best` sets the **quality** setting of *libvpx-vp9* to **best**, users can choose from **realtime**, **good** and **best**. This setting affects compression efficiency
* `-v 0` sets the **speed** setting of *libvpx-vp9* to 0, users can set this in the range **0-5** with 0 having the best compression and 5 the lowest
* `-s 00:00:10.500 -e 00:01:19.690` sets the **start** and **end** points. Users can choose to use none, either one of them or both.
* `-x "-vf eq=saturation=1.1,scale=-1:720 -aspect 16:9"` this specifies additional settings to be handed over to *ffmpeg*, for further reference, [consult the ffmpeg manuals.](https://trac.ffmpeg.org/wiki "ffmpeg documentation")

* (not shown) `-l` changes the video and audio codices to *libvpx* (VP8) and *libvorbis*. This also means that `-q` and `-v` are no longer functional. This should only be used for compatibility (**legacy**) purposes.

* (new) `-t` changes the VP9 encoder to SVT-VP9. Requires SvtVp9EncApp in `$PATH` or locally. Skips two-pass encoding.[^2]

The help screen explains all flags and can be accessed via `$ ./4webm.sh -h`

## Default behaviour

The script determines a suitable total bitrate for a two pass encoding and additionally ensures that all board limits are met (i.e. max. file size, duration and resolution). If the input file is already within board limitations, the output file will closely match it in both size and quality. Should the input file exceed board limitations, the max. permissible bitrate for the output will be automatically selected.

The script also suggests a value for the margin setting `-m`, should the output be above/significantly below board limits. Alternatively, if audio was enabled, a lower audio bitrate is determined which reduces the file size (this option only re-encodes audio and is thus significantly faster than re-encoding the video again). 

There are currently no flags to optimise for bandwidth or storage space, this can be worked around by setting a high margin `-m` or setting the target board to /bant/: `-b bant` (2MiB limit).

## Alternative encoder: SVT-VP9

Running the script with `-t` enabled sets the VP9 encoder to SVT-VP9. Optimisations for SvtVp9EncApp are automatically determined. Using SVT-VP9 instead of libvpx-vp9 will result in a significant encoding speed boost of 10x-100x (depending on `-v` setting and system specs). Tradeoffs are a reduction in compression efficiency and visual quality at lower bitrates. Additionally, only a single pass can be made, which is less efficient than a two-pass approach.

[^1]: Currently, a positive margin value reduces the total bitrate, while a negative value increases it. This should probably be changed, but for now, it'll work.
[^2]: No audio compatibility for now. Known issues: scrubbing is broken.
