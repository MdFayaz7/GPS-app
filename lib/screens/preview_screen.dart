import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            titleTextStyle: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            title: const Text('Photo'),
          ),
          body: Column(children: [
            Expanded(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.file(File(path))),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Color(0xFF34D399), size: 18),
                      SizedBox(width: 6),
                      Text('Saved to Gallery › GPS Camera',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                        ),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        onPressed: () => SharePlus.instance
                            .share(ShareParams(files: [XFile(path)])),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      );
}
