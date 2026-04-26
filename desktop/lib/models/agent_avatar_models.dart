/// Mirrors [ai.axiomaster.bonio.ai.AgentState] for server-driven `setState`.
enum AgentAvatarActivity {
  idle,
  bored,
  sleeping,
  listening,
  thinking,
  speaking,
  working,
  happy,
  confused,
  angry,
  watching,
}

AgentAvatarActivity? parseAgentAvatarActivity(String name) {
  switch (name.toLowerCase()) {
    case 'idle':
      return AgentAvatarActivity.idle;
    case 'listening':
      return AgentAvatarActivity.listening;
    case 'thinking':
      return AgentAvatarActivity.thinking;
    case 'speaking':
      return AgentAvatarActivity.speaking;
    case 'working':
      return AgentAvatarActivity.working;
    case 'watching':
      return AgentAvatarActivity.watching;
    case 'sleeping':
      return AgentAvatarActivity.sleeping;
    case 'bored':
      return AgentAvatarActivity.bored;
    case 'happy':
      return AgentAvatarActivity.happy;
    case 'confused':
      return AgentAvatarActivity.confused;
    case 'angry':
      return AgentAvatarActivity.angry;
    default:
      return null;
  }
}

/// Mirrors [ai.axiomaster.bonio.avatar.AvatarAction] for `performAction`.
enum DesktopAvatarGesture {
  none,
  tapping,
  swiping,
  longPressing,
  doubleTapping,
  typing,
  waiting,
  finishing,
  launching,
  goBack,
  takingPhoto,
}

DesktopAvatarGesture parseDesktopAvatarGesture(String actionType) {
  final normalized = actionType.toLowerCase().replaceAll(' ', '');
  switch (normalized) {
    case 'tap':
    case 'click':
      return DesktopAvatarGesture.tapping;
    case 'swipe':
    case 'scroll':
      return DesktopAvatarGesture.swiping;
    case 'longpress':
      return DesktopAvatarGesture.longPressing;
    case 'doubletap':
      return DesktopAvatarGesture.doubleTapping;
    case 'type':
    case 'input':
    case 'type_name':
      return DesktopAvatarGesture.typing;
    case 'wait':
    case 'sleep':
      return DesktopAvatarGesture.waiting;
    case 'finish':
      return DesktopAvatarGesture.finishing;
    case 'launch':
    case 'open':
    case 'start_app':
      return DesktopAvatarGesture.launching;
    case 'back':
    case 'go_back':
    case 'press_back':
      return DesktopAvatarGesture.goBack;
    case 'take_photo':
    case 'screenshot':
    case 'photo':
      return DesktopAvatarGesture.takingPhoto;
    default:
      return DesktopAvatarGesture.none;
  }
}

String activityLabel(AgentAvatarActivity a) {
  switch (a) {
    case AgentAvatarActivity.idle:
      return 'Idle';
    case AgentAvatarActivity.listening:
      return 'Listening';
    case AgentAvatarActivity.thinking:
      return 'Thinking';
    case AgentAvatarActivity.speaking:
      return 'Speaking';
    case AgentAvatarActivity.working:
      return 'Working';
    case AgentAvatarActivity.watching:
      return 'Watching';
    case AgentAvatarActivity.sleeping:
      return 'Sleeping';
    case AgentAvatarActivity.bored:
      return 'Bored';
    case AgentAvatarActivity.happy:
      return 'Happy';
    case AgentAvatarActivity.confused:
      return 'Confused';
    case AgentAvatarActivity.angry:
      return 'Angry';
  }
}

String gestureLabel(DesktopAvatarGesture g) {
  switch (g) {
    case DesktopAvatarGesture.none:
      return '';
    case DesktopAvatarGesture.tapping:
      return 'Tap';
    case DesktopAvatarGesture.swiping:
      return 'Swipe';
    case DesktopAvatarGesture.longPressing:
      return 'Long press';
    case DesktopAvatarGesture.doubleTapping:
      return 'Double tap';
    case DesktopAvatarGesture.typing:
      return 'Typing';
    case DesktopAvatarGesture.waiting:
      return 'Wait';
    case DesktopAvatarGesture.finishing:
      return 'Finish';
    case DesktopAvatarGesture.launching:
      return 'Launch';
    case DesktopAvatarGesture.goBack:
      return 'Back';
    case DesktopAvatarGesture.takingPhoto:
      return 'Photo';
  }
}
