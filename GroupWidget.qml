import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// A collapsible group: one toggle button on the bar that expands to reveal a row
// of real, live widgets (each a target plugin's pill + working popout). Members
// render inline in the bar window, so their popouts position below the bar
// correctly — the whole reason this works where a dropdown panel didn't.
PluginComponent {
    id: root

    property string variantId: ""
    property var variantData: null
    property var popoutService: null

    property bool expanded: false

    // When this group expands and "collapse others" is on, broadcast our id via a
    // shared (in-memory) global var; every other group instance collapses itself.
    onExpandedChanged: {
        if (root.expanded && root.collapseOthers && pluginService)
            pluginService.setGlobalVar(root.pluginId, "openGroup", root.variantId)
    }

    Connections {
        target: pluginService
        function onPluginDataChanged(changedId) {
            if (changedId !== root.pluginId || root.variantId === "") return
            const fresh = pluginService.getPluginVariantData(root.pluginId, root.variantId)
            if (fresh) root.variantData = fresh
        }
        function onGlobalVarChanged(changedId, varName) {
            if (changedId !== root.pluginId || varName !== "openGroup")
                return
            const opener = pluginService.getGlobalVar(root.pluginId, "openGroup", "")
            if (opener && opener !== root.variantId && root.expanded)
                root.expanded = false
        }
    }

    readonly property var targets: variantData?.targets ?? []
    readonly property string groupIcon: variantData?.icon || "widgets"
    readonly property string groupLabel: variantData?.label || ""
    readonly property string groupDisplay: variantData?.display || "both"
    readonly property string expandIndicatorPosition: variantData?.expandIndicatorPosition || ""
    readonly property bool showArrow: variantData?.showArrow !== false
    readonly property bool showArrowOnlyOnHover: variantData?.showArrowOnlyOnHover === true
    readonly property bool collapseOthers: variantData?.collapseOthers === true

    // Per-button click actions. Each button ("left"/"right"/"middle") maps to an
    // action: "expand" (toggle the group), "command" (run a shell command),
    // "widget" (activate a chosen member), or "none". Left defaults to expand.
    readonly property string leftClickAction:    variantData?.leftClickAction    || "expand"
    readonly property string leftClickCommand:   variantData?.leftClickCommand   || ""
    readonly property string leftClickWidget:    variantData?.leftClickWidget    || ""
    readonly property string rightClickAction:   variantData?.rightClickAction   || "none"
    readonly property string rightClickCommand:  variantData?.rightClickCommand  || ""
    readonly property string rightClickWidget:   variantData?.rightClickWidget   || ""
    readonly property string middleClickAction:  variantData?.middleClickAction  || "none"
    readonly property string middleClickCommand: variantData?.middleClickCommand || ""
    readonly property string middleClickWidget:  variantData?.middleClickWidget  || ""

    // Members pinned to the collapsed view: their icons stay visible on the bar
    // even when the group is folded, sitting beside the toggle button.
    readonly property var collapsedTargets: variantData?.collapsedTargets ?? []

    // Unified click: treat the collapsed control (toggle content + pinned icons) as
    // one button — a click anywhere on it fires the assigned mouse action, and the
    // pinned members don't handle their own clicks (like a DMS control-center pill).
    readonly property bool unifiedClick: variantData?.unifiedClick === true
    // Overlay mode: when expanded, don't reserve layout space (don't push other
    // widgets) — members overflow and paint on top instead.
    readonly property bool overlayExpand: variantData?.overlayExpand === true
    // Outline around the expanded backing (helps delineate the group on opaque bars).
    readonly property bool showExpandedBorder: variantData?.showExpandedBorder !== false

    // Paint over neighbouring widgets by raising the bar's section-delegate z.
    // Reaches into the bar item tree (root → WidgetHost → section cell), so it's
    // best-effort: if the hierarchy differs it simply no-ops (members would just
    // render under later siblings, as without overlay).
    //
    // Tied to the *setting*, not the expanded state: raise it once and leave it,
    // so collapsing and re-expanding can't drop us back behind a neighbour (a
    // collapsed group is only the toggle, so a high z has no visual cost).
    function _updateOverlayZ() {
        const want = root.overlayExpand ? 1000 : 0
        const host = root.parent                   // WidgetHost (Loader)
        const cell = host ? host.parent : null     // section-row delegate (the painting sibling)
        if (host) host.z = want
        if (cell) cell.z = want
    }
    onOverlayExpandChanged: _updateOverlayZ()
    Component.onCompleted: Qt.callLater(_updateOverlayZ)

    property var _memberRefs: ({})

    // Bumped whenever a member's size or the pinned set changes, so the overlay
    // footprint (which sums pinned members) re-evaluates.
    property int _pinRev: 0
    function _bumpPinRev() { root._pinRev = root._pinRev + 1 }

    // "both" | "icon" | "text" | "none". "none" shows neither icon nor label —
    // just the expand/collapse symbol next to any pinned members.
    readonly property bool showIcon:  groupDisplay === "both" || groupDisplay === "icon"
    readonly property bool showLabel: (groupDisplay === "both" || groupDisplay === "text") && groupLabel !== ""
    readonly property bool hasToggleContent: showIcon || showLabel

    // Auto-orient expansion by the toggle's position on screen so members unfold
    // toward the open part of the bar: a group in the right half opens left (up
    // on a vertical bar), otherwise it opens right (down). Computed only while
    // collapsed — from the toggle, which is stable then — so there's no feedback
    // once members start growing. The chevrons, end-cap marker, and member layout
    // all derive from hLeft/vUp, so they stay consistent with the real direction.
    property bool _autoHLeft: false
    property bool _autoVUp: false
    readonly property bool hLeft: _autoHLeft
    readonly property bool vUp:   _autoVUp

    function _barExtent(vertical) {
        const win = root.blurBarWindow
        if (win) {
            const d = vertical ? win.height : win.width
            if (d > 0) return d
        }
        if (root.parentScreen) {
            const d = vertical ? root.parentScreen.height : root.parentScreen.width
            if (d > 0) return d
        }
        return 0
    }

    // Deadband around the centre: near the midpoint the toggle's position can sit
    // exactly on the boundary and jitter cx > w/2 back and forth, which flips
    // _autoHLeft and cancels the chevron's expand/collapse flip. Only commit a
    // change once the toggle is clearly past centre; keep the current value inside
    // the band.
    function _recomputeHDir(toggleItem) {
        if (root.expanded || !toggleItem) return
        // A hover-hidden toggle is out of the layout, so its position is stale —
        // measure the collapsed row around it instead.
        const ref = toggleItem.visible ? toggleItem : toggleItem.parent
        if (!ref) return
        const w = root._barExtent(false)
        if (w <= 0) return
        const cx = ref.mapToItem(null, ref.width / 2, 0).x
        const margin = w * 0.04
        if (cx > w / 2 + margin) root._autoHLeft = true
        else if (cx < w / 2 - margin) root._autoHLeft = false
    }

    function _recomputeVDir(toggleItem) {
        if (root.expanded || !toggleItem) return
        const ref = toggleItem.visible ? toggleItem : toggleItem.parent   // see _recomputeHDir
        if (!ref) return
        const h = root._barExtent(true)
        if (h <= 0) return
        const cy = ref.mapToItem(null, 0, ref.height / 2).y
        const margin = h * 0.04
        if (cy > h / 2 + margin) root._autoVUp = true
        else if (cy < h / 2 - margin) root._autoVUp = false
    }
    readonly property bool toggleArrowBeforeContent: {
        const pos = root._resolvedExpandIndicatorPosition()
        return pos === "left" || pos === "top"
    }

    // Auto-collapse behaviour
    readonly property bool autoCollapse: variantData?.autoCollapse === true
    readonly property int autoCollapseSeconds: {
        const s = variantData?.autoCollapseSeconds
        return (s && s >= 1) ? s : 5
    }
    readonly property bool autoCollapseOnLeave: variantData?.autoCollapseOnLeave === true
    property bool hovered: false

    function _barPosition() {
        const edge = root.axis?.edge || "top"
        return edge === "left" ? 2 : (edge === "right" ? 3 : (edge === "top" ? 0 : 1))
    }

    function _registerMember(targetId, member) {
        if (!targetId || !member)
            return
        const refs = Object.assign({}, root._memberRefs || {})
        refs[targetId] = member
        root._memberRefs = refs
        root._bumpPinRev()
    }

    function _unregisterMember(targetId, member) {
        if (!targetId || !member || !root._memberRefs || !root._memberRefs[targetId])
            return
        if (root._memberRefs[targetId] !== member)
            return
        const refs = Object.assign({}, root._memberRefs)
        delete refs[targetId]
        root._memberRefs = refs
        root._bumpPinRev()
    }

    function _activateMember(targetId) {
        if (!targetId)
            return false
        const member = root._memberRefs?.[targetId]
        if (!member || typeof member.triggerMainAction !== "function")
            return false
        return member.triggerMainAction()
    }

    function _runCommand(cmd) {
        const c = (cmd || "").trim()
        if (!c)
            return
        try {
            Quickshell.execDetached(["sh", "-c", c])
        } catch (e) {
            console.warn("[widgetGroup] command failed:", c, ":", e)
        }
    }

    // Whether a member is pinned to (shown in) the collapsed view.
    function _isMemberPinned(targetId) {
        return root.collapsedTargets.indexOf(targetId) >= 0
    }

    // A member reserves space / renders when the group is expanded, or when it's
    // pinned to the collapsed view.
    function _isMemberShown(targetId) {
        return root.expanded || root._isMemberPinned(targetId)
    }

    // Primary-axis extent of the always-shown content (toggle + pinned members),
    // used as the overlay-mode footprint so pinned icons reserve their space while
    // only the expand-only members overflow and paint on top. Reads _pinRev,
    // targets, collapsedTargets and _memberRefs so it re-evaluates on any change.
    function _pinnedFootprint(vertical, toggleSize, spacing) {
        const _tick = root._pinRev
        const refs = root._memberRefs || {}
        let total = toggleSize
        for (let i = 0; i < root.targets.length; i++) {
            const id = root.targets[i]
            if (!root._isMemberPinned(id))
                continue
            const m = refs[id]
            if (!m)
                continue
            const s = vertical ? m.implicitHeight : m.implicitWidth
            if (s > 0)
                total += (total > 0 ? spacing : 0) + s   // no leading gap when the toggle is hidden
        }
        return total
    }

    function _resolvedExpandIndicatorPosition() {
        if (root.expandIndicatorPosition)
            return root.expandIndicatorPosition
        const edge = root.axis?.edge || "top"
        return (edge === "left" || edge === "right") ? "bottom" : "right"
    }

    // Hiding the symbol takes it out of the layout entirely (the slot is `visible:
    // false`, so Row/Column drop it and its spacing) — the group closes up rather than
    // leaving a gap, and re-hovering reopens it. Kept on while expanded: the symbol is
    // the collapse control there, and an open group shouldn't reshuffle on hover.
    function _shouldShowArrow(hovered) {
        const hoverOnly = root.showArrow && root.showArrowOnlyOnHover && !root.expanded
        // Symbol-only toggle (display "none"): the symbol *is* the button, so it never
        // switches off for good. It can still wait for hover, but only while a pinned
        // icon keeps the group on the bar meanwhile — otherwise the whole widget would
        // vanish and there'd be nothing left to hover.
        if (!root.hasToggleContent)
            return (hoverOnly && root.collapsedTargets.length > 0) ? hovered === true : true
        if (!root.showArrow)
            return false
        return hoverOnly ? hovered === true : true
    }

    function _toggleArrowSlotVisible() {
        return root.hasToggleContent ? root.showArrow : true
    }

    function _horizontalToggleSourceComponent() {
        // No icon/label (display "none"): render just the symbol, no body/padding.
        if (!root.hasToggleContent)
            return hToggleArrowOnlyComp
        if (!root._toggleArrowSlotVisible())
            return hToggleBodyComp
        const pos = root._resolvedExpandIndicatorPosition()
        if (pos === "left")
            return hToggleRowBeforeComp
        if (pos === "top")
            return hToggleColumnBeforeComp
        if (pos === "bottom")
            return hToggleColumnAfterComp
        return hToggleRowAfterComp
    }

    function _verticalToggleSourceComponent() {
        if (!root.hasToggleContent)
            return vToggleArrowOnlyComp
        if (!root._toggleArrowSlotVisible())
            return vToggleBodyComp
        const pos = root._resolvedExpandIndicatorPosition()
        if (pos === "left")
            return vToggleRowBeforeComp
        if (pos === "top")
            return vToggleColumnBeforeComp
        if (pos === "bottom")
            return vToggleColumnAfterComp
        return vToggleRowAfterComp
    }

    // The end caps mirror the toggle: group icon + collapse symbol, arranged by
    // the same expand/collapse-symbol position the user picks for the toggle.
    function _capSourceComponent() {
        const pos = root._resolvedExpandIndicatorPosition()
        if (pos === "left")   return capRowBeforeComp
        if (pos === "top")    return capColumnBeforeComp
        if (pos === "bottom") return capColumnAfterComp
        return capRowAfterComp   // "right"
    }

    Component {
        id: capRowAfterComp
        Row {
            spacing: Theme.spacingXS
            DankIcon { visible: root.showIcon; name: root.groupIcon; size: root.iconSize; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
            DankIcon { name: root._hChevron; rotation: 90; size: root.iconSize - 8; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Component {
        id: capRowBeforeComp
        Row {
            spacing: Theme.spacingXS
            DankIcon { name: root._hChevron; rotation: 90; size: root.iconSize - 8; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
            DankIcon { visible: root.showIcon; name: root.groupIcon; size: root.iconSize; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Component {
        id: capColumnAfterComp
        Column {
            spacing: 1
            DankIcon { visible: root.showIcon; name: root.groupIcon; size: root.iconSize; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
            DankIcon { name: root._vChevron; size: root.iconSize - 8; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
        }
    }
    Component {
        id: capColumnBeforeComp
        Column {
            spacing: 1
            DankIcon { name: root._vChevron; size: root.iconSize - 8; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
            DankIcon { visible: root.showIcon; name: root.groupIcon; size: root.iconSize; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
        }
    }

    function _clickActionFor(button) {
        if (button === Qt.LeftButton)
            return { action: root.leftClickAction,   command: root.leftClickCommand,   widget: root.leftClickWidget }
        if (button === Qt.RightButton)
            return { action: root.rightClickAction,  command: root.rightClickCommand,  widget: root.rightClickWidget }
        if (button === Qt.MiddleButton)
            return { action: root.middleClickAction, command: root.middleClickCommand, widget: root.middleClickWidget }
        return { action: "none", command: "", widget: "" }
    }

    // The expand/collapse symbol always stays an expand/collapse control, whatever
    // the group's click actions are set to — otherwise a group whose left click runs
    // a command or activates a member has no way to unfold. Every hit-target that
    // covers the symbol (the toggle's own area, and the unified one over the whole
    // collapsed cluster) routes left clicks landing on it back to toggling.
    //
    // The region is the toggle arrangement's symbol slot, which it exposes as
    // `symbolSlot`; with no icon or label the toggle is symbol-only, so the whole
    // button counts. Arrangements without a symbol expose nothing and opt out.
    function _toggleSymbolTarget(loader, toggle) {
        if (!root.hasToggleContent)
            return toggle
        return loader?.item?.symbolSlot ?? null
    }

    function _hitsExpandSymbol(slot, source, x, y) {
        if (!slot || !slot.visible || slot.width <= 0 || slot.height <= 0)
            return false
        const p = source.mapToItem(slot, x, y)
        return p.x >= 0 && p.y >= 0 && p.x < slot.width && p.y < slot.height
    }

    function _handleGroupClick(button) {
        const a = root._clickActionFor(button)
        switch (a.action) {
        case "expand":
            root.expanded = !root.expanded
            break
        case "command":
            root._runCommand(a.command)
            break
        case "widget":
            root._activateMember(a.widget)
            break
        default:
            break
        }
    }

    // Symmetric opposing-chevron icons that flip on expand/collapse only — there's
    // no left/right direction to compute, so this behaves identically in every
    // section (and sidesteps the centre-drift ambiguity entirely). The horizontal
    // toggle rotates the icon 90° so it reads as ‹ › / › ‹.
    readonly property string _hChevron: root.expanded ? "unfold_less" : "unfold_more"
    readonly property string _vChevron: root.expanded ? "unfold_less" : "unfold_more"

    Timer {
        id: collapseTimer
        interval: root.autoCollapseSeconds * 1000
        repeat: false
        // When "on leave" is set, only count down while the mouse is away from the
        // expanded group (re-entering resets it); otherwise count from expand.
        running: root.expanded && root.autoCollapse
                 && (root.autoCollapseOnLeave ? !root.hovered : true)
        onTriggered: root.expanded = false
    }

    Component {
        id: hToggleBodyComp
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                visible: root.showIcon
                name: root.groupIcon
                size: root.iconSize
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.showLabel
                text: root.groupLabel
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Component {
        id: hToggleArrowComp
        DankIcon {
            name: root._hChevron
            rotation: 90   // unfold icons are vertical; rotate so they read ‹ › / › ‹
            size: root.iconSize - 8
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Symbol-only toggle body (display "none"): just the chevron, no body or gap.
    // Hover-hiding is handled by the toggle itself, which drops out of the layout.
    Component {
        id: hToggleArrowOnlyComp
        DankIcon {
            name: root._hChevron
            rotation: 90
            size: root.iconSize - 8
            color: Theme.surfaceVariantText
        }
    }

    Component {
        id: hToggleRowBeforeComp
        Row {
            spacing: Theme.spacingXS
            readonly property int slotHeight: Math.max(root.iconSize, hBodyLoader.implicitHeight)
            // Where the expand/collapse symbol sits, for the click handlers above.
            readonly property Item symbolSlot: hSymbolSlot
            Item {
                id: hSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: root.iconSize
                height: slotHeight
                Loader {
                    id: hArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleArrowComp
                }
            }
            Item {
                width: hBodyLoader.implicitWidth
                height: slotHeight
                Loader {
                    id: hBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleBodyComp
                }
            }
        }
    }

    Component {
        id: hToggleRowAfterComp
        Row {
            spacing: Theme.spacingXS
            readonly property int slotHeight: Math.max(root.iconSize, hBodyLoader.implicitHeight)
            // Where the expand/collapse symbol sits, for the click handlers above.
            readonly property Item symbolSlot: hSymbolSlot
            Item {
                id: hSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: root.iconSize
                height: slotHeight
                Loader {
                    id: hArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleArrowComp
                }
            }
            Item {
                width: hBodyLoader.implicitWidth
                height: slotHeight
                Loader {
                    id: hBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleBodyComp
                }
            }
        }
    }

    Component {
        id: hToggleColumnBeforeComp
        Column {
            spacing: Theme.spacingXS
            readonly property int slotWidth: Math.max(root.iconSize, hBodyLoader.implicitWidth)
            readonly property Item symbolSlot: hSymbolSlot
            Item {
                id: hSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: slotWidth
                height: root.iconSize
                Loader {
                    id: hArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleArrowComp
                }
            }
            Item {
                width: slotWidth
                height: hBodyLoader.implicitHeight
                Loader {
                    id: hBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleBodyComp
                }
            }
        }
    }

    Component {
        id: hToggleColumnAfterComp
        Column {
            spacing: Theme.spacingXS
            readonly property int slotWidth: Math.max(root.iconSize, hBodyLoader.implicitWidth)
            readonly property Item symbolSlot: hSymbolSlot
            Item {
                width: slotWidth
                height: hBodyLoader.implicitHeight
                Loader {
                    id: hBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleBodyComp
                }
            }
            Item {
                id: hSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: slotWidth
                height: root.iconSize
                Loader {
                    id: hArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: hToggleArrowComp
                }
            }
        }
    }

    Component {
        id: vToggleBodyComp
        Column {
            spacing: 1
            DankIcon {
                visible: root.showIcon
                name: root.groupIcon
                size: root.iconSize
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                visible: root.showLabel
                text: root.groupLabel
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Component {
        id: vToggleArrowComp
        DankIcon {
            name: root._vChevron
            size: root.iconSize - 8
            color: Theme.surfaceVariantText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Component {
        id: vToggleArrowOnlyComp
        DankIcon {
            name: root._vChevron
            size: root.iconSize - 8
            color: Theme.surfaceVariantText
        }
    }

    Component {
        id: vToggleRowBeforeComp
        Row {
            spacing: Theme.spacingXS
            readonly property int slotHeight: Math.max(root.iconSize, vBodyLoader.implicitHeight)
            readonly property Item symbolSlot: vSymbolSlot
            Item {
                id: vSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: root.iconSize
                height: slotHeight
                Loader {
                    id: vArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleArrowComp
                }
            }
            Item {
                width: vBodyLoader.implicitWidth
                height: slotHeight
                Loader {
                    id: vBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleBodyComp
                }
            }
        }
    }

    Component {
        id: vToggleRowAfterComp
        Row {
            spacing: Theme.spacingXS
            readonly property int slotHeight: Math.max(root.iconSize, vBodyLoader.implicitHeight)
            readonly property Item symbolSlot: vSymbolSlot
            Item {
                id: vSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: root.iconSize
                height: slotHeight
                Loader {
                    id: vArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleArrowComp
                }
            }
            Item {
                width: vBodyLoader.implicitWidth
                height: slotHeight
                Loader {
                    id: vBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleBodyComp
                }
            }
        }
    }

    Component {
        id: vToggleColumnBeforeComp
        Column {
            spacing: Theme.spacingXS
            readonly property int slotWidth: Math.max(root.iconSize, vBodyLoader.implicitWidth)
            readonly property Item symbolSlot: vSymbolSlot
            Item {
                id: vSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: slotWidth
                height: root.iconSize
                Loader {
                    id: vArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleArrowComp
                }
            }
            Item {
                width: slotWidth
                height: vBodyLoader.implicitHeight
                Loader {
                    id: vBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleBodyComp
                }
            }
        }
    }

    Component {
        id: vToggleColumnAfterComp
        Column {
            spacing: Theme.spacingXS
            readonly property int slotWidth: Math.max(root.iconSize, vBodyLoader.implicitWidth)
            readonly property Item symbolSlot: vSymbolSlot
            Item {
                width: slotWidth
                height: vBodyLoader.implicitHeight
                Loader {
                    id: vBodyLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleBodyComp
                }
            }
            Item {
                id: vSymbolSlot
                visible: root._shouldShowArrow(root.hovered)
                width: slotWidth
                height: root.iconSize
                Loader {
                    id: vArrowLoader
                    anchors.centerIn: parent
                    sourceComponent: vToggleArrowComp
                }
            }
        }
    }

    // ── Horizontal bar pill ──────────────────────────────────────────────────
    horizontalBarPill: Component {
        Item {
            // In overlay mode keep the bar footprint at the collapsed size (toggle
            // plus any pinned members) so expanding doesn't push neighbours; the
            // expand-only members overflow and paint over.
            implicitWidth: root.overlayExpand ? root._pinnedFootprint(false, hToggle.visible ? hToggle.width : 0, hRow.spacing) : hRow.width
            implicitHeight: hRow.height

            // Solid backing shown while expanded so the group stays readable when
            // its members overlap an adjacent bar section (the bar itself may be
            // transparent, making overlapping icons blend together otherwise).
            Rectangle {
                anchors.fill: hRow
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0
                border.width: root.showExpandedBorder ? 1 : 0
                border.color: Theme.outlineVariant
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
            }

            // Unified-click hover highlight: while collapsed and unified, the whole
            // cluster (toggle + pinned icons) highlights as one button on hover.
            Rectangle {
                anchors.fill: hRow
                radius: Theme.cornerRadius
                color: Theme.primaryHover
                visible: root.unifiedClick && !root.expanded && hUnifiedArea.containsMouse
            }

            Row {
                id: hRow
                spacing: Theme.spacingXS
                layoutDirection: root.hLeft ? Qt.RightToLeft : Qt.LeftToRight
                // Pin the toggle end to the collapsed footprint so it stays put while
                // members overflow. Expand-left pins right, expand-right pins left.
                anchors.left: (root.overlayExpand && root.hLeft) ? undefined : parent.left
                anchors.right: (root.overlayExpand && root.hLeft) ? parent.right : undefined
                anchors.verticalCenter: parent.verticalCenter

                HoverHandler { onHoveredChanged: { root.hovered = hovered; if (hovered) root._recomputeHDir(hToggle) } }

            // Recompute the unfold direction once the bar has settled.
            Timer { interval: 150; running: true; repeat: false; onTriggered: root._recomputeHDir(hToggle) }

            // Toggle button
            Rectangle {
                id: hToggle
                // Symbol-only button: when the symbol hides on hover there's nothing
                // left in it, so drop the whole button from the row rather than leave
                // an empty pill. Hovering the pinned icons brings it back.
                visible: root.hasToggleContent || root._shouldShowArrow(root.hovered)
                width: hToggleLoader.implicitWidth + (root.hasToggleContent ? Theme.spacingS * 2 : Theme.spacingXS * 2)
                height: hToggleLoader.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius
                color: hToggleArea.containsMouse ? Theme.primaryHover : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                Loader {
                    id: hToggleLoader
                    anchors.centerIn: parent
                    sourceComponent: root._horizontalToggleSourceComponent()
                }

                MouseArea {
                    id: hToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        // Left-clicking the expand/collapse symbol always folds/unfolds,
                        // even when left click is bound to a command or a member.
                        if (mouse.button === Qt.LeftButton
                            && root._hitsExpandSymbol(root._toggleSymbolTarget(hToggleLoader, hToggle),
                                                      hToggleArea, mouse.x, mouse.y)) {
                            root.expanded = !root.expanded
                            return
                        }
                        root._handleGroupClick(mouse.button)
                    }
                }
            }

            Repeater {
                model: root.targets

                delegate: Item {
                    id: hWrap
                    required property var modelData
                    readonly property bool shown: root._isMemberShown(hWrap.modelData)
                    visible: shown
                    height: shown ? hMember.implicitHeight : 0
                    width: shown ? hMember.implicitWidth : 0
                    clip: true
                    opacity: shown ? 1 : 0
                    anchors.verticalCenter: parent.verticalCenter

                    Behavior on width   { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    GroupMember {
                        id: hMember
                        anchors.verticalCenter: parent.verticalCenter
                        targetId: hWrap.modelData
                        pluginService: root.pluginService
                        popoutService: root.popoutService
                        axis: root.axis
                        section: root.section
                        parentScreen: root.parentScreen
                        widgetThickness: root.widgetThickness
                        barThickness: root.barThickness
                        barSpacing: root.barSpacing
                        barConfig: root.barConfig
                        blurBarWindow: root.blurBarWindow
                        onReadyChanged: {
                            if (ready)
                                root._registerMember(hWrap.modelData, hMember)
                        }
                        onImplicitWidthChanged: root._bumpPinRev()
                    }

                    Component.onCompleted: root._registerMember(hWrap.modelData, hMember)
                    Component.onDestruction: root._unregisterMember(hWrap.modelData, hMember)
                }
            }

            // Group end cap — a matching button at the far end (group icon + the
            // collapse chevron), so there's a collapse control with a clear hover
            // target at both ends of the expanded panel.
            Rectangle {
                id: hCap
                visible: root.targets.length > 0
                width: root.expanded ? hCapLoader.implicitWidth + Theme.spacingS * 2 : 0
                height: hCapLoader.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius
                color: hCapArea.containsMouse ? Theme.primaryHover : "transparent"
                opacity: root.expanded ? 1 : 0
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width   { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on color   { ColorAnimation { duration: Theme.shortDuration } }

                Loader {
                    id: hCapLoader
                    anchors.centerIn: parent
                    sourceComponent: root._capSourceComponent()
                }

                MouseArea {
                    id: hCapArea
                    anchors.fill: parent
                    enabled: root.expanded
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.expanded = false
                }
            }
        }

            // Unified click: one hit-target over the collapsed cluster (toggle +
            // pinned members). On top of their own mouse areas so pinned members act
            // as passive icons; disabled while expanded so members stay interactive.
            MouseArea {
                id: hUnifiedArea
                anchors.fill: hRow
                z: 10
                visible: root.unifiedClick && !root.expanded
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: function(mouse) {
                    // The symbol is carved out of the unified button: clicking it
                    // expands/collapses instead of firing the group's action.
                    if (mouse.button === Qt.LeftButton
                        && root._hitsExpandSymbol(root._toggleSymbolTarget(hToggleLoader, hToggle),
                                                  hUnifiedArea, mouse.x, mouse.y)) {
                        root.expanded = !root.expanded
                        return
                    }
                    root._handleGroupClick(mouse.button)
                }
                onContainsMouseChanged: { root.hovered = containsMouse; if (containsMouse) root._recomputeHDir(hToggle) }
            }
        }
    }

    // ── Vertical bar pill ────────────────────────────────────────────────────
    // Members render above the toggle when "up", below it when "down".
    Component {
        id: vMembersComp
        Column {
            spacing: Theme.spacingXS

            // End cap at the top — far end when expanding upward
            Rectangle {
                id: vCapTop
                visible: root.targets.length > 0 && root.vUp
                anchors.horizontalCenter: parent.horizontalCenter
                width: vCapTopLoader.implicitWidth + Theme.spacingXS * 2
                height: root.expanded ? vCapTopLoader.implicitHeight + Theme.spacingXS * 2 : 0
                radius: Theme.cornerRadius
                color: vCapTopArea.containsMouse ? Theme.primaryHover : "transparent"
                opacity: root.expanded ? 1 : 0
                clip: true
                Behavior on height  { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on color   { ColorAnimation { duration: Theme.shortDuration } }

                Loader {
                    id: vCapTopLoader
                    anchors.centerIn: parent
                    sourceComponent: root._capSourceComponent()
                }

                MouseArea {
                    id: vCapTopArea
                    anchors.fill: parent
                    enabled: root.expanded
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.expanded = false
                }
            }

            Repeater {
                model: root.targets
                delegate: Item {
                    id: vWrap
                    required property var modelData
                    readonly property bool shown: root._isMemberShown(vWrap.modelData)
                    visible: shown
                    width: shown ? vMember.implicitWidth : 0
                    height: shown ? vMember.implicitHeight : 0
                    clip: true
                    opacity: shown ? 1 : 0
                    anchors.horizontalCenter: parent.horizontalCenter

                    Behavior on height  { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    GroupMember {
                        id: vMember
                        anchors.horizontalCenter: parent.horizontalCenter
                        targetId: vWrap.modelData
                        pluginService: root.pluginService
                        popoutService: root.popoutService
                        axis: root.axis
                        section: root.section
                        parentScreen: root.parentScreen
                        widgetThickness: root.widgetThickness
                        barThickness: root.barThickness
                        barSpacing: root.barSpacing
                        barConfig: root.barConfig
                        blurBarWindow: root.blurBarWindow
                        onReadyChanged: {
                            if (ready)
                                root._registerMember(vWrap.modelData, vMember)
                        }
                        onImplicitHeightChanged: root._bumpPinRev()
                    }

                    Component.onCompleted: root._registerMember(vWrap.modelData, vMember)
                    Component.onDestruction: root._unregisterMember(vWrap.modelData, vMember)
                }
            }

            // End cap at the bottom — far end when expanding downward
            Rectangle {
                id: vCapBot
                visible: root.targets.length > 0 && !root.vUp
                anchors.horizontalCenter: parent.horizontalCenter
                width: vCapBotLoader.implicitWidth + Theme.spacingXS * 2
                height: root.expanded ? vCapBotLoader.implicitHeight + Theme.spacingXS * 2 : 0
                radius: Theme.cornerRadius
                color: vCapBotArea.containsMouse ? Theme.primaryHover : "transparent"
                opacity: root.expanded ? 1 : 0
                clip: true
                Behavior on height  { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on color   { ColorAnimation { duration: Theme.shortDuration } }

                Loader {
                    id: vCapBotLoader
                    anchors.centerIn: parent
                    sourceComponent: root._capSourceComponent()
                }

                MouseArea {
                    id: vCapBotArea
                    anchors.fill: parent
                    enabled: root.expanded
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.expanded = false
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vCol.width
            // In overlay mode keep the bar footprint at the collapsed size (toggle
            // plus any pinned members) so expanding doesn't push neighbours; the
            // expand-only members overflow and paint over.
            implicitHeight: root.overlayExpand ? root._pinnedFootprint(true, vToggle.visible ? vToggle.height : 0, vCol.spacing) : vCol.height

            // Solid backing shown while expanded so the group stays readable when
            // its members overlap an adjacent bar section.
            Rectangle {
                anchors.fill: vCol
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0
                border.width: root.showExpandedBorder ? 1 : 0
                border.color: Theme.outlineVariant
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
            }

            // Unified-click hover highlight (see the horizontal pill for details).
            Rectangle {
                anchors.fill: vCol
                radius: Theme.cornerRadius
                color: Theme.primaryHover
                visible: root.unifiedClick && !root.expanded && vUnifiedArea.containsMouse
            }

            Column {
                id: vCol
                spacing: Theme.spacingXS
                // Pin the toggle end to the collapsed footprint so it stays put while
                // members overflow. Expand-up pins bottom, expand-down pins top.
                anchors.top: (root.overlayExpand && root.vUp) ? undefined : parent.top
                anchors.bottom: (root.overlayExpand && root.vUp) ? parent.bottom : undefined
                anchors.horizontalCenter: parent.horizontalCenter

                HoverHandler { onHoveredChanged: { root.hovered = hovered; if (hovered) root._recomputeVDir(vToggle) } }

                // Recompute the unfold direction once the bar has settled.
                Timer { interval: 150; running: true; repeat: false; onTriggered: root._recomputeVDir(vToggle) }

            // Members above the toggle (when expanding up)
            Loader {
                active: root.vUp
                sourceComponent: vMembersComp
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Rectangle {
                id: vToggle
                // See the horizontal toggle: a symbol-only button leaves the column
                // when its symbol is hover-hidden.
                visible: root.hasToggleContent || root._shouldShowArrow(root.hovered)
                width: vToggleLoader.implicitWidth + Theme.spacingXS * 2
                height: vToggleLoader.implicitHeight + (root.hasToggleContent ? Theme.spacingS * 2 : Theme.spacingXS * 2)
                radius: Theme.cornerRadius
                color: vToggleArea.containsMouse ? Theme.primaryHover : "transparent"
                anchors.horizontalCenter: parent.horizontalCenter
                Loader {
                    id: vToggleLoader
                    anchors.centerIn: parent
                    sourceComponent: root._verticalToggleSourceComponent()
                }

                MouseArea {
                    id: vToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        // See the horizontal toggle: the symbol always expands/collapses.
                        if (mouse.button === Qt.LeftButton
                            && root._hitsExpandSymbol(root._toggleSymbolTarget(vToggleLoader, vToggle),
                                                      vToggleArea, mouse.x, mouse.y)) {
                            root.expanded = !root.expanded
                            return
                        }
                        root._handleGroupClick(mouse.button)
                    }
                }
            }

            // Members below the toggle (when expanding down)
            Loader {
                active: !root.vUp
                sourceComponent: vMembersComp
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

            // Unified click hit-target over the collapsed cluster (toggle + pinned).
            MouseArea {
                id: vUnifiedArea
                anchors.fill: vCol
                z: 10
                visible: root.unifiedClick && !root.expanded
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: function(mouse) {
                    // See the horizontal pill: the symbol is carved out of the button.
                    if (mouse.button === Qt.LeftButton
                        && root._hitsExpandSymbol(root._toggleSymbolTarget(vToggleLoader, vToggle),
                                                  vUnifiedArea, mouse.x, mouse.y)) {
                        root.expanded = !root.expanded
                        return
                    }
                    root._handleGroupClick(mouse.button)
                }
                onContainsMouseChanged: { root.hovered = containsMouse; if (containsMouse) root._recomputeVDir(vToggle) }
            }
        }
    }
}
