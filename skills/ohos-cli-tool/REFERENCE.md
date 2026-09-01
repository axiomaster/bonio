## hms-geofence
Geofence management tool for subscribing and unsubscribing geofence status. Used for location-based geofence event subscription scenarios. Does not support real-time location tracking or continuous monitoring.
Permissions: ohos.permission.APPROXIMATELY_LOCATION
### subscribe
Subscribe to geofence status events. Used for registering geofence monitoring with specific location and scenario parameters. Does not support batch subscription or modification of existing subscriptions.
- --sessionId <string> REQUIRED — Session identifier for the subscription
- --ruleId <string> REQUIRED — Rule identifier for the subscription
- --bundleName <string> REQUIRED — Bundle name of the application
- --type <integer> REQUIRED — Location type (0: HOME, 1: COMPANY, 2: OTHERS)
- --latitude <number> REQUIRED — Latitude coordinate (-90 to 90)
- --longitude <number> REQUIRED — Longitude coordinate (-180 to 180)
- --status <integer> REQUIRED — Subscription status (0: ENTER, 1: EXIT, 2: ENTER_EXIT)
- --code <integer> REQUIRED — Event reporter code
- --interfaceToken <string> REQUIRED — Interface token for event reporter
- --abilityName <string> REQUIRED — Ability name for event reporter
### unsubscribe
Unsubscribe from geofence status events. Used for removing geofence monitoring registration. Does not support partial unsubscription or unsubscription of non-existent sessions.
- --sessionId <string> REQUIRED — Session identifier to unsubscribe
- --ruleId <string> REQUIRED — Rule identifier to unsubscribe
- --bundleName <string> REQUIRED — Bundle name of the application

## hms-movementAwareness
CLI tool for subscribing and unsubscribing device movement state
### subscribe
订阅运动状态变化事件。用于应用需要监测用户运动状态并做出响应的场景。不适用于不需要运动状态监测的应用。属于异步接口
- --type <integer> REQUIRED — 运动类型：0(步行WALKING)、1(跑步RUNNING)、2(骑行BICYCLE)、3(乘车IN_VEHICLE)
- --event <integer> default:3 — 运动事件：1(进入ENTER)、2(退出EXIT)、3(进入和退出ENTER_EXIT)，默认值为3
- --interval <integer> default:2000000000 — 监测间隔时间（纳秒），默认值为2000000000（2秒）
- --sessionId <string> REQUIRED — 会话ID，用于标识本次订阅
- --ruleId <string> REQUIRED — 规则ID，用于标识运动监测规则
- --bundleName <string> REQUIRED — 应用包名
- --abilityName <string> REQUIRED — Ability名称
- --code <integer> REQUIRED — 事件上报码
- --interfaceToken <string> REQUIRED — 接口Token，用于IPC通信验证
### unsubscribe
取消订阅运动状态变化事件。用于应用不再需要监测用户运动状态的场景。不适用于未订阅过运动状态的应用。为同步命令
- --sessionId <string> REQUIRED — 会话ID，用于标识需要取消的订阅
- --ruleId <string> REQUIRED — 规则ID，用于标识需要取消的运动监测规则
- --bundleName <string> REQUIRED — 应用包名

