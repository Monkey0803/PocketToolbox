import { ToolPalette } from '../../model/ToolPalette';

/**
 * 桌面「常用工具」服务卡片（ArkTS 卡片页）。
 *
 * 与工具页不同，卡片页有**三处硬约束**，改动前请先看 `AGENTS.md` 的「服务卡片」一节：
 * ① 只能用 ArkTS 卡片支持的组件白名单（`Row/Column/Text/Blank` 等；**不能用** `SymbolGlyph`、`Grid`、
 *   `Scroll`、`Select`、`Search`、`TextInput`），所以这里用「文字 + 色块」表达工具，而不是图标；
 * ② 数据只能经 `formBindingData` → `@LocalStorageProp` 下发（`FormBindingData` 会被序列化成字符串，
 *   因此 `tools` 是 JSON 文本、`columns` 按字符串解析）；卡片页不读本地存储；
 * ③ 装饰器只能用 V1（`@Entry`/`@Component`/`@LocalStorageProp`）——ArkUI V2 没有卡片数据绑定通道，
 *   这是工程内唯一允许写 V1 的地方。
 *
 * 显示哪些工具、每格什么文字、排几列全部由 `model/WidgetCards.ets` 算好后下发，本文件不含业务规则。
 */

/** 下发给卡片的一格（与 `model/WidgetCards.ets` 的 `QuickToolTile` 字段一致）。 */
class CardTile {
  id: string = '';
  label: string = '';
}

// 卡片数据由系统注入到 entry 的 LocalStorage，再由 @LocalStorageProp 绑到上面各字段。
let storage: LocalStorage = new LocalStorage();

@Entry(storage)
@Component
struct QuickToolsCard {
  @LocalStorageProp('title') title: string = '工具';
  @LocalStorageProp('tools') toolsJson: string = '[]';
  @LocalStorageProp('columns') columnsRaw: string = '2';

  /** 解析下发的工具列表；内容异常时返回空数组（宁可少几格，不能崩）。 */
  private tiles(): CardTile[] {
    try {
      const parsed: CardTile[] = JSON.parse(this.toolsJson) as CardTile[];
      if (!Array.isArray(parsed)) { return []; }
      return parsed.filter((tile: CardTile): boolean => tile.id.length > 0);
    } catch (_) {
      return [];
    }
  }

  /** 列数只认 2 / 4，其它值按 2 列。 */
  private columns(): number {
    return Number(this.columnsRaw) === 4 ? 4 : 2;
  }

  /** 按列数把工具切成若干行，交给 ForEach 逐行渲染。 */
  private rows(): CardTile[][] {
    const columns: number = this.columns();
    const tiles: CardTile[] = this.tiles();
    const rows: CardTile[][] = [];
    for (let index: number = 0; index < tiles.length; index += columns) {
      rows.push(tiles.slice(index, index + columns));
    }
    return rows;
  }

  /** 格子底色按下标循环取主题浅色调（不按工具做语义映射，避免把工具登记表的资源绑带进卡片）。 */
  private tintFor(index: number): Resource {
    const tints: Resource[] = [ToolPalette.tintBlue, ToolPalette.tintRose, ToolPalette.tintTeal,
      ToolPalette.tintGreen, ToolPalette.tintAmber, ToolPalette.tintPurple, ToolPalette.tintIndigo,
      ToolPalette.tintMint, ToolPalette.tintSky];
    return tints[index % tints.length];
  }

  private tileWidth(): string {
    return this.columns() === 4 ? '23%' : '48%';
  }

  /** 点格子：拉起应用并直达该工具（want 参数 `tool` 由 EntryAbility/StartupIntent 消费）。 */
  private openTool(id: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { tool: id }
    });
  }

  /** 点标题：只打开应用首页。 */
  private openApp(): void {
    postCardAction(this, { action: 'router', abilityName: 'EntryAbility' });
  }

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ToolPalette.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .onClick(() => { this.openApp(); })

      ForEach(this.rows(), (row: CardTile[], rowIndex: number) => {
        Row() {
          ForEach(row, (tile: CardTile, index: number) => {
            Column() {
              Text(tile.label)
                .fontSize(13)
                .fontColor(ToolPalette.textPrimary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .width(this.tileWidth())
            .height('100%')
            .padding(6)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.tintFor(rowIndex * this.columns() + index))
            .borderRadius(10)
            .onClick(() => { this.openTool(tile.id); })
          }, (tile: CardTile): string => tile.id)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.SpaceBetween)
      }, (row: CardTile[], rowIndex: number): string => 'row' + rowIndex)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ToolPalette.background)
  }
}
