# YamaGo Flutter

ネイティブアプリ版 **YamaGo（山手線リアル鬼ごっこ）** の実装リポジトリです。Web 版（Next.js / Firebase）を仕様リファレンスとし、iOS / Android に最適化した UI とリアルタイム体験を Flutter で再構築します。

## ゲーム説明（チュートリアル & イベント）

- **YamaGoの舞台**: 山手線エリア全体を使ったリアル鬼ごっこで、鬼と逃走者に分かれて移動しながらプレイします。現実の地形や路線を活かし、仲間と通信しながら勝利条件を目指します。
- **鬼のミッション**: 逃走者の位置をマップで共有しながら捕獲範囲へ追い込み、全員を捕獲できれば勝利。退路を塞ぎながら包囲する粘り強さが重要です。
- **逃走者のミッション**: マップ上の発電機をすべて解除すれば逃走者の勝利。解除中は同じ場所にとどまり、開始と同時に鬼へ通知されるため仲間の警戒が必須です。
- **ダウンと救出**: 捕まった逃走者は「ダウン中」となり、ほかの仲間が捕獲範囲内で救出ゲージを満たすと復帰します。救出は鬼に見つかりやすい行動なので連携が求められます。
- **ゲームの開始と終了**: オーナーが開始ボタンを押してスタート。鬼が動けるようになるまでのカウントダウン中に逃走者は散開します。終了後は設定タブから必ずログアウトして位置共有を止めてください。
- **定期イベント**: ゲーム時間の 25% ごとに「第1フェーズ → 第2フェーズ → 最終フェーズ」とイベントが発生。マップに水色ピンのターゲット発電所が出現し、逃走者はイベント時間内に指定人数で同時解除を達成する必要があります。
- **イベントのリスクと結果**: 目標を達成できないと鬼の捕獲半径が次イベントまで 2 倍に拡大し、残りの発電機位置も再配置されます。成功すれば未解除の発電機が新しい場所に再配置され、次の攻略ルートを組み立てられます。

## プロジェクト方針

- **構造**: `lib/features/<feature>/presentation|application|data` と `lib/core/...` の feature-first 構成。UI・状態・データアクセスを分離し、機能単位で保守しやすくします。
- **状態管理**: `flutter_riverpod` + `riverpod_annotation` を採用。Firestore のリアルタイム購読、位置情報ストリーム、UI 状態を統合的に扱います。
- **ルーティング**: `go_router` の `StatefulShellRoute` を用い、ゲーム画面の BottomNav（Map / Chat / Settings）をネイティブタブライクに表現。deeplink や `/game/:gameId/...` の画面分岐も容易にします。
- **テーマ**: Material 3 + ダークモード基調。山手線 PWA 版と同様のハイコントラスト配色を `ColorScheme.fromSeed` で再現しやすくしています。
- **Firebase 直接更新**: Web 版と同じくクライアントから Firestore に直接アクセスします。`core/services/firebase` 層で初期化を行い、Auth/Firestore の Provider を各機能に注入する設計です。

## 現状の画面と遷移

| Route | 役割 |
| --- | --- |
| `/splash` | Firebase 初期化・Auth チェックを置く予定の起動画面 |
| `/welcome` | 参加/作成 CTA をまとめたトップ画面 |
| `/join` | ニックネーム・ゲーム ID・アバター選択フォーム（今後実装） |
| `/create` | ゲーム作成フロー（匿名ログイン → createGame → owner join） |
| `/game/:gameId/map` | リアルタイムマップ／HUD。StatefulShellRoute の 1 タブ |
| `/game/:gameId/chat` | 役割別チャット UI |
| `/game/:gameId/settings` | プレイヤー設定・退出・ロール管理など |

## 今後の実装ステップ（抜粋）

1. `core/services/firebase` と `bootstrap.dart` を追加し、匿名 Auth / Firestore 初期化を Splash → Welcome へ繋ぐ。
2. Map タブに `google_maps_flutter` + 位置情報許諾フローを組み込み、ピン・HUD の UI コンポーネントを移植。
3. Firestore Repositories（Game / Player / Location / Chat）を data 層に配置し、Riverpod Notifier で game store を再現。
4. `Info.plist` / Android `AndroidManifest.xml` に位置情報パーミッション文言を追加（実際のキーは含めない）。

## 開発メモ

- API キー・`GoogleService-Info.plist`・`google-services.json` など秘密情報は追加しません。各開発者がローカルで配置してください。
- 地図は `google_maps_flutter` を採用し、`BitmapDescriptor.fromBytes` によるカスタムピンで鬼／逃走者アイコンを表現できます。
- 位置情報利用目的（App Store 審査想定文言案）:
  > 「リアルタイムで鬼ごっこを成立させるために、プレイヤーの現在地を取得・共有します。他のプレイヤーにはゲームルールで許可された範囲のみ表示されます。」

- 既存 Web 版の仕様は `reference_repo/` で確認できます。Firestore スキーマやゲームロジックの整合性を保ちながら Flutter へ移植してください。

## Cloud Functions / 通知

- `functions/` ディレクトリに Firebase Functions（Node.js 20）を追加しました。`onChatMessageCreated` で Firestore の `messages_oni / messages_runner` への書き込みを検知し、同じ役割のプレイヤーへ FCM 通知を送信します。`messages_general` については `onGeneralChatMessageCreated` で処理し、ゲーム参加者全員に総合チャットの通知を届けます。
- `cleanupInactiveGames` は Cloud Scheduler（毎日 03:00 JST）で起動し、30 日間更新が無いゲームドキュメントを自動削除します。`players.updatedAt / joinedAt`、`pins.updatedAt`、`events.createdAt`、チャット `timestamp` などを走査して最後のアクティビティを推定し、閾値より古ければ `recursiveDelete` でサブコレクションごとクリーンアップします。
- デプロイ前に `cd functions && npm install` を実行してください。ローカルエミュレータでの動作確認や本番デプロイは `firebase deploy --only functions` で行えます。
- Scheduler の有効化は関数デプロイ時に自動作成されます。初回のみ Cloud Scheduler API を有効化し、必要に応じて `gcloud scheduler jobs list` で `cleanupInactiveGames` の状態を確認してください。
