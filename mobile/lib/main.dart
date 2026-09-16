import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app/app_controller.dart';
import 'app/tijarti_app.dart';
import 'core/media/image_upload_policy.dart';
import 'core/network/api_client.dart';
import 'core/storage/local_database.dart';
import 'core/storage/offline_operation_sync.dart';
import 'core/storage/secure_session.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/catalog/data/catalog_repository.dart';
import 'features/commerce/data/commerce_repository.dart';
import 'features/notifications/data/firebase_push_service.dart';
import 'features/notifications/data/notification_repository.dart';
import 'features/workspace/data/workspace_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseAvailable = false;
  try {
    await Firebase.initializeApp();
    firebaseAvailable = true;
  } catch (_) {
    // The app remains usable without FCM while the Firebase configuration files
    // have not been installed. In-app notifications continue to use the API.
  }

  await ImageUploadPolicy.load();

  final sessionStore = SecureSessionStore();
  final apiClient = ApiClient(sessionStore);
  final localDatabase = LocalDatabase.instance;
  final notificationRepository = NotificationRepository(apiClient);
  final controller = AppController(
    authRepository: AuthRepository(apiClient, sessionStore),
    catalogRepository: CatalogRepository(apiClient, localDatabase),
    commerceRepository: CommerceRepository(apiClient),
    notificationRepository: notificationRepository,
    pushService: FirebasePushService(
      notificationRepository,
      isFirebaseAvailable: firebaseAvailable,
    ),
    workspaceRepository: WorkspaceRepository(apiClient),
    offlineSync: OfflineOperationSync(localDatabase, apiClient),
    sessionStore: sessionStore,
  );

  runApp(TijartiApp(controller: controller));
}