## ohos-a11yManager
OHOS Accessibility Manager - Command line tool for managing system accessibility features. Used for developer testing and system administrator configuration of accessibility settings. Not suitable for daily operations of ordinary users.
Permissions: ohos.permission.cli.WRITE_ACCESSIBILITY_CONFIG_VISION, ohos.permission.cli.WRITE_ACCESSIBILITY_CONFIG_HEARING, ohos.permission.cli.WRITE_ACCESSIBILITY_CONFIG_ACTION, ohos.permission.cli.READ_ACCESSIBILITY_CONFIG_VISION, ohos.permission.cli.READ_ACCESSIBILITY_CONFIG_HEARING, ohos.permission.cli.READ_ACCESSIBILITY_CONFIG_ACTION
### state-is-screen-reader-enabled
Check if screen reader is enabled. Used to get the current enabled status of screen reader. Not applicable for modifying screen reader status.
### ability-enable-screen-reader
Enable screen reader function. Used to turn on screen reading service for visually impaired users. Not applicable when screen reader is already enabled.
### ability-disable-screen-reader
Disable screen reader function. Used to turn off screen reading service. Not applicable when screen reader is already disabled.
### magnification-set-state
Set screen magnification state. Used to enable or disable screen magnification to assist users with poor vision. Not applicable for adjusting magnification level.
- --state <string> REQUIRED enum:[true|false] — Screen magnification state
### magnification-get-state
Get screen magnification state. Used to query whether screen magnification is currently enabled. Not applicable for modifying screen magnification status.
### shortkey-set-state
Set shortcut key state. Used to enable or disable accessibility shortcut keys. Not applicable for setting specific shortcut key combinations.
- --state <string> REQUIRED enum:[true|false] — Shortkey state
### shortkey-get-state
Get shortcut key state. Used to query whether accessibility shortcut keys are currently enabled. Not applicable for modifying shortcut key status.
### high-contrast-set-state
Set high contrast text state. Used to enable or disable high contrast text to improve text readability. Not applicable for adjusting contrast level.
- --state <string> REQUIRED enum:[true|false] — High contrast text state
### high-contrast-get-state
Get high contrast text state. Used to query whether high contrast text is currently enabled. Not applicable for modifying high contrast status.
### invert-color-set-state
Set color inversion state. Used to enable or disable color inversion to assist users with color vision deficiency. Not applicable for adjusting inversion intensity.
- --state <string> REQUIRED enum:[true|false] — Invert color state
### invert-color-get-state
Get color inversion state. Used to query whether color inversion is currently enabled. Not applicable for modifying color inversion status.
### animation-off-set-state
Set animation off state. Used to enable or disable system animation to reduce dynamic effect interference. Not applicable for adjusting animation speed.
- --state <string> REQUIRED enum:[true|false] — Animation off state
### animation-off-get-state
Get animation off state. Used to query whether system animation is currently disabled. Not applicable for modifying animation settings.
### audio-set-mono
Set audio mono state. Used to enable or disable mono audio to assist users with single-sided hearing impairment. Not applicable for adjusting volume.
- --state <string> REQUIRED enum:[true|false] — Audio mono state
### audio-get-mono
Get audio mono state. Used to query whether audio mono is currently enabled. Not applicable for modifying audio settings.
### audio-set-balance
Set audio left-right channel balance. Used to adjust the volume ratio between left and right channels to assist users with unbalanced binaural hearing. Not applicable for adjusting overall volume.
- --balance <number> REQUIRED — Audio balance value (float)
### audio-get-balance
Get audio left-right channel balance value. Used to query the current volume ratio between left and right channels. Not applicable for modifying audio balance settings.
### daltonization-set-state
Set daltonization (color blindness correction) state. Used to enable or disable color blindness mode to assist users with color vision deficiency. Not applicable for adjusting color blindness mode intensity.
- --state <string> REQUIRED enum:[true|false] — Daltonization state
### daltonization-get-state
Get daltonization (color blindness correction) state. Used to query whether color blindness mode is currently enabled. Not applicable for modifying color blindness mode settings.
### daltonization-set-filter
Set daltonization (color blindness correction) filter type. Used to select filters suitable for different types of color vision deficiency. Not applicable for disabling color blindness mode.
- --type <integer> REQUIRED enum:[0|1|2|3] — Filter type (0=Normal, 1=Protanomaly, 2=Deuteranomaly, 3=Tritanomaly)
### daltonization-get-filter
Get daltonization (color blindness correction) filter type. Used to query the current color blindness filter type in use. Not applicable for modifying filter settings.
### click-set-response-time
Set click response time. Used to adjust the system response delay for click operations to assist users with hand tremors. Not applicable for adjusting long press time.
- --time <integer> REQUIRED enum:[0|1|2] — Click response time (0=short(default), 1=medium, 2=long)
### click-get-response-time
Get click response time setting. Used to query the current response delay time for click operations. Not applicable for modifying click response time.
### ignore-repeat-click-set-state
Set ignore repeat click state. Used to enable or disable repeat click filtering to assist users with hand tremors. Not applicable for adjusting filtering interval.
- --state <string> REQUIRED enum:[true|false] — Ignore repeat click state
### ignore-repeat-click-get-state
Get ignore repeat click state. Used to query whether repeat click filtering is currently enabled. Not applicable for modifying filter settings.
### ignore-repeat-click-set-time
Set ignore repeat click time interval. Used to adjust the time threshold for determining repeat clicks. Not applicable for enabling or disabling repeat click filtering.
- --interval <integer> REQUIRED enum:[0|1|2|3|4] — Ignore repeat click interval (0=0.1s, 1=0.4s, 2=0.7s, 3=1.0s, 4=1.3s)
### ignore-repeat-click-get-time
Get ignore repeat click time interval. Used to query the current time threshold for determining repeat clicks. Not applicable for modifying time interval settings.

## ohos-aa
ohos-aa - Ability management utility for starting an ability or stopping an application on the system.
### start
ohos-aa start - Start an ability on the system
- --help <boolean> default:false
- --abilityname <string> — abilityName
- --bundlename <string> — bundleName
- --deviceId <string> — deviceId
- --modulename <string> — moduleName
- --sandboxCloneIndex <integer> — Sandbox clone index for launching sandbox clone application (range: 2000-3000)
- --creatorBundle <string> — Creator bundle name for sandbox clone application
- --uri <string> — URI
- --action <string> — action
- --entity <string> — entity
- --type <string> — type
- --time <boolean> default:false — time
- --pi <string> — Parameter integer key-value pair map as JSON string. Example: '{"key1":100,"key2":101}'
- --pb <string> — Parameter boolean key-value pair map as JSON string. Example: '{"key1":true,"key2":false}'
- --ps <string> — Parameter string key-value pair map as JSON string. Example: '{"key1":"value1","key2":"value2"}'
- --psn <string> — For the string-type value corresponding to an empty key.
### force-stop
ohos-aa force-stop - Stop an application on the system.
- --help <boolean> default:false
- --bundlename <string> — bundleName

## ohos-arkTSScript
Run a specified function from an ArkTS script ABC file
- --abcPath <string> REQUIRED — ABC file path
- --scriptPath <string> — Optional script file or class name
- --functionName <string> REQUIRED — Function name to execute
- --args <string> — JSON object string for function arguments, for example {"arg0":10,"arg1":20}

