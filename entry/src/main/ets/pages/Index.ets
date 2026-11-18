import { controller, ViewState, PreviewFrame, EmotionCandidate, candidateText, EMOTION_OVERLAY_MS } from '../model/Controller';
import { DEFAULT_HOST } from '../model/Trust';

@Entry
@Component
struct Index {
  @State state: ViewState = new ViewState();
  @State preview: PreviewFrame = new PreviewFrame();
  @State host: string = DEFAULT_HOST;
  @State code: string = '';
  @State cameraIp: string = '';
  @State pan: number = 90;
  @State tilt: number = 90;
  @State reversePan: boolean = false;
  @State reverseTilt: boolean = false;
  @State speed: number = 20;
  @State duration: number = 3000;
  @State slot: number = 0;
  @State presetName: string = '观察位';
  @State tab: number = 1;
  private readonly accent: string = '#087F73';
  private readonly ink: string = '#153333';

  aboutToAppear(): void {
    controller.onState = (state: ViewState): void => {
      if (!this.state.online && state.online) {
        this.tab = 0;
        this.pan = state.pan; this.tilt = state.tilt;
        this.reversePan = state.panSign === -1; this.reverseTilt = state.tiltSign === -1;
      }
      this.state = state;
    };
    controller.onImage = (frame: PreviewFrame): void => { this.preview = frame; };
  }
  onPageHide(): void { controller.suspend(); }
  aboutToDisappear(): void { controller.suspend(); }

  private move(action: string): void {
    controller.command(action);
  }

  private async center(): Promise<void> {
    await controller.command('center');
    if (this.state.online) { this.pan = this.state.pan; this.tilt = this.state.tilt; }
  }

  private async recall(): Promise<void> {
    await controller.command('preset_apply', { slot: (this.slot + 1).toString() });
    if (this.state.online) {
      this.pan = this.state.pan; this.tilt = this.state.tilt;
      this.reversePan = this.state.panSign === -1; this.reverseTilt = this.state.tiltSign === -1;
    }
  }

