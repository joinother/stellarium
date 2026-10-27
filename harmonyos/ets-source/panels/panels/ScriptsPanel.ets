import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { RecordingEntry } from '../../pages/MainWindowModels'
import { ToolsStore } from '../../state/ToolsStore'
import { ScriptStore } from '../../state/ScriptStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { GuideLibrary } from '../guide/GuideLibrary'
import { scriptZh, scriptDesc } from '../../common/derive/labels'

// 脚本面板，对应 `activePanel === 'scripts'`：脚本列表 / 回放 / 录制 / 屏幕 MP4 / 帧序列导出。
//
// 脚本与录制状态来自 ScriptStore（@ObjectLink），录制开关读 ToolsStore（@ObjectLink）；
// guideSessionActive 由宿主派生后传入。所有动作回调注入宿主；scriptZh/scriptDesc 直连
// common/derive/labels，scriptMetaLine/scriptSourceLine 读 scriptStore 元数据，故由宿主回注。

@Component
export struct ScriptsPanel {
  @ObjectLink tools: ToolsStore
  // guideSessionActive 属导览会话域，由宿主 scriptSessionActive() 派生，故为 @Prop。
  @Prop guideSessionActive: boolean
  @ObjectLink scriptStore: ScriptStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onWillApplyTheme(theme: Theme) {
    this.c = slotsFromTheme(theme)
  }
  scriptMetaLine: (filename: string) => string = () => ''
  scriptSourceLine: (filename: string) => string = () => ''
  onStartGuide: (id: string) => void = () => {}
  onStopPlayback: () => void = () => {}
  onImportScript: () => void = () => {}
  onPlayScript: (name: string) => void = () => {}
  onToggleRecording: () => void = () => {}
  onSaveRecording: () => void = () => {}
  onSetRecordName: (value: string) => void = () => {}
  onPlayRecording: (file: string) => void = () => {}
  onLoadRecording: (file: string, name: string) => void = () => {}
  onShareRecording: (rec: RecordingEntry, idx: number) => void = () => {}
  onDeleteRecording: (file: string) => void = () => {}
  onToggleScreenVideo: () => void = () => {}
  onSaveScreenVideoToGallery: (result: SaveButtonOnClickResult) => void = () => {}
  onShareScreenVideo: () => void = () => {}
  onSaveScreenVideoAs: () => void = () => {}
  onSetVideoFps: (value: string) => void = () => {}
  onSetVideoDuration: (value: string) => void = () => {}
  onToggleVideoRecording: () => void = () => {}
  onShareVideoArchive: () => void = () => {}
  onExportVideoArchive: () => void = () => {}

