const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

const CHAT_CHANNELS = {
  messages_oni: {
    role: 'oni',
    title: '鬼チャット',
    targetRole: 'oni',
  },
  messages_runner: {
    role: 'runner',
    title: '逃走者チャット',
    targetRole: 'runner',
  },
  messages_general: {
    role: 'general',
    title: '総合チャット',
  },
};

const INACTIVITY_DAYS = 30;
const MILLIS_PER_DAY = 24 * 60 * 60 * 1000;

const SUBCOLLECTION_ACTIVITY_FIELDS = [
  {
    name: 'players',
    orderFields: ['updatedAt', 'joinedAt'],
  },
  {
    name: 'pins',
    orderFields: ['updatedAt', 'createdAt'],
  },
  {
    name: 'captures',
    orderFields: ['createdAt'],
  },
  {
    name: 'events',
    orderFields: ['createdAt'],
  },
  {
    name: 'messages_oni',
    orderFields: ['timestamp'],
  },
  {
    name: 'messages_runner',
    orderFields: ['timestamp'],
  },
  {
    name: 'messages_general',
    orderFields: ['timestamp'],
  },
];

async function handleChatNotification({
  snapshot,
  gameId,
  messageId,
  channelKey,
  channelMeta,
}) {
  const data = snapshot.data() || {};
  if (!data || data.type === 'system') {
    return null;
  }

  const rawMessage = (data.message || '').toString().trim();
  if (!rawMessage) {
    return null;
  }

  const senderUid = data.uid || '';
  const senderName = (data.nickname || '').toString().trim() || '仲間';
  const sanitizedMessage = rawMessage.replace(/\s+/g, ' ').slice(0, 120);

  try {
    const recipients = await fetchChatRecipients({
      gameId,
      senderUid,
      targetRole: channelMeta.targetRole,
    });

    if (!recipients) {
      return null;
    }

    const notification = {
      title: channelMeta.title,
      body: `${senderName}: ${sanitizedMessage}`,
    };
    const dataPayload = {
      gameId,
      messageId: messageId || '',
      role: channelMeta.role,
      senderUid,
    };

    await sendChatNotificationBatches({
      gameId,
      channelKey,
      channelMeta,
      notification,
      dataPayload,
      tokens: recipients.tokens,
      tokenOwners: recipients.tokenOwners,
    });
  } catch (error) {
    functions.logger.error('Chat notification handling failed', {
      error,
      gameId,
      channel: channelKey,
    });
  }

  return null;
}

async function fetchChatRecipients({ gameId, senderUid, targetRole }) {
  let playersQuery = db
    .collection('games')
    .doc(gameId)
    .collection('players');
  if (targetRole) {
    playersQuery = playersQuery.where('role', '==', targetRole);
  }
  const playersSnap = await playersQuery.get();

  if (playersSnap.empty) {
    return null;
  }

  const tokens = [];
  const tokenOwners = new Map();

  playersSnap.forEach((doc) => {
    if (doc.id === senderUid) {
      return;
    }
    const playerData = doc.data() || {};
    const fcmTokens = playerData.fcmTokens;
    if (!Array.isArray(fcmTokens)) {
      return;
    }
    fcmTokens.forEach((token) => {
      if (typeof token === 'string' && token.length > 0) {
        tokens.push(token);
        if (!tokenOwners.has(token)) {
          tokenOwners.set(token, doc.id);
        }
      }
    });
  });

  if (tokens.length === 0) {
    return null;
  }

  return { tokens, tokenOwners };
}

async function sendChatNotificationBatches({
  gameId,
  channelKey,
  channelMeta,
  notification,
  dataPayload,
  tokens,
  tokenOwners,
}) {
  const invalidTokens = new Set();
  const chunkSize = 500;

  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    try {
      functions.logger.info('Sending chat notification batch', {
        gameId,
        role: channelMeta.role,
        channel: channelKey,
        batchSize: chunk.length,
      });
      const response = await messaging.sendEachForMulticast({
        tokens: chunk,
        notification,
        data: dataPayload,
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'chat_messages',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
          },
          payload: {
            aps: {
              alert: notification,
              sound: 'default',
            },
          },
        },
      });
      response.responses.forEach((res, idx) => {
        if (!res.success) {
          const code = res.error?.code || '';
          if (
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token'
          ) {
            invalidTokens.add(chunk[idx]);
          } else {
            functions.logger.error('Chat notification delivery failed', {
              code,
              error: res.error,
              token: chunk[idx],
              gameId,
              role: channelMeta.role,
              channel: channelKey,
            });
          }
        }
      });
    } catch (error) {
      functions.logger.error('Failed to send chat notifications', {
        error,
        gameId,
        role: channelMeta.role,
        channel: channelKey,
      });
    }
  }

  if (invalidTokens.size > 0) {
    await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
  }
}

