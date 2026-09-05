import { NodeRuntime } from '../node/NodeRuntime';
import { BonioMemory } from '../node/MemoryService';
import { common } from '@kit.AbilityKit';

@Component
export struct MemoryTab {
  runtime: NodeRuntime | undefined = undefined;

  @State memories: BonioMemory[] = [];
  @State searchText: string = '';
  @State selectedTag: string = '';
  @State selectedMemory: BonioMemory | undefined = undefined;
  @State isLoading: boolean = false;
  @State errorText: string = '';
  private readonly memoryChanged = (): void => { void this.refresh(); };

  aboutToAppear() {
    this.runtime?.memoryService.addChangeListener(this.memoryChanged);
    void this.refresh();
  }

  aboutToDisappear() {
    this.runtime?.memoryService.removeChangeListener(this.memoryChanged);
  }

  private async refresh() {
    if (!this.runtime?.isConnected) {
      this.errorText = '请先连接 Bonio 服务';
      return;
    }
    this.isLoading = true;
    this.errorText = '';
    try {
      this.memories = await this.runtime.memoryService.list();
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '记忆加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private filteredMemories(): BonioMemory[] {
    const query = this.searchText.trim().toLowerCase();
    return this.memories.filter((memory: BonioMemory): boolean => {
      if (this.selectedTag && !memory.tags.includes(this.selectedTag)) return false;
      if (!query) return true;
      return [memory.title, memory.content, memory.sourceApp, memory.pageTitle, memory.source, ...memory.tags]
        .join(' ')
        .toLowerCase()
        .includes(query);
    });
  }

  private tags(): string[] {
    const counts: Record<string, number> = {};
    this.memories.forEach((memory: BonioMemory) => {
      memory.tags.forEach((tag: string) => {
        counts[tag] = (counts[tag] || 0) + 1;
      });
    });
    return Object.keys(counts).sort((a: string, b: string): number => counts[b] - counts[a]);
  }

  private formatDate(timestamp: number): string {
    if (!timestamp) return '';
    const now = Date.now();
    const diff = now - timestamp;
    if (diff < 60 * 1000) return '刚刚';
    if (diff < 60 * 60 * 1000) return `${Math.floor(diff / 60000)}分钟前`;
    if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / 3600000)}小时前`;
    const date = new Date(timestamp);
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  private sourceName(memory: BonioMemory): string {
    return memory.pageTitle || memory.sourceApp || memory.source || '屏幕内容';
  }

  private isMsdpMemory(memory: BonioMemory): boolean {
    return memory.source.startsWith('msdp_');
  }

  private coverDataUrl(memory: BonioMemory): string {
    return `data:image/jpeg;base64,${memory.coverImage}`;
  }

  private detailImageDataUrl(memory: BonioMemory): string {
    if (!memory.originalImage) return '';
    return `data:${memory.originalImageMimeType || 'image/png'};base64,${memory.originalImage}`;
  }

  private cardTags(memory: BonioMemory): string[] {
    const content = memory.tags.find((tag: string): boolean => tag.startsWith('内容:'));
    const behavior = memory.tags.find((tag: string): boolean => tag.startsWith('行为:'));
    return [content, behavior].filter((tag: string | undefined): boolean => !!tag) as string[];
  }

  private async deleteSelectedMemory() {
    if (!this.runtime || !this.selectedMemory) return;
    try {
      await this.runtime.memoryService.delete(this.selectedMemory.id);
      this.selectedMemory = undefined;
      await this.refresh();
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '删除记忆失败';
    }
  }

  private async openMemoryDetail(memory: BonioMemory) {
    if (!this.runtime) {
      this.selectedMemory = memory;
      return;
    }
    this.errorText = '';
    try {
      const detailedMemory = await this.runtime.memoryService.get(memory.id);
      this.selectedMemory = detailedMemory || memory;
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '记忆详情加载失败';
      this.selectedMemory = memory;
    }
  }

  private confirmDeleteSelectedMemory() {
    if (!this.selectedMemory) return;
    AlertDialog.show({
      title: '删除这条记忆？',
      message: '删除后将无法恢复。',
      autoCancel: true,
      primaryButton: {
        value: '删除',
        action: () => { void this.deleteSelectedMemory(); }
      },
      secondaryButton: {
        value: '取消',
        action: () => {}
      }
    });
  }

  private async openSourceLink(pageLink: string) {
    if (!/^https?:\/\//i.test(pageLink)) {
      this.errorText = '来源链接无效';
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await context.startAbility({ action: 'ohos.want.action.viewData', uri: pageLink });
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '无法打开来源页面';
    }
  }

  private isTagSelected(tag: string): boolean {
    return tag === '全部' ? this.selectedTag === '' : this.selectedTag === tag;
  }

  @Builder TagChip(tag: string, count: number) {
    Button(`${tag} ${count}`)
      .type(ButtonType.Normal)
      .height(30)
      .fontSize(12)
      .fontColor(this.isTagSelected(tag) ? '#FFFFFF' : '#4D5B70')
      .backgroundColor(this.isTagSelected(tag) ? '#0A59F7' : '#FFFFFF')
      .border({ width: 1, color: this.isTagSelected(tag) ? '#0A59F7' : '#D8E1EF', radius: 15 })
      .margin({ right: 8 })
      .onClick(() => {
        if (tag === '全部') {
          this.selectedTag = '';
          return;
        }
        this.selectedTag = this.selectedTag === tag ? '' : tag;
      })
  }

  @Builder MemoryRow(memory: BonioMemory) {
    Row() {
      if (memory.coverImage) {
        Image(this.coverDataUrl(memory))
          .width(50)
          .height(50)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .margin({ right: 12 })
      } else {
        Text(this.isMsdpMemory(memory) ? '◇' : '▤')
          .fontSize(22)
          .fontColor('#0A59F7')
          .width(50)
          .height(50)
          .textAlign(TextAlign.Center)
          .padding({ top: 12 })
          .backgroundColor('#E8F1FF')
          .borderRadius(6)
          .margin({ right: 12 })
      }
      Column() {
        Row() {
          Text(memory.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1D2939')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.formatDate(memory.createdAt))
            .fontSize(11)
            .fontColor('#8A97A9')
            .margin({ left: 8 })
        }
        .width('100%')
        Text(memory.content)
          .fontSize(13)
          .fontColor('#667085')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 4 })
        if (this.cardTags(memory).length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.cardTags(memory), (tag: string) => {
              Text(tag)
                .fontSize(11)
                .fontColor(tag.startsWith('行为:') ? '#027A48' : '#0A59F7')
                .backgroundColor(tag.startsWith('行为:') ? '#ECFDF3' : '#E8F1FF')
                .borderRadius(3)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ right: 6, top: 6 })
            }, (tag: string): string => tag)
          }
          .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 13, bottom: 13 })
    .border({ width: { bottom: 1 }, color: '#E8EDF5' })
    .onClick(() => {
      void this.openMemoryDetail(memory);
    })
  }

  @Builder MemoryDetail(memory: BonioMemory) {
    Column() {
      Row() {
        Button('‹')
          .type(ButtonType.Normal)
          .width(36)
          .height(36)
          .fontSize(28)
          .fontColor('#0A59F7')
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.selectedMemory = undefined; })
        Text('记忆详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172033')
          .layoutWeight(1)
        Button('删除')
          .type(ButtonType.Normal)
          .fontSize(13)
          .fontColor('#D92D20')
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.confirmDeleteSelectedMemory(); })
      }
      .width('100%')
      .height(58)
      .padding({ left: 8, right: 12 })
      Scroll() {
        Column() {
          Text(memory.title)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#172033')
            .width('100%')
          Text(this.sourceName(memory))
            .fontSize(13)
            .fontColor('#667085')
            .width('100%')
            .margin({ top: 8 })
          Text(this.formatDate(memory.createdAt))
            .fontSize(12)
            .fontColor('#98A2B3')
            .width('100%')
            .margin({ top: 4 })
          if (memory.originalImage) {
            Image(this.detailImageDataUrl(memory))
              .width('100%')
              .height(360)
              .objectFit(ImageFit.Contain)
              .borderRadius(6)
              .margin({ top: 16 })
          }
          if (memory.tags.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(memory.tags, (tag: string) => {
                Text(tag)
                  .fontSize(12)
                  .fontColor('#0A59F7')
                  .backgroundColor('#E8F1FF')
                  .borderRadius(4)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .margin({ right: 6, top: 12 })
              }, (tag: string): string => tag)
            }
            .width('100%')
          }
          Divider().margin({ top: 20, bottom: 20 })
          Text(memory.content)
            .fontSize(16)
            .fontColor('#344054')
            .lineHeight(25)
            .width('100%')
          if (memory.pageLink) {
            Button('打开来源')
              .type(ButtonType.Normal)
              .height(36)
              .fontSize(13)
              .fontColor('#0A59F7')
              .backgroundColor('#E8F1FF')
              .borderRadius(6)
              .margin({ top: 24 })
              .onClick(() => { void this.openSourceLink(memory.pageLink); })
            Text(memory.pageLink)
              .fontSize(12)
              .fontColor('#667085')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 8 })
          }
        }
        .width('100%')
        .padding(20)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  build() {
    if (this.selectedMemory) {
      this.MemoryDetail(this.selectedMemory)
    } else {
      Column() {
        Row() {
          TextInput({ text: this.searchText, placeholder: '搜索记忆' })
            .height(40)
            .fontSize(14)
            .backgroundColor('#EFF3F8')
            .borderRadius(8)
            .layoutWeight(1)
            .onChange((value: string) => { this.searchText = value; })
          Button('↻')
            .type(ButtonType.Normal)
            .width(36)
            .height(36)
            .fontSize(22)
            .fontColor('#0A59F7')
            .backgroundColor(Color.Transparent)
            .margin({ left: 8 })
            .onClick(() => { void this.refresh(); })
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 12, bottom: 8 })
        Scroll(new Scroller()) {
          Row() {
            this.TagChip('全部', this.memories.length)
            ForEach(this.tags(), (tag: string) => {
              this.TagChip(tag, this.memories.filter((memory: BonioMemory): boolean => memory.tags.includes(tag)).length)
            }, (tag: string): string => tag)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .height(42)
        if (this.errorText) {
          Text(this.errorText)
            .fontSize(12)
            .fontColor('#D92D20')
            .width('100%')
            .padding({ left: 16, right: 16, top: 4 })
        }
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(28).height(28)
            Text('正在加载记忆…').fontSize(13).fontColor('#98A2B3').margin({ top: 10 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.filteredMemories().length === 0) {
          Column() {
            Text('▤').fontSize(46).fontColor('#B7C5D9')
            Text(this.memories.length === 0 ? '还没有记忆' : '没有匹配的记忆')
              .fontSize(16)
              .fontColor('#667085')
              .margin({ top: 10 })
            Text(this.memories.length === 0 ? '通过聊天或 Bonio 保存的内容会显示在这里' : '换个关键词或标签试试')
              .fontSize(13)
              .fontColor('#98A2B3')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.filteredMemories(), (memory: BonioMemory) => {
              ListItem() { this.MemoryRow(memory) }
            }, (memory: BonioMemory): string => memory.id)
          }
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')
    }
  }
}
