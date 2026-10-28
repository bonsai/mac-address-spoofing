# mac-spoof へようこそ 🛰️

Wi-Fi の **MAC アドレス** を付けかえて、その記録を残すための小さな道具箱です。
この README だけで、**「何なのか」「なぜやるのか」「どう使うのか」「どこが危ないのか」** が全部わかるように書きました。

むずかしい言葉はできるだけ使わず、使うときは説明を付けています。
対象は「プログラミングを少し触ったことがある中学生」くらいです。

---

## 目次

1. [MAC アドレスってなに？](#1-mac-アドレスってなに)
2. [「spoof（なりすまし）」ってどういう意味？](#2-spoofなりすましってどういう意味)
3. [なぜ付けかえるの？](#3-なぜ付けかえるの)
4. [なぜ記録を残すの？](#4-なぜ記録を残すの)
5. [なぜ位置情報も残すの？](#5-なぜ位置情報も残すの)
6. [フォルダの構成](#6-フォルダの構成)
7. [使い方](#7-使い方)
8. [中で何が起きているの？](#8-中で何が起きているの)
9. [気をつけること（ここが一番大事）](#9-気をつけることここが一番大事)
10. [うまくいかないとき](#10-うまくいかないとき)

---

## 1. MAC アドレスってなに？

Wi-Fi や 有線 LAN の機械（アダプタ）1つ1つに付いている、**48ビットの番号**です。
`02:F1:2D:C9:AB:C1` みたいに、6つのブロックで書きます。

たとえるなら **「機械の名札」** です。名前ではなく番号の名札。

名札の先頭（1つ目のブロック）には、大事なルールがあります。

| 先頭 | 意味 | 使っていい？ |
|---|---|---|
| bit1 が 0（例: `00`, `A4`） | メーカーが工場で焼いた番号。**世界で1つだけ** | 勝手に使うと他人とぶつかる ⚠️ |
| bit1 が 1（例: `02`, `06`, `0A`） | **自分で決めていい**番号（ローカル管理） | ここを使う ✅ |
| bit0 が 1（例: `01`, `03`） | 「みんな宛て」の特別な番号 | 機械に付けたら通信が壊れる ❌ |

この道具が作るのは、**いつも `02:xx:xx:xx:xx:xx`** です。
`02` は「自分で決めていい番号」のスタート地点なので、ここを使うのがルール違反になりません。

> 💡 `01` で始まる番号を付けてしまうと、通信がおかしくなります。コードで「必ず `02` から始める」と決めているのは、その事故を防ぐためです。

---

## 2. 「spoof（なりすまし）」ってどういう意味？

MAC アドレスは機械に焼き付けてありますが、**OS は「送るときに別の番号を使う」ことができます**。
ドライバ（機械を動かすプログラム）に「この番号で送って」と頼むだけです。

これが **MAC spoofing（MAC のなりすまし）** です。

でも、勘ちがいしないでください。

> **これは「セキュリティを破る魔法」ではありません。名札を付けかえているだけです。**

パスワードは1つも破っていません。暗号も解いていません。
変わるのは **「さっきと同じ機械か？」という判定だけ** です。

### 効く相手 / 効かない相手

| 相手 | 効く？ | なぜ |
|---|---|---|
| 公衆 Wi-Fi の「1台◯分まで」制限 | 効くことが多い | 機械を MAC で見分けているから |
| 接続履歴の追跡 | 少し効く | 「同じ機械」としてつながりにくくなる |
| Wi-Fi のパスワード認証 | 効かない | パスワードを知らないと入れない |
| 学校・会社の認証 | 効かない | 証明書や ID で見ている |
| Web サイトのログイン状態 | 効かない | Cookie という別の仕組みで追跡される |
| 位置の特定 | ほとんど効かない | 電波・GPS・IP アドレスから別ルートでわかる |

**「MAC を変えれば正体がバレない」はウソ** です。変わるのは「同じ機械かどうか」だけ。
これを知っておくのが、この道具を使う上での第一歩です。

---

## 3. なぜ付けかえるの？

実際のログ（`data/db.jsonl`）を見ると、この道具はこんなふうに使われています。

```
mcd_connect   ssid: 00_MCD-FREE-WIFI   → お店の無料 Wi-Fi につないだ
switch_to_TEX                          → 別の Wi-Fi に切りかえた
schedule_rotate in_min: 50             → 50分ごとに MAC を変える予約
```

理由はだいたい3つです。

1. **無料 Wi-Fi の時間制限をリセットする** — 「1台◯分まで」を MAC で数えているお店では、変えると新しい機械として見られる
2. **接続の履歴を分ける** — 「ずっと同じ人がいた」と記録されにくくする
3. **ログの相関を弱める** — 何回かの接続を、同じ機械だと結びつけにくくする

> ⚠️ **でも 1 は、多くの場合お店のルール（利用規約）に反します。**
> 「技術的にできる」と「やっていい」は別です。自分の回線・自分の実験・許可された検証の範囲で使いましょう。
> くわしくは [9章](#9-気をつけることここが一番大事) を読んでください。

---

## 4. なぜ記録を残すの？

MAC を変える作業で、いちばん危ないのは **「何をしたか分からなくなる」** ことです。

- 変える前の番号は？
- 本当に変わったの？
- いつ、どの番号にしたの？
- 元に戻せる？

だからこの道具は、**成功しても失敗しても、必ず1行** を `data/db.jsonl` に残します。

```jsonl
{"t":"2026-10-28T19:58:55+09:00","cmd":"rotate","mac":"02-F1-2D-C9-AB-C1","ok":true,"adapter":"Wi-Fi"}
```

| 項目 | 意味 |
|---|---|
| `t` | いつ（ISO 8601 形式の時刻） |
| `cmd` | 何をしたか（`rotate` = 付けかえ） |
| `mac` | 新しい番号 |
| `ok` | **本当に変わったか**（下で説明） |
| `adapter` | どのアダプタか |

### `ok: true` の意味が大事

`ok` は「命令を出したか」ではなく **「本当にその番号になったか」** です。

1. レジストリ（Windows の設定置き場）に番号を書く
2. アダプタを一旦オフ→オンする
3. **OS にもう一度聞いて、書いた番号と同じか確かめる**
4. 同じなら `ok: true`、違うなら `ok: false`

つまり **自己申告ではなく実測**。ここをサボると「変えたつもりで変わっていない」が起きます。

> 💡 この記録があるから、あとから **元の番号に戻す** こともできます。
> `db.jsonl` は飾りではなく、この道具の **安全装置** です。

### 記録の形（スキーマ）

1行1行がどんな形をしているかを、機械が読める形で決めてあります。それが **スキーマ**。

```
src/core/db-schema.mjs     ← 決まりごとの「原本」（ここだけ直せばよい）
      │ npm run schema
      ▼
schema/db.schema.json      ← JSON Schema（ほかの道具からも読める形）
```

決まりごとを **1か所（`db-schema.mjs`）だけ** に書いているのがポイントです。
2か所に書くと、必ずどちらかが古くなってズレます。

| コマンド | 中身 |
|---|---|
| `rotate` | 付けかえの実績（`mac` と `ok` が必須） |
| `rotate_planned` | これからの予定（`run` / `of` / `task` が必須） |
| `schedule_rotate` | 予約を入れた記録 |
| `speed_record` | 回線の速さ・遅延 |
| `mcd_connect` `switch_to_TEX` `wifi_record` ほか | ゆるい記録（`cmd` だけでOK） |

### ダミーデータで練習できる

本物の記録（`data/db.jsonl`）は **git に入れません**（個人の行動記録なので）。
代わりに **形だけのダミー** を入れてあります。

```
data/sample.db.jsonl       ← 架空データ（02:AA:BB:.. / 203.0.113.x = 例示用アドレス）
```

```powershell
npm run validate:sample   # ダミーがスキーマに合うか確かめる
npm run validate          # 本物の記録を確かめる
npm run schema            # スキーマを作り直す
```

わざと壊した行を入れると、どこがどうダメか教えてくれます。

```
data\db.jsonl:1: [1] rotate.mac: "00:11:22:33:44:55" がパターン ^02([-:][0-9A-Fa-f]{2}){5}$ に合いません
```

これは **`00` で始まる番号を使っている** という指摘です。まさに 1章で話した事故ですね。

---

## 5. なぜ位置情報も残すの？

「どの番号を、どこで使ったか」を残すためです。理由は **監査（あとから確認できること）**。

- 同じ MAC を別の場所で使い回していないことが証明できる
- お店の Wi-Fi の利用実績と照らし合わせられる

取り方はこういう順番です。

```
① Windows の位置情報（精度1mを要求 → GPS を優先）
      │  取れた？ → はい → 使う（PositionSource が Satellite なら gps: true）
      ▼  だめなら
② IP アドレスから大体の場所（ip-api.com）
      → 市区町村・国・プロバイダ・グローバルIP を補う
```

### 正直に言っておきます

**このパソコンには GPS が付いていません。**（センサー機器が0個でした）

実際に取れたのはこんな結果です。

```
source: wifi, gps: false, accuracy_m: 55, city: Sapporo
```

これは **Wi-Fi の電波から計算した位置** で、誤差は 55m くらい。
本物の GPS ではありません。だから記録に `gps: false` と正直に書きます。

さらに、**IP から引いた地名は信用しすぎない** でください。
同じ機械・同じ座標なのに、ある日は `Minato`、別の日は `Sapporo` と返ってきました。
携帯回線の IP は接続のたびに変わり、しかも遠くの街を指すことがあるからです。

- `gps` を別の項目にしているのは、**精度の違う数字を混ぜないため**です
- GPS の 5m と Wi-Fi の 55m を同じ扱いにすると、監査の意味がなくなります
- `-GpsOnly` を付けると **Satellite（本物のGPS）以外は記録しない** 動きになります
- GPS 内蔵のタブレットや USB GPS を使えば `gps: true` で記録されます

---

## 6. フォルダの構成

```
mac-spoof/
├── README.md                 ← この説明書（旧 spoof.md の内容もここに統合）
├── package.json              ← npm run ○○ のコマンド一覧
├── .gitignore                ← data/ の中身は git に入れない設定
│
├── data/                     ← データ（プログラムではない）
│   ├── db.jsonl              ★ 唯一の記録ファイル（実績も予定もここ）※git 対象外
│   ├── dashboard.json        ← 自動生成される集計ファイル ※git 対象外
│   ├── sample.db.jsonl       ← 架空のダミーデータ（これだけ git に入る）
│   └── tsubame.db            ← 昔の SQLite（今は使っていない）
│
├── schema/
│   └── db.schema.json        ← npm run schema で生成されるスキーマ
│
├── scripts/                  ← OS を操作する処理（PowerShell / sh）
│   ├── rotate.ps1            ★ MAC を付けかえる本体（Windows）
│   ├── rotate.sh             ★ 同じことをする sh 版（Linux/macOS/Windows-bash）
│   └── location.ps1          ← 位置情報を取る部品（rotate.ps1 から使う）
│
└── src/                      ← JavaScript 側
    ├── core/
    │   ├── db-schema.mjs     ★ 記録の形の「原本」
    │   ├── detect.js         ← SSID/IP を見る部品
    │   ├── rotate.js         ← 回転の入口（薄いラッパー）
    │   └── speed.js          ← 回線計測の部品
    ├── tools/
    │   ├── gen-schema.mjs    ← スキーマ生成
    │   └── validate-db.mjs   ← JSONL 検証
    ├── mcp/server.js         ← MCP サーバ（AI から道具として呼べる）
    ├── bridge/ws.js          ← WebSocket の橋わたし (ws://localhost:8765)
    └── dashboard/
        ├── gen-dashboard.js  ← db.jsonl → dashboard.json に集計
        └── dashboard.html    ← 画面（60秒ごとに自動更新）
```

### なぜ分けているの？

| フォルダ | 入れるもの | 入れないもの |
|---|---|---|
| `data/` | 記録・結果 | プログラム |
| `schema/` | 形の定義 | 実データ |
| `scripts/` | OS を操作する処理 | データ |
| `src/` | JavaScript の処理 | データ |

**「データ」と「プログラム」を同じ場所に置かない** のが基本です。
そうすると「消していいのはどれ？」が迷いません。

### 冗長なものをまとめました

前は似たようなファイルが多くて「どれを実行すればいいの？」となりがちでした。今はこうです。

| 前 | 今 |
|---|---|
| `rotate.ps1` と `rotate-registry.ps1` | **`rotate.ps1` 1本**（`-NoRestart` で昔の動き） |
| `rotate.sh` は「表示するだけ」のお飾り | **本物の sh 版**（Windows では PowerShell に丸投げ、Linux/macOS は自分でやる） |
| スキーマが無い（形が口伝え） | `src/core/db-schema.mjs` が唯一の原本 |

---

## 7. 使い方

### 準備

- Windows の **管理者として実行** した PowerShell が必要です（設定置き場を書き換えるため）
- Node.js が入っていると、ダッシュボードが使えます

### ふつうに付けかえる

```powershell
cd C:\Users\dance\mac-spoof
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate.ps1
```

出てくる表示の例:

```
MAC: 02F12DC9ABC1 -> 02-8B-70-78-2A-86
LOC: 35.6977515 (139.7073181 / 55m) Minato, wifi
```

### 選べるオプション

```powershell
# 位置情報を取らない（オフラインのとき・速くしたいとき）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate.ps1 -NoLocation

# 本物の GPS が取れたときだけ記録する
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate.ps1 -GpsOnly

# レジストリに書くだけで、アダプタを落とさない（旧 rotate-registry.ps1）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate.ps1 -NoRestart

# 何も変えずに「やること」だけ見る（練習用）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate.ps1 -DryRun

# アダプタ名が "Wi-Fi" じゃないとき
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\rotate.ps1 -AdapterName "Wi-Fi 2"
```

### sh から使う（Linux / macOS / Git Bash / WSL）

同じことをする **sh 版** もあります。使う場所によって中身が切りかわります。

| 場所 | 何をする |
|---|---|
| Windows の bash（Git Bash / MSYS2 / WSL） | PowerShell 版に丸投げ（同じ結果になる） |
| Linux | `ip link`（あれば `macchanger`）で付けかえ |
| macOS | `ifconfig ... ether` で付けかえ |

```bash
./scripts/rotate.sh                  # 付けかえ + 位置情報(IP)
./scripts/rotate.sh --no-location    # 位置情報なし
./scripts/rotate.sh --no-restart     # 設定だけ書く
./scripts/rotate.sh --dry-run        # 表示だけ
./scripts/rotate.sh --adapter wlan0  # アダプタ名を指定
```

**記録の形は PowerShell 版とまったく同じ** です（`os` フィールドだけ追加されます）。
だからダッシュボードで区別なく見られます。

### npm で短く書く

```powershell
npm run rotate            # 付けかえる
npm run rotate:sh         # sh 版で付けかえる
npm run rotate:gps        # GPS のときだけ
npm run rotate:dry        # 練習（何も変えない）
npm run rotate:registry   # 設定だけ書く
npm run validate          # 記録がスキーマに合っているか確かめる
npm run dashboard         # dashboard.json を作り直す
npm run view              # 作ってから http://localhost:8080/src/dashboard/dashboard.html を開く
```

### 予定を入れる（50分ごと・3回だけ）

`schtasks /Change /SC MINUTE /MO 50` は **ずっと繰り返して止まりません**。
「3回だけ」にしたいときは、**1つのタスクに単発の予定を3つ** 入れます。

```powershell
$start = (Get-Date).AddMinutes(50)
$times = @($start, $start.AddMinutes(50), $start.AddMinutes(100))   # 3回ぶん
$triggers = $times | ForEach-Object { New-ScheduledTaskTrigger -Once -At $_ }
Set-ScheduledTask -TaskName MacSpoofRotate -Trigger $triggers
```

登録するときの注意:

- `/RL HIGHEST` と `/RU SYSTEM` を付ける（管理者権限で動かすため）
- 実行中は Wi-Fi が **数秒切れます**（アダプタをオフ→オンするので）

確認と取り消し:

```powershell
Get-ScheduledTask -TaskName MacSpoofRotate | Get-ScheduledTaskInfo
Unregister-ScheduledTask -TaskName MacSpoofRotate -Confirm:$false
```

### 「予定」も同じファイルに書く

`db.jsonl` は **未来の時刻の行も受け付けます**。

```jsonl
{"t":"2026-10-28T20:43:00+09:00","cmd":"rotate_planned","run":1,"of":3,"task":"MacSpoofRotate","status":"pending"}
```

- `t` が **未来** → 予定
- `t` が **過去** → 実績

`gen-dashboard.js` がこの1本のファイルから「予定 / 実績 / 今の MAC」を分けて、`dashboard.html` が同じ画面に並べます。
**予定と結果を別々の場所に置かない** ので、「予約したのに実行された？」がいつも1画面で分かります。

---

## 8. 中で何が起きているの？

### なぜ `Set-NetAdapterAdvancedProperty` ではダメなのか

ふつうはこの PowerShell コマンドで MAC を変えられます。
でも、このパソコンの Wi-Fi チップ（Intel Dual Band Wireless-AC 8265）では **必ず失敗** します。

```
No matching MSFT_NetAdapterAdvancedPropertySettingData objects found by CIM query ...
```

理由はかんたん。**このチップには "Network Address" という設定項目が無い** からです。
高機能なチップはその項目を出すのですが、この機種は出しません。だから「そんな項目ないよ」と怒られます。

### 代わりにレジストリを直接書く

レジストリ＝Windows の設定をしまっておく巨大な棚です。

```
HKLM\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}\<NNNN>
    NetworkAddress = "02F12DC9ABC1"     ← 12桁の16進数、区切りなし
```

`<NNNN>`（`0002` など）はパソコンによって違います。
だから `rotate.ps1` は **`NetCfgInstanceId` と `InterfaceGuid` を照らし合わせて、正しい棚を自動で探します**。
だから `-AdapterName` を変えれば他のパソコンでも動きます。

書いただけでは反映されないので、**アダプタをオフ→オン** して読み直させます（この数秒だけ通信が切れます）。

### 処理の流れ

```
位置情報を取る（GPS → Wi-Fi測位 → IP の順にためす）
   ↓
アダプタのレジストリの棚を探す
   ↓
02 から始まる番号を作る
   ↓
レジストリに書く
   ↓
アダプタをオフ → オン
   ↓
OS に聞いて、本当に変わったか確かめる
   ↓
db.jsonl に1行書く（ok: true / false）
```

---

## 9. 気をつけること（ここが一番大事）

### やってはいけないこと

- ❌ 他の人のパソコンやスマホになりすます
- ❌ お店や学校のルールを破るために制限を回避する
- ❌ パスワードや暗号を突破しようとする（そもそも関係ない）
- ❌ **変える前の番号を記録せずに上書きする**

### 法律の話

日本では、他人になりすます目的での MAC 偽装は **不正アクセス禁止法** に関わることがあります。
「技術的にできる」ことと「やってよい」ことは、はっきり違います。

### 技術的な注意

| 注意 | 理由 |
|---|---|
| 番号は必ず `02` から始める | `00` は他人とぶつかる、`01` は通信が壊れる |
| 12桁の16進数を**区切りなし**で書く | `02 4D F4` のようにスペースが入ると失敗する |
| `.ps1` は **UTF-8 BOM 付き** で保存 | BOM が無いと日本語コメントで構文エラーになる（実体験） |
| アダプタのオフ→オンで数秒切れる | 当たり前ですが、通信中の作業には向かない |
| 管理者でないと失敗する | 失敗しても `ok: false` で記録される（黙って消えない） |
| `data/` の中身は git に入れない | 行動記録は個人情報。ダミーだけ共有する |

> 💡 **BOM の話**：Windows PowerShell 5.1 は、BOM の無い UTF-8 ファイルを別の文字コードとして読みます。
> すると日本語コメントの文字がとなりの中身を飲みこんでしまい、**関係ない行でエラー** が出ます。
> 「日本語を書いたら急に壊れた」ときは、まずこれを疑ってください。

### 何を git に入れて、何を入れないか

| 入れる | 入れない |
|---|---|
| プログラム（`src/` `scripts/`） | 本物の記録 `data/db.jsonl` |
| スキーマ（`schema/`） | 集計結果 `data/dashboard.json` |
| ダミー `data/sample.db.jsonl` | 古いDB `data/tsubame.db` |

`.gitignore` はこうなっています。

```gitignore
data/*
!data/sample.db.jsonl
```

**「全部無視して、サンプルだけ例外」** という書き方です。
逆（「本物だけ無視」）にすると、新しいファイルを追加したときに**うっかり漏れる**からです。
安全側に倒す、という考え方ですね。

---

## 10. うまくいかないとき

| 症状 | 原因 | 直し方 |
|---|---|---|
| `No matching MSFT_NetAdapterAdvancedPropertySettingData` | 古い方法を使っている | `scripts\rotate.ps1`（レジストリ方式）を使う |
| `Registry key not found` | アダプタ名が違う | `Get-NetAdapter` で名前を調べ、`-AdapterName` で渡す |
| `ok: false` になる | 管理者じゃない / アダプタ名が違う | 管理者で実行。名前を確認 |
| 番号が `02 4D F4 ...` になる | JSON 変換でスペースが混ざった | 文字列連結で組み立てる |
| 日本語コメントを書いたら構文エラー | BOM が無い | UTF-8 **BOM 付き** で保存 |
| 予定が永遠に続く | `/SC MINUTE /MO 50` にした | 単発トリガー3個に置きかえる |
| 位置がいつも同じ・誤差が大きい | GPS が無く Wi-Fi 測位になっている | `gps: false` を見る。必要なら `-GpsOnly` |
| ダッシュボードが真っ白 | `dashboard.json` が古い / パスが違う | `npm run dashboard` を実行 |
| `validate` が `invalid: 1` になる | 昔の「 `00` で始まる番号」の行が残っている | その行を直すか、消す（新しい記録には影響なし） |
| `sh: rotate.ps1: No such file` | 古いパスを見ている | タスクのアクションを `scripts\rotate.ps1` に向ける |
| `Processing -File '-NoLocation' failed` | `-File` の後ろにスクリプトを置いていない | `-File <スクリプト> <引数>` の順にする |

---

## まとめ

> **MAC アドレスは「身分証」ではなく「名札」にすぎない。**

付けかえること（spoof）だけを目的にすると、事故ります。
**付けかえたことを残す（log）** ところまでやって、はじめて自分の通信環境を自分で把握できます。

この道具がやっているのは、その2つをセットで扱えるようにすることです。