## ohos-audioManager
Audio management tool for controlling volume, devices, and audio settings. Used for audio device management and volume control scenarios. Does not support advanced audio processing or routing configuration.
Permissions: ohos.permission.ACCESS_NOTIFICATION_POLICY, ohos.permission.USE_BLUETOOTH
### get-volume
Get the current volume for a specific volume type. Used for querying audio volume levels. Does not support volume change notifications.
- --type <string> default:"STREAM_MUSIC" — Volume type. Values: [STREAM_MUSIC, STREAM_RING, STREAM_VOICE_CALL, STREAM_VOICE_COMMUNICATION, STREAM_VOICE_ASSISTANT, STREAM_ALARM, STREAM_SYSTEM, STREAM_VOICE_RING, STREAM_NAVIGATION, STREAM_NOTIFICATION, STREAM_ULTRASONIC, STREAM_ANNOUNCEMENT, STREAM_EMERGENCY, STREAM_ALL]
### set-volume
Set the volume for a specific volume type. Used for adjusting audio volume levels. Does not support volume ramping or fade effects.
- --volume <integer> REQUIRED — Volume value to set (typically 0-100 or 0-15)
- --type <string> default:"STREAM_MUSIC" — Volume type. Values: [STREAM_MUSIC, STREAM_RING, STREAM_VOICE_CALL, STREAM_VOICE_COMMUNICATION, STREAM_VOICE_ASSISTANT, STREAM_ALARM, STREAM_SYSTEM, STREAM_VOICE_RING, STREAM_NAVIGATION, STREAM_NOTIFICATION, STREAM_ULTRASONIC, STREAM_ANNOUNCEMENT, STREAM_EMERGENCY, STREAM_ALL]
### get-max-volume
Get the maximum volume for a specific volume type. Used for querying volume range limits. Does not support custom volume range configuration.
- --type <string> default:"STREAM_MUSIC" — Volume type. Values: [STREAM_MUSIC, STREAM_RING, STREAM_VOICE_CALL, STREAM_VOICE_COMMUNICATION, STREAM_VOICE_ASSISTANT, STREAM_ALARM, STREAM_SYSTEM, STREAM_VOICE_RING, STREAM_NAVIGATION, STREAM_NOTIFICATION, STREAM_ULTRASONIC, STREAM_ANNOUNCEMENT, STREAM_EMERGENCY, STREAM_ALL]
### is-mute
Check if a specific volume type is muted. Used for querying mute state. Does not support mute state change notifications.
- --type <string> default:"STREAM_MUSIC" — Volume type. Values: [STREAM_MUSIC, STREAM_RING, STREAM_VOICE_CALL, STREAM_VOICE_COMMUNICATION, STREAM_VOICE_ASSISTANT, STREAM_ALARM, STREAM_SYSTEM, STREAM_VOICE_RING, STREAM_NAVIGATION, STREAM_NOTIFICATION, STREAM_ULTRASONIC, STREAM_ANNOUNCEMENT, STREAM_EMERGENCY, STREAM_ALL]
### set-mute
Set the mute state for a specific volume type. Used for muting or unmuting audio streams. Does not support per-device mute configuration.
- --mute <boolean> REQUIRED — Mute state: true to mute, false to unmute
- --type <string> default:"STREAM_MUSIC" — Volume type. Values: [STREAM_MUSIC, STREAM_RING, STREAM_VOICE_CALL, STREAM_VOICE_COMMUNICATION, STREAM_VOICE_ASSISTANT, STREAM_ALARM, STREAM_SYSTEM, STREAM_VOICE_RING, STREAM_NAVIGATION, STREAM_NOTIFICATION, STREAM_ULTRASONIC, STREAM_ANNOUNCEMENT, STREAM_EMERGENCY, STREAM_ALL]
### get-devices
Get the list of audio devices. Used for querying available audio devices. Does not support device capability details.
- --flag <string> default:"OUTPUT_DEVICES_FLAG" — Device flag. Values: [OUTPUT_DEVICES_FLAG, INPUT_DEVICES_FLAG, ALL_DEVICES_FLAG]
### select-output-device
Select the output audio device. Used for switching audio output device. Does not support simultaneous output to multiple devices.
- --type <string> REQUIRED — Device type. Values: [DEVICE_TYPE_INVALID, DEVICE_TYPE_EARPIECE, DEVICE_TYPE_SPEAKER, DEVICE_TYPE_WIRED_HEADSET, DEVICE_TYPE_WIRED_HEADPHONES, DEVICE_TYPE_BLUETOOTH_SCO, DEVICE_TYPE_BLUETOOTH_A2DP, DEVICE_TYPE_MIC, DEVICE_TYPE_USB_HEADSET, DEVICE_TYPE_DP, DEVICE_TYPE_REMOTE_CAST, DEVICE_TYPE_USB_DEVICE, DEVICE_TYPE_HDMI, DEVICE_TYPE_LINE_DIGITAL, DEVICE_TYPE_REMOTE_DAUDIO, DEVICE_TYPE_HEARING_AID, DEVICE_TYPE_NEARLINK, DEVICE_TYPE_SYSTEM_PRIVATE, DEFAULT]. Can be specified multiple times
### help
Show help information for commands. Used for displaying command usage and examples. Does not provide interactive tutorials.
- --command <string> — Optional command name to show detailed help

