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
      root.current = data
    })
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

  // --- Copy the comic image to the Wayland clipboard -----------------------
  // "" | "copying" | "done" | "error", shown transiently by the view.
  property string copyStatus: ""

  Timer { id: copyReset; interval: 1600; onTriggered: root.copyStatus = "" }

  function copyImage(comic) {
    var url = imageUrl(comic)
    if (!url || copyProc.running) return
    var type = /\.jpe?g(\?|$)/i.test(url) ? "image/jpeg" : "image/png"
    // Stream the image straight from xkcd into wl-copy so nothing touches
    // disk. HTTPS only, no redirects (-L dropped), and hard size/time caps so
    // even a hostile server can't stream unbounded data into the clipboard.
    copyProc.command = ["sh", "-c",
      "curl -fsS --proto '=https' --max-filesize 20971520 --max-time 30 \"$1\" | wl-copy --type \"$2\"", "sh", url, type]
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
