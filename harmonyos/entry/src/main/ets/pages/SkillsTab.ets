import { NodeRuntime } from '../node/NodeRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3D00;

class SkillEntry {
  id: string = '';
  name: string = '';
  description: string = '';
  enabled: boolean = true;
  builtin: boolean = false;
}

class EmptyParams {
}

class SkillIdParams {
  id: string = '';
}

@Component
export struct SkillsTab {
  runtime: NodeRuntime | undefined = undefined;

  @State avatarSkin: string = 'cat';
  @State skills: SkillEntry[] = [];
  @State isLoading: boolean = false;
  @State errorText: string = '';
  @State isConnected: boolean = false;
  @State statusText: string = 'Offline';

  private statusTimer: number = -1;

  aboutToAppear() {
    this.avatarSkin = this.runtime?.prefs.getAvatarSkin() || 'cat';
    this.refreshStatus();
    this.statusTimer = setInterval(() => { this.refreshStatus(); }, 1000);
    void this.loadSkills();
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  private refreshStatus() {
    if (this.runtime) {
      this.isConnected = this.runtime.isConnected;
      this.statusText = this.runtime.statusText;
    }
  }

  private async loadSkills() {
    if (!this.runtime?.isConnected) {
      this.errorText = '请先连接 Bonio 服务';
      this.skills = [];
      return;
    }
    this.isLoading = true;
    this.errorText = '';
    try {
      const response = await this.runtime.operatorSession.request('skills.list', new EmptyParams());
      const payload = (response.payload as Record<string, Object>) || {};
      const rawList = payload['skills'];
      const entries: SkillEntry[] = [];
      if (Array.isArray(rawList)) {
        rawList.forEach((item: Object) => {
          const raw = item as Record<string, Object>;
          const entry = new SkillEntry();
          entry.id = typeof raw['id'] === 'string' ? raw['id'] as string : '';
          entry.name = typeof raw['name'] === 'string' ? raw['name'] as string : '';
          entry.description = typeof raw['description'] === 'string' ? raw['description'] as string : '';
          entry.enabled = typeof raw['enabled'] === 'boolean' ? raw['enabled'] as boolean : true;
          entry.builtin = typeof raw['builtin'] === 'boolean' ? raw['builtin'] as boolean : false;
          if (entry.id) entries.push(entry);
        });
      }
      this.skills = entries;
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '技能列表加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private async toggleSkill(entry: SkillEntry) {
    if (!this.runtime?.isConnected) return;
    const targetEnabled = !entry.enabled;
    try {
      const method = targetEnabled ? 'skills.enable' : 'skills.disable';
      const skillParams = new SkillIdParams();
      skillParams.id = entry.id;
      await this.runtime.operatorSession.request(method, skillParams);
      entry.enabled = targetEnabled;
      // Refresh list to reflect authoritative server state.
      void this.loadSkills();
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '技能状态切换失败';
      void this.loadSkills();
    }
  }

  private selectAvatarSkin(skin: string): void {
    const normalized = skin === 'kun' ? 'kun' : 'cat';
    this.avatarSkin = normalized;
    this.runtime?.prefs.setAvatarSkin(normalized);
    AppStorage.setOrCreate<string>('avatarSkin', normalized);
  }

  @Builder SectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#0A59F7')
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: 16, top: 20, bottom: 6 })
  }

  @Builder SkinChoice(value: string, title: string, subtitle: string) {
    Row() {
      Column() {
        Text(title).fontSize(15).fontColor('#333333')
        Text(subtitle).fontSize(12).fontColor('#999999').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Radio({ value: value, group: 'avatarSkin' })
        .checked(this.avatarSkin === value)
        .onChange((isChecked: boolean) => {
          if (isChecked) this.selectAvatarSkin(value);
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.White)
    .onClick(() => this.selectAvatarSkin(value))
  }

  @Builder SkillRow(entry: SkillEntry) {
    Row() {
      Column() {
        Row() {
          Text(entry.name).fontSize(15).fontColor('#333333').fontWeight(FontWeight.Medium)
          if (entry.builtin) {
            Text('内置')
              .fontSize(10)
              .fontColor('#0A59F7')
              .backgroundColor('#E8F0FE')
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .margin({ left: 8 })
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(entry.description)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 3 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: entry.enabled })
        .selectedColor('#0A59F7')
        .onChange(() => {
          this.toggleSkill(entry);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
  }

  build() {
    Column() {
      // Header
      Text('SKILLS')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0A59F7')
        .width('100%')
        .margin({ bottom: 4 })
      Text('Avatar & Skills')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .margin({ bottom: 4 })
      Text('Choose your avatar skin and manage backend skills.')
        .fontSize(13)
        .fontColor('#999999')
        .width('100%')
        .margin({ bottom: 12 })

      List({ space: 8 }) {
        // Avatar Skin Section
        ListItem() { this.SectionHeader('Avatar Skin') }
        ListItem() {
          this.SkinChoice('cat', 'Cat', 'Lottie cat avatar')
        }
        ListItem() {
          this.SkinChoice('kun', 'Kun', 'Pixel-art Kun avatar')
        }

        // Skills Section
        ListItem() { this.SectionHeader('Backend Skills (DSH)') }
        if (this.isLoading) {
          ListItem() {
            Row() {
              LoadingProgress().width(28).height(28).color('#0A59F7')
              Text('Loading skills...').fontSize(14).fontColor('#999999').margin({ left: 12 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 24, bottom: 24 })
          }
        } else if (this.errorText) {
          ListItem() {
            Column() {
              Text(this.errorText)
                .fontSize(14)
                .fontColor('#E53935')
                .textAlign(TextAlign.Center)
                .width('100%')
              if (!this.isConnected) {
                Text('请前往 Settings 页签连接 Bonio 服务后查看后端技能。')
                  .fontSize(12)
                  .fontColor('#999999')
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .margin({ top: 8 })
              } else {
                Button('Retry')
                  .fontSize(14)
                  .fontColor(Color.White)
                  .backgroundColor('#0A59F7')
                  .borderRadius(8)
                  .margin({ top: 12 })
                  .onClick(() => { void this.loadSkills(); })
              }
            }
            .width('100%')
            .padding({ top: 24, bottom: 24 })
            .backgroundColor(Color.White)
          }
        } else if (this.skills.length === 0) {
          ListItem() {
            Text('No skills found on the backend.')
              .fontSize(14)
              .fontColor('#999999')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 24, bottom: 24 })
              .backgroundColor(Color.White)
          }
        } else {
          ForEach(this.skills, (skill: SkillEntry) => {
            ListItem() {
              this.SkillRow(skill)
            }
          }, (skill: SkillEntry) => skill.id)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FAFAFA')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }
}