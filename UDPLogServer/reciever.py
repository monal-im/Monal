#~~~~IMPORTS~~~~#
from PyQt5 import QtWidgets
from PyQt5.QtWidgets import QFileDialog, QComboBox
from PyQt5.QtCore import Qt


import sys
import json
import struct

#~~~Window~~~#
def window():

    #This Function imports a file (The file you picked)
    def open_file_browser():
        file , check = QFileDialog.getOpenFileName(None, "QFileDialog.getOpenFileName()",
                                                "", "All Files (*);;Python Files (*.py);;Text Files (*.txt);; Raw Log (*.rawlog)")
        if check:
            #gives out the location of the rawlog file
            return file

    #Sets a font color and filters the messages (if needed)
    def labels_and_colors(entry_point, filters):
        identifyer = entry_point['flag'] #filter
        entry_point = entry_point['formattedMessage'] #message

        label_and_color = QtWidgets.QLabel(entry_point)

        if filters != None:
            if int(identifyer) == 1 and filters != 'error': # error
                label_and_color.setStyleSheet("color: #ff3333; font-weight: bold; font-size: 12px;") #red
                label_and_color.show()

            elif int(identifyer) == 2 and filters != 'warning': # warning
                label_and_color.setStyleSheet("color: #ffcc00; font-weight: bold; font-size: 12px;") #yellow
                label_and_color.show()

            elif int(identifyer) == 4 and filters != 'info': # info
                label_and_color.setStyleSheet("color: #2F327A; font-weight: bold; font-size: 12px;") #blue
                label_and_color.show()

            elif int(identifyer) == 8 and filters != 'debug': # debug
                label_and_color.setStyleSheet("color: #D27D2D; font-weight: bold; font-size: 12px;") #orange
                label_and_color.show()

            elif int(identifyer) == 16 and filters != 'verbose': # verbose
                label_and_color.setStyleSheet("color: #228B22; font-weight: bold; font-size: 12px;") #green
                label_and_color.show()

            else:
                label_and_color.hide()

        else:
            if int(identifyer) == 1: # error
                label_and_color.setStyleSheet("color: #ff3333; font-weight: bold; font-size: 12px;") #red

            elif int(identifyer) == 2: # warning
                label_and_color.setStyleSheet("color: #ffcc00; font-weight: bold; font-size: 12px;") #yellow

            elif int(identifyer) == 4: # info
                label_and_color.setStyleSheet("color: #2F327A; font-weight: bold; font-size: 12px;") #blue

            elif int(identifyer) == 8: # debug
                label_and_color.setStyleSheet("color: #D27D2D; font-weight: bold; font-size: 12px;") #orange

            elif int(identifyer) == 16: # verbose
                label_and_color.setStyleSheet("color: #228B22; font-weight: bold; font-size: 12px;") #green

            else:
                raise Exception("flag is not in range")

        return label_and_color

    label_list = [] #all finished lavels (shown in the big scroll box)
    entrys = [] #all entrys get inhere to sum them up

    app = QtWidgets.QApplication(sys.argv)
    widget = QtWidgets.QWidget()

    #read out files
    path_to_file = open_file_browser()
    repeater = 0

    fp = open(path_to_file, "rb") #open log

    while True:
        #Unpacks the rawlog file and strips down the values
        acht_bytes = fp.read(8)
        if len(acht_bytes) != 8:
            break

        jason_read_len = struct.unpack("!Q", acht_bytes)
        jason_read_len = jason_read_len[0]
        block_output = fp.read(jason_read_len)
        if len(block_output) != jason_read_len:
            raise Exception("File Corupt")

        decoded = json.loads(str(block_output, "UTF-8"))
        repeater += 1
        entrys.append(decoded)


    #Log Messages
    groupbox = QtWidgets.QGroupBox('Log Messages')
    Entrys = QtWidgets.QFormLayout()
    
    for i in range(repeater): #gets all entrys and writes them in the scroll box
        entry_point = entrys[i]

        label_list.append(labels_and_colors(entry_point, None))
        Entrys.addWidget(label_list[i])

    #scroll box parameters
    groupbox.setLayout(Entrys)
    scroll = QtWidgets.QScrollArea()
    scroll.setWidget(groupbox)
    scroll.setWidgetResizable(True)
    scroll.setFixedHeight(750)
    layout = QtWidgets.QVBoxLayout(widget)
    layout.addWidget(scroll)
    layout.setAlignment(Qt.AlignBottom)


    #dropdown
    #NOTE: TO FIX: NEW LOGMESSAGES SHOW IN DIFFERENT WINDOW
    def _pullComboText(text): 
        #this function gets all entrys, checks if they are the filter you picked and if not writes it in the scoll box
        label_list.clear()
        b = 0
        while True:
            if repeater == b:
                break
            else:
                if text != 'All entrys':
                    label_list.append(labels_and_colors(entrys[b], text))
                else:
                    label_list.append(labels_and_colors(entrys[b], None))
                b += 1
        b = 0

    combo = QComboBox(widget)
    #setting up the filter
    combo.addItem('All entrys')
    combo.addItem('error')
    combo.addItem('warning')
    combo.addItem('info')
    combo.addItem('debug')
    combo.addItem('verbose')
    combo.currentTextChanged.connect(_pullComboText)
    combo.move(20, 20)


    #main window stuff
    widget.setGeometry(300,160,1400,820)
    widget.setWindowTitle("MONAL LOG")
    widget.show()

    sys.exit(app.exec_())


if __name__ == '__main__':
    window()
