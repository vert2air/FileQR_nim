import wNim/wNim/[wApp, wBitmap, wButton, wComboBox, wFileDialog, wFrame, wImage, wNoteBook,
    wPanel, wRadioButton, wStaticBitmap, wStaticBox, wStaticText, wStatusBar, wTextCtrl, ]
import qr
import std/[base64, paths, strformat, strutils, tables]
import checksums/sha1

let list_err = {
    "L( 7%)": (Ecc_LOW,      2_953),
    "M(15%)": (Ecc_MEDIUM,   2_331),
    "Q(25%)": (Ecc_QUARTILE, 1_663),
    "H(30%)": (Ecc_HIGH,     1_272),
}.toOrderedTable

let app = App(wSystemDpiAware)
let frame = Frame(title="File <=> QR")
let panel = Panel(frame)

proc num2bin2(number: int): string =
    var buffer: array[2, string]
    buffer[0] = fmt"{char((number shr  0) and 0xff)}"
    buffer[1] = fmt"{char((number shr  8) and 0xff)}"
    return buffer.join()

proc num2bin4(number: int): string =
    var buffer: array[4, string]
    buffer[0] = fmt"{char((number shr  0) and 0xff)}"
    buffer[1] = fmt"{char((number shr  8) and 0xff)}"
    buffer[2] = fmt"{char((number shr 16) and 0xff)}"
    buffer[3] = fmt"{char((number shr 24) and 0xff)}"
    return buffer.join()

proc make_qr_data(fileName: Path, data: string, err_cor: string): seq[seq[string]] =
    result = @[]
    let base64data: string = data.encode()
    let baseName: string = fileName.lastPathPart().string()
    let size_per_qr: int = list_err[err_cor][1] - fmt"abcd:001:100:{baseName}:".len()
    let qrHash: string = ($secureHash(base64data & err_cor))[0..3]
    let last_len: int = base64data.len() mod size_per_qr
    let total: int = (base64data.len() + size_per_qr - 1) div size_per_qr

    var idx = 0
    for offset in countup(0, base64data.len() - last_len - 1, size_per_qr):
        var qrOrder: seq[string] = @[]
        for qrRevLine in qrBinary(
                fmt"{qrHash}:{idx:03d}:{total:03d}:{baseName}:" & base64data[offset ..< offset + size_per_qr],
                eccLevel=list_err[err_cor][0]).splitLines:
            if qrRevLine.len() > 0:
                qrOrder.insert(qrRevLine, 0)
        result.add(qrOrder)
        idx += 1
    if last_len > 0:
        var qrOrder: seq[string] = @[]
        for qrRevLine in qrBinary(
                fmt"{qrHash}:{idx:03d}:{total:03d}:{baseName}:" & base64data[idx * size_per_qr .. ^1],
                eccLevel=list_err[err_cor][0]).splitLines:
            if qrRevLine.len() > 0:
                qrOrder.insert(qrRevLine, 0)
        result.add(qrOrder)

proc qr_data_to_pbm(pbm_fn: string, qrbin: string) =
    let line_len = qrbin.find("\n")
    block:
        var f: File = open(pbm_fn, FileMode.fmWrite)
        defer:
            close(f)
        f.write("P1\n")
        f.write(fmt"{line_len} {line_len}" & "\n")
        f.write(qrbin)

proc qr_data_to_bmp(bmp_fn: string, qrLine: seq[string]) =
    # BMPファイルフォーマット
    # https://www.setsuki.com/hsp/ext/bmp.htm
    var line_count = qrLine.len()
    block:
        var f: File = open(bmp_fn, FileMode.fmWrite)
        defer:
            f.close()
        f.write('B') # bfType
        f.write('M') # bfType
        let data_size: int = ((3 * line_count + 3) div 4) * 4 * line_count
        f.write(num2bin4(14 + 40 + data_size)) # bfSize
        f.write(num2bin2(0)) # bfReserved1
        f.write(num2bin2(0)) # bfReserved2
        f.write(num2bin4(14 + 40)) # bfOffBits

        f.write(num2bin4(40)) # bcSize
        f.write(num2bin4(line_count)) # bcWidth
        f.write(num2bin4(line_count)) # bcHeight
        f.write(num2bin2(1)) # bcPlanes
        f.write(num2bin2(24)) # bcBitCount

        f.write(num2bin4(0)) # biComression 0:BI_RGB
        f.write(num2bin4(data_size)) # biSizeImage
        f.write(num2bin4(0)) # biXPixPerMeter
        f.write(num2bin4(0)) # biYPixPerMeter
        f.write(num2bin4(0)) # biClrUsed
        f.write(num2bin4(0)) # biClrImportant

        for line in qrLine:
            if line.len() == 0:
                continue
            for ch in line:
                case ch:
                of '0': f.write(fmt"{char(0xff)}{char(0xff)}{char(0xff)}")
                of '1': f.write(fmt"{char(0x00)}{char(0x00)}{char(0x00)}")
                else:
                    echo "skip 1 char"
            for ix in (3 * line_count mod 4) ..< 4:
                f.write(fmt"{char(0x00)}")

    

frame.dpiAutoScale:
    frame.size = (750, 450)

let statusBar = StatusBar(frame)

let box_input  = StaticBox(panel, label="Select Input")
let box_QR     = StaticBox(panel, label="Display QR code")
let box_decode = StaticBox(panel, label="Decode file")
let box_output = StaticBox(panel, label="Output")
box_output.margin = 20

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
            btn_decode.enable()

proc popupQR(data_file_name: Path) =
    var frame_qr = Frame(title="QR code", size=(900, 800))
    var panel_qr = Panel(frame_qr)
    var btn_head = Button(frame_qr, label="▲▲")
    var btn_next = Button(frame_qr, label="▼")
    var btn_tail = Button(frame_qr, label="▼▼")
    block:
        var f: File = open(data_file_name.string(), FileMode.fmRead)
        defer:
            f.close()
        let data = f.readAll()
        var err_level: string = ""
        for k, v in list_err:
            if cb_err.value().startsWith(k):
                err_level = k
        let a = make_qr_data(data_file_name, data, err_level)
        const qr_file_name = "test.bmp"
        qr_data_to_bmp(qr_file_name, a[0])
        let bm = StaticBitmap(panel_qr, bitmap=Bitmap(qr_file_name), style=wSbFit)
        bm.backgroundColor = -1
        proc layout_qr() =
            panel_qr.autolayout """
                H:|-[btn_head,btn_next,btn_tail]-[bm]-|
                V:|-[btn_head(=20%)]-[btn_next(=50%)]-[btn_tail(=20%)]-|
                V:|-[bm(=bm.width)]-|
            """
        layout_qr()
        frame_qr.show()

rb_file.value = true
btn_qr.disable()
btn_decode.disable()

rb_file.wEvent_RadioButton do ():
    echo "Radio button: file clicked."
    input_file.enable()
    btn_input.enable()
    input_text.disable()

rb_text.wEvent_RadioButton do ():
    echo "Radio button: text clicked."
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

layout()
frame.center()
frame.show()
app.mainLoop()
        