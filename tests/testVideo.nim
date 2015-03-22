import pipelines
import mio

let source = newVideoSource()
let sink = newVideoSink()
source.take(128).readInto(sink)
close source
close sink
