import os
import strutils

import optionals
import numerics
import pipelines

#===============================================================================
# GObject Imports

const gObjectPath =
  when hostOS == "linux": "libgobject-2.0.so"
  elif hostOS == "macosx": "libgobject-2.0.dylib"
  else: "unknown"

type GError = object
type GType = csize

{.push callConv: cDecl, dynLib: gObjectPath, importC.}

proc g_signal_emit_by_name(instance: pointer, detailed_signal: cstring)
                           {.varargs.}
{.pop.}

#===============================================================================
# GStreamer Imports

const gStreamerPath =
  when hostOS == "linux": "libgstreamer-1.0.so"
  elif hostOS == "macosx": "libgstreamer-1.0.dylib"
  else: "unknown"

type GstClockTime = int64
type GstFlowReturn = cint
type GstMapFlags = cint
type GstMessageType = cint
type GstState = cint
type GstStateChangeReturn = cint

type GstAllocationParams = object
type GstAllocator = object
type GstBin = object
type GstBus = object
type GstCaps = object
type GstPad = object
type GstBufferPool = object
type GstElement = object
type GstEvent = object
type GstMemory = object
type GstMessage = object
type GstSample = object
type GstStructure = object

type GstMiniObject = array[64, byte]

type GstBuffer = object
  mini_object: GstMiniObject
  pool: ptr GstBufferPool
  pts, dts, duration: GstClockTime
  offset, offset_end: uint64

type GstMapInfo = object
  memory: ptr GstMemory
  flags: GstMapFlags
  data: ptr uint8
  size, maxsize: csize

const GST_CLOCK_TIME_NONE = -1
const GST_MAP_READ = 1
const GST_MAP_WRITE = 2
const GST_MESSAGE_EOS = 1
const GST_STATE_CHANGE_FAILURE = 0
const GST_STATE_NULL = 1
const GST_STATE_PLAYING = 4

{.push callConv: cDecl, dynLib: gStreamerPath, importC.}

proc gst_bin_get_by_name(bin: ptr GstBin, name: cstring): ptr GstElement

proc gst_buffer_map(buffer: ptr GstBuffer, info: ptr GstMapInfo,
                    flags: GstMapFlags): bool

proc gst_buffer_new_allocate(allocator: ptr GstAllocator, size: csize,
                             params: ptr GstAllocationParams): ptr GstBuffer

proc gst_buffer_unmap(buffer: ptr GstBuffer, info: ptr GstMapInfo)

proc gst_caps_get_structure(caps: ptr GstCaps, index: cuint): ptr GstStructure

proc gst_element_get_bus(element: ptr GstElement): ptr GstBus

proc gst_element_get_state(element: ptr GstElement, state: ptr GstState,
                           pending: ptr GstState, timeout: GstClockTime):
                           GstStateChangeReturn

proc gst_element_get_static_pad(element: ptr GstElement, name: cstring):
                                ptr GstPad

proc gst_element_send_event(element: ptr GstElement, event: ptr GstEvent): bool

proc gst_element_set_state(element: ptr GstElement, state: GstState):
                           GstStateChangeReturn

proc gst_event_new_eos(): ptr GstEvent

proc gst_init(argc: ptr cint, argv: ptr ptr cstring)

proc gst_mini_object_unref(sample: ptr GstMiniObject)

proc gst_object_unref(obj: pointer)

proc gst_pad_get_current_caps(pad: ptr GstPad): ptr GstCaps

proc gst_parse_launch(pipeline_description: cstring, error: ptr ptr GError):
                      ptr GstElement

proc gst_bus_timed_pop_filtered(bus: ptr GstBus, timeout: GstClockTime,
                                types: GstMessageType): ptr GstMessage

proc gst_sample_get_buffer(sample: ptr GstSample): ptr GstBuffer

proc gst_structure_get_int(structure: ptr GstStructure, fieldname: cstring,
                           value: ptr cint): bool
{.pop.}