## ohos-avsession-manager
OHOS AVSession管理工具。用于查询和控制媒体会话播放状态。不支持创建会话和投屏功能。
Permissions: ohos.permission.MANAGE_MEDIA_RESOURCES, ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC
### list-sessions
列出系统中所有AVSession描述符。用于查询当前活跃的媒体会话。无参数输入。
### get-playback-state
获取会话播放状态。用于查询当前播放进度和状态信息。需要提供有效的sessionId。
- --session-id <string> REQUIRED — Session ID to query
### get-metadata
获取会话元数据。用于查询媒体标题、艺术家和专辑信息。需要提供有效的sessionId。
- --session-id <string> REQUIRED — Session ID to query
### get-valid-commands
获取有效控制命令列表。用于查询会话支持的播放控制操作。需要提供有效的sessionId。
- --session-id <string> REQUIRED — Session ID to query
### send-control-command-to-session
向特定会话发送控制命令。用于精确控制目标会话的播放状态。不支持自定义命令。
- --session-id <string> REQUIRED — Session ID to control
- --command <string> REQUIRED enum:[play|pause|stop|play_next|play_previous|fast_forward|rewind|seek|set_speed|set_loop_mode|set_target_loop_mode|toggle_favorite] — Control command to send
- --time <integer> — Time in milliseconds (required for seek, default 15000 for fast_forward/rewind)
- --speed <number> — Playback speed for set_speed command (default 1.0)
- --mode <integer> — Loop mode for set_loop_mode: -1=undefined, 0=sequence, 1=single, 2=list, 3=shuffle, 4=custom
- --target-mode <integer> — Target loop mode for set_target_loop_mode: -1=undefined, 0=sequence, 1=single, 2=list, 3=shuffle, 4=custom
- --asset-id <string> — Asset ID for toggle_favorite command (required)

## ohos-batteryManager
Battery capacity and energy query tool. Used for system management, maintenance troubleshooting and battery status inspection. Not applicable for real-time battery monitoring or battery event subscription.
### capacity
Query battery capacity percentage (0-100%). Used for battery status checking and system management scenarios. Not applicable for real-time monitoring or subscription-based battery events.
### total-energy
Query battery total energy in mAh. Used for battery hardware diagnostics and system maintenance scenarios. Requires system caller identity, not available for third-party applications.
### remain-energy
Query battery remaining energy in mAh. Used for battery health assessment and power management diagnostics. Requires system caller identity, not available for third-party applications.

## ohos-bluetoothTool
Bluetooth device management CLI tool. Used for enabling, disabling, and querying Bluetooth state. Not suitable for Bluetooth device pairing or connection management.
Permissions: ohos.permission.ACCESS_BLUETOOTH
### enable-bt
Enable Bluetooth. Used for activating Bluetooth functionality when the device is in disabled state. Requires Bluetooth service to be available.
### disable-bt
Disable Bluetooth functionality. Used for turning off Bluetooth when the device is enabled. Cannot be executed while Bluetooth is in connecting state.
### get-state
Get current Bluetooth adapter state. Used for querying Bluetooth status in diagnostic scenarios. Returns state information only, does not modify Bluetooth settings.
### get-paired-devices
Get list of paired Bluetooth devices. Used for querying paired devices when managing device connections or troubleshooting. Not suitable for discovering new devices.
- --transport <string> enum:[bredr|ble] — Transport type: bredr for classic Bluetooth, ble for BLE. Default: bredr
### get-device-name
Get device name by MAC address. Used for identifying paired devices when the device name is unknown. Requires device to be paired first.
- --addr <string> REQUIRED — Device MAC address in format XX:XX:XX:XX:XX:XX
### connect-profiles
Connect all allowed profiles to a paired device. Used for establishing Bluetooth connections for data transfer or audio streaming. Device must be paired and within range.
- --addr <string> REQUIRED — Device MAC address in format XX:XX:XX:XX:XX:XX
### disconnect-profiles
Disconnect all profiles from a connected device. Used for ending Bluetooth connections when data transfer or audio streaming is complete. Device must be connected first.
- --addr <string> REQUIRED — Device MAC address in format XX:XX:XX:XX:XX:XX

