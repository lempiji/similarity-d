---
title: Default Collect Nested Functions
date: 2025-07-06
status: Accepted
---

# ADR 0001: デフォルトで入れ子関数を収集する

Originating Proposal: docs/design/proposals/0001-nested-function-collection.md

## 背景
提案 0001 ではユーザーが入れ子関数の収集をオプトアウトできる `excludeNested` オプションの追加を説明しています。
すべての関数を調査することで重複を検出しやすくするのが目的です。
これには他の関数内で宣言されたものも含みます。

## 決定
入れ子関数をデフォルトで収集します。
コレクターと CLI は `excludeNested` フラグを公開し、不要な場合は入れ子宣言を無視できるようにします。

## 結果
- 入れ子関数を多用するプロジェクトでの類似度検出が向上します。
- 大規模コードベースではメモリ使用量と処理時間がやや増加しますが、`--exclude-nested` で抑制できます。