#===============================================================================
# URI Construction

proc isUri(path: string): bool =
  (path.startsWith("https://") or
   path.startsWith("http://") or
   path.startsWith("file://"))

proc asUri(path: string): string =
  if path.isUri:
    path
  elif path.isAbsolute:
    "file://" & path
  else:
    "file://" & getCurrentDir() / path

#===============================================================================
# Sound

# type Sound* = DenseGrid[tuple[s, c: int], float32]
# proc nSamples*(sound: Sound): int = sound.size[0]
# proc nChannels*(sound: Sound): int = sound.size[1]

type Sound* = object
  nSamples, nChannels: int
  data: seq[float32]

proc newSound*(nSamples: int, nChannels = 2): Sound =
  Sound(nSamples: nSamples, nChannels: nChannels,
        data: newSeq[float32](nSamples * nChannels))

proc nSamples*(sound: Sound): int =
  sound.nSamples

proc nChannels*(sound: Sound): int =
  sound.nChannels

proc `[]`*(sound: Sound, s, c: int): float32 =
  sound.data[sound.nChannels * s + c]

proc `[]=`*(sound: var Sound, s, c: int, v: float32) =
  sound.data[sound.nChannels * s + c] = v

#===============================================================================
# Image

# type Image* = DenseGrid[tuple[h, w, c: int], float32]
# proc height*(image: Image): int = image.size[0]
# proc width*(image: Image): int = image.size[1]
# proc nChannels*(image: Image): int = image.size[2]

type Image* = object
  height, width, nChannels: int
  data: seq[float32]

proc newImage*(height, width: int, nChannels = 3): Image =
  Image(height: height, width: width, nChannels: nChannels,
        data: newSeq[float32](height * width * nChannels))

proc height*(image: Image): int = image.height
proc width*(image: Image): int = image.width
proc nChannels*(image: Image): int = image.nChannels

proc `[]`*(image: Image, y, x, c: int): float =
  image.data[image.width * image.nChannels * y + image.nChannels * x + c]

proc `[]=`*(image: var Image, y, x, c: int, v: float) =
  image.data[image.width * image.nChannels * y + image.nChannels * x + c] = v

#===============================================================================
# AudioSource

type AudioSourceObj = object
  pipe: ptr GstElement

type AudioSource* = ref AudioSourceObj

proc tearDownPipeline(source: AudioSource) =
  if source.pipe != nil:
    discard gst_element_set_state(source.pipe, GST_STATE_NULL)
    gst_object_unref(source.pipe)

proc newAudioSource*(path=""): AudioSource =
  gst_init(nil, nil)
  let pipe =
    if path == "":
      gst_parse_launch(
        "autoaudiosrc ! audioconvert ! audioresample ! appsink name=appsink " &
        "max-buffers=1 drop=true caps=audio/x-raw,rate=44100,channels=2," &
        "format=F32LE,layout=interleaved", nil)
    else:
      gst_parse_launch(
        "uridecodebin uri=" & path.asUri & " ! audioconvert ! " &
        "audioresample ! appsink name=appsink caps=audio/x-raw,rate-44100," &
        "channels=2,format=F32LE,layout=interleaved", nil)

  let stateChange = gst_element_set_state(pipe, GST_STATE_PLAYING)
  discard gst_element_get_state(pipe, nil, nil, GST_CLOCK_TIME_NONE)

  if state_change == GST_STATE_CHANGE_FAILURE:
    gst_object_unref(pipe)
    let errorMessage =
      if path == "": "No microphone is available."
      else: "The target file is inaccessible or does not exist."
    raise newException(IOError, errorMessage)

  new(result, tearDownPipeline)
  result.pipe = pipe