## ohos-bm
ohos-bm bundle management CLI tool
### uninstall
Uninstall an application package
- --help <boolean> default:false
- --bundleName <string> default:"" — Bundle name to uninstall
- --keepData <boolean> default:false
- --shared <boolean> default:false
- --version <string> default:"" — Uninstall inter-application shared library by version code
### dump
View application package information
- --help <boolean> default:false
- --all <boolean> default:false
- --debugBundle <boolean> default:false
- --bundleName <string> default:"" — Specify bundle name
- --shortcutInfo <boolean> default:false
- --deviceId <string> default:"" — Specify device ID
- --label <boolean> default:false
### dump-dependencies
View dependency information of specified application and module
- --help <boolean> default:false
- --bundleName <string> default:"" — Specify bundle name
- --moduleName <string> default:"" — Specify module name
### dump-shared
View inter-application shared library information
- --help <boolean> default:false
- --all <boolean> default:false
- --bundleName <string> default:"" — Specify bundle name
### clean
Clean application cache or data files
- --help <boolean> default:false
- --bundleName <string> default:"" — Specify bundle name
- --cache <boolean> default:false
- --data <boolean> default:false
- --appIndex <integer> default:0 — Specify application index
### set-disposed-rule
Set disposed rule for clone app to control component behavior
- --help <boolean> default:false
- --appId <string> REQUIRED — Application appId or appIdentifier
- --appIndex <integer> — Clone app index, a positive integer
- --priority <integer> REQUIRED — Disposed rule priority, non-negative integer, lower value means higher priority
- --componentType <string> REQUIRED — Component type to control: 1=UI_ABILITY, 2=UI_EXTENSION
- --disposedType <string> REQUIRED — Disposed type: 1=BLOCK_APPLICATION, 2=BLOCK_ABILITY, 3=NON_BLOCK
- --controlType <string> REQUIRED — Control type: 1=ALLOWED_LIST, 2=DISALLOWED_LIST
- --elements <array> — Controlled component element list, format: /bundleName/moduleName/abilityName, multiple elements allowed
- --wantBundleName <string> REQUIRED — Want redirection target bundleName
- --wantModuleName <string> — Want redirection target moduleName
- --wantAbilityName <string> REQUIRED — Want redirection target abilityName
- --wantParamsStrings <string> — Want string type additional parameters, format: Example: '{"key1":"value1","key2":"value2"}'
- --wantParamsInts <string> — Want int type additional parameters, format: Example: '{"key1":100,"key2":101}'
- --wantParamsBools <string> — Want bool type additional parameters, format: Example: '{"key1":true,"key2":false}'
### delete-disposed-rule
Delete disposed rule for clone app
- --help <boolean> default:false
- --appId <string> REQUIRED — Application appId or appIdentifier
- --appIndex <integer> — Clone app index, a positive integer
### get-recoverable-apps
Get recoverable (uninstalled pre-installed) applications info
- --help <boolean> default:false
### recover
Recover an uninstalled pre-installed application
- --help <boolean> default:false
- --bundleName <string> REQUIRED — Bundle name to recover
### create-cli-sandbox-app
Create an cli sandbox app
- --help <boolean> default:false
- --bundleName <string> REQUIRED — Bundle name need to create sandbox app
- --creatorBundleName <string> — Bundle name to create sandbox app
### destroy-cli-sandbox-app
Destroy an cli sandbox app
- --help <boolean> default:false
- --bundleName <string> REQUIRED — Bundle name need to destroy sandbox app
- --creatorBundleName <string> — Creator bundle name to destroy sandbox app
- --appIndex <integer> REQUIRED — AppIndex of the sandbox app to destroy

## ohos-displayManager
Display brightness management CLI tool for adjusting screen brightness. Used for system display configuration scenarios. Does not support advanced display features such as color calibration.
### set-brightness
Set the brightness level of a display device. Used for adjusting screen brightness in system management. Does not support brightness scheduling or automatic adjustment configuration.
- --value <integer> REQUIRED — Target brightness level to set. Used to specify desired screen brightness. Range: 0 (off) to 255 (maximum).
- --continuous <boolean> default:false — Continuous brightness adjustment mode. Used for smooth brightness transitions. Does not affect discrete step adjustments.

## ohos-location
定位服务命令行工具。用于查询和设置设备定位开关状态、获取缓存位置及实时定位。不支持非系统权限的第三方应用定位请求。
Permissions: ohos.permission.MANAGE_SECURE_SETTINGS, ohos.permission.CONTROL_LOCATION_SWITCH, ohos.permission.APPROXIMATELY_LOCATION, ohos.permission.LOCATION
### is-enabled
查询设备定位开关是否已启用。用于检查当前设备的定位功能状态。
### enable
启用设备定位开关。用于开启设备的定位功能以便获取位置信息。依赖系统定位服务运行。
- --userId <integer> default:-1 — 多用户场景下的用户ID，可选参数
### disable
禁用设备定位开关。用于关闭设备的定位功能以保护隐私。依赖系统定位服务运行。
- --userId <integer> default:-1 — 多用户场景下的用户ID，可选参数
### get-last-approximate-location
获取设备最后缓存的大致位置。用于快速获取位置信息而不启动实时定位。依赖定位开关已启用。
### get-last-precise-location
获取设备最后缓存的精确位置。用于获取高精度位置信息而不启动实时定位。依赖定位开关和定位权限已授予。
### get-current-approximate-location
获取设备当前大致位置（同步模式）。用于快速获取当前位置而不需要高精度定位。依赖定位开关已启用。
- --priority <string> enum:[accuracy|speed] default:"accuracy" — 定位优先级，accuracy为精度优先，speed为速度优先
- --timeout <integer> default:3000 — 等待定位结果的超时时间（毫秒）
### get-current-precise-location
获取设备当前精确位置（同步模式）。用于获取高精度GPS定位结果。依赖定位开关、GPS权限和良好的卫星信号。
- --priority <string> enum:[accuracy|speed] default:"accuracy" — 定位优先级，accuracy为精度优先，speed为速度优先
- --timeout <integer> default:3000 — 等待定位结果的超时时间（毫秒）