  build() {
    Scroll() {
      Column({ space: 10 }) {
        GuideLibrary({
          sessionActive: this.guideSessionActive,
          onStartGuide: (id: string) => { this.onStartGuide(id) }
        })
        // ===== 脚本播放列表 =====
        Text(I18n.t('i0123')).fontSize(15).fontColor(this.c.text).width('100%').margin({ top: 4 })
        Row({ space: 8 }) {
          Button(I18n.t('i0252')).fontSize(11).fontColor(this.c.onAccent).backgroundColor(this.c.error)
            .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
            .onClick(() => { this.onStopPlayback() })
          Button(I18n.t('btn_import_script')).fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
            .enabled(!this.scriptStore.scriptImporting)
            .onClick(() => { this.onImportScript() })
          if (this.scriptStore.scriptImporting) {
            LoadingProgress().width(16).height(16).color(this.c.accent)
          }
        }.width('100%').padding({ left: 6, right: 6 })
        if (this.scriptStore.scriptList.length === 0) {
          Text(I18n.t('msg_no_scripts')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 6 })
        }
        if (this.scriptStore.scriptLaunching) {
          Row({ space: 6 }) {
            LoadingProgress().width(16).height(16).color(this.c.accent)
            Text(I18n.format('script_starting_named', [scriptZh(this.scriptStore.scriptLaunchingName)])).fontSize(10).fontColor(this.c.sub)
          }.width('100%').padding({ left: 6, right: 6, bottom: 2 })
        }
        Column({ space: 2 }) {
            ForEach(this.scriptStore.scriptList, (s: string) => {
              Column({ space: 0 }) {
                Row() {
                  Text(scriptZh(s)).fontSize(11).fontColor(this.c.text)
                    .fontWeight(FontWeight.Medium).layoutWeight(1)
                  Polygon({ width: 9, height: 10 })
                    .points([[0, 0], [9, 5], [0, 10]])
                    .fill(this.c.dockActive)
                }
                .height(28).width('100%').padding({ left: 10, right: 10 })
                if (scriptDesc(s)) {
                  Text(scriptDesc(s))
                    .fontSize(10).fontColor(this.c.sub).width('100%')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 10, right: 10, bottom: 3 })
                }
                if (this.scriptMetaLine(s).length > 0) {
                  Text(this.scriptMetaLine(s))
                    .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 10, right: 10, bottom: 3 })
                }
                if (this.scriptSourceLine(s).length > 0) {
                  Text(this.scriptSourceLine(s)).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 10, right: 10, bottom: 3 })
                }
            }
            .width('100%')
            .backgroundColor(this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL)
            .opacity(this.scriptStore.scriptLaunching && this.scriptStore.scriptLaunchingName !== s ? 0.55 : 1)
            .hitTestBehavior(HitTestMode.Default)
            .onClick(() => { this.onPlayScript(s) })
          }, (s: string, index: number) => s)
        }
          .id('scripts-list-scroll')
          .width('100%')
          .hitTestBehavior(HitTestMode.Default)

        Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 6, bottom: 6 })

        // ===== 录制操作 =====
        Text(I18n.t('c_script_record')).fontSize(15).fontColor(this.c.text).width('100%').margin({ top: 4 })
        Text(I18n.t('m_script_record_desc'))
          .fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 4, right: 4 })

        Row({ space: 10 }) {
          Button(this.tools.recording ? I18n.t('btn_stop_recording') : I18n.t('btn_start_recording'))
            .fontSize(13).fontColor(this.c.textStrong).backgroundColor(this.tools.recording ? this.c.error : this.c.actionPositive)
            .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 16, right: 16 })
            .onClick(() => { this.onToggleRecording() })
          if (this.tools.recording) {
            Text(I18n.t('c_recording')).fontSize(12).fontColor(this.c.errorText)
          }
        }.width('100%').padding({ left: 6, right: 6 })

        Text(I18n.format('script_recorded_commands', [this.scriptStore.recordCount.toString()]) + (this.scriptStore.recordMsg.length > 0 ? ' · ' + this.scriptStore.recordMsg : ''))
          .fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 6, right: 6 })

        Row({ space: 8 }) {
          TextInput({ placeholder: I18n.t('c_record_name_hint'), text: this.scriptStore.recordName })
            .fontSize(12).fontColor(this.c.text)
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).layoutWeight(1).height(36)
            .onChange((v: string) => { this.onSetRecordName(v) })
          Button(I18n.t('btn_save_record'))
            .fontSize(12).fontColor(this.scriptStore.recordCount > 0 ? this.c.onAccent : this.c.text).backgroundColor(this.scriptStore.recordCount > 0 ? this.c.accent : this.c.disabled)
            .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 12, right: 12 })
            .enabled(this.scriptStore.recordCount > 0)
            .onClick(() => { this.onSaveRecording() })
        }.width('100%').padding({ left: 6, right: 6 })

        Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 6, bottom: 6 })

        Text(I18n.t('c_saved_recordings')).fontSize(13).fontColor(this.c.text).width('100%').padding({ left: 6 })
        if (this.scriptStore.recordings.length === 0) {
          Text(I18n.t('m_no_recordings')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 6 })
        }
        ForEach(this.scriptStore.recordings, (rec: RecordingEntry, idx: number) => {
          Column({ space: 4 }) {
            Row({ space: 8 }) {
              Column() {
                Text(rec.name).fontSize(13).fontColor(this.c.text).width('100%')
                Text((rec.created.length > 0 ? rec.created + ' · ' : '') + rec.count + ' 条命令')
                  .fontSize(10).fontColor(this.c.sub).width('100%')
              }.layoutWeight(1)
              Button(I18n.t('btn_playback'))
                .fontSize(11).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 12, right: 12 })
                .onClick(() => { this.onPlayRecording(rec.file) })
              Button('加载')
                .fontSize(11).fontColor(this.c.textStrong).backgroundColor(this.c.actionLoad)
                .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 12, right: 12 })
                .onClick(() => { this.onLoadRecording(rec.file, rec.name) })
              if ((rec.path ?? '').length > 0) {
                Button('分享')
                  .id('recording-share-' + idx.toString())
                  .fontSize(11).fontColor(this.c.textStrong).backgroundColor(this.c.actionShare)
                  .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
                  .onClick(() => {
                    this.onShareRecording(rec, idx)
                  })
              }
              Button(I18n.t('btn_delete'))
                .fontSize(11).fontColor(this.c.textStrong).backgroundColor(this.c.error)
                .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 12, right: 12 })
                .onClick(() => { this.onDeleteRecording(rec.file) })
            }.width('100%')
          }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        }, (item: RecordingEntry, idx: number) => item.file)

        // ===== 直接屏幕录制 MP4 =====
        Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 6, bottom: 6 })
        Text('屏幕视频（MP4）').fontSize(13).fontColor(this.c.text).width('100%').padding({ left: 6 })
        Text('录制屏幕中的星图与交互界面；系统会在开始前显示录屏授权确认。默认不录麦克风。')
          .fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 6, right: 6 }).maxLines(3)
        Row({ space: 8 }) {
          Button(this.scriptStore.screenVideoRecording ? '停止并生成 MP4' : '开始录制 MP4')
            .fontSize(12).fontColor(this.c.textStrong)
            .backgroundColor(this.scriptStore.screenVideoRecording ? this.c.error : this.c.actionPositive)
            .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 14, right: 14 })
            .onClick(() => {
              this.onToggleScreenVideo()
            })
          if (this.scriptStore.screenCaptureFinalizing) {
            LoadingProgress().width(18).height(18).color(this.c.accent)
          }
          Text(this.scriptStore.screenVideoStatus).fontSize(10)
            .fontColor(this.scriptStore.screenVideoRecording ? this.c.errorText : this.c.sub)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%').padding({ left: 6, right: 6 })
        if (this.scriptStore.screenVideoBytes > 0 && this.scriptStore.screenVideoPath.length > 0) {
          Row({ space: 8 }) {
            SaveButton({ icon: SaveIconStyle.LINES, text: SaveDescription.SAVE_TO_GALLERY,
              buttonType: ButtonType.Capsule })
              .height(34)
              .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
                this.onSaveScreenVideoToGallery(result)
              })
            Button('分享')
              .id('screen-video-share')
              .fontSize(11).fontColor(this.c.textStrong).backgroundColor(this.c.actionShare)
              .borderRadius(UI_RADIUS_CONTROL).height(34).padding({ left: 12, right: 12 })
              .onClick(() => {
                this.onShareScreenVideo()
              })
            Button('另存为')
              .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(34).padding({ left: 12, right: 12 })
              .onClick(() => { this.onSaveScreenVideoAs() })
          }.width('100%').padding({ left: 6, right: 6 })
        }

        // ===== 视频录制（帧序列方案，纯星图高质量导出）=====
        Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 6, bottom: 6 })
        Text(I18n.t('c_video_frames')).fontSize(13).fontColor(this.c.text).width('100%').padding({ left: 6 })
        Text(I18n.t('m_video_frames_desc'))
          .fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 4, right: 4 })

        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(I18n.t('c_fps')).fontSize(10).fontColor(this.c.sub)
            TextInput({ placeholder: '1', text: this.scriptStore.videoFps })
              .fontSize(12).fontColor(this.c.text)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).width(72).height(34)
              .onChange((v: string) => { this.onSetVideoFps(v) })
          }.width(72)
          Column({ space: 2 }) {
            Text(I18n.t('c_duration_sec')).fontSize(10).fontColor(this.c.sub)
            TextInput({ placeholder: '5', text: this.scriptStore.videoDuration })
              .fontSize(12).fontColor(this.c.text)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).width(72).height(34)
              .onChange((v: string) => { this.onSetVideoDuration(v) })
          }.width(72)
          Button(this.scriptStore.videoRecording ? '停止录制' : '开始录制')
            .fontSize(13).fontColor(this.c.textStrong).backgroundColor(this.scriptStore.videoRecording ? this.c.error : this.c.actionPositive)
            .borderRadius(UI_RADIUS_CONTROL).height(36).layoutWeight(1).padding({ left: 16, right: 16 })
            .onClick(() => { this.onToggleVideoRecording() })
        }.width('100%').padding({ left: 6, right: 6 })

        if (this.scriptStore.videoRecording || this.scriptStore.videoFrameCount > 0) {
          Row({ space: 10 }) {
            if (this.scriptStore.videoRecording) {
              Text(I18n.t('c_recording')).fontSize(12).fontColor(this.c.errorText)
            }
            Text(I18n.t('c_captured') + ' ' + this.scriptStore.videoFrameCount + ' / ' + this.scriptStore.videoMaxFrames + ' ' + I18n.t('c_frames'))
              .fontSize(11).fontColor(this.c.sub)
            if (this.scriptStore.videoFailedFrames > 0) {
              Text('失败 ' + this.scriptStore.videoFailedFrames).fontSize(10).fontColor(this.c.warning)
            }
          }.width('100%').padding({ left: 6, right: 6 })
        }
        if (this.scriptStore.videoDir.length > 0) {
          Text('存放目录：' + this.scriptStore.videoDir)
            .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 6, right: 6 })
        }
        if (this.scriptStore.videoArchivePath.length > 0) {
          Row({ space: 8 }) {
            Button('分享帧包')
              .id('video-frames-share')
              .fontSize(11).fontColor(this.c.textStrong).backgroundColor(this.c.actionShare)
              .borderRadius(UI_RADIUS_CONTROL).height(34).padding({ left: 12, right: 12 })
              .onClick(() => {
                this.onShareVideoArchive()
              })
            Button('导出 ZIP')
              .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(34).padding({ left: 12, right: 12 })
              .onClick(() => { this.onExportVideoArchive() })
          }.width('100%').padding({ left: 6, right: 6, bottom: 8 })
        }
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
