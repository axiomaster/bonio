import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NodeRuntime } from '../node/NodeRuntime';
import { SecurePrefs } from '../common/SecurePrefs';
import { DeviceIdentityStore } from '../common/DeviceIdentityStore';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

const DOMAIN = 0x3D00;

export default class EntryAbility extends UIAbility {
  private initPromise: Promise<void> | undefined = undefined;
  private isBackgroundRunning: boolean = false;

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '!!! EntryAbility onCreate - ai.openclaw.harmonyos STARTING !!!');

    this.initPromise = (async () => {
      try {
        // Initialize core storage before NodeRuntime
        const prefs = SecurePrefs.getInstance();
        await prefs.init(this.context);
        const identityStore = new DeviceIdentityStore(this.context);
        await identityStore.loadOrCreate();

        // Create NodeRuntime and store it in AppStorage for the UI to access
        const runtime = new NodeRuntime(this.context);
        AppStorage.setOrCreate<NodeRuntime>('nodeRuntime', runtime);
        hilog.info(DOMAIN, 'testTag', 'NodeRuntime initialized and stored in AppStorage');
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'Failed to initialize NodeRuntime: %{public}s', JSON.stringify(e));
        // Even if it fails, we should resolve so loadContent can proceed and show the error in UI
      }
    })();
    
    await this.initPromise;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    this.stopBackgroundRunning();
    const runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (runtime) {
      runtime.disconnect();
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // Ensure initialization is fully complete before loading UI content
    if (this.initPromise) {
      hilog.info(DOMAIN, 'testTag', 'onWindowStageCreate: waiting for initPromise...');
      await this.initPromise;
      hilog.info(DOMAIN, 'testTag', 'onWindowStageCreate: initPromise resolved.');
    }

    windowStage.loadContent('pages/LoginPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    this.stopBackgroundRunning();
    const runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (runtime) {
      runtime.setForeground(true);
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    const runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (runtime) {
      runtime.setForeground(false);
      // Only start background task if connected
      if (runtime.isConnected) {
        this.startBackgroundRunning();
      }
    }
  }

  private startBackgroundRunning(): void {
    if (this.isBackgroundRunning) return;
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'ai.openclaw.harmonyos',
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      wantAgent.getWantAgent(wantAgentInfo).then((agent: object) => {
        backgroundTaskManager.startBackgroundRunning(this.context,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent).then(() => {
          this.isBackgroundRunning = true;
          hilog.info(DOMAIN, 'testTag', 'Background running started for data transfer');
        }).catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to start background running: %{public}s', String(err));
        });
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to get want agent: %{public}s', String(err));
      });
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'startBackgroundRunning error: %{public}s', String(e));
    }
  }

  private stopBackgroundRunning(): void {
    if (!this.isBackgroundRunning) return;
    try {
      backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
        this.isBackgroundRunning = false;
        hilog.info(DOMAIN, 'testTag', 'Background running stopped');
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to stop background running: %{public}s', String(err));
      });
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'stopBackgroundRunning error: %{public}s', String(e));
    }
  }
}
