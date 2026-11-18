import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { SERVER_CA, SERVER_PIN } from './Trust';

interface PairReply { token: string; protocol: string; }
interface PairRequest { code: string; }
interface SequenceRequest { sequence: number; }
interface CameraRequest { action: string; generation: number; sequence: number; source?: string; }
export interface CommandExtra {
  pan?: number; tilt?: number; panSign?: number; tiltSign?: number;
  speed?: number; duration?: number; frameId?: number; index?: number;
  slot?: string; name?: string;
}
interface CommandRequest extends CommandExtra { action: string; generation: number; sequence: number; }
interface Axes { panSign: number; tiltSign: number; }
interface Selection { mode: string; box: number[] | null; }
interface Preset { name: string; pan: number; tilt: number; panSign: number; tiltSign: number; }
interface PresetList { slots: Record<string, Preset>; }
interface Camera { state: string; frames: number; generation: number; }
interface Observation { state: string; reason?: string; confidence?: number | null; }
export interface EmotionCandidate { label: string; confidence: number; xyxy: number[]; }
interface EmotionPreview { frameId: number; frameAgeMs: number; cameraGeneration: number; width: number; height: number; detections: EmotionCandidate[]; }
interface Emotion { ready: boolean; fresh: boolean; error?: string | null; observation: Observation; preview?: EmotionPreview | null; }
const EMOTION_LABELS: Record<string, string> = { 'Cry': '哭泣表情', 'Happy': '笑脸', 'Neutral': '中性表情', 'Sleep': '闭眼状态' };
export const EMOTION_OVERLAY_MS: number = 600;
export function candidateText(item: EmotionCandidate): string {
  return (EMOTION_LABELS[item.label] || item.label) + ' · 模型分数 ' + (item.confidence * 100).toFixed(1) + '%';
}
interface SensorHealth { dht11: string; }
interface ReportData { temp: number | null; hum: number | null; sensorHealth: SensorHealth; }
interface Report { fresh: boolean; data: ReportData; }
interface VoiceData { stops: number; applied: number; }
interface Voice { fresh: boolean; data: VoiceData; }
interface StatusData { voice: number; il_trip: number; il_stop: number; il_arm: number; il_pg: number; }
interface Status { fresh: boolean; data: StatusData; }
interface ControllerData { pan: number; tilt: number; pwm?: number; fault?: number; enabled?: number; trip?: number; }
interface ControllerFeedback { fresh: boolean; profile: string; data: ControllerData; }
interface Device { connected: boolean; readOnly?: boolean; controller?: ControllerFeedback; report?: Report; voiceRx?: Voice; status?: Status; }
interface HardwareFeatures { motor?: boolean; }
interface WireState {
  protocol: string; generation: number; hardware: boolean; mode: string; message: string;
  pan: number; tilt: number; remainingMs: number; axes: Axes; presets: PresetList;
  frameId: number | null; frameAgeMs: number | null; frameFresh: boolean; faces: number[][]; selection: Selection; width: number; height: number;
  camera: Camera; emotion: Emotion; device: Device; controlState: string;
  servoBench?: boolean; hardwareFeatures?: HardwareFeatures;
}

export class ViewState {
  online: boolean = false;
  hardware: boolean = false;
  mode: string = 'idle';
  message: string = '尚未配对';
  pan: number = 90;
  tilt: number = 90;
  remaining: string = '--';
  temperature: string = '--';
  humidity: string = '--';
  sensor: string = '无数据';
  voice: string = '--';
  stops: string = '--';
  protection: string = '--';
  controllerLink: string = '未接入主控';
  controllerProfile: string = '--';
  controllerTarget: string = '--';
  controllerOutput: string = '--';
  label: string = '未确认';
  candidates: string[] = [];
  emotionBoxes: EmotionCandidate[] = [];
  emotionFrameId: number = -1;
  emotionWidth: number = 0;
  emotionHeight: number = 0;
  camera: string = '未连接';
  execution: string = '未连接';
  presets: string[] = ['空预置位', '空预置位', '空预置位'];
  faceCount: number = 0;
  frameId: number = -1;
  selected: boolean = false;
  canTrack: boolean = false;
  canRock: boolean = false;
  canSoothe: boolean = false;
  rockUnavailable: string = '';
  panSign: number = 1;
  tiltSign: number = 1;
}

