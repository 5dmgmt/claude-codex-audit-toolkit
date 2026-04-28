# 06. dev / local 環境 auth bypass の 4 原則 — Adapter: Next.js + 自前 auth

> **Adapter 階層**: 本ドキュメントは **Next.js + 自前 auth (NextAuth / Supabase Auth / Auth0 等の専用ライブラリを使わない実装)** を前提とした実装パターンです。Rails / Django / Go 等は別 adapter として整備すべき領域 ([CONTRIBUTING.md](../CONTRIBUTING.md) 参照)。**4 原則の概念 (二重ガード / read-only 限定 / 最低権限 + RBAC / null 比較統一)** はフレームワーク中立で、実装パターンが Next.js 固有です。

## 位置づけ

Codex 監査で「Phase 8 まで通すために dev 環境で auth bypass を入れたら、Codex から P1×複数 / P2×多数の指摘を食らった」という事案 (SIFT 12 ラウンド目) から抽出した、**最初から織り込まないと爆発する** 4 つの設計原則。

## なぜ普通の auth bypass は危ないか

「dev 環境だけ login をスキップする」は一見簡単そうですが、実装ミスが本番に波及すると **認証ゼロのシステム** ができあがります。Codex は本番リスクを最大限警戒するので、bypass 実装の **隙を全部指摘** してきます。

最初から 4 原則を織り込めば、bypass を入れつつ bypass 関連の追加修正ラウンドを避けやすくなります (アプリ固有の mutation 面や Codex の挙動差により完全な「指摘ゼロ」を保証するものではない)。

## 4 原則

### 原則 1. 二重ガード (`NODE_ENV` + opt-in env) + 起動時 fail-closed

`NODE_ENV` だけで分岐すると、本番でうっかり `NODE_ENV=development` になっただけで bypass が発動します。**opt-in 専用の env 変数** との AND を必須に。さらに、両方が production / preview / CI で同時に true になってしまった場合に **起動時 fail-closed (throw)** するガードを足します:

```ts
// アプリ起動時 (server entry / instrumentation.ts 等)
const bypass = process.env.ENABLE_DEV_AUTH_BYPASS === "true";
const isProd =
  process.env.VERCEL_ENV === "production" ||
  process.env.VERCEL_ENV === "preview" ||
  process.env.NODE_ENV === "production" ||
  process.env.CI === "true";
if (bypass && isProd) {
  throw new Error(
    "FATAL: ENABLE_DEV_AUTH_BYPASS=true on production/preview/CI. Aborting boot."
  );
}

// ランタイム判定
if (
  process.env.NODE_ENV === "development" &&
  process.env.ENABLE_DEV_AUTH_BYPASS === "true"
) {
  return mockUser;
}
```

NG (起動時 fail-closed なし — env 設定ミスで bypass が production で active 化する経路が残る):

```ts
// NG
if (process.env.NODE_ENV === "development") return mockUser;
```

`ENABLE_DEV_AUTH_BYPASS` は `.env.local` のみに置き、`.env.production` には絶対に書かない。Vercel の Production / Preview env にも登録しない。さらに上記 fail-closed ガードで「起動時に env を確認して production で bypass true なら die」する二重防衛を実装する。

### 原則 2. read-only 限定 (write は 403/405 強制 + negative test)

bypass user は **read-only 操作のみ許可**、write 操作は **必ず 403 (Forbidden) または 405 (Method Not Allowed) を返す** ようにします。no-op (silent success) は禁止 — 成功に見えると検出できません:

```ts
// API endpoint
export async function POST(req: Request) {
  const user = await getCurrentUser();
  if (user === null) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  if (user.isBypass) {
    return Response.json(
      { error: "bypass user is read-only" },
      { status: 403 }
    );
  }
  // 実際の write 処理
}
```

検証時の必須要件:
- ランブック側: bypass user で代表的な write endpoint を 1-2 件叩き、**403 が返ることを negative test として記録** する (read-only journey をスキップするだけでは検証になっていない)
- 通常の read-only journey とは別に、`POST /api/foo` に明示的に bypass user で投げて 403 を assert する step を追加

### 原則 3. systemRole=USER 固定 + server-side RBAC

