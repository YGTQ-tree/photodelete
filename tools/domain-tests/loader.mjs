// L1 测试的 Node 加载入口：
//   node --import ./tools/domain-tests/loader.mjs --test tools/domain-tests/*.test.ts
import { register } from 'node:module';

register(new URL('./resolve-ts.mjs', import.meta.url));
