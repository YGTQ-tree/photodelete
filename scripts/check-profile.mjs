#!/usr/bin/env node
/**
 * build-profile.json5 / oh-package.json5 / hvigor-config.json5 配置合规检查。
 *
 * 为什么需要它：HarmonyOS 的版本字段规则很细（HarmonyOS 模式下必须是
 * "x.y.z(api)" 字符串、compatible ≤ target ≤ compile、modelVersion 两处一致），
 * 而且升级到 API 26 时这些规则最容易在多人/多 product 下被写歪。
 * 让机器记住规则，而不是让人记住。
 *
 * 用法： node scripts/check-profile.mjs
 * 退出码：0 = 全部合规；1 = 有不合规项
 */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const problems = [];
const notes = [];

function readJson5(relPath) {
  const raw = readFileSync(resolve(root, relPath), 'utf8');
  const stripped = raw
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1')
    .replace(/,\s*([}\]])/g, '$1');
  return JSON.parse(stripped);
}

function apiOf(value) {
  const m = /^(\d+)\.(\d+)\.(\d+)\((\d+)\)$/.exec(String(value));
  return m ? Number(m[4]) : null;
}

function checkVersionField(label, value, { required = true } = {}) {
  if (value === undefined || value === null) {
    if (required) problems.push(`${label} 缺失`);
    return null;
  }
  if (typeof value !== 'string') {
    problems.push(`${label} 必须是字符串（HarmonyOS 模式要求 "x.y.z(api)" 形式），当前是 ${typeof value}: ${value}`);
    return null;
  }
  const api = apiOf(value);
  if (api === null) {
    problems.push(`${label} 格式不合法：${value}（应为 "6.0.2(22)" 形式）`);
  }
  return api;
}

// ---------- build-profile.json5 ----------
const profile = readJson5('build-profile.json5');
const products = profile?.app?.products ?? [];
if (products.length === 0) {
  problems.push('build-profile.json5: app.products 为空（必须至少有一个 product）');
}
const productNames = new Set();
for (const product of products) {
  const name = product.name;
  if (!name) {
    problems.push('build-profile.json5: 存在没有 name 的 product');
    continue;
  }
  productNames.add(name);

  const compileApi = checkVersionField(`${name}.compileSdkVersion`, product.compileSdkVersion);
  const compatibleApi = checkVersionField(`${name}.compatibleSdkVersion`, product.compatibleSdkVersion);
  const targetApi = checkVersionField(`${name}.targetSdkVersion`, product.targetSdkVersion, { required: false });

  if (compatibleApi !== null && targetApi !== null && compatibleApi > targetApi) {
    problems.push(`${name}: compatibleSdkVersion(${compatibleApi}) 不能高于 targetSdkVersion(${targetApi})`);
  }
  if (targetApi !== null && compileApi !== null && targetApi > compileApi) {
    problems.push(`${name}: targetSdkVersion(${targetApi}) 不能高于 compileSdkVersion(${compileApi})`);
  }
  if (compatibleApi !== null && compileApi !== null && compatibleApi > compileApi) {
    problems.push(`${name}: compatibleSdkVersion(${compatibleApi}) 不能高于 compileSdkVersion(${compileApi})`);
  }

  const runtimeOS = product.runtimeOS;
  if (runtimeOS && runtimeOS !== 'HarmonyOS' && runtimeOS !== 'OpenHarmony') {
    problems.push(`${name}: runtimeOS 只能是 HarmonyOS 或 OpenHarmony，当前 ${runtimeOS}`);
  }
  if (runtimeOS === 'HarmonyOS' && typeof product.compileSdkVersion === 'number') {
    problems.push(`${name}: HarmonyOS 模式下 compileSdkVersion 不能是数字`);
  }
}

if (!productNames.has('default')) {
  problems.push('build-profile.json5: 缺少名为 default 的 product');
}