proc read*(source: AudioSource): Optional[Sound] =
  assert source.pipe != nil
  var mapInfo: GstMapInfo
  var sample: ptr GstSample
  let appSink = gst_bin_get_by_name(cast[ptr GstBin](source.pipe), "appsink")
  g_signal_emit_by_name(appSink, "pull-sample", addr sample, nil)

  let buffer = gst_sample_get_buffer(sample)
  discard gst_buffer_map(buffer, addr mapInfo, GST_MAP_READ)
  let nSamples = mapInfo.size div sizeOf(float32) div 2
  result = newSound(nSamples, 2)

  for i in 0 .. <(2 * nSamples):
    let entry = cast[ptr float32](cast[int](mapInfo.data) + 4 * i)[]
    result.value.data[i] = entry

  gst_object_unref(appSink)
  gst_buffer_unmap(buffer, addr mapInfo)
  gst_mini_object_unref(cast[ptr GstMiniObject](sample))

proc close*(source: AudioSource) =
  tearDownPipeline(source)
  source.pipe = nil

iterator items*(source: AudioSource): Sound =
  while true:
    let clip = source.read
    if clip.hasValue: yield clip.value
    else: break

#===============================================================================
# VideoSource

type VideoSourceObj = object
  height, width: int
  pipe: ptr GstElement

type VideoSource* = ref VideoSourceObj

proc tearDownPipeline(source: VideoSource) =
  if source.pipe != nil:
    discard gst_element_set_state(source.pipe, GST_STATE_NULL)
    gst_object_unref(source.pipe)

proc newVideoSource*(path=""): VideoSource =
  gst_init(nil, nil)
  let pipe =
    if path == "":
      gst_parse_launch(
        "autovideosrc ! videoconvert ! appsink name=appsink max-buffers=1 " &
        "drop=true caps=video/x-raw,format=RGB", nil)
    else:
      gst_parse_launch(
        "uridecodebin uri=" & path.asUri & " ! videoconvert ! appsink " &
        "name=appsink caps=video/x-raw,format=RGB", nil)

  let stateChange = gst_element_set_state(pipe, GST_STATE_PLAYING)
  discard gst_element_get_state(pipe, nil, nil, GST_CLOCK_TIME_NONE)

  if stateChange == GST_STATE_CHANGE_FAILURE:
    gst_object_unref(pipe)
    let errorMessage =
      if path == "": "No camera is available."
      else: "The target file is inaccessible or does not exist."
    raise newException(IOError, errorMessage)

  let appSink = gst_bin_get_by_name(cast[ptr GstBin](pipe), "appsink")
  let pad = gst_element_get_static_pad(appSink, "sink")
  let caps = gst_pad_get_current_caps(pad)
  let capStruct = gst_caps_get_structure(caps, 0)
  var height, width: cint
  discard gst_structure_get_int(cap_struct, "height", addr height)
  discard gst_structure_get_int(cap_struct, "width", addr width)
  gst_mini_object_unref(cast[ptr GstMiniObject](caps))
  gst_object_unref(appSink)
  gst_object_unref(pad)

  new(result, tearDownPipeline)
  result.height = height
  result.width = width
  result.pipe = pipe

proc read*(source: var VideoSource): Optional[Image] =
  assert source.pipe != nil
  var mapInfo: GstMapInfo
  var sample: ptr GstSample
  let appSink = gst_bin_get_by_name(cast[ptr GstBin](source.pipe), "appsink")
  g_signal_emit_by_name(appSink, "pull-sample", addr sample, nil)

  let buffer = gst_sample_get_buffer(sample)
  discard gst_buffer_map(buffer, addr mapInfo, GST_MAP_READ)
  result = newImage(source.height, source.width, 3)

  for i in 0 .. <(source.height * source.width * 3):
    let entry = cast[ptr uint8](cast[int](mapInfo.data) + i)[]
    result.value.data[i] = 1/255 * float32(entry)

  gst_object_unref(appSink)
  gst_buffer_unmap(buffer, addr mapInfo)
  gst_mini_object_unref(cast[ptr GstMiniObject](sample))

