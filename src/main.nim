import tables
import strutils
import strformat
import osproc
import os
import gintro/[glib, gobject, gtk]
import gintro/gio except ListStore

const
  N_COLUMNS = 2
  DELAY = 750 # ms

var path = ""
var rgArgs = "-i --max-depth 3"
var list: TreeView
var running = true
var mainChannel: Channel[Table[string, seq[string]]] # send to main
var workChannel: Channel[tuple[path: string, args: string, msg: string]] # send to work
var workThread: system.Thread[void]

proc workProc =
  while running:
    let msg = workChannel.tryRecv()
    if msg.dataAvailable:
      let (basePath, tArgs, pattern) = msg.msg
      if len(pattern) > 1:
        let command = &"rg -n {tArgs} {pattern.quoteShell} {basePath.quoteShell}"
        # TODO stream output
        let (output, code) = execCmdEx(command)
        if code == 0:
          var results = initTable[string, seq[string]]()
          for outputLine in output.split(Newlines):
            var line: string
            var prependPath = ""
            # TODO use regex
            if outputLine.contains("C:"):
              line = outputLine.replace("C:", "")
              prependPath = "C:"
            else:
              line = outputLine

            let parts = line.split(":", 2)
            if len(parts) == 3:
              let file = &"{prependPath}{parts[0]} ({parts[1]})"
              let match = parts[2]

              if file notin results:
                results[file] = newSeq[string]()
              results[file].add(match)

          mainChannel.send(results)
    else:
      sleep(DELAY)

# we need the following two procs for now -- later we will not use that ugly cast...
proc typeTest(o: gobject.Object; s: string): bool =
  let gt = g_type_from_name(s)
  return g_type_check_instance_is_a(cast[ptr TypeInstance00](o.impl), gt).toBool

proc listStore(o: gobject.Object): gtk.ListStore =
  assert(typeTest(o, "GtkListStore"))
  cast[gtk.ListStore](o)

proc appendItem(filename, text: string) =
  var
    val: Value
    fval: Value
    iter: TreeIter
  let store = listStore(getModel(list))
  let gtype = gStringGetType()
  discard init(val, gtype)
  discard init(fval, gtype)
  setString(val, text)
  setString(fval, filename)
  store.append(iter)
  store.setValue(iter, 0, fval)
  store.setValue(iter, 1, val)

proc removeResults =
  var
    iter: TreeIter
  let store = list.getModel.listStore
  if not store.getIterFirst(iter):
    return
  clear(store)

proc showResults(entry: Entry): bool =
  let msg = mainChannel.tryRecv()

  if msg.dataAvailable:
    let results = msg.msg
    removeResults()
    for file, matches in pairs(results):
      for match in matches:
        appendItem(file, match)

  if not running:
    return SOURCE_REMOVE

  return SOURCE_CONTINUE

proc initList(list: TreeView) =
  let renderer = newCellRendererText()

  let column1 = newTreeViewColumn()
  column1.setTitle("File")
  column1.packStart(renderer, true)
  column1.addAttribute(renderer, "text", 0)
  discard list.appendColumn(column1)

  let column2 = newTreeViewColumn()
  column2.setTitle("Match")
  column2.packStart(renderer, true)
  column2.addAttribute(renderer, "text", 1)
  discard list.appendColumn(column2)

  let gtype = [gStringGetType(), gStringGetType()]
  let store = newListStore(N_COLUMNS, cast[ptr GType](unsafeaddr gtype))
  list.setModel(store)
  list.setHeadersVisible()
  list.setGridLines(TreeViewGridLines.horizontal)

proc search(entry: Entry) =
  workChannel.send((path, rgArgs, entry.text))

proc setArgs(entry: Entry) =
  rgArgs = entry.text

proc setPath(data: FileChooserButton) =
  path = data.getFilename()

proc appActivate(app: Application) =
  let
    window = newApplicationWindow(app)
    sw = newScrolledWindow()
    hbox = newBox(Orientation.horizontal, 5)
    hboxArgs = newBox(Orientation.horizontal, 5)
    vbox = newBox(Orientation.vertical, 0)
    argsEntry = newEntry()
    pathPicker = newFileChooserButton("Path...", FileChooserAction.selectFolder)
    entry = newEntry()

  argsEntry.text = rgArgs

  window.title = "guirg"
  window.position = WindowPosition.center
  window.borderWidth = 10
  window.setSizeRequest(500, 400)

  list = newTreeView()
  sw.add(list)
  sw.setPolicy(PolicyType.automatic, PolicyType.automatic)
  sw.setShadowType(ShadowType.etchedIn)
  list.setHeadersVisible(false)

  vbox.packStart(sw, true, true, 5)
  hbox.packStart(entry, true, true, 3)
  hboxArgs.packStart(argsEntry, true, true, 3)
  hboxArgs.packStart(pathPicker, false, true, 3)
  vbox.packStart(hbox, false, true, 3)
  vbox.packStart(hboxArgs, false, true, 3)
  window.add(vbox)

  pathPicker.connect("file-set", setPath)
  entry.connect("changed", search)
  argsEntry.connect("changed", setArgs)

  initList(list)
  showAll(window)

  mainChannel.open()
  workChannel.open()
  createThread(workThread, workProc)

  discard timeoutAdd(DELAY, showResults, entry)

proc main =
  let app = newApplication("org.gtk.example")
  connect(app, "activate", appActivate)
  discard run(app)

  running = false
  workThread.joinThread()
  mainChannel.close()
  workChannel.close()

main()