for (const mod of profile?.modules ?? []) {
  if (!mod.name || !mod.srcPath) {
    problems.push('build-profile.json5: module 必须同时有 name 与 srcPath');
  }
  for (const target of mod.targets ?? []) {
    for (const p of target.applyToProducts ?? []) {
      if (!productNames.has(p)) {
        problems.push(`build-profile.json5: module ${mod.name} 的 target ${target.name} 引用了不存在的 product: ${p}`);
      }
    }
  }
}

// ---------- 页面注册一致性 ----------
// 为什么检查这个：ArkUI 的 @Entry 页面必须在 main_pages.json 里注册，否则要等到运行期
// 才报「找不到页面」；反过来，注册了不存在的文件同样是运行期才炸。
// 这两类问题编译期都发现不了（`router.pushUrl` 的参数只是字符串），所以做静态检查。
const pagesProfilePath = 'entry/src/main/resources/base/profile/main_pages.json';
const pagesDir = 'entry/src/main/ets';
try {
  const pagesProfile = readJson5(pagesProfilePath);
  const registered = pagesProfile?.src ?? [];
  if (registered.length === 0) {
    problems.push(`${pagesProfilePath}: src 为空`);
  }
  for (const p of registered) {
    if (typeof p !== 'string' || !existsSync(resolve(root, pagesDir, `${p}.ets`))) {
      problems.push(`${pagesProfilePath}: 注册的页面不存在 → ${pagesDir}/${p}.ets`);
    }
  }

  // 扫出所有 @Entry 页面，必须都已注册
  const found = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = resolve(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.name.endsWith('.ets')) {
        const text = readFileSync(full, 'utf8');
        if (/^\s*@Entry\b/m.test(text)) {
          found.push(relative(resolve(root, pagesDir), full).replace(/\.ets$/, ''));
        }
      }
    }
  };
  walk(resolve(root, pagesDir));
  for (const page of found) {
    if (!registered.includes(page)) {
      problems.push(`页面未注册：${page}.ets 有 @Entry 但不在 ${pagesProfilePath} 的 src 里`);
    }
  }
  notes.push(`页面注册：${registered.length} 个（@Entry 扫描到 ${found.length} 个）`);
} catch (err) {
  problems.push(`页面注册检查失败：${err.message}`);
}

// ---------- modelVersion 两处一致 ----------
const hvigorConfig = readJson5('hvigor/hvigor-config.json5');
const ohPackage = readJson5('oh-package.json5');
const mvHvigor = hvigorConfig?.modelVersion;
const mvOh = ohPackage?.modelVersion;
if (!mvHvigor || !mvOh) {
  problems.push('modelVersion 缺失：hvigor/hvigor-config.json5 与 oh-package.json5 都必须声明');
} else if (mvHvigor !== mvOh) {
  problems.push(`modelVersion 不一致：hvigor-config.json5=${mvHvigor}，oh-package.json5=${mvOh}`);
} else {
  notes.push(`modelVersion = ${mvHvigor}`);
}

// ---------- 受限权限红线（架构前提，不允许被顺手加回来） ----------
const moduleJson = readJson5('entry/src/main/module.json5');
// 只禁用这两个**受限开放权限**（AGC 基本不批给清理类应用）。
// 注意：ohos.permission.CUSTOM_SCREEN_CAPTURE 是 **user_grant**（用户授权型，平板/2in1 可用），
// 不属于受限开放权限，已按 ADR-005 决策允许使用。
const restricted = ['ohos.permission.READ_IMAGEVIDEO', 'ohos.permission.WRITE_IMAGEVIDEO'];
const declared = (moduleJson?.module?.requestPermissions ?? []).map((p) => p.name);
for (const r of restricted) {
  if (declared.includes(r)) {
    problems.push(`module.json5 申请了受限权限 ${r}（本项目架构前提是禁止申请，见 AGENTS.md 硬约束 2）`);
  }
}
notes.push(`已声明权限：${declared.join(', ') || '无'}`);

// ---------- 输出 ----------
for (const n of notes) console.log(`  [info] ${n}`);
if (problems.length > 0) {
  console.error('工程配置检查未通过：');
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log('工程配置检查通过：版本字段合法、product 引用完整、modelVersion 一致、无受限权限。');
