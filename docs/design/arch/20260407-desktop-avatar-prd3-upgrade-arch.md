# PRD 3.0 Desktop Avatar Upgrade Plan

## Current State vs PRD 3.0: Core Differences

### Placement Model (biggest architectural change)

- **Current**: Avatar starts on taskbar (ON_DOCK), only perches on a window after user focuses it for 1 minute. Taskbar is the "home" state.
- **PRD 3.0**: Avatar immediately anchors to the active window's top edge center. When no application window exists (all minimized/closed, user on desktop), avatar falls back to taskbar/Dock — treating the desktop itself as the "companion target". Taskbar behavior is identical to window anchoring (wandering, etc.).

**Impact**: The `_PlacementState` enum and entire polling logic in `desktop/lib/avatar_window_app.dart` need restructuring. `ON_DOCK` remains but only as a fallback for the "desktop as companion" case, not the default startup state.

### Interaction Model (5 new interactions)

| Action | Current | PRD 3.0 |
|--------|---------|---------|
| Click | No response | Random animation + emotion bubble |
| Double-click | N/A | Show text input field below avatar |
| Long-press | Voice input (PTT) | Voice input (PTT) -- already done |
| Right-click | N/A | Context menu (AI Lens, etc.) |
| Drag | Enters USER_DRAG, returns to taskbar after 5min | Stays at user offset until window resizes/moves |
| Hover | N/A | Deferred (eye tracking not in this iteration) |

### Fullscreen Behavior

- **Current**: Avatar returns to taskbar when fullscreen detected.
- **PRD 3.0**: Avatar moves to screen top-right (simulating title-bar right side position).

### Window Following Physics

- **Current**: Rigid 50ms polling — avatar snaps to position.
- **PRD 3.0**: 200ms elastic/spring follow for physical feel.

---

## Architecture Changes

### New Placement State Machine

```
                          startup, fg window exists
                    ┌──────────────────────────────────┐
                    ▼                                   │
              ┌────────────────┐                        │
 startup,     │                │  active window         │
 no fg window │ ANCHORED_WINDOW│──changes──────────────►│ (self-loop)
    │         │ (window top)   │                        │
    │         └───┬────┬───┬───┘                        │
    │             │    │   │                             │
    │     fullscreen   │   │ all windows                │
    │     detected     │   │ closed/minimized           │
    │         │     drag   │                            │
    │         ▼        │   ▼                            │
    │  ┌──────────────┐│ ┌────────┐                    │
    │  │ FULLSCREEN   ││ │ON_DOCK │   window gains     │
    │  │ _CORNER      ││ │(taskbar│───focus───────────►│
    │  │ (top-right)  ││ │ /Dock) │                    │
    │  └──────┬───────┘│ └────────┘                    │
    │         │        │       ▲                        │
    │    exit fullscreen  │    │ startup, no fg window  │
    │    or fg changes    │    │                        │
    │         │           ▼    │                        │
    │         │    ┌───────────┴─┐                      │
    │         │    │ USER_OFFSET │  window resizes      │
    │         └───►│ (dragged)   │──or moves──────────►│
    │              └─────────────┘                      │
    └──────────────────────────────────────────────────►│
```

States:
- **ANCHORED_WINDOW**: Default. Avatar on top edge of active window (center or user-offset). Wanders along window top edge.
- **FULLSCREEN_CORNER**: Active window is fullscreen; avatar at screen top-right.
- **USER_OFFSET**: User dragged avatar; position maintained relative to window until window geometry changes, then resets to center.
- **ON_DOCK**: No application window to anchor — desktop is the companion target. Avatar sits on taskbar/Dock, wanders along it. Behaves identically to ANCHORED_WINDOW but on the taskbar surface. Reuses existing dock detection code (`SHAppBarMessage`, `getDockInfo`).

### State Variables (replacing current)

```
placementState      : ANCHORED_WINDOW | FULLSCREEN_CORNER | USER_OFFSET | ON_DOCK
anchoredHwnd        : HWND of the window avatar is anchored to (0 when ON_DOCK)
anchorOffsetX       : X offset relative to window center (0 = centered, modified by drag)
userDragActive      : true while user is dragging (suppress anchor updates)
```

