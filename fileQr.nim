import wNim/wNim/[wApp, wBitmap, wButton, wComboBox, wFileDialog, wFrame, wImage, wNoteBook,
    wPanel, wRadioButton, wStaticBitmap, wStaticBox, wStaticText, wStatusBar, wTextCtrl, ]
import qr
import std/strformat
import strutils

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

proc make_qr_data(data: string, err_cor: enum): seq[string] =
    result = @[]
    for line in qrBinary(data).splitLines:   # , eccLevel=Ecc_Low)
        if line.len > 0:
            result.insert(line, 0)

proc qr_data_to_pbm(pbm_fn: string, qrbin: string) =
    let line_len = qrbin.find("\n")
    block:
        var f: File = open(pbm_fn, FileMode.fmWrite)
        defer:
            close(f)
        f.write("P1\n")
        f.write(fmt"{line_len} {line_len}" & "\n")
        f.write(qrbin)

proc qr_data_to_bmp(bmp_fn: string, qrbin: seq[string]) =
    # BMPファイルフォーマット
    # https://www.setsuki.com/hsp/ext/bmp.htm
    let line_len = qrbin.len

    block:
        var f: File = open(bmp_fn, FileMode.fmWrite)
        defer:
            f.close()
        f.write('B') # bfType
        f.write('M') # bfType
        let data_size: int = ((3 * line_len + 3) div 4) * 4 * line_len
        f.write(num2bin4(14 + 40 + data_size)) # bfSize
        f.write(num2bin2(0)) # bfReserved1
        f.write(num2bin2(0)) # bfReserved2
        f.write(num2bin4(14 + 40)) # bfOffBits

        f.write(num2bin4(40)) # bcSize
        f.write(num2bin4(line_len)) # bcWidth
        f.write(num2bin4(line_len)) # bcHeight
        f.write(num2bin2(1)) # bcPlanes
        f.write(num2bin2(24)) # bcBitCount

        f.write(num2bin4(0)) # biComression 0:BI_RGB
        f.write(num2bin4(data_size)) # biSizeImage
        f.write(num2bin4(0)) # biXPixPerMeter
        f.write(num2bin4(0)) # biYPixPerMeter
        f.write(num2bin4(0)) # biClrUsed
        f.write(num2bin4(0)) # biClrImportant

        for line in qrbin:
            for ch in line:
                case ch:
                of '0': f.write(fmt"{char(0xff)}{char(0xff)}{char(0xff)}")
                of '1': f.write(fmt"{char(0x00)}{char(0x00)}{char(0x00)}")
                else:
                    echo "skip 1 char"
            for ix in (3 * line_len mod 4) ..< 4:
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
let list_err = ["L(7%)", "M(15%)", "Q(25%)", "H(30%)"]
let cb_err = ComboBox(panel, value=list_err[0], choices=list_err)
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

proc popupQR(data_file_name: string) =
    var frame_qr = Frame(title="QR code", size=(400, 400))
    var panel_qr = Panel(frame_qr)
    block:
        var f: File = open(data_file_name, FileMode.fmRead)
        defer:
            f.close()
        let data = f.readAll()
        let a = make_qr_data(data, Ecc_Low)
        const qr_file_name = "test.bmp"
        qr_data_to_bmp(qr_file_name, a)
        let bm = StaticBitmap(panel_qr, bitmap=Bitmap(qr_file_name), style=wSbFit)
        bm.backgroundColor = -1
        proc layout_qr() =
            panel_qr.autolayout """
                H:|-[bm]-|
                V:|-[bm]-|
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
        popupQR(input_file.value)

layout()
frame.center()
frame.show()
app.mainLoop()
        