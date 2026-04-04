import '../models/app_models.dart';
import 'api_service.dart';

class SocketService {
  const SocketService(this.apiService);

  final ApiService apiService;

  Stream<List<AlertRecord>> watchAlerts({
    Duration interval = const Duration(seconds: 4),
    int limit = 8,
  }) async* {
    while (true) {
      yield await apiService.fetchRecentAlerts(limit: limit);
      await Future<void>.delayed(interval);
    }
  }
}
