import QtQuick
import QtQuick.Controls
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.layolayo.camarchy-control"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property int sharpness: 1
  property int sharpnessMin: 0
  property int sharpnessMax: 7
  property int sharpnessDefault: 3

  property int brightness: 128
  property int brightnessMin: 0
  property int brightnessMax: 255
  property int brightnessDefault: 128

  property int contrast: 32
  property int contrastMin: 0
  property int contrastMax: 100
  property int contrastDefault: 32

  property int saturation: 64
  property int saturationMin: 0
  property int saturationMax: 100
  property int saturationDefault: 64

  property int gamma: 120
  property int gammaMin: 90
  property int gammaMax: 150
  property int gammaDefault: 120

  property int backlightComp: 0
  property int dynamicFramerate: 0

  property bool showPreview: false
  property bool mirrorPreview: true
  property string previewError: ""

  readonly property int panelWidth: Style.space(350)

  MediaDevices {
    id: mediaDevices
  }

  readonly property var availableCameras: {
    var list = []
    var inputs = mediaDevices.videoInputs
    for (var i = 0; i < inputs.length; i++) {
      var id = String(inputs[i].id)
      var desc = String(inputs[i].description)
      // Filter out virtual IPU7 / loopback devices
      if (desc.indexOf("ISP") === -1 && id.indexOf("video50") === -1) {
        list.push(inputs[i])
      }
    }
    return list
  }

  property int selectedCameraIndex: 0

  readonly property var activeCameraDevice: {
    if (availableCameras.length === 0) return null
    var idx = Math.max(0, Math.min(selectedCameraIndex, availableCameras.length - 1))
    return availableCameras[idx]
  }

  readonly property string activeDevicePath: activeCameraDevice ? String(activeCameraDevice.id) : "/dev/video0"
  readonly property string activeDeviceName: activeCameraDevice ? String(activeCameraDevice.description) : "Integrated Camera"

  onSelectedCameraIndexChanged: {
    if (cameraSessionLoader.active) {
      cameraSessionLoader.active = false
      Qt.callLater(function() {
        cameraSessionLoader.active = root.opened && root.showPreview
      })
    }
    refresh()
  }

  function cleanDeviceTitle(desc) {
    var str = String(desc || "Webcam")
    str = str.replace("Integrated Camera: ", "")
    if (str === "Integrated C") return "Color Camera"
    if (str === "Integrated I") return "IR Camera"
    return str
  }

  function pickBestCameraFormat(dev) {
    if (!dev || !dev.videoFormats || dev.videoFormats.length === 0) return null
    var formats = dev.videoFormats

    // 1. Prefer MJPEG (pf === 29) at 1920x1080 for full native sensor resolution
    for (var i = 0; i < formats.length; i++) {
      var f = formats[i]
      if (f.pixelFormat === 29 && f.resolution.width === 1920 && f.resolution.height === 1080) {
        return f
      }
    }

    // 2. Next prefer MJPEG at 1280x720
    for (var j = 0; j < formats.length; j++) {
      var f2 = formats[j]
      if (f2.pixelFormat === 29 && f2.resolution.width === 1280 && f2.resolution.height === 720) {
        return f2
      }
    }

    // 3. Any 1080p or 720p format
    for (var k = 0; k < formats.length; k++) {
      var f3 = formats[k]
      var w = f3.resolution.width
      var h = f3.resolution.height
      if ((w === 1920 && h === 1080) || (w === 1280 && h === 720)) {
        return f3
      }
    }

    // 4. Any format with pf === 29 (MJPEG)
    for (var l = 0; l < formats.length; l++) {
      if (formats[l].pixelFormat === 29) {
        return formats[l]
      }
    }

    return formats[0]
  }

  Loader {
    id: cameraSessionLoader
    active: root.opened && root.showPreview
    sourceComponent: Component {
      CaptureSession {
        id: session
        property alias cam: camItem
        camera: Camera {
          id: camItem
          cameraDevice: root.activeCameraDevice
          cameraFormat: root.pickBestCameraFormat(root.activeCameraDevice)
          active: true
          onErrorOccurred: function(error, errorString) {
            root.previewError = String(errorString || "")
          }
        }
        videoOutput: viewfinder
      }
    }
  }

  readonly property var activeCam: cameraSessionLoader.item ? cameraSessionLoader.item.cam : null
  readonly property bool camHasError: activeCam ? (activeCam.errorOccurred && activeCam.error !== Camera.NoError) : false

  function open() {
    refresh()
    root.showPreview = true
    root.controller.show()
  }

  function close() {
    root.showPreview = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") {
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    }
    return false
  }

  function refresh() {
    if (!/^\/dev\/video\d+$/.test(root.activeDevicePath)) return
    queryProc.running = true
  }

  function setControl(name, value) {
    if (!/^\/dev\/video\d+$/.test(root.activeDevicePath)) return
    var allowed = [
      "sharpness", "brightness", "contrast", "gamma", "saturation",
      "backlight_compensation", "exposure_dynamic_framerate", "auto_exposure", "white_balance_automatic"
    ]
    if (allowed.indexOf(name) === -1) return
    var num = Math.round(Number(value))
    if (isNaN(num)) return
    Quickshell.execDetached(["/usr/bin/v4l2-ctl", "-d", root.activeDevicePath, "--set-ctrl=" + name + "=" + num])
  }

  function isPresetActive(name) {
    if (name === "clean") {
      return root.sharpness === 1 && root.backlightComp === 0 && root.brightness === 128
    } else if (name === "default") {
      return root.sharpness === 3 && root.backlightComp === 1 && root.brightness === 128
    } else if (name === "backlit") {
      return root.sharpness === 2 && root.backlightComp >= 1 && root.brightness === 142
    } else if (name === "lowlight") {
      return root.sharpness === 1 && root.dynamicFramerate === 1 && root.brightness === 148
    }
    return false
  }

  function applyPreset(name) {
    if (!/^\/dev\/video\d+$/.test(root.activeDevicePath)) return
    if (name === "clean") {
      root.sharpness = 1
      root.backlightComp = 0
      root.dynamicFramerate = 0
      root.brightness = 128
      root.contrast = 32
      root.gamma = 120
      root.saturation = 64
      Quickshell.execDetached(["/usr/bin/v4l2-ctl", "-d", root.activeDevicePath,
        "--set-ctrl=auto_exposure=3",
        "--set-ctrl=white_balance_automatic=1",
        "--set-ctrl=sharpness=1",
        "--set-ctrl=backlight_compensation=0",
        "--set-ctrl=exposure_dynamic_framerate=0",
        "--set-ctrl=brightness=128",
        "--set-ctrl=contrast=32",
        "--set-ctrl=gamma=120",
        "--set-ctrl=saturation=64"])
    } else if (name === "default") {
      root.sharpness = 3
      root.backlightComp = 1
      root.dynamicFramerate = 1
      root.brightness = 128
      root.contrast = 32
      root.gamma = 120
      root.saturation = 64
      Quickshell.execDetached(["/usr/bin/v4l2-ctl", "-d", root.activeDevicePath,
        "--set-ctrl=auto_exposure=3",
        "--set-ctrl=white_balance_automatic=1",
        "--set-ctrl=sharpness=3",
        "--set-ctrl=backlight_compensation=1",
        "--set-ctrl=exposure_dynamic_framerate=1",
        "--set-ctrl=brightness=128",
        "--set-ctrl=contrast=32",
        "--set-ctrl=gamma=120",
        "--set-ctrl=saturation=64"])
    } else if (name === "backlit") {
      root.sharpness = 2
      root.backlightComp = 2
      root.dynamicFramerate = 0
      root.brightness = 142
      root.contrast = 38
      root.gamma = 130
      root.saturation = 68
      Quickshell.execDetached(["/usr/bin/v4l2-ctl", "-d", root.activeDevicePath,
        "--set-ctrl=auto_exposure=3",
        "--set-ctrl=white_balance_automatic=1",
        "--set-ctrl=sharpness=2",
        "--set-ctrl=backlight_compensation=2",
        "--set-ctrl=exposure_dynamic_framerate=0",
        "--set-ctrl=brightness=142",
        "--set-ctrl=contrast=38",
        "--set-ctrl=gamma=130",
        "--set-ctrl=saturation=68"])
    } else if (name === "lowlight") {
      root.sharpness = 1
      root.backlightComp = 0
      root.dynamicFramerate = 1
      root.brightness = 148
      root.contrast = 28
      root.gamma = 135
      root.saturation = 58
      Quickshell.execDetached(["/usr/bin/v4l2-ctl", "-d", root.activeDevicePath,
        "--set-ctrl=auto_exposure=3",
        "--set-ctrl=white_balance_automatic=1",
        "--set-ctrl=sharpness=1",
        "--set-ctrl=backlight_compensation=0",
        "--set-ctrl=exposure_dynamic_framerate=1",
        "--set-ctrl=brightness=148",
        "--set-ctrl=contrast=28",
        "--set-ctrl=gamma=135",
        "--set-ctrl=saturation=58"])
    }
  }

  Process {
    id: queryProc
    command: ["/usr/bin/v4l2-ctl", "-d", root.activeDevicePath, "-l"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = (text || "").split("\n")
        var lineRe = /^\s*([a-z0-9_]+)\s+[0-9a-fx]+\s+\([a-z]+\)\s*:\s*(.*)$/i
        var valRe = /value=(-?\d+)/
        var minRe = /min=(-?\d+)/
        var maxRe = /max=(-?\d+)/
        var defRe = /default=(-?\d+)/

        for (var i = 0; i < lines.length; i++) {
          var m = lines[i].match(lineRe)
          if (!m) continue
          var k = m[1]
          var rest = m[2]
          var vM = rest.match(valRe)
          var minM = rest.match(minRe)
          var maxM = rest.match(maxRe)
          var defM = rest.match(defRe)

          var v = vM ? parseInt(vM[1], 10) : NaN
          var mi = minM ? parseInt(minM[1], 10) : NaN
          var ma = maxM ? parseInt(maxM[1], 10) : NaN
          var de = defM ? parseInt(defM[1], 10) : NaN

          if (!isNaN(v)) {
            if (k === "sharpness") {
              root.sharpness = v
              if (!isNaN(mi)) root.sharpnessMin = mi
              if (!isNaN(ma)) root.sharpnessMax = ma
              if (!isNaN(de)) root.sharpnessDefault = de
            } else if (k === "brightness") {
              root.brightness = v
              if (!isNaN(mi)) root.brightnessMin = mi
              if (!isNaN(ma)) root.brightnessMax = ma
              if (!isNaN(de)) root.brightnessDefault = de
            } else if (k === "contrast") {
              root.contrast = v
              if (!isNaN(mi)) root.contrastMin = mi
              if (!isNaN(ma)) root.contrastMax = ma
              if (!isNaN(de)) root.contrastDefault = de
            } else if (k === "gamma") {
              root.gamma = v
              if (!isNaN(mi)) root.gammaMin = mi
              if (!isNaN(ma)) root.gammaMax = ma
              if (!isNaN(de)) root.gammaDefault = de
            } else if (k === "saturation") {
              root.saturation = v
              if (!isNaN(mi)) root.saturationMin = mi
              if (!isNaN(ma)) root.saturationMax = ma
              if (!isNaN(de)) root.saturationDefault = de
            } else if (k === "backlight_compensation") {
              root.backlightComp = v
            } else if (k === "exposure_dynamic_framerate") {
              root.dynamicFramerate = v
            }
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(12)
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(contentCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.switchPanel(direction)
      }

      Column {
        id: contentCol
        width: parent.width
        spacing: Style.space(10)

        // Header
        Item {
          width: parent.width
          implicitHeight: Math.max(headerRow.implicitHeight, headerActions.implicitHeight)
          height: implicitHeight

          Row {
            id: headerRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: "󰄀"
              color: Color.accent
              font.pixelSize: Style.font.subtitle
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              Text {
                text: "CAMARCHY CONTROL"
                color: root.barForeground
                font.bold: true
                font.pixelSize: Style.font.bodySmall
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
              }
              Text {
                text: root.cleanDeviceTitle(root.activeDeviceName) + " (" + root.activeDevicePath + ")"
                color: root.barForeground
                opacity: 0.6
                font.pixelSize: Style.space(10)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                elide: Text.ElideRight
                width: Style.space(190)
              }
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            // Switch Camera button (only if > 1 camera detected)
            PanelActionButton {
              visible: root.availableCameras.length > 1
              iconText: "󰑣"
              tooltipText: "Switch camera (currently: " + root.cleanDeviceTitle(root.activeDeviceName) + ")"
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: {
                root.selectedCameraIndex = (root.selectedCameraIndex + 1) % root.availableCameras.length
              }
            }

            // Viewfinder toggle button
            PanelActionButton {
              iconText: root.showPreview ? "󰕦" : "󰕧"
              tooltipText: root.showPreview ? "Hide live viewfinder" : "Show live viewfinder"
              foreground: root.showPreview ? Color.accent : root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.showPreview = !root.showPreview
            }

            // Refresh button
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh camera settings"
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.refresh()
            }
          }
        }


        // --- In-Popup Collapsible Viewfinder ---
        Item {
          id: previewContainer
          width: parent.width
          implicitHeight: root.showPreview ? Math.round(width * 9 / 16) : 0
          height: implicitHeight
          visible: implicitHeight > 0
          clip: true

          Behavior on implicitHeight {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: "#0a0e14"
            clip: true
            border.color: Color.accent
            border.width: 1

            VideoOutput {
              id: viewfinder
              anchors.fill: parent
              fillMode: VideoOutput.PreserveAspectCrop
              mirrored: root.mirrorPreview
              visible: !root.camHasError
            }

            // Stream error / busy overlay (e.g. Teams has camera open)
            Item {
              anchors.fill: parent
              visible: root.camHasError

              Column {
                anchors.centerIn: parent
                spacing: Style.space(4)
                width: parent.width - Style.space(24)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "󰄀"
                  color: Color.accent
                  font.pixelSize: Style.font.title
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Camera in use by active call/app"
                  color: root.barForeground
                  font.bold: true
                  font.pixelSize: Style.font.bodySmall
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Hardware tuning controls below remain active"
                  color: root.barForeground
                  opacity: 0.6
                  font.pixelSize: Style.font.caption
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                }
              }
            }

            // Viewfinder controls overlay (Mirror & Close)
            Row {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(6)
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "󰁨"
                tooltipText: root.mirrorPreview ? "Mirror: ON (natural view)" : "Mirror: OFF (direct view)"
                foreground: root.mirrorPreview ? Color.accent : root.barForeground
                bordered: true
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                onClicked: root.mirrorPreview = !root.mirrorPreview
              }

              PanelActionButton {
                iconText: "󰅖"
                tooltipText: "Close viewfinder"
                foreground: root.barForeground
                bordered: true
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                onClicked: root.showPreview = false
              }
            }
          }
        }

        // --- 2x2 Quick Presets ---
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "PRESETS"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          // Row 1
          Row {
            id: presetRow1
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: presetRow1.cellWidth
              iconText: "󰁨"
              iconSize: Style.font.body
              text: "De-grain"
              tooltipText: "Sharpness 1 + Backlight Off (recommended for low noise)"
              fontSize: Style.font.bodySmall
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.isPresetActive("clean")
              onClicked: root.applyPreset("clean")
            }

            Button {
              width: presetRow1.cellWidth
              iconText: "󰁯"
              iconSize: Style.font.body
              text: "Balanced"
              tooltipText: "Sharpness 3 + Backlight On (factory default)"
              fontSize: Style.font.bodySmall
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.isPresetActive("default")
              onClicked: root.applyPreset("default")
            }
          }

          // Row 2
          Row {
            id: presetRow2
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: presetRow2.cellWidth
              iconText: "󰖨"
              iconSize: Style.font.body
              text: "Backlit"
              tooltipText: "Boosts gain & gamma for bright windows behind you"
              fontSize: Style.font.bodySmall
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.isPresetActive("backlit")
              onClicked: root.applyPreset("backlit")
            }

            Button {
              width: presetRow2.cellWidth
              iconText: "󰓅"
              iconSize: Style.font.body
              text: "Low Light"
              tooltipText: "Zero sharpness noise + Dynamic FPS for dark rooms"
              fontSize: Style.font.bodySmall
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.isPresetActive("lowlight")
              onClicked: root.applyPreset("lowlight")
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.barForeground
        }

        PanelSectionHeader {
          text: "IMAGE ADJUSTMENTS"
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        // --- Sharpness Slider ---
        Column {
          width: parent.width
          spacing: Style.space(2)

          Item {
            width: parent.width
            implicitHeight: Math.max(sharpnessLbl.implicitHeight, sharpnessVal.implicitHeight)
            height: implicitHeight

            Text {
              id: sharpnessLbl
              anchors.left: parent.left
              anchors.top: parent.top
              text: "SHARPNESS"
              color: root.barForeground
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              id: sharpnessVal
              anchors.right: parent.right
              anchors.baseline: sharpnessLbl.baseline
              text: root.sharpness + " / " + root.sharpnessMax
              color: Color.accent
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Text {
            width: parent.width
            text: "Edge sharpness filter; lower cuts harsh noise (default: " + root.sharpnessDefault + ")"
            color: root.barForeground
            opacity: 0.55
            font.pixelSize: Style.font.caption
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            wrapMode: Text.WordWrap
          }

          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: root.sharpnessMin
            maximum: root.sharpnessMax
            step: 1
            integer: true
            value: root.sharpness
            onMoved: function(v) {
              root.sharpness = v
              root.setControl("sharpness", v)
            }
            onReleased: function(v) {
              root.sharpness = v
              root.setControl("sharpness", v)
            }
          }
        }

        // --- Brightness Slider ---
        Column {
          width: parent.width
          spacing: Style.space(2)

          Item {
            width: parent.width
            implicitHeight: Math.max(brightnessLbl.implicitHeight, brightnessVal.implicitHeight)
            height: implicitHeight

            Text {
              id: brightnessLbl
              anchors.left: parent.left
              anchors.top: parent.top
              text: "BRIGHTNESS"
              color: root.barForeground
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              id: brightnessVal
              anchors.right: parent.right
              anchors.baseline: brightnessLbl.baseline
              text: root.brightness + " / " + root.brightnessMax
              color: Color.accent
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Text {
            width: parent.width
            text: "Auto-exposure target level (default: " + root.brightnessDefault + ")"
            color: root.barForeground
            opacity: 0.55
            font.pixelSize: Style.font.caption
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            wrapMode: Text.WordWrap
          }

          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: root.brightnessMin
            maximum: root.brightnessMax
            step: 1
            integer: true
            value: root.brightness
            onMoved: function(v) {
              root.brightness = v
              root.setControl("brightness", v)
            }
            onReleased: function(v) {
              root.brightness = v
              root.setControl("brightness", v)
            }
          }
        }

        // --- Contrast Slider ---
        Column {
          width: parent.width
          spacing: Style.space(2)

          Item {
            width: parent.width
            implicitHeight: Math.max(contrastLbl.implicitHeight, contrastVal.implicitHeight)
            height: implicitHeight

            Text {
              id: contrastLbl
              anchors.left: parent.left
              anchors.top: parent.top
              text: "CONTRAST"
              color: root.barForeground
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              id: contrastVal
              anchors.right: parent.right
              anchors.baseline: contrastLbl.baseline
              text: root.contrast + " / " + root.contrastMax
              color: Color.accent
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Text {
            width: parent.width
            text: "Separation of dark & light; higher deepens shadows (default: " + root.contrastDefault + ")"
            color: root.barForeground
            opacity: 0.55
            font.pixelSize: Style.font.caption
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            wrapMode: Text.WordWrap
          }

          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: root.contrastMin
            maximum: root.contrastMax
            step: 1
            integer: true
            value: root.contrast
            onMoved: function(v) {
              root.contrast = v
              root.setControl("contrast", v)
            }
            onReleased: function(v) {
              root.contrast = v
              root.setControl("contrast", v)
            }
          }
        }

        // --- Saturation Slider ---
        Column {
          width: parent.width
          spacing: Style.space(2)

          Item {
            width: parent.width
            implicitHeight: Math.max(satLbl.implicitHeight, satVal.implicitHeight)
            height: implicitHeight

            Text {
              id: satLbl
              anchors.left: parent.left
              anchors.top: parent.top
              text: "SATURATION"
              color: root.barForeground
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              id: satVal
              anchors.right: parent.right
              anchors.baseline: satLbl.baseline
              text: root.saturation + " / " + root.saturationMax
              color: Color.accent
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Text {
            width: parent.width
            text: "Color intensity; lower tames noisy color speckles (default: " + root.saturationDefault + ")"
            color: root.barForeground
            opacity: 0.55
            font.pixelSize: Style.font.caption
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            wrapMode: Text.WordWrap
          }

          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: root.saturationMin
            maximum: root.saturationMax
            step: 1
            integer: true
            value: root.saturation
            onMoved: function(v) {
              root.saturation = v
              root.setControl("saturation", v)
            }
            onReleased: function(v) {
              root.saturation = v
              root.setControl("saturation", v)
            }
          }
        }

        // --- Gamma Slider ---
        Column {
          width: parent.width
          spacing: Style.space(2)

          Item {
            width: parent.width
            implicitHeight: Math.max(gammaLbl.implicitHeight, gammaVal.implicitHeight)
            height: implicitHeight

            Text {
              id: gammaLbl
              anchors.left: parent.left
              anchors.top: parent.top
              text: "GAMMA"
              color: root.barForeground
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              id: gammaVal
              anchors.right: parent.right
              anchors.baseline: gammaLbl.baseline
              text: root.gamma + " / " + root.gammaMax
              color: Color.accent
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Text {
            width: parent.width
            text: "Midtone brightness curve (default: " + root.gammaDefault + ")"
            color: root.barForeground
            opacity: 0.55
            font.pixelSize: Style.font.caption
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            wrapMode: Text.WordWrap
          }

          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: root.gammaMin
            maximum: root.gammaMax
            step: 1
            integer: true
            value: root.gamma
            onMoved: function(v) {
              root.gamma = v
              root.setControl("gamma", v)
            }
            onReleased: function(v) {
              root.gamma = v
              root.setControl("gamma", v)
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.barForeground
        }

        // --- Hardware Toggles ---
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "HARDWARE MODES"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Row {
            id: toggleRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: toggleRow.cellWidth
              iconText: "󰖨"
              iconSize: Style.font.body
              text: "Backlight: " + (root.backlightComp >= 1 ? "ON" : "OFF")
              tooltipText: "Hardware backlight compensation (boosts exposure in backlit rooms)"
              fontSize: Style.font.bodySmall
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.backlightComp >= 1
              onClicked: {
                var next = root.backlightComp >= 1 ? 0 : 1
                root.backlightComp = next
                root.setControl("backlight_compensation", next)
              }
            }

            Button {
              width: toggleRow.cellWidth
              iconText: "󰓅"
              iconSize: Style.font.body
              text: "Dyn FPS: " + (root.dynamicFramerate === 1 ? "ON" : "OFF")
              tooltipText: "Allow frame rate to dynamically decrease to gain sensor exposure in the dark"
              fontSize: Style.font.bodySmall
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              selected: root.dynamicFramerate === 1
              onClicked: {
                var next = root.dynamicFramerate === 1 ? 0 : 1
                root.dynamicFramerate = next
                root.setControl("exposure_dynamic_framerate", next)
              }
            }
          }
        }

      }
    }
  }
}
