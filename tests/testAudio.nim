import pipelines
import mio

let source = newAudioSource()
let sink = newAudioSink()
source.take(512).readInto(sink)
close source
close sink
