---
name: wildix-update-message
description: Use when asked to edit, change, correct, update or delete a message the user sent earlier in an x-bees, collaboration 7 or x-hoppers chat. Triggers on requests like "edit my message", "fix the typo in that message", "update the text of my message", "delete my message", "remove what I just sent".
license: MIT
metadata:
  author: Vladimir Gorobets
allowed-tools: >-
  Bash, Glob, Skill
---

# Update or Delete a Message

Edits the text of a message **the user sent**, or deletes it, as the user whose token is used. A message of someone else is never touched: the script reads it first and stops when its author is not the user.

## Peer Skills

Before running, check that `wildix-auth` is installed:
```bash
Glob ~/.claude/skills/wildix-auth/SKILL.md
# If missing: npx skills add gorets/wildix-skills --s wildix-auth -y
```

See [`peers.yaml`](peers.yaml) for the full peer manifest.

## Flow

1. **Get the IdToken** of the user with the `wildix-auth` skill (`get-token.sh <email>`). Use the `IdToken`, not the AccessToken.
2. **Find the messageId** when you only know the message by its text or position: read the chat with `wildix-get-messages-in-chat`; the id is the `messageId` field. A channel may be given as an inbox URL, a full `channelId` or a raw id.
3. **Confirm with the user before a delete**: it cannot be undone. An edit overwrites the old text, so show the new text first when it is not exactly what the user dictated.
4. **Run the script:**

```bash
# edit the text
ID_TOKEN="$ID_TOKEN" bash <BASE_DIR>/scripts/update-message.sh edit   "<channelId>" "<messageId>" "<new text>"
# edit, the new text is Markdown
ID_TOKEN="$ID_TOKEN" bash <BASE_DIR>/scripts/update-message.sh edit   "<channelId>" "<messageId>" "<new text>" --markdown
# delete
ID_TOKEN="$ID_TOKEN" bash <BASE_DIR>/scripts/update-message.sh delete "<channelId>" "<messageId>"
```

On success the script prints the API answer, or `{"ok":true,...}` when it is empty. Exit codes: `1` for a bad argument or an HTTP error (status and body on stderr), `2` when the message is not the user's own (nothing was changed).

## API

| Operation | Endpoint |
|-----------|----------|
| Read (ownership check) | `GET /v2/conversations/channels/{channelId}/messages/{messageId}` |
| Edit | `PATCH /v2/conversations/channels/{channelId}/messages/{messageId}`, body `{"set": {"text": "…", "markdown": true}}` |
| Delete | `DELETE /v2/conversations/channels/{channelId}/messages/{messageId}` |

Base: `https://api.x-bees.com`, `Authorization: Bearer <IdToken>`. The routes come from the x-bees conversations SDK schema. The author is compared by e-mail: the `email` claim of the IdToken against `user.email` of the message.

## Common Mistakes

| Problem | Fix |
|---------|-----|
| Exit 2, "the message is not yours" | The messageId belongs to another author, or the token is of another account. Check with `wildix-get-messages-in-chat` |
| HTTP 401 | The IdToken expired (1 hour). Get a fresh one with `wildix-auth` |
| HTTP 403 or 404 on the read | Wrong channel for this messageId, or the user is not a member of the channel |
| Editing a bot's message | Messages sent with a bot token belong to the bot, not to the user: use the bot's token, not this skill |
| Text with quotes or newlines | Pass it as one quoted argument; the script builds the JSON itself |
| Worried that attachments vanish after an edit | They stay: `edit` is a `PATCH` that sets only the text (checked on a message with a file) |