  @Builder
  section(title: string) {
    Text(title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(this.ink).width('100%').margin({ top: 16, bottom: 10 })
  }

  @Builder
  datum(label: string, value: string) {
    Column({ space: 5 }) {
      Text(label).fontSize(12).fontColor('#526C6B')
      Text(value).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  connection() {
    this.section('连接电脑')
    TextInput({ placeholder: '电脑局域网 IP', text: this.host }).onChange((value: string) => { this.host = value.trim(); })
      .enabled(!this.state.online).backgroundColor('#FFFFFF').borderRadius(6)
    Row({ space: 8 }) {
      TextInput({ placeholder: '8 位配对码', text: this.code }).type(InputType.NUMBER_PASSWORD).maxLength(8)
        .onChange((value: string) => { this.code = value; }).layoutWeight(1).enabled(!this.state.online).backgroundColor('#FFFFFF').borderRadius(6)
      Button(this.state.online ? '断开' : '配对连接', { type: ButtonType.Normal }).height(44).borderRadius(6).backgroundColor(this.accent)
        .onClick(() => { if (this.state.online) { controller.suspend(); } else { controller.connect(this.host, this.code); } })
    }.margin({ top: 8 })
  }

  @Builder
  camera() {
    this.section('实时画面')
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.preview.pixels) {
        Image(this.preview.pixels).width('100%').height('100%').objectFit(ImageFit.Fill)
        if (this.state.online && this.preview.id >= this.state.emotionFrameId && this.preview.id - this.state.emotionFrameId < EMOTION_OVERLAY_MS &&
          this.preview.width === this.state.emotionWidth && this.preview.height === this.state.emotionHeight) {
          ForEach(this.state.emotionBoxes, (item: EmotionCandidate) => {
            Text('候选 ' + item.label + ' ' + (item.confidence * 100).toFixed(1) + '%')
              .width((100 * (item.xyxy[2] - item.xyxy[0]) / this.preview.width) + '%')
              .height((100 * (item.xyxy[3] - item.xyxy[1]) / this.preview.height) + '%')
              .position({ x: (100 * item.xyxy[0] / this.preview.width) + '%', y: (100 * item.xyxy[1] / this.preview.height) + '%' })
              .fontSize(11).fontColor('#126F9B').align(Alignment.TopStart).maxLines(2)
              .border({ width: 2, color: '#126F9B', style: BorderStyle.Dashed }).hitTestBehavior(HitTestMode.None)
              .accessibilityText('候选 ' + candidateText(item))
          })
        }
        ForEach(this.preview.faces, (box: number[], index: number) => {
          Button((index + 1).toString(), { type: ButtonType.Normal })
            .width((100 * (box[2] - box[0]) / this.preview.width) + '%').height((100 * (box[3] - box[1]) / this.preview.height) + '%')
            .position({ x: (100 * box[0] / this.preview.width) + '%', y: (100 * box[1] / this.preview.height) + '%' })
            .backgroundColor('#16087F73').fontColor('#FFFFFF').border({ width: 2, color: '#12B7A4' }).borderRadius(2)
            .enabled(this.state.online && this.state.mode === 'idle' && this.state.canTrack && this.state.frameId === this.preview.id)
            .onClick(() => { controller.command('select_target', { frameId: this.preview.id, index: index }); })
        })
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.video')).fontSize(36).fontColor(['#6B8985'])
          Text(this.state.online ? '等待相机画面' : '未连接').fontSize(15).fontColor('#526C6B')
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
    }.width('100%').aspectRatio(this.preview.width / this.preview.height).backgroundColor('#E5ECEA').borderRadius(6).clip(true)
    Column({ space: 5 }) {
      Text(this.state.camera).fontSize(12).fontColor('#526C6B').width('100%')
      Text(this.state.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.accent).width('100%')
      ForEach(this.state.candidates, (text: string) => {
        Text(text).fontSize(12).fontColor('#315651').width('100%')
      })
    }.alignItems(HorizontalAlign.Start).margin({ top: 8, bottom: 8 })
    Row({ space: 8 }) {
      TextInput({ placeholder: '相机 IP', text: this.cameraIp }).onChange((value: string) => { this.cameraIp = value.trim(); })
        .layoutWeight(1).backgroundColor('#FFFFFF').borderRadius(6)
      Button('连接', { type: ButtonType.Normal }).borderRadius(6).backgroundColor(this.accent).height(42)
        .enabled(this.state.online && this.state.mode === 'idle' && this.cameraIp.length > 0)
        .onClick(() => { controller.camera(this.cameraIp); })
      Button('断开', { type: ButtonType.Normal }).borderRadius(6).backgroundColor('#DAE8E5').fontColor(this.accent).height(42)
        .enabled(this.state.online && this.state.mode === 'idle').onClick(() => { controller.camera(''); })
    }
    Row({ space: 8 }) {
      Button(this.state.selected ? '跟踪所选目标' : '自动单人脸跟踪', { type: ButtonType.Normal }).layoutWeight(1).borderRadius(6).backgroundColor(this.accent)
        .enabled(this.state.online && this.state.canTrack && this.state.mode === 'idle')
        .onClick(() => { controller.command('auto', { panSign: this.reversePan ? -1 : 1, tiltSign: this.reverseTilt ? -1 : 1 }); })
      Button('清除选择', { type: ButtonType.Normal }).borderRadius(6).backgroundColor('#DAE8E5').fontColor(this.accent)
        .enabled(this.state.online && this.state.selected && this.state.mode === 'idle').onClick(() => { this.move('clear_target'); })
    }.margin({ top: 10 })
  }

  @Builder
  gimbal() {
    this.section('云台角度')
    Row() { Text('水平目标').layoutWeight(1); Text(this.pan + '°').fontWeight(FontWeight.Bold) }
    Slider({ value: this.pan, min: 60, max: 120, step: 1 }).selectedColor(this.accent)
      .onChange((value: number) => { this.pan = Math.round(value); })
    Row() { Text('俯仰目标').layoutWeight(1); Text(this.tilt + '°').fontWeight(FontWeight.Bold) }
    Slider({ value: this.tilt, min: 75, max: 105, step: 1 }).selectedColor(this.accent)
      .onChange((value: number) => { this.tilt = Math.round(value); })
    Row({ space: 8 }) {
      Button('应用角度', { type: ButtonType.Normal }).layoutWeight(1).borderRadius(6).backgroundColor(this.accent)
        .enabled(this.state.online && (this.state.mode === 'idle' || this.state.mode === 'manual'))
        .onClick(() => { controller.command('manual', { pan: this.pan, tilt: this.tilt }); })
      Button('回中', { type: ButtonType.Normal }).layoutWeight(1).borderRadius(6).backgroundColor('#DAE8E5').fontColor(this.accent)
        .enabled(this.state.online && (this.state.mode === 'idle' || this.state.mode === 'manual')).onClick(() => { this.center(); })
    }
    Row() {
      Checkbox({ name: 'pan' }).select(this.reversePan).selectedColor(this.accent).enabled(this.state.mode === 'idle')
        .onChange((value: boolean) => { this.reversePan = value; })
      Text('水平反向').fontSize(13).layoutWeight(1)
      Checkbox({ name: 'tilt' }).select(this.reverseTilt).selectedColor(this.accent).enabled(this.state.mode === 'idle')
        .onChange((value: boolean) => { this.reverseTilt = value; })
      Text('俯仰反向').fontSize(13).layoutWeight(1)
    }.margin({ top: 8 })
    this.section('预置位')
    Select(this.state.presets.map((name: string, index: number): SelectOption => { return { value: (index + 1) + ' · ' + name }; }))
      .selected(this.slot).value((this.slot + 1) + ' · ' + this.state.presets[this.slot])
      .onSelect((index: number) => { this.slot = index; }).width('100%').backgroundColor('#FFFFFF')
    Row({ space: 8 }) {
      TextInput({ text: this.presetName, placeholder: '预置名称' }).maxLength(16).onChange((value: string) => { this.presetName = value; })
        .layoutWeight(1).backgroundColor('#FFFFFF').borderRadius(6)
      Button({ type: ButtonType.Normal }) { SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(20) }
        .width(44).height(44).borderRadius(6).backgroundColor('#DAE8E5').fontColor(this.accent).accessibilityText('保存预置位')
        .enabled(this.state.online && this.state.mode === 'idle' && this.presetName.trim().length > 0)
        .onClick(() => { controller.command('preset_save', { slot: (this.slot + 1).toString(), name: this.presetName, pan: this.pan, tilt: this.tilt, panSign: this.reversePan ? -1 : 1, tiltSign: this.reverseTilt ? -1 : 1 }); })
    }.margin({ top: 8 })
    Button('转到预置位', { type: ButtonType.Normal }).width('100%').borderRadius(6).backgroundColor(this.accent).margin({ top: 8 })
      .enabled(this.state.online && this.state.mode === 'idle' && this.state.presets[this.slot] !== '空预置位')
      .onClick(() => { this.recall(); })
  }

  @Builder
  soothe() {
    this.section('限时摇摆')
    if (this.state.rockUnavailable.length > 0) {
      Text(this.state.rockUnavailable).width('100%').fontSize(13).fontColor('#526C6B').margin({ bottom: 8 })
    }
    Row({ space: 12 }) {
      Select([{ value: '10%' }, { value: '15%' }, { value: '20%' }]).selected([10, 15, 20].indexOf(this.speed)).value(this.speed + '%').layoutWeight(1)
        .onSelect((index: number) => { this.speed = 10 + index * 5; })
      Select([{ value: '2 秒' }, { value: '3 秒' }, { value: '5 秒' }]).selected([2000, 3000, 5000].indexOf(this.duration)).value((this.duration / 1000) + ' 秒').layoutWeight(1)
        .onSelect((index: number) => { this.duration = [2000, 3000, 5000][index]; })
    }
    Button('摇摆一次', { type: ButtonType.Normal }).width('100%').borderRadius(6).backgroundColor(this.accent).margin({ top: 8 })
      .enabled(this.state.online && this.state.mode === 'idle' && this.state.canRock)
      .onClick(() => { controller.command('rock', { speed: this.speed, duration: this.duration }); })
    Button('启用单次 Cry 触发', { type: ButtonType.Normal }).width('100%').borderRadius(6).backgroundColor('#DAE8E5').fontColor(this.accent).margin({ top: 8 })
      .enabled(this.state.online && this.state.mode === 'idle' && this.state.canSoothe).onClick(() => { this.move('arm_soothe'); })
  }

  @Builder
  feedback() {
    this.section('主控实时状态')
    Column({ space: 12 }) {
      Row() { Text('主控链路').layoutWeight(1); Text(this.state.controllerLink) }
      Row() { Text('固件类型').layoutWeight(1); Text(this.state.controllerProfile) }
      Text('主控目标 ' + this.state.controllerTarget).width('100%')
      Text(this.state.controllerOutput).width('100%').fontColor(this.accent)
    }.padding({ bottom: 16 })
    Row({ space: 16 }) { this.datum('温度', this.state.temperature); this.datum('湿度', this.state.humidity) }.padding({ bottom: 16 })
    Divider().color('#D0DEDA')
    Column({ space: 14 }) {
      Row() { Text('传感器').layoutWeight(1); Text(this.state.sensor) }
      Row() { Text('语音命令').layoutWeight(1); Text(this.state.voice) }
      Row() { Text('STOP 接收 / 处理').layoutWeight(1); Text(this.state.stops) }
      Text('保护状态（软件报告）').width('100%').fontColor('#526C6B')
      Text(this.state.protection).width('100%')
      Text(this.state.execution).width('100%').fontColor(this.accent)
      Text('控制目标（软件）' + this.state.pan + '° / ' + this.state.tilt + '°').width('100%')
    }.padding({ top: 16 })
  }

  build() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text('陪护控制台').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.ink)
          Text(this.state.online ? (this.state.hardware ? '已配对 · 硬件控制' : '已配对 · 软件预演') : '未连接').fontSize(12).fontColor(this.accent)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('停止', { type: ButtonType.Normal }).height(48).width(88).borderRadius(6).backgroundColor('#B6293B')
          .enabled(this.state.online).onClick(() => { this.move('stop'); })
      }.padding({ left: 20, right: 20, top: 16, bottom: 14 })
      Row() {
        Text(this.state.message).fontSize(13).fontColor(this.ink).layoutWeight(1)
        Text(this.state.remaining).fontSize(13).fontColor('#526C6B')
      }.padding({ left: 20, right: 20, bottom: 12 })
      Tabs({ barPosition: BarPosition.Start, index: this.tab }) {
        TabContent() {
          Scroll() { Column() { this.camera(); this.gimbal(); this.soothe() }.padding({ left: 20, right: 20, bottom: 32 }).width('100%') }
        }.tabBar('画面与控制')
        TabContent() {
          Scroll() { Column() { this.feedback(); this.connection(); Text('无人桌面原型；视觉标签不等于情绪或医疗判断。').fontSize(12).fontColor('#526C6B').margin({ top: 20 }) }.padding(20).width('100%') }
        }.tabBar('状态与连接')
      }.layoutWeight(1).barMode(BarMode.Fixed).onChange((index: number) => { this.tab = index; })
    }.width('100%').height('100%').backgroundColor('#F4F7F6')
  }
}