exports.onChatMessageCreated = functions
  .region('us-central1')
  .firestore.document('games/{gameId}/{collectionId}/{messageId}')
  .onCreate(async (snapshot, context) => {
    const { gameId, collectionId, messageId } = context.params;
    const channelMeta = CHAT_CHANNELS[collectionId];
    if (!channelMeta) {
      return null;
    }

    return handleChatNotification({
      snapshot,
      gameId,
      messageId,
      channelKey: collectionId,
      channelMeta,
    });
  });

exports.notifyPlayersOnGameStatusChange = functions
  .region('us-central1')
  .firestore.document('games/{gameId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    if (!afterData) {
      return null;
    }
    const previousStatus = beforeData?.status;
    const currentStatus = afterData.status;
    const shouldNotifyStart =
      currentStatus === 'running' && previousStatus !== 'running';
    const shouldNotifyEnd =
      currentStatus === 'ended' && previousStatus !== 'ended';
    const previousTimedEventResult = beforeData?.timedEventResult;
    const currentTimedEventResult = afterData.timedEventResult;
    const previousTimedEventResultAt = convertToDate(
      beforeData?.timedEventResultAt
    );
    const currentTimedEventResultAt = convertToDate(
      afterData.timedEventResultAt
    );
    const shouldNotifyTimedEventResult =
      currentTimedEventResult &&
      currentTimedEventResultAt &&
      (!previousTimedEventResult ||
        previousTimedEventResult !== currentTimedEventResult ||
        !previousTimedEventResultAt ||
        previousTimedEventResultAt.getTime() !==
          currentTimedEventResultAt.getTime());

    if (
      !shouldNotifyStart &&
      !shouldNotifyEnd &&
      !shouldNotifyTimedEventResult
    ) {
      return null;
    }

    const gameId = context.params.gameId;
    try {
      const playersSnapshot = await db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .get();

      if (playersSnapshot.empty) {
        functions.logger.info(
          'No players found for game start notification',
          { gameId }
        );
        return null;
      }

      const tokens = [];
      const tokenOwners = new Map();

      playersSnapshot.forEach((doc) => {
        const data = doc.data() || {};
        const playerTokens = data.fcmTokens;
        if (!Array.isArray(playerTokens)) {
          return;
        }
        playerTokens.forEach((token) => {
          if (typeof token === 'string' && token.length > 0) {
            tokens.push(token);
            if (!tokenOwners.has(token)) {
              tokenOwners.set(token, doc.id);
            }
          }
        });
      });

      if (tokens.length === 0) {
        functions.logger.info('No players to notify on status change', {
          gameId,
        });
        return null;
      }

      const invalidTokens = new Set();
      if (shouldNotifyStart) {
        await sendStatusNotificationBatch({
          gameId,
          tokens,
          tokenOwners,
          invalidTokens,
          notification: {
            title: 'ゲームが開始しました',
            body: 'アプリを開いてマップを確認しましょう。',
          },
          dataPayload: {
            type: 'game_start',
            gameId,
          },
          apnsCategory: 'GAME_START',
        });
      }
      if (shouldNotifyEnd) {
        await sendStatusNotificationBatch({
          gameId,
          tokens,
          tokenOwners,
          invalidTokens,
          notification: {
            title: 'ゲームが終了しました',
            body: '結果を確認しましょう。',
          },
          dataPayload: {
            type: 'game_end',
            gameId,
          },
          apnsCategory: 'GAME_END',
        });
      }
      if (shouldNotifyTimedEventResult) {
        const isSuccess = currentTimedEventResult === 'success';
        const body = isSuccess
          ? '未解除の残りの発電機の場所が変わりました。'
          : '鬼の捕獲半径が2倍になり、未解除の発電機の場所が変わりました。';
        await sendStatusNotificationBatch({
          gameId,
          tokens,
          tokenOwners,
          invalidTokens,
          notification: {
            title: 'イベント終了',
            body,
          },
          dataPayload: {
            type: 'timed_event_result',
            gameId,
            result: currentTimedEventResult,
          },
          apnsCategory: 'TIMED_EVENT_RESULT',
        });
      }

      if (invalidTokens.size > 0) {
        await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
      }
    } catch (error) {
      functions.logger.error('Game status notification handling failed', {
        error,
        gameId,
      });
    }

    return null;
  });

