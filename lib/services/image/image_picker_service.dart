import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as syspaths;

class ImagePickerService {
  const ImagePickerService();

  static final ImagePicker _picker = ImagePicker();

  Future<File?> pickImage(ImageSource source, int quality) async {
    final imageFile = await _picker.pickImage(source: source, imageQuality: quality);
    if (imageFile == null) return null;
    final stored = File(imageFile.path);
    final appDir = await syspaths.getApplicationDocumentsDirectory();
    final fileName = path.basename(imageFile.path);
    return stored.copy('${appDir.path}/$fileName');
  }

  Future<void> removeImage(File image) async {
    await image.delete();
  }
}
