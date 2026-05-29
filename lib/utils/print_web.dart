// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void printTabPdf({required String title, required List<List<String>> headersAndData}) {
  final buffer = StringBuffer();
  buffer.write('<html><head><meta charset="UTF-8"><title>$title</title>');
  buffer.write('<style>');
  buffer.write('body { font-family: sans-serif; padding: 40px; color: #333; }');
  buffer.write('h1 { color: #003289; border-bottom: 2px solid #003289; padding-bottom: 10px; }');
  buffer.write('table { width: 100%; border-collapse: collapse; margin-top: 20px; }');
  buffer.write('th, td { border: 1px solid #ddd; padding: 12px 15px; text-align: left; }');
  buffer.write('th { background-color: #003289; color: white; }');
  buffer.write('tr:nth-child(even) { background-color: #f9f9f9; }');
  buffer.write('</style></head><body>');
  buffer.write('<h1>$title</h1>');
  
  final timeStr = DateTime.now().toLocal().toString().split('.')[0];
  buffer.write('<p>Reporte generado el: $timeStr</p>');
  buffer.write('<table><thead><tr>');

  // Headers
  for (final header in headersAndData.first) {
    buffer.write('<th>$header</th>');
  }
  buffer.write('</tr></thead><tbody>');

  // Rows
  for (var i = 1; i < headersAndData.length; i++) {
    final row = headersAndData[i];
    if (row.length == 2 && row[0] == '---' && row[1] == '---') {
      buffer.write('<tr><td colspan="2" style="border: none; padding: 20px 0; border-bottom: 2px dashed #003289;"></td></tr>');
      continue;
    }
    buffer.write('<tr>');
    for (final cell in row) {
      buffer.write('<td>$cell</td>');
    }
    buffer.write('</tr>');
  }

  buffer.write('</tbody></table>');
  buffer.write('<script>window.onload = function() { window.print(); }</script>');
  buffer.write('</body></html>');

  final blob = html.Blob([buffer.toString()], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}

void printHtmlReport({required String title, required String htmlContent}) {
  final blob = html.Blob([htmlContent], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}
