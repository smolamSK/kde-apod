// Panel widget for apod-wallpaper (https://github.com/smolamSK/kde-apod): shows the current NASA APOD
// wallpaper and switches between the "latest" and "random" modes.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // On PATH if installed system-wide, otherwise where install.sh puts it.
    readonly property string command: "\"$(command -v apod-wallpaper || echo $HOME/.local/bin/apod-wallpaper)\""
    property var info: ({})          // output of `apod-wallpaper status`
    property bool busy: false
    property string busyText: ""
    property string error: ""
    readonly property bool randomMode: info.mode === "random"

    Plasmoid.icon: "kstars_planets-symbolic"
    toolTipMainText: info.title || "NASA APOD"
    toolTipSubText: busy ? busyText : (randomMode ? "Random" : "Latest") + (info.date ? " · " + info.date : "")

    function refresh() {
        exec.connectSource(command + " status")
    }

    function run(action, text) {
        if (busy) return
        busy = true
        busyText = text
        error = ""
        exec.connectSource(command + " " + action)
    }

    function showLatest() { run("latest", "Fetching today's picture…") }
    function showRandom() { run("random", "Fetching a random picture…") }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            if (source.endsWith(" status")) {
                try { root.info = JSON.parse(data.stdout) } catch (e) { }
                return
            }
            root.busy = false
            if (data["exit code"] !== 0) {
                // The first log line names the cause (rate limit, network…); later ones are follow-up.
                const cause = data.stderr.split("\n")
                    .map(l => l.replace(/^apod-wallpaper: /, "").trim())
                    .find(l => l && !/^(no picture fetched|applied|rendering|downloading)/.test(l))
                root.error = cause || "Couldn't fetch a picture"
            }
            root.refresh()
        }
    }

    Timer {
        interval: 5 * 60 * 1000   // pick up changes made by the daily timer
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
    onExpandedChanged: if (expanded) refresh()

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Latest picture of the day"
            icon.name: "view-calendar-day-symbolic"
            enabled: !root.busy
            onTriggered: root.showLatest()
        },
        PlasmaCore.Action {
            text: root.randomMode ? "Shuffle" : "Random pictures"
            icon.name: "media-playlist-shuffle"
            enabled: !root.busy
            onTriggered: root.showRandom()
        }
    ]

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 32
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            Kirigami.ShadowedImage {
                Layout.fillWidth: true
                Layout.preferredHeight: width * 10 / 16
                radius: Kirigami.Units.cornerRadius
                color: Kirigami.Theme.alternateBackgroundColor
                source: root.info.image ? "file://" + root.info.image : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 800
                asynchronous: true

                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    running: root.busy
                    visible: root.busy
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    wrapMode: Text.Wrap
                    text: root.info.title || "No picture yet"
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    opacity: 0.7
                    text: [root.info.date, root.info.credit ? "© " + root.info.credit : ""].filter(Boolean).join(" · ")
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    text: "Latest"
                    icon.name: "view-calendar-day-symbolic"
                    checked: !root.randomMode
                    enabled: !root.busy
                    onClicked: root.showLatest()
                    PlasmaComponents.ToolTip { text: "Show NASA's newest picture every day" }
                }
                PlasmaComponents.Button {
                    text: "Random"
                    icon.name: "roll"
                    checked: root.randomMode
                    enabled: !root.busy
                    onClicked: root.showRandom()
                    PlasmaComponents.ToolTip { text: "Show a random archive picture every day" }
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.ToolButton {
                    text: "Shuffle"
                    icon.name: "media-playlist-shuffle"
                    visible: root.randomMode
                    enabled: !root.busy
                    onClicked: root.showRandom()
                    PlasmaComponents.ToolTip { text: "Another random picture now" }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.busy || root.error !== ""
                wrapMode: Text.Wrap
                color: root.error !== "" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                text: root.busy ? root.busyText : root.error
            }

            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

                // A TextArea sizes itself to the ScrollView, avoiding a width binding loop.
                PlasmaComponents.TextArea {
                    readOnly: true
                    wrapMode: Text.Wrap
                    textFormat: TextEdit.PlainText
                    background: null
                    leftPadding: 0
                    selectByMouse: true
                    text: root.info.explanation || ""
                }
            }

            PlasmaComponents.ToolButton {
                Layout.alignment: Qt.AlignRight
                text: "Open on apod.nasa.gov"
                icon.name: "internet-web-browser-symbolic"
                enabled: !!root.info.page
                onClicked: Qt.openUrlExternally(root.info.page)
            }
        }
    }
}