bypass user の role を **常に最低権限の `USER`** に固定します。**UI 側で隠すだけでなく、admin 系の loader / route handler / server action / API endpoint で server-side に RBAC を必須化** します — UI を隠しても、API を直接叩けばデータが漏れます:

```ts
const mockUser: User = {
  id: "dev-bypass-user",
  email: "dev@localhost",
  systemRole: "USER", // 必ず最低権限
  isBypass: true,
};
```

```tsx
// admin 画面 (UI 側、表示防止)
// systemRole で正面から弾く (bypass user は systemRole=USER 固定なのでここで弾かれる)
if (user.systemRole !== "ADMIN") {
  if (user.isBypass) {
    return <div>bypass user は admin 機能を使えません</div>;
  }
  return <div>権限がありません</div>;
}
```

```ts
// admin route handler / server action / API (server-side RBAC、必須)
export async function GET(req: Request) {
  const user = await getCurrentUser();
  if (user === null || user.systemRole !== "ADMIN") {
    return Response.json({ error: "forbidden" }, { status: 403 });
  }
  // admin データ返却
}
```

UI 側だけだと、bypass user が `/api/admin/users` 等を直接叩いた瞬間に admin データが流れます。**server-side RBAC が真の防衛線**。

### 原則 4. `if (!userId)` 禁止 (型と比較式を段階で揃える)

旧型で `userId` が `0` (number) または `""` (空文字) を取り得る場合、`if (!userId)` は両方を anonymous 扱いに倒します。bypass user の id がこれらの値を持つと意図せず認証スキップが起きる事故になります。

正しいやり方は **型と比較式を段階で揃える** ことです:

```ts
// (1) 型定義 — 空文字を構造的に排除した branded 型
type UserId = string & { readonly __brand: "UserId" };
const makeUserId = (s: string): UserId => {
  if (s.length === 0) throw new Error("UserId cannot be empty");
  return s as UserId;
};

// User 型と mock user の両方で UserId を使う
interface User {
  id: UserId;
  email: string;
  systemRole: "USER" | "ADMIN";
  isBypass: boolean;
}
const mockUser: User = {
  id: makeUserId("dev-bypass-user"),
  email: "dev@localhost",
  systemRole: "USER",
  isBypass: true,
};

// (2) 入力境界 (cookie / header / DB result 等、型が UserId | null | undefined)
//     → == null で null と undefined を一括判定 (推奨)
function rawUserIdFromCookie(req: Request): UserId | null | undefined {
  const raw = req.cookies.get("userId")?.value;
  return raw && raw.length > 0 ? makeUserId(raw) : null;
}
const userId = rawUserIdFromCookie(req);
if (userId == null) return redirect("/login");

// (3) 正規化後の内部型 (UserId | null) → === null のみ
function getUserById(userId: UserId | null): User | null {
  if (userId === null) return null;
  // ...
}

// NG (0 / "" を unset と誤判定 / type-narrowing が効かない)
if (!userId) return redirect("/login");
```

ポイント:
- **型レベルで空文字を排除** (`makeUserId` factory を強制) → 実行時に空文字が混入する経路を物理的に塞ぐ
- **入力境界では `== null`** → `null` と `undefined` を一括で判定。strict TS でも型 narrow が効く
- **正規化後の内部型では `=== null`** → strict TS で `=== undefined` を書くと no-overlap 警告が出る (型上 undefined を取らないため)

これは bypass 限定の話ではなく **全 codebase に適用** すべきルール。`!userId` の grep がゼロになるまで置換する。

## 実装パターン (Next.js + 自前 auth)

```ts
// lib/auth-guard.ts (起動時 fail-closed)
export function assertDevAuthBypassNotEnabledInProd(): void {
  const bypass = process.env.ENABLE_DEV_AUTH_BYPASS === "true";
  const isProd =
    process.env.VERCEL_ENV === "production" ||
    process.env.VERCEL_ENV === "preview" ||
    process.env.NODE_ENV === "production" ||
    process.env.CI === "true";
  if (bypass && isProd) {
    throw new Error(
      "FATAL: ENABLE_DEV_AUTH_BYPASS=true on production/preview/CI. Aborting boot."
    );
  }
}

// instrumentation.ts (Next.js 起動時に必ず呼ぶ)
import { assertDevAuthBypassNotEnabledInProd } from "@/lib/auth-guard";
export function register() {
  assertDevAuthBypassNotEnabledInProd();
}

// lib/auth.ts
export async function getCurrentUser(): Promise<User | null> {
  // 1. 通常の session lookup
  const session = await getSession();
  if (session?.userId !== null && session?.userId !== undefined) {
    return await loadUser(session.userId);
  }

  // 2. dev bypass (二重ガード)
  if (
    process.env.NODE_ENV === "development" &&
    process.env.ENABLE_DEV_AUTH_BYPASS === "true"
  ) {
    return {
      id: "dev-bypass-user",
      email: "dev@localhost",
      systemRole: "USER",
      isBypass: true,
    };
  }

  // 3. 認証なし
  return null;
}
```

