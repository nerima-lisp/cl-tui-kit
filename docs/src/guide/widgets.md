# Widgets and Models

## Widget protocol

The core widget protocol consists of render-widget and handle-widget-event.
A widget renders the current state and returns a normalized event result or a
semantic action. Side effects remain in the application.

Composite widgets can use widget-handle-child-action to interpret actions
returned by descendants. Accessibility metadata, enabled and focusable state,
semantic roles, help text, and cursor position are exposed through the widget
protocol where a widget supports them.

## Built-in widgets

The widget system includes text, box, divider, list, tree, text view, tabs,
menu, table, input, textarea, button, checkbox, radio, select, spinner,
progress, form, viewport, modal, notification center, status bar, and scroll
bar widgets.

The built-ins are intended as composable protocols rather than a mandatory
application architecture. An application can provide its own widget while
reusing geometry, layout, focus, text, and backend behavior.

## Lazy list and tree models

List and tree models use callbacks for counts, item or node lookup, stable
keys, labels, rendering, children, and expansion state. A widget requests the
visible range instead of materializing every item for every frame.

Selection can be represented by a stable key as well as a visible index. This
keeps selection meaningful when a lazy or changing data source is refreshed.

## Viewport-aware rendering

Text views, tables, menus, lists, and trees render against the available
viewport. Large or delayed data sources therefore do not need to be fully
converted into cells before the visible frame can be drawn.
