// lib/youtube_util.dart

import 'dart:io';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class YoutubeUtil {
  final YoutubeExplode _yt;
  String? url;
  Video? video;
  bool videoLoaded = false;

  YoutubeUtil() : _yt = YoutubeExplode();

  /// Cierra la instancia de YoutubeExplode para liberar recursos
  void cleanUp() {
    _yt.close();
  }

  /// Solicita permisos de almacenamiento
  Future<bool> requestPermissions() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        print("Permiso de almacenamiento denegado.");
        return false;
      }
    }
    return true;
  }

  /// Carga la información del video dado su URL
  Future<bool> loadVideo(String url) async {
    try {
      this.url = url;
      this.video = await _yt.videos.get(url);
      videoLoaded = true;
      return true;
    } catch (e) {
      print("Error al cargar el video: $e");
      return false;
    }
  }

  /// Obtiene el autor del video
  String getVideoAuthor() {
    if (videoLoaded && video != null) {
      return video!.author;
    } else {
      return "No video loaded";
    }
  }

  /// Obtiene el título del video
  String getVideoTitle() {
    if (videoLoaded && video != null) {
      return video!.title;
    } else {
      return "No video loaded";
    }
  }

  /// Obtiene la URL de la miniatura del video
  String getVideoThumbnailUrl() {
    if (videoLoaded && video != null) {
      try {
        return video!.thumbnails.highResUrl;
      } catch (e) {
        return "";
      }
    } else {
      return "No video loaded";
    }
  }

  /// Obtiene la ruta de almacenamiento para guardar los archivos
  Future<String?> getSaveLocation() async {
    try {
      var downloadsDirectory = await getExternalStorageDirectory();
      return downloadsDirectory?.path;
    } catch (e) {
      print("Error al obtener el directorio de descargas: $e");
      return null;
    }
  }

  /// Descarga el audio del video y lo convierte a MP3
  Future<bool> downloadMP3(Function(String) onProgress) async {
    if (!videoLoaded || video == null) {
      print("No hay video cargado.");
      return false;
    }

    try {
      // Obtener el manifiesto del video y las pistas de audio
      var manifest = await _yt.videos.streams.getManifest(video!.id);
      var audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      if (audioStreamInfo == null) {
        print("No se encontró una pista de audio.");
        return false;
      }

      // Construir el directorio de descargas
      var downloadsDirectory = await getSaveLocation();
      if (downloadsDirectory == null) {
        print("No se pudo obtener el directorio de descargas.");
        return false;
      }

      // Sanitizar el título del video para usarlo como nombre de archivo
      var sanitizedTitle = video!.title
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
          .replaceAll(' ', '_');
      var fileExtension = audioStreamInfo.container.name; // e.g., 'webm', 'mp4'
      var inputFilePath = path.join(downloadsDirectory, '$sanitizedTitle.$fileExtension');

      print("Ruta del archivo de entrada: $inputFilePath");

      // Crear el archivo y abrir el stream para escribir
      var file = File(inputFilePath);
      var fileStream = file.openWrite();

      // Descargar y escribir el contenido del stream en el archivo con manejo de progreso
      var stream = _yt.videos.streams.get(audioStreamInfo);
      var totalBytes = audioStreamInfo.size.totalBytes;
      var receivedBytes = 0;

      await for (var data in stream) {
        receivedBytes += data.length;
        fileStream.add(data);
        double progress = receivedBytes / totalBytes;
        onProgress((progress * 100).toStringAsFixed(2));
      }

      // Cerrar el stream de escritura
      await fileStream.flush();
      await fileStream.close();

      print("Descarga completada. Iniciando conversión a MP3...");

      // Verificar si el archivo ya es .mp3
      if (inputFilePath.endsWith('.mp3')) {
        print('El archivo ya está en formato .mp3');
        return true;
      }

      // Definir la ruta del archivo de salida (.mp3)
      String outputFilePath;
      if (inputFilePath.endsWith('.mp4')) {
        outputFilePath = inputFilePath.replaceAll('.mp4', '.mp3');
      } else if (inputFilePath.endsWith('.webm')) {
        outputFilePath = inputFilePath.replaceAll('.webm', '.mp3');
      } else {
        print('Formato desconocido para convertir.');
        return false;
      }

      print("Ruta del archivo de salida: $outputFilePath");

      // Construir el comando FFmpeg especificando el codificador MP3
      String command =
          '-i "$inputFilePath" -vn -ar 44100 -ac 2 -b:a 192k -codec:a libmp3lame "$outputFilePath"';
      print("Comando FFmpeg: $command");

      // Ejecutar el comando FFmpeg
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print("Conversión a MP3 exitosa.");

        // Eliminar el archivo original si la conversión fue exitosa
        await file.delete();
        print("Archivo original eliminado: $inputFilePath");

        return true;
      } else {
        print("Error en la conversión. Código de retorno: $returnCode");

        // Obtener los logs de FFmpeg para más detalles
        final logs = await session.getAllLogs();
        for (var log in logs) {
          print(log.getMessage());
        }

        return false;
      }
    } catch (e, s) {
      print("Algo salió mal: $e");
      debugPrintStack(stackTrace: s);
      return false;
    }
  }
}
