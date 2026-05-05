import 'dart:io';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';

import 'noti_identity_state.dart';

class NotiIdentityCubit extends Cubit<NotiIdentityState> {
  NotiIdentityCubit({required NotiIdentityRepository repository})
      : _repository = repository,
        super(const NotiIdentityState());

  final NotiIdentityRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: NotiIdentityStatus.loading, clearError: true));
    final identity = await _repository.getCurrent();
    emit(
      state.copyWith(
        status: NotiIdentityStatus.ready,
        identity: identity,
        clearError: true,
      ),
    );
  }

  Future<void> updateDisplayName(String name) async {
    final id = state.identity;
    if (id == null) return;
    final updated = id.copyWith(displayName: name);
    await _repository.save(updated);
    emit(state.copyWith(identity: updated));
  }

  Future<void> updatePhoto(File? photo) async {
    final id = state.identity;
    if (id == null) return;
    await _repository.setPhoto(id, photo);
    final updated = id.copyWith(
      profilePicture: photo,
      clearProfilePicture: photo == null,
    );
    emit(state.copyWith(identity: updated));
  }

  Future<void> removePhoto() async {
    final id = state.identity;
    if (id == null || id.profilePicture == null) return;
    await _repository.removePhoto(id);
    final updated = id.copyWith(clearProfilePicture: true);
    emit(state.copyWith(identity: updated));
  }

  Future<void> updatePalette(List<Color> swatches) async {
    final id = state.identity;
    if (id == null) return;
    final updated = id.copyWith(signaturePalette: List.of(swatches));
    await _repository.save(updated);
    emit(state.copyWith(identity: updated));
  }

  Future<void> updatePatternKey(String? key) async {
    final id = state.identity;
    if (id == null) return;
    final updated = id.copyWith(
      signaturePatternKey: key,
      clearSignaturePatternKey: key == null,
    );
    await _repository.save(updated);
    emit(state.copyWith(identity: updated));
  }

  Future<void> updateAccent(String? accent) async {
    final id = state.identity;
    if (id == null) return;
    final normalized = (accent == null || accent.isEmpty) ? null : accent;
    final updated = id.copyWith(
      signatureAccent: normalized,
      clearSignatureAccent: normalized == null,
    );
    await _repository.save(updated);
    emit(state.copyWith(identity: updated));
  }

  Future<void> updateTagline(String tagline) async {
    final id = state.identity;
    if (id == null) return;
    final updated = id.copyWith(signatureTagline: tagline);
    await _repository.save(updated);
    emit(state.copyWith(identity: updated));
  }
}
