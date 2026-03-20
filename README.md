# BAPP Auto API Client — Dart

Official Dart client for the [BAPP Auto API](https://www.bapp.ro). Provides a
simple, consistent interface for authentication, entity CRUD, and task execution.

## Getting Started

### 1. Install

```yaml
dependencies:
  bapp_api_client: ^0.4.4
```

### 2. Create a client

```dart
import 'package:bapp_api_client/bapp_api_client.dart';

final client = BappApiClient(token: 'your-api-key');
```

### 3. Make your first request

```dart
// List with filters
final countries = await client.list('core.country', {'page': '1', 'search': 'Romania'});

// Get by ID
final country = await client.get('core.country', '42');

// Create
final created = await client.create('core.country', {'name': 'Romania', 'code': 'RO'});

// Patch (partial update)
await client.patch('core.country', '42', {'code': 'RO'});

// Delete
await client.delete('core.country', '42');
```

## Authentication

The client supports **Token** (API key) and **Bearer** (JWT / OAuth) authentication.
Token auth already includes a tenant binding, so you don't need to specify `tenant` separately.

```dart
// Static API token (tenant is included in the token)
final client = BappApiClient(token: 'your-api-key');

// Bearer (JWT / OAuth)
final client = BappApiClient(bearer: 'eyJhbG...', tenant: '1');
```

## Configuration

`tenant` and `app` can be changed at any time after construction:

```dart
client.tenant = '2';
client.app = 'wms';
```

## API Reference

### Client options

| Option | Description | Default |
|--------|-------------|---------|
| `token` | Static API token (`Token <value>`) — includes tenant | — |
| `bearer` | Bearer / JWT token | — |
| `host` | API base URL | `https://panel.bapp.ro/api` |
| `tenant` | Tenant ID (`x-tenant-id` header) | `None` |
| `app` | App slug (`x-app-slug` header) | `"account"` |

### Methods

| Method | Description |
|--------|-------------|
| `me()` | Get current user profile |
| `get_app(app_slug)` | Get app configuration by slug |
| `list(content_type, **filters)` | List entities (paginated) |
| `get(content_type, id)` | Get a single entity |
| `create(content_type, data)` | Create an entity |
| `update(content_type, id, data)` | Full update (PUT) |
| `patch(content_type, id, data)` | Partial update (PATCH) |
| `delete(content_type, id)` | Delete an entity |
| `list_introspect(content_type)` | Get list view metadata |
| `detail_introspect(content_type)` | Get detail view metadata |
| `get_document_views(record)` | Extract available views from a record |
| `get_document_url(record, output?, label?, variation?)` | Build a render/download URL |
| `get_document_content(record, output?, label?, variation?)` | Fetch document bytes (PDF, HTML, JPG) |
| `list_tasks()` | List available task codes |
| `detail_task(code)` | Get task configuration |
| `run_task(code, payload?)` | Execute a task |
| `run_task_async(code, payload?)` | Run a long-running task and poll until done |

### Paginated responses

`list()` returns the results directly as a list/array. Pagination metadata is
available as extra attributes:

- `count` — total number of items across all pages
- `next` — URL of the next page (or `null`)
- `previous` — URL of the previous page (or `null`)

## File Uploads

When data contains file objects, the client automatically switches from JSON to
`multipart/form-data`. Mix regular fields and files in the same call:

```dart
import 'dart:io';

// File objects are auto-detected — switches to multipart/form-data
await client.create('myapp.document', {
  'name': 'Report',
  'file': File('report.pdf'),
});

// Or use http.MultipartFile for more control
import 'package:http/http.dart' as http;
await client.create('myapp.document', {
  'name': 'Report',
  'file': await http.MultipartFile.fromPath('file', 'report.pdf'),
});
```

## Document Views

Records may include `public_view` and/or `view_token` fields with JWT tokens
for rendering documents (invoices, orders, reports, etc.) as HTML, PDF, or images.

The SDK normalises both formats and builds the correct URL automatically:

```dart
final order = await client.get('company_order.order', '42');

// Get a PDF download URL (auto-detects public_view vs view_token)
final url = client.getDocumentUrl(order, output: 'pdf');

// Pick a specific view by label
final url2 = client.getDocumentUrl(order, output: 'html', label: 'Comanda interna');

// Use a variation
final url3 = client.getDocumentUrl(order, output: 'pdf', variation: 'v4');

// Fetch the actual content as bytes
final pdfBytes = await client.getDocumentContent(order, output: 'pdf');
if (pdfBytes != null) File('order.pdf').writeAsBytesSync(pdfBytes);

// Enumerate all available views
final views = client.getDocumentViews(order);
for (final v in views) {
  print('${v['label']} ${v['type']} ${v['variations']}');
}
```

`get_document_views()` returns a list of normalised view entries with `label`,
`token`, `type` (`"public_view"` or `"view_token"`), `variations`, and
`default_variation`. Use it to enumerate available views (e.g. for a dropdown).

## Tasks

Tasks are server-side actions identified by a dotted code (e.g. `myapp.export_report`).

```dart
final tasks = await client.listTasks();

final cfg = await client.detailTask('myapp.export_report');

// Run without payload (GET)
final result = await client.runTask('myapp.export_report');

// Run with payload (POST)
final result = await client.runTask('myapp.export_report', {'format': 'csv'});
```

### Long-running tasks

Some tasks run asynchronously on the server. When triggered, they return an `id`
that can be polled via `bapp_framework.taskdata`. Use `run_task_async()` to
handle this automatically — it polls until `finished` is `true` and returns the
final task data (which includes a `file` URL when the task produces a download).

## License

MIT
