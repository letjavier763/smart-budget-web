import 'package:share_plus/share_plus.dart';

void exportCsv({required String fileName, required String csvContent}) {
  Share.share(csvContent, subject: fileName);
}
