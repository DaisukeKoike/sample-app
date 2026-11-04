# Project Lab: 案件・タスク管理演習
## 目的
AIと一緒に、不具合の発見→根拠のある起票→修正→回帰テスト→レビュー→PRを練習する。
3案件・36タスクの架空データを初回起動時にSQLiteへ作成する。実データ・認証情報は使わない。

## 起動（リポジトリ直下 / Git Bash）
```bash
python api/app.py
```
ブラウザで http://127.0.0.1:8080 を開く。終了はCtrl+C。
実行時はPython標準ライブラリのみ。AWS、Docker、Node.js、外部DBは不要。
初回は `api/data/training.db` を自動作成。ローカル再起動ではデータを保持する。

## 機能
- 全体ダッシュボード: 件数、完了率、見積・実績工数
- 案件/状態/タイトル/期限で絞込み、ページ送り、CSV出力
- タスク登録、状態変更、コメント追加・閲覧
- APIで実績工数更新、versionによる更新競合検知、変更監査レコード
- UI → HTTP API → service.py → repository.py → SQLiteの層構造

## 正しい業務仕様
- 期限終了日は当日を含む。
- 一覧はpriority,idの昇順。ページ間で欠落・重複しない。
- 状態はtodo→doing→done。done→doing、doing→todoは可能。todo→doneは禁止。
- 完了率はdone件数÷全件数。0件は0%。小数1桁。
- CSVは画面と同じ検索条件を適用する。ページ条件は適用しない。

## テスト
```bash
python -m pip install -r api/requirements-dev.txt
(cd api && python -m pytest -q)
```
既定はバグON。5件の仕様テストは strict xfail として明示する。
xfailは「正しい」ではなく「既知の仕様違反」。修正した1件のマーカーを外し、通常テストへ昇格する。
`TRAINING_BUGS=off python -m pytest` はapiディレクトリでの比較用。OFFにするだけの修正は禁止。

## 開発の始め方
Claude Codeで例:
```
/issue-create 期限を11月10日までにすると当日のタスクが消える。再現して受入基準付きで起票して
/issue-start <番号> --local
```
対象1件だけ修正し、テスト→ `/review-<プロジェクト名>` → `/pr-create`。
正解が必要なときだけ `docs/training-bugs.md` を参照する。

## 制限
認証・ユーザー権限管理は未実装。ローカル演習専用で、本番利用不可。
Dockerは `docker run -p 127.0.0.1:8080:8080 <image>` のようにローカル限定で使う。
ECSの既存構成はSQLiteを永続化しない。タスク再作成でデータが消える。
CSVは現段階では最大100件。大量データ対応、認証、永続DB、E2Eは発展課題。
