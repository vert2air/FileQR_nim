import wNim/wNim/[wApp, wBitmap, wBrush, wButton, wComboBox, wFileDialog,
  wFrame, wImage, wMemoryDC, wPaintDC, wPanel, wRadioButton, wStaticBox,
  wStaticText, wStatusBar, wTextCtrl, ]
import qr
import std/[base64, paths, re, strformat, strutils, tables]
import checksums/sha1

let list_err = {
  "L( 7%)": (Ecc_LOW,      2_953),
  "M(15%)": (Ecc_MEDIUM,   2_331),
  "Q(25%)": (Ecc_QUARTILE, 1_663),
  "H(30%)": (Ecc_HIGH,     1_272),
}.toOrderedTable

proc num2bin2(number: int): string =
  [ fmt"{char((number shr  0) and 0xff)}",
    fmt"{char((number shr  8) and 0xff)}",
  ].join()

proc num2bin4(number: int): string =
  [ fmt"{char((number shr  0) and 0xff)}",
    fmt"{char((number shr  8) and 0xff)}",
    fmt"{char((number shr 16) and 0xff)}",
    fmt"{char((number shr 24) and 0xff)}",
  ].join()

proc make_qr_data(filename: string, data: string, err_cor: string): seq[seq[string]] =
  result = @[]
  let base64data: string = filename & ":" & data.encode()
  let size_per_qr: int = list_err[err_cor][1] - fmt"12345678:001:100:".len()
  let qrHash: string = ($secureHash(base64data & err_cor))[0..7]
  let last_len: int = base64data.len() mod size_per_qr
  let total: int = (base64data.len() + size_per_qr - 1) div size_per_qr

  for offset in countup(0, base64data.len() - last_len - 1, size_per_qr):
    var qrOrder: seq[string] = @[]
    for qrRevLine in qrBinary(
            fmt"{qrHash}:{result.len:03d}:{total:03d}:" & base64data[offset ..< offset + size_per_qr],
            eccLevel=list_err[err_cor][0]).splitLines:
      if qrRevLine.len() > 0:
        qrOrder.insert(qrRevLine, 0)
    result.add(qrOrder)
  if last_len > 0:
    var qrOrder: seq[string] = @[]
    for qrRevLine in qrBinary(
              fmt"{qrHash}:{result.len:03d}:{total:03d}:" & base64data[result.len * size_per_qr .. ^1],
              eccLevel=list_err[err_cor][0]).splitLines:
      if qrRevLine.len() > 0:
        qrOrder.insert(qrRevLine, 0)
    result.add(qrOrder)

proc decode_qr_data(data: string) =
  var acc = initTable[string, seq[string]]()
  for line in data.splitLines:
    var matches: array[4, string]
    if match(line, re".*([0-9a-fA-f]{8}):(000):(\d{3}):(.*:[0-9A-Za-z+/]*=*).*", matches):
      # pass
      discard matches
    elif match(line, re".*([0-9a-fA-f]{8}):(\d{3}):(\d{3}):([0-9A-Za-z+/]*=*).*", matches):
      # pass
      discard matches
    else:
      # フォーマットが違った。
      echo fmt"discard line : illegal format : '{line}'"
      continue
    let hash = matches[0]
    let myIndex = matches[1].parseInt
    let totalIndex = matches[2].parseInt
    let nameAndBase64 = matches[3]
    if myIndex >= totalIndex:
      # この行のindexが総長を超えた。
      echo "discard line : too big myIndex"
      continue
    if hash in acc:
        # 既出のエントリだった。
        if totalIndex != acc[hash].len:
          # 総長が既出の値と違った。
          echo "discard line : existed totalIndex different"
          continue
        if acc[hash][myIndex] != "":
          # 処理済みのindexだった。
          echo "discard line : duplicate index"
          continue
    else:
      # 新出のエントリだった。
      acc[hash] = newSeq[string](totalIndex)
      echo fmt"add new hash : {hash}"
    acc[hash][myIndex] = nameAndBase64
  for hash in acc.keys:
    var lack = false
    for line in acc[hash]:
      if line == "":
        echo "not complete"
        lack = true
        break
    if lack:
      continue
    echo fmt"output for hash : {hash}"
    var matches: array[2, string]
    if match(acc[hash].join, re"^(.*):(.*)$", matches):
      let filename = matches[0]
      let base64data = matches[1]
      echo fmt"file name : {filename}"
      block:
        let outFile = open(filename, FileMode.fmWrite)
        defer:
          outFile.close
        outFile.write(base64data.decode)