exports.onTimedEventCreated = functions
  .region('us-central1')
  .firestore.document('games/{gameId}/events/{eventId}')
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data || data.type !== 'timed_event') {
      return null;
    }

    const { gameId } = context.params;
    const quarter = toInt(data.quarter ?? data.quarterIndex);
    const requiredRunners = toInt(data.requiredRunners);
    const durationSeconds = toInt(data.eventDurationSeconds);

    try {
      const playersSnapshot = await db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .get();

      if (playersSnapshot.empty) {
        functions.logger.info('No players for timed event notification', {
          gameId,
        });
        return null;
      }

      const tokens = [];
      const tokenOwners = new Map();
      playersSnapshot.forEach((doc) => {
        const playerData = doc.data() || {};
        const playerTokens = playerData.fcmTokens;
        if (!Array.isArray(playerTokens)) {
          return;
        }
        playerTokens.forEach((token) => {
          if (typeof token === 'string' && token.length > 0) {
            tokens.push(token);
            if (!tokenOwners.has(token)) {
              tokenOwners.set(token, doc.id);
            }
          }
        });
      });

      if (tokens.length === 0) {
        functions.logger.info('No tokens for timed event notification', {
          gameId,
        });
        return null;
      }

      const quarterLabel = getQuarterLabel(quarter);
      const durationLabel = formatDurationLabel(durationSeconds);
      const bodySegments = [
        `${quarterLabel}のイベントが発生しました。`,
      ];
      if (requiredRunners > 0 && durationLabel) {
        bodySegments.push(
          `${durationLabel}以内に${requiredRunners}人で発電所を解除してください。`
        );
      } else {
        bodySegments.push('アプリを開いてマップを確認してください。');
      }

      const notification = {
        title: 'イベント発生',
        body: bodySegments.join(' '),
      };
      const dataPayload = {
        type: 'timed_event',
        gameId,
        quarter: quarter.toString(),
      };

      const invalidTokens = new Set();
      const chunkSize = 500;
      for (let i = 0; i < tokens.length; i += chunkSize) {
        const chunk = tokens.slice(i, i + chunkSize);
        try {
          functions.logger.info('Sending timed event notification batch', {
            gameId,
            batchSize: chunk.length,
          });
          const response = await messaging.sendEachForMulticast({
            tokens: chunk,
            notification,
            data: dataPayload,
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                channelId: 'map_events',
              },
            },
            apns: {
              headers: {
                'apns-priority': '10',
                'apns-push-type': 'alert',
              },
              payload: {
                aps: {
                  alert: notification,
                  sound: 'default',
                  category: 'TIMED_EVENT',
                },
              },
            },
          });
          response.responses.forEach((res, idx) => {
            if (!res.success) {
              const code = res.error?.code || '';
              if (
                code === 'messaging/registration-token-not-registered' ||
                code === 'messaging/invalid-registration-token'
              ) {
                invalidTokens.add(chunk[idx]);
              } else {
                functions.logger.error(
                  'Timed event notification delivery failed',
                  {
                    code,
                    error: res.error,
                    token: chunk[idx],
                    gameId,
                  }
                );
              }
            }
          });
        } catch (error) {
          functions.logger.error(
            'Failed to send timed event notification batch',
            {
              error,
              gameId,
            }
          );
        }
      }

      if (invalidTokens.size > 0) {
        await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
      }
    } catch (error) {
      functions.logger.error('Timed event notification handling failed', {
        error,
        gameId,
      });
    }

    return null;
  });

async function removeInvalidTokens(gameId, invalidTokens, tokenOwners) {
  const removals = [];
  invalidTokens.forEach((token) => {
    const ownerUid = tokenOwners.get(token);
    if (!ownerUid) {
      return;
    }

    const update = db
      .collection('games')
      .doc(gameId)
      .collection('players')
      .doc(ownerUid)
      .update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
      })
      .catch((error) => {
        functions.logger.error('Failed to prune invalid token', {
          token,
          ownerUid,
          error,
          gameId,
        });
      });

    removals.push(update);
  });

  if (removals.length > 0) {
    await Promise.all(removals);
  }
}