proc close*(source: var VideoSource) =
  tearDownPipeline(source)
  source.pipe = nil

iterator items*(source: var VideoSource): Image =
  while true:
    let frame = source.read
    if frame.hasValue: yield frame.value
    else: break

#===============================================================================
# AudioSink

type AudioSinkObj = object
  path: string
  time: float
  pipe: ptr GstElement
  nChannels: int
  hasBeenOpened: bool

type AudioSink* = ref AudioSinkObj

proc setUpPipeline(sink: AudioSink) =
  let gstSourceDesc =
    "appsrc name=appsrc format=time block=true max-bytes=1 caps=audio/x-raw," &
    "rate=44100,channels=" & $sink.nChannels & ",format=F32LE," &
    "layout=interleaved ! audioconvert ! audioresample"
  let gstSinkDesc =
    if sink.path == "":
      "autoaudiosink"
    elif sink.path.endsWith(".webm"):
      "vorbisenc ! webmmux ! filesink location=" & sink.path
    else:
      "vorbisenc ! oggmux ! filesink location=" & sink.path

  sink.pipe = gst_parse_launch(gstSourceDesc & " ! " & gstSinkDesc, nil)
  let stateChange = gst_element_set_state(sink.pipe, GST_STATE_PLAYING)

  if stateChange == GST_STATE_CHANGE_FAILURE:
    gst_object_unref(sink.pipe)
    let errorMessage =
      if sink.path == "": "No audio output is available."
      else: "The target file is inaccessible or does not exist."
    raise newException(IOError, errorMessage)
  else:
    sink.hasBeenOpened = true

proc tearDownPipeline(sink: AudioSink) =
  if sink.pipe != nil:
    let bus = gst_element_get_bus(sink.pipe)
    let appSource = gst_bin_get_by_name(cast[ptr GstBin](sink.pipe), "appsrc")
    discard gst_element_send_event(sink.pipe, gst_event_new_eos())
    discard gst_bus_timed_pop_filtered(bus, GST_CLOCK_TIME_NONE,
                                       GST_MESSAGE_EOS)
    gst_object_unref(appSource)
    gst_object_unref(bus)
    discard gst_element_set_state(sink.pipe, GST_STATE_NULL)
    gst_object_unref(sink.pipe)

proc newAudioSink*(path=""): AudioSink =
  gst_init(nil, nil)
  new(result, tearDownPipeline)
  result.path = path

proc write*(sink: AudioSink, clip: Sound) =
  if not sink.hasBeenOpened:
    assert clip.nChannels in {1, 2}
    sink.nChannels = clip.nChannels
    setUpPipeline(sink)
  else:
    assert sink.pipe != nil
    assert clip.nChannels == sink.nChannels

  var mapInfo: GstMapInfo
  let nElements = clip.nSamples * clip.nChannels
  var buffer = gst_buffer_new_allocate(nil, 4 * nElements, nil)
  discard gst_buffer_map(buffer, addr mapInfo, GST_MAP_WRITE)

  for i in 0 .. <nElements:
    var outputPtr = cast[ptr float32](cast[int](mapInfo.data) + 4 * i)
    outputPtr[] = clip.data[i]

  gst_buffer_unmap(buffer, addr mapInfo)
  buffer.pts = int(1_000_000_000 * sink.time)
  buffer.duration = int(1_000_000_000 * clip.nSamples / 44_100)
  sink.time += clip.nSamples / 44_100

  var flowResult: GstFlowReturn
  let appSource = gst_bin_get_by_name(cast[ptr GstBin](sink.pipe), "appsrc")
  g_signal_emit_by_name(appSource, "push-buffer", buffer, addr flowResult)
  gst_object_unref(appSource)
  gst_mini_object_unref(cast[ptr GstMiniObject](buffer))

proc close*(sink: AudioSink) =
  tearDownPipeline(sink)
  sink.pipe = nil

#===============================================================================
# VideoSink

