# Technology

## Stack
#### Vanilla JS only
No frameworks, no build tools, no npm. The app is a single `index.html` file with embedded CSS and JavaScript.

#### localStorage for persistence
No backend, no database. All data lives in the browser's localStorage.

#### Modern browser APIs
Use `crypto.randomUUID()` for ID generation. Target modern evergreen browsers — no polyfills.

## UI
#### Clean minimal design
Light background, centered container (max-width 500px), subtle shadows. No external fonts or icons — use Unicode characters for the delete button (×).

#### Responsive
The app works on mobile and desktop. The input field and task list scale to the container width.
