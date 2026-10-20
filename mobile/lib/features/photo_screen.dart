import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/permissions.dart';
import 'image_set_screen.dart';

class PhotoScreen extends StatelessWidget {
  const PhotoScreen({super.key});

  @override
  Widget build(BuildContext context) => ImageSetScreen(
        title: 'Print photos',
        kind: 'photo',
        addLabel: 'Choose photos',
        addIcon: Icons.photo_library,
        source: (ctx) async {
          final src = await showModalBottomSheet<ImageSource>(
            context: ctx,
            builder: (c) => SafeArea(child: Wrap(children: [
              ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
              ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Camera'), onTap: () => Navigator.pop(c, ImageSource.camera)),
            ])),
          );
          if (src == null || !ctx.mounted) return [];
          if (src == ImageSource.camera && !await ensureCamera(ctx)) return [];
          final picker = ImagePicker();
          final files = src == ImageSource.gallery ? await picker.pickMultiImage() : [?await picker.pickImage(source: ImageSource.camera)];
          return [for (final f in files) await f.readAsBytes()];
        },
      );
}
