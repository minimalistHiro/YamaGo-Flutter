# YamaGo Flutter

ネイティブアプリ版 **YamaGo（山手線リアル鬼ごっこ）** の実装リポジトリです。Web 版（Next.js / Firebase）を仕様リファレンスとし、iOS / Android に最適化した UI とリアルタイム体験を Flutter で再構築します。

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

- `functions/` ディレクトリに Firebase Functions（Node.js 20）を追加しました。`onChatMessageCreated` で Firestore の `messages_oni / messages_runner` への書き込みを検知し、同じ役割のプレイヤーへ FCM 通知を送信します。
- デプロイ前に `cd functions && npm install` を実行してください。ローカルエミュレータでの動作確認や本番デプロイは `firebase deploy --only functions` で行えます。
