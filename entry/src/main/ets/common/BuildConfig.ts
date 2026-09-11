/**
 * 构建期开关。纯 TS：禁止 import 任何 @kit.* / @ohos.*。
 *
 * ⚠️ 发布前必读（见 docs/RELEASE.md §6）：
 *   `DEVTOOLS_ENABLED` 控制首页上的开发入口（自检结果、演示数据生成、相机探针）。
 *   置为 `false` 后这些入口在**运行期不可达**，用户不会误点「生成演示数据」把假照片写进真实数据里。
 *
 *   注意：ArkTS/hvigor **不做跨模块 tree-shaking**（未验证），所以置 false **不会**让
 *   `devtools/` 的代码从包里消失，只是不可达。若要让代码也消失，需要连同
 *   `pages/Index.ets` 里对 `devtools/*` 的 import 与 `pages/CameraProbePage.ets` 一起删除，
 *   并把它从 `main_pages.json` 摘掉（`scripts/check-profile.mjs` 的页面注册检查会提醒你）。
 */

export const DEVTOOLS_ENABLED: boolean = false;