proc qr_data_to_pbm(pbm_fn: string, qrbin: string) =
  let line_len = qrbin.find("\n")
  block:
    let f: File = open(pbm_fn, FileMode.fmWrite)
    defer:
      close(f)
    f.write("P1\n")
    f.write(fmt"{line_len} {line_len}" & "\n")
    f.write(qrbin)

proc qr_data_to_bmp(bmp_fn: string, qrLine: seq[string], magnify: int = 1, margin: int = 20) =
  # BMPファイルフォーマット
  # https://www.setsuki.com/hsp/ext/bmp.htm
  let line_count = qrLine.len()
  let bmp_size: int = line_count * magnify + 2 * margin
  block:
    let f: File = open(bmp_fn, FileMode.fmWrite)
    defer:
      f.close()
    f.write('B') # bfType
    f.write('M') # bfType
    let data_size: int = ((3 * bmp_size + 3) div 4) * 4 * bmp_size
    f.write(num2bin4(14 + 40 + data_size)) # bfSize
    f.write(num2bin2(0)) # bfReserved1
    f.write(num2bin2(0)) # bfReserved2
    f.write(num2bin4(14 + 40)) # bfOffBits

    f.write(num2bin4(40)) # bcSize
    f.write(num2bin4(bmp_size)) # bcWidth
    f.write(num2bin4(bmp_size)) # bcHeight
    f.write(num2bin2(1)) # bcPlanes
    f.write(num2bin2(24)) # bcBitCount

    f.write(num2bin4(0)) # biComression 0:BI_RGB
    f.write(num2bin4(data_size)) # biSizeImage
    f.write(num2bin4(0)) # biXPixPerMeter
    f.write(num2bin4(0)) # biYPixPerMeter
    f.write(num2bin4(0)) # biClrUsed
    f.write(num2bin4(0)) # biClrImportant

    for m in 1 .. margin:
      for ix in 1 .. bmp_size:
        f.write(fmt"{char(0xff)}{char(0xff)}{char(0xff)}")
      for ix in (3 * bmp_size mod 4) ..< 4:
        f.write(fmt"{char(0x00)}")

    for line in qrLine:
      for mag in 1 .. magnify:
        for ix in 1 .. margin:
          f.write(fmt"{char(0xff)}{char(0xff)}{char(0xff)}")
        for ch in line:
          case ch:
          of '0':
            for mag in 1 .. magnify:
              f.write(fmt"{char(0xff)}{char(0xff)}{char(0xff)}")
          of '1':
            for mag in 1 .. magnify:
              f.write(fmt"{char(0x00)}{char(0x00)}{char(0x00)}")
          else:
            echo "skip 1 char"
        for ix in 1 .. margin:
          f.write(fmt"{char(0xff)}{char(0xff)}{char(0xff)}")
        for ix in (3 * bmp_size mod 4) ..< 4:
          f.write(fmt"{char(0x00)}")

    for m in 1 .. margin:
      for ix in 1 .. bmp_size:
        f.write(fmt"{char(0xff)}{char(0xff)}{char(0xff)}")
      for ix in (3 * bmp_size mod 4) ..< 4:
        f.write(fmt"{char(0x00)}")

let app = App(wSystemDpiAware)
let frame = Frame(title="File <=> QR")
let panel = Panel(frame)

frame.dpiAutoScale:
    frame.size = (750, 450)

let statusBar = StatusBar(frame)

let box_input  = StaticBox(panel, label="Select Input")
let box_QR     = StaticBox(panel, label="Display QR code")
let box_decode = StaticBox(panel, label="Decode file")
let box_output = StaticBox(panel, label="Output")

let rb_file = RadioButton(panel, label="File Name")
let rb_text = RadioButton(panel, label="Direct Text")

let input_file= TextCtrl(panel)
let btn_input = Button(panel, label="Open..")
let file_sel = FileDialog(panel, message="Open...")

let input_text = TextCtrl(panel)

let label_err = StaticText(panel, label="Error correct")
var choices: seq[string] = @[]
for k, v in list_err:
    choices.add(fmt"{k} {v[1]} bytes")
let cb_err = ComboBox(panel, value=choices[low(choices)], choices=choices) # [list_err.values().tolist()])
let btn_qr = Button(panel, label="Display QR codes")

let btn_decode = Button(panel, label="Output Decode file")

let frame_qr_ctl = Frame(title="QR code ctl", size=(300, 200))
let panel_qr_ctl = Panel(frame_qr_ctl)
let frame_qr = Frame(title="QR code", size=(600, 630))
let panel_qr = Panel(frame_qr)
let btn_head = Button(panel_qr_ctl, label="▲▲")
let btn_next = Button(panel_qr_ctl, label="▼")
let btn_tail = Button(panel_qr_ctl, label="▼▼")
var cur_idx: int = 0
let label_cur_idx = StaticText(panel_qr_ctl, label="nnn")
let label_total = StaticText(panel_qr_ctl, label=" / nnn")
var bm: wImage = nil
const qr_file_name = "test.bmp"
var qr_codes: seq[seq[string]]
var memDc = MemoryDC()

