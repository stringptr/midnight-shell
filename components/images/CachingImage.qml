import QtQuick
import Quickshell
import Caelestia.Images

Image {
    id: root

    property string path
    property real hOffset: 0.0
    property real vOffset: 0.0

    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    source: IUtils.urlForPath(path, fillMode, hOffset, vOffset)
    sourceSize: {
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        return Qt.size(width * dpr, height * dpr);
    }
}
