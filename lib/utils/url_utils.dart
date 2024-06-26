// ignore: depend_on_referenced_packages
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:yolx/utils/log.dart';

String getURLFromQQDL(String url) {
  String base64Input = url.substring("qqdl://".length);
  String base64Output = utf8.decode(base64.decode(base64Input));
  return base64Output;
}

String getURLFromFlashget(String url) {
  String base64Input = url.substring("flashget://".length);
  String base64Output = utf8.decode(base64.decode(base64Input));
  if (base64Output.startsWith("[FLASHGET]")) {
    base64Output = base64Output.substring("[FLASHGET]".length);
  }

  if (base64Output.endsWith("[FLASHGET]")) {
    base64Output =
        base64Output.substring(0, base64Output.length - "[FLASHGET]".length);
  }
  return base64Output;
}

String getURLFromThunder(String url) {
  String base64Input = url.substring("thunder://".length);
  String base64Output = utf8.decode(base64.decode(base64Input));
  if (base64Output.startsWith("AA")) {
    base64Output = base64Output.substring("AA".length);
  }

  if (base64Output.endsWith("ZZ")) {
    base64Output = base64Output.substring(0, base64Output.length - "ZZ".length);
  }
  return base64Output;
}

Future<String> getFileTypeFromHeader(String url) async {
  try {
    var response = await http.head(Uri.parse(url));
    // 获取文件名
    var filename = response.headers['content-disposition'];
    if (filename != null) {
      filename = filename.split('filename=')[1];
      int dotPos = filename.lastIndexOf('.');
      if (dotPos != -1 && dotPos < filename.length - 1) {
        // extract and return the file extension
        return filename.substring(dotPos + 1);
      } else {
        return '';
      }
    }
  } catch (e) {
    Log.w(e);
  }
  return '';
}

Future<String> getFileTypeFromURL(String url) async {
  try {
    Uri uri = Uri.parse(url);
    String host = uri.host;

    if (host.isNotEmpty && url.endsWith(host)) {
      // handle ...example.com
      return '';
    }
  } catch (e) {
    return '';
  }
  int lastSlashPos = url.lastIndexOf('/');
  int startIndex = (lastSlashPos != -1) ? lastSlashPos + 1 : 0;
  int length = url.length;
  // find end index for ?
  int lastQMPos = url.lastIndexOf('?');
  if (lastQMPos == -1) {
    lastQMPos = length;
  }
  // find end index for #
  int lastHashPos = url.lastIndexOf('#');
  if (lastHashPos == -1) {
    lastHashPos = length;
  }
  // calculate the end index
  int endIndex = (lastQMPos < lastHashPos) ? lastQMPos : lastHashPos;
  String fileName = url.substring(startIndex, endIndex);

  int dotPos = fileName.lastIndexOf('.');
  if (dotPos != -1 && dotPos < fileName.length - 1) {
    // extract and return the file extension
    return fileName.substring(dotPos + 1);
  } else {
    return '';
  }
}

Future<String> getFileType(String url) async {
  String? fileType = await getFileTypeFromURL(url);
  if (fileType.isEmpty) {
    return getFileTypeFromHeader(url);
  } else {
    return fileType;
  }
}
