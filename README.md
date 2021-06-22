## Simple two pass ffmpeg transcoding with dynamic loudnorm normalization

```shell
usage: ./transcode.sh FILENAME_PATH  --bitrate=BITRATE_INT --scale=HEIGHT_INT:WIDTH_INT --output=RESULT_FILENAME_PATH --debug
```
### System
* `bash`, `ffmpeg`, `ffprobe`, `which` must be installed
* `bash` version >= 4.4 

### Options
* _FILENAME_PATH_ - abs or relative path to the input video file. **Must be a first argument**
* _BITRATE_INT_ - unsigned integer (in __kb/s__)
* _HEIGHT_INT & WIDTH_INT_ - unsigned integers both
* _RESULT_FILENAME_PATH_ - abs or relative path to the output video file
* --debug - is optional - provide a same info to stdout