## ohos-nearlinkControl
NearLink control utility for enabling and disabling NearLink functionality. Used for NearLink device management scenarios. Does not support NearLink operations on non-NearLink capable devices.
Permissions: ohos.permission.ACCESS_NEARLINK, ohos.permission.MANAGE_NEARLINK
### enable
Enable NearLink functionality with optional auto-connect policy. Used for activating NearLink adapter. Does not support enabling when NearLink is already enabled or device does not support NearLink.
- --autoConnPolicy <integer> default:0 — Auto-connect policy when NearLink is enabled (0: AUTO_CONN_GENERAL, 1: AUTO_CONN_EXCEPT_AUDIO_DEVICES, 2: AUTO_CONN_EXCEPT_USER_DISCONNECTED_DEVICES)
### disable
Disable NearLink functionality. Used for deactivating NearLink adapter. Does not support disabling when NearLink is already disabled.

## ohos-networkShare
网络共享管理CLI工具。用于查询和控制系统网络共享状态（WiFi热点、USB tethering、蓝牙PAN）的启停和状态查询。仅限系统调用者使用，不支持普通应用调用。
Permissions: ohos.permission.cli.GET_HOTSPOT, ohos.permission.cli.SET_HOTSPOT
### is-supported
Check if network sharing is supported on the device. Used for querying device capabilities. Only available on devices with network sharing hardware support.
### is-sharing
Check if network sharing is currently active. Used for querying current network sharing status. Only reflects WiFi/USB/Bluetooth sharing states.
### start
Start network sharing of specified type. Used for enabling network sharing. Requires CONNECTIVITY_INTERNAL permission and system caller privilege.
- --type <string> REQUIRED enum:[wifi|usb|bluetooth] — Sharing type to start
### stop
Stop network sharing of specified type. Used for disabling network sharing. Requires CONNECTIVITY_INTERNAL permission and system caller privilege.
- --type <string> REQUIRED enum:[wifi|usb|bluetooth] — Sharing type to stop

## ohos-nfcManager
NFC management CLI tool for querying and controlling device NFC function status.
### get-state
Get current NFC state (off/turning_on/on/turning_off)
### turn-on
Enable device NFC function
### turn-off
Disable device NFC function
### is-available
Check if current device supports NFC function

## ohos-notificationManager
OpenHarmony notification management tool. Used for notification publishing, cancellation, removal, and querying active notifications. Does not support notification subscription or interactive UI operations.
Permissions: ohos.permission.NOTIFICATION_CONTROLLER, ohos.permission.NOTIFICATION_AGENT_CONTROLLER
### publish
Publish a notification. Used for sending notifications to the system. Does not support subscription-type notifications.
- --help <boolean> default:false
- --notificationId <integer> default:0 — 通知ID
- --notificationContent <string> REQUIRED — 通知内容JSON字符串。所有类型公共必填: title(≤1024B), text(≤3072B)；公共可选: additionalText(≤3072B)；所有属性超长截取。type仅支持basic、long_text、multiline:
basic示例: {"type":"basic","title":"通知标题","text":"通知内容","additionalText":"附加文本"}
long_text: longText(≤3072B)、expandedTitle(≤1024B)、briefText(≤1024B)，超长截取。示例: {"type":"long_text","title":"通知标题","text":"短内容","longText":"长文本内容","expandedTitle":"展开标题","briefText":"摘要","additionalText":"附加文本"}
multiline: expandedTitle(≤1024B)、briefText(≤1024B)、lines(≤3个元素,每个≤1024B)，超长截取。示例: {"type":"multiline","title":"通知标题","text":"通知内容","expandedTitle":"展开标题","briefText":"摘要","lines":["第一行","第二行","第三行"],"additionalText":"附加文本"}
- --slotType <integer> default:3 — 通知渠道类型（0=社交通信, 1=服务提醒, 2=内容信息, 3=其他, 6=客服消息，不支持4=自定义、5=实况通知、7=紧急信息）
- --updateOnly <boolean> default:false — 仅更新已存在的通知，不创建新通知
- --appMessageId <string> — 应用消息ID，用于标识特定消息
- --priorityNotificationType <string> enum:[OTHER|PRIMARY_CONTACT|AT_ME|URGENT_MESSAGE|SCHEDULE_REMINDER] — 优先级通知类型，枚举值: OTHER(非优先级通知)、PRIMARY_CONTACT(重要联系人)、AT_ME(有人@我)、URGENT_MESSAGE(紧急消息)、SCHEDULE_REMINDER(日程提醒)
- --alertOneTime <boolean> default:false — 仅提醒一次，后续更新不再提醒
- --sound <string> — 自定义通知声音URI
- --badgeNumber <integer> — 通知角标增加数量（设置为在当前角标基础上增加的数字，必须>=0）
- --autoDeletedTime <number> — 自动删除时间（毫秒）
- --label <string> — 通知标签（不超过204字节）
- --groupName <string> — 通知分组名称（不超过204字节，超长截取）
- --notificationFlags <string> — 通知提醒标志JSON字符串。支持字段: soundEnabled(声音)、vibrationEnabled(振动)、bannerEnabled(横幅)、lockScreenEnabled(锁屏)，值枚举: 2=CLOSE(关闭)。示例: {"soundEnabled":2,"vibrationEnabled":2}
### cancelById
Cancel notification by bundle and notification ID. Used for managing notifications of specific applications. Does not support canceling notifications without bundle information.
- --help <boolean> default:false
- --bundleOption <string> REQUIRED — 目标应用信息JSON字符串，包含bundleName(应用包名)和uid(应用UID)两个属性
- --notificationId <integer> REQUIRED — 待取消的通知ID
### cancelByBundle
Cancel all notifications for a specified bundle. Used for batch canceling notifications of a specific application.
- --help <boolean> default:false
- --bundleOption <string> REQUIRED — 目标应用信息JSON字符串，包含bundleName(应用包名)和uid(应用UID)两个属性
### batchCancel
Batch cancel notifications by hashcodes. Used for canceling specific notifications identified by their hashcodes.
- --help <boolean> default:false
- --hashcodes <string> REQUIRED — 通知哈希码JSON数组字符串，指定要移除的通知列表
### enableNotification
Set notification enabled/disabled for bundle. Used for controlling notification permissions of applications. Does not support setting status without bundle information.
- --help <boolean> default:false
- --bundleOption <string> REQUIRED — 目标应用信息JSON字符串，包含bundleName(应用包名)和uid(应用UID)两个属性
- --enabled <boolean> REQUIRED default:false — 通知开关状态（true=启用, false=禁用）
### setSlotFlags
Set notification slot flags for bundle. Used for configuring notification reminder modes of applications. Does not support setting slot flags without bundle information.
- --help <boolean> default:false
- --bundleOption <string> REQUIRED — 目标应用信息JSON字符串，包含bundleName(应用包名)和uid(应用UID)两个属性
- --flags <integer> REQUIRED — 渠道标志位掩码，仅bit0-bit5有效（bit0=声音, bit1=锁屏, bit2=横幅, bit3=亮屏, bit4=振动, bit5=状态栏图标），必须>=0且不能大于0b111111(63)，其中亮屏(bit3)和状态栏图标(bit5)设置关闭不会生效，服务端会强制保持开启
### listAllNotification
List all active notifications. Used for querying current notification status. Does not support listing notifications for other users.
- --help <boolean> default:false

