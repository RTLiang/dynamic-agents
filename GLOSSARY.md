# Dynamic Agents

Dynamic Agents helps people follow their coding-agent conversations and return to the ones that need attention.

## Language

**Coding session**:
An ongoing conversation with a coding agent. A session can contain many turns and remain open between them.
_Avoid_: Task, terminal window

**Turn**:
One round of a user's request and the agent's work before it returns control or waits for a decision.
_Avoid_: Project, entire task

**Running**:
A coding session whose agent is actively processing a turn.
_Avoid_: App open, session open

**Needs Input**:
A turn that is paused for a permission, answer or other user decision.
_Avoid_: Completed, idle

**Completed**:
A recent turn has ended and its result is ready to review. This does not establish that a whole project is finished or that every requested outcome succeeded.
_Avoid_: Project finished, permanent history

**Idle**:
An available coding session with no turn running and no current completion reminder. A new session, an interrupted session and a previously reviewed or expired completion can all be idle.
_Avoid_: Completed, closed session

**Completion reminder**:
A temporary indication that a turn ended recently enough to bring back to the user's attention.
_Avoid_: Completion timestamp reset on view

**Background work**:
Internal agent maintenance such as memory consolidation or automatic title generation, outside the user's coding conversation.
_Avoid_: User task
