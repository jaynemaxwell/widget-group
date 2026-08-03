import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "widgetGroup"

    property string newGroupName: ""
    property string newGroupIcon: "widgets"

    // Which editor tab is active (see the DankTabBar in the edit card).
    property int currentTab: 0

    property string editingGroupId: ""
    property var editingGroup: null
    property string newMemberId: ""
    property int editingMemberIndex: -1
    // Hover-insert target: a new member is inserted before this index (-1 = append).
    property int addMemberTargetPos: -1
    property string editDisplay: "both"      // both | icon | text
    property bool editAutoCollapse: false
    property int editAutoCollapseSeconds: 5
    property bool editAutoCollapseOnLeave: false
    property string editExpandIndicatorPosition: ""
    property bool editShowArrow: true
    property bool editShowArrowOnlyOnHover: false
    property bool editCollapseOthers: false
    property bool editOverlayExpand: false
    property bool editShowExpandedBorder: true

    // Per-button click actions: "expand" | "command" | "widget" | "none"
    property string editLeftClickAction: "expand"
    property string editLeftClickCommand: ""
    property string editLeftClickWidget: ""
    property string editRightClickAction: "none"
    property string editRightClickCommand: ""
    property string editRightClickWidget: ""
    property string editMiddleClickAction: "none"
    property string editMiddleClickCommand: ""
    property string editMiddleClickWidget: ""

    // Members pinned to the collapsed view (icons shown even when folded).
    property var editCollapsedTargets: []

    // Treat the collapsed control (button + pinned icons) as one clickable item.
    property bool editUnifiedClick: false

    onVariantsChanged: {
        localGroups.clear()
        for (let i = 0; i < variants.length; i++) {
            const v = variants[i]
            localGroups.append({
                vid: v.id || "",
                vname: v.name || "",
                vicon: v.icon || "widgets",
                vcount: (v.targets ? v.targets.length : 0)
            })
        }
        if (editingGroupId !== "") {
            editingGroup = variants.find(v => v.id === editingGroupId) || null
            _loadClickActions(editingGroup)
            editExpandIndicatorPosition = editingGroup?.expandIndicatorPosition || ""
            editShowArrow = editingGroup?.showArrow !== false
            editShowArrowOnlyOnHover = editingGroup?.showArrowOnlyOnHover === true
            editCollapseOthers = editingGroup?.collapseOthers === true
            editOverlayExpand = editingGroup?.overlayExpand === true
            editShowExpandedBorder = editingGroup?.showExpandedBorder !== false
            editCollapsedTargets = (editingGroup?.collapsedTargets ?? []).slice()
            editUnifiedClick = editingGroup?.unifiedClick === true
            _syncMembers()
        }
    }

    ListModel { id: localGroups }
    ListModel { id: localMembers }

    function _syncMembers() {
        localMembers.clear()
        const t = editingGroup?.targets ?? []
        for (let i = 0; i < t.length; i++)
            localMembers.append({ mid: t[i] })
    }

    function _currentMembers() {
        const out = []
        for (let i = 0; i < localMembers.count; i++)
            out.push(localMembers.get(i).mid)
        return out
    }

    function _editMember(index) {
        const r = localMembers.get(index)
        if (!r) return
        editingMemberIndex = index
        newMemberId = r.mid
        memberPicker.currentValue = _nameFor(r.mid)
    }

    function _cancelMemberEdit() {
        editingMemberIndex = -1
        newMemberId = ""
        memberPicker.currentValue = ""
    }

    // ── Member add/edit dialog + drag reorder ───────────────────────────────────
    function _openAddMemberDialog() {
        _cancelMemberEdit()
        addMemberTargetPos = -1
        addMemberPopup.open()
    }

    // Insert before `pos` — the between-rows "+".
    function _openInsertMemberDialog(pos) {
        _cancelMemberEdit()
        addMemberTargetPos = pos
        addMemberPopup.open()
    }

    function _openEditMemberDialog(index) {
        addMemberTargetPos = -1
        _editMember(index)
        addMemberPopup.open()
    }

    function _commitMemberDialog() {
        if (!newMemberId) {
            ToastService.showError("Pick a widget plugin")
            return
        }
        const a = _currentMembers()
        const editing = editingMemberIndex >= 0 && editingMemberIndex < a.length
        if (editing)
            a[editingMemberIndex] = newMemberId
        else if (addMemberTargetPos >= 0 && addMemberTargetPos <= a.length)
            a.splice(addMemberTargetPos, 0, newMemberId)
        else
            a.push(newMemberId)
        _saveMembers(a)
        ToastService.showInfo(editing ? "Widget changed" : "Widget added")
        _cancelMemberEdit()
        addMemberTargetPos = -1
        addMemberPopup.close()
    }

    function _cancelMemberDialog() {
        _cancelMemberEdit()
        addMemberTargetPos = -1
        addMemberPopup.close()
    }

    // Drag reorder: move the member at `from` to insert-before position `to`.
    function _reorderMembers(from, to) {
        if (from < 0 || from >= localMembers.count) return
        let insert = to
        if (insert > from) insert -= 1
        if (insert === from) return
        const a = _currentMembers()
        const moved = a.splice(from, 1)[0]
        a.splice(insert, 0, moved)
        _saveMembers(a)
    }

    function _saveMembers(arr) {
        if (!editingGroupId || !pluginService) return
        // Drop pins / click-widget references that point at members no longer here.
        const collapsedTargets = (editCollapsedTargets || []).filter(id => arr.includes(id))
        editCollapsedTargets = collapsedTargets
        if (!arr.includes(editLeftClickWidget)) editLeftClickWidget = ""
        if (!arr.includes(editRightClickWidget)) editRightClickWidget = ""
        if (!arr.includes(editMiddleClickWidget)) editMiddleClickWidget = ""
        const cfg = { targets: arr, collapsedTargets,
            leftClickWidget: editLeftClickWidget,
            rightClickWidget: editRightClickWidget,
            middleClickWidget: editMiddleClickWidget }
        updateVariant(editingGroupId, cfg)
        editingGroup = Object.assign({}, editingGroup, cfg)
        _syncMembers()
        for (let i = 0; i < localGroups.count; i++) {
            if (localGroups.get(i).vid === editingGroupId) {
                localGroups.setProperty(i, "vcount", arr.length)
                break
            }
        }
    }

    function _selectGroup(v) {
        editingGroup = v
        // Load the per-click edit state BEFORE flipping editingGroupId: changing
        // editingGroupId re-seeds the command fields / widget dropdowns (via their
        // Connections), which must read this group's freshly-loaded values.
        _loadClickActions(v)
        editCollapsedTargets = (v.collapsedTargets ?? []).slice()
        editUnifiedClick = v.unifiedClick === true
        editNameField.text = v.name || ""
        editLabelField.text = v.label || ""
        editIconField.currentIcon = v.icon || "widgets"
        editDisplay = v.display || "both"
        editAutoCollapse = v.autoCollapse === true
        editAutoCollapseSeconds = (v.autoCollapseSeconds && v.autoCollapseSeconds >= 1) ? v.autoCollapseSeconds : 5
        editAutoCollapseOnLeave = v.autoCollapseOnLeave === true
        editExpandIndicatorPosition = v.expandIndicatorPosition || ""
        editShowArrow = v.showArrow !== false
        editShowArrowOnlyOnHover = v.showArrowOnlyOnHover === true
        editCollapseOthers = v.collapseOthers === true
        editOverlayExpand = v.overlayExpand === true
        editShowExpandedBorder = v.showExpandedBorder !== false
        newMemberId = ""
        editingMemberIndex = -1
        memberPicker.currentValue = ""
        _syncMembers()
        editingGroupId = v.id
    }

    function _saveGroupMeta() {
        if (!editingGroupId || !pluginService) return
        const nm = editNameField.text.trim()
        if (!nm) return
        const cfg = {
            name: nm,
            label: editLabelField.text.trim(),
            icon: editIconField.currentIcon || "widgets",
            display: editDisplay,
            autoCollapse: editAutoCollapse,
            autoCollapseSeconds: editAutoCollapseSeconds,
            autoCollapseOnLeave: editAutoCollapseOnLeave,
            expandIndicatorPosition: editExpandIndicatorPosition || "",
            showArrow: editShowArrow !== false,
            showArrowOnlyOnHover: editShowArrow ? editShowArrowOnlyOnHover === true : false,
            collapseOthers: editCollapseOthers === true,
            overlayExpand: editOverlayExpand === true,
            showExpandedBorder: editShowExpandedBorder === true,
            leftClickAction: editLeftClickAction,
            leftClickCommand: editLeftClickCommand,
            leftClickWidget: editLeftClickWidget,
            rightClickAction: editRightClickAction,
            rightClickCommand: editRightClickCommand,
            rightClickWidget: editRightClickWidget,
            middleClickAction: editMiddleClickAction,
            middleClickCommand: editMiddleClickCommand,
            middleClickWidget: editMiddleClickWidget,
            collapsedTargets: (editCollapsedTargets || []).slice(),
            unifiedClick: editUnifiedClick === true
        }
        updateVariant(editingGroupId, cfg)
        editingGroup = Object.assign({}, editingGroup, cfg)
        for (let i = 0; i < localGroups.count; i++) {
            if (localGroups.get(i).vid === editingGroupId) {
                localGroups.setProperty(i, "vname", nm)
                localGroups.setProperty(i, "vicon", cfg.icon)
                break
            }
        }
    }

    function _saveDisplay(v) { editDisplay = v; _saveGroupMeta() }
    function _saveAutoCollapse(v) { editAutoCollapse = v; _saveGroupMeta() }
    function _saveAutoCollapseOnLeave(v) { editAutoCollapseOnLeave = v; _saveGroupMeta() }
    function _saveAutoCollapseSeconds(v) { editAutoCollapseSeconds = v; _saveGroupMeta() }
    function _saveExpandIndicatorPosition(v) { editExpandIndicatorPosition = v; _saveGroupMeta() }
    function _saveShowArrow(v) {
        editShowArrow = v
        if (!v)
            editShowArrowOnlyOnHover = false
        _saveGroupMeta()
    }
    function _saveShowArrowOnlyOnHover(v) { editShowArrowOnlyOnHover = v; _saveGroupMeta() }
    function _saveUnifiedClick(v) { editUnifiedClick = v; _saveGroupMeta() }
    function _saveCollapseOthers(v) { editCollapseOthers = v; _saveGroupMeta() }
    function _saveOverlayExpand(v) { editOverlayExpand = v; _saveGroupMeta() }
    function _saveShowExpandedBorder(v) { editShowExpandedBorder = v; _saveGroupMeta() }

    // ── Per-button click actions ────────────────────────────────────────────────
    function _loadClickActions(v) {
        editLeftClickAction    = v?.leftClickAction    || "expand"
        editLeftClickCommand   = v?.leftClickCommand   || ""
        editLeftClickWidget    = v?.leftClickWidget    || ""
        editRightClickAction   = v?.rightClickAction   || "none"
        editRightClickCommand  = v?.rightClickCommand  || ""
        editRightClickWidget   = v?.rightClickWidget   || ""
        editMiddleClickAction  = v?.middleClickAction  || "none"
        editMiddleClickCommand = v?.middleClickCommand || ""
        editMiddleClickWidget  = v?.middleClickWidget  || ""
    }

    function _clickAction(btn) {
        return btn === "left" ? editLeftClickAction : btn === "right" ? editRightClickAction : editMiddleClickAction
    }
    function _clickCommand(btn) {
        return btn === "left" ? editLeftClickCommand : btn === "right" ? editRightClickCommand : editMiddleClickCommand
    }
    function _clickWidget(btn) {
        return btn === "left" ? editLeftClickWidget : btn === "right" ? editRightClickWidget : editMiddleClickWidget
    }
    function _saveClickAction(btn, v) {
        if (btn === "left") editLeftClickAction = v
        else if (btn === "right") editRightClickAction = v
        else editMiddleClickAction = v
        _saveGroupMeta()
    }
    function _saveClickCommand(btn, v) {
        if (btn === "left") editLeftClickCommand = v
        else if (btn === "right") editRightClickCommand = v
        else editMiddleClickCommand = v
        _saveGroupMeta()
    }
    function _saveClickWidget(btn, v) {
        if (btn === "left") editLeftClickWidget = v
        else if (btn === "right") editRightClickWidget = v
        else editMiddleClickWidget = v
        _saveGroupMeta()
    }

    // ── Collapsed-view pins ─────────────────────────────────────────────────────
    function _isCollapsedPinned(id) {
        return (editCollapsedTargets || []).indexOf(id) >= 0
    }
    function _toggleCollapsedPin(id) {
        const arr = (editCollapsedTargets || []).slice()
        const i = arr.indexOf(id)
        if (i >= 0) arr.splice(i, 1)
        else arr.push(id)
        editCollapsedTargets = arr
        _saveGroupMeta()
    }

    // DMS's built-in bar widgets (media controls, power menu, system tray, etc.)
    // are not PluginService plugins, so they do not appear in availablePluginsList.
    // Mirror the core widget catalog from DMS WidgetsTab so Widget Group can select
    // both core DMS widgets and third-party/system plugin widgets.
    readonly property var coreWidgetTargets: [
        { id: "workspaceSwitcher", name: "Workspace Switcher", icon: "view_module" },
        { id: "focusedWindow", name: "Focused Window", icon: "window" },
        { id: "runningApps", name: "Running Apps", icon: "apps" },
        { id: "appsDock", name: "Apps Dock", icon: "dock_to_bottom" },
        { id: "clock", name: "Clock", icon: "schedule" },
        { id: "weather", name: "Weather Widget", icon: "wb_sunny" },
        { id: "music", name: "Media Controls", icon: "music_note" },
        { id: "clipboard", name: "Clipboard Manager", icon: "content_paste" },
        { id: "cpuUsage", name: "CPU Usage", icon: "memory" },
        { id: "memUsage", name: "Memory Usage", icon: "developer_board" },
        { id: "diskUsage", name: "Disk Usage", icon: "storage" },
        { id: "cpuTemp", name: "CPU Temperature", icon: "device_thermostat" },
        { id: "gpuTemp", name: "GPU Temperature", icon: "auto_awesome_mosaic" },
        { id: "systemTray", name: "System Tray", icon: "notifications" },
        { id: "privacyIndicator", name: "Privacy Indicator", icon: "privacy_tip" },
        { id: "layout", name: "Layout", icon: "view_quilt" },
        { id: "controlCenterButton", name: "Control Center", icon: "settings" },
        { id: "notificationButton", name: "Notification Center", icon: "notifications" },
        { id: "battery", name: "Battery", icon: "battery_std" },
        { id: "vpn", name: "VPN", icon: "vpn_lock" },
        { id: "idleInhibitor", name: "Idle Inhibitor", icon: "motion_sensor_active" },
        { id: "capsLockIndicator", name: "Caps Lock Indicator", icon: "shift_lock" },
        { id: "spacer", name: "Spacer", icon: "more_horiz" },
        { id: "separator", name: "Separator", icon: "remove" },
        { id: "network_speed_monitor", name: "Network Speed Monitor", icon: "network_check" },
        { id: "keyboard_layout_name", name: "Keyboard Layout Name", icon: "keyboard" },
        { id: "notepadButton", name: "Notepad", icon: "assignment" },
        { id: "colorPicker", name: "Color Picker", icon: "palette" },
        { id: "systemUpdate", name: "System Update", icon: "update" },
        { id: "powerMenuButton", name: "Power", icon: "power_settings_new" }
    ]

    readonly property var availableTargets: {
        const targets = coreWidgetTargets.slice()
        if (!pluginService) return targets
        return targets.concat(pluginService.availablePluginsList
            .filter(p => p.id !== "widgetGroup"
                      && (p.type === "widget" || (pluginService.pluginWidgetComponents && pluginService.pluginWidgetComponents[p.id])))
            .map(p => ({ id: p.id, name: p.name, icon: p.icon || "extension" }))
            .sort((a, b) => String(a.name || "").localeCompare(String(b.name || ""), undefined, { sensitivity: "base" })))
    }
    readonly property var availableTargetNames: availableTargets.map(p => p.name)

    // Current members of the group being edited (ids + display names), for the
    // per-click "Open widget" dropdowns. Derived from editingGroup so it tracks
    // member add/remove/reorder.
    readonly property var memberIds: editingGroup?.targets ?? []
    readonly property var memberOptionNames: memberIds.map(id => _nameFor(id))

    function _memberIdForName(name) {
        const ids = root.memberIds
        for (let i = 0; i < ids.length; i++)
            if (_nameFor(ids[i]) === name) return ids[i]
        return ""
    }

    function _targetFor(id) {
        return availableTargets.find(p => p.id === id) || null
    }

    function _nameFor(id) {
        const t = _targetFor(id)
        return t ? t.name : id
    }

    function _iconFor(id) {
        const t = _targetFor(id)
        return t ? (t.icon || "extension") : "extension"
    }

    function _isCoreTarget(id) {
        return coreWidgetTargets.some(p => p.id === id)
    }

    function _isTargetAvailable(id) {
        return _isCoreTarget(id) || !!(pluginService && pluginService.availablePlugins[id]?.loaded)
    }

    // ── Header ─────────────────────────────────────────────────────────────────
    StyledText {
        width: parent.width
        text: "Widget Groups"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "One bar button that expands to reveal several widgets inline — each keeps its own live pill and popout. Create a group below, then select it to edit its settings."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ── Create group ───────────────────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: addCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: addCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Add Group"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: (parent.width - Theme.spacingM) / 2
                    spacing: Theme.spacingXS
                    StyledText { text: "Name"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                    DankTextField {
                        id: nameField
                        width: parent.width
                        placeholderText: "e.g. System"
                        onTextChanged: root.newGroupName = text
                    }
                }

                Column {
                    width: (parent.width - Theme.spacingM) / 2
                    spacing: Theme.spacingXS
                    StyledText { text: "Button icon"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                    DropdownIconPicker {
                        id: iconField
                        width: parent.width
                        currentIcon: "widgets"
                        onIconSelected: (name) => root.newGroupIcon = name
                    }
                }
            }

            DankButton {
                text: "Create Group"
                iconName: "add"
                onClicked: {
                    if (!root.newGroupName) {
                        ToastService.showError("Please enter a name")
                        return
                    }
                    const newId = createVariant(root.newGroupName, {
                        icon: root.newGroupIcon || "widgets",
                        label: "",
                        display: "both",
                        targets: [],
                        collapsedTargets: [],
                        unifiedClick: false,
                        expandIndicatorPosition: "",
                        showArrow: true,
                        showArrowOnlyOnHover: false,
                        collapseOthers: false,
                        overlayExpand: false,
                        showExpandedBorder: true,
                        leftClickAction: "expand",
                        leftClickCommand: "",
                        leftClickWidget: "",
                        rightClickAction: "none",
                        rightClickCommand: "",
                        rightClickWidget: "",
                        middleClickAction: "none",
                        middleClickCommand: "",
                        middleClickWidget: ""
                    })
                    if (newId) {
                        Qt.callLater(() => pluginService.reloadPlugin("widgetGroup"))
                        ToastService.showInfo("Group created: " + root.newGroupName)
                        root.newGroupName = ""
                        root.newGroupIcon = "widgets"
                        nameField.text = ""
                        iconField.currentIcon = "widgets"
                    } else {
                        ToastService.showError("Failed to save — plugin service unavailable")
                    }
                }
            }
        }
    }

    // ── Existing groups ─────────────────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: Math.max(80, groupsCol.implicitHeight + Theme.spacingL * 2)
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: groupsCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                text: "Your Groups"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                visible: localGroups.count === 0
                width: parent.width
                text: "No groups yet. Create one above."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: localGroups

                delegate: StyledRect {
                    required property string vid
                    required property string vname
                    required property string vicon
                    required property int vcount
                    required property int index

                    width: groupsCol.width
                    height: gRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: root.editingGroupId === vid
                        ? Theme.primaryContainer
                        : (gHover.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)

                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    MouseArea {
                        id: gHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Second click on the same row collapses the editor
                            if (root.editingGroupId === vid) {
                                root.editingGroupId = ""
                                root.editingGroup = null
                                return
                            }
                            const fresh = variants.find(v => v.id === vid) || null
                            if (fresh) root._selectGroup(fresh)
                        }
                    }

                    Row {
                        id: gRow
                        anchors.left: parent.left
                        anchors.right: gDel.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingM

                        DankIcon {
                            name: vicon || "widgets"
                            size: Theme.iconSize
                            color: root.editingGroupId === vid ? Theme.onPrimaryContainer : Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: parent.width - Theme.iconSize - Theme.spacingM

                            StyledText {
                                text: vname || "Unnamed"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: root.editingGroupId === vid ? Theme.onPrimaryContainer : Theme.surfaceText
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            StyledText {
                                text: vcount + " widget" + (vcount === 1 ? "" : "s")
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.editingGroupId === vid ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                                width: parent.width
                            }
                        }
                    }

                    Rectangle {
                        id: gDel
                        z: 1
                        width: 32; height: 32; radius: 16
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        color: gDelArea.containsMouse ? Theme.error : "transparent"

                        DankIcon {
                            anchors.centerIn: parent
                            name: "delete"; size: 16
                            color: gDelArea.containsMouse ? Theme.onError : Theme.surfaceVariantText
                        }

                        MouseArea {
                            id: gDelArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.editingGroupId === vid) {
                                    root.editingGroupId = ""
                                    root.editingGroup = null
                                }
                                removeVariant(vid)
                                Qt.callLater(() => pluginService.reloadPlugin("widgetGroup"))
                                ToastService.showInfo("Group removed")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Edit selected group (tabbed) ────────────────────────────────────────────
    StyledRect {
        width: parent.width
        height: editCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        visible: root.editingGroupId !== ""

        Column {
            id: editCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                width: parent.width
                text: (root.editingGroup?.name || "Group") + " — Settings"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            // ---- Tab bar ----------------------------------------------------
            Item {
                width: parent.width
                height: 45 + Theme.spacingS

                DankTabBar {
                    id: editTabBar
                    width: Math.min(parent.width, 720)
                    height: 45
                    anchors.horizontalCenter: parent.horizontalCenter
                    currentIndex: root.currentTab
                    model: [
                        { text: "Setup", icon: "school" },
                        { text: "Definition", icon: "badge" },
                        { text: "Actions", icon: "ads_click" },
                        { text: "Behavior", icon: "tune" },
                        { text: "Members", icon: "widgets" }
                    ]

                    Component.onCompleted: Qt.callLater(updateIndicator)

                    onTabClicked: index => {
                        root.currentTab = index;
                        currentIndex = index;
                    }
                }
            }

            // ==== Tab 0: Setup ==============================================
            Column {
                visible: root.currentTab === 0
                width: parent.width
                spacing: Theme.spacingM

                Row {
                    spacing: Theme.spacingS
                    DankIcon { name: "info"; size: Theme.iconSize; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    StyledText {
                        text: "How to use"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                StyledText {
                    width: parent.width
                    text: "1. Enable the widget plugins you want to group (DMS built-ins need no setup)\n2. Create a group above, then select it in Your Groups to edit (click again to collapse the editor)\n3. Definition — set the button icon, label, and what the button shows (icon/text/both/nothing)\n4. Actions — assign the left / right / middle mouse clicks: expand/collapse, run a command, open a member widget, or nothing (left defaults to expand/collapse)\n5. Behavior — the expand/collapse symbol, overlay mode, one-open-at-a-time, expanded border, and auto-collapse\n6. Members — click “Add widget…” (or the + that appears between rows) to add members via a dialog; drag the handle to reorder, click a row to change its widget, ✕ to remove, or the pin to keep a member's icon visible while collapsed\n7. Go to Bar Settings → Add Widget to place the group on your bar\n\nOn the bar, each mouse button runs the action you assigned it. Pinned member icons stay on the bar beside the button even while the group is collapsed."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    lineHeight: 1.5
                }

                Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant; opacity: 0.5 }

                StyledText { text: "How members expand"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText }
                StyledText {
                    width: parent.width
                    text: "When expanded, the grouped widgets unfold toward the open part of the bar: a group on the right side opens to the left, otherwise it opens to the right (and the equivalent below/above on a vertical bar). The direction adjusts automatically to where the group sits — and the chevrons follow it — so there's nothing to configure."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            // ==== Tab 1: Definition (name / icon / label / display) =========
            Column {
                visible: root.currentTab === 1
                width: parent.width
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    Column {
                        width: (parent.width - Theme.spacingM) / 2
                        spacing: Theme.spacingXS
                        StyledText { text: "Name"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                        DankTextField {
                            id: editNameField
                            width: parent.width
                            placeholderText: "Group name"
                            onEditingFinished: root._saveGroupMeta()
                        }
                    }

                    Column {
                        width: (parent.width - Theme.spacingM) / 2
                        spacing: Theme.spacingXS
                        StyledText { text: "Button icon"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                        DropdownIconPicker {
                            id: editIconField
                            width: parent.width
                            onIconSelected: (name) => root._saveGroupMeta()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    StyledText { text: "Button label (optional)"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                    DankTextField {
                        id: editLabelField
                        width: parent.width
                        placeholderText: "Text shown on the button"
                        onEditingFinished: root._saveGroupMeta()
                    }
                }

                Column {
                    spacing: Theme.spacingXS
                    StyledText { text: "Button shows"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                    Row {
                        spacing: Theme.spacingS
                        Repeater {
                            model: [
                                { value: "both", label: "Icon & Text" },
                                { value: "icon", label: "Icon only"  },
                                { value: "text", label: "Text only"  },
                                { value: "none", label: "Nothing"     }
                            ]
                            delegate: DankButton {
                                required property var modelData
                                text: modelData.label
                                buttonHeight: 32
                                backgroundColor: root.editDisplay === modelData.value ? Theme.primary : Theme.surfaceContainerHigh
                                textColor: root.editDisplay === modelData.value ? Theme.onPrimary : Theme.surfaceText
                                onClicked: root._saveDisplay(modelData.value)
                            }
                        }
                    }
                }
            }

            // ==== Tab 2: Click Actions ======================================
            Column {
                visible: root.currentTab === 2
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    width: parent.width
                    text: "Assign what each mouse button does when the group button is clicked: expand the group, run a shell command, open one of the member widgets, or nothing. The expand/collapse symbols always fold and unfold the group, whatever you assign here. Once the group is expanded, its member widgets take their own clicks and behave exactly as they do anywhere else on the bar."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: [
                        { key: "left", label: "Left click" },
                        { key: "right", label: "Right click" },
                        { key: "middle", label: "Middle click" }
                    ]

                    delegate: Column {
                        id: clickRow
                        required property var modelData
                        width: parent.width
                        spacing: Theme.spacingXS

                        readonly property string btn: modelData.key

                        StyledText {
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingS
                            Repeater {
                                model: [
                                    { value: "expand", label: "Expand/collapse" },
                                    { value: "command", label: "Run command" },
                                    { value: "widget", label: "Open widget" },
                                    { value: "none", label: "Do nothing" }
                                ]
                                delegate: DankButton {
                                    required property var modelData
                                    text: modelData.label
                                    buttonHeight: 32
                                    backgroundColor: root._clickAction(clickRow.btn) === modelData.value ? Theme.primary : Theme.surfaceContainerHigh
                                    textColor: root._clickAction(clickRow.btn) === modelData.value ? Theme.onPrimary : Theme.surfaceText
                                    onClicked: root._saveClickAction(clickRow.btn, modelData.value)
                                }
                            }
                        }

                        DankTextField {
                            id: cmdField
                            width: parent.width
                            visible: root._clickAction(clickRow.btn) === "command"
                            placeholderText: "Command to run, e.g. kitty"
                            text: root._clickCommand(clickRow.btn)
                            onEditingFinished: root._saveClickCommand(clickRow.btn, text)
                            // Re-seed from the group's saved value when a different
                            // group is selected (user edits break the binding above).
                            Connections {
                                target: root
                                function onEditingGroupIdChanged() { cmdField.text = root._clickCommand(clickRow.btn) }
                            }
                        }

                        DankDropdown {
                            id: widgetDropdown
                            width: parent.width
                            visible: root._clickAction(clickRow.btn) === "widget"
                            emptyText: root.memberOptionNames.length > 0 ? "Select a member widget…" : "Add member widgets first"
                            options: root.memberOptionNames
                            currentValue: root._clickWidget(clickRow.btn) ? root._nameFor(root._clickWidget(clickRow.btn)) : ""
                            onValueChanged: (value) => root._saveClickWidget(clickRow.btn, root._memberIdForName(value))
                            Connections {
                                target: root
                                function onEditingGroupIdChanged() {
                                    widgetDropdown.currentValue = root._clickWidget(clickRow.btn) ? root._nameFor(root._clickWidget(clickRow.btn)) : ""
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant; opacity: 0.5 }

                DankToggle {
                    width: parent.width
                    text: "Treat pinned icons as one button"
                    description: "While collapsed, the button and any pinned member icons act as a single item — clicking anywhere on them fires the assigned mouse action (like the Control Center bar widget), instead of the pinned widgets responding on their own. The expand/collapse symbol is excluded: left-clicking it always folds/unfolds the group. Expanded members stay individually clickable."
                    checked: root.editUnifiedClick
                    onToggled: (checked) => root._saveUnifiedClick(checked)
                }
            }

            // ==== Tab 3: Behavior ===========================================
            Column {
                visible: root.currentTab === 3
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText { text: "Expand/collapse symbol position"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                    Flow {
                        width: parent.width
                        spacing: Theme.spacingS
                        Repeater {
                            model: [
                                { value: "", label: "Auto" },
                                { value: "right", label: "Right" },
                                { value: "left", label: "Left" },
                                { value: "bottom", label: "Bottom" },
                                { value: "top", label: "Top" }
                            ]
                            delegate: DankButton {
                                required property var modelData
                                text: modelData.label
                                buttonHeight: 32
                                backgroundColor: root.editExpandIndicatorPosition === modelData.value ? Theme.primary : Theme.surfaceContainerHigh
                                textColor: root.editExpandIndicatorPosition === modelData.value ? Theme.onPrimary : Theme.surfaceText
                                onClicked: root._saveExpandIndicatorPosition(modelData.value)
                            }
                        }
                    }

                    DankToggle {
                        width: parent.width
                        text: "Show expand/collapse symbol"
                        description: "Turning it off needs an icon or text on the button — with nothing else to show, the symbol stays visible so the group can still be unfolded."
                        checked: root.editShowArrow
                        onToggled: (checked) => root._saveShowArrow(checked)
                    }

                    DankToggle {
                        width: parent.width
                        visible: root.editShowArrow
                        text: "Show symbol only on hover"
                        description: "Keep the expand/collapse symbol hidden until the group is hovered — its space is given back while hidden, so the group closes up instead of leaving a gap. If the button shows no icon or text, this needs at least one pinned member icon to hover — with nothing else on the bar, the symbol stays visible. While expanded the symbol always shows, since it's the collapse control."
                        checked: root.editShowArrowOnlyOnHover
                        onToggled: (checked) => root._saveShowArrowOnlyOnHover(checked)
                    }

                    DankToggle {
                        width: parent.width
                        text: "Collapse other groups when this opens"
                        description: "When this group expands, automatically collapse any other open group. Enable it on each group for strict one-open-at-a-time behaviour."
                        checked: root.editCollapseOthers
                        onToggled: (checked) => root._saveCollapseOthers(checked)
                    }

                    DankToggle {
                        width: parent.width
                        text: "Overlay when expanded (don't push other widgets)"
                        description: "Keep the bar footprint at the collapsed size when expanded — members overflow and paint on top of neighbouring widgets instead of pushing them aside. They first fill any free space in this group's own section, then spill over. Paints over reliably for a group in the centre section; a left/right group can only paint over its own section."
                        checked: root.editOverlayExpand
                        onToggled: (checked) => root._saveOverlayExpand(checked)
                    }

                    DankToggle {
                        width: parent.width
                        text: "Show border around expanded group"
                        description: "Draw a thin outline around the expanded group's backing so it stays delineated from the bar — useful when the bar background is opaque and a similar tone."
                        checked: root.editShowExpandedBorder
                        onToggled: (checked) => root._saveShowExpandedBorder(checked)
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant; opacity: 0.5 }

                // Auto-collapse behaviour
                DankToggle {
                    width: parent.width
                    text: "Auto-collapse"
                    description: "Collapse the group automatically after it has been expanded"
                    checked: root.editAutoCollapse
                    onToggled: (checked) => root._saveAutoCollapse(checked)
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.editAutoCollapse

                    StyledText {
                        text: "Stay open for " + root.editAutoCollapseSeconds + " second" + (root.editAutoCollapseSeconds === 1 ? "" : "s")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    DankSlider {
                        width: parent.width
                        minimum: 1
                        maximum: 30
                        step: 1
                        unit: "s"
                        value: root.editAutoCollapseSeconds
                        onSliderValueChanged: (newValue) => root.editAutoCollapseSeconds = newValue
                        onSliderDragFinished: (finalValue) => root._saveAutoCollapseSeconds(finalValue)
                    }

                    DankToggle {
                        width: parent.width
                        text: "Only start the timer after the mouse leaves"
                        description: "The countdown pauses while you're hovering the expanded group, and (re)starts when you move away"
                        checked: root.editAutoCollapseOnLeave
                        onToggled: (checked) => root._saveAutoCollapseOnLeave(checked)
                    }
                }
            }

            // ==== Tab 4: Members ============================================
            Column {
                visible: root.currentTab === 4
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    text: "Member widgets (order shown when expanded)"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width
                    text: "Drag the handle to reorder. Hover the gap between rows and click the + to insert a widget at that spot. Click a row to change its widget, use the pin to keep its icon on the bar while the group is collapsed, or ✕ to remove."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                DankButton {
                    text: "Add widget…"
                    iconName: "add"
                    onClicked: root._openAddMemberDialog()
                }

                StyledText {
                    visible: localMembers.count === 0
                    text: "No widgets yet. Click “Add widget…”."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                ListView {
                    id: membersListView
                    width: parent.width
                    height: contentHeight
                    model: localMembers
                    interactive: false
                    spacing: Theme.spacingS

                    property int draggedIndex: -1    // index being dragged
                    property int dropIndex: -1       // insert-before position; count = append
                    property int dropAboveIndex: -1  // row to draw the line above; -1 = append line

                    function updateDropIndex(dragIdx, localY) {
                        let above = -1
                        for (let i = 0; i < localMembers.count; i++) {
                            const del = itemAtIndex(i)
                            if (del && localY < del.y + del.height / 2) { above = i; break }
                        }
                        draggedIndex = dragIdx
                        dropIndex = above === -1 ? localMembers.count : above
                        dropAboveIndex = above
                    }

                    function finishDrag() {
                        const from = draggedIndex
                        const to = dropIndex
                        draggedIndex = -1; dropIndex = -1; dropAboveIndex = -1
                        if (from < 0) return
                        root._reorderMembers(from, to)
                    }

                    move: Transition {
                        NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.InOutQuad }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.InOutQuad }
                    }

                    delegate: Item {
                        id: memberDelegate
                        required property string mid
                        required property int index

                        width: membersListView.width
                        height: mCard.height

                        StyledRect {
                            id: mCard
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: mRow.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: root.editingMemberIndex === index
                                ? Theme.primaryContainer
                                : (editMemberArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)
                            opacity: membersListView.draggedIndex === index ? 0.5 : 1.0

                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                            // Reorder drop indicators: before this row, or after the last row.
                            Rectangle {
                                width: parent.width; height: 2; color: Theme.primary
                                anchors.top: parent.top; anchors.topMargin: -Theme.spacingS / 2
                                visible: membersListView.draggedIndex >= 0 && membersListView.dropAboveIndex === index
                            }
                            Rectangle {
                                width: parent.width; height: 2; color: Theme.primary
                                anchors.bottom: parent.bottom; anchors.bottomMargin: -Theme.spacingS / 2
                                visible: membersListView.draggedIndex >= 0 && membersListView.dropAboveIndex === -1
                                         && index === localMembers.count - 1
                            }

                            // Click the row (outside the handle/pin/remove) to edit it in the dialog.
                            MouseArea {
                                id: editMemberArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._openEditMemberDialog(memberDelegate.index)
                            }

                            Row {
                                id: mRow
                                anchors.left: parent.left
                                anchors.right: mMain.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingS

                                // Reorder handle
                                Rectangle {
                                    width: 24; height: 32; radius: 4
                                    color: reorderArea.pressed ? Theme.surfaceContainerHighest : "transparent"
                                    anchors.verticalCenter: parent.verticalCenter

                                    DankIcon { anchors.centerIn: parent; name: "reorder"; size: 18; color: Theme.surfaceVariantText }

                                    MouseArea {
                                        id: reorderArea
                                        anchors.fill: parent
                                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        preventStealing: true
                                        onPressed: (mouse) => { mouse.accepted = true; const p = mapToItem(membersListView, mouse.x, mouse.y); membersListView.updateDropIndex(memberDelegate.index, p.y) }
                                        onPositionChanged: (mouse) => { if (!pressed) return; mouse.accepted = true; const p = mapToItem(membersListView, mouse.x, mouse.y); membersListView.updateDropIndex(memberDelegate.index, p.y) }
                                        onReleased: (mouse) => { mouse.accepted = true; membersListView.finishDrag() }
                                        onCanceled: { membersListView.draggedIndex = -1; membersListView.dropIndex = -1; membersListView.dropAboveIndex = -1 }
                                    }
                                }

                                DankIcon {
                                    name: root._iconFor(mid)
                                    size: Theme.iconSize - 4
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    width: parent.width - 24 - (Theme.iconSize - 4) - parent.spacing * 2

                                    StyledText {
                                        text: root._nameFor(mid)
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    StyledText {
                                        visible: !root._isTargetAvailable(mid)
                                        text: "not available"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.error
                                    }
                                }
                            }

                            Rectangle {
                                id: mMain
                                width: 32; height: 32; radius: 16
                                color: root._isCollapsedPinned(mid)
                                    ? Theme.primary
                                    : (mainArea.containsMouse ? Theme.surfaceContainerHighest : "transparent")
                                border.width: root._isCollapsedPinned(mid) || mainArea.containsMouse ? 1 : 0
                                border.color: root._isCollapsedPinned(mid) ? Theme.primary : Theme.outlineVariant
                                anchors.right: mDel.left
                                anchors.rightMargin: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "push_pin"
                                    rotation: root._isCollapsedPinned(mid) ? 0 : 45
                                    size: 14
                                    color: root._isCollapsedPinned(mid)
                                        ? Theme.onPrimary
                                        : (mainArea.containsMouse ? Theme.primary : Theme.surfaceVariantText)
                                }
                                MouseArea {
                                    id: mainArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root._toggleCollapsedPin(mid)
                                }

                                Rectangle {
                                    visible: mainArea.containsMouse
                                    z: 1000
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: Theme.spacingXS
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: mMainTip.implicitWidth + Theme.spacingM
                                    height: mMainTip.implicitHeight + Theme.spacingXS * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainerHigh
                                    border.width: 1
                                    border.color: Theme.outlineVariant
                                    StyledText {
                                        id: mMainTip
                                        anchors.centerIn: parent
                                        text: root._isCollapsedPinned(mid) ? "Shown when collapsed" : "Show when collapsed"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                    }
                                }
                            }

                            Rectangle {
                                id: mDel
                                width: 32; height: 32; radius: 16
                                color: mDelArea.containsMouse ? Theme.error : "transparent"
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                DankIcon { anchors.centerIn: parent; name: "close"; size: 14; color: mDelArea.containsMouse ? Theme.onError : Theme.surfaceVariantText }
                                MouseArea {
                                    id: mDelArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const a = root._currentMembers()
                                        a.splice(memberDelegate.index, 1)
                                        root._saveMembers(a)
                                    }
                                }

                                Rectangle {
                                    visible: mDelArea.containsMouse
                                    z: 1000
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: Theme.spacingXS
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: mDelTip.implicitWidth + Theme.spacingM
                                    height: mDelTip.implicitHeight + Theme.spacingXS * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainerHigh
                                    border.width: 1
                                    border.color: Theme.outlineVariant
                                    StyledText {
                                        id: mDelTip
                                        anchors.centerIn: parent
                                        text: "Remove from group"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                    }
                                }
                            }
                        }

                        // Hover the gap above a row to reveal a "+" that inserts a
                        // new member *before* it (Word-table style).
                        Item {
                            z: 10
                            anchors.left: mCard.left
                            anchors.right: mCard.right
                            anchors.top: parent.top
                            anchors.topMargin: -membersListView.spacing
                            height: membersListView.spacing + 6
                            visible: membersListView.draggedIndex < 0

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 2
                                radius: 1
                                color: Theme.primary
                                visible: insertArea.containsMouse
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 20; height: 20; radius: 10
                                color: Theme.primary
                                visible: insertArea.containsMouse
                                DankIcon { anchors.centerIn: parent; name: "add"; size: 14; color: Theme.onPrimary }
                            }

                            MouseArea {
                                id: insertArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._openInsertMemberDialog(memberDelegate.index)
                            }
                        }
                    }
                }
            }
        }

        // ── Add / Edit member dialog ────────────────────────────────────────────
        // Adding/editing a member happens in a focused modal dialog (same pattern
        // as the Dropdown Menu plugin) instead of an inline form below the list.
        Popup {
            id: addMemberPopup
            parent: Overlay.overlay
            modal: true
            dim: false
            padding: 0
            closePolicy: Popup.CloseOnEscape   // Esc closes; outside-click is the scrim below
            x: 0
            y: 0
            width: Overlay.overlay?.width ?? 900
            height: Overlay.overlay?.height ?? 800

            background: Rectangle { color: "transparent" }

            contentItem: Item {
                // Scrim over the whole overlay: a click outside the card cancels.
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                    MouseArea { anchors.fill: parent; onClicked: root._cancelMemberDialog() }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(480, parent.width - 80)
                    height: memberDialogCol.implicitHeight + Theme.spacingL * 2
                    color: Theme.surface
                    radius: Theme.cornerRadius

                    MouseArea { anchors.fill: parent }   // absorb clicks so they don't hit the scrim

                    Column {
                        id: memberDialogCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingM

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                text: root.editingMemberIndex >= 0 ? "Change Widget" : "Add Widget"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // "at position N" chip when inserting between rows.
                            Rectangle {
                                visible: root.editingMemberIndex < 0 && root.addMemberTargetPos >= 0
                                height: 22
                                width: posRow.implicitWidth + Theme.spacingS * 2
                                radius: 11
                                color: Theme.primaryContainer
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: posRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS
                                    DankIcon { name: "low_priority"; size: 12; color: Theme.onPrimaryContainer; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText {
                                        text: "at position " + (root.addMemberTargetPos + 1)
                                        font.pixelSize: 10
                                        color: Theme.onPrimaryContainer
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS
                            StyledText { text: "Widget"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            DankDropdown {
                                id: memberPicker
                                width: parent.width
                                emptyText: "Select a widget plugin…"
                                enableFuzzySearch: true
                                options: root.availableTargetNames
                                onValueChanged: (value) => {
                                    const idx = root.availableTargetNames.indexOf(value)
                                    root.newMemberId = idx >= 0 ? root.availableTargets[idx].id : ""
                                }
                            }
                        }

                        Row {
                            spacing: Theme.spacingS

                            DankButton {
                                text: root.editingMemberIndex >= 0 ? "Save" : "Add"
                                iconName: root.editingMemberIndex >= 0 ? "check" : "add"
                                onClicked: root._commitMemberDialog()
                            }

                            DankButton {
                                text: "Cancel"
                                backgroundColor: Theme.surfaceContainerHigh
                                textColor: Theme.surfaceText
                                onClicked: root._cancelMemberDialog()
                            }
                        }
                    }
                }
            }
        }
    }
}
