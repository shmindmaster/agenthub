export async function cleanupCreatedSessions(createdSessionIds, deleteSession) {
  const errors = [];
  for (const sessionId of [...createdSessionIds].reverse()) {
    try {
      await deleteSession(sessionId);
    } catch (error) {
      errors.push(`${sessionId}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  createdSessionIds.length = 0;
  return errors;
}