## ohos-pasteboard
A command-line tool for pasteboard management that supports reading, writing, and querying pasteboard data. Suitable for setting or getting HTML, URI, or plain text data. Not suitable for setting or getting non-text data types.
Permissions: ohos.permission.READ_PASTEBOARD
### set-data
Set pasteboard data. Suitable for setting HTML, URI, or plain text data. Not suitable for setting non-text data types.
- --html <string> — HTML content to set in pasteboard
- --uri <string> — URI content to set in pasteboard
- --text <string> — Plain text content to set in pasteboard
### get-data
Get pasteboard data. Suitable for getting HTML, URI, or plain text data. Not suitable for non-text data types.
### clear-data
Clear pasteboard data. Used for resetting pasteboard state. Not suitable for selective record deletion.
### has-data
Check if pasteboard contains any data. Used for verifying the status of the pasteboard before getting data. Not suitable for content-level data verification.
### has-data-type
Check if pasteboard contains data of specific data type. Used for verifying the status of the pasteboard before getting data. Not suitable for content-level data verification.
- --type <string> REQUIRED enum:[text/plain|text/html|text/uri] — Type to check (e.g., text/plain, text/html, text/uri)
### has-remote-data
Check if pasteboard contains remote data from distributed devices. Used for distributed pasteboard state verification. Not suitable for detailed remote device information query.

## ohos-powerManager
Power management CLI tool for device suspend, wakeup, power mode switching and screen off timeout management. Used for system administration and automated device power control scenarios. Does not support callback registration or long-running monitoring operations.
### suspend
Suspend device and turn off screen with fixed 'application' reason. Used for remotely or programmatically putting the device into suspend state. Does not support custom suspend reasons other than 'application'.
- --immediately <boolean> default:false — Whether to suspend immediately without delay
### wakeup
Wake up device and turn on screen with fixed 'application' reason. Used for remotely or programmatically waking the device from suspend state. Does not support custom wakeup reasons other than 'application'.
- --detail <string> default:"cli-call" — Wakeup detail description string, max 128 characters
### set-power-mode
Set device power mode to normal or powerSave. Used for switching between balanced and power-save profiles. Does not support performance, extreme or custom power modes.
- --mode <string> REQUIRED enum:[normal|powerSave] — Target power mode: 'normal' for balanced mode or 'powerSave' for power save mode
### override-screen-off-time
Override the system screen off timeout with a custom value in milliseconds. Used for temporarily extending or shortening the screen off delay. Does not persist across device reboots.
- --time <integer> REQUIRED — Screen off timeout in milliseconds, must be a positive integer
### restore-screen-off-time
Restore the screen off timeout to the system default value. Used for reverting a previous override-screen-off-time call. Has no effect if no override is currently active.

## ohos-queryTime
Query system time information including wall time, boot time, monotonic time, and time zone. Used for system time diagnostics and monitoring scenarios. Does not support setting or modifying system time.
### get-wall-time
Get wall time (UTC time in milliseconds from 1970-01-01 00:00:00). Used for obtaining the current system UTC timestamp. Does not support time format conversion.
### get-boot-time
Get boot time (milliseconds since boot, including sleep time). Used for measuring system uptime including suspend periods. Does not provide high-precision timing for short intervals.
### get-monotonic-time
Get monotonic time (milliseconds since boot, excluding sleep time). Used for precise interval timing that pauses during system suspend. Does not include time spent in sleep state.
### get-time-zone
Get current time zone ID. Used for retrieving the system timezone setting. Does not support timezone conversion or DST calculation.