### New Inter-Engine Methods

Avatar engine -> Main engine:
- `avatarVoiceStart` / `avatarVoiceStop` (existing)
- `avatarClick` (new: single click)
- `avatarDoubleClick` (new: double click, show/hide input)
- `avatarRightClick` (new: show context menu)
- `avatarTextSubmit` (new: text from input field)

Main engine -> Avatar engine:
- `sync` (existing: AvatarSnapshot)
- `showInput` / `hideInput` (new: toggle input field visibility)
- `window_close` (existing)

---

## Implementation Tasks

### Phase 1: Placement Model Refactor

**File**: `desktop/lib/avatar_window_app.dart`

1. Replace `_PlacementState` enum: `onDock | perchedWindow | userDrag` -> `anchoredWindow | fullscreenCorner | userOffset | onDock`
2. On startup: immediately detect foreground window and anchor (no 1-minute delay). If no window -> ON_DOCK
3. On active window change: immediately switch to new window (no delay)
4. Fullscreen detection: instead of returning to dock, position at `(screenWidth - windowWidth - 20, 20)` (top-right)
5. Keep dock/taskbar code (`_dockLeft`, `_dockRight`, `_dockHeight`, `_moveToDockPosition`, `_initTaskbarWindows`, `_initDockMacOS`) for ON_DOCK fallback — desktop is treated as a companion target
6. Remove 1-minute focus candidate delay (`_focusCandidateHwnd`, `_focusCandidateSince`, `_perchAfter`); window switch is immediate
7. User drag: record offset from window top-center; maintain until window geometry changes, then reset to center
8. Keep wandering: on window top edge (ANCHORED_WINDOW) or along taskbar (ON_DOCK)
9. Keep 50ms fast tracking timer but add elastic spring interpolation
10. ON_DOCK -> ANCHORED_WINDOW transition: when any non-self, non-fullscreen window gains focus, immediately anchor to it

**Elastic follow implementation** in `_trackPerchedWindow`:
```dart
// Instead of directly setting position:
_targetX = clampedX;  _targetY = targetY;
// In a 16ms render timer, lerp toward target:
_currentX += (_targetX - _currentX) * 0.15; // ~200ms spring
_currentY += (_targetY - _currentY) * 0.15;
wc.setPosition(Offset(_currentX, _currentY));
```

### Phase 2: Mouse Interaction Overhaul

**File**: `desktop/lib/ui/widgets/desktop_avatar_overlay.dart`

Current `Listener` on `avatarStack` handles pointer down/up/move for long-press (voice) vs drag. Need to add:

1. **Single click detection**: pointer down + pointer up within 300ms with minimal movement, no double-click follow-up within 300ms
2. **Double-click detection**: two clicks within 400ms
3. **Right-click**: detect `PointerDownEvent` with `buttons == kSecondaryButton`
4. **Timing**: down -> 300ms no movement = voice start. down + up < 300ms = potential click. second click within 400ms = double-click. Otherwise single click.

State machine for pointer:
```
PointerDown (left button)
  ├─ move > 2px before 300ms → DRAG (startDragging)
  ├─ 300ms timer fires (no move) → VOICE (onVoiceStart)
  └─ PointerUp < 300ms → CLICK_PENDING
       ├─ second PointerDown within 400ms → DOUBLE_CLICK
       └─ 400ms timeout → SINGLE_CLICK

PointerDown (right button)
  └─ immediately → RIGHT_CLICK (onAvatarRightClick)
```

Add callbacks to `DesktopAvatarView`: `onAvatarClick`, `onAvatarDoubleClick`, `onAvatarRightClick`

### Phase 3: Single Click — Random Animation + Emotion Bubble

**Files**: `desktop/lib/providers/app_state.dart`, `desktop/lib/services/avatar_controller.dart`

1. `_handleAvatarClick()`: pick random animation from a preset list (happy, bored, watching, confused) + random emotion text from a list, show via `setBubble` for 3 seconds, then auto-clear
2. Animation assets already exist (`cat-happy`, `cat-bored`, `cat-watching`, etc.)

### Phase 4: Double Click — Text Input Field

