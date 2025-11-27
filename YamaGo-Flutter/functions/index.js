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

exports.onChatMessageCreated = functions
  .region('us-central1')
  .firestore.document('games/{gameId}/{collectionId}/{messageId}')
  .onCreate(async (snapshot, context) => {
    const { gameId, collectionId, messageId } = context.params;
    const channelMeta = CHAT_CHANNELS[collectionId];
    if (!channelMeta) {
      return null;
    }

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
      let playersQuery = db
        .collection('games')
        .doc(gameId)
        .collection('players');
      if (channelMeta.targetRole) {
        playersQuery = playersQuery.where('role', '==', channelMeta.targetRole);
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
        if (Array.isArray(fcmTokens)) {
          fcmTokens.forEach((token) => {
            if (typeof token === 'string' && token.length > 0) {
              tokens.push(token);
              if (!tokenOwners.has(token)) {
                tokenOwners.set(token, doc.id);
              }
            }
          });
        }
      });

      if (tokens.length === 0) {
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

      const invalidTokens = new Set();
      const chunkSize = 500;
      for (let i = 0; i < tokens.length; i += chunkSize) {
        const chunk = tokens.slice(i, i + chunkSize);
        try {
          functions.logger.info('Sending chat notification batch', {
            gameId,
            role: channelMeta.role,
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
                });
              }
            }
          });
        } catch (error) {
          functions.logger.error('Failed to send chat notifications', {
            error,
            gameId,
            role: channelMeta.role,
          });
        }
      }

      if (invalidTokens.size > 0) {
        await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
      }
    } catch (error) {
      functions.logger.error('Chat notification handling failed', {
        error,
        gameId,
        collectionId,
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
