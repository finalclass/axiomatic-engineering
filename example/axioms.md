# Todo App

A minimal task manager — add, complete, and delete tasks. Data persists in the browser via localStorage.

[Technology decisions](./technology.md)

## Dictionary
- **Task** — a single item on the todo list, with a text description and a completion status (done/not done).
- **Task list** — the ordered collection of all tasks.

## Labels
### [test]
Write unit tests before implementation (TDD). Tests run in the browser console via a self-contained test runner — no build tools, no npm.

## Axioms
### Data model
#### Task structure
[test]
A task is an object with three fields: `id` (unique string, generated via `crypto.randomUUID()`), `text` (non-empty string), `done` (boolean, default `false`).

#### Persistence
[test]
The task list is stored in `localStorage` under the key `todo-tasks` as a JSON array. Every mutation (add, toggle, delete) immediately saves the full list. On page load, the list is restored from localStorage. If the key is missing or the JSON is invalid, start with an empty list.

### User interactions
#### Add task
[test]
The user types a task description into an input field and submits (Enter key or button click). If the input is empty or whitespace-only, nothing happens. After adding, the input is cleared and focused.

#### Toggle task
[test]
Clicking a task's checkbox toggles its `done` status. Completed tasks are visually distinguished with a strikethrough and muted color.

#### Delete task
[test]
Each task has a delete button. Clicking it removes the task from the list immediately — no confirmation dialog.

#### Filter tasks
Buttons or tabs allow filtering the visible tasks: All, Active (not done), Completed (done). The current filter is visually highlighted. Changing the filter does not modify the data — only the display.

#### Task counter
The footer displays the number of active (not done) tasks in the format: `{n} items left`.

### Bulk actions
#### Clear completed
A "Clear completed" button removes all tasks with `done === true` from the list. The button is only visible when at least one completed task exists.