exports.cleanupInactiveGames = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB',
  })
  .pubsub.schedule('0 3 * * *')
  .timeZone('Asia/Tokyo')
  .onRun(async () => {
    const cutoffMs = Date.now() - INACTIVITY_DAYS * MILLIS_PER_DAY;
    const gamesSnapshot = await db.collection('games').get();
    if (gamesSnapshot.empty) {
      functions.logger.info('No games found for inactivity cleanup');
      return null;
    }

    let evaluated = 0;
    let deleted = 0;
    for (const doc of gamesSnapshot.docs) {
      evaluated += 1;
      try {
        const lastActivity = await getLastActivityForGame(doc);
        const lastActivityMs = lastActivity?.getTime() ?? null;
        if (!lastActivityMs || lastActivityMs < cutoffMs) {
          await db.recursiveDelete(doc.ref);
          deleted += 1;
          functions.logger.info('Deleted inactive game', {
            gameId: doc.id,
            lastActivity: lastActivity?.toISOString() ?? null,
          });
        }
      } catch (error) {
        functions.logger.error('Failed to evaluate game for cleanup', {
          gameId: doc.id,
          error,
        });
      }
    }

    functions.logger.info('Inactive game cleanup completed', {
      evaluatedGames: evaluated,
      deletedGames: deleted,
      inactivityCutoff: new Date(cutoffMs).toISOString(),
    });
    return null;
  });

async function getLastActivityForGame(doc) {
  const data = doc.data() || {};
  const timestamps = [];
  addTimestampIfPresent(timestamps, data.updatedAt);
  addTimestampIfPresent(timestamps, data.createdAt);
  addTimestampIfPresent(timestamps, data.startAt);
  addTimestampIfPresent(timestamps, data.countdownStartAt);

  for (const config of SUBCOLLECTION_ACTIVITY_FIELDS) {
    const ts = await fetchLatestTimestamp(doc.ref, config);
    if (ts) {
      timestamps.push(ts);
    }
  }

  if (timestamps.length === 0) {
    return null;
  }

  let latest = timestamps[0];
  for (const ts of timestamps) {
    if (ts.getTime() > latest.getTime()) {
      latest = ts;
    }
  }
  return latest;
}

async function fetchLatestTimestamp(docRef, config) {
  for (const field of config.orderFields) {
    try {
      const snapshot = await docRef
        .collection(config.name)
        .orderBy(field, 'desc')
        .limit(1)
        .get();
      if (!snapshot.empty) {
        const value = snapshot.docs[0].get(field);
        const date = convertToDate(value);
        if (date) {
          return date;
        }
      }
    } catch (error) {
      functions.logger.error('Failed to fetch latest timestamp', {
        gameId: docRef.id,
        collection: config.name,
        orderField: field,
        error,
      });
    }
  }
  return null;
}

function addTimestampIfPresent(list, value) {
  const date = convertToDate(value);
  if (date) {
    list.push(date);
  }
}

function convertToDate(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toDate === 'function') {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'string') {
    const date = new Date(value);
    if (!isNaN(date.getTime())) {
      return date;
    }
  }
  return null;
}

async function sendStatusNotificationBatch({
  gameId,
  tokens,
  tokenOwners,
  invalidTokens,
  notification,
  dataPayload,
  apnsCategory,
}) {
  const chunkSize = 500;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    try {
      functions.logger.info('Sending status notification batch', {
        gameId,
        batchSize: chunk.length,
        type: dataPayload?.type ?? 'unknown',
      });
      const response = await messaging.sendEachForMulticast({
        tokens: chunk,
        notification,
        data: dataPayload,
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'map_events',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
          },
          payload: {
            aps: {
              alert: notification,
              sound: 'default',
              category: apnsCategory,
            },
          },
        },
      });
      response.responses.forEach((res, idx) => {
        if (!res.success) {
          const code = res.error?.code || '';
          if (
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token'
          ) {
            invalidTokens.add(chunk[idx]);
          } else {
            functions.logger.error('Status notification delivery failed', {
              code,
              error: res.error,
              token: chunk[idx],
              gameId,
              type: dataPayload?.type ?? 'unknown',
            });
          }
        }
      });
    } catch (error) {
      functions.logger.error('Failed to send status notification batch', {
        error,
        gameId,
        type: dataPayload?.type ?? 'unknown',
      });
    }
  }
}

function toInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return 0;
  }
  return Math.trunc(parsed);
}

function formatDurationLabel(seconds) {
  const duration = Math.max(0, toInt(seconds));
  if (duration === 0) {
    return '';
  }
  const minutes = Math.floor(duration / 60);
  const remainingSeconds = duration % 60;
  if (minutes > 0 && remainingSeconds > 0) {
    return `${minutes}分${remainingSeconds}秒`;
  }
  if (minutes > 0) {
    return `${minutes}分`;
  }
  return `${remainingSeconds}秒`;
}

function getQuarterLabel(quarter) {
  switch (quarter) {
    case 1:
      return '第1フェーズ';
    case 2:
      return '第2フェーズ';
    case 3:
      return '最終フェーズ';
    default:
      return 'イベント';
  }
}
