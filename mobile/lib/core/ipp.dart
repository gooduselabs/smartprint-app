import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:multicast_dns/multicast_dns.dart';

class IppPrinter {
  IppPrinter({required this.name, required this.host, required this.port, required this.path, this.tls = false});
  final String name, host, path;
  final int port;
  final bool tls;
  String get uri => '${tls ? 'ipps' : 'ipp'}://$host:$port/$path';
  String get httpUrl => '${tls ? 'https' : 'http'}://$host:$port/$path';
}

/// Minimal IPP/1.1 client: Bonjour (_ipp._tcp) discovery + Print-Job with a PDF.
class Ipp {
  static Future<List<IppPrinter>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    final client = MDnsClient();
    final found = <String, IppPrinter>{};
    await client.start();
    try {
      for (final svc in ['_ipp._tcp.local', '_ipps._tcp.local']) {
        await for (final ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(svc), timeout: timeout)) {
          await for (final srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName), timeout: timeout)) {
            var path = 'ipp/print';
            await for (final txt in client.lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName), timeout: timeout)) {
              final rp = RegExp(r'rp=([^\n]*)').firstMatch(txt.text)?.group(1);
              if (rp != null && rp.isNotEmpty) path = rp;
            }
            String host = srv.target;
            await for (final ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target), timeout: timeout)) {
              host = ip.address.address;
              break;
            }
            final name = ptr.domainName.split('._ipp').first.replaceAll(r'\032', ' ');
            found[name] = IppPrinter(name: name, host: host, port: srv.port, path: path, tls: svc.startsWith('_ipps'));
          }
        }
      }
    } finally {
      client.stop();
    }
    return found.values.toList();
  }

  static void _attr(BytesBuilder b, int tag, String name, String value) {
    final n = utf8.encode(name), v = utf8.encode(value);
    b.addByte(tag);
    b.add([n.length >> 8, n.length & 0xff, ...n, v.length >> 8, v.length & 0xff, ...v]);
  }

  static Uint8List buildPrintJob(String printerUri, Uint8List pdf, {String jobName = 'SmartPrint', String user = 'smartprint', int copies = 1, int requestId = 1}) {
    final b = BytesBuilder()
      ..add([0x01, 0x01, 0x00, 0x02]) // IPP 1.1, Print-Job
      ..add([requestId >> 24 & 0xff, requestId >> 16 & 0xff, requestId >> 8 & 0xff, requestId & 0xff])
      ..addByte(0x01); // operation-attributes
    _attr(b, 0x47, 'attributes-charset', 'utf-8');
    _attr(b, 0x48, 'attributes-natural-language', 'en');
    _attr(b, 0x45, 'printer-uri', printerUri);
    _attr(b, 0x42, 'requesting-user-name', user);
    _attr(b, 0x42, 'job-name', jobName);
    _attr(b, 0x49, 'document-format', 'application/pdf');
    if (copies > 1) {
      b.addByte(0x02); // job-attributes
      final n = utf8.encode('copies');
      b.add([0x21, 0, n.length, ...n, 0, 4, copies >> 24 & 0xff, copies >> 16 & 0xff, copies >> 8 & 0xff, copies & 0xff]);
    }
    b.addByte(0x03);
    b.add(pdf);
    return b.toBytes();
  }

  /// Returns the IPP status code (0x0000-0x00FF = success).
  static Future<int> printPdf(IppPrinter p, Uint8List pdf, {String jobName = 'SmartPrint', int copies = 1}) async {
    final res = await Dio().post<List<int>>(p.httpUrl,
        data: Stream.value(buildPrintJob(p.uri, pdf, jobName: jobName, copies: copies)),
        options: Options(headers: {'Content-Type': 'application/ipp'}, responseType: ResponseType.bytes));
    final body = res.data!;
    return (body[2] << 8) | body[3];
  }
}
