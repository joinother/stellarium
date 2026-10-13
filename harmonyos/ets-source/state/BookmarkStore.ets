import hilog from '@ohos.hilog'
import { BookmarkItem, BookmarkRaw, BookmarksResponse } from '../pages/MainWindowModels'
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'

// 宿主 → BookmarkStore 的注入：store 不得 import NAPI/UI 上下文，
// 故 Preferences 读写与 UI 提示职责整体经 hooks 提供。
export interface BookmarkHostHooks {
  // 读 Preferences 'bookmarks' 原始 JSON（无则 '[]'）；宿主用 @ohos.data.preferences 实现。
  readBookmarksStorage(): Promise<string>
  // 持久化当前列表到 Preferences；宿主实现。
  saveBookmarksToStorage(): void
  // 书签增删跳转的 UI 提示经此回注（store 不触碰 UI）。
  flashHint(text: ResourceStr): void
}

// 书签域状态：面板（BookmarkPanel）以 @ObjectLink 订阅；本 store 自持加载 / 增删跳转命令，
// Preferences 持久化经 hooks。
@Observed
export class BookmarkStore {
  list: BookmarkItem[] = []
  loading: boolean = false
  draftName: string = ''

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器不使用请求序号（无并发抑制需求）；seq 预留以保持统一约定。
  private seq: number = 0
  private hooks: BookmarkHostHooks | null = null

  attachPort(port: CommandPort): void {
    this.port = port
  }

  attachHooks(hooks: BookmarkHostHooks): void {
    this.hooks = hooks
  }

  // 桥拉取书签列表，回包后由宿主持久化。
  loadBookmarks(): void {
    const hooks = this.hooks
    const port = this.port
    if (hooks === null || port === null) {
      return
    }
    this.loading = true
    port.requestWhenReady('getBookmarks', '', (r: StellariumBridgeResponse) => {
      const resp = r as BookmarksResponse
      const list = resp.items ?? []
      this.list = list.map((b: BookmarkRaw): BookmarkItem => ({
        id: b.id ?? '',
        name: b.name ?? I18n.t('bookmark_fallback'),
        fov: b.fov ?? 60,
        object: b.object ?? '',
      }))
      this.loading = false
      hooks.saveBookmarksToStorage()
    })
  }

  // 首次启动从 Preferences 载入书签（经 hooks，store 不 import NAPI/UI）。
  async loadBookmarksFromStorage(): Promise<void> {
    const hooks = this.hooks
    try {
      const jsonStr: string = hooks !== null ? await hooks.readBookmarksStorage() : '[]'
      const parsed: BookmarkItem[] = JSON.parse(jsonStr)
      if (parsed.length > 0) {
        this.list = parsed
      }
    } catch (e) {
      hilog.warn(0xD002, 'Stellarium', 'load bookmarks failed: %{public}s', String(e))
    }
  }

  // 保存当前视图为书签；回包后提示并就地刷新列表。
  addCurrentBookmark(): void {
    const hooks = this.hooks
    const port = this.port
    if (hooks === null || port === null) {
      return
    }
    const name = this.draftName.trim()
    port.requestWhenReady('addBookmark', name, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.draftName = ''
        hooks.flashHint(I18n.t('msg_bookmark_saved'))
        this.loadBookmarks()
      } else {
        hooks.flashHint(I18n.t('msg_bookmark_save_failed'))
      }
    })
  }

  // 跳转到书签。
  gotoBookmark(id: string): void {
    const hooks = this.hooks
    const port = this.port
    if (hooks === null || port === null) {
      return
    }
    port.requestInteractive('gotoBookmark', id, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        hooks.flashHint(I18n.t('msg_navigated'))
      } else {
        hooks.flashHint(I18n.t('msg_navigation_failed'))
      }
    })
  }

  // 删除书签；成功后提示并刷新列表。
  deleteBookmark(id: string): void {
    const hooks = this.hooks
    const port = this.port
    if (hooks === null || port === null) {
      return
    }
    port.requestWhenReady('deleteBookmark', id, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        hooks.flashHint(I18n.t('msg_bookmark_deleted'))
        this.loadBookmarks()
      }
    })
  }
}