type VideoSinkObj = object
  path: string
  time, frameRate: float
  pipe: ptr GstElement
  height, width, nChannels: int
  hasBeenOpened: bool

type VideoSink = ref VideoSinkObj

proc setUpPipeline(sink: VideoSink) =
  const formats = ["", "GRAY8", "", "RGB", "RGBA"]
  let format = formats[sink.nChannels]
  let gstSourceDesc =
    "appsrc name=appsrc format=time block=true max-bytes=1 caps=video/x-raw," &
    "width=" & $sink.width & ",height=" & $sink.height & ",framerate=" &
    $int(1000 * sink.frameRate) & "/1000,format=" & format & " ! videoconvert"
  let gstSinkDesc =
    if sink.path == "":
      "autovideosink"
    elif sink.path.endsWith(".webm"):
      "vp8enc ! webmmux ! filesink location=" & sink.path
    else:
      "theoraenc ! oggmux ! filesink location=" & sink.path

  sink.pipe = gst_parse_launch(gstSourceDesc & " ! " & gstSinkDesc, nil)
  let stateChange = gst_element_set_state(sink.pipe, GST_STATE_PLAYING)

  if stateChange == GST_STATE_CHANGE_FAILURE:
    gst_object_unref(sink.pipe)
    let errorMessage =
      if sink.path == "": "No display is available."
      else: "The target file is inaccessible or does not exist."
    raise newException(IOError, errorMessage)
  else:
    sink.hasBeenOpened = true

proc tearDownPipeline(sink: VideoSink) =
  if sink.pipe != nil:
    let bus = gst_element_get_bus(sink.pipe)
    let appSource = gst_bin_get_by_name(cast[ptr GstBin](sink.pipe), "appsrc")
    discard gst_element_send_event(sink.pipe, gst_event_new_eos())
    discard gst_bus_timed_pop_filtered(bus, GST_CLOCK_TIME_NONE,
                                       GST_MESSAGE_EOS)
    gst_object_unref(appSource)
    gst_object_unref(bus)
    discard gst_element_set_state(sink.pipe, GST_STATE_NULL)
    gst_object_unref(sink.pipe)

proc newVideoSink*(path="", frameRate=30.0): VideoSink =
  gst_init(nil, nil)
  new(result, tearDownPipeline)
  result.path = path
  result.frameRate = frameRate

proc write*(sink: VideoSink, frame: Image) =
  if not sink.hasBeenOpened:
    assert frame.nChannels in {1, 3, 4}
    sink.height = frame.height
    sink.width = frame.width
    sink.nChannels = frame.nChannels
    setUpPipeline(sink)
  else:
    assert sink.pipe != nil
    assert frame.height == sink.height
    assert frame.width == sink.width
    assert frame.nChannels == sink.nChannels

  var mapInfo: GstMapInfo
  let nElements = frame.width * frame.height * frame.nChannels
  var buffer = gst_buffer_new_allocate(nil, nElements, nil)
  discard gst_buffer_map(buffer, addr mapInfo, GST_MAP_WRITE)

  for i in 0 .. <nElements:
    var outputPtr = cast[ptr uint8](cast[int](mapInfo.data) + i)
    outputPtr[] = uint8(int(255 * frame.data[i]))

  gst_buffer_unmap(buffer, addr mapInfo)
  buffer.pts = int(1_000_000_000 * sink.time)
  buffer.duration = int(1_000_000_000 / sink.frameRate)
  sink.time += 1 / sink.frameRate

  var flowResult: GstFlowReturn
  let appSource = gst_bin_get_by_name(cast[ptr GstBin](sink.pipe), "appsrc")
  g_signal_emit_by_name(appSource, "push-buffer", buffer, addr flowResult)
  gst_object_unref(appSource)
  gst_mini_object_unref(cast[ptr GstMiniObject](buffer))

proc close*(sink: VideoSink) =
  tearDownPipeline(sink)
  sink.pipe = nil
