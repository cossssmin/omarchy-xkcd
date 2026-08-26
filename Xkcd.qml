import QtQuick
import Quickshell
import Quickshell.Io

// xkcd fetch engine. Talks to the public search API
// (api.xkcdsearch.workers.dev), which mirrors xkcd's own info.0.json response
// shape and adds a /search endpoint with full-text ranking over title, alt
// text, and transcript. Hosts bind their UI to `current`, `results`, `mode`.
Item {
  id: root

  readonly property string base: "https://api.xkcdsearch.workers.dev"

  // "latest" | "number" | "search"
  property string mode: "latest"
  property var current: null      // comic object shown in the preview
  property var results: []        // search hit rows (comic objects)
  property string query: ""
  property bool loading: false
  property string error: ""

  // Guard against a runaway body (search returns transcripts; still tiny, but
  // never buffer without bound). QML's XHR exposes partial responseText from
  // LOADING onward, so we can abort mid-download the moment it exceeds this.
  readonly property int maxResponseBytes: 1048576

  // Bumped on every new request; late callbacks from a superseded request
  // compare against it and bail, so out-of-order responses can't clobber state.
  property int generation: 0
  property var inflight: null

  function abortInflight() {
    if (root.inflight) {
      try { root.inflight.abort() } catch (e) {}
      root.inflight = null
    }
  }

  function overLimit(xhr) {
    if (xhr.readyState === XMLHttpRequest.LOADING
        && xhr.responseText.length > root.maxResponseBytes) {
      xhr.abort()
      return true
    }
    return false
  }

  function begin() {
    root.generation++
    root.abortInflight()
    root.error = ""
    root.loading = true
    return root.generation
  }

  function fail(msg) {
    root.loading = false
    root.error = msg
  }

  // GET `path`, parse JSON, invoke onOk(data) on 200 and onOk(null) on 404 so
  // the caller can phrase its own not-found message. Other statuses -> error.
  function get(path, gen, onOk) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", root.base + path)
    xhr.timeout = 10000
    xhr.onreadystatechange = function() {
      if (root.overLimit(xhr)) { if (gen === root.generation) root.fail("Response too large"); return }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (gen !== root.generation) return
      root.loading = false
      root.inflight = null
      if (xhr.status === 200) {
        var data = null
        try { data = JSON.parse(xhr.responseText) } catch (e) { root.fail("Could not read response"); return }
        onOk(data)
      } else if (xhr.status === 404) {
        onOk(null)
      } else if (xhr.status === 0) {
        root.fail("Network error — is the machine online?")
      } else {
        root.fail("Server error (" + xhr.status + ")")
      }
    }
    root.inflight = xhr
    xhr.send()
  }

  function loadLatest() {
    var gen = begin()
    root.mode = "latest"
    root.results = []
    root.query = ""
    get("/latest", gen, function(data) {
      if (!data) { root.fail("Could not load the latest comic"); return }
      root.latestNum = data.num
      root.current = data
    })
  }

  // Highest known comic number, learned from /latest; shuffle picks below it.
  property int latestNum: 0

  function shuffle() {
    if (root.latestNum > 0) { loadRandomNumber(); return }
    var gen = begin()
    get("/latest", gen, function(data) {
      if (!data) { root.fail("Could not load the latest comic"); return }
      root.latestNum = data.num
      loadRandomNumber()
    })
  }

  function loadRandomNumber() {
    var n
    // #404 famously doesn't exist.
    do { n = 1 + Math.floor(Math.random() * root.latestNum) } while (n === 404)
    loadNumber(n)
  }

  function loadNumber(n) {
    var gen = begin()
    root.mode = "number"
    root.results = []
    root.query = ""
    get("/" + n, gen, function(data) {
      if (!data) { root.current = null; root.fail("No comic #" + n); return }
      root.current = data
    })
  }

  function search(q) {
    var gen = begin()
    root.mode = "search"
    root.query = q
    get("/search?q=" + encodeURIComponent(q) + "&limit=24", gen, function(data) {
      var rows = (data && data.results) ? data.results : []
      root.results = rows
      root.current = rows.length ? rows[0] : null
      if (!rows.length) root.error = "No comics match “" + q + "”"
    })
  }

  // Decide what a raw input string means, then run it.
  function run(raw) {
    var s = (raw || "").trim()
    if (s === "") { loadLatest(); return }
    if (/^\d+$/.test(s)) { loadNumber(parseInt(s, 10)); return }
    search(s)
  }

  function select(i) {
    if (i >= 0 && i < root.results.length) root.current = root.results[i]
  }

  // Only load comic images from xkcd's own image host, over HTTPS. The API is
  // trusted for comic data, but a compromised response could point `img` at
  // file://, localhost, or an unbounded stream.
  function imageUrl(comic) {
    var url = comic && comic.img ? String(comic.img) : ""
    return /^https:\/\/imgs\.xkcd\.com\//.test(url) ? url : ""
  }

  function openComic(comic) {
    if (!comic || !comic.num) return
    Quickshell.execDetached(["xdg-open", "https://xkcd.com/" + comic.num])
  }

  function openExplain(comic) {
    if (!comic || !comic.num) return
    Quickshell.execDetached(["xdg-open", "https://www.explainxkcd.com/wiki/index.php/" + comic.num])
  }

  // --- Comic image transport -----------------------------------------------
  // QML Image's own network fetch follows redirects wherever the server
  // points it, so the shell never gives it a network URL. The bytes travel
  // through the same hardened curl as copyImage and reach Image as a data:
  // URL instead.
  property string imageData: ""
  property bool imageFailed: false
  property int imageGen: 0
  property string pendingImageUrl: ""

  onCurrentChanged: fetchImage()

  function fetchImage() {
    var url = imageUrl(root.current)
    root.imageGen++
    root.imageFailed = false
    root.imageData = ""
    if (!url) { root.imageFailed = root.current !== null; return }
    root.pendingImageUrl = url
    // A running fetch is stale now; kill it and let onExited start this one.
    if (imgProc.running) { imgProc.running = false; return }
    startImageProc()
  }

  function startImageProc() {
    var url = root.pendingImageUrl
    root.pendingImageUrl = ""
    if (!url) return
    imgProc.mime = /\.jpe?g(\?|$)/i.test(url) ? "image/jpeg" : "image/png"
    imgProc.gen = root.imageGen
    // pipefail + head -c (cap + 1): a response larger than the cap SIGPIPEs
    // curl and fails the pipeline, so the collector can never buffer more
    // than cap + 1 bytes worth of base64 no matter what the server streams.
    imgProc.command = ["sh", "-c",
      "set -o pipefail; curl -fsS --proto '=https' --max-filesize 20971520 --max-time 30 \"$1\" | head -c 20971521 | base64 -w0", "sh", url]
    imgProc.running = true
  }

  Process {
    id: imgProc
    property int gen: 0
    property string mime: "image/png"
    stdout: StdioCollector { id: imgOut; waitForEnd: true }
    // Base64 length of exactly maxImageBytes; anything longer means head hit
    // its cap on a response that ended right at cap + 1 bytes without
    // tripping pipefail, i.e. a truncated image — reject, never render it.
    readonly property int maxB64: Math.ceil(20971520 / 3) * 4
    onExited: function(code) {
      if (root.pendingImageUrl !== "") { root.startImageProc(); return }
      if (gen !== root.imageGen) return
      if (code === 0 && imgOut.text.length > 0 && imgOut.text.length <= maxB64)
        root.imageData = "data:" + mime + ";base64," + imgOut.text
      else
        root.imageFailed = true
    }
  }

  // --- Copy the comic image to the Wayland clipboard -----------------------
  // "" | "copying" | "done" | "error", shown transiently by the view.
  property string copyStatus: ""

  Timer { id: copyReset; interval: 1600; onTriggered: root.copyStatus = "" }

  function copyImage(comic) {
    var url = imageUrl(comic)
    if (!url || copyProc.running) return
    var type = /\.jpe?g(\?|$)/i.test(url) ? "image/jpeg" : "image/png"
    // Buffer in XDG_RUNTIME_DIR (tmpfs) with a hard byte cap before wl-copy
    // ever sees the data: pipefail + head -c (cap + 1) bound the stream, and
    // the size check rejects a capped partial so a truncated image can never
    // land in the clipboard as if it were the real one.
    copyProc.command = ["sh", "-c",
      'set -o pipefail; f=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/xkcd-copy.XXXXXX") || exit 1; ' +
      'trap \'rm -f "$f"\' EXIT; ' +
      'curl -fsS --proto \'=https\' --max-filesize 20971520 --max-time 30 "$1" | head -c 20971521 > "$f" || exit 1; ' +
      '[ "$(wc -c < "$f")" -le 20971520 ] || exit 1; ' +
      'wl-copy --type "$2" < "$f"', "sh", url, type]
    root.copyStatus = "copying"
    copyReset.stop()
    copyProc.running = true
  }

  Process {
    id: copyProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.copyStatus = (code === 0) ? "done" : "error"
      copyReset.restart()
    }
  }

  Component.onCompleted: loadLatest()
}
