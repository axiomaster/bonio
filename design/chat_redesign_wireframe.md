# Chat UI Redesign Wireframe

This document outlines the proposed layout changes for the BoJi Chat interface, focusing on a cleaner and more intuitive design.

## 1. Top Navigation
- **Location**: Top of the screen (replaces bottom navigation).
- **Components**: Standard Android TabRow or NavigationBar moved to the top slot of the `Scaffold`.
- **Items**: Chat, Voice, Screen, Settings.

## 2. Message List
- **Location**: Fills the center of the screen, scrollable.

## 3. Control Row (Above Input)
- **Buttons (Left)**:
    - `Continue` (Icon: Refresh): Triggers `onRefresh`.
    - `Stop` (Icon: Stop): Triggers `onAbort`, only enabled when `pendingRunCount > 0`.
- **Selector (Right)**:
    - `Thinking: [Level]` (Icon: Auto-fix/Sparkle): Replaces the current `Attach` button location. Opens the thinking level dropdown.

## 4. Bottom Input Area
- **Structure**:
    - A single, auto-expanding `TextField` in a capsule shape.
    - **Placeholder**: "Ask anything..."
- **Input Logic**:
    - **Empty State**: Shows a `+` icon on the right.
- **Typing State**: If text is present, the `+` button is replaced by a `Send` (upward arrow) icon. **Only one button is visible at a time.**

## 5. Attachment Menu (Revealed via `+`)
- **Behavior**: When the `+` button is clicked, a menu drawer opens **directly below** the input box, pushing the input box upward.
- **Components**: Three circular buttons with vertical icons and labels:
    1. **Camera**: Triggers camera capture.
    2. **Gallery**: Triggers image picker.
    3. **File**: Triggers generic file picker (File Picker).
- **Layout**: These 3 buttons are horizontally centered and evenly spaced, taking up the full width.
- **Dismissal**: Clicking anywhere outside the menu (e.g., on the message list) or clicking the `+` button again (which might turn into an `x` or just toggle) collapses the menu.

## 6. Eliminated Components
- Removed the large "Send" button at the very bottom.
- Removed the "Attach" button from the top row of the composer.

---

![Chat UI Redesign Wireframe](file:///C:/Users/lism/.gemini/antigravity/brain/4fbd60b7-1356-40bd-bc12-024afa06f12a/chat_ui_redesign_wireframe_1773504006637.png)