export class PreviewFrame {
  pixels: image.PixelMap | undefined = undefined;
  id: number = -1;
  faces: number[][] = [];
  width: number = 640;
  height: number = 480;
}

export class Controller {
  onState: (state: ViewState) => void = (_: ViewState): void => {};
  onImage: (frame: PreviewFrame) => void = (_: PreviewFrame): void => {};
  private host: string = '';
  private token: string = '';
  private generation: number = 0;
  private sequence: number = 0;
  private run: number = 0;
  private active: boolean = false;
  private busy: boolean = false;
  private imaging: boolean = false;
  private displayedFrame: number = -1;
  private imageEpoch: number = 0;
  private imageTimer: number = -1;
  private cameraGeneration: number = -1;
  private connecting: boolean = false;
  private timer: number = -1;
  private emotionTimer: number = -1;
  private overlayTimer: number = -1;
  private view: ViewState = new ViewState();
  private requests: http.HttpRequest[] = [];
  private pixels: image.PixelMap | undefined = undefined;

  private async request(path: string, payload?: string, binary: boolean = false): Promise<http.HttpResponse> {
    if (!SERVER_CA || !SERVER_PIN) { throw new Error('尚未配置电脑证书'); }
    const task = http.createHttp();
    this.requests.push(task);
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.token) { headers['Authorization'] = 'Bearer ' + this.token; }
    try {
      const result = await task.request('https://' + this.host + ':8443' + path, {
        method: payload === undefined ? http.RequestMethod.GET : http.RequestMethod.POST,
        header: headers, extraData: payload, usingCache: false, usingProxy: false,
        caData: SERVER_CA, certificatePinning: { publicKeyHash: SERVER_PIN, hashAlgorithm: 'SHA-256' },
        connectTimeout: 1200, readTimeout: 1200, maxLimit: binary ? 2097152 : 65536,
        expectDataType: binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
      });
      if (result.responseCode !== 200) {
        if (result.responseCode === 401) { this.token = ''; }
        throw new Error(result.responseCode === 401 ? '配对失效，请重新配对' : '请求未执行 (' + result.responseCode + ')');
      }
      return result;
    } finally {
      this.requests = this.requests.filter((item: http.HttpRequest) => item !== task);
      task.destroy();
    }
  }

  private accept(result: http.HttpResponse, requestedAt: number): void {
    const state = JSON.parse(result.result as string) as WireState;
    if (state.protocol !== 'harmony-control-1' || !Number.isInteger(state.generation)) { throw new Error('电脑端协议不匹配'); }
    if (state.generation < this.generation) { return; }
    this.generation = state.generation;
    const v = new ViewState();
    v.online = true; v.hardware = state.hardware; v.mode = state.mode; v.message = state.message;
    v.pan = state.pan; v.tilt = state.tilt; v.panSign = state.axes.panSign; v.tiltSign = state.axes.tiltSign;
    v.remaining = state.mode === 'idle' ? '--' : (state.remainingMs / 1000).toFixed(1) + ' 秒';
    v.frameId = state.frameFresh && state.frameId !== null ? state.frameId : -1;
    v.faceCount = state.frameFresh ? state.faces.length : 0;
    v.selected = state.selection.mode === 'selected';
    v.canTrack = state.frameFresh && (state.selection.mode !== 'selected' || state.selection.box !== null);
    const motorUnsupported = state.hardware && (state.servoBench === true || state.hardwareFeatures?.motor === false);
    const hardwareOffline = state.hardware && (state.controlState === 'offline' || state.controlState === 'stopping');
    v.canRock = !motorUnsupported && !hardwareOffline;
    v.rockUnavailable = motorUnsupported ? '当前固件未启用电机控制' : hardwareOffline ? '主控未就绪，不能摇摆' : '';
    v.canSoothe = v.canRock && state.emotion.ready && state.emotion.fresh && state.frameFresh;
    v.camera = state.camera.state === 'streaming' ? (state.frameFresh ? '相机采集中' : '画面延迟，自动控制暂停') + ' · ' + state.camera.frames + ' 帧' : state.camera.state === 'connecting' ? '正在连接相机' : state.camera.state === 'error' ? '相机连接异常' : '相机未连接';
    const observation = state.emotion.observation;
    const p = state.emotion.preview;
    const previewAge = p ? p.frameAgeMs + Math.max(0, Date.now() - requestedAt) : 1500;
    const previewFresh = state.emotion.ready && state.emotion.fresh && !state.emotion.error && p !== null && p !== undefined &&
      p.cameraGeneration === state.camera.generation && Number.isFinite(previewAge) && p.frameAgeMs >= 0 && previewAge < 1500;
    const candidates: EmotionCandidate[] = previewFresh && p ? p.detections : [];
    const reasons: Record<string, string> = { 'no_detection': '未检测到目标', 'low_confidence': '低分候选，待确认', 'multiple_detections': '多目标待确认', 'ambiguous_class': '类别冲突，待确认', 'confirming': '等待连续确认' };
    const reason = reasons[observation.reason || ''] || '待确认';
    v.label = state.emotion.error ? '识别异常' : !state.emotion.ready ? '模型未就绪' : !state.emotion.fresh || (p && !previewFresh) ? '等待新画面' :
      observation.state === 'Unknown' ? (candidates.length ? candidateText(candidates[0]) + ' · ' + reason : '识别中 · ' + reason) :
      (EMOTION_LABELS[observation.state] || observation.state) + ' · 连续确认' +
        (typeof observation.confidence === 'number' ? ' · 模型分数 ' + (observation.confidence * 100).toFixed(1) + '%' : '');
    v.candidates = candidates.slice(0, 5).map((item: EmotionCandidate): string => '候选：' + candidateText(item));
    if (this.emotionTimer !== -1) { clearTimeout(this.emotionTimer); this.emotionTimer = -1; }
    if (this.overlayTimer !== -1) { clearTimeout(this.overlayTimer); this.overlayTimer = -1; }
    if (previewFresh && p) {
      if (previewAge < EMOTION_OVERLAY_MS) {
        v.emotionBoxes = candidates; v.emotionFrameId = p.frameId;
        v.emotionWidth = p.width; v.emotionHeight = p.height;
        this.overlayTimer = setTimeout(() => {
          this.view.emotionBoxes = []; this.onState(this.view);
        }, EMOTION_OVERLAY_MS - previewAge);
      }
      this.emotionTimer = setTimeout(() => {
        this.view.label = '等待新画面'; this.view.candidates = []; this.view.emotionBoxes = []; this.onState(this.view);
      }, 1500 - previewAge);
    }
    v.execution = !state.hardware ? '软件预演，无硬件输出' : state.controlState === 'accepted' ? '主控已接纳（非实测位移）' : state.controlState;
    for (let n = 0; n < 3; n++) {
      const saved = state.presets.slots[(n + 1).toString()];
      if (saved) { v.presets[n] = saved.name + ' · ' + saved.pan + '°/' + saved.tilt + '°'; }
    }
    const report = state.device.report;
    if (report && report.fresh) {
      v.sensor = report.data.sensorHealth.dht11;
      v.temperature = report.data.temp === null ? '--' : report.data.temp.toFixed(1) + ' °C';
      v.humidity = report.data.hum === null ? '--' : report.data.hum.toFixed(1) + ' %';
    }
    const voice = state.device.voiceRx;
    if (voice && voice.fresh) { v.stops = voice.data.stops + ' / ' + voice.data.applied; }
    const status = state.device.status;
    if (status && status.fresh) {
      v.voice = '0x' + status.data.voice.toString(16);
      v.protection = 'STOP ' + status.data.il_stop + ' · ARM ' + status.data.il_arm + ' · PG ' + status.data.il_pg + ' · TRIP ' + status.data.il_trip;
    }
    v.controllerLink = state.device.connected ? (state.device.readOnly ? '已连接 · 只读日志' : '已连接') : '主控未连接';
    const board = state.device.controller;
    if (board && board.fresh) {
      v.controllerProfile = board.profile === 'GB01' ? 'GB01 · 空载舵机台架' : board.profile;
      v.controllerTarget = board.data.pan + '° / ' + board.data.tilt + '°（软件目标）';
      v.controllerOutput = board.profile === 'GB01' ? 'PWM ' + board.data.pwm + ' · 故障 ' + board.data.fault : '使能 ' + board.data.enabled + ' · TRIP ' + board.data.trip;
      if (board.profile === 'GB01') {
        v.sensor = '台架固件已禁用'; v.voice = '台架固件已禁用';
        v.protection = 'GB01 未接外部保护；PWM 不代表实测位置';
      }
    } else if (board) { v.controllerProfile = '日志已过期'; }
    if (state.device.readOnly) { v.execution = '控制为软件预演；主控日志只读'; }
    this.view = v; this.onState(v);
    if (state.camera.generation !== this.cameraGeneration) {
      this.cameraGeneration = state.camera.generation;
      ++this.imageEpoch; this.clearPreview();
    }
    const displayable = state.frameId !== null && state.frameAgeMs !== null && Number.isFinite(state.frameAgeMs) && state.frameAgeMs >= 0 && state.frameAgeMs < 2000;
    if (state.camera.state === 'disconnected') { ++this.imageEpoch; this.clearPreview(); }
    else if (!displayable) { ++this.imageEpoch; }
    else if (!this.imaging && state.frameId !== this.displayedFrame) {
      this.fetchImage(state.frameId as number, state.frameFresh ? state.faces : [], state.width, state.height, this.run, 2000 - (state.frameAgeMs as number));
    }
  }

  private clearPreview(): void {
    if (this.imageTimer !== -1) { clearTimeout(this.imageTimer); this.imageTimer = -1; }
    const old = this.pixels; this.pixels = undefined; this.displayedFrame = -1;
    this.onImage(new PreviewFrame());
    if (old) { old.release(); }
  }

  private async fetchImage(frame: number, faces: number[][], width: number, height: number, run: number, lifetime: number): Promise<void> {
    this.imaging = true;
    const epoch = this.imageEpoch;
    let expired = false;
    let published = false;
    // Download and decode consume this frame's lifetime; newer metadata cannot renew it.
    const timer = setTimeout(() => {
      expired = true;
      if (run === this.run && epoch === this.imageEpoch && this.displayedFrame === frame) { this.clearPreview(); }
    }, lifetime);
    let source: image.ImageSource | undefined = undefined;
    try {
      const response = await this.request('/frame.jpg?frame=' + frame, undefined, true);
      source = image.createImageSource(response.result as ArrayBuffer);
      const pixels = await source.createPixelMap();
      if (this.active && run === this.run && epoch === this.imageEpoch && !expired) {
        if (this.imageTimer !== -1) { clearTimeout(this.imageTimer); }
        this.imageTimer = timer; published = true;
        const old = this.pixels; this.pixels = pixels; this.displayedFrame = frame;
        const preview = new PreviewFrame();
        preview.pixels = pixels; preview.id = frame; preview.faces = faces; preview.width = width; preview.height = height;
        this.onImage(preview);
        if (old) { old.release(); }
      } else { pixels.release(); }
    } catch (_) { /* A single missed image does not clear a still-valid displayed frame. */ }
    finally {
      if (!published) { clearTimeout(timer); }
      if (source) { source.release(); }
      this.imaging = false;
    }
  }

  async connect(host: string, code: string): Promise<void> {
    if (this.connecting) { return; }
    if (!/^(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|127\.0\.0\.1)$/.test(host)
      || host.split('.').some((part: string) => Number(part) > 255)) { this.fail('请输入电脑局域网 IPv4'); return; }
    this.suspend();
    if (host !== this.host) { this.token = ''; }
    this.host = host;
    this.connecting = true;
    const run = ++this.run;
    try {
      if (!this.token) {
        if (!/^\d{8}$/.test(code)) { throw new Error('请输入电脑显示的 8 位配对码'); }
        const request: PairRequest = { code: code };
        const result = await this.request('/api/pair', JSON.stringify(request));
        const pair = JSON.parse(result.result as string) as PairReply;
        if (pair.protocol !== 'harmony-control-1' || !/^[a-f0-9]{64}$/.test(pair.token)) { throw new Error('配对协议不符'); }
        this.token = pair.token; this.sequence = 0;
      }
      if (run !== this.run) { return; }
      this.active = true; this.generation = 0;
      await this.poll(run);
    } catch (error) { if (run === this.run) { this.fail((error as Error).message); } }
    finally { this.connecting = false; }
  }

  private async poll(run: number): Promise<void> {
    if (!this.active || run !== this.run) { return; }
    try {
      if (!this.busy) {
        const requestedAt = Date.now();
        const result = await this.request('/api/state');
        if (!this.active || run !== this.run) { return; }
        this.accept(result, requestedAt);
        if (this.view.mode !== 'idle' && !this.busy) { await this.command('heartbeat'); }
      }
    } catch (_) { if (run === this.run) { this.fail('连接中断，控制已退出'); } }
    if (this.active && run === this.run) { this.timer = setTimeout(() => { this.poll(run); }, 150); }
  }

  async command(action: string, extra: CommandExtra = {}): Promise<void> {
    if (!this.active || (this.busy && action !== 'stop')) { return; }
    if ((action === 'rock' && !this.view.canRock) || (action === 'arm_soothe' && !this.view.canSoothe)) { return; }
    const run = this.run;
    this.busy = true;
    const data: CommandRequest = { action: action, generation: this.generation, sequence: ++this.sequence,
      pan: extra.pan, tilt: extra.tilt, panSign: extra.panSign, tiltSign: extra.tiltSign,
      speed: extra.speed, duration: extra.duration, frameId: extra.frameId, index: extra.index,
      slot: extra.slot, name: extra.name };
    try {
      const requestedAt = Date.now();
      const result = await this.request('/api/control', JSON.stringify(data));
      if (this.active && run === this.run) { this.accept(result, requestedAt); }
    } catch (error) {
      if (run === this.run) { this.fail((error as Error).message); }
    } finally { this.busy = false; }
  }

  async camera(source: string): Promise<void> {
    if (!this.active || this.busy) { return; }
    this.busy = true;
    ++this.imageEpoch; this.clearPreview();
    const run = this.run;
    const data: CameraRequest = { action: source ? 'connect' : 'disconnect', generation: this.generation, sequence: ++this.sequence };
    if (source) { data.source = source; }
    try {
      const requestedAt = Date.now();
      const result = await this.request('/api/camera', JSON.stringify(data));
      if (run === this.run && this.active) { this.accept(result, requestedAt); }
    } catch (error) { if (run === this.run) { this.fail((error as Error).message); } }
    finally { this.busy = false; }
  }

  suspend(): void {
    const wasActive = this.active;
    this.active = false; ++this.run; ++this.imageEpoch; this.cameraGeneration = -1;
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    if (this.emotionTimer !== -1) { clearTimeout(this.emotionTimer); this.emotionTimer = -1; }
    if (this.overlayTimer !== -1) { clearTimeout(this.overlayTimer); this.overlayTimer = -1; }
    this.requests.forEach((request: http.HttpRequest) => { request.destroy(); }); this.requests = [];
    if (wasActive && this.token) {
      const request: SequenceRequest = { sequence: ++this.sequence };
      this.request('/api/suspend', JSON.stringify(request)).catch(() => {});
    }
    this.view = new ViewState(); this.view.message = '已断开，需手动连接'; this.onState(this.view); this.clearPreview();
  }

  private fail(message: string): void {
    this.suspend(); this.view.message = message; this.onState(this.view);
  }
}

export const controller = new Controller();
