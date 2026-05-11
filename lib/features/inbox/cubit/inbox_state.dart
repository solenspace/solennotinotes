import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/received_share.dart';

/// Top-level state of the inbox screen.
class InboxState extends Equatable {
  const InboxState({
    this.entries = const <ReceivedShare>[],
    this.listener = InboxListenerStatus.off,
    this.failureDetail,
  });

  final List<ReceivedShare> entries;
  final InboxListenerStatus listener;

  /// Populated alongside [InboxListenerStatus.failed] for telemetry /
  /// debug surfaces. Null in every other phase.
  final String? failureDetail;

  bool get isEmpty => entries.isEmpty;

  InboxState copyWith({
    List<ReceivedShare>? entries,
    InboxListenerStatus? listener,
    String? failureDetail,
    bool clearFailureDetail = false,
  }) {
    return InboxState(
      entries: entries ?? this.entries,
      listener: listener ?? this.listener,
      failureDetail: clearFailureDetail ? null : (failureDetail ?? this.failureDetail),
    );
  }

  @override
  List<Object?> get props => [entries, listener, failureDetail];
}

/// Lifecycle of the opt-in receive transport. Drives the inbox
/// screen's "Discoverable" toggle row.
enum InboxListenerStatus { off, starting, on, failed }
