import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_upload_policy.dart';

final class CourierProofPage extends StatefulWidget {
  const CourierProofPage({super.key, required this.title, required this.description});
  final String title;
  final String description;

  @override
  State<CourierProofPage> createState() => _CourierProofPageState();
}

final class _CourierProofPageState extends State<CourierProofPage> {
  XFile? _image;
  Future<Uint8List>? _preview;

  Future<void> _pickImage() async {
    final image = await ImageUploadPolicy.pick(ImageSource.camera);
    if (image != null && mounted) {
      setState(() {
        _image = image;
        _preview = image.readAsBytes();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(widget.description))),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(_image == null ? 'التقاط صورة الإثبات' : 'إعادة التقاط الصورة'),
        ),
        if (_preview != null) ...[
          const SizedBox(height: 12),
          FutureBuilder<Uint8List>(
            future: _preview,
            builder: (context, snapshot) => ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: snapshot.hasData
                    ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                    : const ColoredBox(color: Color(0xFFF0F2F4), child: Center(child: CircularProgressIndicator())),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('معاينة صورة الإثبات', textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _image == null ? null : () => Navigator.of(context).pop(_image),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('استخدام هذه الصورة'),
        ),
      ],
    ),
  );
}
