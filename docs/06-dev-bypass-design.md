# 06. dev / local 環境 auth bypass の 4 原則

## 位置づけ

Codex 監査で「Phase 8 まで通すために dev 環境で auth bypass を入れたら、Codex から P1×複数 / P2×多数の指摘を食らった」という事案 (SIFT 12 ラウンド目) から抽出した、**最初から織り込まないと爆発する** 4 つの設計原則。

## なぜ普通の auth bypass は危ないか

「dev 環境だけ login をスキップする」は一見簡単そうですが、実装ミスが本番に波及すると **認証ゼロのシステム** ができあがります。Codex は本番リスクを最大限警戒するので、bypass 実装の **隙を全部指摘** してきます。

最初から 4 原則を織り込めば、bypass を入れつつ Codex の指摘を回避できます。

## 4 原則

### 原則 1. 二重ガード (`NODE_ENV` + opt-in env)

`NODE_ENV` だけで分岐すると、本番でうっかり `NODE_ENV=development` になっただけで bypass が発動します。**opt-in 専用の env 変数** との AND を必須に:

```ts
// NG (NODE_ENV だけ — 本番事故の温床)
if (process.env.NODE_ENV === "development") {
  return mockUser;
}

// OK (二重ガード)
if (
  process.env.NODE_ENV === "development" &&
  process.env.ENABLE_DEV_AUTH_BYPASS === "true"
) {
  return mockUser;
}
```

`ENABLE_DEV_AUTH_BYPASS` は `.env.local` のみに置き、`.env.production` には絶対に書かない。Vercel の Production env にも登録しない。

### 原則 2. read-only 限定 (write は no-op)

bypass user は **read-only 操作のみ許可**、write 操作は no-op (またはエラー) にします。bypass で write が通ると、ローカル DB / preview DB に bogus データが混入します:

```ts
// API endpoint
export async function POST(req: Request) {
  const user = await getCurrentUser();
  if (user.isBypass) {
    return Response.json(
      { error: "bypass user is read-only" },
      { status: 403 }
    );
  }
  // 実際の write 処理
}
```

ランブック側にも「bypass user では write 操作はテストしない (read-only ジャーニーのみ完走)」と明記。

### 原則 3. systemRole=USER 固定 (admin UI を隠す)

bypass user の role を **常に最低権限の `USER`** に固定します。admin / maintainer 等の UI を bypass で開いてしまうと、Codex から「権限昇格の経路がある」として P1 指摘されます:

```ts
const mockUser: User = {
  id: "dev-bypass-user",
  email: "dev@localhost",
  systemRole: "USER", // 必ず最低権限
  isBypass: true,
};
```

UI 側でも:

```tsx
// admin 画面
if (user.isBypass) {
  return <div>bypass user は admin 機能を使えません</div>;
}
```

### 原則 4. `if (!userId)` 禁止 (`=== null` 比較)

`userId` が `0` や `""` のとき、`!userId` は truthy と判定されます。bypass user の id が `0` 始まりだと意図せず anonymous 扱いになる事故が起きます:

```ts
// NG (0 / "" を unset と誤判定)
if (!userId) {
  return redirect("/login");
}

// OK (明示比較)
if (userId === null || userId === undefined) {
  return redirect("/login");
}
```

これは bypass 限定の話ではなく **全 codebase に適用** すべきルール。Codex は型レベルで指摘してきます。

## 実装パターン (Next.js + 自前 auth)

```ts
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
3. ジャーニー: read-only 操作のみテスト (write はスキップ)
4. テスト完了後、`.env.local` から該当行を削除
```

## チェックリスト

dev bypass を実装する前に確認:

- [ ] `NODE_ENV === "development"` かつ `ENABLE_DEV_AUTH_BYPASS === "true"` の二重ガード
- [ ] `ENABLE_DEV_AUTH_BYPASS` は `.env.local` のみ (本番 env に存在しない)
- [ ] write API endpoint で `user.isBypass` チェック、403 を返す
- [ ] mock user の `systemRole` は `"USER"` 固定
- [ ] admin / maintainer UI で `user.isBypass` を弾く
- [ ] `if (!userId)` を全 codebase で `=== null` 比較に置換
- [ ] ランブックに bypass の有効化手順 + read-only 限定の注意を明記

7 項目全部 ✅ で Codex 監査に投入。最初から織り込めば 0 ラウンドで bypass 関連の指摘を消せます。

## 関連文書

- [`03-five-decisive-fixes.md`](03-five-decisive-fixes.md) — 5 つの決定的対策
- [`05-env-lint-checklist.md`](05-env-lint-checklist.md) — 環境系 lint 14 項目
