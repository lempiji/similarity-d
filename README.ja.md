# similarity-d

**English version:** [README.md](README.md)

このリポジトリはD言語で書かれたコマンドラインツール **similarity-d** の日本語版READMEです。プロジェクト内の類似した関数を検出するために、正規化された抽象構文木を比較するTree Edit Distance(TED)アルゴリズムを利用します。

## 前提条件

ツールを使用するには **DMD** 2.111.0 以上が必要で、`dub` が `PATH` に通っている必要があります。コンパイラがインストールされていない場合は、D言語プロジェクトが提供する `install.sh` または Windows インストーラーを利用してください。インストール後に `dub --version` を実行してツールチェーンが利用可能か確認します。

## 使い方

```
dub fetch similarity-d
dub run similarity-d -- [options]
```

### オプション

- `--dir` <path>  検索対象となる `.d` ソースファイルのディレクトリ(デフォルトはカレントディレクトリ)
- `--threshold` <float>  類似度の閾値
- `--min-lines` <integer>  対象とする最小行数
- `--min-tokens` <integer>  正規化ASTノードの最小数(デフォルト20)
- `--no-size-penalty`  類似度計算時の長さペナルティを無効化
- `--print`  結果表示時に各関数のスニペットを表示
- `--cross-file[=true|false]`  ファイルを跨いだ比較を許可(デフォルトは `true`)
- `--exclude-unittests`  `unittest` ブロックを除外
- `--exclude-nested`  ネストした関数を無視しトップレベルのみ収集
- `--version`  パッケージのバージョンを表示して終了

指定したディレクトリ内のすべての関数を比較し、閾値を超えるものを報告します。結果には双方の位置と計算された類似度が表示されます。TEDアルゴリズムは識別子やリテラルを正規化してから編集距離ベースのスコアを求めます。

短い関数が結果を支配しないよう長さペナルティを加えています。生の編集距離を用いたい場合は `--no-size-penalty` を指定してください。

例:

```bash
$ similarity-d --threshold=0.8 --min-lines=3 --dir=source --exclude-nested
# ファイル間比較を無効化
$ similarity-d --threshold=0.8 --cross-file=false
$ similarity-d --version
0.1.0
```

## 備考

本プロジェクトは [mizchi/similarity](https://github.com/mizchi/similarity) で提案されたアイデアを基にしています。元のリポジトリは複数言語を対象としていますが、**similarity-d** はD言語専用に同じTED手法を実装しています。

## サンプル

`samples/` フォルダーにいくつかの小さな例があります。各フォルダーには2つの`.d`ファイルと簡単な説明があります。

### `samples/basic`

ほぼ同一の関数が2つあります。トークンフィルターを下げて一致を確認できます:

```bash
$ dub run -- --dir samples/basic --min-tokens=0
samples/basic\file_a.d:3-9 <-> samples/basic\file_b.d:3-9 score=1 priority=7
samples/basic\file_a.d:20-26 <-> samples/basic\file_b.d:20-26 score=1 priority=7
```

デフォルトではファイル間比較が有効なため `file_a.d` と `file_b.d` の関数が一致します。ファイル内のみで比較したい場合:

```bash
$ dub run -- --dir samples/basic --min-tokens=0 --cross-file=false
No similar functions found.
```

`--min-tokens=0` を指定しないとデフォルト値20により小さな関数は出力されません。

### `samples/threshold`

`a.d` には長さの異なる2つの関数があります。デフォルトの閾値 `0.85` ではペアが隠れます:

```bash
$ dub run -- --dir samples/threshold
No similar functions found.
```

閾値を下げると部分一致が見つかります:

```bash
$ dub run -- --dir samples/threshold --threshold=0.3 --min-tokens=0 --cross-file=false
samples/threshold\a.d:1-7 <-> samples/threshold\a.d:9-17 score=0.346939 priority=3.12245
```

### `samples/nested`

このフォルダーではネストした関数が結果に影響する様子を示しています。ファイルには同一のネストした `addOne` 関数がありますが外側の関数は異なります。

```bash
$ dub run -- --dir samples/nested --min-tokens=0
samples/nested\file_a.d:3-9 <-> samples/nested\file_b.d:3-9 score=1 priority=7
```

ネストした関数を無視すると一致は無くなります:

```bash
$ dub run -- --dir samples/nested --min-tokens=0 --exclude-nested
No similar functions found.
```

## 開発

プルリクエストを送る前に必ずテストスイートを実行してください。各モジュールで70%以上のカバレッジが求められます。

```bash
dub test --coverage --coverage-ctfe
```

テスト後、`source-*.lst` 各ファイルが少なくとも70%のカバレッジを示すか確認するため次を実行します:

```bash
rdmd ./scripts/check_coverage.d
```
閾値を下回るファイルがあるとスクリプトはエラーで終了します。

CLI が問題なく動作するか、最小構成で確認します:

```bash
dub run -- --dir source/lib --exclude-unittests --threshold=0.9 --min-lines=3
```

## 依存関係の管理

`dub upgrade` で依存関係を更新した後、テストスイートを実行してカバレッジを取得してください。テストが通ったら上記の手順でCLIが動作するか確認し、更新されたマニフェストファイルをコミットします。詳細な手順は [AGENTS.md](AGENTS.md#dependency-maintenance-dub) を参照してください。

## コントリビュート

ワークフローやガイドラインは [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## ライセンス

本プロジェクトは [MIT License](LICENSE) のもとで公開されています。

