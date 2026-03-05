import 'package:bapp_api_client/bapp_api_client.dart';

Future<void> main() async {
  // Authenticate with an API token
  final client = BappApiClient(token: 'your-api-key');

  // List entities with filters
  final items = await client.list('core.country', {'search': 'Romania'});
  print('Total: ${items.count}');
  for (final item in items) {
    print(item['name']);
  }

  // Get a single entity
  final country = await client.get('core.country', '1');
  print(country);

  // Create
  final created = await client.create('core.country', {'name': 'Test', 'code': 'TS'});
  print('Created: ${created['id']}');

  // Update
  await client.patch('core.country', created['id'].toString(), {'code': 'TX'});

  // Delete
  await client.delete('core.country', created['id'].toString());

  // Run a long-running task
  final taskResult = await client.runTaskAsync(
    'myapp.export_report',
    {'format': 'CSV'},
  );
  print('File URL: ${taskResult['file']}');
}