**Files**: `desktop/lib/ui/widgets/desktop_avatar_overlay.dart`, `desktop/lib/models/avatar_snapshot.dart`, `desktop/lib/avatar_window_app.dart`

1. Add `showInput` boolean to `AvatarSnapshot`
2. In `DesktopAvatarView`, when `showInput == true`, render a `TextField` below the avatar cat (inside the existing `Column`)
3. Avatar window needs to grow taller to accommodate input: dynamically resize window when input is shown
4. On Enter key: send text via `avatarTextSubmit` to main engine, hide input
5. On Escape: hide input without sending
6. Main engine handler: `_handleAvatarTextSubmit(text)` -> `chatController.sendMessage(text)`

**Window resize consideration**: Current window is 244x156. When input visible, expand to ~244x200. Use `windowManager.setSize()` and adjust position upward so the cat doesn't jump.

### Phase 5: Right-Click Context Menu

**Files**: `desktop/lib/ui/widgets/desktop_avatar_overlay.dart`, `desktop/lib/avatar_window_app.dart`

1. On right-click: show menu directly in the avatar engine (self-contained, avoids cross-engine complexity)
2. Temporarily expand avatar window to accommodate the menu overlay, then shrink back
3. Menu items for this iteration:
   - **AI 圈选 (BoJi Lens)** — triggers screen capture flow
   - --- (separator)
   - **BoJi 桌面** — show main window
   - **更换伴随窗口** — placeholder/future
   - --- (separator)
   - **休息一下** — hide avatar, keep tray icon

### Phase 6: AI Lens (Screen Capture + Selection)

**New file**: `desktop/lib/platform/win32_screen_capture.dart`

1. **Capture**: Use Win32 `BitBlt` via dart:ffi to capture the entire screen to a bitmap
2. **Selection overlay**: Create a new fullscreen transparent Flutter window (via `desktop_multi_window`) with a 40% black overlay
3. User drags to select a rectangle region
4. Crop the captured bitmap to the selection rectangle
5. Encode as PNG, send to server via chat message (as image content)
6. Close the overlay window

Win32 APIs needed:
```
GetDC(NULL)            → screen DC
CreateCompatibleDC     → memory DC
CreateCompatibleBitmap → bitmap
BitBlt                 → copy screen to bitmap
GetDIBits              → extract raw pixel data
```

### Phase 7: Fullscreen Title-Bar Position

**File**: `desktop/lib/avatar_window_app.dart`

1. When fullscreen detected: move avatar to `(screenWidth - windowWidth - 20, 8)` (top-right corner, slight padding)
2. No wandering in fullscreen mode
3. When window exits fullscreen or active window changes to non-fullscreen: return to window top edge

---

## Files Changed Summary

| File | Change Type |
|------|-------------|
| `desktop/lib/avatar_window_app.dart` | Major refactor: placement states, elastic follow, fullscreen corner |
| `desktop/lib/ui/widgets/desktop_avatar_overlay.dart` | Major: click/dblclick/rightclick detection, text input field, menu |
| `desktop/lib/providers/app_state.dart` | Moderate: new handlers for click, dblclick, text submit, right-click |
| `desktop/lib/models/avatar_snapshot.dart` | Minor: add `showInput` field, resize window size constant |
| `desktop/lib/services/avatar_controller.dart` | Minor: random animation helper |
| `desktop/lib/platform/win32_screen_capture.dart` | **New**: Win32 FFI screen capture |
| `design/desktop_avatar_design.md` | Update to reflect PRD 3.0 architecture |

## Implementation Order

Phases 1–2 are foundational and must come first. Phases 3–7 are independent features that can be done in any order after Phase 2.

Recommended sequence: **1 → 2 → 3 → 4 → 7 → 5 → 6** (AI Lens last as it's most complex).

## Deferred Items (not in this iteration)

- **Hover eye tracking**: requires new Lottie assets with controllable eye direction or shader-based pupil offset
- **Snap-back magnetic effect**: user drags avatar near window top edge → auto-reattach with sound effect
- **Multi-monitor awareness**: avatar stays on same monitor as active window
- **"更换伴随窗口" menu**: window picker UI for manually selecting a non-active window to companion
