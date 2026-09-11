// 让 Node 能解析领域层的「无后缀相对导入」（ArkTS 约定）。
// 仅用于主机侧 L1 测试：specifier 无扩展名时优先尝试 <specifier>.ts。
export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith('.') && !/\.[cm]?[jt]s$/.test(specifier)) {
    try {
      return await nextResolve(specifier + '.ts', context);
    } catch {
      // 落到默认解析（目录、.mjs 等）
    }
  }
  return nextResolve(specifier, context);
}
