import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'local_database.dart';

/// Flushes only explicitly queued, non-financial mutations. It is safe to call
/// on launch and after a successful reconnect; each request retains the same
/// idempotency key it received when it was first queued.
final class OfflineOperationSync {
  const OfflineOperationSync(this._database, this._api);

  final LocalDatabase _database;
  final ApiClient _api;

  Future<int> flush() async {
    var completed = 0;
    for (final operation in await _database.pendingOperations()) {
      try {
        switch (operation.method) {
          case 'POST':
            await _api.post(
              operation.apiPath,
              body: operation.payload,
              idempotencyKey: operation.idempotencyKey,
            );
            break;
          case 'PATCH':
            await _api.patch(
              operation.apiPath,
              body: operation.payload,
              idempotencyKey: operation.idempotencyKey,
            );
            break;
          case 'DELETE':
            await _api.delete(
              operation.apiPath,
              idempotencyKey: operation.idempotencyKey,
            );
            break;
          default:
            await _database.recordOperationFailure(
              operation.id,
              StateError('Unsupported queued method ${operation.method}'),
            );
            continue;
        }
        await _database.completeOperation(operation.id);
        completed++;
      } on ApiException catch (error) {
        await _database.recordOperationFailure(operation.id, error);
        // Network failures mean following operations will fail too. Keep their
        // original order and wait for the next reconnect/launch.
        if (error.code == 'network_error' || error.code == 'timeout') break;
      } catch (error) {
        await _database.recordOperationFailure(operation.id, error);
        break;
      }
    }
    return completed;
  }
}