proc layout() =
  panel.autolayout """
    H:|-40-[box_input]-40-|
    H:|-40-[box_QR]-[box_decode]-40-|
    V:|-[box_input]-30-[box_QR,box_decode]-40-|

    outer: box_input
    H:|-[rb_file]-[input_file]-[btn_input(75)]-|
    H:|-[rb_text]-[input_text]-|
    V:|-[rb_file,input_file,btn_input]-[rb_text, input_text]-|

    outer: box_QR
    H:|-[label_err]-[cb_err]-|
    H:|-[btn_qr]-|
    V:|-[label_err,cb_err]-[btn_qr]-|

    outer: box_decode
    H:|-[btn_decode]-|
    V:|-[btn_decode]-|
  """
  box_output.contain(box_QR, box_decode)

btn_input.wEvent_Button do ():
  let input_file_name: seq[string] = file_sel.display()
  input_file.setValue(input_file_name[0])
  if rb_file.value == true:
    if input_file.value.len() > 0:
      btn_qr.enable()
      btn_decode.enable()
    else:
      btn_qr.disable()
      btn_decode.disable()

proc layout_qr_ctl() =
  panel_qr_ctl.autolayout """
    H:|-[btn_head,btn_next,btn_tail]-[label_cur_idx]-[label_total]-|
    V:|-[btn_head]-[btn_next(btn_head.height*2)]-[btn_tail(btn_head.height)]-|
    V:|-[label_cur_idx,label_total]-|
  """

proc displayQr(idx: int) =
  label_cur_idx.setLabel(idx.intToStr)
  qr_data_to_bmp(fmt"{qr_file_name}{idx}", qr_codes[idx], magnify=3, margin=20)
  bm = Image(fmt"{qr_file_name}{idx}")
  # bm.backgroundColor = -1
  memDc.selectObject(Bitmap(bm.size))
  memDc.clear()
  memDc.setBackground(wWhiteBrush)
  memDc.setBrush(wWhiteBrush)
  memDc.drawImage(bm, 0, 0)
  panel_qr.center()
  frame_qr.show()
  panel_qr.refresh()
  layout_qr_ctl()
  frame_qr_ctl.show()

panel_qr.wEvent_Paint do ():
  var dc = PaintDC(panel_qr)
  dc.blit(source=memDc, xdest=0, ydest=0, width=bm.getSize().width, height=bm.getSize().height)
  dc.delete

proc popupQR(data_file_name: Path) =
  block:
    let f: File = open(data_file_name.string(), FileMode.fmRead)
    defer:
      f.close()
    let data = f.readAll()
    var err_level: string = ""
    for k, v in list_err:
      if cb_err.value().startsWith(k):
        err_level = k
    qr_codes = make_qr_data(data_file_name.lastPathPart.string, data, err_level)
  label_total.setLabel(fmt" / {qr_codes.len}")
  cur_idx = 0
  displayQr(0)

btn_head.wEvent_Button do ():
  if cur_idx == low(qr_codes):
    return
  cur_idx = low(qr_codes)
  displayQr(cur_idx)

btn_next.wEvent_Button do ():
  if cur_idx < high(qr_codes):
    cur_idx += 1
    displayQr(cur_idx)

btn_tail.wEvent_Button do ():
  if cur_idx == high(qr_codes):
    return
  cur_idx = high(qr_codes)
  displayQr(cur_idx)

rb_file.value = true
btn_qr.disable()
btn_decode.disable()

rb_file.wEvent_RadioButton do ():
  input_file.enable()
  btn_input.enable()
  input_text.disable()

rb_text.wEvent_RadioButton do ():
  input_file.disable()
  btn_input.disable()
  input_text.enable()

btn_qr.wEvent_Button do ():
  var in_data: string = ""
  if rb_file.value == true and input_file.value.len() > 0:
    in_data = input_file.value
  elif rb_text.value == true:
    in_data = input_text.value
  if in_data.len() > 0:
    popupQR(input_file.value.Path())

btn_decode.wEvent_Button do ():
  if rb_file.value == true and input_file.value.len() > 0:
    block:
      let inFile = open(input_file.value, FileMode.fmRead)
      defer:
        inFile.close
      let data = inFile.readAll
      decode_qr_data(data)

layout()
frame.center()
frame.show()
app.mainLoop()