```ts
// app/api/foo/route.ts
export async function POST(req: Request) {
  const user = await getCurrentUser();
  if (user === null) return Response.json({ error: "unauthorized" }, { status: 401 });
  if (user.isBypass) return Response.json({ error: "bypass is read-only" }, { status: 403 });

  // write 処理
}
```

## ランブック側の記述

監査ランブックには bypass の使い方を明記:

```markdown
### dev bypass の有効化

1. `.env.local` に `ENABLE_DEV_AUTH_BYPASS=true` を追記
2. `npm run dev` で起動
3. read-only journey: 通常の閲覧操作で 200 を確認
4. **write 防御の negative test (必須)**: 代表的な write endpoint (POST / PUT / PATCH / DELETE) を bypass user で叩き、403 が返ることを assert する。例:
   ```bash
   HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
     -X POST http://localhost:3001/api/foo)
   [ "$HTTP_CODE" = "403" ] || { echo "FAIL: expected 403, got $HTTP_CODE"; exit 1; }
   ```
   未定義 method の 405 は別枠。read-only journey をスキップするだけでは不十分で、**bypass user で write が 403 になることを実走で確認** する必要がある (no-op = silent success だと検証にならない)
5. テスト完了後、`.env.local` から該当行を削除
```

## チェックリスト (証跡付き)

dev bypass を実装する前に、各項目を証跡付きで確認:

- [ ] **二重ガード**: `getCurrentUser` 等の bypass 経路で `NODE_ENV === "development" && ENABLE_DEV_AUTH_BYPASS === "true"` を AND 必須 / 証跡: `git grep 'ENABLE_DEV_AUTH_BYPASS'` で参照箇所を確認
- [ ] **起動時 fail-closed**: server entry / instrumentation で `bypass && (VERCEL_ENV === "production"|"preview" || NODE_ENV === "production" || CI === "true")` で throw / 証跡: `git grep -n 'ENABLE_DEV_AUTH_BYPASS' src/server/instrumentation*` 等
- [ ] **本番 env 未登録**: `vercel env ls production` / `vercel env ls preview` で `ENABLE_DEV_AUTH_BYPASS` が出ないこと / 証跡: 出力スクリーンショット
- [ ] **write は 403**: 全 mutation 境界 (POST / PUT / PATCH / DELETE / server action) で `user.isBypass` → 403 / 証跡: `git grep -nE '(export async function (POST|PUT|PATCH|DELETE))' app/api/` を一覧化、各箇所で 403 分岐を確認
- [ ] **write negative test 実走**: bypass user で代表 write endpoint に `curl -X POST` し 403 を確認 / 証跡: `curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:PORT/api/foo` の出力
- [ ] **mock user role**: `systemRole: "USER"` 固定 / 証跡: `git grep -n 'isBypass: true' lib/auth*` の周辺
- [ ] **admin server-side RBAC**: admin 系 route / API で `user.systemRole !== "ADMIN"` → 403 / 証跡: admin route inventory + 各箇所の RBAC チェック
- [ ] **`==`/`===` null 統一**: `git grep -nE 'if \(![^)=]+(Id|Token|Session)\)'` で `if (!userId)` 系がゼロ
- [ ] **runbook 明記**: bypass 有効化手順 + read-only journey + 403 negative test step が記載

9 項目全部 ✅ + 証跡付きで Codex 監査に投入。これにより bypass 関連の追加修正ラウンドを避けやすくなります (R1 投入前に主要リスクを潰せる)。

## 関連文書

- [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — 5 つの決定的対策
- [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — 環境系 lint 14 項目