## ohos-storageManager
Storage manager CLI tool for querying storage statistics. Used for retrieving disk space information and application storage usage. Does not support real-time storage monitoring or modification.
Permissions: ohos.permission.STORAGE_MANAGER
### get-total-size
Get total storage size. Used for querying the total capacity of device storage. Does not return information about individual partitions.
### get-free-size
Get free storage size. Used for checking available disk space before installing apps or saving files. Does not support per-partition free space query.
### get-system-size
Get system partition size. Used for checking the size of the system partition. Does not support querying other partition types.
### get-user-storage-stats
Get user storage statistics. Used for checking user data storage usage. Does not support historical statistics or trend analysis.
- --userId <integer> default:100 — User id
### get-bundle-stats
Get storage statistics for a specific bundle. Used for checking how much storage an application is using. Does not support querying uninstalled applications.
- --packageName <string> REQUIRED — Bundle name to app
- --appIndex <integer> default:0 — Application index, default 0
### get-current-bundle-stats
Get storage statistics for the current running application. Used for an app to check its own storage usage. Does not support querying other applications.

## ohos-usageStatsQuery
Application usage statistics query tool. Used for system administration and performance analysis scenarios. Does not support real-time monitoring or subscription operations.
Permissions: ohos.permission.cli.BUNDLE_ACTIVE_INFO
### check-bundle-idle
Query whether an application is in idle state. Used for application usage analysis. Requires bundle name parameter.
- --bundle <string> REQUIRED — Application bundle name to query
- --user <integer> default:-1 — User ID, -1 means current user
### check-bundle-period
Query whether an application is in use period. Used for application usage pattern analysis. Only available for native processes.
- --bundle <string> REQUIRED — Application bundle name to query
- --user <integer> default:-1 — User ID, -1 means current user
### query-stats-interval
Query application usage statistics within a time interval. Used for application usage frequency analysis. Requires valid time range and interval type.
- --interval <integer> REQUIRED — Interval type: 0=by_day, 1=by_week, 2=by_month, 3=by_year
- --begin <number> REQUIRED — Begin time in milliseconds
- --end <number> REQUIRED — End time in milliseconds
- --user <integer> default:-1 — User ID, -1 means current user
### query-events
Query application event records within a time range. Used for application usage history analysis. Requires valid time range.
- --begin <number> REQUIRED — Begin time in milliseconds
- --end <number> REQUIRED — End time in milliseconds
- --user <integer> default:-1 — User ID, -1 means current user
- --max <integer> default:1000 — Maximum number of records to return
### query-app-group
Query application group information. Used for application priority analysis. Requires bundle name parameter.
- --bundle <string> REQUIRED — Application bundle name to query
- --user <integer> default:-1 — User ID, -1 means current user
### query-high-freq-bundle
Query high-frequency usage application list. Used for identifying frequently used applications. Returns top N most used apps.
- --user <integer> default:-1 — User ID, -1 means current user
- --max <integer> default:20 — Maximum number of apps to return
- --days <integer> default:7 — Query day range
### query-module-records
Query module usage records. Used for analyzing application module usage patterns. Returns module usage history.
- --max <integer> default:1000 — Maximum number of records to return
- --user <integer> default:-1 — User ID, -1 means current user
### query-notification-stats
Query notification event statistics. Used for analyzing application notification patterns. Requires valid time range.
- --begin <number> REQUIRED — Begin time in milliseconds
- --end <number> REQUIRED — End time in milliseconds
- --user <integer> default:-1 — User ID, -1 means current user
### query-high-freq-period
Query high-frequency usage period for applications. Used for analyzing application usage time patterns. Returns peak usage hours.
- --user <integer> default:-1 — User ID, -1 means current user
### query-latest-used-time
Query the latest usage time of an application today. Used for tracking recent application usage. Requires bundle name parameter.
- --bundle <string> REQUIRED — Application bundle name to query
- --user <integer> default:-1 — User ID, -1 means current user

## ohos-vibratorControl
Vibrator control utility for starting preset vibrations and checking effect support. Used for triggering device haptic feedback and querying vibration capability. Does not support custom vibration patterns.
Permissions: ohos.permission.VIBRATE
### startVibrator
Start preset vibration effect
- --effectId <string> REQUIRED — The preset vibration effect ID
### isSupportEffect
Check preset vibration effect ID to query
- --effectId <string> REQUIRED — The preset vibration effect ID to query (e.g., haptic.clock.timer)

## ohos-wifiManager
WiFi STA mode control tool for enabling/disabling STA mode and scanning networks
### sta-enable
Enable WiFi STA mode
### sta-disable
Disable WiFi STA mode
### scan-start
Start WiFi scan
### scan-list
List WiFi scan results
### sta-connect
Connect to a specified WiFi network in STA mode. Supports open networks and WPA/WPA2/WPA3-PSK secured networks. The preSharedKey parameter is required for encrypted WiFi and optional for open WiFi.
- --ssid <string> REQUIRED
- --preSharedKey <string>
### sta-getLinkedInfo
Get current WiFi linked information (SSID, BSSID, signal, frequency, link speed)
