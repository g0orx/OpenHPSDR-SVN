#-------------------------------------------------
#
# Project created by QtCreator 2010-12-14T14:22:05
#
#-------------------------------------------------

QT       += core gui network

TARGET = HPSDRProgrammer
TEMPLATE = app

CONFIG += static

win32 {
    INCLUDEPATH += "\Documents and Settings\john\Desktop\WpdPack\Include"
    LIBS += "\Documents and Settings\john\Desktop\WpdPack\Lib\wpcap.lib" /Qt/2010.05/mingw/lib/libws2_32.a
 }
macx {
    LIBS += -framework Security -lpcap
    INCLUDEPATH += "/System/Library/Frameworks/Security.framework/Headers"
} else {
    LIBS += -lpcap
}

SOURCES += main.cpp\
        mainwindow.cpp \
    Interfaces.cpp \
    RawReceiveThread.cpp \
    DiscoveryThread.cpp \
    ReceiveThread.cpp \
    Metis.cpp \
    AboutDialog.cpp

HEADERS  += mainwindow.h \
    Interfaces.h \
    RawReceiveThread.h \
    DiscoveryThread.h \
    ReceiveThread.h \
    Metis.h \
    AboutDialog.h

FORMS    += mainwindow.ui \
    AboutDialog.ui

RESOURCES +=
